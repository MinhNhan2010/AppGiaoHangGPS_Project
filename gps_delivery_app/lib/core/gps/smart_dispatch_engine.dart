import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../../data/datasources/local/app_state_store.dart';
import '../../domain/entities/geo_point.dart';
import '../config/env_config.dart';
import '../utils/geo_math.dart';

class DispatchCandidateScore {
  final DriverApplicantRecord driver;
  final double distanceMeters;
  final int searchRadiusTierMeters;
  final double totalScore;

  const DispatchCandidateScore({
    required this.driver,
    required this.distanceMeters,
    required this.searchRadiusTierMeters,
    required this.totalScore,
  });
}

class GeocodedPlaceSuggestion {
  final String title;
  final String fullAddress;
  final GeoPoint location;

  const GeocodedPlaceSuggestion({
    required this.title,
    required this.fullAddress,
    required this.location,
  });
}

class OsrmRouteResult {
  final int distanceMeters;
  final int durationSeconds;
  final List<GeoPoint> polylinePoints;
  final bool isLiveOsrm;

  const OsrmRouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.polylinePoints,
    required this.isLiveOsrm,
  });
}

/// Động cơ Điều phối Tài xế Thông minh
/// & Bộ giải mã Địa chỉ Google Maps Geocoding / Nominatim + Dẫn đường Google Directions / OSRM Thực tế
class SmartDispatchEngine {
  const SmartDispatchEngine._();

  static const List<int> radiusTiersMeters = [3000, 5000, 8000];

  static const int _maxLiveCachedPlaces = 150;
  static final List<GeocodedPlaceSuggestion> _liveCachedPlaces = [];
  static List<GeoPoint>? _lastLiveOsrmPolyline;

  static void _cachePlaceSuggestion(GeocodedPlaceSuggestion suggestion) {
    _liveCachedPlaces.removeWhere(
      (p) =>
          p.fullAddress == suggestion.fullAddress ||
          (GeoMath.distanceMeters(p.location, suggestion.location) < 8.0 &&
              p.title == suggestion.title),
    );
    _liveCachedPlaces.insert(0, suggestion);
    if (_liveCachedPlaces.length > _maxLiveCachedPlaces) {
      _liveCachedPlaces.removeRange(
        _maxLiveCachedPlaces,
        _liveCachedPlaces.length,
      );
    }
  }

  static List<GeocodedPlaceSuggestion> get _allPlaces => _liveCachedPlaces;

  static String _foldVietnamese(String input) {
    const groups = <String, String>{
      'a': 'àáạảãâầấậẩẫăằắặẳẵ',
      'e': 'èéẹẻẽêềếệểễ',
      'i': 'ìíịỉĩ',
      'o': 'òóọỏõôồốộổỗơờớợởỡ',
      'u': 'ùúụủũưừứựửữ',
      'y': 'ỳýỵỷỹ',
      'd': 'đ',
    };
    var out = input.trim().toLowerCase();
    groups.forEach((ascii, chars) {
      for (var i = 0; i < chars.length; i++) {
        out = out.replaceAll(chars[i], ascii);
      }
    });
    return out;
  }

  /// Tìm kiếm gợi ý địa chỉ cục bộ + bộ nhớ đệm Google Maps / Nominatim (hỗ trợ cả có dấu & không dấu)
  static List<GeocodedPlaceSuggestion> searchAddressSuggestions(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return _allPlaces.take(4).toList();
    final foldedQuery = _foldVietnamese(normalized);
    final tokens = foldedQuery
        .split(RegExp(r'[\s,]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final matches = _allPlaces.where((p) {
      final rawHay = '${p.title} ${p.fullAddress}'.toLowerCase();
      if (rawHay.contains(normalized)) return true;
      final foldedHay = _foldVietnamese(rawHay);
      if (foldedHay.contains(foldedQuery)) return true;
      return tokens.isNotEmpty && tokens.every(foldedHay.contains);
    }).toList();
    if (matches.isNotEmpty) return matches;
    if (_liveCachedPlaces.isNotEmpty) return _liveCachedPlaces.take(5).toList();
    return const <GeocodedPlaceSuggestion>[];
  }

