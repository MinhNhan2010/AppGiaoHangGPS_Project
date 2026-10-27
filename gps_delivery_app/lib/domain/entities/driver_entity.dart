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

  /// Điểm điều phối thông minh đa tiêu chí
  /// Kết hợp khoảng cách GPS (bán kính 3km), điểm đánh giá (1..5), tỷ lệ nhận chuyến (0..100%) và quỹ ký quỹ >= 200.000đ
  double computeDispatchScore(GeoPoint pickupLocation) {
    final normalizedApproval = approvalStatus.trim().toUpperCase();
    final isApproved = normalizedApproval == 'APPROVED' ||
        approvalStatus.trim() == 'Đã duyệt';
    if (!isOnline ||
        !isApproved ||
        currentLocation == null ||
        walletBalance < 200000) {
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

    return (proximityScore * 0.50) +
        (ratingScore * 0.30) +
        (acceptanceScore * 0.20);
  }

  factory DriverEntity.fromMap(Map<String, dynamic> map) {
    final parsedPoint = GeoPoint.tryParsePostgis(map['current_location']) ??
        ((map['latitude'] is num && map['longitude'] is num)
            ? GeoPoint(
                latitude: (map['latitude'] as num).toDouble(),
                longitude: (map['longitude'] as num).toDouble(),
              )
            : null);
    final trips = (map['total_trips'] as num?)?.toInt() ?? 0;
    final rejected = (map['rejected_count'] as num?)?.toInt() ?? 0;
    final computedAcceptance = (trips + rejected) > 0
        ? (trips / (trips + rejected)) * 100.0
        : 100.0;
    return DriverEntity(
      id: (map['id'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      fullName: (map['full_name'] ?? '').toString(),
      licensePlate: (map['license_plate'] ?? '').toString(),
      vehicleType: (map['vehicle_type'] ?? 'MOTORBIKE').toString(),
      citizenId: (map['citizen_id'] ?? '').toString(),
      isOnline: map['is_online'] == true || map['is_online'] == 1,
      currentLocation: parsedPoint,
      currentBearing: (map['current_bearing'] as num? ?? 0.0).toDouble(),
      ratingAvg:
          ((map['rating_avg'] ?? map['rating']) as num? ?? 5.0).toDouble(),
      acceptanceRate:
          (map['acceptance_rate'] as num? ?? computedAcceptance).toDouble(),
      approvalStatus: (map['approval_status'] ?? 'PENDING').toString(),
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
        acceptanceRate,
        approvalStatus,
        walletBalance,
      ];
}
