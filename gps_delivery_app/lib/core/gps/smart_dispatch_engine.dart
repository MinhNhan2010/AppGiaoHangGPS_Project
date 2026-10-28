import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../../data/datasources/local/app_state_store.dart';
import '../../domain/entities/geo_point.dart';
import '../../domain/enums/order_status.dart';
import '../../domain/enums/service_type.dart';
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

class OptimizedMultiStopRouteResult {
  final List<Map<String, dynamic>> optimizedStops;
  final int originalDistanceMeters;
  final int optimizedDistanceMeters;
  final int savedDistanceMeters;
  final int estimatedDurationSeconds;
  final List<GeoPoint> routePolyline;

  const OptimizedMultiStopRouteResult({
    required this.optimizedStops,
    required this.originalDistanceMeters,
    required this.optimizedDistanceMeters,
    required this.savedDistanceMeters,
    required this.estimatedDurationSeconds,
    required this.routePolyline,
  });
}

class CoDirectionalBatchMatch {
  final ActiveOrderRecord partnerOrder;
  final double pickupDistanceMeters;
  final double bearingDifferenceDegrees;
  final double combinedWeightKg;
  final int estimatedCombinedDurationSeconds;

  const CoDirectionalBatchMatch({
    required this.partnerOrder,
    required this.pickupDistanceMeters,
    required this.bearingDifferenceDegrees,
    required this.combinedWeightKg,
    required this.estimatedCombinedDurationSeconds,
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

  static const List<GeocodedPlaceSuggestion> knownPlaces = [
    GeocodedPlaceSuggestion(
      title: '145 Phố Huế, Hai Bà Trưng',
      fullAddress: '145 Phố Huế, Hai Bà Trưng, Hà Nội',
      location: GeoPoint(latitude: 21.0145, longitude: 105.8512),
    ),
    GeocodedPlaceSuggestion(
      title: '15 Ngõ 100 Lê Trọng Tấn',
      fullAddress:
          'Số 15, Ngõ 100, Đường Lê Trọng Tấn, Quận Thanh Xuân, Hà Nội',
      location: GeoPoint(latitude: 20.9951, longitude: 105.8286),
    ),
    GeocodedPlaceSuggestion(
      title: '123 Đường Lê Lợi',
      fullAddress: '123 Đường Lê Lợi, Phường Bến Nghé, Quận 1, TP. HCM',
      location: GeoPoint(latitude: 10.7769, longitude: 106.6953),
    ),
    GeocodedPlaceSuggestion(
      title: '123 Lê Lợi',
      fullAddress: '123 Lê Lợi, Phường Bến Thành, Quận 1, TP. HCM',
      location: GeoPoint(latitude: 10.7731, longitude: 106.6983),
    ),
    GeocodedPlaceSuggestion(
      title: '456 Đường Nguyễn Đình Chiểu',
      fullAddress: '456 Đường Nguyễn Đình Chiểu, Phường 6, Quận 3, TP. HCM',
      location: GeoPoint(latitude: 10.7752, longitude: 106.6869),
    ),
    GeocodedPlaceSuggestion(
      title: 'Bitexco Financial Tower',
      fullAddress:
          'Bitexco Financial Tower, 45 Lê Lợi, P. Bến Nghé, Q.1, TP. HCM',
      location: GeoPoint(latitude: 10.7716, longitude: 106.7044),
    ),
    GeocodedPlaceSuggestion(
      title: 'Landmark 81',
      fullAddress: 'Landmark 81, Quận Bình Thạnh, TP.HCM',
      location: GeoPoint(latitude: 10.7950, longitude: 106.7218),
    ),
    GeocodedPlaceSuggestion(
      title: '188 Phan Xích Long',
      fullAddress: '188 Phan Xích Long, Quận Phú Nhuận, TP.HCM',
      location: GeoPoint(latitude: 10.7972, longitude: 106.6882),
    ),
    GeocodedPlaceSuggestion(
      title: 'Cảng Tân Thuận',
      fullAddress: 'Cảng Tân Thuận, Khu Chế Xuất Q.7',
      location: GeoPoint(latitude: 10.7425, longitude: 106.7250),
    ),
    GeocodedPlaceSuggestion(
      title: 'Chợ Bến Thành',
      fullAddress: 'Chợ Bến Thành, Quận 1, TP. HCM',
      location: GeoPoint(latitude: 10.7725, longitude: 106.6980),
    ),
    GeocodedPlaceSuggestion(
      title: 'Dinh Độc Lập',
      fullAddress: 'Dinh Độc Lập, Quận 1, TP. HCM',
      location: GeoPoint(latitude: 10.7770, longitude: 106.6953),
    ),
    GeocodedPlaceSuggestion(
      title: '456 Nguyễn Huệ, Phú Nhuận',
      fullAddress: '456 Đường Nguyễn Huệ, Quận Phú Nhuận, TP. HCM',
      location: GeoPoint(latitude: 10.7992, longitude: 106.6805),
    ),
    GeocodedPlaceSuggestion(
      title: '77 Võ Văn Tần, Quận 3',
      fullAddress: '77 Võ Văn Tần, Phường 6, Quận 3, TP. HCM',
      location: GeoPoint(latitude: 10.7761, longitude: 106.6894),
    ),
    GeocodedPlaceSuggestion(
      title: '789 Điện Biên Phủ, Bình Thạnh',
      fullAddress: '789 Điện Biên Phủ, Quận Bình Thạnh, TP. HCM',
      location: GeoPoint(latitude: 10.7985, longitude: 106.7152),
    ),
    GeocodedPlaceSuggestion(
      title: '72 Lê Thánh Tôn',
      fullAddress: '72 Lê Thánh Tôn, Phường Bến Nghé, Quận 1, TP. HCM',
      location: GeoPoint(latitude: 10.7780, longitude: 106.7018),
    ),
    GeocodedPlaceSuggestion(
      title: '120 Nguyễn Trãi',
      fullAddress: '120 Nguyễn Trãi, Phường 3, Quận 5, TP. HCM',
      location: GeoPoint(latitude: 10.7582, longitude: 106.6785),
    ),
    GeocodedPlaceSuggestion(
      title: '45 Lê Duẩn',
      fullAddress: '45 Lê Duẩn, Phường Bến Nghé, Quận 1, TP. HCM',
      location: GeoPoint(latitude: 10.7815, longitude: 106.7005),
    ),
    GeocodedPlaceSuggestion(
      title: 'Phở Hòa Pasteur',
      fullAddress: '260C Pasteur, Phường Võ Thị Sáu, Quận 3, TP. HCM',
      location: GeoPoint(latitude: 10.7868, longitude: 106.6881),
    ),
    GeocodedPlaceSuggestion(
      title: 'Cơm Tấm Phúc Lộc Thọ',
      fullAddress:
          '236 Nguyễn Thị Minh Khai, Phường Võ Thị Sáu, Quận 3, TP. HCM',
      location: GeoPoint(latitude: 10.7778, longitude: 106.6898),
    ),
    GeocodedPlaceSuggestion(
      title: 'Bánh Mì Huỳnh Hoa',
      fullAddress: '26 Lê Thị Riêng, Phường Bến Thành, Quận 1, TP. HCM',
      location: GeoPoint(latitude: 10.7712, longitude: 106.6913),
    ),
    GeocodedPlaceSuggestion(
      title: 'Phê La - Hồ Tùng Mậu',
      fullAddress: '115 Hồ Tùng Mậu, Phường Bến Nghé, Quận 1, TP. HCM',
      location: GeoPoint(latitude: 10.7730, longitude: 106.7032),
    ),
    GeocodedPlaceSuggestion(
      title: 'Poke Saigon - Lý Tự Trọng',
      fullAddress: '42 Lý Tự Trọng, Phường Bến Nghé, Quận 1, TP. HCM',
      location: GeoPoint(latitude: 10.7782, longitude: 106.7014),
    ),
    GeocodedPlaceSuggestion(
      title: 'Cháo Sườn & Dimsum Đêm Chợ Cũ',
      fullAddress: '84 Tôn Thất Đạm, Phường Bến Nghé, Quận 1, TP. HCM',
      location: GeoPoint(latitude: 10.7718, longitude: 106.7038),
    ),
    GeocodedPlaceSuggestion(
      title: 'Bún Chả Hương Liên',
      fullAddress: '24 Lê Văn Hưu, Quận Hai Bà Trưng, Hà Nội',
      location: GeoPoint(latitude: 21.0181, longitude: 105.8535),
    ),
    GeocodedPlaceSuggestion(
      title: 'Cà Phê Giảng Phố Cổ',
      fullAddress: '39 Nguyễn Hữu Huân, Quận Hoàn Kiếm, Hà Nội',
      location: GeoPoint(latitude: 21.0338, longitude: 105.8546),
    ),
  ];

  static List<GeocodedPlaceSuggestion> get _allPlaces => [
    ..._liveCachedPlaces,
    ...knownPlaces,
  ];

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

  /// Quãng đường thực tế tối đa trên 100% pin xe máy điện giao hàng (VinFast Evo200/Feliz S ~90km đô thị)
  static const double evFullChargeRangeMeters = 90000.0;

  /// Quãng đường khả dụng ước tính theo % dung lượng pin hiện tại (SoC)
  static double estimateEvUsableRangeMeters(int batteryPercent) {
    return (batteryPercent.clamp(0, 100) / 100.0) * evFullChargeRangeMeters;
  }

  /// Kiểm tra an toàn dung lượng pin xe điện trước khi điều phối:
  /// Đảm bảo pin >= 15% và quãng đường khả dụng >= 1.3 * (quãng đường đón + lộ trình đơn)
  static bool hasSufficientEvBatteryForOrder({
    required DriverApplicantRecord driver,
    required GeoPoint pickupLocation,
    required int orderRouteMeters,
  }) {
    if (!driver.isElectricVehicle) return true;
    if (driver.batteryPercent < 15) return false;
    final distToPickupRoad =
        GeoMath.distanceMeters(driver.location, pickupLocation) * 1.28;
    final requiredWithReserve =
        (distToPickupRoad + math.max(0, orderRouteMeters)) * 1.30;
    return estimateEvUsableRangeMeters(driver.batteryPercent) >=
        requiredWithReserve;
  }

  /// Hạn mức ký quỹ tối thiểu theo giá trị khai báo bảo hiểm / COD của đơn hàng
  static double requiredMinWalletForOrder({
    double codAmount = 0.0,
    double declaredValueVnd = 0.0,
  }) {
    if (declaredValueVnd >= 3000000 || codAmount >= 2000000) {
      return math.max(500000.0, (codAmount * 0.25).clamp(500000.0, 2000000.0));
    }
    return 200000.0;
  }

  /// Kiểm tra tài xế đủ điều kiện nhận đơn giá trị cao / xe điện / xe tải
  static bool isDriverEligibleForOrder({
    required DriverApplicantRecord driver,
    required GeoPoint pickupLocation,
    DeliveryServiceType? serviceType,
    bool requireElectricVehicle = false,
    int totalOrderRouteMeters = 0,
    double declaredValueVnd = 0.0,
    double codAmount = 0.0,
  }) {
    if (requireElectricVehicle && !driver.isElectricVehicle) {
      return false;
    }
    if (serviceType != null) {
      final isTruckDriver = driver.vehicleType.toLowerCase().contains('tải') ||
          driver.vehicleType.toLowerCase().contains('van') ||
          driver.vehicleType.toUpperCase().contains('TRUCK');
      if (serviceType == DeliveryServiceType.truck && !isTruckDriver) {
        return false;
      }
      if (serviceType != DeliveryServiceType.truck && isTruckDriver) {
        return false;
      }
    }
    if (!hasSufficientEvBatteryForOrder(
      driver: driver,
      pickupLocation: pickupLocation,
      orderRouteMeters: totalOrderRouteMeters,
    )) {
      return false;
    }
    final minWallet = requiredMinWalletForOrder(
      codAmount: codAmount,
      declaredValueVnd: declaredValueVnd,
    );
    if (driver.walletBalance < minWallet) {
      return false;
    }
    final isHighValue = declaredValueVnd >= 3000000 || codAmount >= 2000000;
    if (isHighValue && driver.rating > 0 && driver.rating < 4.5) {
      return false;
    }
    return true;
  }

  /// Xếp hạng ứng viên tài xế theo bán kính mở rộng (3km -> 5km -> 8km)
  /// Công thức: Score = 0.5 * DistanceScore + 0.3 * RatingScore + 0.2 * AcceptanceRate (+ EcoBonus)
  static List<DispatchCandidateScore> rankDriversForPickup({
    required GeoPoint pickupLocation,
    required List<DriverApplicantRecord> drivers,
    Set<String> excludedDriverIds = const {},
    bool requireElectricVehicle = false,
    bool preferElectricVehicle = false,
    int totalOrderRouteMeters = 0,
    double declaredValueVnd = 0.0,
    double codAmount = 0.0,
    DeliveryServiceType? serviceType,
  }) {
    final eligible = drivers.where((d) {
      if (!d.isOnline ||
          d.approvalStatus != 'Đã duyệt' ||
          excludedDriverIds.contains(d.id)) {
        return false;
      }
      return isDriverEligibleForOrder(
        driver: d,
        pickupLocation: pickupLocation,
        serviceType: serviceType,
        requireElectricVehicle: requireElectricVehicle,
        totalOrderRouteMeters: totalOrderRouteMeters,
        declaredValueVnd: declaredValueVnd,
        codAmount: codAmount,
      );
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
          final ecoBonus =
              (preferElectricVehicle && d.isElectricVehicle) ? 0.08 : 0.0;
          final weighted = (0.5 * distScore +
                  0.3 * ratingScore +
                  0.2 * acceptanceRate +
                  ecoBonus)
              .clamp(0.0, 1.08);

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
      final ecoBonus =
          (preferElectricVehicle && d.isElectricVehicle) ? 0.08 : 0.0;
      final score =
          (0.5 * distScore + 0.3 * ratingScore + 0.2 * acceptanceRate + ecoBonus)
              .clamp(0.0, 1.08);
      return DispatchCandidateScore(
        driver: d,
        distanceMeters: dist,
        searchRadiusTierMeters: 8000,
        totalScore: score,
      );
    }).toList()..sort((a, b) => b.totalScore.compareTo(a.totalScore));

    return allRanked;
  }

  /// Tối ưu hóa lộ trình đa điểm dừng (Nearest-Neighbor + 2-Opt Local Search TSP)
  /// Hỗ trợ cả giao 1 chiều và giao khứ hồi 2 chiều (quay lại điểm lấy hàng).
  static OptimizedMultiStopRouteResult optimizeMultiStopRoute({
    required GeoPoint pickup,
    required List<Map<String, dynamic>> stops,
    bool isRoundTrip = false,
  }) {
    if (stops.isEmpty) {
      return OptimizedMultiStopRouteResult(
        optimizedStops: const [],
        originalDistanceMeters: 0,
        optimizedDistanceMeters: 0,
        savedDistanceMeters: 0,
        estimatedDurationSeconds: 0,
        routePolyline: [pickup],
      );
    }

    final resolvedStops = <Map<String, dynamic>>[];
    final stopPoints = <GeoPoint>[];

    for (var i = 0; i < stops.length; i++) {
      final clone = Map<String, dynamic>.from(stops[i]);
      final rawLat = clone['latitude'] ?? clone['lat'];
      final rawLng = clone['longitude'] ?? clone['lng'];
      GeoPoint pt;
      if (rawLat is num && rawLng is num) {
        pt = GeoPoint(latitude: rawLat.toDouble(), longitude: rawLng.toDouble());
      } else {
        final addr = (clone['address'] ?? '').toString().trim();
        final cached = tryResolveAddressToCoordinate(addr);
        if (cached != null) {
          pt = cached;
        } else {
          // Nội suy tọa độ xác định quanh điểm lấy khi nhập địa chỉ mới ở chế độ ngoại tuyến
          final seed = addr.codeUnits.fold<int>(i * 97 + 31, (a, b) => a * 31 + b);
          final angle = ((seed.abs() % 360) * math.pi) / 180.0;
          final radiusDeg = 0.012 + ((seed.abs() % 18) * 0.0015);
          pt = GeoPoint(
            latitude: pickup.latitude + math.sin(angle) * radiusDeg,
            longitude: pickup.longitude + math.cos(angle) * radiusDeg,
          );
        }
      }
      clone['latitude'] = pt.latitude;
      clone['longitude'] = pt.longitude;
      resolvedStops.add(clone);
      stopPoints.add(pt);
    }

    double computeTourRoadMeters(List<int> order) {
      var total = 0.0;
      var prev = pickup;
      for (final idx in order) {
        total += GeoMath.distanceMeters(prev, stopPoints[idx]) * 1.28;
        prev = stopPoints[idx];
      }
      if (isRoundTrip) {
        total += GeoMath.distanceMeters(prev, pickup) * 1.28;
      }
      return total;
    }

    final n = stopPoints.length;
    final originalOrder = List<int>.generate(n, (i) => i);
    final originalMeters = computeTourRoadMeters(originalOrder);

    List<int> bestOrder;
    if (n <= 1) {
      bestOrder = originalOrder;
    } else {
      // Bước 1: Dựng lộ trình khởi tạo bằng thuật toán Láng giềng gần nhất (Nearest-Neighbor)
      final unvisited = Set<int>.from(originalOrder);
      final nnOrder = <int>[];
      var current = pickup;
      while (unvisited.isNotEmpty) {
        int? nearestIdx;
        var nearestDist = double.infinity;
        for (final idx in unvisited) {
          final d = GeoMath.distanceMeters(current, stopPoints[idx]);
          if (d < nearestDist) {
            nearestDist = d;
            nearestIdx = idx;
          }
        }
        nnOrder.add(nearestIdx!);
        unvisited.remove(nearestIdx);
        current = stopPoints[nearestIdx];
      }

      bestOrder = computeTourRoadMeters(nnOrder) <= originalMeters
          ? nnOrder
          : List<int>.from(originalOrder);

      // Bước 2: Tinh chỉnh cục bộ 2-Opt tháo gỡ các đoạn đường cắt chéo
      var improved = true;
      while (improved) {
        improved = false;
        final currentBestDist = computeTourRoadMeters(bestOrder);
        for (var i = 0; i < n - 1; i++) {
          for (var k = i + 1; k < n; k++) {
            final candidate = <int>[
              ...bestOrder.sublist(0, i),
              ...bestOrder.sublist(i, k + 1).reversed,
              ...bestOrder.sublist(k + 1),
            ];
            if (computeTourRoadMeters(candidate) + 0.5 < currentBestDist) {
              bestOrder = candidate;
              improved = true;
              break;
            }
          }
          if (improved) break;
        }
      }
    }

    final optimizedMeters = computeTourRoadMeters(bestOrder);
    final reorderedStops =
        bestOrder.map((idx) => resolvedStops[idx]).toList(growable: false);

    final polyline = <GeoPoint>[];
    var legStart = pickup;
    for (final idx in bestOrder) {
      final legPts = generateRoutePolyline(legStart, stopPoints[idx], segments: 6);
      if (polyline.isNotEmpty && legPts.isNotEmpty) {
        polyline.addAll(legPts.skip(1));
      } else {
        polyline.addAll(legPts);
      }
      legStart = stopPoints[idx];
    }
    if (isRoundTrip) {
      final returnPts = generateRoutePolyline(legStart, pickup, segments: 6);
      if (polyline.isNotEmpty && returnPts.isNotEmpty) {
        polyline.addAll(returnPts.skip(1));
      } else {
        polyline.addAll(returnPts);
      }
    }

    final origRounded = originalMeters.round();
    final optRounded = math.min(origRounded, optimizedMeters.round());
    final savedRounded = math.max(0, origRounded - optRounded);
    final durationSec =
        ((optRounded / 1000.0) * 180).round() + (n - 1) * 180;

    return OptimizedMultiStopRouteResult(
      optimizedStops: reorderedStops,
      originalDistanceMeters: origRounded,
      optimizedDistanceMeters: optRounded,
      savedDistanceMeters: savedRounded,
      estimatedDurationSeconds: durationSec,
      routePolyline: polyline,
    );
  }

  /// Đánh giá khả năng ghép 2 đơn nội thành 2H cùng hướng (Co-Directional Batching):
  /// - Cùng gói dịch vụ `SAME_DAY_2H` và không phải đơn khứ hồi 2 chiều
  /// - Khoảng cách giữa 2 điểm lấy hàng <= 1.500m (1.5km)
  /// - Độ lệch góc phương vị (Bearing) giữa 2 vector giao hàng <= 25°
  /// - Tổng khối lượng hàng hóa <= 20kg
  /// - Tổng thời gian hoàn thành dự kiến <= 95 phút (đảm bảo SLA 2 giờ)
  static CoDirectionalBatchMatch? evaluateBatchCompatibility(
    ActiveOrderRecord a,
    ActiveOrderRecord b,
  ) {
    if (a.id == b.id) return null;
    if (a.serviceType != DeliveryServiceType.sameDay2h ||
        b.serviceType != DeliveryServiceType.sameDay2h) {
      return null;
    }
    if (a.isRoundTrip || b.isRoundTrip) return null;
    final batchableStatuses = <OrderStatus>{
      OrderStatus.searching,
      OrderStatus.accepted,
      OrderStatus.arrivingPickup,
    };
    if (!batchableStatuses.contains(b.status)) return null;

    final pickupDist = GeoMath.distanceMeters(a.pickupLocation, b.pickupLocation);
    if (pickupDist > 1500.0) return null;

    final bearingA = GeoMath.bearingDegrees(a.pickupLocation, a.dropoffLocation);
    final bearingB = GeoMath.bearingDegrees(b.pickupLocation, b.dropoffLocation);
    final bearingDiff = GeoMath.angularDifferenceDegrees(bearingA, bearingB);
    if (bearingDiff > 25.0) return null;

    final combinedWeight = a.weightKg + b.weightKg;
    if (combinedWeight > 20.0) return null;

    final seqAB = (pickupDist +
            GeoMath.distanceMeters(b.pickupLocation, a.dropoffLocation) +
            GeoMath.distanceMeters(a.dropoffLocation, b.dropoffLocation)) *
        1.28;
    final seqBA = (pickupDist +
            GeoMath.distanceMeters(b.pickupLocation, b.dropoffLocation) +
            GeoMath.distanceMeters(b.dropoffLocation, a.dropoffLocation)) *
        1.28;
    final bestCombinedRoadMeters = math.min(seqAB, seqBA);
    final combinedDurationSec =
        ((bestCombinedRoadMeters / 1000.0) * 180).round() + 300;
    if (combinedDurationSec > 95 * 60) return null;

    return CoDirectionalBatchMatch(
      partnerOrder: b,
      pickupDistanceMeters: pickupDist,
      bearingDifferenceDegrees: bearingDiff,
      combinedWeightKg: combinedWeight,
      estimatedCombinedDurationSeconds: combinedDurationSec,
    );
  }

  /// Tìm đơn hàng đối tác tối ưu nhất để ghép cặp cùng hướng cho gói Giao nhanh 2H
  static CoDirectionalBatchMatch? findBestBatchPartner(
    ActiveOrderRecord target,
    Iterable<ActiveOrderRecord> pool,
  ) {
    final groupCounts = <String, int>{};
    for (final o in pool) {
      final gid = o.batchGroupId;
      if (gid != null && gid.trim().isNotEmpty) {
        groupCounts[gid] = (groupCounts[gid] ?? 0) + 1;
      }
    }

    final matches = <CoDirectionalBatchMatch>[];
    for (final candidate in pool) {
      if (candidate.id == target.id) continue;
      final existingGroup = candidate.batchGroupId;
      if (existingGroup != null &&
          existingGroup.trim().isNotEmpty &&
          (groupCounts[existingGroup] ?? 0) >= 2) {
        continue;
      }
      final match = evaluateBatchCompatibility(target, candidate);
      if (match != null) {
        matches.add(match);
      }
    }
    if (matches.isEmpty) return null;
    matches.sort((x, y) {
      final scoreX = x.bearingDifferenceDegrees * 25.0 + x.pickupDistanceMeters;
      final scoreY = y.bearingDifferenceDegrees * 25.0 + y.pickupDistanceMeters;
      return scoreX.compareTo(scoreY);
    });
    return matches.first;
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
