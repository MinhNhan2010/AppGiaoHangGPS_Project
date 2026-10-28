import 'package:equatable/equatable.dart';

import '../../core/error/app_exception.dart';
import '../enums/order_status.dart';
import '../enums/service_type.dart';
import 'geo_point.dart';

class OrderEntity extends Equatable {
  final String id;
  final String trackingCode;
  final String customerId;
  final String? driverId;
  final String? merchantId;
  final DeliveryServiceType serviceType;
  final String senderName;
  final String senderPhone;
  final String pickupAddress;
  final GeoPoint pickupLocation;
  final String recipientName;
  final String recipientPhone;
  final String dropoffAddress;
  final GeoPoint dropoffLocation;
  final int distanceMeters;
  final int durationSeconds;
  final String? routePolyline;
  final double deliveryFee;
  final double surchargeFee;
  final double discountAmount;
  final double codAmount;
  final double totalAmount;
  final String paymentMethod;
  final String paymentStatus;
  final OrderStatus status;
  final String? podImageUrl;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final bool preferEcoEv;
  final double declaredValueVnd;
  final double insuranceFee;
  final bool isRoundTrip;
  final int extraStopCount;
  final String? batchGroupId;
  final double co2SavedGrams;
  final bool greenFundContributed;
  final String? publicTrackingToken;

  const OrderEntity({
    required this.id,
    required this.trackingCode,
    required this.customerId,
    this.driverId,
    this.merchantId,
    required this.serviceType,
    this.senderName = '',
    this.senderPhone = '',
    required this.pickupAddress,
    required this.pickupLocation,
    this.recipientName = '',
    this.recipientPhone = '',
    required this.dropoffAddress,
    required this.dropoffLocation,
    required this.distanceMeters,
    required this.durationSeconds,
    this.routePolyline,
    required this.deliveryFee,
    this.surchargeFee = 0.0,
    this.discountAmount = 0.0,
    this.codAmount = 0.0,
    required this.totalAmount,
    required this.paymentMethod,
    this.paymentStatus = 'UNPAID',
    required this.status,
    this.podImageUrl,
    required this.createdAt,
    this.deliveredAt,
    this.preferEcoEv = false,
    this.declaredValueVnd = 0.0,
    this.insuranceFee = 0.0,
    this.isRoundTrip = false,
    this.extraStopCount = 0,
    this.batchGroupId,
    this.co2SavedGrams = 0.0,
    this.greenFundContributed = false,
    this.publicTrackingToken,
  });

