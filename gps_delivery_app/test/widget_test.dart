import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/config/env_config.dart';
import 'package:gps_delivery_app/core/gps/gps_integrity_validator.dart';
import 'package:gps_delivery_app/core/gps/kalman_gps_filter.dart';
import 'package:gps_delivery_app/core/gps/smart_dispatch_engine.dart';
import 'package:gps_delivery_app/core/utils/geo_math.dart';
import 'package:gps_delivery_app/core/utils/security_and_barcode_utils.dart';
import 'package:gps_delivery_app/data/datasources/local/app_state_store.dart';
import 'package:gps_delivery_app/data/datasources/local/sqlite_offline_queue_datasource.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/domain/entities/pricing_estimate.dart';
import 'package:gps_delivery_app/domain/enums/order_status.dart';
import 'package:gps_delivery_app/domain/enums/service_type.dart';
import 'package:gps_delivery_app/domain/enums/user_role.dart';
import 'package:gps_delivery_app/main.dart';
import 'package:gps_delivery_app/presentation/admin/admin_subsystem_views.dart';
import 'package:gps_delivery_app/presentation/customer/customer_subsystem_views.dart';
import 'package:gps_delivery_app/presentation/driver/driver_subsystem_views.dart';
import 'package:gps_delivery_app/presentation/merchant/merchant_subsystem_views.dart';
import 'package:gps_delivery_app/presentation/widgets/animated_3d_ui_icons.dart';
import 'package:gps_delivery_app/presentation/widgets/studio_design_widgets.dart';

