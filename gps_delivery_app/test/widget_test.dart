import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/config/env_config.dart';
import 'package:gps_delivery_app/core/gps/gps_integrity_validator.dart';
import 'package:gps_delivery_app/core/gps/kalman_gps_filter.dart';
import 'package:gps_delivery_app/core/gps/smart_dispatch_engine.dart';
import 'package:gps_delivery_app/core/utils/geo_math.dart';
import 'package:gps_delivery_app/core/utils/security_and_barcode_utils.dart';
import 'package:gps_delivery_app/data/datasources/local/app_state_store.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/domain/entities/pricing_estimate.dart';
import 'package:gps_delivery_app/domain/enums/order_status.dart';
import 'package:gps_delivery_app/domain/enums/service_type.dart';
import 'package:gps_delivery_app/main.dart';

void main() {
  testWidgets(
    'TC-05..TC-08: GpsDeliveryApp renders all 4 subsystems (Customer, Driver, Merchant, Admin) and System States',
    (WidgetTester tester) async {
      await tester.pumpWidget(const GpsDeliveryApp());

      expect(
        find.text('Hệ Thống Giao Hàng Định Vị GPS Đa Nền Tảng'),
        findsOneWidget,
      );
      // Mặc định: Phân hệ Khách hàng (Hình 8.4: UC03 Tạo đơn & Chọn gói dịch vụ)
      expect(
        find.text('Hình 8.4: Tạo đơn hàng & Chọn gói dịch vụ (UC03)'),
        findsOneWidget,
      );

      // Chuyển sang Phân hệ Tài xế (Hình 8.16: UC14)
      await tester.tap(find.text('Phân hệ Tài xế'));
      await tester.pumpAndSettle();
      expect(
        find.text('Hình 8.16: Trang chủ Tài xế & Trạng thái Hoạt động (UC14)'),
        findsOneWidget,
      );

      // Chuyển sang Phân hệ Cửa hàng B2B (Hình 8.38: UC32)
      await tester.tap(find.text('Phân hệ Cửa hàng / Người gửi'));
      await tester.pumpAndSettle();
      expect(
        find.text('Hình 8.38: Tạo Đơn Giao hàng Lẻ B2B (UC32)'),
        findsOneWidget,
      );

      // Chuyển sang Phân hệ Quản trị Admin (Hình 8.24: UC22)
      await tester.tap(find.text('Phân hệ Quản trị viên'));
      await tester.pumpAndSettle();
      expect(
        find.text('Hình 8.24: Dashboard Tổng quan Hệ thống (UC22)'),
        findsOneWidget,
      );
    },
  );

  test(
    'TC-01: UC05 Express 14.5km + Peak + PROMO20K equals 138,250 VND (Hình 8.5)',
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
    'TC-02: OrderStatus FSM enforces valid and invalid transitions (Table 22)',
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
    'TC-03 & TC-04: Ray-Casting Point-in-Polygon, Kalman Filter & Adaptive Battery Policy (Table 36)',
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
    'TC-09: SmartDispatchEngine, SecurityAndBarcodeUtils, RBAC & Live Route Progression',
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
    'TC-10: OpenStreetMap Nominatim, OSRM Street Routing & Runtime Supabase Cloud Config',
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

      // 2. Giải mã địa chỉ Nominatim & Tìm đường OSRM (tự động chuyển sang dự phòng khi offline/test)
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

      // 2. Chuyển đơn qua các bước tới IN_TRANSIT -> Không được phép hủy (RULE-ORD-02)
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

      // 3. Hoàn tất giao hàng (DELIVERED) -> Tài xế nhận đúng 80% cước vận chuyển (RULE-FIN-01)
      final balanceBefore = store.driverWalletBalance;
      store.driverAdvanceOrderStatus(pctOrder.trackingCode); // DELIVERED
      final expectedDriverEarning =
          ((pctOrder.deliveryFee + pctOrder.surchargeFee) * 0.80)
              .roundToDouble();
      expect(
        store.driverWalletBalance,
        closeTo(balanceBefore + expectedDriverEarning, 1.0),
      );

      // 4. Rút tiền vượt quá số dư ký quỹ 200.000đ bị từ chối (RULE-FIN-02)
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
    },
  );
}




