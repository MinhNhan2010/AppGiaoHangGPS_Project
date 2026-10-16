import 'dart:convert';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:uuid/uuid.dart';
import '../../../core/config/env_config.dart';
import '../../../domain/entities/order_entity.dart';

class OfflineSyncRecord {
  final int id;
  final String idempotencyKey;
  final String actionType;
  final Map<String, dynamic> payload;
  final int retryCount;
  final String syncStatus;
  final int createdAtMs;

  const OfflineSyncRecord({
    required this.id,
    required this.idempotencyKey,
    required this.actionType,
    required this.payload,
    required this.retryCount,
    required this.syncStatus,
    required this.createdAtMs,
  });

  /// Công thức lùi mũ Exponential Backoff (Chương 15.1): min(2^n * 1000ms, 30000ms)
  int get nextBackoffDelayMs {
    final rawMs = math.pow(2, retryCount).toInt() * 1000;
    return math.min(rawMs, EnvConfig.maxOfflineRetryBackoffMs);
  }
}

class SqliteOfflineQueueDatasource {
  static const String _dbFileName = 'gps_delivery_offline.db';
  static const int _dbVersion = 2;
  static const Uuid _uuid = Uuid();

  sqflite.Database? _database;

  Future<sqflite.Database> get database async {
    if (_database != null) return _database!;
    final dbDir = await sqflite.getDatabasesPath();
    final fullPath = p.join(dbDir, _dbFileName);

    _database = await sqflite.openDatabase(
      fullPath,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createTables(db);
      },
    );
    return _database!;
  }

  Future<void> _createTables(sqflite.Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        idempotency_key TEXT UNIQUE NOT NULL,
        action_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        sync_status TEXT NOT NULL DEFAULT 'PENDING',
        created_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cached_active_orders (
        id TEXT PRIMARY KEY,
        tracking_code TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');

    // Lưu trữ bền vững cho toàn bộ 16 bảng dữ liệu (Bảng 11.1 - 11.16)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_relational_entities (
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        PRIMARY KEY (table_name, record_id)
      )
    ''');
  }

  Future<void> upsertEntityRecord({
    required String tableName,
    required String recordId,
    required Map<String, dynamic> payload,
  }) async {
    final db = await database;
    await db.insert(
      'local_relational_entities',
      {
        'table_name': tableName,
        'record_id': recordId,
        'payload_json': jsonEncode(payload),
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getEntityRecords(String tableName) async {
    final db = await database;
    final rows = await db.query(
      'local_relational_entities',
      where: 'table_name = ?',
      whereArgs: [tableName],
      orderBy: 'updated_at_ms DESC',
    );
    return rows
        .map(
          (r) =>
              jsonDecode(r['payload_json'] as String) as Map<String, dynamic>,
        )
        .toList();
  }

  Future<String> enqueueAction({
    required String actionType,
    required Map<String, dynamic> payload,
  }) async {
    final db = await database;
    final idempotencyKey = _uuid.v4();
    await db.insert(
      'local_sync_queue',
      {
        'idempotency_key': idempotencyKey,
        'action_type': actionType,
        'payload_json': jsonEncode(payload),
        'retry_count': 0,
        'sync_status': 'PENDING',
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
    return idempotencyKey;
  }

  Future<List<OfflineSyncRecord>> getPendingSyncItems({int limit = 50}) async {
    final db = await database;
    final rows = await db.query(
      'local_sync_queue',
      where: 'sync_status = ?',
      whereArgs: ['PENDING'],
      orderBy: 'created_at_ms ASC',
      limit: limit,
    );

    return rows.map((row) {
      return OfflineSyncRecord(
        id: row['id'] as int,
        idempotencyKey: row['idempotency_key'] as String,
        actionType: row['action_type'] as String,
        payload: jsonDecode(row['payload_json'] as String)
            as Map<String, dynamic>,
        retryCount: row['retry_count'] as int,
        syncStatus: row['sync_status'] as String,
        createdAtMs: row['created_at_ms'] as int,
      );
    }).toList();
  }

  Future<int> getPendingQueueCount() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM local_sync_queue WHERE sync_status = 'PENDING'",
    );
    return sqflite.Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> markSynced(int id) async {
    final db = await database;
    await db.delete(
      'local_sync_queue',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> incrementRetry(int id, int currentRetry) async {
    final db = await database;
    final nextRetry = currentRetry + 1;
    final nextStatus = nextRetry >= 10 ? 'FAILED' : 'PENDING';
    await db.update(
      'local_sync_queue',
      {
        'retry_count': nextRetry,
        'sync_status': nextStatus,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> cacheOrder(OrderEntity order) async {
    final db = await database;
    await db.insert(
      'cached_active_orders',
      {
        'id': order.id,
        'tracking_code': order.trackingCode,
        'customer_id': order.customerId,
        'payload_json': jsonEncode(order.toMap()),
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  Future<List<OrderEntity>> getCachedOrders([String? customerId]) async {
    final db = await database;
    final rows = await db.query(
      'cached_active_orders',
      where: customerId != null ? 'customer_id = ?' : null,
      whereArgs: customerId != null ? [customerId] : null,
      orderBy: 'updated_at_ms DESC',
    );
    return rows.map((r) {
      final map =
          jsonDecode(r['payload_json'] as String) as Map<String, dynamic>;
      return OrderEntity.fromMap(map);
    }).toList();
  }
}
