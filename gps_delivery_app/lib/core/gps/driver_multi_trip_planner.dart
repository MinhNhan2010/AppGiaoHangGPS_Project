import 'dart:math' as math;

import '../../domain/entities/geo_point.dart';
import '../utils/geo_math.dart';

/// Role of a stop in a multi-order driver route sequence.
enum DriverStopKind { pickup, extraStop, dropoff, returnPickup }

/// A single stop within an optimized multi-trip driver sequence.
class DriverRouteStop {
  const DriverRouteStop({
    required this.orderId,
    required this.trackingCode,
    required this.kind,
    required this.stopIndex,
    required this.label,
    required this.address,
    required this.recipientName,
    required this.point,
    required this.legDistanceKm,
    required this.cumulativeKm,
    required this.etaMinutes,
  });

  final String orderId;
  final String trackingCode;
  final DriverStopKind kind;
  final int stopIndex;
  final String label;
  final String address;
  final String recipientName;
  final GeoPoint point;
  final double legDistanceKm;
  final double cumulativeKm;
  final int etaMinutes;
}

/// Result of optimizing all currently active orders assigned to a driver.
class DriverMultiTripPlan {
  const DriverMultiTripPlan({
    required this.stops,
    required this.originalDistanceKm,
    required this.optimizedDistanceKm,
    required this.savedDistanceKm,
    required this.estimatedTotalMinutes,
    required this.activeOrderCount,
    this.googleMapsDirectionsUri,
  });

  final List<DriverRouteStop> stops;
  final double originalDistanceKm;
  final double optimizedDistanceKm;
  final double savedDistanceKm;
  final int estimatedTotalMinutes;
  final int activeOrderCount;
  final Uri? googleMapsDirectionsUri;

  bool get isEmpty => stops.isEmpty;
}

class _StopDraft {
  const _StopDraft({
    required this.orderKey,
    required this.orderId,
    required this.trackingCode,
    required this.chainPos,
    required this.kind,
    required this.label,
    required this.address,
    required this.recipientName,
    required this.point,
  });

  final int orderKey;
  final String orderId;
  final String trackingCode;
  final int chainPos;
  final DriverStopKind kind;
  final String label;
  final String address;
  final String recipientName;
  final GeoPoint point;
}

