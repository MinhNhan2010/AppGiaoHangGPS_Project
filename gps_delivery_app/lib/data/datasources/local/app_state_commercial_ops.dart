part of 'app_state_store.dart';

extension AppStateCommercialOps on AppStateStore {
  Future<List<Map<String, dynamic>>> orderStopsFor(String orderId) async {
    if (orderId.trim().isEmpty) return const [];
    return _sqliteDb.queryRows(
      'order_stops',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'sequence_no ASC',
    );
  }

  Future<Map<String, dynamic>?> scheduledOrderFor(String orderId) async {
    if (orderId.trim().isEmpty) return null;
    final rows = await _sqliteDb.queryRows(
      'scheduled_orders',
      where: 'order_id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> pendingWebhookDeliveries() {
    return _sqliteDb.queryRows(
      'webhook_deliveries',
      where: 'status = ?',
      whereArgs: ['PENDING'],
      orderBy: 'next_attempt_at_ms ASC',
      limit: 100,
    );
  }

  Future<List<Map<String, dynamic>>> scheduledOrders() {
    return _sqliteDb.queryRows(
      'scheduled_orders',
      orderBy: 'scheduled_at_ms ASC',
      limit: 100,
    );
  }

  Future<List<Map<String, dynamic>>> paymentLedgerEntries() {
    return _sqliteDb.queryRows(
      'payment_ledger',
      orderBy: 'created_at_ms DESC',
      limit: 100,
    );
  }

  Future<List<Map<String, dynamic>>> auditLogEntries() {
    return _sqliteDb.queryRows(
      'audit_logs',
      orderBy: 'created_at_ms DESC',
      limit: 100,
    );
  }

  Future<bool> saveOrderStops({
    required String orderId,
    required List<Map<String, dynamic>> stops,
  }) async {
    if (orderId.trim().isEmpty || stops.isEmpty) return false;
    for (var index = 0; index < stops.length; index++) {
      final stop = stops[index];
      final address = (stop['address'] ?? '').toString().trim();
      final lat = stop['latitude'];
      final lng = stop['longitude'];
      if (address.isEmpty ||
          (lat != null && lat is! num) ||
          (lng != null && lng is! num)) {
        return false;
      }
    }
    await _sqliteDb.deleteRows(
      'order_stops',
      where: 'order_id = ?',
      whereArgs: [orderId],
    );
    for (var index = 0; index < stops.length; index++) {
      final stop = stops[index];
      final stopId = (stop['id'] ?? '${orderId}_STOP_${index + 1}').toString();
      await _sqliteDb.upsertRow('order_stops', {
        'id': stopId,
        'order_id': orderId,
        'sequence_no': index,
        'stop_type': (stop['stopType'] ?? 'DROPOFF').toString(),
        'address': stop['address'].toString().trim(),
        'latitude': stop['latitude'],
        'longitude': stop['longitude'],
        'recipient_name': stop['recipientName'],
        'recipient_phone': stop['recipientPhone'],
        'cod_amount': (stop['codAmount'] as num?)?.toDouble() ?? 0.0,
        'status': (stop['status'] ?? 'PENDING').toString(),
        'note': stop['note'],
        'otp_code': stop['otpCode']?.toString(),
        'pod_note': stop['podNote']?.toString(),
        'completed_at_ms': (stop['completedAtMs'] as num?)?.toInt(),
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
      });
    }
    unawaited(
      recordAuditEvent(
        action: 'SAVE_ORDER_STOPS',
        entityType: 'ORDER',
        entityId: orderId,
        after: {'stopCount': stops.length},
      ),
    );
    return true;
  }

  /// Đánh dấu hoàn thành từng trạm dừng trong lộ trình giao đa điểm / giao khứ hồi 2 chiều
  Future<bool> completeOrderStop({
    required String orderId,
    required int sequenceNo,
    String? otpInput,
    String? podNote,
  }) async {
    if (orderId.trim().isEmpty || sequenceNo < 0) return false;
    final rows = await _sqliteDb.queryRows(
      'order_stops',
      where: 'order_id = ? AND sequence_no = ?',
      whereArgs: [orderId, sequenceNo],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final stopRow = rows.first;
    final expectedOtp = stopRow['otp_code']?.toString().trim() ?? '';
    if (expectedOtp.isNotEmpty &&
        otpInput != null &&
        otpInput.trim().isNotEmpty &&
        otpInput.trim() != expectedOtp) {
      return false;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _sqliteDb.updateRows(
      'order_stops',
      {
        'status': 'COMPLETED',
        'pod_note':
            podNote ?? 'Đã xác nhận hoàn thành điểm dừng #$sequenceNo',
        'completed_at_ms': nowMs,
      },
      where: 'id = ?',
      whereArgs: [stopRow['id']],
    );
    unawaited(
      recordAuditEvent(
        action: 'COMPLETE_ORDER_STOP',
        entityType: 'ORDER_STOP',
        entityId: stopRow['id']?.toString(),
        after: {
          'orderId': orderId,
          'sequenceNo': sequenceNo,
          'completedAtMs': nowMs,
        },
      ),
    );
    _notifyStoreChanged();
    return true;
  }

  Future<bool> scheduleOrder({
    required String orderId,
    required DateTime scheduledAt,
  }) async {
    if (orderId.trim().isEmpty || !scheduledAt.isAfter(DateTime.now())) {
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _sqliteDb.upsertRow('scheduled_orders', {
      'id': '${orderId}_SCHEDULED',
      'order_id': orderId,
      'scheduled_at_ms': scheduledAt.millisecondsSinceEpoch,
      'timezone': 'Asia/Ho_Chi_Minh',
      'status': 'PENDING',
      'last_error': null,
      'created_at_ms': now,
      'updated_at_ms': now,
    });
    unawaited(
      recordAuditEvent(
        action: 'SCHEDULE_ORDER',
        entityType: 'ORDER',
        entityId: orderId,
        after: {'scheduledAt': scheduledAt.toIso8601String()},
      ),
    );
    return true;
  }

  Future<void> recordAuditEvent({
    required String action,
    required String entityType,
    String? entityId,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    String? actorId,
    String? actorRole,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _sqliteDb.upsertRow('audit_logs', {
      'id': '${now}_${action.hashCode.abs()}',
      'actor_id': actorId ?? activeAuthenticatedUser?.id,
      'actor_role': actorRole ?? activeAuthenticatedUser?.roleDbCode,
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'before_json': before == null ? null : jsonEncode(before),
      'after_json': after == null ? null : jsonEncode(after),
      'device_id': null,
      'created_at_ms': now,
    });
  }

  Future<bool> recordLedgerEntry({
    required String ownerType,
    required String direction,
    required String entryType,
    required double amount,
    String? ownerId,
    String? orderId,
    required String idempotencyKey,
    Map<String, dynamic>? metadata,
  }) async {
    if (amount < 0 || idempotencyKey.trim().isEmpty) return false;
    final existing = await _sqliteDb.queryRows(
      'payment_ledger',
      where: 'idempotency_key = ?',
      whereArgs: [idempotencyKey],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;
    await _sqliteDb.upsertRow('payment_ledger', {
      'id': idempotencyKey,
      'owner_id': ownerId,
      'owner_type': ownerType,
      'order_id': orderId,
      'direction': direction,
      'entry_type': entryType,
      'amount': amount,
      'currency': 'VND',
      'idempotency_key': idempotencyKey,
      'metadata_json': metadata == null ? null : jsonEncode(metadata),
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
    return true;
  }

  Future<void> queueWebhookDelivery({
    required String endpointUrl,
    required String eventType,
    required String aggregateId,
    required Map<String, dynamic> payload,
    String? signature,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = '${eventType}_${aggregateId}_$now';
    await _sqliteDb.upsertRow('webhook_deliveries', {
      'id': id,
      'endpoint_url': endpointUrl,
      'event_type': eventType,
      'aggregate_id': aggregateId,
      'payload_json': jsonEncode(payload),
      'signature': signature,
      'status': 'PENDING',
      'attempt_count': 0,
      'next_attempt_at_ms': now,
      'created_at_ms': now,
    });
  }

  /// Delivers queued merchant webhooks with bounded exponential backoff.
  /// This keeps order creation responsive and allows offline/local-first use.
  Future<int> processDueWebhookDeliveries({int maxItems = 25}) async {
    if (isOfflineMode || maxItems <= 0) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await _sqliteDb.queryRows(
      'webhook_deliveries',
      where: 'status = ? AND next_attempt_at_ms <= ?',
      whereArgs: ['PENDING', now],
      orderBy: 'next_attempt_at_ms ASC',
      limit: maxItems,
    );
    var delivered = 0;
    for (final row in rows) {
      final id = row['id']?.toString();
      final endpoint = Uri.tryParse(row['endpoint_url']?.toString() ?? '');
      if (id == null || endpoint == null || endpoint.host.isEmpty) continue;
      final attempt = (row['attempt_count'] as num?)?.toInt() ?? 0;
      try {
        final response = await http
            .post(
              endpoint,
              headers: {
                'Content-Type': 'application/json; charset=utf-8',
                if ((row['signature'] ?? '').toString().isNotEmpty)
                  'X-GoMau-Signature': row['signature'].toString(),
              },
              body: row['payload_json']?.toString() ?? '{}',
            )
            .timeout(const Duration(seconds: 5));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          await _sqliteDb.updateRows(
            'webhook_deliveries',
            {
              'status': 'DELIVERED',
              'attempt_count': attempt + 1,
              'last_http_status': response.statusCode,
              'last_error': null,
              'delivered_at_ms': now,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
          delivered++;
        } else {
          await _markWebhookRetry(
            id,
            attempt: attempt,
            statusCode: response.statusCode,
            error: 'HTTP ${response.statusCode}',
          );
        }
      } catch (error) {
        await _markWebhookRetry(id, attempt: attempt, error: error.toString());
      }
    }
    return delivered;
  }

  Future<void> _markWebhookRetry(
    String id, {
    required int attempt,
    int? statusCode,
    required String error,
  }) async {
    final boundedAttempt = attempt.clamp(0, 8).toInt();
    final nextAttempt = DateTime.now().add(
      Duration(seconds: (1 << boundedAttempt) * 5),
    );
    final errorText = error.length > 500 ? error.substring(0, 500) : error;
    await _sqliteDb.updateRows(
      'webhook_deliveries',
      {
        'status': attempt >= 7 ? 'FAILED' : 'PENDING',
        'attempt_count': attempt + 1,
        'last_http_status': statusCode,
        'last_error': errorText,
        'next_attempt_at_ms': nextAttempt.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Đăng tải hoặc cập nhật món ăn / đồ uống của Đối tác B2B lên hệ sinh thái GrabFood
  Future<FoodMenuItemRecord> upsertMerchantMenuItem({
    String? id,
    required String name,
    required double priceVnd,
    String description = '',
    String category = 'Cơm • Bún • Phở',
    int prepMinutes = 15,
    List<String> mealSlots = const <String>[
      'breakfast',
      'lunch',
      'afternoonTea',
      'dinner',
    ],
    bool isEcoPackaging = true,
    bool isColdItem = false,
    bool hasPromoBadge = false,
    bool isAvailable = true,
    String? customStoreName,
    String? customStoreAddress,
    GeoPoint? customStoreLocation,
  }) async {
    final activeMer = activeMerchantRecord;
    final personalWhs = merchantPersonalWarehouses;
    final primaryWh =
        personalWhs.where((w) => w.isPrimary).firstOrNull ??
        personalWhs.firstOrNull;

    final resolvedMerId =
        activeMer?.id ??
        (merchantStoreName.trim().isNotEmpty
            ? 'MER-${merchantStoreName.trim().hashCode.abs()}'
            : 'MER-PARTNER-01');
    final resolvedStoreName =
        (customStoreName != null && customStoreName.trim().isNotEmpty)
        ? customStoreName.trim()
        : (activeMer?.storeName.trim().isNotEmpty == true
              ? activeMer!.storeName.trim()
              : (merchantStoreName.trim().isNotEmpty
                    ? merchantStoreName.trim()
                    : 'Quán Đối tác B2B'));
    final resolvedAddress =
        (customStoreAddress != null && customStoreAddress.trim().isNotEmpty)
        ? customStoreAddress.trim()
        : (primaryWh != null && primaryWh.address.trim().isNotEmpty
              ? primaryWh.address.trim()
              : '123 Đường Lê Lợi, Phường Bến Nghé, Quận 1, TP. HCM');
    final resolvedLocation =
        customStoreLocation ??
        primaryWh?.location ??
        SmartDispatchEngine.resolveAddressToCoordinate(
          resolvedAddress,
          fallback:
              liveDeviceLocation ??
              const GeoPoint(latitude: 10.7769, longitude: 106.6953),
        );

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final existingIdx = id == null
        ? -1
        : merchantMenuItems.indexWhere((m) => m.id == id);
    final resolvedId = (id != null && id.trim().isNotEmpty)
        ? id.trim()
        : allocateUniqueId(
            'MENU-',
            merchantMenuItems.map((m) => m.id),
            minNumber: 101,
            padDigits: 3,
          );
    final prevSold = existingIdx >= 0
        ? merchantMenuItems[existingIdx].soldCount
        : 0;
    final cleanSlots = mealSlots.where((s) => s.trim().isNotEmpty).toList();

    final record = FoodMenuItemRecord(
      id: resolvedId,
      merchantId: resolvedMerId,
      storeName: resolvedStoreName,
      storeAddress: resolvedAddress,
      storeLocation: resolvedLocation,
      name: name.trim(),
      description: description.trim(),
      category: category.trim().isNotEmpty ? category.trim() : 'Cơm • Bún • Phở',
      priceVnd: priceVnd.clamp(0.0, 50000000.0).roundToDouble(),
      prepMinutes: prepMinutes.clamp(3, 120),
      mealSlots: cleanSlots.isNotEmpty
          ? cleanSlots
          : const <String>['breakfast', 'lunch', 'afternoonTea', 'dinner'],
      isEcoPackaging: isEcoPackaging,
      isColdItem: isColdItem,
      hasPromoBadge: hasPromoBadge,
      isAvailable: isAvailable,
      rating: 4.9,
      soldCount: prevSold,
      isPartnerMerchant: true,
      createdAtMs: existingIdx >= 0
          ? merchantMenuItems[existingIdx].createdAtMs
          : nowMs,
    );

    if (existingIdx >= 0) {
      merchantMenuItems[existingIdx] = record;
    } else {
      merchantMenuItems.insert(0, record);
    }

    await _sqliteDb.upsertRow('merchant_menu_items', record.toSqlRow());
    _persistMutation('UPSERT_MERCHANT_MENU_ITEM', {
      'table': 'merchant_menu_items',
      'record': record.toSqlRow(),
    });
    _notifyStoreChanged();
    return record;
  }

  /// Bật/tắt trạng thái Còn món / Tạm hết trên thực đơn Đối tác B2B
  Future<bool> toggleMerchantMenuItemAvailability(String itemId) async {
    final item = merchantMenuItems.where((m) => m.id == itemId).firstOrNull;
    if (item == null) return false;
    item.isAvailable = !item.isAvailable;
    await _sqliteDb.updateRows(
      'merchant_menu_items',
      {'is_available': item.isAvailable ? 1 : 0},
      where: 'id = ?',
      whereArgs: [item.id],
    );
    _persistMutation('TOGGLE_MERCHANT_MENU_ITEM', {
      'id': item.id,
      'isAvailable': item.isAvailable,
    });
    _notifyStoreChanged();
    return true;
  }

  /// Xóa món ăn khỏi thực đơn Đối tác B2B
  Future<bool> deleteMerchantMenuItem(String itemId) async {
    final existed = merchantMenuItems.any((m) => m.id == itemId);
    if (!existed) return false;
    merchantMenuItems.removeWhere((m) => m.id == itemId);
    await _sqliteDb.deleteRows(
      'merchant_menu_items',
      where: 'id = ?',
      whereArgs: [itemId],
    );
    _persistMutation('DELETE_MERCHANT_MENU_ITEM', {'id': itemId});
    _notifyStoreChanged();
    return true;
  }

  /// Đặt món trực tiếp từ Giỏ hàng GrabFood -> sinh vận đơn GPS thực tế + hỗ trợ Giữ lạnh / Xe điện / Voucher
  ActiveOrderRecord createGrabFoodOrder({
    required List<GrabFoodCartEntry> cartEntries,
    required String dropoffAddress,
    GeoPoint? customDropoffLocation,
    String? recipientName,
    String? recipientPhone,
    DeliveryServiceType serviceType = DeliveryServiceType.express30m,
    String paymentMethod = 'Người nhận trả phí',
    String? voucherCode,
    bool preferEcoEv = false,
    bool greenFundContributed = false,
    String kitchenNote = '',
  }) {
    final validEntries = cartEntries.where((e) => e.quantity > 0).toList();
    if (validEntries.isEmpty) {
      throw ArgumentError('Giỏ hàng ăn uống không được để trống.');
    }
    final head = validEntries.first.item;
    final foodSubtotalVnd = validEntries
        .fold<double>(0.0, (sum, entry) => sum + entry.lineTotalVnd)
        .roundToDouble();
    final totalQuantity = validEntries.fold<int>(
      0,
      (sum, entry) => sum + entry.quantity,
    );
    final hasColdItem = validEntries.any((entry) => entry.item.isColdItem);
    final estimatedWeightKg = (totalQuantity * 0.45).clamp(0.5, 18.0);

    final itemSummary = validEntries
        .map((e) => '${e.quantity}x ${e.item.name}')
        .join(', ');
    final cleanNote = kitchenNote.trim();
    final coldSuffix = hasColdItem ? ' [GIỮ LẠNH CHỐNG TAN ĐÁ]' : '';
    final noteSuffix = cleanNote.isNotEmpty ? ' • Ghi chú quán: $cleanNote' : '';
    final fullDesc =
        '[GrabFood • ${head.storeName}] $itemSummary$coldSuffix$noteSuffix';

    for (final entry in validEntries) {
      final partnerRecord = merchantMenuItems
          .where((m) => m.id == entry.item.id)
          .firstOrNull;
      if (partnerRecord != null) {
        partnerRecord.soldCount += entry.quantity;
        _sqliteDb.updateRows(
          'merchant_menu_items',
          {'sold_count': partnerRecord.soldCount},
          where: 'id = ?',
          whereArgs: [partnerRecord.id],
        );
      }
    }

    final resolvedRecipientName =
        (recipientName != null && recipientName.trim().isNotEmpty)
        ? recipientName.trim()
        : (customerFullName.trim().isNotEmpty
              ? customerFullName.trim()
              : 'Khách đặt món GrabFood');
    final resolvedRecipientPhone =
        (recipientPhone != null && recipientPhone.trim().isNotEmpty)
        ? recipientPhone.trim()
        : (displayCustomerPhone.trim().isNotEmpty
              ? displayCustomerPhone.trim()
              : (customerPhone.trim().isNotEmpty
                    ? customerPhone.trim()
                    : '0900000000'));

    final created = createNewOrder(
      pickupAddress: head.storeAddress,
      dropoffAddress: dropoffAddress.trim(),
      recipientName: resolvedRecipientName,
      recipientPhone: resolvedRecipientPhone,
      packageDescription: fullDesc,
      weightKg: double.parse(estimatedWeightKg.toStringAsFixed(1)),
      dimensionsCm: '28 x 22 x 18 cm (Túi giữ nhiệt GrabFood)',
      serviceType: serviceType,
      codAmount: foodSubtotalVnd,
      paymentMethod: paymentMethod,
      voucherCode: voucherCode,
      isKeepColdTag: hasColdItem,
      customPickupLocation: head.storeLocation,
      customDropoffLocation: customDropoffLocation,
      preferEcoEv: preferEcoEv,
      greenFundContributed: greenFundContributed,
    );

    final partnerMerchant = merchantApplicants
        .where(
          (m) =>
              m.id == head.merchantId ||
              m.storeName.trim().toLowerCase() ==
                  head.storeName.trim().toLowerCase(),
        )
        .firstOrNull;
    if (partnerMerchant != null) {
      _pushRealtimeNotification(
        category: 'Đơn hàng',
        title:
            'Đơn ăn uống GrabFood mới ${created.trackingCode}: $itemSummary (${foodSubtotalVnd.toStringAsFixed(0)}đ).',
        targetGroup: 'Cửa hàng B2B',
        recipientKey: partnerMerchant.id,
      );
    }
    return created;
  }
}
