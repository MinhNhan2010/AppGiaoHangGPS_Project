import '../entities/geo_point.dart';
import '../entities/order_entity.dart';
import '../enums/order_status.dart';

abstract interface class IOrderRepository {
  Future<OrderEntity> createOrder(OrderEntity order);

  Future<List<OrderEntity>> getCustomerOrders(String customerId);

  Future<OrderEntity> updateOrderStatus({
    required String orderId,
    required OrderStatus nextStatus,
    String? podImageUrl,
    String? podOtpCode,
  });

  Stream<GeoPoint> watchDriverLocationForOrder(String orderId);
}
