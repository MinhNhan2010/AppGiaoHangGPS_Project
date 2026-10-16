import 'package:equatable/equatable.dart';
import '../../core/config/env_config.dart';
import '../../core/utils/geo_math.dart';
import 'geo_point.dart';

class DriverEntity extends Equatable {
  final String id;
  final String phone;
  final String fullName;
  final String licensePlate;
  final String vehicleType;
  final String citizenId;
  final bool isOnline;
  final GeoPoint? currentLocation;
  final double currentBearing;
  final double ratingAvg;
  final double acceptanceRate;
  final String approvalStatus;
  final double walletBalance;

  const DriverEntity({
    required this.id,
    required this.phone,
    required this.fullName,
    required this.licensePlate,
    required this.vehicleType,
    required this.citizenId,
    required this.isOnline,
    this.currentLocation,
    this.currentBearing = 0.0,
    this.ratingAvg = 5.0,
    this.acceptanceRate = 100.0,
    this.approvalStatus = 'PENDING',
    this.walletBalance = 0.0,
  });

  /// Điểm điều phối thông minh đa tiêu chí (Mục 4.2.2)
  /// Kết hợp khoảng cách GPS (bán kính 3km), điểm đánh giá (1..5) và tỷ lệ nhận chuyến (0..100%)
  double computeDispatchScore(GeoPoint pickupLocation) {
    if (!isOnline || approvalStatus != 'APPROVED' || currentLocation == null) {
      return -1.0;
    }
    final distMeters = GeoMath.distanceMeters(currentLocation!, pickupLocation);
    if (distMeters > EnvConfig.dispatchRadiusMeters) {
      return -1.0;
    }
    final proximityScore =
        1.0 - (distMeters / EnvConfig.dispatchRadiusMeters).clamp(0.0, 1.0);
    final ratingScore = (ratingAvg / 5.0).clamp(0.0, 1.0);
    final acceptanceScore = (acceptanceRate / 100.0).clamp(0.0, 1.0);

    return (proximityScore * 0.55) +
        (ratingScore * 0.25) +
        (acceptanceScore * 0.20);
  }

  factory DriverEntity.fromMap(Map<String, dynamic> map) {
    return DriverEntity(
      id: map['id'] as String,
      phone: map['phone'] as String,
      fullName: map['full_name'] as String,
      licensePlate: map['license_plate'] as String,
      vehicleType: map['vehicle_type'] as String,
      citizenId: map['citizen_id'] as String,
      isOnline: map['is_online'] as bool? ?? false,
      currentLocation: map['current_location'] != null
          ? GeoPoint.fromGeoJson(
              map['current_location'] as Map<String, dynamic>,
            )
          : null,
      currentBearing: (map['current_bearing'] as num? ?? 0.0).toDouble(),
      ratingAvg: (map['rating_avg'] as num? ?? 5.0).toDouble(),
      acceptanceRate: (map['acceptance_rate'] as num? ?? 100.0).toDouble(),
      approvalStatus: map['approval_status'] as String? ?? 'PENDING',
      walletBalance: (map['wallet_balance'] as num? ?? 0.0).toDouble(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        isOnline,
        currentLocation,
        currentBearing,
        ratingAvg,
        walletBalance,
      ];
}
