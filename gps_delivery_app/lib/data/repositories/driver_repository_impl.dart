import '../../core/gps/gps_integrity_validator.dart';
import '../../core/gps/kalman_gps_filter.dart';
import '../../domain/entities/driver_entity.dart';
import '../../domain/entities/geo_point.dart';
import '../../domain/repositories/i_driver_repository.dart';
import '../datasources/local/sqlite_offline_queue_datasource.dart';
import '../datasources/remote/supabase_postgis_datasource.dart';

class DriverRepositoryImpl implements IDriverRepository {
  final SupabasePostgisDatasource remoteDatasource;
  final SqliteOfflineQueueDatasource localOfflineDatasource;
  final KalmanGpsFilter _kalmanFilter;

  GeoPoint? _lastValidPoint;
  int? _lastValidTimestampMs;

  DriverRepositoryImpl({
    required this.remoteDatasource,
    required this.localOfflineDatasource,
    KalmanGpsFilter? kalmanFilter,
  }) : _kalmanFilter = kalmanFilter ?? KalmanGpsFilter();

  @override
  Future<void> toggleOnlineStatus({
    required String driverId,
    required bool isOnline,
  }) async {
    if (!isOnline) {
      _kalmanFilter.reset();
    }
    try {
      await remoteDatasource.updateDriverOnlineState(
        driverId: driverId,
        isOnline: isOnline,
      );
    } catch (_) {
      await localOfflineDatasource.enqueueAction(
        actionType: 'DRIVER_TOGGLE_ONLINE',
        payload: {
          'driver_id': driverId,
          'is_online': isOnline,
        },
      );
    }
  }

  @override
  Future<void> recordDriverGpsSample({
    required String driverId,
    String? activeOrderId,
    required GeoPoint rawPoint,
    required double accuracyMeters,
    required double speedKmh,
    required double bearing,
    required bool isMockLocation,
    required int timestampMs,
  }) async {
    GpsIntegrityValidator.validateSample(
      currentPoint: rawPoint,
      currentTimestampMs: timestampMs,
      isMockFlaggedByOs: isMockLocation,
      previousPoint: _lastValidPoint,
      previousTimestampMs: _lastValidTimestampMs,
      reportedSpeedKmh: speedKmh,
    );

    final smoothedPoint = _kalmanFilter.filter(
      rawPoint: rawPoint,
      accuracyMeters: accuracyMeters,
      timestampMs: timestampMs,
    );

    _lastValidPoint = smoothedPoint;
    _lastValidTimestampMs = timestampMs;

    try {
      await remoteDatasource.insertDriverTrackingLog(
        driverId: driverId,
        orderId: activeOrderId,
        smoothedLocation: smoothedPoint,
        speedKmh: speedKmh,
        bearing: bearing,
        isMockLocation: isMockLocation,
      );
    } catch (_) {
      await localOfflineDatasource.enqueueAction(
        actionType: 'GPS_PING',
        payload: {
          'driver_id': driverId,
          'order_id': activeOrderId,
          'lat': smoothedPoint.latitude,
          'lng': smoothedPoint.longitude,
          'speed_kmh': speedKmh,
          'bearing': bearing,
          'recorded_at_ms': timestampMs,
        },
      );
    }
  }

  @override
  Future<List<DriverEntity>> findNearbyOnlineDrivers(
    GeoPoint pickupPoint,
  ) async {
    final drivers = await remoteDatasource.fetchOnlineApprovedDrivers();
    final scored = <(DriverEntity, double)>[];
    for (final d in drivers) {
      final score = d.computeDispatchScore(pickupPoint);
      if (score >= 0.0) {
        scored.add((d, score));
      }
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.map((e) => e.$1).toList();
  }
}
