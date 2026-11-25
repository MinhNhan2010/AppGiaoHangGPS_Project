import 'dart:math' as math;

import '../../domain/entities/geo_point.dart';
import '../../domain/entities/vehicle_class.dart';
import '../utils/geo_math.dart';

/// Real-time telemetry projection computed from a cloud order and the driver's
/// latest GPS sample.
class LiveTripTelemetry {
  const LiveTripTelemetry({
    required this.targetLabel,
    required this.targetPoint,
    required this.straightDistanceMeters,
    required this.estimatedRoadMeters,
    required this.effectiveSpeedKmh,
    required this.usedLiveSpeed,
    required this.etaMinutes,
    required this.estimatedArrival,
    required this.gpsAgeSeconds,
    required this.isSignalStale,
    required this.isArrivingSoon,
  });

  final String targetLabel;
  final GeoPoint targetPoint;
  final double straightDistanceMeters;
  final double estimatedRoadMeters;
  final double effectiveSpeedKmh;
  final bool usedLiveSpeed;
  final int etaMinutes;
  final DateTime estimatedArrival;
  final int? gpsAgeSeconds;
  final bool isSignalStale;
  final bool isArrivingSoon;
}

GeoPoint? _parseTelemetryPoint(Object? rawLat, Object? rawLng) {
  final lat = rawLat is num
      ? rawLat.toDouble()
      : double.tryParse('${rawLat ?? ''}'.trim());
  final lng = rawLng is num
      ? rawLng.toDouble()
      : double.tryParse('${rawLng ?? ''}'.trim());
  if (lat == null ||
      lng == null ||
      !lat.isFinite ||
      !lng.isFinite ||
      (lat == 0 && lng == 0) ||
      lat.abs() > 90 ||
      lng.abs() > 180) {
    return null;
  }
  return GeoPoint(latitude: lat, longitude: lng);
}

double _vehicleFallbackSpeedKmh(VehicleClass vehicle) => switch (vehicle.id) {
  'tricycle' => 22.0,
  'van' || 'truck' => 24.0,
  _ => 28.0,
};

double? _parseLiveSpeedKmh(Map<String, dynamic> liveGps) {
  final kmhRaw = liveGps['speed_kmh'];
  final kmh = kmhRaw is num
      ? kmhRaw.toDouble()
      : double.tryParse('${kmhRaw ?? ''}'.trim());
  if (kmh != null && kmh.isFinite && kmh >= 3.0 && kmh <= 80.0) {
    return kmh;
  }
  final mpsRaw = liveGps['speed_mps'] ?? liveGps['speed'];
  final mps = mpsRaw is num
      ? mpsRaw.toDouble()
      : double.tryParse('${mpsRaw ?? ''}'.trim());
  if (mps != null && mps.isFinite) {
    final converted = mps * 3.6;
    if (converted >= 3.0 && converted <= 80.0) {
      return converted;
    }
  }
  return null;
}

/// Computes live road-adjusted distance, ETA, and signal freshness from
/// [order] and [liveGps]. Returns `null` when [order] is not actively moving
/// or coordinates are missing/invalid.
LiveTripTelemetry? computeLiveTripTelemetry({
  required Map<String, dynamic> order,
  required Map<String, dynamic> liveGps,
  Set<String> completedCheckpoints = const {},
  DateTime? now,
}) {
  final driverPt = _parseTelemetryPoint(
    liveGps['latitude'] ?? liveGps['lat'],
    liveGps['longitude'] ?? liveGps['lng'],
  );
  if (driverPt == null) return null;

  final status = '${order['status'] ?? ''}';
  final details = order['details'] is Map
      ? order['details'] as Map
      : const <String, dynamic>{};

  String? targetLabel;
  GeoPoint? targetPoint;

  switch (status) {
    case 'accepted':
    case 'arrivingPickup':
      targetLabel = 'Điểm lấy hàng [A]';
      targetPoint = _parseTelemetryPoint(
        details['pickup_lat'],
        details['pickup_lng'],
      );
      break;
    case 'inTransit':
      final rawStops = details['extra_stops'] is List
          ? (details['extra_stops'] as List).whereType<Map>().toList()
          : const <Map>[];
      for (var i = 0; i < rawStops.length; i++) {
        final done =
            completedCheckpoints.contains('stop:$i') ||
            completedCheckpoints.contains('stop_${i + 1}');
        if (done) continue;
        final pt = _parseTelemetryPoint(rawStops[i]['lat'], rawStops[i]['lng']);
        if (pt != null) {
          targetLabel = 'Điểm dừng #${i + 1}';
          targetPoint = pt;
          break;
        }
      }
      targetPoint ??= _parseTelemetryPoint(
        details['dropoff_lat'],
        details['dropoff_lng'],
      );
      targetLabel ??= 'Điểm giao hàng [B]';
      break;
    case 'returning':
      targetLabel = 'Điểm hoàn hàng [A]';
      targetPoint = _parseTelemetryPoint(
        details['pickup_lat'],
        details['pickup_lng'],
      );
      break;
    default:
      return null;
  }

  if (targetPoint == null) return null;

  final straightDistanceMeters = GeoMath.distanceMeters(driverPt, targetPoint);
  final estimatedRoadMeters = straightDistanceMeters < 150
      ? straightDistanceMeters
      : straightDistanceMeters * 1.28;

  final vehicle = VehicleClass.resolve(
    vehicleType: details['vehicle_type'] ?? order['vehicle_type'],
    serviceType: details['service_type'] ?? order['service_type'],
    preferEv: details['prefer_ev'] == true,
  );
  final liveSpeed = _parseLiveSpeedKmh(liveGps);
  final usedLiveSpeed = liveSpeed != null;
  final effectiveSpeedKmh = liveSpeed ?? _vehicleFallbackSpeedKmh(vehicle);

  final etaMinutes = straightDistanceMeters <= 80
      ? 0
      : math.max(
          1,
          ((estimatedRoadMeters / 1000.0) / effectiveSpeedKmh * 60.0).ceil(),
        );

  final refNow = (now ?? DateTime.now()).toLocal();
  final estimatedArrival = refNow.add(Duration(minutes: etaMinutes));

  final rawUpdatedAt = '${liveGps['updated_at'] ?? ''}'.trim();
  final updatedAt = rawUpdatedAt.isEmpty
      ? null
      : DateTime.tryParse(rawUpdatedAt);
  final gpsAgeSeconds = updatedAt == null
      ? null
      : math.max(0, refNow.toUtc().difference(updatedAt.toUtc()).inSeconds);

  return LiveTripTelemetry(
    targetLabel: targetLabel,
    targetPoint: targetPoint,
    straightDistanceMeters: straightDistanceMeters,
    estimatedRoadMeters: estimatedRoadMeters,
    effectiveSpeedKmh: effectiveSpeedKmh,
    usedLiveSpeed: usedLiveSpeed,
    etaMinutes: etaMinutes,
    estimatedArrival: estimatedArrival,
    gpsAgeSeconds: gpsAgeSeconds,
    isSignalStale: gpsAgeSeconds != null && gpsAgeSeconds > 120,
    isArrivingSoon: straightDistanceMeters <= 300,
  );
}

String formatTelemetryDistance(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000.0).toStringAsFixed(1)} km';

String formatTelemetryClock(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String formatGpsAgeLabel(int? seconds) {
  if (seconds == null) return 'Đang đồng bộ';
  if (seconds < 60) return 'Vừa cập nhật';
  if (seconds <= 120) return '${seconds ~/ 60} phút trước';
  return 'Tín hiệu cũ (${seconds ~/ 60}p)';
}