  OrderEntity transitionTo(
    OrderStatus nextStatus, {
    String? podImageUrl,
    DateTime? deliveredAt,
  }) {
    if (!status.canTransitionTo(nextStatus)) {
      throw InvalidOrderStateTransitionException(
        fromState: status.dbCode,
        toState: nextStatus.dbCode,
      );
    }
    return OrderEntity(
      id: id,
      trackingCode: trackingCode,
      customerId: customerId,
      driverId: driverId,
      merchantId: merchantId,
      serviceType: serviceType,
      senderName: senderName,
      senderPhone: senderPhone,
      pickupAddress: pickupAddress,
      pickupLocation: pickupLocation,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      dropoffAddress: dropoffAddress,
      dropoffLocation: dropoffLocation,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      routePolyline: routePolyline,
      deliveryFee: deliveryFee,
      surchargeFee: surchargeFee,
      discountAmount: discountAmount,
      codAmount: codAmount,
      totalAmount: totalAmount,
      paymentMethod: paymentMethod,
      paymentStatus: nextStatus == OrderStatus.delivered
          ? 'PAID'
          : paymentStatus,
      status: nextStatus,
      podImageUrl: podImageUrl ?? this.podImageUrl,
      createdAt: createdAt,
      deliveredAt: nextStatus == OrderStatus.delivered
          ? (deliveredAt ?? this.deliveredAt ?? DateTime.now())
          : this.deliveredAt,
      preferEcoEv: preferEcoEv,
      declaredValueVnd: declaredValueVnd,
      insuranceFee: insuranceFee,
      isRoundTrip: isRoundTrip,
      extraStopCount: extraStopCount,
      batchGroupId: batchGroupId,
      co2SavedGrams: co2SavedGrams,
      greenFundContributed: greenFundContributed,
      publicTrackingToken: publicTrackingToken,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'tracking_code': trackingCode,
    'customer_id': customerId,
    'driver_id': driverId,
    'merchant_id': merchantId,
    'service_type': serviceType.dbCode,
    'sender_name': senderName,
    'sender_phone': senderPhone,
    'pickup_address': pickupAddress,
    'pickup_location': pickupLocation.toGeoJson(),
    'recipient_name': recipientName,
    'recipient_phone': recipientPhone,
    'dropoff_address': dropoffAddress,
    'dropoff_location': dropoffLocation.toGeoJson(),
    'distance_meters': distanceMeters,
    'duration_seconds': durationSeconds,
    'route_polyline': routePolyline,
    'delivery_fee': deliveryFee,
    'surcharge_fee': surchargeFee,
    'discount_amount': discountAmount,
    'cod_amount': codAmount,
    'total_amount': totalAmount,
    'payment_method': paymentMethod,
    'payment_status': paymentStatus,
    'status': status.dbCode,
    'pod_image_url': podImageUrl,
    'prefer_eco_ev': preferEcoEv,
    'declared_value_vnd': declaredValueVnd,
    'insurance_fee': insuranceFee,
    'is_round_trip': isRoundTrip,
    'extra_stop_count': extraStopCount,
    'batch_group_id': batchGroupId,
    'co2_saved_grams': co2SavedGrams,
    'green_fund_contributed': greenFundContributed,
    'public_tracking_token': publicTrackingToken,
    'created_at': createdAt.toIso8601String(),
    if (deliveredAt != null) 'delivered_at': deliveredAt!.toIso8601String(),
  };

  static DateTime _parseRequiredDateTime(Object? isoRaw, Object? epochMsRaw) {
    if (isoRaw != null) {
      final parsed = DateTime.tryParse(isoRaw.toString());
      if (parsed != null) return parsed;
    }
    if (epochMsRaw is num) {
      return DateTime.fromMillisecondsSinceEpoch(epochMsRaw.toInt());
    }
    if (epochMsRaw != null) {
      final ms = int.tryParse(epochMsRaw.toString());
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime? _parseOptionalDateTime(Object? isoRaw, Object? epochMsRaw) {
    if (isoRaw != null) {
      final parsed = DateTime.tryParse(isoRaw.toString());
      if (parsed != null) return parsed;
    }
    if (epochMsRaw is num) {
      return DateTime.fromMillisecondsSinceEpoch(epochMsRaw.toInt());
    }
    if (epochMsRaw != null) {
      final ms = int.tryParse(epochMsRaw.toString());
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return null;
  }

  factory OrderEntity.fromMap(Map<String, dynamic> map) {
    final pickupLocation =
        GeoPoint.tryParsePostgis(map['pickup_location']) ??
        _parseCoordinatePair(map['pickup_lat'], map['pickup_lng']);
    final dropoffLocation =
        GeoPoint.tryParsePostgis(map['dropoff_location']) ??
        _parseCoordinatePair(map['dropoff_lat'], map['dropoff_lng']);
    if (pickupLocation == null || dropoffLocation == null) {
      throw const FormatException(
        'Đơn hàng thiếu tọa độ điểm lấy hoặc điểm giao.',
      );
    }
    return OrderEntity(
      id: (map['id'] ?? '').toString(),
      trackingCode: (map['tracking_code'] ?? '').toString(),
      customerId: (map['customer_id'] ?? map['customer_name'] ?? '').toString(),
      driverId: map['driver_id']?.toString(),
      merchantId: map['merchant_id']?.toString(),
      serviceType: DeliveryServiceType.fromDbCode(
        (map['service_type'] ?? 'STANDARD').toString(),
      ),
      senderName: map['sender_name']?.toString() ?? '',
      senderPhone: map['sender_phone']?.toString() ?? '',
      pickupAddress: (map['pickup_address'] ?? '').toString(),
      pickupLocation: pickupLocation,
      recipientName: map['recipient_name']?.toString() ?? '',
      recipientPhone: map['recipient_phone']?.toString() ?? '',
      dropoffAddress: (map['dropoff_address'] ?? '').toString(),
      dropoffLocation: dropoffLocation,
      distanceMeters: (map['distance_meters'] as num? ?? 0).toInt(),
      durationSeconds: (map['duration_seconds'] as num? ?? 0).toInt(),
      routePolyline: map['route_polyline']?.toString(),
      deliveryFee: (map['delivery_fee'] as num? ?? 0).toDouble(),
      surchargeFee: (map['surcharge_fee'] as num? ?? 0).toDouble(),
      discountAmount: (map['discount_amount'] as num? ?? 0).toDouble(),
      codAmount: (map['cod_amount'] as num? ?? 0).toDouble(),
      totalAmount: (map['total_amount'] as num? ?? 0).toDouble(),
      paymentMethod: (map['payment_method'] ?? 'CASH').toString(),
      paymentStatus: (map['payment_status'] ?? 'UNPAID').toString(),
      status: OrderStatus.fromDbCode((map['status'] ?? 'DRAFT').toString()),
      podImageUrl: (map['pod_image_url'] ?? map['pod_image_note'])?.toString(),
      createdAt: _parseRequiredDateTime(
        map['created_at'],
        map['created_at_ms'],
      ),
      deliveredAt: _parseOptionalDateTime(
        map['delivered_at'],
        map['delivered_at_ms'],
      ),
      preferEcoEv: map['prefer_eco_ev'] == true || map['prefer_eco_ev'] == 1,
      declaredValueVnd: (map['declared_value_vnd'] as num? ?? 0.0).toDouble(),
      insuranceFee: (map['insurance_fee'] as num? ?? 0.0).toDouble(),
      isRoundTrip: map['is_round_trip'] == true || map['is_round_trip'] == 1,
      extraStopCount: (map['extra_stop_count'] as num? ?? 0).toInt(),
      batchGroupId: map['batch_group_id']?.toString(),
      co2SavedGrams: (map['co2_saved_grams'] as num? ?? 0.0).toDouble(),
      greenFundContributed: map['green_fund_contributed'] == true ||
          map['green_fund_contributed'] == 1,
      publicTrackingToken: map['public_tracking_token']?.toString(),
    );
  }

  static GeoPoint? _parseCoordinatePair(Object? rawLat, Object? rawLng) {
    final lat = rawLat is num ? rawLat.toDouble() : double.tryParse('$rawLat');
    final lng = rawLng is num ? rawLng.toDouble() : double.tryParse('$rawLng');
    if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) {
      return null;
    }
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return GeoPoint(latitude: lat, longitude: lng);
  }

  @override
  List<Object?> get props => [
    id,
    trackingCode,
    status,
    paymentStatus,
    totalAmount,
    driverId,
    deliveredAt,
  ];
}
