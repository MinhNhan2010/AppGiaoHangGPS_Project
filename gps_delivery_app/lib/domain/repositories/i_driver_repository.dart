import '../entities/driver_entity.dart';
import '../entities/geo_point.dart';

abstract interface class IDriverRepository {
  Future<void> toggleOnlineStatus({
    required String driverId,
    required bool isOnline,
  });

  Future<void> recordDriverGpsSample({
    required String driverId,
    String? activeOrderId,
    required GeoPoint rawPoint,
    required double accuracyMeters,
    required double speedKmh,
    required double bearing,
    required bool isMockLocation,
    required int timestampMs,
  });

  Future<List<DriverEntity>> findNearbyOnlineDrivers(GeoPoint pickupPoint);
}
