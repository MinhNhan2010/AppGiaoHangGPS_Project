import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;
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

  int get nextBackoffDelayMs {
    final rawMs = math.pow(2, retryCount).toInt() * 1000;
    return math.min(rawMs, EnvConfig.maxOfflineRetryBackoffMs);
  }
}

class SqliteOfflineQueueDatasource {
  static final SqliteOfflineQueueDatasource instance =
      SqliteOfflineQueueDatasource._internal();

  factory SqliteOfflineQueueDatasource() => instance;

  SqliteOfflineQueueDatasource._internal();

  static const String _dbFileName = 'gps_delivery_production.db';
  static const int _dbVersion = 4;
  static const Uuid _uuid = Uuid();

  static bool _ffiInitialized = false;
  sqflite.Database? _database;
  String? _resolvedDbFilePath;

  String get databaseFilePath => _resolvedDbFilePath ?? _dbFileName;

  static void ensureDesktopFfiInitialized() {
    if (_ffiInitialized) return;
    try {
      if (Platform.isWindows) {
        final exeDir = File(Platform.resolvedExecutable).parent;
        if (File(p.join(exeDir.path, 'sqlite3.dll')).existsSync() &&
            !File(p.join(Directory.current.path, 'pubspec.yaml')).existsSync()) {
          Directory.current = exeDir;
        }
      }
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        sqflite_ffi.sqfliteFfiInit();
        sqflite.databaseFactory = sqflite_ffi.databaseFactoryFfiNoIsolate;
      }
    } catch (_) {}
    _ffiInitialized = true;
  }

  Future<sqflite.Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    ensureDesktopFfiInitialized();

    final isTestEnv = Platform.environment.containsKey('FLUTTER_TEST');
    String fullPath;
    if (isTestEnv) {
      fullPath = p.join(
        Directory.systemTemp.path,
        'gps_delivery_test_runtime.db',
      );
    } else {
      final hasPubspecInCwd = File(
        p.join(Directory.current.path, 'pubspec.yaml'),
      ).existsSync();
      final baseDirPath = hasPubspecInCwd
          ? Directory.current.path
          : File(Platform.resolvedExecutable).parent.path;
      final localDbDir = Directory(p.join(baseDirPath, 'database'));
      String targetDir;
      try {
        if (!localDbDir.existsSync()) {
          localDbDir.createSync(recursive: true);
        }
        targetDir = localDbDir.path;
      } catch (_) {
        targetDir = Directory.systemTemp.path;
      }
      fullPath = p.join(targetDir, _dbFileName);
    }
    _resolvedDbFilePath = fullPath;

    _database = await sqflite.openDatabase(
      fullPath,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createRelationalSchema16Tables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createRelationalSchema16Tables(db);
      },
    );
    return _database!;
  }

  Future<void> _createRelationalSchema16Tables(sqflite.Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS admin_roles_permissions (
        id TEXT PRIMARY KEY,
        role_name TEXT UNIQUE NOT NULL,
        permissions_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        phone TEXT UNIQUE NOT NULL,
        email TEXT,
        password_hash TEXT NOT NULL,
        full_name TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'CUSTOMER',
        default_address TEXT,
        default_lat REAL NOT NULL DEFAULT 10.7769,
        default_lng REAL NOT NULL DEFAULT 106.6953,
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_addresses (
        id TEXT PRIMARY KEY,
        user_phone TEXT NOT NULL,
        label TEXT NOT NULL,
        full_address TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS drivers (
        id TEXT PRIMARY KEY,
        phone TEXT UNIQUE NOT NULL,
        full_name TEXT NOT NULL,
        citizen_id TEXT NOT NULL,
        license_plate TEXT NOT NULL,
        vehicle_type TEXT NOT NULL,
        vehicle_color TEXT NOT NULL,
        approval_status TEXT NOT NULL,
        is_online INTEGER NOT NULL DEFAULT 1,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        rating REAL NOT NULL DEFAULT 5.0,
        total_trips INTEGER NOT NULL DEFAULT 0,
        wallet_balance REAL NOT NULL DEFAULT 0.0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS merchants (
        id TEXT PRIMARY KEY,
        owner_phone TEXT NOT NULL,
        store_name TEXT NOT NULL,
        business_type TEXT NOT NULL,
        tax_code TEXT NOT NULL,
        representative_name TEXT NOT NULL,
        open_hours TEXT NOT NULL,
        bank_name TEXT NOT NULL,
        bank_account TEXT NOT NULL,
        cod_balance REAL NOT NULL DEFAULT 0.0,
        approval_status TEXT NOT NULL DEFAULT 'APPROVED',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS merchant_pickup_points (
        id TEXT PRIMARY KEY,
        merchant_id TEXT NOT NULL,
        warehouse_name TEXT NOT NULL,
        full_address TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pricing_configs (
        id TEXT PRIMARY KEY,
        service_type TEXT UNIQUE NOT NULL,
        base_fare REAL NOT NULL,
        price_per_km REAL NOT NULL,
        peak_hour_surcharge REAL NOT NULL,
        bad_weather_surcharge REAL NOT NULL,
        is_peak_enabled INTEGER NOT NULL DEFAULT 1,
        is_weather_enabled INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS vouchers (
        code TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        discount_label TEXT NOT NULL,
        discount_value REAL NOT NULL,
        is_percentage INTEGER NOT NULL,
        max_discount REAL NOT NULL,
        min_order_value REAL NOT NULL,
        expiry_date TEXT NOT NULL,
        status TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS orders (
        id TEXT PRIMARY KEY,
        tracking_code TEXT UNIQUE NOT NULL,
        customer_name TEXT NOT NULL,
        recipient_name TEXT NOT NULL,
        recipient_phone TEXT NOT NULL,
        pickup_address TEXT NOT NULL,
        dropoff_address TEXT NOT NULL,
        pickup_lat REAL NOT NULL,
        pickup_lng REAL NOT NULL,
        dropoff_lat REAL NOT NULL,
        dropoff_lng REAL NOT NULL,
        service_type TEXT NOT NULL,
        package_description TEXT NOT NULL,
        weight_kg REAL NOT NULL,
        dimensions_cm TEXT NOT NULL,
        distance_meters INTEGER NOT NULL,
        duration_seconds INTEGER NOT NULL,
        delivery_fee REAL NOT NULL,
        surcharge_fee REAL NOT NULL,
        discount_amount REAL NOT NULL,
        cod_amount REAL NOT NULL,
        total_amount REAL NOT NULL,
        payment_method TEXT NOT NULL,
        payment_status TEXT NOT NULL,
        status TEXT NOT NULL,
        assigned_driver_name TEXT,
        assigned_driver_plate TEXT,
        pod_image_note TEXT,
        cancel_reason TEXT,
        rating_stars INTEGER,
        rating_comment TEXT,
        created_date_label TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_tracking_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id TEXT NOT NULL,
        driver_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        speed REAL NOT NULL,
        bearing REAL NOT NULL,
        is_mock_location INTEGER NOT NULL DEFAULT 0,
        recorded_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS geofence_zones (
        id TEXT PRIMARY KEY,
        zone_name TEXT NOT NULL,
        zone_type TEXT NOT NULL,
        surcharge_rate REAL NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        boundary_json TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS wallets_and_transactions (
        id TEXT PRIMARY KEY,
        owner_name TEXT NOT NULL,
        owner_role TEXT NOT NULL,
        amount REAL NOT NULL,
        bank_name TEXT NOT NULL,
        account_masked TEXT NOT NULL,
        request_date TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cod_reconciliations (
        id TEXT PRIMARY KEY,
        merchant_id TEXT NOT NULL,
        period_label TEXT NOT NULL,
        total_cod_collected REAL NOT NULL,
        total_service_fee REAL NOT NULL,
        net_payout_amount REAL NOT NULL,
        status TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_ratings (
        id TEXT PRIMARY KEY,
        order_tracking_code TEXT UNIQUE NOT NULL,
        customer_name TEXT NOT NULL,
        driver_name TEXT NOT NULL,
        stars INTEGER NOT NULL,
        comment TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS incidents_and_complaints (
        ticket_code TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        customer_name TEXT NOT NULL,
        driver_name TEXT NOT NULL,
        issue_type TEXT NOT NULL,
        description TEXT NOT NULL,
        status TEXT NOT NULL,
        replies_json TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages_and_notifications (
        id TEXT PRIMARY KEY,
        record_type TEXT NOT NULL,
        order_id TEXT,
        sender_name TEXT,
        is_customer INTEGER NOT NULL DEFAULT 1,
        category TEXT,
        title TEXT,
        content TEXT NOT NULL,
        target_group TEXT NOT NULL DEFAULT 'Khách hàng',
        time_label TEXT NOT NULL,
        is_read INTEGER NOT NULL DEFAULT 0,
        created_at_ms INTEGER NOT NULL
      )
    ''');

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

  Future<List<Map<String, dynamic>>> queryRows(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    final db = await database;
    return db.query(
      table,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );
  }

  Future<void> upsertRow(String table, Map<String, Object?> values) async {
    final db = await database;
    await db.insert(
      table,
      values,
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  Future<int> updateRows(
    String table,
    Map<String, Object?> values, {
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final db = await database;
    return db.update(table, values, where: where, whereArgs: whereArgs);
  }

  Future<int> deleteRows(
    String table, {
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final db = await database;
    return db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<int> countRows(String table) async {
    final db = await database;
    final res = await db.rawQuery('SELECT COUNT(*) AS cnt FROM $table');
    return sqflite.Sqflite.firstIntValue(res) ?? 0;
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
