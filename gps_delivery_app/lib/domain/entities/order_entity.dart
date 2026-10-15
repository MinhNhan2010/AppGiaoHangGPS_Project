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
  final String pickupAddress;
  final GeoPoint pickupLocation;
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

  const OrderEntity({
    required this.id,
    required this.trackingCode,
    required this.customerId,
    this.driverId,
    this.merchantId,
    required this.serviceType,
    required this.pickupAddress,
    required this.pickupLocation,
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
  });

  OrderEntity transitionTo(OrderStatus nextStatus, {String? podImageUrl}) {
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
      pickupAddress: pickupAddress,
      pickupLocation: pickupLocation,
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
      paymentStatus: paymentStatus,
      status: nextStatus,
      podImageUrl: podImageUrl ?? this.podImageUrl,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'tracking_code': trackingCode,
        'customer_id': customerId,
        'driver_id': driverId,
        'merchant_id': merchantId,
        'service_type': serviceType.dbCode,
        'pickup_address': pickupAddress,
        'pickup_location': pickupLocation.toGeoJson(),
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
        'created_at': createdAt.toIso8601String(),
      };

  factory OrderEntity.fromMap(Map<String, dynamic> map) {
    return OrderEntity(
      id: map['id'] as String,
      trackingCode: map['tracking_code'] as String,
      customerId: map['customer_id'] as String,
      driverId: map['driver_id'] as String?,
      merchantId: map['merchant_id'] as String?,
      serviceType:
          DeliveryServiceType.fromDbCode(map['service_type'] as String),
      pickupAddress: map['pickup_address'] as String,
      pickupLocation: GeoPoint.fromGeoJson(
        map['pickup_location'] as Map<String, dynamic>,
      ),
      dropoffAddress: map['dropoff_address'] as String,
      dropoffLocation: GeoPoint.fromGeoJson(
        map['dropoff_location'] as Map<String, dynamic>,
      ),
      distanceMeters: (map['distance_meters'] as num).toInt(),
      durationSeconds: (map['duration_seconds'] as num).toInt(),
      routePolyline: map['route_polyline'] as String?,
      deliveryFee: (map['delivery_fee'] as num).toDouble(),
      surchargeFee: (map['surcharge_fee'] as num? ?? 0).toDouble(),
      discountAmount: (map['discount_amount'] as num? ?? 0).toDouble(),
      codAmount: (map['cod_amount'] as num? ?? 0).toDouble(),
      totalAmount: (map['total_amount'] as num).toDouble(),
      paymentMethod: map['payment_method'] as String,
      paymentStatus: map['payment_status'] as String? ?? 'UNPAID',
      status: OrderStatus.fromDbCode(map['status'] as String),
      podImageUrl: map['pod_image_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, trackingCode, status, totalAmount, driverId];
}