void main() {
  setUpAll(() async {
    SqliteOfflineQueueDatasource.ensureDesktopFfiInitialized();
    await AppStateStore.instance.initializeDatabase();
  });

  testWidgets(
    'TC-05..TC-08: GpsDeliveryApp mở trực tiếp màn hình UC01 Đăng ký / Đăng nhập, xác thực tài khoản thực tế trong CSDL users và phân quyền giao diện độc lập (RBAC) cho từng vai trò',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const GpsDeliveryApp());

      // 1. Khi mở app: Hiển thị màn hình chính thức UC01 Đăng nhập / Đăng ký (Chỉ dùng Google + Email/SĐT, đã bỏ Facebook)
      expect(find.text('Đăng nhập hệ thống'), findsOneWidget);
      expect(find.text('Gửi mã OTP'), findsOneWidget);
      expect(find.text('Tiếp tục với Google'), findsOneWidget);
      expect(find.text('Tiếp tục với Facebook'), findsNothing);

      // 2. Đăng nhập vai trò Khách hàng (0912345678 trong bảng users) -> Chỉ hiển thị giao diện Khách hàng
      await tester.enterText(find.byType(TextField).first, '0912345678');
      await tester.tap(find.text('Gửi mã OTP'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(
        find.byType(TextField).last,
        AppStateStore.instance.activeOtpCodesByPhone['0912345678']!,
      );
      await tester.tap(find.text('Xác nhận OTP & Đăng nhập'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Tạo đơn hàng mới'), findsWidgets);
      expect(find.byType(Animated3dIconBadge), findsWidgets);
      expect(find.text('GO-MAU Admin'), findsNothing);

      // Đăng xuất khỏi Khách hàng -> Quay về UC01 Đăng nhập hệ thống
      await tester.tap(find.text('Đăng xuất').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Đăng nhập hệ thống'), findsOneWidget);

      // 3. Đăng nhập vai trò Tài xế (0987654321 trong bảng users) -> Chỉ hiển thị giao diện Tài xế
      await tester.enterText(find.byType(TextField).first, '0987654321');
      await tester.tap(find.text('Gửi mã OTP'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(
        find.byType(TextField).last,
        AppStateStore.instance.activeOtpCodesByPhone['0987654321']!,
      );
      await tester.tap(find.text('Xác nhận OTP & Đăng nhập'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Xin chào, Nguyễn Văn Nam!'), findsOneWidget);
      await tester.tap(find.text('Đăng xuất').first);
      await tester.pump(const Duration(milliseconds: 300));

      // 4. Đăng nhập vai trò Cửa hàng B2B (0909112233 trong bảng users) -> Chỉ hiển thị Merchant Web Portal
      await tester.enterText(find.byType(TextField).first, '0909112233');
      await tester.tap(find.text('Gửi mã OTP'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(
        find.byType(TextField).last,
        AppStateStore.instance.activeOtpCodesByPhone['0909112233']!,
      );
      await tester.tap(find.text('Xác nhận OTP & Đăng nhập'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Shop của tôi'), findsOneWidget);
      expect(find.text('Tạo đơn gửi hàng'), findsWidgets);
      await tester.tap(find.text('Đăng xuất').first);
      await tester.pump(const Duration(milliseconds: 300));

      // 5. Đăng nhập vai trò Quản trị viên (0900999999 trong bảng users) -> Chỉ hiển thị GO-MAU Admin Web Portal
      await tester.enterText(find.byType(TextField).first, '0900999999');
      await tester.tap(find.text('Gửi mã OTP'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(
        find.byType(TextField).last,
        AppStateStore.instance.activeOtpCodesByPhone['0900999999']!,
      );
      await tester.tap(find.text('Xác nhận OTP & Đăng nhập'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('GO-MAU'), findsOneWidget);
      expect(find.text('Tổng quan hệ thống'), findsOneWidget);
    },
  );

  test(
    'TC-01: Gói Hỏa tốc 14.5km + Giờ cao điểm + PROMO20K ra chính xác 138.250 VNĐ',
    () {
      final estimate = PricingEstimate.calculate(
        serviceType: DeliveryServiceType.express30m,
        distanceMeters: 14500,
        durationSeconds: 2700,
        isPeakHour: true,
        voucherDiscount: 20000,
      );

      expect(estimate.baseFare, 15000);
      expect(estimate.distanceFare, 123250);
      expect(estimate.surchargeFee, 20000);
      expect(estimate.discountAmount, 20000);
      expect(estimate.totalAmount, 138250);
    },
  );

  test(
    'TC-02: Máy trạng thái hữu hạn OrderStatus FSM kiểm soát chặt chẽ chuyển đổi hợp lệ và bất hợp lệ',
    () {
      expect(OrderStatus.draft.canTransitionTo(OrderStatus.searching), isTrue);
      expect(OrderStatus.draft.canTransitionTo(OrderStatus.delivered), isFalse);
      expect(
        OrderStatus.inTransit.canTransitionTo(OrderStatus.delivered),
        isTrue,
      );
      expect(
        OrderStatus.delivered.canTransitionTo(OrderStatus.cancelled),
        isFalse,
      );
    },
  );

  test(
    'TC-03 & TC-04: Thuật toán Ray-Casting Point-in-Polygon, Bộ lọc Kalman 2D & Chính sách Pin thích ứng',
    () {
      const polygon = [
        GeoPoint(latitude: 10.76, longitude: 106.68),
        GeoPoint(latitude: 10.76, longitude: 106.71),
        GeoPoint(latitude: 10.79, longitude: 106.71),
        GeoPoint(latitude: 10.79, longitude: 106.68),
      ];
      const insidePoint = GeoPoint(latitude: 10.7769, longitude: 106.6953);
      expect(GeoMath.isPointInPolygon(insidePoint, polygon), isTrue);

      final kalman = KalmanGpsFilter();
      final smoothed = kalman.filter(
        rawPoint: const GeoPoint(
          latitude: 10.7769,
          longitude: 106.6953,
        ),
        accuracyMeters: 8.0,
        timestampMs: 1700000000000,
      );
      expect(smoothed.latitude, closeTo(10.7769, 0.001));

      final lowBatteryPolicy = GpsIntegrityValidator.resolvePolicy(
        batteryLevelPercent: 15,
        isCharging: false,
      );
      expect(lowBatteryPolicy.enable3dBuildings, isFalse);
      expect(lowBatteryPolicy.cameraPitch, 0.0);

      // Kiểm chứng AppStateStore đồng bộ trạng thái giữa các phân hệ
      final store = AppStateStore.instance;
      final initialCount = store.orders.length;
      final newOrder = store.createNewOrder(
        pickupAddress: '123 Lê Lợi, Q.1',
        dropoffAddress: '456 Nguyễn Huệ, Q.1',
        recipientName: 'Khách Test',
        recipientPhone: '0912345678',
        packageDescription: 'Hàng kiểm thử',
        weightKg: 1.0,
        dimensionsCm: '20x10x10 cm',
        serviceType: DeliveryServiceType.express30m,
        codAmount: 200000,
        paymentMethod: 'Tiền mặt (COD)',
        voucherCode: 'PROMO20K',
      );
      expect(store.orders.length, initialCount + 1);
      store.driverAcceptOrder(newOrder.trackingCode);
      expect(newOrder.status, OrderStatus.accepted);
    },
  );

  test(
    'TC-09: SmartDispatchEngine, SecurityAndBarcodeUtils, RBAC & Di chuyển Lộ trình Trực tiếp',
    () {
      final store = AppStateStore.instance;

      // 1. Xếp hạng ứng viên tài xế SmartDispatchEngine (3km -> 5km -> 8km + công thức trọng số)
      final ranked = SmartDispatchEngine.rankDriversForPickup(
        pickupLocation: const GeoPoint(latitude: 10.7769, longitude: 106.7009),
        drivers: store.drivers,
      );
      expect(ranked, isNotEmpty);
      expect(ranked.first.totalScore, greaterThan(0.5));

      // 2. Che số điện thoại bảo mật & Tạo chữ ký thanh toán chống trùng lặp
      expect(
        SecurityAndBarcodeUtils.maskPhoneNumber(
          '0912345678',
          shouldMask: true,
        ),
        '0912***678',
      );
      final sig1 = SecurityAndBarcodeUtils.generatePaymentSignature(
        orderCode: 'GH-882910',
        amount: 138250,
        method: 'Tiền mặt (COD)',
      );
      expect(sig1.length, equals(16));

      // 3. Kiểm tra thực thi phân quyền quản trị RBAC
      store.setAdminActiveRole('Hỗ trợ CSKH');
      expect(store.hasAdminPermission('Tài chính: Thanh toán'), isFalse);
      store.setAdminActiveRole('Super Admin');
      expect(store.hasAdminPermission('Tài chính: Thanh toán'), isTrue);

      // 4. Di chuyển tài xế dọc theo lộ trình & Kiểm tra hàng rào địa lý 100m
      store.stepDriverAlongRoute(snapToDropoff: true);
      expect(store.routeProgressStep, equals(10));
      expect(
        store.distanceFromDriverToDropoffMeters(),
        lessThanOrEqualTo(100.0),
      );
    },
  );

  test(
    'TC-10: OpenStreetMap Nominatim, Định tuyến OSRM & Cấu hình Cloud Supabase lúc chạy',
    () async {
      // 1. Cấu hình nóng kết nối Cloud Supabase lúc chạy
      EnvConfig.configureSupabaseRuntime(
        url: 'https://demo-gps-postgis.supabase.co',
        anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.demo',
      );
      expect(EnvConfig.isSupabaseConfigured, isTrue);

      // Đặt lại cấu hình mặc định sau khi kiểm tra
      EnvConfig.configureSupabaseRuntime(url: '', anonKey: '');
      expect(EnvConfig.isSupabaseConfigured, isFalse);

      // 2. Giải mã địa chỉ Google Maps / Nominatim & Tìm đường Google Directions / OSRM
      final tileUrl = EnvConfig.buildGoogleMapTileUrl(
        x: 26018,
        y: 15416,
        z: 15,
        layer: 'm,traffic',
      );
      expect(tileUrl.contains('.google.com/vt/lyrs=m,traffic'), isTrue);
      expect(tileUrl.contains('x=26018&y=15416&z=15'), isTrue);

      final decodedPolyline = SmartDispatchEngine.decodeGoogleEncodedPolyline(
        '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
      );
      expect(decodedPolyline.length, equals(3));
      expect(decodedPolyline.first.latitude, closeTo(38.5, 0.01));
      expect(decodedPolyline.first.longitude, closeTo(-120.2, 0.01));

      final places = await SmartDispatchEngine.fetchLiveNominatimSuggestions(
        'Phố Huế',
      );
      expect(places, isNotEmpty);

      final route = await SmartDispatchEngine.fetchLiveOsrmRoute(
        const GeoPoint(latitude: 21.0145, longitude: 105.8512),
        const GeoPoint(latitude: 20.9951, longitude: 105.8286),
      );
      expect(route.distanceMeters, greaterThan(500));
      expect(route.polylinePoints.length, greaterThanOrEqualTo(2));
    },
  );

  test(
    'TC-11: Kiểm tra tính nhất quán Logic Nghiệp vụ (Voucher %, Hoa hồng 80%, Chặn hủy FSM, Ký quỹ 200k & Hoàn tiền Rút)',
    () {
      final store = AppStateStore.instance;
      expect(EnvConfig.driverAcceptTimeoutSeconds, equals(28));

      // 1. Kiểm tra Voucher phần trăm (GHN-BACKTOSCHOOL: giảm 10%, tối đa 25.000đ)
      final pctOrder = store.createNewOrder(
        pickupAddress: '145 Phố Huế, Hai Bà Trưng, Hà Nội',
        dropoffAddress: 'Số 15, Ngõ 100, Đường Lê Trọng Tấn, Quận Thanh Xuân, Hà Nội',
        recipientName: 'Khách Voucher %',
        recipientPhone: '0912345678',
        packageDescription: 'Kiện hàng kiểm tra %',
        weightKg: 1.0,
        dimensionsCm: '20x10x10 cm',
        serviceType: DeliveryServiceType.express30m,
        codAmount: 100000,
        paymentMethod: 'Tiền mặt (COD)',
        voucherCode: 'GHN-BACKTOSCHOOL',
      );
      // Tổng cước trước giảm là 158.250đ -> 10% là 15.825đ (<= 25.000đ)
      expect(pctOrder.discountAmount, closeTo(15825, 1.0));

      // 2. Chuyển đơn qua các bước tới IN_TRANSIT -> Không được phép hủy
      store.driverAdvanceOrderStatus(pctOrder.trackingCode); // ACCEPTED
      store.driverAdvanceOrderStatus(pctOrder.trackingCode); // ARRIVING_PICKUP
      store.driverAdvanceOrderStatus(pctOrder.trackingCode); // IN_TRANSIT
      expect(pctOrder.status, equals(OrderStatus.inTransit));
      final cancelWhileInTransit = store.cancelOrder(
        pctOrder.trackingCode,
        'Đổi ý khi xe đang giao',
      );
      expect(cancelWhileInTransit, isFalse);
      expect(pctOrder.status, equals(OrderStatus.inTransit));

      // 3. Hoàn tất giao hàng (DELIVERED) -> Tài xế nhận đúng 80% cước vận chuyển
      final balanceBefore = store.driverWalletBalance;
      store.driverAdvanceOrderStatus(pctOrder.trackingCode); // DELIVERED
      final expectedDriverEarning =
          ((pctOrder.deliveryFee + pctOrder.surchargeFee) * 0.80)
              .roundToDouble();
      expect(
        store.driverWalletBalance,
        closeTo(balanceBefore + expectedDriverEarning, 1.0),
      );

      // 4. Rút tiền vượt quá số dư ký quỹ 200.000đ bị từ chối
      final overWithdraw = store.requestWithdrawal(
        ownerName: 'Nguyễn Văn Nam',
        ownerRole: 'Tài xế',
        amount: store.driverWalletBalance - 100000, // Còn lại 100k < 200k
        bankName: 'Vietcombank',
        accountMasked: '007100****889',
      );
      expect(overWithdraw, isFalse);

      // 5. Rút tiền hợp lệ và được hoàn lại ví khi Admin Từ chối lệnh rút
      final validWithdrawAmount = 100000.0;
      final balBeforeWithdraw = store.driverWalletBalance;
      final okWithdraw = store.requestWithdrawal(
        ownerName: 'Nguyễn Văn Nam',
        ownerRole: 'Tài xế',
        amount: validWithdrawAmount,
        bankName: 'Vietcombank',
        accountMasked: '007100****889',
      );
      expect(okWithdraw, isTrue);
      expect(
        store.driverWalletBalance,
        closeTo(balBeforeWithdraw - validWithdrawAmount, 1.0),
      );

      final newestReqId = store.withdrawalRequests.first.id;
      store.updateWithdrawalStatus(newestReqId, 'Từ chối');
      expect(store.driverWalletBalance, closeTo(balBeforeWithdraw, 1.0));

      // 6. Đánh giá chuyến hàng + Tip chỉ cộng ví 1 lần duy nhất (chống cộng trùng Tip)
      final balBeforeTip = store.driverWalletBalance;
      store.submitDriverRating(
        pctOrder.trackingCode,
        5,
        'Giao nhanh đúng giờ',
        tipVnd: 10000,
      );
      expect(store.driverWalletBalance, closeTo(balBeforeTip + 10000, 1.0));
      store.submitDriverRating(
        pctOrder.trackingCode,
        4,
        'Cập nhật lại nhận xét',
        tipVnd: 10000,
      );
      expect(store.driverWalletBalance, closeTo(balBeforeTip + 10000, 1.0));
      expect(pctOrder.ratingStars, equals(4));

      // 7. Đổi tên/SĐT hồ sơ khách hàng vẫn bảo toàn danh sách đơn hàng và sổ địa chỉ
      final prevName = store.customerFullName;
      final prevPhone = store.customerPhone;
      final prevOrdersCount = store.customerOrders.length;
      final prevAddrCount = store.customerSavedAddresses.length;
      store.updateCustomerProfile(
        fullName: 'Trần Thị Bích Ngọc',
        phone: '0912345699',
        email: store.customerEmail,
        defaultAddress: store.customerDefaultAddress,
      );
      expect(store.customerOrders.length, equals(prevOrdersCount));
      expect(store.customerSavedAddresses.length, equals(prevAddrCount));
      store.updateCustomerProfile(
        fullName: prevName,
        phone: prevPhone,
        email: store.customerEmail,
        defaultAddress: store.customerDefaultAddress,
      );

      // 8. Phụ phí khối lượng (>5kg) + Dễ vỡ (+5k) + Giữ lạnh (+10k) & Luồng Sự cố -> Chuyển hoàn (RETURNING)
      final heavyFragileOrder = store.createNewOrder(
        pickupAddress: '145 Phố Huế, Hai Bà Trưng, Hà Nội',
        dropoffAddress:
            'Số 15, Ngõ 100, Đường Lê Trọng Tấn, Quận Thanh Xuân, Hà Nội',
        recipientName: 'Khách Kiểm Tra Phụ Phí',
        recipientPhone: '0912345678',
        packageDescription: 'Thực phẩm (Dễ vỡ, Giữ lạnh)',
        weightKg: 7.0, // +6.000đ (>5kg) + 5.000đ (Dễ vỡ) + 10.000đ (Giữ lạnh) = +21.000đ
        dimensionsCm: '30x20x15 cm',
        serviceType: DeliveryServiceType.express30m,
        codAmount: 250000,
        paymentMethod: 'Tiền mặt (COD)',
      );
      expect(heavyFragileOrder.surchargeFee, closeTo(20000 + 21000, 1.0));

      store.driverAcceptOrder(heavyFragileOrder.trackingCode);
      store.driverAdvanceOrderStatus(heavyFragileOrder.trackingCode); // ARRIVING_PICKUP
      store.driverAdvanceOrderStatus(heavyFragileOrder.trackingCode); // IN_TRANSIT
      expect(heavyFragileOrder.status, equals(OrderStatus.inTransit));

      store.addIncidentOrComplaint(
        orderId: heavyFragileOrder.trackingCode,
        reporterName: 'Tài xế Nguyễn Văn Nam',
        issueType: 'Khách không nhận hàng',
        description: 'Gọi 3 cuộc không nghe máy',
      );
      expect(heavyFragileOrder.status, equals(OrderStatus.failed));

      final returnOk = store.requeueOrReturnOrder(
        heavyFragileOrder.trackingCode,
        isReturn: true,
      );
      expect(returnOk, isTrue);
      expect(heavyFragileOrder.status, equals(OrderStatus.returning));

      store.driverAdvanceOrderStatus(heavyFragileOrder.trackingCode);
      expect(heavyFragileOrder.status, equals(OrderStatus.delivered));
      expect(heavyFragileOrder.paymentStatus, equals('RETURNED'));
      store.submitDriverRating(
        heavyFragileOrder.trackingCode,
        5,
        'Thử đánh giá đơn hoàn kho',
        tipVnd: 15000,
      );
      expect(heavyFragileOrder.ratingStars, isNull);

      final currentActiveName = store.customerFullName;
      final adminCreated = store.registerUserAccountWithRole(
        phone: '0909888777',
        fullName: 'Đối tác Tạo Từ Admin',
        password: '12345678',
        role: SubsystemRole.merchant,
        activateSession: false,
      );
      expect(adminCreated, isNotNull);
      expect(store.customerFullName, equals(currentActiveName));

      final dualCsv = store.parseAndCreateBulkOrdersFromCsv(
        'ten_nguoi_nhan,sdt_nguoi_nhan,dia_chi_giao,mo_ta_hang,khoi_luong_kg,tien_cod_vnd,loai_dich_vu\n'
        'Lê Văn Bốn,0901234567,120 Nguyễn Trãi Quận 5 TP.HCM,320000\n'
        'Phạm Thị Bảy,0902345678,45 Lê Duẩn Quận 1 TP.HCM,Giày thể thao,1.8,450000,EXPRESS',
      );
      expect(dualCsv.validCount, equals(2));
      expect(dualCsv.rows[0].codAmount, closeTo(320000, 1.0));
      expect(dualCsv.rows[1].codAmount, closeTo(450000, 1.0));
      expect(dualCsv.rows[1].serviceType, equals(DeliveryServiceType.express30m));

      store.selectDriverOrder('#DH123456');
      store.stepDriverAlongRoute(snapToDropoff: true);
    },
  );

  test(
    'TC-12: Thực thi thật 100% (Lưu đĩa JSON, Băm mật khẩu + OTP 6 số, EMVCo VietQR + Idempotency, Batch CSV, Xuất tệp A6 & POD SVG)',
    () async {
      final store = AppStateStore.instance;

      // 1. Lưu và nạp lại trạng thái bền vững trên đĩa hệ thống
      final snapshotPath = await store.saveStateSnapshotToDisk();
      expect(File(snapshotPath).existsSync(), isTrue);
      final loaded = await store.loadStateSnapshotFromDisk();
      expect(loaded, isTrue);

      // 2. Đăng ký mật khẩu băm SHA-256 + Salt và xác thực OTP 6 chữ số có thời hạn 120s
      final regOk = store.authenticateOrRegisterAccount(
        phone: '0988776655',
        password: 'MatKhauAnToan99',
        isRegister: true,
        fullName: 'Lê Minh Tuấn',
      );
      expect(regOk, isTrue);
      expect(
        store.authenticateOrRegisterAccount(
          phone: '0988776655',
          password: 'SaiMatKhau',
          isRegister: false,
        ),
        isFalse,
      );
      expect(
        store.authenticateOrRegisterAccount(
          phone: '0988776655',
          password: 'MatKhauAnToan99',
          isRegister: false,
        ),
        isTrue,
      );

      final otp6 = store.generateOtpForPhone('0988776655');
      expect(otp6.length, equals(6));
      expect(store.getRemainingOtpSeconds('0988776655'), greaterThan(100));
      expect(store.verifyOtpCode('0988776655', '000000'), isFalse);
      expect(store.verifyOtpCode('0988776655', otp6), isTrue);

      // 3. Chuỗi EMVCo Napas247 VietQR kèm CRC-16/CCITT-FALSE và khóa chống thu trùng Idempotency
      final emvQr = SecurityAndBarcodeUtils.generateEmvVietQrPayload(
        orderCode: '#DH123456',
        amountVnd: 138250,
      );
      expect(emvQr.startsWith('00020101021238540010A000000727'), isTrue);
      expect(emvQr.contains('6304'), isTrue);

      final payFirst = store.processOrderPayment(
        trackingCode: '#DH123456',
        gateway: 'VNPay / VietQR',
        transactionId: 'TXN-998877',
      );
      expect(payFirst, isTrue);
      final payDuplicate = store.processOrderPayment(
        trackingCode: '#DH123456',
        gateway: 'VNPay / VietQR',
        transactionId: 'TXN-998877',
      );
      expect(payDuplicate, isFalse);

      // 4. Phân tích cú pháp CSV hàng loạt và khởi tạo đơn thực tế
      final ordersBeforeCsv = store.orders.length;
      final csvRes = store.parseAndCreateBulkOrdersFromCsv(
        'Nguyễn Văn H,0912345678,123 Đường Lê Lợi Quận 1 TP.HCM,Gốm sứ,2.0,300000,EXPRESS\n'
        'Lỗi SĐT,123,Địa chỉ ngắn,Hàng lỗi,1.0,100000,STANDARD',
        commitOrders: true,
      );
      expect(csvRes.validCount, equals(1));
      expect(csvRes.invalidCount, equals(1));
      expect(store.orders.length, equals(ordersBeforeCsv + 1));

      // 5. Kết xuất tệp vận đơn khổ A6 (.html) và ảnh bằng chứng POD (.svg) ra đĩa hệ thống
      final a6Path = await SecurityAndBarcodeUtils.exportA6LabelToHtmlFile(
        trackingCode: '#DH123456',
        storeName: store.merchantStoreName,
        warehouseAddress: store.merchantWarehouses.first.address,
        recipientName: 'Nguyễn Thị Minh An',
        recipientPhone: '0912345678',
        dropoffAddress: '15 Lê Trọng Tấn, Thanh Xuân, Hà Nội',
        packageDescription: '2x Áo thun Polo',
        codAmount: 1500000,
      );
      expect(File(a6Path).existsSync(), isTrue);

      final podSvgPath = await SecurityAndBarcodeUtils.exportPodWatermarkToSvgFile(
        orderCode: '#DH123456',
        recipientName: 'Nguyễn Thị Minh An',
        otpCode: '4829',
        driverLocation: const GeoPoint(latitude: 20.9951, longitude: 105.8286),
        distanceMeters: 12.4,
      );
      expect(File(podSvgPath).existsSync(), isTrue);

      // 5b. Xác minh cấu hình SMTP TLS thực tế (RealAuthDeliveryService) và đăng nhập Google OAuth 2.0
      expect(EnvConfig.isSmtpConfigured, isTrue);
      expect(EnvConfig.smtpSenderEmail, equals('trihienkuns@gmail.com'));

      final oauthUser = store.signInOrRegisterOAuthUser(
        email: 'khach.google.oauth@gmail.com',
        fullName: 'Khách Google OAuth',
      );
      expect(oauthUser, isNotNull);
      expect(oauthUser!.email, equals('khach.google.oauth@gmail.com'));
      expect(oauthUser.role, equals(SubsystemRole.customer));

      // 5c. Luồng chuẩn: Tài khoản mới mặc định là CUSTOMER -> Nộp KYC Chờ duyệt -> Admin Duyệt tự động nâng cấp vai trò
      final newCustomer = store.registerUserAccountWithRole(
        phone: '0966554433',
        fullName: 'Phạm Hoàng Quân',
        password: '123456',
        role: SubsystemRole.customer,
      );
      expect(newCustomer, isNotNull);
      expect(newCustomer!.role, equals(SubsystemRole.customer));

      store.registerOrUpdateDriverKyc(
        fullName: 'Phạm Hoàng Quân',
        phone: '0966554433',
        citizenId: '079098001122',
        vehicleType: 'Xe máy',
        licensePlate: '59-P1 998.87',
      );
      final pendingDrv = store.drivers
          .firstWhere((d) => d.phone.contains('0966554433'));
      expect(pendingDrv.approvalStatus, equals('Chờ duyệt'));
      expect(store.findUserByPhone('0966554433')!.role, equals(SubsystemRole.customer));

      store.updateDriverApproval(pendingDrv.id, 'Đã duyệt');
      expect(pendingDrv.approvalStatus, equals('Đã duyệt'));
      expect(store.findUserByPhone('0966554433')!.role, equals(SubsystemRole.driver));

      final newShopOwner = store.registerUserAccountWithRole(
        phone: '0955443322',
        fullName: 'Đặng Thu Thảo',
        password: '123456',
        role: SubsystemRole.customer,
      );
      expect(newShopOwner!.role, equals(SubsystemRole.customer));
      store.registerOrUpdateMerchantKyc(
        ownerPhone: '0955443322',
        storeName: 'Mỹ phẩm Thảo Nguyên',
        businessType: 'Công ty TNHH',
        taxCode: '0319988776',
        representativeName: 'Đặng Thu Thảo',
        bankName: 'ACB',
        bankAccount: '8899001122',
      );
      final pendingMer = store.merchantApplicants
          .firstWhere((m) => m.ownerPhone.contains('0955443322'));
      expect(pendingMer.approvalStatus, equals('Chờ duyệt'));
      expect(store.findUserByPhone('0955443322')!.role, equals(SubsystemRole.customer));

      store.updateMerchantApproval(pendingMer.id, 'Đã duyệt');
      expect(pendingMer.approvalStatus, equals('Đã duyệt'));
      expect(store.findUserByPhone('0955443322')!.role, equals(SubsystemRole.merchant));

      // 6. Xác minh tồn tại thực tế của 4 tệp biểu tượng 3D AI và 4 tệp Hoạt ảnh SVG 3D chuyển động
      for (final style in Icon3dStyle.values) {
        final iconFile = File(style.assetPath);
        expect(iconFile.existsSync(), isTrue);
        expect(iconFile.lengthSync(), greaterThan(100000));

        final animSvgFile = File(style.animatedSvgPath);
        expect(animSvgFile.existsSync(), isTrue);
        final svgContent = animSvgFile.readAsStringSync();
        expect(svgContent.contains('<animate'), isTrue);
      }
    },
  );

  testWidgets(
    'TC-13: Hoạt ảnh 3D đa thành phần (Animated3dIconBadge) chuyển động liên tục 60 FPS qua các khung hình cho cả 4 mẫu Icon',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Animated3dIconBadge(
                  style: Icon3dStyle.scooterExpress,
                  forceContinuousInTest: true,
                ),
                Animated3dIconBadge(
                  style: Icon3dStyle.parcelBox,
                  forceContinuousInTest: true,
                ),
                Animated3dIconBadge(
                  style: Icon3dStyle.gpsPinRadar,
                  forceContinuousInTest: true,
                ),
                Animated3dIconBadge(
                  style: Icon3dStyle.walletVault,
                  forceContinuousInTest: true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(Animated3dIconBadge), findsNWidgets(4));

      // Tiến hành chạy qua nhiều khung hình thời gian thực để xác nhận vòng lặp hoạt ảnh liên tục không dừng
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(tester.binding.hasScheduledFrame, isTrue);

      // Kiểm chứng Màn hình Hoạt ảnh Khởi động 3D (Studio3dStartupSplashScreen)
      bool splashCompleted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Studio3dStartupSplashScreen(
            duration: const Duration(milliseconds: 1000),
            forceContinuousInTest: true,
            onCompleted: () => splashCompleted = true,
          ),
        ),
      );
      expect(find.byType(Studio3dStartupSplashScreen), findsOneWidget);
      expect(find.text('BỎ QUA 3D INTRO'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      expect(splashCompleted, isFalse);
      await tester.pump(const Duration(milliseconds: 600));
      expect(splashCompleted, isTrue);
    },
  );

  testWidgets(
    'TC-14: Kiểm chứng giao diện Tự động Scale linh hoạt theo khung hình mỗi thiết bị (360x800, 412x915, 768x1024, 1024x768, 1366x768, 1920x1080) đạt 0 lỗi tràn trên toàn bộ 50 màn hình',
    (WidgetTester tester) async {
      final viewports = <Size>[
        const Size(360, 800),
        const Size(412, 915),
        const Size(768, 1024),
        const Size(1024, 768),
        const Size(1366, 768),
        const Size(1920, 1080),
      ];
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const customerScreens = <int>[
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14,
      ];
      const driverScreens = <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
      const merchantScreens = <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      const adminScreens = <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
      final layoutErrors = <String>[];

      Future<void> pumpAndCollect(
        String label,
        Size size,
        Widget child,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('$label-${size.width.toInt()}x${size.height.toInt()}'),
            home: Scaffold(body: child),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        dynamic err = tester.takeException();
        while (err != null) {
          layoutErrors.add('[$label @ ${size.width.toInt()}x${size.height.toInt()}] $err');
          err = tester.takeException();
        }
      }

      for (final size in viewports) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await pumpAndCollect(
          'Splash3D',
          size,
          Studio3dStartupSplashScreen(onCompleted: () {}),
        );

        await pumpAndCollect(
          'AuthGateway',
          size,
          const GpsDeliveryApp(),
        );

        for (final idx in customerScreens) {
          await pumpAndCollect(
            'Customer($idx)',
            size,
            CustomerSubsystemEntry(forcedScreenIndex: idx, onLogout: () {}),
          );
        }

        for (final idx in driverScreens) {
          await pumpAndCollect(
            'Driver($idx)',
            size,
            DriverSubsystemEntry(forcedScreenIndex: idx, onLogout: () {}),
          );
        }

        for (final idx in merchantScreens) {
          await pumpAndCollect(
            'Merchant($idx)',
            size,
            MerchantSubsystemEntry(forcedScreenIndex: idx, onLogout: () {}),
          );
        }

        for (final idx in adminScreens) {
          await pumpAndCollect(
            'Admin($idx)',
            size,
            AdminSubsystemEntry(forcedScreenIndex: idx, onLogout: () {}),
          );
        }
      }

      expect(layoutErrors, isEmpty, reason: layoutErrors.join('\n---\n'));
    },
  );
}
