import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/env_config.dart';
import '../../../core/gps/gps_integrity_validator.dart';
import '../../../core/gps/kalman_gps_filter.dart';
import '../../../core/gps/smart_dispatch_engine.dart';
import '../../../core/utils/geo_math.dart';
import '../../../core/utils/security_and_barcode_utils.dart';
import '../../../domain/entities/geo_point.dart';
import '../../../domain/entities/pricing_estimate.dart';
import '../../../domain/enums/order_status.dart';
import '../../../domain/enums/service_type.dart';
import '../../../domain/enums/user_role.dart';
import '../remote/supabase_postgis_datasource.dart';
import 'sqlite_offline_queue_datasource.dart';

import '../../models/app_state_records.dart';
export '../../models/app_state_records.dart';

part 'app_state_seed_and_hydration.dart';
part 'app_state_auth_and_gps_ops.dart';
part 'app_state_order_and_admin_ops.dart';

class AppStateStore extends ChangeNotifier {
  static final AppStateStore instance = AppStateStore._internal();

  final SqliteOfflineQueueDatasource _sqliteDb =
      SqliteOfflineQueueDatasource.instance;
  final KalmanGpsFilter _kalmanFilter = KalmanGpsFilter();
  bool isOfflineMode = false;
  int offlineQueueCount = 0;
  bool isDriverOnline = true;
  bool isMap3dEnabled = true;
  double currentCameraPitch = 55.0;
  int batteryPercent = 85;
  double currentSpeedKmh = 35.0;
  bool isDatabaseReady = false;

  GeoPoint activeDriverLocation =
      const GeoPoint(latitude: 21.0068, longitude: 105.8421);
  double activeDriverBearing = 215.0;
  int routeProgressStep = 4;
  List<GeoPoint> activeRoutePolyline = const [];
  String currentAdminRoleName = 'Super Admin';
  String lastSyncStatusMessage =
      'Đã kết nối CSDL SQLite 16 bảng & đồng bộ PostgreSQL/PostGIS';

  final Map<String, String> registeredUserPasswordHashes = {};
  final Map<String, String> activeOtpCodesByPhone = {};
  final Map<String, int> otpExpiryEpochMsByPhone = {};
  final Set<String> processedPaymentSignatures = {};

  String customerFullName = 'Nguyễn Thu Hà';
  String customerPhone = '0912345678';
  String customerEmail = 'thu.ha@gmail.com';
  String customerDefaultAddress = '123 Đường Lê Lợi, Quận 1, TP. HCM';
  bool isCustomerGoogleLinked = true;
  bool isCustomerFacebookLinked = false;
  String? selectedCustomerOrderCode;

  String activeDriverId = 'DV10928';
  String activeDriverName = 'Nguyễn Văn Nam';
  String activeDriverPhone = '0987654321';
  String? selectedDriverOrderCode;

  double baseFareConfig = 25000;
  double pricePerKmConfig = 5000;
  double peakHourSurchargeConfig = 10000;
  double badWeatherSurchargeConfig = 15000;
  bool isPeakSurchargeActive = true;
  bool isWeatherSurchargeActive = false;

  String merchantStoreName = 'Cửa hàng Gốm Sứ Việt';
  String merchantBusinessType = 'Gốm sứ & Nội thất';
  String merchantTaxCode = '0316892451';
  String merchantRepresentative = 'Nguyễn Văn A';
  String merchantOpenHours = '8:00 AM - 9:00 PM (Thứ 2 - Chủ Nhật)';
  String merchantBankName = 'Ngân hàng VPBank (VPB)';
  String merchantBankAccount = '123456****789';
  double merchantCodBalance = 5250000;
  double driverWalletBalance = 6190000;

  UserAccountRecord? activeAuthenticatedUser;
  final List<UserAccountRecord> users = [];
  final List<SavedAddressRecord> savedAddresses = [];
  final List<PickupWarehouseRecord> merchantWarehouses = [];
  final List<VoucherRecord> vouchers = [];
  final List<ActiveOrderRecord> orders = [];
  final List<ChatMessageRecord> chatMessages = [];
  final List<NotificationRecord> notifications = [];
  final List<DriverApplicantRecord> drivers = [];
  final List<MerchantApplicantRecord> merchantApplicants = [];
  final List<ComplaintTicketRecord> complaints = [];
  final List<WithdrawalRequestRecord> withdrawalRequests = [];
  final List<GeofenceZoneRecord> geofenceZones = [];
  final List<RbacRoleRecord> rbacRoles = [];

  AppStateStore._internal() {
    _populateInitialRelationalRecordsInMemory();
    final defaultPhone = _normalizePhone(customerPhone);
    registeredUserPasswordHashes[defaultPhone] =
        SecurityAndBarcodeUtils.hashPasswordWithSalt('12345678', defaultPhone);
    for (final u in users) {
      registeredUserPasswordHashes[_normalizePhone(u.phone)] = u.passwordHash;
    }
    if (orders.isNotEmpty) {
      activeRoutePolyline = SmartDispatchEngine.generateRoutePolyline(
        orders.first.pickupLocation,
        orders.first.dropoffLocation,
        segments: 10,
      );
    }
    initializeDatabase();
  }