  /// Truy vấn trực tiếp Google Maps Geocoding API + OpenStreetMap Nominatim toàn quốc (`countrycodes=vn`)
  static Future<List<GeocodedPlaceSuggestion>> fetchLiveNominatimSuggestions(
    String query,
  ) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return searchAddressSuggestions(trimmed);

    final client = http.Client();
    try {
      if (EnvConfig.isGoogleMapsKeyConfigured) {
        final gUri = Uri.parse(EnvConfig.googleMapsGeocodeEndpoint).replace(
          queryParameters: {
            'address': trimmed,
            'components': 'country:VN',
            'language': 'vi',
            'key': EnvConfig.googleMapsApiKey,
          },
        );
        final gResp = await client
            .get(gUri)
            .timeout(const Duration(seconds: 4));
        if (gResp.statusCode == 200) {
          final gDecoded = jsonDecode(utf8.decode(gResp.bodyBytes));
          if (gDecoded is Map<String, dynamic> &&
              gDecoded['status'] == 'OK' &&
              gDecoded['results'] is List) {
            final gResults = <GeocodedPlaceSuggestion>[];
            for (final item in gDecoded['results'] as List) {
              if (item is Map<String, dynamic>) {
                final formatted = '${item['formatted_address'] ?? ''}'.trim();
                final geom = item['geometry'] as Map<String, dynamic>?;
                final loc = geom?['location'] as Map<String, dynamic>?;
                final lat = (loc?['lat'] as num?)?.toDouble();
                final lng = (loc?['lng'] as num?)?.toDouble();
                if (lat != null && lng != null && formatted.isNotEmpty) {
                  final parts = formatted.split(',');
                  final shortTitle = parts.take(2).join(',').trim();
                  final suggestion = GeocodedPlaceSuggestion(
                    title: shortTitle.isEmpty ? formatted : shortTitle,
                    fullAddress: formatted,
                    location: GeoPoint(latitude: lat, longitude: lng),
                  );
                  gResults.add(suggestion);
                  _cachePlaceSuggestion(suggestion);
                }
              }
            }
            if (gResults.isNotEmpty) return gResults;
          }
        }
      }

      final uri = Uri.parse(EnvConfig.nominatimSearchEndpoint).replace(
        queryParameters: {
          'format': 'json',
          'countrycodes': 'vn',
          'limit': '5',
          'q': trimmed,
        },
      );
      final resp = await client
          .get(
            uri,
            headers: kIsWeb
                ? const <String, String>{}
                : const <String, String>{
                    'User-Agent': 'GpsDeliveryApp/1.0 (Flutter Multiplatform)',
                  },
          )
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
        if (decoded is List && decoded.isNotEmpty) {
          final results = <GeocodedPlaceSuggestion>[];
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              final lat = double.tryParse('${item['lat']}');
              final lon = double.tryParse('${item['lon']}');
              final displayName = '${item['display_name'] ?? ''}'.trim();
              if (lat != null && lon != null && displayName.isNotEmpty) {
                final parts = displayName.split(',');
                final shortTitle = parts.take(2).join(',').trim();
                final suggestion = GeocodedPlaceSuggestion(
                  title: shortTitle.isEmpty ? displayName : shortTitle,
                  fullAddress: displayName,
                  location: GeoPoint(latitude: lat, longitude: lon),
                );
                results.add(suggestion);
                _cachePlaceSuggestion(suggestion);
              }
            }
          }
          if (results.isNotEmpty) return results;
        }
      }
    } catch (_) {
      // Tự động fallback về danh mục nội bộ khi không có kết nối mạng hoặc trong môi trường test
    } finally {
      client.close();
    }
    return searchAddressSuggestions(trimmed);
  }

  /// Giải mã chuỗi Encoded Polyline chuẩn Google Maps Directions API (5-bit chunk / ZigZag)
  static List<GeoPoint> decodeGoogleEncodedPolyline(String encoded) {
    final points = <GeoPoint>[];
    var index = 0;
    final len = encoded.length;
    var lat = 0;
    var lng = 0;

    while (index < len) {
      var b = 0;
      var shift = 0;
      var result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < len);
      if (b >= 0x20) break;
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      if (index >= len) break;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < len);
      if (b >= 0x20) break;
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(GeoPoint(latitude: lat / 1e5, longitude: lng / 1e5));
    }
    return points;
  }

  /// Truy vấn trực tiếp Google Maps Directions API + OSRM (`router.project-osrm.org`)
  static Future<OsrmRouteResult> fetchLiveOsrmRoute(
    GeoPoint start,
    GeoPoint end,
  ) async {
    final client = http.Client();
    try {
      if (EnvConfig.isGoogleMapsKeyConfigured) {
        final gUri = Uri.parse(EnvConfig.googleMapsDirectionsEndpoint).replace(
          queryParameters: {
            'origin': '${start.latitude},${start.longitude}',
            'destination': '${end.latitude},${end.longitude}',
            'mode': 'driving',
            'language': 'vi',
            'key': EnvConfig.googleMapsApiKey,
          },
        );
        final gResp = await client
            .get(gUri)
            .timeout(const Duration(seconds: 4));
        if (gResp.statusCode == 200) {
          final gDecoded = jsonDecode(utf8.decode(gResp.bodyBytes));
          if (gDecoded is Map<String, dynamic> &&
              gDecoded['status'] == 'OK' &&
              gDecoded['routes'] is List &&
              (gDecoded['routes'] as List).isNotEmpty) {
            final rawFirstRoute = (gDecoded['routes'] as List).first;
            if (rawFirstRoute is Map) {
              final route = Map<String, dynamic>.from(rawFirstRoute);
              final legs = route['legs'];
              final firstLeg =
                  (legs is List && legs.isNotEmpty && legs.first is Map)
                  ? Map<String, dynamic>.from(legs.first as Map)
                  : null;
              final distMap = firstLeg?['distance'];
              final durMap = firstLeg?['duration'];
              final distVal = distMap is Map ? distMap['value'] : null;
              final durVal = durMap is Map ? durMap['value'] : null;
              final dist = ((distVal is num ? distVal.round() : 1200)).clamp(
                50,
                3000000,
              );
              final dur = ((durVal is num ? durVal.round() : 300)).clamp(
                30,
                259200,
              );
              final overview = route['overview_polyline'];
              final encodedPoints = overview is Map
                  ? '${overview['points'] ?? ''}'.trim()
                  : '';
              if (encodedPoints.isNotEmpty) {
                final pts = decodeGoogleEncodedPolyline(encodedPoints);
                if (pts.length >= 2) {
                  _lastLiveOsrmPolyline = pts;
                  return OsrmRouteResult(
                    distanceMeters: dist,
                    durationSeconds: dur,
                    polylinePoints: pts,
                    isLiveOsrm: true,
                  );
                }
              }
            }
          }
        }
      }

      final url =
          '${EnvConfig.osrmRouteEndpoint}/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson';
      final resp = await client
          .get(
            Uri.parse(url),
            headers: kIsWeb
                ? const <String, String>{}
                : const <String, String>{
                    'User-Agent': 'GpsDeliveryApp/1.0 (Flutter Multiplatform)',
                  },
          )
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          final routes = decoded['routes'];
          if (routes is List && routes.isNotEmpty && routes.first is Map) {
            final route = Map<String, dynamic>.from(routes.first as Map);
            final rawDist = route['distance'];
            final rawDur = route['duration'];
            final dist = ((rawDist is num ? rawDist.round() : 1200)).clamp(
              50,
              3000000,
            );
            final dur = ((rawDur is num ? rawDur.round() : 300)).clamp(
              30,
              259200,
            );
            final geom = route['geometry'];
            final coords = geom is Map ? geom['coordinates'] : null;
            final pts = <GeoPoint>[];
            if (coords is List) {
              for (final c in coords) {
                if (c is List && c.length >= 2 && c[0] is num && c[1] is num) {
                  final lon = (c[0] as num).toDouble();
                  final lat = (c[1] as num).toDouble();
                  pts.add(GeoPoint(latitude: lat, longitude: lon));
                }
              }
            }
            if (pts.length >= 2) {
              _lastLiveOsrmPolyline = pts;
              return OsrmRouteResult(
                distanceMeters: dist,
                durationSeconds: dur,
                polylinePoints: pts,
                isLiveOsrm: true,
              );
            }
          }
        }
      }
    } catch (_) {
      // Fallback sang nội suy Haversine khi offline
    } finally {
      client.close();
    }

    final rawMeters = GeoMath.distanceMeters(start, end);
    final fallbackDist = rawMeters < 1.0
        ? 0
        : (rawMeters * 1.28).round().clamp(50, 3000000);
    final fallbackDur = ((fallbackDist / 1000.0) * 185).round();
    final fallbackPts = generateRoutePolyline(start, end);
    return OsrmRouteResult(
      distanceMeters: fallbackDist,
      durationSeconds: fallbackDur,
      polylinePoints: fallbackPts,
      isLiveOsrm: false,
    );
  }

  /// Giải mã ngược tọa độ GPS (Reverse Geocoding) sang địa chỉ đường phố thực tế qua Google Maps / OpenStreetMap Nominatim
  static Future<String> reverseGeocodeCoordinate(GeoPoint point) async {
    final client = http.Client();
    try {
      if (EnvConfig.isGoogleMapsKeyConfigured) {
        final gUri = Uri.parse(EnvConfig.googleMapsGeocodeEndpoint).replace(
          queryParameters: {
            'latlng': '${point.latitude},${point.longitude}',
            'language': 'vi',
            'key': EnvConfig.googleMapsApiKey,
          },
        );
        final gResp = await client
            .get(gUri)
            .timeout(const Duration(seconds: 4));
        if (gResp.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(gResp.bodyBytes));
          if (decoded is Map<String, dynamic> &&
              decoded['status'] == 'OK' &&
              decoded['results'] is List &&
              (decoded['results'] as List).isNotEmpty) {
            final first = (decoded['results'] as List).first;
            if (first is Map<String, dynamic>) {
              final formatted = '${first['formatted_address'] ?? ''}'.trim();
              if (formatted.isNotEmpty) {
                final parts = formatted.split(',');
                final shortTitle = parts.take(2).join(',').trim();
                _cachePlaceSuggestion(
                  GeocodedPlaceSuggestion(
                    title: shortTitle.isEmpty ? formatted : shortTitle,
                    fullAddress: formatted,
                    location: point,
                  ),
                );
                return formatted;
              }
            }
          }
        }
      }

      final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse')
          .replace(
            queryParameters: {
              'format': 'jsonv2',
              'lat': point.latitude.toStringAsFixed(6),
              'lon': point.longitude.toStringAsFixed(6),
              'accept-language': 'vi',
            },
          );
      final resp = await client
          .get(
            uri,
            headers: kIsWeb
                ? const <String, String>{}
                : const <String, String>{
                    'User-Agent': 'GpsDeliveryApp/1.0 (Flutter Multiplatform)',
                  },
          )
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          final displayName = '${decoded['display_name'] ?? ''}'.trim();
          if (displayName.isNotEmpty) {
            final parts = displayName.split(',');
            final shortTitle = parts.take(2).join(',').trim();
            _cachePlaceSuggestion(
              GeocodedPlaceSuggestion(
                title: shortTitle.isEmpty ? displayName : shortTitle,
                fullAddress: displayName,
                location: point,
              ),
            );
            return displayName;
          }
        }
      }
    } catch (_) {
      // Fallback sang địa điểm đã xác thực gần nhất khi mất kết nối mạng hoặc trong môi trường test
    } finally {
      client.close();
    }

    GeocodedPlaceSuggestion? nearest;
    var bestMeters = double.infinity;
    for (final p in _allPlaces) {
      final d = GeoMath.distanceMeters(point, p.location);
      if (d < bestMeters) {
        bestMeters = d;
        nearest = p;
      }
    }
    if (nearest != null && bestMeters <= 900) {
      return nearest.fullAddress;
    }
    return 'Tọa độ (${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)})';
  }

  /// Giải mã địa chỉ sang tọa độ GPS thực tế
  static GeoPoint resolveAddressToCoordinate(
    String address, {
    required GeoPoint fallback,
  }) {
    return tryResolveAddressToCoordinate(address) ?? fallback;
  }

  static GeoPoint? tryResolveAddressToCoordinate(String address) {
    final normalized = address.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final folded = _foldVietnamese(normalized);
    for (final p in _allPlaces) {
      final titleLow = p.title.toLowerCase();
      final fullLow = p.fullAddress.toLowerCase();
      if (normalized.contains(titleLow) ||
          fullLow == normalized ||
          folded.contains(_foldVietnamese(titleLow)) ||
          _foldVietnamese(fullLow) == folded) {
        return p.location;
      }
    }
    return null;
  }

  /// Xếp hạng ứng viên tài xế theo bán kính mở rộng (3km -> 5km -> 8km)
  /// Công thức: Score = 0.5 * DistanceScore + 0.3 * RatingScore + 0.2 * AcceptanceRate
  static List<DispatchCandidateScore> rankDriversForPickup({
    required GeoPoint pickupLocation,
    required List<DriverApplicantRecord> drivers,
    Set<String> excludedDriverIds = const {},
  }) {
    final eligible = drivers.where((d) {
      return d.isOnline &&
          d.approvalStatus == 'Đã duyệt' &&
          d.walletBalance >= 200000 &&
          !excludedDriverIds.contains(d.id);
    }).toList();

    for (final radiusTier in radiusTiersMeters) {
      final inTier = <DispatchCandidateScore>[];
      for (final d in eligible) {
        final dist = GeoMath.distanceMeters(pickupLocation, d.location);
        if (dist <= radiusTier) {
          final distScore = (1.0 - (dist / radiusTier)).clamp(0.0, 1.0);
          final ratingScore = (d.rating / 5.0).clamp(0.0, 1.0);
          final acceptanceRate =
              (d.acceptanceRate > 1.0
                      ? d.acceptanceRate / 100.0
                      : d.acceptanceRate)
                  .clamp(0.0, 1.0);
          final weighted =
              0.5 * distScore + 0.3 * ratingScore + 0.2 * acceptanceRate;

          inTier.add(
            DispatchCandidateScore(
              driver: d,
              distanceMeters: dist,
              searchRadiusTierMeters: radiusTier,
              totalScore: weighted,
            ),
          );
        }
      }
      if (inTier.isNotEmpty) {
        inTier.sort((a, b) => b.totalScore.compareTo(a.totalScore));
        return inTier;
      }
    }

    // Fallback khi tài xế ở xa hơn 8km (vẫn xếp hạng theo tổng điểm)
    final allRanked = eligible.map((d) {
      final dist = GeoMath.distanceMeters(pickupLocation, d.location);
      final distScore = (1.0 / (1.0 + dist / 5000.0)).clamp(0.0, 1.0);
      final ratingScore = (d.rating / 5.0).clamp(0.0, 1.0);
      final acceptanceRate =
          (d.acceptanceRate > 1.0 ? d.acceptanceRate / 100.0 : d.acceptanceRate)
              .clamp(0.0, 1.0);
      final score = 0.5 * distScore + 0.3 * ratingScore + 0.2 * acceptanceRate;
      return DispatchCandidateScore(
        driver: d,
        distanceMeters: dist,
        searchRadiusTierMeters: 8000,
        totalScore: score,
      );
    }).toList()..sort((a, b) => b.totalScore.compareTo(a.totalScore));

    return allRanked;
  }

  static List<GeoPoint>? get lastLiveOsrmPolyline => _lastLiveOsrmPolyline;

  /// Nội suy danh sách điểm tọa độ Polyline giữa điểm lấy và điểm giao
  static List<GeoPoint> generateRoutePolyline(
    GeoPoint start,
    GeoPoint end, {
    int segments = 10,
  }) {
    final safeSegments = math.max(1, segments);
    final dLat = end.latitude - start.latitude;
    final dLng = end.longitude - start.longitude;
    final chord = math.sqrt(dLat * dLat + dLng * dLng);
    final maxBend = math.min(0.0035, chord * 0.18);
    final points = <GeoPoint>[];
    for (var i = 0; i <= safeSegments; i++) {
      final t = i / safeSegments;
      final bend = (t * (1.0 - t)) * maxBend;
      points.add(
        GeoPoint(
          latitude: start.latitude + dLat * t + bend,
          longitude: start.longitude + dLng * t - bend,
        ),
      );
    }
    return points;
  }

  /// Kiểm tra tài xế đã vào vùng bán kính 100m điểm giao hàng chưa
  static bool isWithinDropoffGeofence({
    required GeoPoint driverLocation,
    required GeoPoint dropoffLocation,
  }) {
    final dist = GeoMath.distanceMeters(driverLocation, dropoffLocation);
    return dist <= EnvConfig.arrivalGeofenceRadiusMeters;
  }
}
