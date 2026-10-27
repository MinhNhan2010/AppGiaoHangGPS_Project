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
  final KalmanGpsFilter? _injectedKalmanFilter;
  final Map<String, KalmanGpsFilter> _kalmanByDriver = {};
  final Map<String, GeoPoint> _lastValidPointByDriver = {};
  final Map<String, int> _lastValidTimestampMsByDriver = {};

  DriverRepositoryImpl({
    required this.remoteDatasource,
    required this.localOfflineDatasource,
    KalmanGpsFilter? kalmanFilter,
  }) : _injectedKalmanFilter = kalmanFilter;

  KalmanGpsFilter _filterForDriver(String driverId) {
    return _kalmanByDriver.putIfAbsent(driverId, () {
      if (_injectedKalmanFilter != null && _kalmanByDriver.isEmpty) {
        return _injectedKalmanFilter;
      }
      return KalmanGpsFilter(
        processNoiseMetersPerSec:
            _injectedKalmanFilter?.processNoiseMetersPerSec ?? 3.0,
      );
    });
  }

  @override
  Future<void> toggleOnlineStatus({
    required String driverId,
    required bool isOnline,
  }) async {
    if (!isOnline) {
      _kalmanByDriver[driverId]?.reset();
      _lastValidPointByDriver.remove(driverId);
      _lastValidTimestampMsByDriver.remove(driverId);
    }
    await localOfflineDatasource.updateRows(
      'drivers',
      {'is_online': isOnline ? 1 : 0},
      where: 'id = ?',
      whereArgs: [driverId],
    );
    try {
      await remoteDatasource.updateDriverOnlineState(
        driverId: driverId,
        isOnline: isOnline,
      );
    } catch (_) {
      await localOfflineDatasource.enqueueAction(
        actionType: 'DRIVER_TOGGLE_ONLINE',
        payload: {
          'table': 'drivers',
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
      previousPoint: _lastValidPointByDriver[driverId],
      previousTimestampMs: _lastValidTimestampMsByDriver[driverId],
      reportedSpeedKmh: speedKmh,
      accuracyMeters: accuracyMeters,
    );

    final smoothedPoint = _filterForDriver(driverId).filter(
      rawPoint: rawPoint,
      accuracyMeters: accuracyMeters,
      timestampMs: timestampMs,
    );

    _lastValidPointByDriver[driverId] = smoothedPoint;
    _lastValidTimestampMsByDriver[driverId] = timestampMs;

    await localOfflineDatasource.updateRows(
      'drivers',
      {
        'latitude': smoothedPoint.latitude,
        'longitude': smoothedPoint.longitude,
      },
      where: 'id = ?',
      whereArgs: [driverId],
    );

    final cleanOrderId = activeOrderId?.trim();
    final hasValidOrder =
        cleanOrderId != null && cleanOrderId.isNotEmpty && cleanOrderId != 'NO_ORDER';

    final recordedAtIso =
        DateTime.fromMillisecondsSinceEpoch(timestampMs).toIso8601String();
    final trackingRow = <String, dynamic>{
      'order_id': hasValidOrder ? cleanOrderId : 'NO_ORDER',
      'driver_id': driverId,
      'latitude': smoothedPoint.latitude,
      'longitude': smoothedPoint.longitude,
      'speed': speedKmh,
      'bearing': bearing,
      'is_mock_location': isMockLocation ? 1 : 0,
      'recorded_at': recordedAtIso,
    };
    if (hasValidOrder) {
      await localOfflineDatasource.upsertRow('order_tracking_logs', trackingRow);
    }

    try {
      await remoteDatasource.insertDriverTrackingLog(
        driverId: driverId,
        orderId: hasValidOrder ? cleanOrderId : null,
        smoothedLocation: smoothedPoint,
        speedKmh: speedKmh,
        bearing: bearing,
        isMockLocation: isMockLocation,
      );
    } catch (_) {
      if (hasValidOrder) {
        await localOfflineDatasource.enqueueAction(
          actionType: 'GPS_PING',
          payload: {
            'table': 'order_tracking_logs',
            'record': trackingRow,
          },
        );
      } else {
        await localOfflineDatasource.enqueueAction(
          actionType: 'DRIVER_LOCATION_PING',
          payload: {
            'driver_id': driverId,
            'latitude': smoothedPoint.latitude,
            'longitude': smoothedPoint.longitude,
            'speed': speedKmh,
            'bearing': bearing,
            'is_mock_location': isMockLocation,
          },
        );
      }
    }
  }

  @override
  Future<List<DriverEntity>> findNearbyOnlineDrivers(
    GeoPoint pickupPoint,
  ) async {
    List<DriverEntity> drivers;
    try {
      drivers = await remoteDatasource.fetchOnlineApprovedDrivers();
    } catch (_) {
      final rows = await localOfflineDatasource.queryRows(
        'drivers',
        where: 'is_online = ?',
        whereArgs: [1],
      );
      drivers = rows.map(DriverEntity.fromMap).toList();
    }
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
