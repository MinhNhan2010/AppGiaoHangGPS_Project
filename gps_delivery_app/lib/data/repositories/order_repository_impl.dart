import '../../domain/entities/geo_point.dart';
import '../../domain/entities/order_entity.dart';
import '../../domain/enums/order_status.dart';
import '../../domain/repositories/i_order_repository.dart';
import '../datasources/local/sqlite_offline_queue_datasource.dart';
import '../datasources/remote/supabase_postgis_datasource.dart';

class OrderRepositoryImpl implements IOrderRepository {
  final SupabasePostgisDatasource remoteDatasource;
  final SqliteOfflineQueueDatasource localOfflineDatasource;

  const OrderRepositoryImpl({
    required this.remoteDatasource,
    required this.localOfflineDatasource,
  });

  @override
  Future<OrderEntity> createOrder(OrderEntity order) async {
    await localOfflineDatasource.cacheOrder(order);
    try {
      final created = await remoteDatasource.insertOrder(order);
      await localOfflineDatasource.cacheOrder(created);
      return created;
    } catch (_) {
      await localOfflineDatasource.enqueueAction(
        actionType: 'CREATE_ORDER',
        payload: order.toMap(),
      );
      return order;
    }
  }

  @override
  Future<List<OrderEntity>> getCustomerOrders(String customerId) async {
    try {
      final remoteOrders =
          await remoteDatasource.fetchCustomerOrders(customerId);
      for (final o in remoteOrders) {
        await localOfflineDatasource.cacheOrder(o);
      }
      return remoteOrders;
    } catch (_) {
      return localOfflineDatasource.getCachedOrders(customerId);
    }
  }

  @override
  Future<OrderEntity> updateOrderStatus({
    required String orderId,
    required OrderStatus nextStatus,
    String? podImageUrl,
    String? podOtpCode,
  }) async {
    final cachedList = await localOfflineDatasource.getCachedOrders();
    final existing = cachedList.where((o) => o.id == orderId).firstOrNull;
    final updatedLocal = existing?.transitionTo(
      nextStatus,
      podImageUrl: podImageUrl,
    );

    if (updatedLocal != null) {
      await localOfflineDatasource.cacheOrder(updatedLocal);
    }

    try {
      return await remoteDatasource.updateOrderStatus(
        orderId: orderId,
        nextStatus: nextStatus,
        podImageUrl: podImageUrl,
        podOtpCode: podOtpCode,
      );
    } catch (_) {
      await localOfflineDatasource.enqueueAction(
        actionType: 'UPDATE_ORDER_STATUS',
        payload: {
          'order_id': orderId,
          'status': nextStatus.dbCode,
          'pod_image_url': podImageUrl,
          'pod_otp_code': podOtpCode,
        },
      );
      if (updatedLocal != null) return updatedLocal;
      rethrow;
    }
  }

  @override
  Stream<GeoPoint> watchDriverLocationForOrder(String orderId) {
    return remoteDatasource.subscribeToOrderTrackingStream(orderId);
  }
}
