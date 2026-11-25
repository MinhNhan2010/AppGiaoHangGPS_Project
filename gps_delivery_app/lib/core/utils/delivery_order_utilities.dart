import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../domain/entities/geo_point.dart';
import '../../domain/entities/vehicle_class.dart';
import '../../presentation/widgets/cloud_order_labels.dart';
import '../../presentation/widgets/cloud_profile_form.dart';
import 'geo_math.dart';
import 'platform_file_and_browser_bridge.dart';

/// Builds `initialDetails` for [CloudOrderForm] from an existing cloud order so
/// the customer can resend with 1 tap while dropping stale schedule/coin flags.
Map<String, dynamic> buildReorderInitialDetails(Map<String, dynamic> order) {
  final raw = order['details'] is Map
      ? Map<String, dynamic>.from(order['details'] as Map)
      : const <String, dynamic>{};
  final result = <String, dynamic>{};

  const copyKeys = [
    'pickup_address',
    'pickup_lat',
    'pickup_lng',
    'dropoff_address',
    'dropoff_lat',
    'dropoff_lng',
    'recipient_name',
    'recipient_phone',
    'package_description',
    'weight_kg',
    'cod_amount',
    'length_cm',
    'width_cm',
    'height_cm',
    'declared_value',
    'buyer_note',
    'service_type',
    'payment_method',
    'is_round_trip',
    'prefer_ev',
    'green_fund',
    'require_pod',
    'require_otp',
    'require_signature',
  ];

  for (final key in copyKeys) {
    if (raw.containsKey(key) && raw[key] != null) {
      result[key] = raw[key];
    }
  }

  final extraStops = raw['extra_stops'];
  if (extraStops is List && extraStops.isNotEmpty) {
    result['extra_stops'] = [
      for (final s in extraStops.whereType<Map>().take(5))
        {'address': '${s['address'] ?? ''}', 'lat': s['lat'], 'lng': s['lng']},
    ];
  }

  final resolvedVehicle = VehicleClass.resolve(
    vehicleType: raw['vehicle_type'],
    serviceType: raw['service_type'],
    preferEv: raw['prefer_ev'] == true,
  );
  result['vehicle_type'] = resolvedVehicle.id;
  if (resolvedVehicle == VehicleClass.evScooter) {
    result['prefer_ev'] = true;
  }
  if (!result.containsKey('cod_amount') && order['cod_amount'] != null) {
    result['cod_amount'] = order['cod_amount'];
  }
  if (!result.containsKey('merchant_id') && order['merchant_id'] != null) {
    result['merchant_id'] = order['merchant_id'];
  }
  return result;
}

class FareEstimateRow {
  const FareEstimateRow({
    required this.vehicle,
    required this.serviceType,
    required this.serviceLabel,
    required this.estimatedFee,
    required this.fitsWeight,
    this.disabledReason,
  });

  final VehicleClass vehicle;
  final String serviceType;
  final String serviceLabel;
  final int estimatedFee;
  final bool fitsWeight;
  final String? disabledReason;

  bool get selectable => disabledReason == null;
}

const _tierPricingSpec =
    <String, ({int base, int perKm, int freeKm, int freeKg, int extraKg})>{
      'standard': (
        base: 25000,
        perKm: 5000,
        freeKm: 2,
        freeKg: 5,
        extraKg: 3000,
      ),
      'express': (
        base: 35000,
        perKm: 6000,
        freeKm: 2,
        freeKg: 5,
        extraKg: 3500,
      ),
      'saving': (base: 18000, perKm: 4000, freeKm: 2, freeKg: 5, extraKg: 2500),
      'same_day_2h': (
        base: 22000,
        perKm: 4500,
        freeKm: 2,
        freeKg: 5,
        extraKg: 2500,
      ),
      'truck': (
        base: 80000,
        perKm: 15000,
        freeKm: 2,
        freeKg: 20,
        extraKg: 3000,
      ),
    };

