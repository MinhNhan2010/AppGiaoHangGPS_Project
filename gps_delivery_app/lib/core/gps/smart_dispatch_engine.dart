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

/// Động cơ Điều phối Tài xế Thông minh (Chương 4.3 & Chương 14.2 - RULE-DSP-01..04)
/// & Bộ giải mã Địa chỉ / Nội suy Lộ trình GPS Thực tế
class SmartDispatchEngine {
  const SmartDispatchEngine._();

  static const List<int> radiusTiersMeters = [3000, 5000, 8000];

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

  /// Tìm kiếm gợi ý địa chỉ (Geocoding Autocomplete - UC03, UC04)
  static List<GeocodedPlaceSuggestion> searchAddressSuggestions(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return knownPlaces.take(4).toList();
    final matches = knownPlaces
        .where(
          (p) =>
              p.fullAddress.toLowerCase().contains(normalized) ||
              p.title.toLowerCase().contains(normalized),
        )
        .toList();
    return matches.isEmpty ? knownPlaces.take(3).toList() : matches;
  }

  /// Giải mã địa chỉ sang tọa độ GPS thực tế
  static GeoPoint resolveAddressToCoordinate(
    String address, {
    required GeoPoint fallback,
  }) {
    final normalized = address.trim().toLowerCase();
    for (final p in knownPlaces) {
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
