import '../../core/config/env_config.dart';
import '../../core/error/app_exception.dart';
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
        payload: {
          'table': 'orders',
          'record': order.toMap(),
        },
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
      final cached = await localOfflineDatasource.getCachedOrders(customerId);
      if (cached.isNotEmpty) return cached;
      final sqlRows = await localOfflineDatasource.queryRows(
        'orders',
        orderBy: 'created_at_ms DESC',
      );
      return sqlRows
          .map(OrderEntity.fromMap)
          .where((o) => customerId.isEmpty || o.customerId == customerId)
          .toList();
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
    OrderEntity? existing =
        cachedList.where((o) => o.id == orderId).firstOrNull;
    if (existing == null) {
      final sqlRows = await localOfflineDatasource.queryRows(
        'orders',
        where: 'id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      if (sqlRows.isNotEmpty) {
        existing = OrderEntity.fromMap(sqlRows.first);
      }
    }
    final now = DateTime.now();
    final updatedLocal = existing?.transitionTo(
      nextStatus,
      podImageUrl: podImageUrl,
      deliveredAt: nextStatus == OrderStatus.delivered ? now : null,
    );

    if (updatedLocal != null) {
      await localOfflineDatasource.cacheOrder(updatedLocal);
    }
    await localOfflineDatasource.updateRows(
      'orders',
      {
        'status': nextStatus.name,
        'pod_image_note': ?podImageUrl,
        if (nextStatus == OrderStatus.delivered) ...{
          'payment_status': 'PAID',
          'delivered_at_ms': now.millisecondsSinceEpoch,
        },
      },
      where: 'id = ?',
      whereArgs: [orderId],
    );

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
          'table': 'orders',
          'order_id': orderId,
          'status': nextStatus.dbCode,
          'pod_image_url': podImageUrl,
          'pod_otp_code': podOtpCode,
          if (updatedLocal != null) 'record': updatedLocal.toMap(),
        },
      );
      if (updatedLocal != null) return updatedLocal;
      rethrow;
    }
  }

  @override
  Stream<GeoPoint> watchDriverLocationForOrder(String orderId) {
    if (EnvConfig.isSupabaseConfigured) {
      return remoteDatasource.subscribeToOrderTrackingStream(orderId);
    }
    return _watchLocalSqliteTrackingLogs(orderId);
  }

  Stream<GeoPoint> _watchLocalSqliteTrackingLogs(String orderId) async* {
    final rows = await localOfflineDatasource.queryRows(
      'order_tracking_logs',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const DatabaseException(
        message: 'Chưa có tín hiệu GPS từ tài xế cho đơn hàng này.',
      );
    }
    final latest = rows.first;
    yield GeoPoint(
      latitude: (latest['latitude'] as num).toDouble(),
      longitude: (latest['longitude'] as num).toDouble(),
    );
  }
}