/// Produces estimated fares across all 5 [VehicleClass]es and compatible
/// service tiers, matching baseline `delivery_cloud_quote` formulas.
List<FareEstimateRow> estimateDeliveryFareMatrix({
  required double distanceKm,
  required double weightKg,
}) {
  final safeKm = (distanceKm.isFinite ? distanceKm : 5.0).clamp(0.5, 200.0);
  final safeKg = (weightKg.isFinite ? weightKg : 1.0).clamp(0.1, 1500.0);
  final rows = <FareEstimateRow>[];

  for (final vehicle in VehicleClass.all) {
    final fits = safeKg <= vehicle.maxKg;
    for (final entry in cloudServiceTypes.entries) {
      final tier = entry.key;
      if (!vehicle.allowsService(tier)) continue;
      final spec = _tierPricingSpec[tier]!;
      final extraKm = math.max(0, (safeKm - spec.freeKm).ceil());
      final extraKg = math.max(0, (safeKg - spec.freeKg).ceil());
      final vehicleFee = vehicle.estimateFee(safeKm);
      final totalFee =
          spec.base +
          extraKm * spec.perKm +
          extraKg * spec.extraKg +
          vehicleFee;

      String? disabledReason;
      if (!fits) {
        disabledReason = 'Vượt tải ${vehicle.maxKg} kg';
      } else if (tier == 'same_day_2h' && safeKm > 50) {
        disabledReason = 'Chỉ hỗ trợ ≤ 50 km';
      }

      rows.add(
        FareEstimateRow(
          vehicle: vehicle,
          serviceType: tier,
          serviceLabel: entry.value,
          estimatedFee: totalFee,
          fitsWeight: fits,
          disabledReason: disabledReason,
        ),
      );
    }
  }
  return rows;
}

const driverIncidentTag = '[SỰ CỐ CHUYẾN GIAO]';

const driverIncidentPresets = <({String code, String title, String detail})>[
  (
    code: 'traffic_flood',
    title: 'Kẹt xe / Đường ngập nặng',
    detail: 'Tuyến đường đang ùn tắc hoặc ngập nước, dự kiến chậm 15–30 phút.',
  ),
  (
    code: 'vehicle_issue',
    title: 'Sự cố phương tiện',
    detail: 'Xe gặp sự cố kỹ thuật giữa đường, tài xế đang xử lý an toàn.',
  ),
  (
    code: 'no_answer',
    title: 'Không liên hệ được người nhận',
    detail: 'Đã gọi điện nhiều lần nhưng người nhận chưa nghe máy.',
  ),
  (
    code: 'wrong_address',
    title: 'Sai địa chỉ / Đổi điểm giao',
    detail:
        'Địa chỉ thực tế chưa khớp hoặc khách yêu cầu điều chỉnh điểm nhận.',
  ),
  (
    code: 'overweight',
    title: 'Hàng cồng kềnh quá tải',
    detail: 'Kích thước hoặc khối lượng kiện hàng vượt mức xe đã đặt.',
  ),
  (
    code: 'heavy_rain',
    title: 'Mưa giông lớn',
    detail: 'Thời tiết xấu cần tạm dừng bảo vệ hàng hóa không bị ướt.',
  ),
];

String formatDriverIncidentMessage(String title, String note) {
  final cleanTitle = title.trim();
  final cleanNote = note.trim();
  return cleanNote.isEmpty
      ? '$driverIncidentTag $cleanTitle'
      : '$driverIncidentTag $cleanTitle — $cleanNote';
}

bool isDriverIncidentMessage(String text) =>
    text.trimLeft().startsWith(driverIncidentTag);

