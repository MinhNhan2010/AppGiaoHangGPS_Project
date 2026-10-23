import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/env_config.dart';
import '../../../core/error/app_exception.dart';
import '../../../domain/entities/driver_entity.dart';
import '../../../domain/entities/geo_point.dart';
import '../../../domain/entities/order_entity.dart';
import '../../../domain/enums/order_status.dart';

/// Datasource kết nối trực tiếp tới cơ sở dữ liệu PostgreSQL + PostGIS trên Supabase
class SupabasePostgisDatasource {
  SupabaseClient _requireClient() {
    if (!EnvConfig.isSupabaseConfigured) {
      throw const NetworkSyncException(
        message:
            'Chưa cấu hình SUPABASE_URL / SUPABASE_ANON_KEY. Chuyển sang chế độ lưu trữ SQLite Offline.',
      );
    }
    return Supabase.instance.client;
  }

  /// Truy vấn tổng quát cho bất kỳ bảng nào trong cơ sở dữ liệu
  Future<List<Map<String, dynamic>>> fetchTableRecords(
    String tableName, {
    int limit = 100,
  }) async {
    final client = _requireClient();
    final rows = await client.from(tableName).select().limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Upsert bản ghi bất kỳ vào 16 bảng (`users`, `saved_addresses`, `merchant_profiles`,
  /// `pickup_points`, `pricing_configs`, `vouchers`, `payments`, `wallets`,
  /// `wallet_transactions`, `withdrawal_requests`, `order_disputes`, `driver_reviews`,
  /// `geofence_zones`, `notifications`, `orders`, `drivers`)
  Future<Map<String, dynamic>> upsertTableRecord(
    String tableName,
    Map<String, dynamic> payload,
  ) async {
    final client = _requireClient();
    final res =
        await client.from(tableName).upsert(payload).select().single();
    return res;
  }

  Future<OrderEntity> insertOrder(OrderEntity order) async {
    final client = _requireClient();
    final response = await client
        .from('orders')
        .insert(order.toMap())
        .select()
        .single();
    return OrderEntity.fromMap(response);
  }

  Future<List<OrderEntity>> fetchCustomerOrders(String customerId) async {
    final client = _requireClient();
    final rows = await client
        .from('orders')
        .select()
        .eq('customer_id', customerId)
        .order('created_at', ascending: false);

    return rows.map((r) => OrderEntity.fromMap(r)).toList();
  }

  Future<OrderEntity> updateOrderStatus({
    required String orderId,
    required OrderStatus nextStatus,
    String? podImageUrl,
    String? podOtpCode,
  }) async {
    final client = _requireClient();
    final payload = <String, dynamic>{
      'status': nextStatus.dbCode,
      'pod_image_url': ?podImageUrl,
      'pod_otp_code': ?podOtpCode,
      if (nextStatus == OrderStatus.delivered)
        'delivered_at': DateTime.now().toIso8601String(),
    };

    final response = await client
        .from('orders')
        .update(payload)
        .eq('id', orderId)
        .select()
        .single();
    return OrderEntity.fromMap(response);
  }

  Future<void> updateDriverOnlineState({
    required String driverId,
    required bool isOnline,
  }) async {
    final client = _requireClient();
    await client
        .from('drivers')
        .update({'is_online': isOnline})
        .eq('id', driverId);
  }

  Future<void> insertDriverTrackingLog({
    required String driverId,
    String? orderId,
    required GeoPoint smoothedLocation,
    required double speedKmh,
    required double bearing,
    required bool isMockLocation,
  }) async {
    final client = _requireClient();
    await client.from('drivers').update({
      'current_location': smoothedLocation.toGeoJson(),
      'current_bearing': bearing,
    }).eq('id', driverId);

    if (orderId != null) {
      await client.from('order_tracking_logs').insert({
        'order_id': orderId,
        'driver_id': driverId,
        'location': smoothedLocation.toGeoJson(),
        'speed': speedKmh,
        'bearing': bearing,
        'is_mock_location': isMockLocation,
      });
    }
  }

  Future<List<DriverEntity>> fetchOnlineApprovedDrivers() async {
    final client = _requireClient();
    final rows = await client
        .from('drivers')
        .select()
        .eq('is_online', true)
        .eq('approval_status', 'APPROVED');

    return rows.map((r) => DriverEntity.fromMap(r)).toList();
  }

  Stream<GeoPoint> subscribeToOrderTrackingStream(String orderId) {
    final client = _requireClient();
    return client
        .from('order_tracking_logs')
        .stream(primaryKey: ['id'])
        .eq('order_id', orderId)
        .order('recorded_at', ascending: false)
        .limit(1)
        .map((rows) {
          if (rows.isEmpty) {
            throw const DatabaseException(
              message: 'Chưa có tín hiệu GPS từ tài xế cho đơn hàng này.',
            );
          }
          return GeoPoint.fromGeoJson(
            rows.first['location'] as Map<String, dynamic>,
          );
        });
  }
}