  /// Đường dẫn tệp cơ sở dữ liệu JSON/SQLite lưu trữ bền vững trên đĩa hệ thống
  String get snapshotFilePath =>
      '${Directory.systemTemp.path}${Platform.pathSeparator}gps_delivery_state_snapshot.json';

  String get sqliteDatabasePath => _sqliteDb.databaseFilePath;

  Future<String> saveStateSnapshotToDisk({
    String actionType = 'STATE_SNAPSHOT',
    Map<String, dynamic>? actionPayload,
  }) async {
    final snapshot = <String, dynamic>{
      'savedAtIso': DateTime.now().toIso8601String(),
      'sqliteDatabasePath': _sqliteDb.databaseFilePath,
      'driverWalletBalance': driverWalletBalance,
      'merchantCodBalance': merchantCodBalance,
      'customerFullName': customerFullName,
      'customerPhone': customerPhone,
      'customerEmail': customerEmail,
      'baseFareConfig': baseFareConfig,
      'pricePerKmConfig': pricePerKmConfig,
      'peakHourSurchargeConfig': peakHourSurchargeConfig,
      'badWeatherSurchargeConfig': badWeatherSurchargeConfig,
      'isPeakSurchargeActive': isPeakSurchargeActive,
      'isWeatherSurchargeActive': isWeatherSurchargeActive,
      'processedPaymentSignatures': processedPaymentSignatures.toList(),
      'orders': orders.map((o) => o.toSqlRow()).toList(),
    };
    try {
      final file = File(snapshotFilePath);
      await file.writeAsString(jsonEncode(snapshot), flush: true);
    } catch (_) {}
    try {
      await _sqliteDb.enqueueAction(
        actionType: actionType,
        payload: actionPayload ?? {'snapshotSaved': true},
      );
    } catch (_) {}
    return snapshotFilePath;
  }

  Future<bool> loadStateSnapshotFromDisk() async {
    await initializeDatabase();
    try {
      final file = File(snapshotFilePath);
      if (!await file.exists()) return isDatabaseReady;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      driverWalletBalance =
          (decoded['driverWalletBalance'] as num?)?.toDouble() ??
              driverWalletBalance;
      merchantCodBalance =
          (decoded['merchantCodBalance'] as num?)?.toDouble() ??
              merchantCodBalance;
      customerFullName =
          decoded['customerFullName']?.toString() ?? customerFullName;
      customerPhone = decoded['customerPhone']?.toString() ?? customerPhone;
      customerEmail = decoded['customerEmail']?.toString() ?? customerEmail;
      final sigs = decoded['processedPaymentSignatures'];
      if (sigs is List) {
        processedPaymentSignatures
          ..clear()
          ..addAll(sigs.map((e) => e.toString()));
      }
      notifyListeners();
      return true;
    } catch (_) {
      return isDatabaseReady;
    }
  }

  void _persistMutation(String actionType, Map<String, dynamic> payload) {
    saveStateSnapshotToDisk(actionType: actionType, actionPayload: payload);
    if (EnvConfig.isSupabaseConfigured && !isOfflineMode) {
      final table = payload['table']?.toString();
      final record = payload['record'];
      if (table != null && record is Map<String, dynamic>) {
        SupabasePostgisDatasource()
            .upsertTableRecord(table, record)
            .catchError((_) => <String, dynamic>{});
      }
    }
  }