String _escapeCsvCell(Object? raw) {
  var value = '${raw ?? ''}'.replaceAll('\r\n', ' ').replaceAll('\n', ' ');
  if (value.isNotEmpty &&
      const ['=', '+', '-', '@', '\t', '\r'].contains(value[0])) {
    value = "'$value";
  }
  if (value.contains(',') || value.contains('"')) {
    value = '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

String _paymentMethodLabel(Object? method) => switch (method) {
  'recipient_cash' => 'Người nhận trả tiền mặt',
  'sender_bank_qr' => 'Chuyển khoản ngân hàng',
  _ => 'Người gửi trả tiền mặt',
};

/// Builds a UTF-8 BOM CSV report of cloud delivery orders safe for Excel.
String buildOrdersCsv(List<Map<String, dynamic>> orders) {
  const headers = [
    'Mã vận đơn',
    'Trạng thái',
    'Loại xe',
    'Gói dịch vụ',
    'Khối lượng (kg)',
    'Cước vận chuyển (VND)',
    'Thu hộ COD (VND)',
    'Thanh toán',
    'Điểm lấy',
    'Điểm giao',
    'Người nhận',
    'SĐT nhận',
    'Thời gian tạo',
  ];
  final lines = <String>[headers.map(_escapeCsvCell).join(',')];
  for (final order in orders) {
    final details = order['details'] is Map
        ? order['details'] as Map
        : const <String, dynamic>{};
    final vehicle = VehicleClass.resolve(
      vehicleType: details['vehicle_type'],
      serviceType: details['service_type'],
      preferEv: details['prefer_ev'] == true,
    );
    final statusKey = '${order['status'] ?? ''}';
    final serviceKey = '${details['service_type'] ?? 'standard'}';
    final row = [
      order['tracking_code'] ?? order['id'] ?? '',
      cloudStatuses[statusKey] ?? statusKey,
      vehicle.label,
      cloudServiceTypes[serviceKey] ?? serviceKey,
      details['weight_kg'] ?? '',
      cloudOrderPayableFee(order),
      (order['cod_amount'] as num? ?? 0).toInt(),
      _paymentMethodLabel(details['payment_method']),
      details['pickup_address'] ?? '',
      details['dropoff_address'] ?? '',
      details['recipient_name'] ?? '',
      details['recipient_phone'] ?? '',
      cloudDate(order['created_at']),
    ];
    lines.add(row.map(_escapeCsvCell).join(','));
  }
  return '\uFEFF${lines.join('\r\n')}';
}

/// Summary metrics for a driver partner's visible orders.
class DriverShiftSummary {
  const DriverShiftSummary({
    required this.activeCount,
    required this.deliveredCount,
    required this.estimatedEarningsVnd,
    required this.codHoldingVnd,
  });

  final int activeCount;
  final int deliveredCount;
  final int estimatedEarningsVnd;
  final int codHoldingVnd;
}

/// Calculates active/delivered counts, 80% net earnings on completed trips, and
/// un-remitted COD held by [driverUserId].
DriverShiftSummary summarizeDriverOrders(
  List<Map<String, dynamic>> orders,
  String driverUserId,
) {
  const activeStatuses = {
    'accepted',
    'arrivingPickup',
    'inTransit',
    'returning',
  };
  var activeCount = 0;
  var deliveredCount = 0;
  var estimatedEarningsVnd = 0;
  var codHoldingVnd = 0;

  for (final order in orders) {
    final assignedDriver = '${order['driver_id'] ?? ''}'.trim();
    if (driverUserId.isNotEmpty &&
        assignedDriver.isNotEmpty &&
        assignedDriver != driverUserId) {
      continue;
    }
    final status = '${order['status'] ?? ''}';
    if (activeStatuses.contains(status)) {
      activeCount++;
    } else if (status == 'delivered') {
      deliveredCount++;
      final explicitEarning = (order['estimated_earning'] as num?)?.round();
      estimatedEarningsVnd +=
          explicitEarning ?? (cloudOrderPayableFee(order) * 0.8).round();
    }

    final cod = (order['cod_amount'] as num? ?? 0).toInt();
    final collected = (order['cod_collected_amount'] as num? ?? 0).toInt();
    final remitted = order['cod_remitted'] == true;
    if (cod > 0 &&
        !remitted &&
        (collected >= cod || status == 'inTransit' || status == 'delivered')) {
      codHoldingVnd += cod;
    }
  }

  return DriverShiftSummary(
    activeCount: activeCount,
    deliveredCount: deliveredCount,
    estimatedEarningsVnd: estimatedEarningsVnd,
    codHoldingVnd: codHoldingVnd,
  );
}

/// Summary KPIs and stale-order counter across admin order views.
class AdminOrdersSummary {
  const AdminOrdersSummary({
    required this.total,
    required this.searching,
    required this.staleSearching,
    required this.active,
    required this.delivered,
    required this.totalShippingFee,
    required this.totalCod,
  });

  final int total;
  final int searching;
  final int staleSearching;
  final int active;
  final int delivered;
  final int totalShippingFee;
  final int totalCod;
}

/// Summarizes status counts, orders waiting in `searching` > 15 min, fees, and COD.
AdminOrdersSummary summarizeAdminOrders(
  List<Map<String, dynamic>> orders, {
  DateTime? now,
}) {
  const activeStatuses = {
    'accepted',
    'arrivingPickup',
    'inTransit',
    'returning',
  };
  final refTime = (now ?? DateTime.now()).toUtc();
  var searching = 0;
  var staleSearching = 0;
  var active = 0;
  var delivered = 0;
  var totalShippingFee = 0;
  var totalCod = 0;

  for (final order in orders) {
    final status = '${order['status'] ?? ''}';
    if (status == 'searching') {
      searching++;
      final createdAt = DateTime.tryParse('${order['created_at'] ?? ''}')
          ?.toUtc();
      if (createdAt != null &&
          refTime.difference(createdAt) > const Duration(minutes: 15)) {
        staleSearching++;
      }
    } else if (activeStatuses.contains(status)) {
      active++;
    } else if (status == 'delivered') {
      delivered++;
    }
    totalShippingFee += cloudOrderPayableFee(order);
    totalCod += (order['cod_amount'] as num? ?? 0).toInt();
  }

  return AdminOrdersSummary(
    total: orders.length,
    searching: searching,
    staleSearching: staleSearching,
    active: active,
    delivered: delivered,
    totalShippingFee: totalShippingFee,
    totalCod: totalCod,
  );
}

/// Builds a UTF-8 BOM CSV report of managed cloud accounts safe for Excel.
String buildAccountsCsv(List<Map<String, dynamic>> accounts) {
  const headers = [
    'UUID',
    'Họ tên',
    'Email',
    'SĐT',
    'CCCD',
    'Vai trò đã duyệt',
    'Trạng thái duyệt',
    'Operator',
    'Trạng thái khóa',
    'Đơn đã tạo',
    'Chuyến tài xế',
    'Ví Xu',
  ];
  final lines = <String>[headers.map(_escapeCsvCell).join(',')];

  for (final account in accounts) {
    final approvedRoles = (account['approved_roles'] as List? ?? const [])
        .map((r) => cloudAccountRoles['$r'] ?? '$r')
        .join(' / ');
    final pendingRoles = (account['memberships'] as List? ?? const [])
        .whereType<Map>()
        .where((m) => m['state'] == 'pending')
        .map((m) => cloudAccountRoles['${m['role']}'] ?? '${m['role'] ?? ''}')
        .toList();
    final approvalLabel = pendingRoles.isNotEmpty
        ? 'Chờ duyệt (${pendingRoles.join(' / ')})'
        : account['has_profile'] == true
        ? 'Đã hoàn tất'
        : 'Chưa hoàn tất hồ sơ';
    final row = [
      account['user_id'] ?? '',
      account['full_name'] ?? '',
      account['email'] ?? '',
      account['phone'] ?? '',
      account['citizen_id'] ?? '',
      approvedRoles.isEmpty ? 'Khách hàng' : approvedRoles,
      approvalLabel,
      account['is_operator'] == true ? 'Có' : 'Không',
      account['blocked'] == true ? 'Đang khóa' : 'Hoạt động',
      (account['orders_count'] as num? ?? 0).toInt(),
      (account['driver_orders_count'] as num? ?? 0).toInt(),
      (account['coin_balance'] as num? ?? 0).toInt(),
    ];
    lines.add(row.map(_escapeCsvCell).join(','));
  }

  return '\uFEFF${lines.join('\r\n')}';
}

Future<String> _exportCsvString(String prefix, String csv) async {
  final now = DateTime.now();
  final stamp =
      '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
  final fileName = '${prefix}_$stamp.csv';
  if (kIsWeb) {
    triggerBrowserFileDownload(
      fileName: fileName,
      content: csv,
      mimeType: 'text/csv;charset=utf-8',
    );
    return fileName;
  }
  final file = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName',
  );
  await file.writeAsString(csv, flush: true);
  return file.path;
}

/// Exports [orders] to a downloadable CSV on web or a temp file on native.
Future<String> exportOrdersCsvFile(List<Map<String, dynamic>> orders) =>
    _exportCsvString('bao_cao_van_don_ghst', buildOrdersCsv(orders));

/// Exports [accounts] to a downloadable CSV on web or a temp file on native.
Future<String> exportAccountsCsvFile(List<Map<String, dynamic>> accounts) =>
    _exportCsvString('danh_sach_tai_khoan_ghst', buildAccountsCsv(accounts));

GeoPoint? _parseUtilityPoint(Object? rawLat, Object? rawLng) {
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

int _parseOrderRouteMeters(Map<String, dynamic> order) {
  final details = order['details'] is Map
      ? order['details'] as Map
      : const <String, dynamic>{};
  final pickup = _parseUtilityPoint(
    details['pickup_lat'],
    details['pickup_lng'],
  );
  final dropoff = _parseUtilityPoint(
    details['dropoff_lat'],
    details['dropoff_lng'],
  );
  if (pickup == null || dropoff == null) return 0;

  final points = <GeoPoint>[pickup];
  if (details['extra_stops'] is List) {
    for (final s in (details['extra_stops'] as List).whereType<Map>()) {
      final pt = _parseUtilityPoint(s['lat'], s['lng']);
      if (pt != null) points.add(pt);
    }
  }
  points.add(dropoff);
  if (details['is_round_trip'] == true) {
    points.add(pickup);
  }

  var meters = 0.0;
  for (var i = 0; i < points.length - 1; i++) {
    meters += GeoMath.distanceMeters(points[i], points[i + 1]) * 1.28;
  }
  return meters.round();
}

/// Customer shipping spend, distance, and EV green-delivery insights computed
/// strictly from real loaded cloud orders.
class CustomerDeliveryInsights {
  const CustomerDeliveryInsights({
    required this.totalOrders,
    required this.activeOrders,
    required this.deliveredOrders,
    required this.evOrders,
    required this.totalShippingSpendVnd,
    required this.estimatedDistanceKm,
    required this.co2SavedGrams,
  });

  final int totalOrders;
  final int activeOrders;
  final int deliveredOrders;
  final int evOrders;
  final int totalShippingSpendVnd;
  final double estimatedDistanceKm;
  final double co2SavedGrams;
}

CustomerDeliveryInsights summarizeCustomerDeliveryInsights(
  List<Map<String, dynamic>> orders,
) {
  const activeStatuses = {
    'searching',
    'accepted',
    'arrivingPickup',
    'inTransit',
    'returning',
  };
  var activeOrders = 0;
  var deliveredOrders = 0;
  var evOrders = 0;
  var totalSpend = 0;
  var totalMeters = 0;
  var co2Saved = 0.0;

  for (final order in orders) {
    final status = '${order['status'] ?? ''}';
    if (activeStatuses.contains(status)) {
      activeOrders++;
    } else if (status == 'delivered') {
      deliveredOrders++;
    }

    if (status == 'cancelled') continue;

    if (status != 'returned') {
      totalSpend += cloudOrderPayableFee(order);
    }

    final details = order['details'] is Map
        ? order['details'] as Map
        : const <String, dynamic>{};
    final vehicle = VehicleClass.resolve(
      vehicleType: details['vehicle_type'] ?? order['vehicle_type'],
      serviceType: details['service_type'] ?? order['service_type'],
      preferEv: details['prefer_ev'] == true,
    );
    final routeMeters = _parseOrderRouteMeters(order);
    totalMeters += routeMeters;
    final isEv =
        vehicle == VehicleClass.evScooter || details['prefer_ev'] == true;
    if (isEv) {
      evOrders++;
      co2Saved += GeoMath.estimateEvCo2SavedGrams(routeMeters);
    }
  }

  return CustomerDeliveryInsights(
    totalOrders: orders.length,
    activeOrders: activeOrders,
    deliveredOrders: deliveredOrders,
    evOrders: evOrders,
    totalShippingSpendVnd: totalSpend,
    estimatedDistanceKm: totalMeters / 1000.0,
    co2SavedGrams: co2Saved,
  );
}

/// Recurring pickup/dropoff route extracted from a customer's real order history.
class FrequentDeliveryRoute {
  const FrequentDeliveryRoute({
    required this.routeKey,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.recipientName,
    required this.vehicle,
    required this.orderCount,
    required this.sampleOrder,
  });

  final String routeKey;
  final String pickupAddress;
  final String dropoffAddress;
  final String recipientName;
  final VehicleClass vehicle;
  final int orderCount;
  final Map<String, dynamic> sampleOrder;
}

class _RouteAcc {
  _RouteAcc({
    required this.routeKey,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.recipientName,
    required this.sampleOrder,
    required this.latestAt,
  });

  final String routeKey;
  final String pickupAddress;
  final String dropoffAddress;
  final String recipientName;
  Map<String, dynamic> sampleOrder;
  DateTime latestAt;
  int count = 0;
}

/// Extracts top frequent routes ordered by repetition count, then recency.
List<FrequentDeliveryRoute> extractFrequentRoutes(
  List<Map<String, dynamic>> orders, {
  int limit = 3,
}) {
  if (limit <= 0) return const [];
  final buckets = <String, _RouteAcc>{};

  for (final order in orders) {
    final details = order['details'] is Map
        ? order['details'] as Map
        : const <String, dynamic>{};
    final pickup = '${details['pickup_address'] ?? ''}'.trim();
    final dropoff = '${details['dropoff_address'] ?? ''}'.trim();
    if (pickup.isEmpty ||
        dropoff.isEmpty ||
        pickup == 'Chưa có thông tin' ||
        dropoff == 'Chưa có thông tin') {
      continue;
    }
    final recPhone = '${details['recipient_phone'] ?? ''}'.trim();
    final recName = '${details['recipient_name'] ?? 'Người nhận'}'.trim();
    final key = '${pickup.toLowerCase()}|${dropoff.toLowerCase()}|$recPhone';
    final createdAt =
        DateTime.tryParse('${order['created_at'] ?? ''}')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    final existing = buckets[key];
    if (existing == null) {
      buckets[key] = _RouteAcc(
        routeKey: key,
        pickupAddress: pickup,
        dropoffAddress: dropoff,
        recipientName: recName.isEmpty ? 'Người nhận' : recName,
        sampleOrder: order,
        latestAt: createdAt,
      )..count = 1;
    } else {
      existing.count++;
      if (createdAt.isAfter(existing.latestAt)) {
        existing.latestAt = createdAt;
        existing.sampleOrder = order;
      }
    }
  }

  final sorted = buckets.values.toList()
    ..sort((a, b) {
      final cmp = b.count.compareTo(a.count);
      if (cmp != 0) return cmp;
      return b.latestAt.compareTo(a.latestAt);
    });

  return [
    for (final item in sorted.take(limit))
      FrequentDeliveryRoute(
        routeKey: item.routeKey,
        pickupAddress: item.pickupAddress,
        dropoffAddress: item.dropoffAddress,
        recipientName: item.recipientName,
        vehicle: VehicleClass.resolve(
          vehicleType:
              (item.sampleOrder['details'] as Map?)?['vehicle_type'] ??
              item.sampleOrder['vehicle_type'],
          serviceType:
              (item.sampleOrder['details'] as Map?)?['service_type'] ??
              item.sampleOrder['service_type'],
          preferEv: (item.sampleOrder['details'] as Map?)?['prefer_ev'] == true,
        ),
        orderCount: item.count,
        sampleOrder: item.sampleOrder,
      ),
  ];
}

/// Fleet SLA, EV adoption, and 5-vehicle revenue breakdown for operator radar.
class AdminFleetOperationsMetrics {
  const AdminFleetOperationsMetrics({
    required this.total,
    required this.delivered,
    required this.failedOrReturned,
    required this.evOrders,
    required this.completionRatePct,
    required this.failureReturnRatePct,
    required this.evAdoptionPct,
    required this.totalEvCo2SavedGrams,
    required this.revenueByVehicle,
    required this.staleSearchingIds,
  });

  final int total;
  final int delivered;
  final int failedOrReturned;
  final int evOrders;
  final double completionRatePct;
  final double failureReturnRatePct;
  final double evAdoptionPct;
  final double totalEvCo2SavedGrams;
  final Map<String, int> revenueByVehicle;
  final Set<String> staleSearchingIds;
}

/// Computes fleet SLA, EV sustainability, and 5-vehicle revenue breakdown.
AdminFleetOperationsMetrics computeAdminFleetMetrics(
  List<Map<String, dynamic>> orders, {
  DateTime? now,
}) {
  final refTime = (now ?? DateTime.now()).toUtc();
  final revenueByVehicle = <String, int>{
    for (final vc in VehicleClass.all) vc.id: 0,
  };
  final staleSearchingIds = <String>{};

  var delivered = 0;
  var failedOrReturned = 0;
  var evOrders = 0;
  var totalEvCo2SavedGrams = 0.0;

  for (final order in orders) {
    final status = '${order['status'] ?? ''}';
    final orderId = '${order['id'] ?? ''}';
    final details = order['details'] is Map
        ? order['details'] as Map
        : const <String, dynamic>{};
    final vehicle = VehicleClass.resolve(
      vehicleType: details['vehicle_type'] ?? order['vehicle_type'],
      serviceType: details['service_type'] ?? order['service_type'],
      preferEv: details['prefer_ev'] == true,
    );

    if (status == 'delivered') {
      delivered++;
    } else if (status == 'failed' ||
        status == 'returning' ||
        status == 'returned') {
      failedOrReturned++;
    } else if (status == 'searching') {
      final createdAt = DateTime.tryParse('${order['created_at'] ?? ''}')
          ?.toUtc();
      if (createdAt != null &&
          refTime.difference(createdAt) > const Duration(minutes: 15) &&
          orderId.isNotEmpty) {
        staleSearchingIds.add(orderId);
      }
    }

    final isEv =
        vehicle == VehicleClass.evScooter || details['prefer_ev'] == true;
    if (isEv) {
      evOrders++;
      if (status != 'cancelled') {
        totalEvCo2SavedGrams += GeoMath.estimateEvCo2SavedGrams(
          _parseOrderRouteMeters(order),
        );
      }
    }

    if (status != 'cancelled') {
      revenueByVehicle[vehicle.id] =
          (revenueByVehicle[vehicle.id] ?? 0) + cloudOrderPayableFee(order);
    }
  }

  final total = orders.length;
  return AdminFleetOperationsMetrics(
    total: total,
    delivered: delivered,
    failedOrReturned: failedOrReturned,
    evOrders: evOrders,
    completionRatePct: total == 0 ? 0.0 : (delivered / total) * 100.0,
    failureReturnRatePct: total == 0 ? 0.0 : (failedOrReturned / total) * 100.0,
    evAdoptionPct: total == 0 ? 0.0 : (evOrders / total) * 100.0,
    totalEvCo2SavedGrams: totalEvCo2SavedGrams,
    revenueByVehicle: revenueByVehicle,
    staleSearchingIds: staleSearchingIds,
  );
}
