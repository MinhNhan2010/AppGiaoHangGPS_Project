part of 'app_state_store.dart';

extension AppStateDemoCleanup on AppStateStore {
  /// Archive only recognizable records shipped by older versions of the app.
  Future<void> removeLegacyDemoRecords() async {
    final migrations = await _sqliteDb.getEntityRecords('data_migrations');
    if (migrations.any((row) => row['name'] == 'remove_demo_v1')) return;

    const samples = <String, List<Map<String, Object?>>>{
      'users': [
        {
          'id': 'USR-01',
          'phone': '0912345678',
          'email': 'thu.ha@gmail.com',
          'created_at': '2026-10-01',
        },
        {
          'id': 'USR-02',
          'phone': '0987654321',
          'email': 'nam.driver@giaohanggps.vn',
          'created_at': '2026-10-01',
        },
        {
          'id': 'USR-03',
          'phone': '0909112233',
          'email': 'contact@gomsuviet.vn',
          'created_at': '2026-10-01',
        },
        {
          'id': 'USR-04',
          'phone': '0900999999',
          'email': 'admin@gomau.vn',
          'created_at': '2026-10-01',
        },
      ],
      'orders': [
        {
          'id': 'ORD-01',
          'tracking_code': '#DH123456',
          'recipient_phone': '0903882145',
        },
        {
          'id': 'ORD-02',
          'tracking_code': '#DH789101',
          'customer_name': 'Nguyễn Thu Hà',
        },
        {
          'id': 'ORD-03',
          'tracking_code': '#DH556778',
          'customer_name': 'Nguyễn Thu Hà',
        },
        {
          'id': 'ORD-B2B-01',
          'tracking_code': '#DH301201',
          'recipient_name': 'Trần Hoàng Minh',
        },
        {
          'id': 'ORD-B2B-02',
          'tracking_code': '#DH301202',
          'recipient_name': 'Võ Thị Ngọc Lan',
        },
        {
          'id': 'ORD-B2B-03',
          'tracking_code': '#DH301203',
          'recipient_name': 'Đinh Quốc Khánh',
        },
        {
          'id': 'ORD-B2B-04',
          'tracking_code': '#DH301204',
          'customer_name': 'Cửa hàng Gốm Sứ Việt',
        },
      ],
      'drivers': [
        {
          'id': 'DV10928',
          'phone': '0987654321',
          'citizen_id': '079095012345',
          'license_plate': '59-P1 123.45',
        },
        {
          'id': 'DV10929',
          'phone': '0938112233',
          'citizen_id': '079092054321',
          'license_plate': '59-P2 678.90',
        },
        {
          'id': 'DV10930',
          'phone': '0945667788',
          'citizen_id': '079196098765',
          'license_plate': '59-X1 456.78',
        },
        {
          'id': 'DV10931',
          'phone': '0939887766',
          'citizen_id': '079094011223',
          'license_plate': '59-T1 889.90',
        },
      ],
      'merchants': [
        {
          'id': 'MER-01',
          'owner_phone': '0909112233',
          'tax_code': '0101234567-001',
        },
        {'id': 'MER-02', 'owner_phone': '0977889900', 'tax_code': '0316549871'},
      ],
      'user_addresses': [
        {
          'id': 'ADDR-01',
          'full_address': '12 Nguyễn Huệ, P. Bến Nghé, Q.1, TP. HCM',
        },
        {
          'id': 'ADDR-02',
          'full_address':
              'Bitexco Financial Tower, 45 Lê Lợi, P. Bến Nghé, Q.1, TP. HCM',
        },
        {
          'id': 'ADDR-03',
          'full_address':
              '18A/24 Nguyễn Thị Minh Khai, P. Đa Kao, Q.1, TP. HCM',
        },
      ],
      'merchant_pickup_points': [
        {
          'id': 'WH-01',
          'merchant_id': 'MER-01',
          'full_address': '123 Đường Lê Lợi, Phường Bến Nghé, Quận 1, TP. HCM',
        },
        {
          'id': 'WH-02',
          'merchant_id': 'MER-01',
          'full_address':
              '456 Đường Nguyễn Đình Chiểu, Phường 6, Quận 3, TP. HCM',
        },
      ],
      'vouchers': [
        {'code': 'PROMO20K', 'title': 'GIẢM 20.000Đ PHÍ VẬN CHUYỂN'},
        {'code': 'FREESHIP20P', 'title': 'GIẢM 20% ĐƠN ĐẦU TIÊN'},
        {'code': 'UUDAI30K', 'title': 'HỖ TRỢ PHÍ GIAO HÀNG 30.000Đ'},
        {'code': 'GHN-BACKTOSCHOOL', 'title': 'GIẢM 10% PHÍ GIAO HÀNG'},
      ],
      'wallets_and_transactions': [
        {'id': 'WD-01', 'owner_id': 'DV10928', 'amount': 5000000},
        {'id': 'WD-02', 'owner_id': 'DV10929', 'amount': 3000000},
        {'id': 'WD-03', 'owner_id': 'MER-01', 'amount': 1150000},
        {'id': 'WD-04', 'owner_id': 'MER-01', 'amount': 1850000},
      ],
      'cod_reconciliations': [
        {
          'id': 'REC-MER-01',
          'merchant_id': 'MER-01',
          'total_cod_collected': 5800000,
        },
      ],
      'incidents_and_complaints': [
        {
          'ticket_code': 'KN-001',
          'order_id': '#DH789101',
          'issue_type': 'Giao hàng chậm',
        },
        {
          'ticket_code': 'KN-002',
          'order_id': '#DH301201',
          'issue_type': 'Shop KN: Hàng hư hỏng',
        },
        {
          'ticket_code': 'KN-003',
          'order_id': '#DH301203',
          'issue_type': 'Thiếu hàng',
        },
      ],
      'chat_messages_and_notifications': [
        {
          'id': 'MSG-01',
          'order_id': '#DH123456',
          'sender_name': 'Nguyễn Thu Hà',
        },
        {
          'id': 'MSG-02',
          'order_id': '#DH123456',
          'sender_name': 'Nguyễn Văn Nam',
        },
        {
          'id': 'MSG-03',
          'order_id': '#DH123456',
          'sender_name': 'Nguyễn Thu Hà',
        },
        {'id': 'NOTI-01', 'title': 'Đơn hàng #DH789101 đã giao thành công'},
        {
          'id': 'NOTI-02',
          'title': 'Tài xế Nguyễn Văn Nam đang vận chuyển đơn #DH123456',
        },
        {
          'id': 'NOTI-03',
          'title': 'Mã PROMO20K giảm 20.000đ phí giao hàng hôm nay',
        },
      ],
      'geofence_zones': [
        {'id': 'GEO-01', 'zone_name': 'Vùng trung tâm (Quận 1 & Quận 3)'},
        {
          'id': 'GEO-02',
          'zone_name': 'Vùng phụ phí cao (Giờ cao điểm / Khu ngập)',
        },
        {'id': 'GEO-03', 'zone_name': 'Vùng hạn chế (Cấm tải giờ cao điểm)'},
      ],
    };

    final removed = <String, Set<String>>{};
    final removedUserPhones = <String>{};
    Future<void> archiveRow(
      String table,
      Map<String, Object?> row,
      String key,
    ) async {
      final recordId = row[key].toString();
      await _sqliteDb.upsertEntityRecord(
        tableName: 'archived_demo_v1',
        recordId: '$table:$recordId',
        payload: {'table': table, 'record': row},
      );
      await _sqliteDb.deleteRows(
        table,
        where: '$key = ?',
        whereArgs: [row[key]],
      );
    }

    for (final table in samples.entries) {
      for (final signature in table.value) {
        final rows = await _sqliteDb.queryRows(
          table.key,
          where: signature.keys.map((key) => '$key = ?').join(' AND '),
          whereArgs: signature.values.toList(),
        );
        for (final row in rows) {
          final key = signature.keys.first;
          final recordId = row[key].toString();
          (removed[table.key] ??= {}).add(recordId);
          if (table.key == 'users') {
            removedUserPhones.add(row['phone'].toString());
          }
          await archiveRow(table.key, row, key);
        }
      }
    }
    const metadataOwners = {
      'driver_meta': 'drivers',
      'verified_driver_locations': 'drivers',
      'merchant_meta': 'merchants',
      'warehouse_meta': 'merchant_pickup_points',
      'withdrawal_meta': 'wallets_and_transactions',
      'voucher_meta': 'vouchers',
      'cod_reconciliation_meta': 'cod_reconciliations',
      'complaint_meta': 'incidents_and_complaints',
    };
    for (final row in await _sqliteDb.queryRows('local_relational_entities')) {
      final table = row['table_name'].toString();
      final id = row['record_id'].toString();
      if (removed[metadataOwners[table]]?.contains(id) != true &&
          !(table == 'user_preferences' && removedUserPhones.contains(id))) {
        continue;
      }
      await _sqliteDb.upsertEntityRecord(
        tableName: 'archived_demo_v1',
        recordId: 'metadata:$table:$id',
        payload: {'table': 'local_relational_entities', 'record': row},
      );
      await _sqliteDb.deleteRows(
        'local_relational_entities',
        where: 'table_name = ? AND record_id = ?',
        whereArgs: [table, id],
      );
    }
    for (final table in ['order_tracking_logs', 'cached_active_orders']) {
      for (final row in await _sqliteDb.queryRows(table)) {
        final orderId =
            row[table == 'cached_active_orders' ? 'id' : 'order_id'];
        if (removed['orders']?.contains(orderId?.toString()) == true ||
            (table == 'order_tracking_logs' &&
                removed['drivers']?.contains(row['driver_id']?.toString()) ==
                    true)) {
          await archiveRow(table, row, 'id');
        }
      }
    }
    for (final row in await _sqliteDb.queryRows('local_sync_queue')) {
      final payload = jsonDecode(row['payload_json'].toString());
      if (payload is! Map) continue;
      final record = payload['record'];
      final table = payload['table']?.toString();
      final key = samples[table]?.first.keys.first;
      final refersToRemovedRecord =
          record is Map &&
          removed[table]?.contains(record[key]?.toString()) == true;
      if (refersToRemovedRecord ||
          removed['orders']?.contains(payload['order_id']?.toString()) ==
              true ||
          removed['drivers']?.contains(payload['driver_id']?.toString()) ==
              true) {
        await archiveRow('local_sync_queue', row, 'id');
      }
    }
    await _sqliteDb.upsertEntityRecord(
      tableName: 'data_migrations',
      recordId: 'remove_demo_v1',
      payload: {
        'name': 'remove_demo_v1',
        'completedAt': DateTime.now().toIso8601String(),
      },
    );
  }
}