GeoPoint? _parsePlannerPoint(Object? rawLat, Object? rawLng) {
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

Set<String> _extractCompletedCheckpoints(
  Map<String, dynamic> order,
  Map details,
) {
  final raw =
      order['completed_checkpoints'] ?? details['completed_checkpoints'];
  if (raw is! List) return const {};
  return {
    for (final item in raw)
      if (item is Map && item['key'] != null)
        '${item['key']}'
      else if (item is String && item.trim().isNotEmpty)
        item.trim(),
  };
}

double _roadKmBetween(GeoPoint a, GeoPoint b) =>
    GeoMath.distanceMeters(a, b) * 1.28 / 1000.0;

double _sequenceDistanceKm(List<_StopDraft> seq, GeoPoint? driverLocation) {
  if (seq.isEmpty) return 0.0;
  var total = 0.0;
  var prev = driverLocation;
  for (final stop in seq) {
    if (prev != null) {
      total += _roadKmBetween(prev, stop.point);
    }
    prev = stop.point;
  }
  return total;
}

List<_StopDraft> _nearestNeighborSequence(
  List<List<_StopDraft>> chains,
  GeoPoint? anchorStart, {
  int forcedFirstOrder = 0,
}) {
  final ptrs = List<int>.filled(chains.length, 0);
  final totalStops = chains.fold<int>(0, (sum, c) => sum + c.length);
  final result = <_StopDraft>[];

  GeoPoint? current = anchorStart;
  if (current == null && totalStops > 0) {
    final first = chains[forcedFirstOrder].first;
    result.add(first);
    ptrs[forcedFirstOrder] = 1;
    current = first.point;
  }

  while (result.length < totalStops) {
    int? bestOrder;
    var bestScore = double.infinity;

    for (var o = 0; o < chains.length; o++) {
      final p = ptrs[o];
      if (p >= chains[o].length) continue;
      final candidate = chains[o][p];
      final dist = current == null
          ? 0.0
          : _roadKmBetween(current, candidate.point);
      if (bestOrder == null ||
          dist < bestScore - 1e-6 ||
          ((dist - bestScore).abs() <= 1e-6 &&
              candidate.kind == DriverStopKind.pickup &&
              chains[bestOrder][ptrs[bestOrder]].kind !=
                  DriverStopKind.pickup)) {
        bestOrder = o;
        bestScore = dist;
      }
    }

    if (bestOrder == null) break;
    final picked = chains[bestOrder][ptrs[bestOrder]++];
    result.add(picked);
    current = picked.point;
  }
  return result;
}

List<_StopDraft> _relocateRefine(
  List<_StopDraft> initial,
  GeoPoint? driverLocation,
) {
  var seq = List<_StopDraft>.from(initial);
  var currentDist = _sequenceDistanceKm(seq, driverLocation);

  for (var pass = 0; pass < 4; pass++) {
    var improved = false;
    for (var i = 0; i < seq.length; i++) {
      final item = seq[i];
      final without = List<_StopDraft>.from(seq)..removeAt(i);

      var minInsert = 0;
      var maxInsert = without.length;
      for (var k = 0; k < without.length; k++) {
        final other = without[k];
        if (other.orderKey != item.orderKey) continue;
        if (other.chainPos < item.chainPos) {
          minInsert = math.max(minInsert, k + 1);
        } else if (other.chainPos > item.chainPos) {
          maxInsert = math.min(maxInsert, k);
        }
      }

      var bestJ = -1;
      var bestDist = currentDist;
      for (var j = minInsert; j <= maxInsert; j++) {
        final candidate = List<_StopDraft>.from(without)..insert(j, item);
        final dist = _sequenceDistanceKm(candidate, driverLocation);
        if (dist < bestDist - 1e-4) {
          bestDist = dist;
          bestJ = j;
        }
      }

      if (bestJ != -1) {
        seq = List<_StopDraft>.from(without)..insert(bestJ, item);
        currentDist = bestDist;
        improved = true;
      }
    }
    if (!improved) break;
  }

  return seq;
}

/// Computes an optimal precedence-constrained multi-trip route across all
/// currently active orders assigned to [driverUserId].
DriverMultiTripPlan buildOptimalDriverTripPlan({
  required List<Map<String, dynamic>> orders,
  required String driverUserId,
  GeoPoint? driverLocation,
  double avgSpeedKmh = 26.0,
}) {
  const activeStatuses = {
    'accepted',
    'arrivingPickup',
    'inTransit',
    'returning',
  };
  final safeSpeed = avgSpeedKmh.isFinite && avgSpeedKmh > 1.0
      ? avgSpeedKmh
      : 26.0;

  final chains = <List<_StopDraft>>[];
  var activeOrderCount = 0;

  for (final order in orders) {
    final assignedDriver = '${order['driver_id'] ?? ''}'.trim();
    if (driverUserId.isNotEmpty &&
        assignedDriver.isNotEmpty &&
        assignedDriver != driverUserId) {
      continue;
    }
    final status = '${order['status'] ?? ''}';
    if (!activeStatuses.contains(status)) continue;

    final orderId = '${order['id'] ?? ''}';
    final trackingCode = '${order['tracking_code'] ?? orderId}';
    final details = order['details'] is Map
        ? order['details'] as Map
        : const <String, dynamic>{};
    final completed = _extractCompletedCheckpoints(order, details);
    final recipientName = '${details['recipient_name'] ?? 'Người nhận'}'.trim();
    final pickupPt = _parsePlannerPoint(
      details['pickup_lat'],
      details['pickup_lng'],
    );
    final dropoffPt = _parsePlannerPoint(
      details['dropoff_lat'],
      details['dropoff_lng'],
    );
    final pickupAddr = '${details['pickup_address'] ?? 'Điểm lấy'}'.trim();
    final dropoffAddr = '${details['dropoff_address'] ?? 'Điểm giao'}'.trim();
    final rawExtra = details['extra_stops'] is List
        ? (details['extra_stops'] as List).whereType<Map>().toList()
        : const <Map>[];
    final isRoundTrip = details['is_round_trip'] == true;

    final chain = <_StopDraft>[];
    final orderKey = chains.length;

    void addDraft({
      required DriverStopKind kind,
      required String label,
      required String address,
      required GeoPoint point,
    }) {
      chain.add(
        _StopDraft(
          orderKey: orderKey,
          orderId: orderId,
          trackingCode: trackingCode,
          chainPos: chain.length,
          kind: kind,
          label: label,
          address: address,
          recipientName: recipientName,
          point: point,
        ),
      );
    }

    if (status == 'accepted' || status == 'arrivingPickup') {
      if (pickupPt != null) {
        addDraft(
          kind: DriverStopKind.pickup,
          label: 'Lấy hàng',
          address: pickupAddr,
          point: pickupPt,
        );
      }
      for (var i = 0; i < rawExtra.length; i++) {
        final done =
            completed.contains('stop:$i') ||
            completed.contains('stop_${i + 1}');
        if (done) continue;
        final pt = _parsePlannerPoint(rawExtra[i]['lat'], rawExtra[i]['lng']);
        if (pt != null) {
          addDraft(
            kind: DriverStopKind.extraStop,
            label: 'Điểm dừng #${i + 1}',
            address: '${rawExtra[i]['address'] ?? 'Điểm dừng #${i + 1}'}',
            point: pt,
          );
        }
      }
      if (dropoffPt != null) {
        addDraft(
          kind: DriverStopKind.dropoff,
          label: 'Giao hàng',
          address: dropoffAddr,
          point: dropoffPt,
        );
      }
      if (isRoundTrip && pickupPt != null) {
        addDraft(
          kind: DriverStopKind.returnPickup,
          label: 'Khứ hồi về điểm lấy',
          address: pickupAddr,
          point: pickupPt,
        );
      }
    } else if (status == 'inTransit') {
      for (var i = 0; i < rawExtra.length; i++) {
        final done =
            completed.contains('stop:$i') ||
            completed.contains('stop_${i + 1}');
        if (done) continue;
        final pt = _parsePlannerPoint(rawExtra[i]['lat'], rawExtra[i]['lng']);
        if (pt != null) {
          addDraft(
            kind: DriverStopKind.extraStop,
            label: 'Điểm dừng #${i + 1}',
            address: '${rawExtra[i]['address'] ?? 'Điểm dừng #${i + 1}'}',
            point: pt,
          );
        }
      }
      if (dropoffPt != null) {
        addDraft(
          kind: DriverStopKind.dropoff,
          label: 'Giao hàng',
          address: dropoffAddr,
          point: dropoffPt,
        );
      }
      if (isRoundTrip && pickupPt != null) {
        addDraft(
          kind: DriverStopKind.returnPickup,
          label: 'Khứ hồi về điểm lấy',
          address: pickupAddr,
          point: pickupPt,
        );
      }
    } else if (status == 'returning') {
      if (pickupPt != null) {
        addDraft(
          kind: DriverStopKind.returnPickup,
          label: 'Hoàn hàng về người gửi',
          address: pickupAddr,
          point: pickupPt,
        );
      }
    }

    if (chain.isNotEmpty) {
      chains.add(chain);
      activeOrderCount++;
    }
  }

  if (chains.isEmpty) {
    return const DriverMultiTripPlan(
      stops: [],
      originalDistanceKm: 0,
      optimizedDistanceKm: 0,
      savedDistanceKm: 0,
      estimatedTotalMinutes: 0,
      activeOrderCount: 0,
    );
  }

  final originalSeq = [for (final c in chains) ...c];
  final originalDistKm = _sequenceDistanceKm(originalSeq, driverLocation);

  var bestSeq = originalSeq;
  var bestDistKm = originalDistKm;

  if (driverLocation != null) {
    final nn = _nearestNeighborSequence(chains, driverLocation);
    final refined = _relocateRefine(nn, driverLocation);
    final refinedDist = _sequenceDistanceKm(refined, driverLocation);
    if (refinedDist < bestDistKm - 1e-4) {
      bestSeq = refined;
      bestDistKm = refinedDist;
    }
  } else {
    for (var startOrder = 0; startOrder < chains.length; startOrder++) {
      final nn = _nearestNeighborSequence(
        chains,
        null,
        forcedFirstOrder: startOrder,
      );
      final refined = _relocateRefine(nn, null);
      final refinedDist = _sequenceDistanceKm(refined, null);
      if (refinedDist < bestDistKm - 1e-4) {
        bestSeq = refined;
        bestDistKm = refinedDist;
      }
    }
  }

  final stops = <DriverRouteStop>[];
  var cumKm = 0.0;
  var prev = driverLocation;
  for (var idx = 0; idx < bestSeq.length; idx++) {
    final d = bestSeq[idx];
    final legKm = prev == null ? 0.0 : _roadKmBetween(prev, d.point);
    cumKm += legKm;
    final etaMin = cumKm <= 0.05
        ? 0
        : math.max(1, (cumKm / safeSpeed * 60.0).ceil());
    stops.add(
      DriverRouteStop(
        orderId: d.orderId,
        trackingCode: d.trackingCode,
        kind: d.kind,
        stopIndex: idx + 1,
        label: d.label,
        address: d.address,
        recipientName: d.recipientName,
        point: d.point,
        legDistanceKm: legKm,
        cumulativeKm: cumKm,
        etaMinutes: etaMin,
      ),
    );
    prev = d.point;
  }

  final originPt = driverLocation ?? stops.first.point;
  final destPt = stops.last.point;
  final middleStops = driverLocation != null
      ? stops.sublist(0, stops.length - 1)
      : (stops.length > 2
            ? stops.sublist(1, stops.length - 1)
            : const <DriverRouteStop>[]);
  final waypointStr = middleStops
      .take(9)
      .map(
        (s) =>
            '${s.point.latitude.toStringAsFixed(6)},${s.point.longitude.toStringAsFixed(6)}',
      )
      .join('|');
  final mapsUri = Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'origin':
        '${originPt.latitude.toStringAsFixed(6)},${originPt.longitude.toStringAsFixed(6)}',
    'destination':
        '${destPt.latitude.toStringAsFixed(6)},${destPt.longitude.toStringAsFixed(6)}',
    if (waypointStr.isNotEmpty) 'waypoints': waypointStr,
    'travelmode': 'driving',
  });

  final savedKm = math.max(0.0, originalDistKm - bestDistKm);
  final totalMinutes = stops.isEmpty ? 0 : stops.last.etaMinutes;

  return DriverMultiTripPlan(
    stops: stops,
    originalDistanceKm: originalDistKm,
    optimizedDistanceKm: bestDistKm,
    savedDistanceKm: savedKm,
    estimatedTotalMinutes: totalMinutes,
    activeOrderCount: activeOrderCount,
    googleMapsDirectionsUri: mapsUri,
  );
}