  String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('84') && digits.length >= 10) {
      return '0${digits.substring(2)}';
    }
    return digits;
  }

  /// Truy vấn bản ghi người dùng từ bảng `users` theo số điện thoại
  UserAccountRecord? findUserByPhone(String phone) {
    final norm = _normalizePhone(phone);
    if (norm.isEmpty) return null;
    return users.where((u) => _normalizePhone(u.phone) == norm).firstOrNull;
  }

  /// Truy vấn bản ghi người dùng từ bảng `users` theo Số điện thoại hoặc Email
  UserAccountRecord? findUserByPhoneOrEmail(String identifier) {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.contains('@')) {
      final lowerEmail = trimmed.toLowerCase();
      return users
          .where((u) => u.email.trim().toLowerCase() == lowerEmail)
          .firstOrNull;
    }
    return findUserByPhone(trimmed);
  }

  /// Truy vấn bản ghi tài xế đang hoạt động trong bảng `drivers` của CSDL SQLite
  DriverApplicantRecord? get activeDriverRecord {
    final byId = drivers.where((d) => d.id == activeDriverId).firstOrNull;
    if (byId != null) return byId;
    final byPhone = drivers
        .where(
          (d) => _normalizePhone(d.phone) == _normalizePhone(activeDriverPhone),
        )
        .firstOrNull;
    return byPhone ?? drivers.firstOrNull;
  }

  /// Truy vấn bản ghi đối tác cửa hàng đang hoạt động trong bảng `merchants` của CSDL SQLite
  MerchantApplicantRecord? get activeMerchantRecord {
    final authPhone = activeAuthenticatedUser?.phone;
    if (authPhone != null && authPhone.isNotEmpty) {
      final byAuth = merchantApplicants
          .where(
            (m) => _normalizePhone(m.ownerPhone) == _normalizePhone(authPhone),
          )
          .firstOrNull;
      if (byAuth != null) return byAuth;
    }
    final byStore = merchantApplicants
        .where((m) => m.storeName == merchantStoreName)
        .firstOrNull;
    return byStore ?? merchantApplicants.firstOrNull;
  }

  /// Truy vấn vận đơn đang hoạt động ưu tiên từ bảng `orders` của CSDL SQLite
  ActiveOrderRecord? get activeOrderRecord {
    if (selectedDriverOrderCode != null) {
      final selected = orders
          .where((o) => o.trackingCode == selectedDriverOrderCode)
          .firstOrNull;
      if (selected != null) {
        return selected;
      }
    }
    final inProgress = orders
        .where(
          (o) =>
              o.status == OrderStatus.inTransit ||
              o.status == OrderStatus.arrivingPickup ||
              o.status == OrderStatus.accepted,
        )
        .firstOrNull;
    if (inProgress != null) return inProgress;
    final searching = orders
        .where((o) => o.status == OrderStatus.searching)
        .firstOrNull;
    return searching ?? orders.firstOrNull;
  }

  void selectDriverOrder(String trackingCode) {
    selectedDriverOrderCode = trackingCode;
    final matched =
        orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (matched != null) {
      activeRoutePolyline = SmartDispatchEngine.generateRoutePolyline(
        matched.pickupLocation,
        matched.dropoffLocation,
        segments: 10,
      );
    }
    _notifyStoreChanged();
  }

  /// Kiểm tra khách hàng hiện tại đã cập nhật số điện thoại thực hay chưa
  bool get hasUserProvidedPhone {
    if (customerPhone.trim().isEmpty) return false;
    if (customerEmail.trim().isNotEmpty) {
      final cleanEmail = customerEmail.trim().toLowerCase();
      final synthetic =
          '09${10000000 + (cleanEmail.hashCode.abs() % 89999999)}';
      if (_normalizePhone(customerPhone) == synthetic) {
        return false;
      }
    }
    return true;
  }

  /// Số điện thoại hiển thị trên giao diện Khách hàng (rỗng nếu mới đăng nhập Google OAuth chưa nhập SĐT)
  String get displayCustomerPhone =>
      hasUserProvidedPhone ? customerPhone : '';

  /// Danh sách vận đơn thuộc về khách hàng đang đăng nhập
  List<ActiveOrderRecord> get customerOrders {
    final targetName = customerFullName.trim().toLowerCase();
    if (targetName.isEmpty) return const [];
    return orders
        .where((o) => o.customerName.trim().toLowerCase() == targetName)
        .toList();
  }

  /// Vận đơn đang hoạt động hoặc được chọn của khách hàng đang đăng nhập
  ActiveOrderRecord? get activeCustomerOrderRecord {
    final list = customerOrders;
    if (selectedCustomerOrderCode != null) {
      final matched = list
          .where((o) => o.trackingCode == selectedCustomerOrderCode)
          .firstOrNull;
      if (matched != null) return matched;
    }
    return list.firstOrNull;
  }

  void selectCustomerOrder(String trackingCode) {
    selectedCustomerOrderCode = trackingCode;
    final matched =
        orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (matched != null) {
      activeRoutePolyline = SmartDispatchEngine.generateRoutePolyline(
        matched.pickupLocation,
        matched.dropoffLocation,
        segments: 10,
      );
    }
    _notifyStoreChanged();
  }

  /// Danh sách địa chỉ đã lưu thuộc về khách hàng đang đăng nhập
  List<SavedAddressRecord> get customerSavedAddresses {
    final norm = _normalizePhone(customerPhone);
    if (norm.isEmpty) return const [];
    return savedAddresses
        .where((a) => _normalizePhone(a.userPhone) == norm)
        .toList();
  }

  /// Danh sách thông báo dành cho khách hàng đang đăng nhập
  List<NotificationRecord> get customerNotifications {
    final myCodes = customerOrders.map((o) => o.trackingCode).toSet();
    return notifications.where((n) {
      if (n.category == 'Đơn hàng') {
        return myCodes.any((code) => n.title.contains(code));
      }
      return true;
    }).toList();
  }

  void _notifyStoreChanged() => notifyListeners();
}
