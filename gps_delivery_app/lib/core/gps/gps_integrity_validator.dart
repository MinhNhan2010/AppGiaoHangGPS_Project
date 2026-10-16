import '../../domain/entities/geo_point.dart';
import '../config/env_config.dart';
import '../error/app_exception.dart';
import '../utils/geo_math.dart';

class BatteryTrackingPolicy {
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
}

class GpsIntegrityValidator {
  const GpsIntegrityValidator._();

  /// Kiểm định tính toàn vẹn mẫu tọa độ GPS theo quy tắc RULE-GEO-01 đến RULE-GEO-05 (Chương 14.1 - Bảng 33)
  static void validateSample({
    required GeoPoint currentPoint,
    required int currentTimestampMs,
    required bool isMockFlaggedByOs,
    GeoPoint? previousPoint,
    int? previousTimestampMs,
    double? reportedSpeedKmh,
    bool isAccelerometerActive = true,
  }) {
    // RULE-GEO-01: Kiểm tra cờ giả lập vị trí (Mock Location) từ hệ điều hành
    if (isMockFlaggedByOs) {
      throw const GpsIntegrityException(
        ruleId: 'RULE-GEO-01',
        message: 'Phát hiện phần mềm giả lập vị trí (Mock Location). Vui lòng tắt Fake GPS để tiếp tục nhận đơn.',
      );
    }

    // RULE-GEO-03: Đối chiếu độ khớp giữa cảm biến gia tốc IMU và vận tốc GPS
    if ((reportedSpeedKmh ?? 0.0) > 30.0 && !isAccelerometerActive) {
      throw const GpsIntegrityException(
        ruleId: 'RULE-GEO-03',
        message: 'Dữ liệu cảm biến gia tốc không khớp với tốc độ di chuyển GPS.',
      );
    }

    if (previousPoint != null && previousTimestampMs != null) {
      final deltaSec = (currentTimestampMs - previousTimestampMs) / 1000.0;
      if (deltaSec > 0.0) {
        final distMeters = GeoMath.distanceMeters(previousPoint, currentPoint);
        final computedSpeedKmh = (distMeters / deltaSec) * 3.6;

        // RULE-GEO-02: Ngưỡng vận tốc dịch chuyển bất thường (> 120 km/h)
        if (computedSpeedKmh > EnvConfig.maxValidVehicleSpeedKmh) {
          throw GpsIntegrityException(
            ruleId: 'RULE-GEO-02',
            message:
                'Vận tốc dịch chuyển tức thời (${computedSpeedKmh.toStringAsFixed(1)} km/h) vượt ngưỡng cho phép (${EnvConfig.maxValidVehicleSpeedKmh} km/h).',
          );
        }
      }
    }
  }

  /// RULE-GEO-05: Phát hiện bất thường khi tài xế đứng yên >= 15 phút trong trạng thái đang giao hàng
  static bool isStationaryAnomaly({
    required GeoPoint anchorPoint,
    required GeoPoint currentPoint,
    required int stationaryStartMs,
    required int currentTimestampMs,
  }) {
    final movedMeters = GeoMath.distanceMeters(anchorPoint, currentPoint);
    if (movedMeters > 15.0) return false;
    final elapsedSeconds = (currentTimestampMs - stationaryStartMs) ~/ 1000;
    return elapsedSeconds >= EnvConfig.stationaryAnomalyAlertSeconds;
  }

  /// Chính sách điều tiết tần suất phát GPS và đồ họa 3D theo dung lượng pin (Chương 15.2 - Bảng 36)
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
