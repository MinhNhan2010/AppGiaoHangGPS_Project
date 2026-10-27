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
}
