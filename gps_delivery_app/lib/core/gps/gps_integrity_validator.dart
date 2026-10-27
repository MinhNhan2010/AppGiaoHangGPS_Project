import 'package:equatable/equatable.dart';
import '../../domain/entities/geo_point.dart';
import '../config/env_config.dart';
import '../error/app_exception.dart';
import '../utils/geo_math.dart';

class BatteryTrackingPolicy extends Equatable {
  final int pingIntervalSeconds;
  final int distanceFilterMeters;
  final bool enable3dBuildings;
  final double cameraPitch;
  final int targetFps;

  const BatteryTrackingPolicy({
    required this.pingIntervalSeconds,
    required this.distanceFilterMeters,
    required this.enable3dBuildings,
    required this.cameraPitch,
    required this.targetFps,
  });

  @override
  List<Object?> get props => [
        pingIntervalSeconds,
        distanceFilterMeters,
        enable3dBuildings,
        cameraPitch,
        targetFps,
      ];
}

class GpsIntegrityValidator {
  const GpsIntegrityValidator._();

  /// Kiểm định tính toàn vẹn mẫu tọa độ GPS trên thiết bị
  static void validateSample({
    required GeoPoint currentPoint,
    required int currentTimestampMs,
    required bool isMockFlaggedByOs,
    GeoPoint? previousPoint,
    int? previousTimestampMs,
    double? reportedSpeedKmh,
    bool isAccelerometerActive = true,
    double? accuracyMeters,
  }) {
    if (!currentPoint.latitude.isFinite ||
        !currentPoint.longitude.isFinite ||
        currentPoint.latitude.abs() > 90.0 ||
        currentPoint.longitude.abs() > 180.0 ||
        (accuracyMeters != null &&
            (!accuracyMeters.isFinite || accuracyMeters < 0.0))) {
      throw const GpsIntegrityException(
        ruleId: 'RULE-GEO-01',
        message: 'Tọa độ GPS hoặc sai số định vị nằm ngoài phạm vi WGS84 hợp lệ.',
      );
    }

    // Kiểm tra cờ giả lập vị trí (Mock Location) từ hệ điều hành
    if (isMockFlaggedByOs) {
      throw const GpsIntegrityException(
        ruleId: 'RULE-GEO-01',
        message:
            'Phát hiện phần mềm giả lập vị trí (Mock Location). Vui lòng tắt Fake GPS để tiếp tục nhận đơn.',
      );
    }

    // Đối chiếu độ khớp giữa cảm biến gia tốc IMU và vận tốc GPS
    if ((reportedSpeedKmh != null && !reportedSpeedKmh.isFinite) ||
        ((reportedSpeedKmh ?? 0.0) > 30.0 && !isAccelerometerActive)) {
      throw const GpsIntegrityException(
        ruleId: 'RULE-GEO-03',
        message:
            'Dữ liệu vận tốc GPS không khớp với cảm biến quán tính (IMU Accelerometer đứng yên).',
      );
    }

    // Phát hiện dịch chuyển tức thời bất thường (Teleportation > 120 km/h)
    if (previousPoint != null && previousTimestampMs != null) {
      final distMeters = GeoMath.distanceMeters(previousPoint, currentPoint);
      final elapsedSec = (currentTimestampMs - previousTimestampMs) / 1000.0;
      if (elapsedSec <= 0) {
        if (distMeters > 30.0) {
          throw GpsIntegrityException(
            ruleId: 'RULE-GEO-02',
            message:
                'Phát hiện dịch chuyển tọa độ tức thời bất thường (${distMeters.toStringAsFixed(0)}m với Δt=${elapsedSec.toStringAsFixed(2)}s).',
          );
        }
      } else if (distMeters > 10.0 || elapsedSec >= 0.5) {
        final calculatedSpeedKmh = (distMeters / elapsedSec) * 3.6;
        if (calculatedSpeedKmh > EnvConfig.maxValidVehicleSpeedKmh) {
          throw GpsIntegrityException(
            ruleId: 'RULE-GEO-02',
            message:
                'Phát hiện dịch chuyển tọa độ bất thường (${calculatedSpeedKmh.toStringAsFixed(1)} km/h > ${EnvConfig.maxValidVehicleSpeedKmh} km/h).',
          );
        }
      }
    }
  }

  /// Xác định cấu hình tần suất định vị và hiển thị bản đồ 3D theo mức pin
  static BatteryTrackingPolicy resolvePolicy({
    required int batteryLevelPercent,
    required bool isCharging,
  }) {
    if (isCharging || batteryLevelPercent > 50) {
      return const BatteryTrackingPolicy(
        pingIntervalSeconds: 2,
        distanceFilterMeters: 5,
        enable3dBuildings: true,
        cameraPitch: EnvConfig.map3dDefaultPitch,
        targetFps: 60,
      );
    }
    if (batteryLevelPercent > EnvConfig.lowBattery2dFallbackPercent) {
      return const BatteryTrackingPolicy(
        pingIntervalSeconds: 5,
        distanceFilterMeters: 10,
        enable3dBuildings: true,
        cameraPitch: 45.0,
        targetFps: EnvConfig.mapMaxFps,
      );
    }
    if (batteryLevelPercent >= 10) {
      return const BatteryTrackingPolicy(
        pingIntervalSeconds: 10,
        distanceFilterMeters: 20,
        enable3dBuildings: false,
        cameraPitch: 0.0,
        targetFps: EnvConfig.mapMaxFps,
      );
    }
    return const BatteryTrackingPolicy(
      pingIntervalSeconds: 30,
      distanceFilterMeters: 50,
      enable3dBuildings: false,
      cameraPitch: 0.0,
      targetFps: 15,
    );
  }
}
