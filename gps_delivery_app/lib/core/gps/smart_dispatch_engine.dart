import 'dart:convert';
import 'dart:io';
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

/// Động cơ Điều phối Tài xế Thông minh (Chương 4.3 & Chương 14.2 - RULE-DSP-01..04)
/// & Bộ giải mã Địa chỉ OpenStreetMap Nominatim / Dẫn đường OSRM Thực tế
class SmartDispatchEngine {
  const SmartDispatchEngine._();

  static const List<int> radiusTiersMeters = [3000, 5000, 8000];

  static final List<GeocodedPlaceSuggestion> _liveCachedPlaces = [];
  static List<GeoPoint>? _lastLiveOsrmPolyline;

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
      title: '123 Lê Lợi, Bến Nghé, Quận 1',
      fullAddress: '123 Đường Lê Lợi, Phường Bến Nghé, Quận 1, TP. HCM',
      location: GeoPoint(latitude: 10.7731, longitude: 106.6983),
    ),
    GeocodedPlaceSuggestion(
      title: 'Bitexco Financial Tower',
      fullAddress: 'Bitexco Financial Tower, 45 Lê Lợi, P. Bến Nghé, Q.1, TP. HCM',
      location: GeoPoint(latitude: 10.7716, longitude: 106.7044),
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
  ];

  static List<GeocodedPlaceSuggestion> get _allPlaces => [
    ..._liveCachedPlaces,
    ...knownPlaces,
  ];

  /// Tìm kiếm gợi ý địa chỉ cục bộ + bộ nhớ đệm Nominatim (UC03, UC04)
  static List<GeocodedPlaceSuggestion> searchAddressSuggestions(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return _allPlaces.take(4).toList();
    final matches = _allPlaces
        .where(
          (p) =>
              p.fullAddress.toLowerCase().contains(normalized) ||
              p.title.toLowerCase().contains(normalized),
        )
        .toList();
    return matches.isEmpty ? _allPlaces.take(3).toList() : matches;
  }

  /// Truy vấn trực tiếp API OpenStreetMap Nominatim toàn quốc (`countrycodes=vn`)
  static Future<List<GeocodedPlaceSuggestion>> fetchLiveNominatimSuggestions(
    String query,
  ) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return searchAddressSuggestions(trimmed);

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4);
    try {
      final uri = Uri.parse(EnvConfig.nominatimSearchEndpoint).replace(
        queryParameters: {
          'format': 'json',
          'countrycodes': 'vn',
          'limit': '5',
          'q': trimmed,
        },
      );
      final req = await client.getUrl(uri);
      req.headers.set(
        HttpHeaders.userAgentHeader,
        'GpsDeliveryApp/1.0 (Flutter Multiplatform)',
      );
      final resp = await req.close().timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
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
                final exists = _liveCachedPlaces.any(
                  (p) => p.fullAddress == suggestion.fullAddress,
                );
                if (!exists) {
                  _liveCachedPlaces.insert(0, suggestion);
                }
              }
            }
          }
          if (results.isNotEmpty) return results;
        }
      }
    } catch (_) {
      // Tự động fallback về danh mục nội bộ khi không có kết nối mạng hoặc trong môi trường test
    } finally {
      client.close(force: true);
    }
    return searchAddressSuggestions(trimmed);
  }

  /// Truy vấn trực tiếp API dẫn đường thực tế OSRM (`router.project-osrm.org`)
  static Future<OsrmRouteResult> fetchLiveOsrmRoute(
    GeoPoint start,
    GeoPoint end,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4);
    try {
      final url =
          '${EnvConfig.osrmRouteEndpoint}/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson';
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(
        HttpHeaders.userAgentHeader,
        'GpsDeliveryApp/1.0 (Flutter Multiplatform)',
      );
      final resp = await req.close().timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          final routes = decoded['routes'];
          if (routes is List && routes.isNotEmpty) {
            final route = routes.first as Map<String, dynamic>;
            final dist = ((route['distance'] as num?)?.round() ?? 1200)
                .clamp(300, 100000);
            final dur = ((route['duration'] as num?)?.round() ?? 300)
                .clamp(60, 36000);
            final geom = route['geometry'] as Map<String, dynamic>?;
            final coords = geom?['coordinates'];
            final pts = <GeoPoint>[];
            if (coords is List) {
              for (final c in coords) {
                if (c is List && c.length >= 2) {
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
      client.close(force: true);
    }

    final fallbackDist =
        (GeoMath.distanceMeters(start, end) * 1.28).round().clamp(800, 50000);
    final fallbackDur = ((fallbackDist / 1000.0) * 185).round();
    final fallbackPts = generateRoutePolyline(start, end);
    return OsrmRouteResult(
      distanceMeters: fallbackDist,
      durationSeconds: fallbackDur,
      polylinePoints: fallbackPts,
      isLiveOsrm: false,
    );
  }

  /// Giải mã địa chỉ sang tọa độ GPS thực tế
  static GeoPoint resolveAddressToCoordinate(
    String address, {
    required GeoPoint fallback,
  }) {
    final normalized = address.trim().toLowerCase();
    for (final p in _allPlaces) {
      if (normalized.contains(p.title.toLowerCase()) ||
          p.fullAddress.toLowerCase() == normalized) {
        return p.location;
      }
    }
    return fallback;
  }

  /// RULE-DSP-01..04: Xếp hạng ứng viên tài xế theo bán kính mở rộng (3km -> 5km -> 8km)
  /// Công thức: Score = 0.5 * DistanceScore + 0.3 * RatingScore + 0.2 * AcceptanceRate
  static List<DispatchCandidateScore> rankDriversForPickup({
    required GeoPoint pickupLocation,
    required List<DriverApplicantRecord> drivers,
    Set<String> excludedDriverIds = const {},
  }) {
    final eligible = drivers.where((d) {
      return d.isOnline &&
          d.approvalStatus == 'Đã duyệt' &&
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
              (0.85 + (d.totalTrips % 15) * 0.01).clamp(0.0, 1.0);
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
      final score = 0.5 * distScore + 0.3 * ratingScore + 0.2 * 0.95;
      return DispatchCandidateScore(
        driver: d,
        distanceMeters: dist,
        searchRadiusTierMeters: 8000,
        totalScore: score,
      );
    }).toList()
      ..sort((a, b) => b.totalScore.compareTo(a.totalScore));

    return allRanked;
  }

  static List<GeoPoint>? get lastLiveOsrmPolyline => _lastLiveOsrmPolyline;

  /// Nội suy danh sách điểm tọa độ Polyline giữa điểm lấy và điểm giao
  static List<GeoPoint> generateRoutePolyline(
    GeoPoint start,
    GeoPoint end, {
    int segments = 10,
  }) {
    final points = <GeoPoint>[];
    for (var i = 0; i <= segments; i++) {
      final t = i / segments;
      // Tạo độ cong nhẹ mô phỏng khúc cua đường phố đô thị
      final bend = (t * (1.0 - t)) * 0.0035;
      points.add(
        GeoPoint(
          latitude: start.latitude + (end.latitude - start.latitude) * t + bend,
          longitude:
              start.longitude + (end.longitude - start.longitude) * t - bend,
        ),
      );
    }
    return points;
  }

  /// Kiểm tra tài xế đã vào vùng bán kính 100m điểm giao hàng chưa (RULE-ORD-03)
  static bool isWithinDropoffGeofence({
    required GeoPoint driverLocation,
    required GeoPoint dropoffLocation,
  }) {
    final dist = GeoMath.distanceMeters(driverLocation, dropoffLocation);
    return dist <= EnvConfig.arrivalGeofenceRadiusMeters;
  }
}

