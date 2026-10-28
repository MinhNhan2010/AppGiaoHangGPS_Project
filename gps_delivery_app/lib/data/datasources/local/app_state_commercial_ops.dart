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

  // ===========================================================================
  // TRUNG TÂM SỰ KIỆN KHUYẾN MÃI SHOPEE × GRAB, VÒNG XOAY & HỘP MÙ BÍ ẨN
  // ===========================================================================

  String _resolveActivePromoUserKey() {
    final rawPhone = activeAuthenticatedUser?.phone ?? customerPhone;
    final norm = _normalizePhone(rawPhone);
    return norm.isNotEmpty ? norm : 'GUEST_LOCAL';
  }

  String _defaultPromoExpiryDate({int daysAhead = 45}) {
    final exp = DateTime.now().add(Duration(days: daysAhead));
    return '${exp.day.toString().padLeft(2, '0')}/${exp.month.toString().padLeft(2, '0')}/${exp.year}';
  }

  /// Ví thưởng Săn Sale & Gamification của khách hàng hiện tại (không ghi DB khi chỉ đọc)
  CustomerPromoWalletState get activeCustomerPromoWallet {
    final key = _resolveActivePromoUserKey();
    final prefs = userPreferencesByPhone[key];
    final rawPromo = prefs?['promoGamification'];
    if (rawPromo is Map) {
      return CustomerPromoWalletState.fromJson(
        Map<String, dynamic>.from(rawPromo),
      );
    }
    return const CustomerPromoWalletState();
  }

  void _persistCustomerPromoWallet(
    CustomerPromoWalletState nextWallet, {
    required String actionType,
    Map<String, dynamic>? summaryPayload,
  }) {
    final key = _resolveActivePromoUserKey();
    final prefs = Map<String, dynamic>.from(
      userPreferencesByPhone[key] ?? const <String, dynamic>{},
    );
    prefs['promoGamification'] = nextWallet.toJson();
    userPreferencesByPhone[key] = prefs;
    _sqliteDb.upsertEntityRecord(
      tableName: 'user_preferences',
      recordId: key,
      payload: prefs,
    );
    _persistMutation(actionType, summaryPayload ?? {'userKey': key});
    _notifyStoreChanged();
  }

  /// Điểm danh 7 ngày kiểu Shopee Xu nhận GHST Xu + Vé Vòng Xoay / Hộp Mù
  PromoActionOutcome claimDailyPromoCheckIn({DateTime? nowOverride}) {
    final now = nowOverride ?? DateTime.now();
    final wallet = activeCustomerPromoWallet;
    if (wallet.hasCheckedInOn(now)) {
      return const PromoActionOutcome(
        success: false,
        message:
            'Hôm nay bạn đã điểm danh nhận thưởng rồi! Hãy quay lại vào ngày mai nhé.',
      );
    }
    final nextDay = (wallet.checkInStreak % 7) + 1;
    final spec = PromoEventGamificationEngine.dailyCheckInSchedule[nextDay - 1];
    final bonusSpin = spec.bonusSpinTickets;
    final bonusBox = spec.bonusBlindBoxTickets;
    final extraParts = <String>[
      '+${spec.coins} GHST Xu',
      if (bonusSpin > 0) '+$bonusSpin Vé Vòng Xoay',
      if (bonusBox > 0) '+$bonusBox Vé Hộp Mù',
    ];
    final summary = extraParts.join(' • ');
    final histEntry = PromoRewardHistoryEntry(
      id: 'CHK-${now.millisecondsSinceEpoch}',
      source: 'CHECK_IN',
      title: 'Điểm danh Ngày $nextDay/7',
      summary: summary,
      rarityCode: nextDay == 7 ? 'SSR' : (nextDay >= 3 ? 'SR' : 'R'),
      timestampLabel: PromoEventGamificationEngine.formatTimeShort(now),
    );
    final updated = CustomerPromoWalletState(
      ghstCoins: wallet.ghstCoins + spec.coins,
      spinTickets: wallet.spinTickets + bonusSpin,
      blindBoxTickets: wallet.blindBoxTickets + bonusBox,
      checkInStreak: nextDay,
      lastCheckInDate: PromoEventGamificationEngine.formatDateKey(now),
      claimedCampaignIds: Set<String>.from(wallet.claimedCampaignIds),
      claimedMissionIds: Set<String>.from(wallet.claimedMissionIds),
      openedBlindBoxes: Map<int, OpenedBlindBoxRecord>.from(
        wallet.openedBlindBoxes,
      ),
      history: [histEntry, ...wallet.history],
      totalSpinsCount: wallet.totalSpinsCount,
      totalBlindBoxesOpened: wallet.totalBlindBoxesOpened,
    );
    _pushRealtimeNotification(
      category: 'Khuyến mãi',
      title: 'Điểm danh Ngày $nextDay thành công: Nhận $summary!',
      targetGroup: 'Khách hàng',
      recipientKey: customerFullName.isNotEmpty ? customerFullName : null,
    );
    _persistCustomerPromoWallet(
      updated,
      actionType: 'PROMO_DAILY_CHECKIN',
      summaryPayload: {'day': nextDay, 'coins': spec.coins},
    );
    return PromoActionOutcome(
      success: true,
      message: 'Điểm danh Ngày $nextDay thành công! Nhận $summary.',
      rewardTitle: 'Điểm danh Ngày $nextDay/7 ($summary)',
      rarity: nextDay == 7 ? PromoRarityTier.legendary : PromoRarityTier.common,
      coinsDelta: spec.coins,
      spinTicketsDelta: bonusSpin,
      blindBoxTicketsDelta: bonusBox,
    );
  }

  /// Lưu mã Flash Sale Khung Giờ Vàng kiểu Shopee & Grab vào Kho Voucher thực tế
  PromoActionOutcome claimFlashSaleCampaign(String campaignId) {
    final campaign = PromoEventGamificationEngine.flashSaleCampaigns
        .where((c) => c.id == campaignId)
        .firstOrNull;
    if (campaign == null) {
      return const PromoActionOutcome(
        success: false,
        message: 'Chiến dịch khuyến mãi không tồn tại hoặc đã kết thúc.',
      );
    }
    final wallet = activeCustomerPromoWallet;
    if (wallet.claimedCampaignIds.contains(campaign.id)) {
      return PromoActionOutcome(
        success: false,
        message:
            'Bạn đã lưu mã chiến dịch "${campaign.codePrefix}" vào Kho Voucher rồi!',
      );
    }

    final existingSameCode = vouchers
        .where((v) => v.code == campaign.codePrefix)
        .firstOrNull;
    final voucherCode = (existingSameCode == null || existingSameCode.isUsable)
        ? campaign.codePrefix
        : allocateUniqueId(
            '${campaign.codePrefix}-',
            vouchers.map((v) => v.code),
            minNumber: 101,
            padDigits: 3,
          );

    final minted = _upsertVoucherInternal(
      code: voucherCode,
      title: '[${campaign.platformStyle}] ${campaign.title}',
      discountValue: campaign.discountValue,
      isPercentage: campaign.isPercentage,
      maxDiscount: campaign.maxDiscount,
      minOrderValue: campaign.minOrderValue,
      usageLimit: existingSameCode != null && existingSameCode.isUsable
          ? existingSameCode.usageLimit + 2
          : 3,
      expiryDate: _defaultPromoExpiryDate(daysAhead: 30),
    );

    final now = DateTime.now();
    final histEntry = PromoRewardHistoryEntry(
      id: 'FLS-${now.millisecondsSinceEpoch}',
      source: 'FLASH_SALE',
      title: campaign.title,
      summary: 'Mã ${minted.code} (${minted.discountLabel}) & +${campaign.bonusCoins} Xu',
      rarityCode: 'SR',
      voucherCode: minted.code,
      timestampLabel: PromoEventGamificationEngine.formatTimeShort(now),
    );
    final nextClaimed = Set<String>.from(wallet.claimedCampaignIds)
      ..add(campaign.id);
    final updated = CustomerPromoWalletState(
      ghstCoins: wallet.ghstCoins + campaign.bonusCoins,
      spinTickets: wallet.spinTickets,
      blindBoxTickets: wallet.blindBoxTickets,
      checkInStreak: wallet.checkInStreak,
      lastCheckInDate: wallet.lastCheckInDate,
      claimedCampaignIds: nextClaimed,
      claimedMissionIds: Set<String>.from(wallet.claimedMissionIds),
      openedBlindBoxes: Map<int, OpenedBlindBoxRecord>.from(
        wallet.openedBlindBoxes,
      ),
      history: [histEntry, ...wallet.history],
      totalSpinsCount: wallet.totalSpinsCount,
      totalBlindBoxesOpened: wallet.totalBlindBoxesOpened,
    );
    _persistCustomerPromoWallet(
      updated,
      actionType: 'PROMO_CLAIM_FLASH_SALE',
      summaryPayload: {'campaignId': campaign.id, 'voucherCode': minted.code},
    );
    return PromoActionOutcome(
      success: true,
      message:
          'Đã săn thành công mã ${minted.code} (${minted.discountLabel}) và cộng +${campaign.bonusCoins} GHST Xu!',
      rewardTitle: '${minted.code} • ${campaign.title}',
      rarity: PromoRarityTier.rare,
      mintedVoucherCode: minted.code,
      coinsDelta: campaign.bonusCoins,
    );
  }

  /// Nhận thưởng Nhiệm vụ GrabChallenges (tặng Xu + Vé Vòng Xoay + Vé Hộp Mù)
  PromoActionOutcome claimPromoMissionReward(String missionId) {
    final wallet = activeCustomerPromoWallet;
    final missions = PromoEventGamificationEngine.evaluateCustomerMissions(
      customerOrders: customerOrders,
      claimedMissionIds: wallet.claimedMissionIds,
    );
    final target = missions.where((m) => m.id == missionId).firstOrNull;
    if (target == null) {
      return const PromoActionOutcome(
        success: false,
        message: 'Không tìm thấy nhiệm vụ săn thưởng này.',
      );
    }
    if (target.isClaimed) {
      return const PromoActionOutcome(
        success: false,
        message: 'Bạn đã nhận phần thưởng nhiệm vụ này rồi!',
      );
    }
    if (!target.isCompleted) {
      return PromoActionOutcome(
        success: false,
        message:
            'Nhiệm vụ chưa hoàn thành (${target.currentCount}/${target.targetCount}). Hãy đặt đơn để mở khóa nhé!',
      );
    }

    final rewardParts = <String>[
      if (target.rewardCoins > 0) '+${target.rewardCoins} Xu',
      if (target.rewardSpinTickets > 0)
        '+${target.rewardSpinTickets} Vé Vòng Xoay',
      if (target.rewardBlindBoxTickets > 0)
        '+${target.rewardBlindBoxTickets} Vé Hộp Mù',
    ];
    final rewardSummary = rewardParts.join(' • ');
    final now = DateTime.now();
    final histEntry = PromoRewardHistoryEntry(
      id: 'MIS-${now.millisecondsSinceEpoch}',
      source: 'MISSION',
      title: 'Nhiệm vụ: ${target.title}',
      summary: rewardSummary,
      rarityCode: target.rewardBlindBoxTickets > 0 ? 'SR' : 'R',
      timestampLabel: PromoEventGamificationEngine.formatTimeShort(now),
    );
    final nextMissions = Set<String>.from(wallet.claimedMissionIds)
      ..add(target.id);
    final updated = CustomerPromoWalletState(
      ghstCoins: wallet.ghstCoins + target.rewardCoins,
      spinTickets: wallet.spinTickets + target.rewardSpinTickets,
      blindBoxTickets: wallet.blindBoxTickets + target.rewardBlindBoxTickets,
      checkInStreak: wallet.checkInStreak,
      lastCheckInDate: wallet.lastCheckInDate,
      claimedCampaignIds: Set<String>.from(wallet.claimedCampaignIds),
      claimedMissionIds: nextMissions,
      openedBlindBoxes: Map<int, OpenedBlindBoxRecord>.from(
        wallet.openedBlindBoxes,
      ),
      history: [histEntry, ...wallet.history],
      totalSpinsCount: wallet.totalSpinsCount,
      totalBlindBoxesOpened: wallet.totalBlindBoxesOpened,
    );
    _pushRealtimeNotification(
      category: 'Khuyến mãi',
      title: 'Hoàn thành nhiệm vụ "${target.title}": Nhận $rewardSummary!',
      targetGroup: 'Khách hàng',
      recipientKey: customerFullName.isNotEmpty ? customerFullName : null,
    );
    _persistCustomerPromoWallet(
      updated,
      actionType: 'PROMO_CLAIM_MISSION',
      summaryPayload: {'missionId': target.id},
    );
    return PromoActionOutcome(
      success: true,
      message: 'Đã nhận thưởng nhiệm vụ "${target.title}": $rewardSummary!',
      rewardTitle: target.title,
      rarity: target.rewardBlindBoxTickets > 0
          ? PromoRarityTier.rare
          : PromoRarityTier.common,
      coinsDelta: target.rewardCoins,
      spinTicketsDelta: target.rewardSpinTickets,
      blindBoxTicketsDelta: target.rewardBlindBoxTickets,
    );
  }

  /// Đổi GHST Xu lấy Vé Vòng Xoay, Vé Hộp Mù hoặc Voucher Freeship 25k
  PromoActionOutcome exchangePromoCoins({required String targetType}) {
    final wallet = activeCustomerPromoWallet;
    final now = DateTime.now();
    if (targetType == 'SPIN_TICKET') {
      const cost = PromoEventGamificationEngine.coinsPerSpinTicket;
      if (wallet.ghstCoins < cost) {
        return PromoActionOutcome(
          success: false,
          message:
              'Cần $cost GHST Xu để đổi 1 Vé Vòng Xoay (Hiện có: ${wallet.ghstCoins} Xu).',
        );
      }
      final hist = PromoRewardHistoryEntry(
        id: 'EXS-${now.millisecondsSinceEpoch}',
        source: 'COIN_SHOP',
        title: 'Đổi Xu lấy +1 Vé Vòng Xoay',
        summary: '-$cost GHST Xu → +1 Lượt quay',
        rarityCode: 'R',
        timestampLabel: PromoEventGamificationEngine.formatTimeShort(now),
      );
      _persistCustomerPromoWallet(
        CustomerPromoWalletState(
          ghstCoins: wallet.ghstCoins - cost,
          spinTickets: wallet.spinTickets + 1,
          blindBoxTickets: wallet.blindBoxTickets,
          checkInStreak: wallet.checkInStreak,
          lastCheckInDate: wallet.lastCheckInDate,
          claimedCampaignIds: Set<String>.from(wallet.claimedCampaignIds),
          claimedMissionIds: Set<String>.from(wallet.claimedMissionIds),
          openedBlindBoxes: Map<int, OpenedBlindBoxRecord>.from(
            wallet.openedBlindBoxes,
          ),
          history: [hist, ...wallet.history],
          totalSpinsCount: wallet.totalSpinsCount,
          totalBlindBoxesOpened: wallet.totalBlindBoxesOpened,
        ),
        actionType: 'PROMO_EXCHANGE_SPIN',
      );
      return const PromoActionOutcome(
        success: true,
        message: 'Đã đổi 150 GHST Xu lấy +1 Vé Vòng Xoay May Mắn!',
        rewardTitle: '+1 Vé Vòng Xoay May Mắn',
        coinsDelta: -cost,
        spinTicketsDelta: 1,
      );
    }

    if (targetType == 'BLIND_BOX_TICKET') {
      const cost = PromoEventGamificationEngine.coinsPerBlindBoxTicket;
      if (wallet.ghstCoins < cost) {
        return PromoActionOutcome(
          success: false,
          message:
              'Cần $cost GHST Xu để đổi 1 Vé Mở Hộp Mù (Hiện có: ${wallet.ghstCoins} Xu).',
        );
      }
      final hist = PromoRewardHistoryEntry(
        id: 'EXB-${now.millisecondsSinceEpoch}',
        source: 'COIN_SHOP',
        title: 'Đổi Xu lấy +1 Vé Hộp Mù Bí Ẩn',
        summary: '-$cost GHST Xu → +1 Vé Hộp Mù',
        rarityCode: 'SR',
        timestampLabel: PromoEventGamificationEngine.formatTimeShort(now),
      );
      _persistCustomerPromoWallet(
        CustomerPromoWalletState(
          ghstCoins: wallet.ghstCoins - cost,
          spinTickets: wallet.spinTickets,
          blindBoxTickets: wallet.blindBoxTickets + 1,
          checkInStreak: wallet.checkInStreak,
          lastCheckInDate: wallet.lastCheckInDate,
          claimedCampaignIds: Set<String>.from(wallet.claimedCampaignIds),
          claimedMissionIds: Set<String>.from(wallet.claimedMissionIds),
          openedBlindBoxes: Map<int, OpenedBlindBoxRecord>.from(
            wallet.openedBlindBoxes,
          ),
          history: [hist, ...wallet.history],
          totalSpinsCount: wallet.totalSpinsCount,
          totalBlindBoxesOpened: wallet.totalBlindBoxesOpened,
        ),
        actionType: 'PROMO_EXCHANGE_BLINDBOX',
      );
      return const PromoActionOutcome(
        success: true,
        message: 'Đã đổi 250 GHST Xu lấy +1 Vé Mở Hộp Mù Bí Ẩn!',
        rewardTitle: '+1 Vé Mở Hộp Mù Bí Ẩn',
        rarity: PromoRarityTier.rare,
        coinsDelta: -cost,
        blindBoxTicketsDelta: 1,
      );
    }

    const voucherCost = PromoEventGamificationEngine.coinsPerDirectVoucher25k;
    if (wallet.ghstCoins < voucherCost) {
      return PromoActionOutcome(
        success: false,
        message:
            'Cần $voucherCost GHST Xu để đổi Voucher 25.000đ (Hiện có: ${wallet.ghstCoins} Xu).',
      );
    }
    final code = allocateUniqueId(
      'XU25K-',
      vouchers.map((v) => v.code),
      minNumber: 101,
      padDigits: 3,
    );
    final minted = _upsertVoucherInternal(
      code: code,
      title: '[Đổi GHST Xu] Freeship 25.000đ Giao hàng & GrabFood',
      discountValue: 25000,
      isPercentage: false,
      maxDiscount: 25000,
      minOrderValue: 20000,
      usageLimit: 1,
      expiryDate: _defaultPromoExpiryDate(),
    );
    final hist = PromoRewardHistoryEntry(
      id: 'EXV-${now.millisecondsSinceEpoch}',
      source: 'COIN_SHOP',
      title: 'Đổi Xu nhận Voucher ${minted.code}',
      summary: '-$voucherCost Xu → Mã giảm 25.000đ',
      rarityCode: 'SR',
      voucherCode: minted.code,
      timestampLabel: PromoEventGamificationEngine.formatTimeShort(now),
    );
    _persistCustomerPromoWallet(
      CustomerPromoWalletState(
        ghstCoins: wallet.ghstCoins - voucherCost,
        spinTickets: wallet.spinTickets,
        blindBoxTickets: wallet.blindBoxTickets,
        checkInStreak: wallet.checkInStreak,
        lastCheckInDate: wallet.lastCheckInDate,
        claimedCampaignIds: Set<String>.from(wallet.claimedCampaignIds),
        claimedMissionIds: Set<String>.from(wallet.claimedMissionIds),
        openedBlindBoxes: Map<int, OpenedBlindBoxRecord>.from(
          wallet.openedBlindBoxes,
        ),
        history: [hist, ...wallet.history],
        totalSpinsCount: wallet.totalSpinsCount,
        totalBlindBoxesOpened: wallet.totalBlindBoxesOpened,
      ),
      actionType: 'PROMO_EXCHANGE_VOUCHER',
      summaryPayload: {'voucherCode': minted.code},
    );
    return PromoActionOutcome(
      success: true,
      message: 'Đổi thành công 400 Xu lấy mã ${minted.code} (Giảm 25.000đ)!',
      rewardTitle: '${minted.code} • Giảm 25.000đ',
      rarity: PromoRarityTier.rare,
      mintedVoucherCode: minted.code,
      coinsDelta: -voucherCost,
    );
  }

  /// Quay Vòng Xoay May Mắn (Lucky Spin Wheel) -> Trả về ô trúng thưởng & cấp Voucher thật vào SQLite
  PromoActionOutcome spinLuckyWheel({
    math.Random? random,
    int? forcedSegmentIndex,
  }) {
    final wallet = activeCustomerPromoWallet;
    if (wallet.spinTickets <= 0) {
      return const PromoActionOutcome(
        success: false,
        message:
            'Bạn đã hết Vé Vòng Xoay! Hãy Điểm danh, làm Nhiệm vụ hoặc dùng 150 GHST Xu đổi thêm lượt nhé.',
      );
    }

    final segment = forcedSegmentIndex != null
        ? PromoEventGamificationEngine.spinWheelSegments[forcedSegmentIndex
              .clamp(0, PromoEventGamificationEngine.spinWheelSegments.length - 1)]
        : PromoEventGamificationEngine.rollWeightedSpinSegment(random: random);

    String? mintedCode;
    int bonusBlindBox = 0;
    String summaryText = '';

    if (segment.rewardType == PromoRewardType.voucher &&
        segment.voucherCodePrefix != null) {
      final newCode = allocateUniqueId(
        '${segment.voucherCodePrefix}-',
        vouchers.map((v) => v.code),
        minNumber: 101,
        padDigits: 3,
      );
      final record = _upsertVoucherInternal(
        code: newCode,
        title: '[Vòng Xoay] ${segment.fullTitle}',
        discountValue: segment.discountValue,
        isPercentage: segment.isPercentage,
        maxDiscount: segment.maxDiscount,
        minOrderValue: segment.minOrderValue,
        usageLimit: 1,
        expiryDate: _defaultPromoExpiryDate(),
      );
      mintedCode = record.code;
      summaryText =
          'Mã ${record.code} (${record.discountLabel})${segment.bonusCoins > 0 ? " & +${segment.bonusCoins} Xu" : ""}';
    } else if (segment.rewardType == PromoRewardType.blindBoxTicket) {
      bonusBlindBox = segment.bonusTickets;
      summaryText =
          '+$bonusBlindBox Vé Hộp Mù${segment.bonusCoins > 0 ? " & +${segment.bonusCoins} Xu" : ""}';
    } else {
      summaryText = '+${segment.bonusCoins} GHST Xu tích lũy';
    }

    final now = DateTime.now();
    final histEntry = PromoRewardHistoryEntry(
      id: 'SPN-${now.millisecondsSinceEpoch}',
      source: 'SPIN_WHEEL',
      title: segment.fullTitle,
      summary: summaryText,
      rarityCode: segment.rarity.code,
      voucherCode: mintedCode,
      timestampLabel: PromoEventGamificationEngine.formatTimeShort(now),
    );

    final updated = CustomerPromoWalletState(
      ghstCoins: wallet.ghstCoins + segment.bonusCoins,
      spinTickets: wallet.spinTickets - 1,
      blindBoxTickets: wallet.blindBoxTickets + bonusBlindBox,
      checkInStreak: wallet.checkInStreak,
      lastCheckInDate: wallet.lastCheckInDate,
      claimedCampaignIds: Set<String>.from(wallet.claimedCampaignIds),
      claimedMissionIds: Set<String>.from(wallet.claimedMissionIds),
      openedBlindBoxes: Map<int, OpenedBlindBoxRecord>.from(
        wallet.openedBlindBoxes,
      ),
      history: [histEntry, ...wallet.history],
      totalSpinsCount: wallet.totalSpinsCount + 1,
      totalBlindBoxesOpened: wallet.totalBlindBoxesOpened,
    );
    _persistCustomerPromoWallet(
      updated,
      actionType: 'PROMO_SPIN_WHEEL',
      summaryPayload: {
        'segmentIndex': segment.index,
        'voucherCode': mintedCode,
      },
    );
    return PromoActionOutcome(
      success: true,
      message: 'Chúc mừng! Bạn quay trúng: ${segment.fullTitle} ($summaryText)',
      rewardTitle: segment.fullTitle,
      rarity: segment.rarity,
      wheelSegmentIndex: segment.index,
      mintedVoucherCode: mintedCode,
      coinsDelta: segment.bonusCoins,
      spinTicketsDelta: -1,
      blindBoxTicketsDelta: bonusBlindBox,
    );
  }

  /// Khui Hộp Mù Bí Ẩn (Mystery Blind Box Gacha) tại vị trí `boxIndex` (0..5)
  PromoActionOutcome openMysteryBlindBox(
    int boxIndex, {
    math.Random? random,
    String? forcedPrizeId,
  }) {
    final safeIdx = boxIndex.clamp(
      0,
      PromoEventGamificationEngine.blindBoxBoardSlots.length - 1,
    );
    final wallet = activeCustomerPromoWallet;
    if (wallet.openedBlindBoxes.containsKey(safeIdx)) {
      return const PromoActionOutcome(
        success: false,
        message:
            'Chiếc hộp mù này đã được khui! Hãy chọn hộp niêm phong khác hoặc bấm "Làm mới bộ 6 Hộp Mù".',
      );
    }
    if (wallet.blindBoxTickets <= 0) {
      return const PromoActionOutcome(
        success: false,
        message:
            'Bạn đã hết Vé Mở Hộp Mù! Hãy dùng 250 GHST Xu đổi vé hoặc quay Vòng Xoay May Mắn để săn vé nhé.',
      );
    }

    final prize = forcedPrizeId != null
        ? (PromoEventGamificationEngine.blindBoxPrizePool
                  .where((p) => p.id == forcedPrizeId)
                  .firstOrNull ??
              PromoEventGamificationEngine.blindBoxPrizePool.first)
        : PromoEventGamificationEngine.rollWeightedBlindBoxPrize(random: random);

    String? mintedCode;
    final parts = <String>[];
    if (prize.rewardType == PromoRewardType.voucher &&
        prize.voucherCodePrefix != null) {
      final newCode = allocateUniqueId(
        '${prize.voucherCodePrefix}-',
        vouchers.map((v) => v.code),
        minNumber: 101,
        padDigits: 3,
      );
      final record = _upsertVoucherInternal(
        code: newCode,
        title: '[Hộp Mù ${prize.rarity.code}] ${prize.title}',
        discountValue: prize.discountValue,
        isPercentage: prize.isPercentage,
        maxDiscount: prize.maxDiscount,
        minOrderValue: prize.minOrderValue,
        usageLimit: 1,
        expiryDate: _defaultPromoExpiryDate(),
      );
      mintedCode = record.code;
      parts.add('Mã ${record.code} (${record.discountLabel})');
    }
    if (prize.bonusCoins > 0) {
      parts.add('+${prize.bonusCoins} Xu');
    }
    if (prize.bonusSpinTickets > 0) {
      parts.add('+${prize.bonusSpinTickets} Vé Quay');
    }
    final summaryText = parts.join(' • ');

    final slotInfo = PromoEventGamificationEngine.blindBoxBoardSlots[safeIdx];
    final openedRecord = OpenedBlindBoxRecord(
      boxIndex: safeIdx,
      title: prize.title,
      summary: summaryText,
      rarityCode: prize.rarity.code,
      voucherCode: mintedCode,
    );
    final nextOpened = Map<int, OpenedBlindBoxRecord>.from(
      wallet.openedBlindBoxes,
    )..[safeIdx] = openedRecord;

    final now = DateTime.now();
    final histEntry = PromoRewardHistoryEntry(
      id: 'BOX-${now.millisecondsSinceEpoch}',
      source: 'BLIND_BOX',
      title: '${slotInfo.boxCode}: ${prize.title}',
      summary: summaryText,
      rarityCode: prize.rarity.code,
      voucherCode: mintedCode,
      timestampLabel: PromoEventGamificationEngine.formatTimeShort(now),
    );

    final updated = CustomerPromoWalletState(
      ghstCoins: wallet.ghstCoins + prize.bonusCoins,
      spinTickets: wallet.spinTickets + prize.bonusSpinTickets,
      blindBoxTickets: wallet.blindBoxTickets - 1,
      checkInStreak: wallet.checkInStreak,
      lastCheckInDate: wallet.lastCheckInDate,
      claimedCampaignIds: Set<String>.from(wallet.claimedCampaignIds),
      claimedMissionIds: Set<String>.from(wallet.claimedMissionIds),
      openedBlindBoxes: nextOpened,
      history: [histEntry, ...wallet.history],
      totalSpinsCount: wallet.totalSpinsCount,
      totalBlindBoxesOpened: wallet.totalBlindBoxesOpened + 1,
    );
    _persistCustomerPromoWallet(
      updated,
      actionType: 'PROMO_OPEN_BLIND_BOX',
      summaryPayload: {
        'boxIndex': safeIdx,
        'prizeId': prize.id,
        'voucherCode': mintedCode,
      },
    );
    return PromoActionOutcome(
      success: true,
      message: 'Khui ${slotInfo.themeTitle} thành công: ${prize.title} ($summaryText)!',
      rewardTitle: prize.title,
      rarity: prize.rarity,
      blindBoxIndex: safeIdx,
      mintedVoucherCode: mintedCode,
      coinsDelta: prize.bonusCoins,
      spinTicketsDelta: prize.bonusSpinTickets,
      blindBoxTicketsDelta: -1,
    );
  }

  /// Làm mới bàn 6 chiếc Hộp Mù Bí Ẩn để khách khui đợt mới
  void resetMysteryBlindBoxBoard() {
    final wallet = activeCustomerPromoWallet;
    if (wallet.openedBlindBoxes.isEmpty) return;
    final updated = CustomerPromoWalletState(
      ghstCoins: wallet.ghstCoins,
      spinTickets: wallet.spinTickets,
      blindBoxTickets: wallet.blindBoxTickets,
      checkInStreak: wallet.checkInStreak,
      lastCheckInDate: wallet.lastCheckInDate,
      claimedCampaignIds: Set<String>.from(wallet.claimedCampaignIds),
      claimedMissionIds: Set<String>.from(wallet.claimedMissionIds),
      openedBlindBoxes: const <int, OpenedBlindBoxRecord>{},
      history: wallet.history,
      totalSpinsCount: wallet.totalSpinsCount,
      totalBlindBoxesOpened: wallet.totalBlindBoxesOpened,
    );
    _persistCustomerPromoWallet(
      updated,
      actionType: 'PROMO_RESET_BLINDBOX_BOARD',
    );
  }

  /// Dành cho Admin: Phát hành nhanh toàn bộ 5 Chiến dịch Flash Sale mẫu (Shopee × Grab) lên sàn
  int publishPresetFlashCampaignsForAdmin() {
    if (!hasAdminPermission('Hệ thống: Cài đặt')) return 0;
    var count = 0;
    for (final camp in PromoEventGamificationEngine.flashSaleCampaigns) {
      if (vouchers.any((v) => v.code == camp.codePrefix)) continue;
      _upsertVoucherInternal(
        code: camp.codePrefix,
        title: '[${camp.platformStyle}] ${camp.title}',
        discountValue: camp.discountValue,
        isPercentage: camp.isPercentage,
        maxDiscount: camp.maxDiscount,
        minOrderValue: camp.minOrderValue,
        usageLimit: 500,
        expiryDate: _defaultPromoExpiryDate(daysAhead: 60),
      );
      count++;
    }
    if (count > 0) {
      _notifyStoreChanged();
    }
    return count;
  }
}
