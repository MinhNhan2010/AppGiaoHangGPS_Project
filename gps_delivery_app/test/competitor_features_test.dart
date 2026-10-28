import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/gps/smart_dispatch_engine.dart';
import 'package:gps_delivery_app/core/utils/geo_math.dart';
import 'package:gps_delivery_app/core/utils/security_and_barcode_utils.dart';
import 'package:gps_delivery_app/data/datasources/local/app_state_store.dart';
import 'package:gps_delivery_app/data/datasources/local/sqlite_offline_queue_datasource.dart';
import 'package:gps_delivery_app/data/datasources/remote/supabase_postgis_datasource.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/domain/entities/pricing_estimate.dart';
import 'package:gps_delivery_app/domain/enums/service_type.dart';
import 'package:gps_delivery_app/domain/enums/user_role.dart';
import 'package:gps_delivery_app/main.dart';
import 'package:gps_delivery_app/presentation/customer/customer_subsystem_views.dart';
import 'package:gps_delivery_app/presentation/merchant/merchant_subsystem_views.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppStateStore store;

  setUpAll(() async {
    SqliteOfflineQueueDatasource.ensureDesktopFfiInitialized();
    store = AppStateStore.instance;
    await store.initializeDatabase();
  });

  test(
    'Feature 5 (GrabExpress): Nearest-Neighbor + 2-Opt TSP optimizes multi-stop order & supports round-trip + per-stop completion',
    () async {
      const pickup = GeoPoint(latitude: 10.7769, longitude: 106.7009);
      final zigzagStops = <Map<String, dynamic>>[
        {
          'address': 'Điểm xa Quận 7',
          'latitude': 10.7295,
          'longitude': 106.7218,
          'recipientName': 'Khách Trạm Xa',
          'recipientPhone': '0901111222',
        },
        {
          'address': 'Điểm gần Quận 1',
          'latitude': 10.7735,
          'longitude': 106.7040,
          'recipientName': 'Khách Trạm Gần',
          'recipientPhone': '0903333444',
        },
        {
          'address': 'Điểm giữa Quận 4',
          'latitude': 10.7575,
          'longitude': 106.7075,
          'recipientName': 'Khách Trạm Giữa',
          'recipientPhone': '0905555666',
        },
      ];

      final oneWayRes = SmartDispatchEngine.optimizeMultiStopRoute(
        pickup: pickup,
        stops: zigzagStops,
        isRoundTrip: false,
      );
      expect(oneWayRes.optimizedStops, hasLength(3));
      expect(
        oneWayRes.optimizedStops.first['address'],
        equals('Điểm gần Quận 1'),
      );
      expect(
        oneWayRes.optimizedDistanceMeters,
        lessThan(oneWayRes.originalDistanceMeters),
      );
      expect(oneWayRes.savedDistanceMeters, greaterThan(0));

      final roundTripRes = SmartDispatchEngine.optimizeMultiStopRoute(
        pickup: pickup,
        stops: zigzagStops,
        isRoundTrip: true,
      );
      expect(
        roundTripRes.optimizedDistanceMeters,
        greaterThan(oneWayRes.optimizedDistanceMeters),
      );
      expect(roundTripRes.routePolyline.last.latitude, closeTo(pickup.latitude, 1e-5));
      expect(
        roundTripRes.routePolyline.last.longitude,
        closeTo(pickup.longitude, 1e-5),
      );

      final created = store.createNewOrder(
        pickupAddress: '72 Lê Thánh Tôn, Quận 1, TP. HCM',
        dropoffAddress: '45 Lê Lợi, Quận 1, TP. HCM',
        recipientName: 'Người nhận Chính',
        recipientPhone: '0912345678',
        packageDescription: 'Hợp đồng ký đóng dấu 2 chiều',
        weightKg: 1.2,
        dimensionsCm: '25 x 20 x 5 cm',
        serviceType: DeliveryServiceType.standard,
        codAmount: 0,
        paymentMethod: 'Tiền mặt (COD)',
        customPickupLocation: pickup,
        customDropoffLocation: const GeoPoint(
          latitude: 10.7735,
          longitude: 106.7040,
        ),
        additionalStops: [
          {
            'address': 'Đoàn Văn Bơ, Quận 4, TP. HCM',
            'latitude': 10.7575,
            'longitude': 106.7075,
            'recipientName': 'Người nhận Phụ',
            'recipientPhone': '0988776655',
          },
        ],
        isRoundTrip: true,
      );

      expect(created.extraStopCount, equals(1));
      expect(created.isRoundTrip, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final persistedStops = await store.orderStopsFor(created.id);
      // 1 điểm lấy (PICKUP) + 2 điểm giao (DROPOFF) + 1 điểm quay về kho/người gửi (RETURN) = 4 trạm
      expect(persistedStops, hasLength(4));
      expect(persistedStops.first['stop_type'], equals('PICKUP'));
      expect(persistedStops.last['stop_type'], equals('RETURN'));

      final firstDropoffOtp = (persistedStops[1]['otp_code'] ?? '').toString();
      expect(firstDropoffOtp.length, equals(4));

      // Sai OTP sẽ bị từ chối
      final wrongOk = await store.completeOrderStop(
        orderId: created.id,
        sequenceNo: 1,
        otpInput: firstDropoffOtp == '0000' ? '9999' : '0000',
      );
      expect(wrongOk, isFalse);

      // Đúng OTP hoàn tất trạm giao #1 (sequence_no = 1)
      final rightOk = await store.completeOrderStop(
        orderId: created.id,
        sequenceNo: 1,
        otpInput: firstDropoffOtp,
      );
      expect(rightOk, isTrue);
      final updatedStops = await store.orderStopsFor(created.id);
      expect(updatedStops[1]['status'], equals('COMPLETED'));
    },
  );

  test(
    'Feature 2 (Be): SAME_DAY_2H co-directional batching pairs same-bearing orders and rejects opposite-bearing orders',
    () {
      final orderSouthEast1 = store.createNewOrder(
        pickupAddress: 'Chợ Bến Thành, Quận 1, TP. HCM',
        dropoffAddress: 'Crescent Mall, Quận 7, TP. HCM',
        recipientName: 'Khách Q7 A',
        recipientPhone: '0911222333',
        packageDescription: 'Mỹ phẩm nội thành 2H',
        weightKg: 3.0,
        dimensionsCm: '20 x 15 x 10 cm',
        serviceType: DeliveryServiceType.sameDay2h,
        codAmount: 150000,
        paymentMethod: 'Tiền mặt (COD)',
        customPickupLocation: const GeoPoint(
          latitude: 10.7725,
          longitude: 106.6980,
        ),
        customDropoffLocation: const GeoPoint(
          latitude: 10.7290,
          longitude: 106.7215,
        ),
      );

      final orderSouthEast2 = store.createNewOrder(
        pickupAddress: '68 Nguyễn Huệ, Quận 1, TP. HCM',
        dropoffAddress: 'Tân Phú, Quận 7, TP. HCM',
        recipientName: 'Khách Q7 B',
        recipientPhone: '0911444555',
        packageDescription: 'Phụ kiện thời trang 2H',
        weightKg: 2.5,
        dimensionsCm: '20 x 15 x 10 cm',
        serviceType: DeliveryServiceType.sameDay2h,
        codAmount: 200000,
        paymentMethod: 'Tiền mặt (COD)',
        customPickupLocation: const GeoPoint(
          latitude: 10.7740,
          longitude: 106.7030,
        ),
        customDropoffLocation: const GeoPoint(
          latitude: 10.7310,
          longitude: 106.7240,
        ),
      );

      expect(orderSouthEast2.batchGroupId, isNotNull);
      expect(orderSouthEast2.batchGroupId, startsWith('BATCH-2H-'));
      expect(orderSouthEast1.batchGroupId, equals(orderSouthEast2.batchGroupId));
      expect(
        store.batchPartnersFor(orderSouthEast1).map((o) => o.id),
        contains(orderSouthEast2.id),
      );

      final orderNorthWest = store.createNewOrder(
        pickupAddress: '70 Nguyễn Huệ, Quận 1, TP. HCM',
        dropoffAddress: 'Sân bay Tân Sơn Nhất, Tân Bình, TP. HCM',
        recipientName: 'Khách Tân Bình',
        recipientPhone: '0911666777',
        packageDescription: 'Tài liệu ngược hướng',
        weightKg: 1.0,
        dimensionsCm: '20 x 15 x 5 cm',
        serviceType: DeliveryServiceType.sameDay2h,
        codAmount: 0,
        paymentMethod: 'Tiền mặt (COD)',
        customPickupLocation: const GeoPoint(
          latitude: 10.7742,
          longitude: 106.7032,
        ),
        customDropoffLocation: const GeoPoint(
          latitude: 10.8185,
          longitude: 106.6588,
        ),
      );

      expect(
        orderNorthWest.batchGroupId,
        isNot(equals(orderSouthEast1.batchGroupId)),
      );
    },
  );

  test(
    'Feature 1 & 4 (Xanh SM + Grab/Be): EV SoC-aware dispatch, CO2 savings & High-value Parcel Insurance filtering',
    () {
      expect(GeoMath.estimateEvCo2SavedGrams(5000), closeTo(240.0, 0.01));

      expect(PricingEstimate.calculateInsuranceFee(0), equals(0.0));
      expect(PricingEstimate.calculateInsuranceFee(200000), equals(2000.0));
      expect(PricingEstimate.calculateInsuranceFee(10000000), equals(50000.0));
      expect(PricingEstimate.calculateInsuranceFee(50000000), equals(150000.0));

      final ecoInsuredEst = PricingEstimate.calculate(
        serviceType: DeliveryServiceType.express30m,
        distanceMeters: 5000,
        durationSeconds: 900,
        isPeakHour: false,
        declaredValueVnd: 10000000,
        greenFundContribution: true,
        preferEcoEv: true,
      );
      expect(ecoInsuredEst.insuranceFee, equals(50000.0));
      expect(ecoInsuredEst.greenContributionFee, equals(1000.0));
      expect(ecoInsuredEst.estimatedCo2SavedGrams, closeTo(240.0, 0.01));

      const pickup = GeoPoint(latitude: 10.7769, longitude: 106.7009);
      final lowBatEvDriver = DriverApplicantRecord(
        id: 'DRV-EV-LOW',
        fullName: 'Tài xế EV Pin yếu',
        phone: '0931000111',
        citizenId: '079099001111',
        vehicleType: 'Xe máy điện (VinFast EV)',
        vehicleColor: 'Xanh lục',
        licensePlate: '59-MD1 111.11',
        approvalStatus: 'Đã duyệt',
        rating: 4.9,
        totalTrips: 40,
        isOnline: true,
        location: const GeoPoint(latitude: 10.7775, longitude: 106.7015),
        walletBalance: 900000,
        isElectricVehicle: true,
        batteryPercent: 12,
      );
      final lowRatingDriver = DriverApplicantRecord(
        id: 'DRV-EV-LOWRATE',
        fullName: 'Tài xế EV Sao thấp',
        phone: '0931000222',
        citizenId: '079099002222',
        vehicleType: 'Xe máy điện (VinFast EV)',
        vehicleColor: 'Xanh lục',
        licensePlate: '59-MD1 222.22',
        approvalStatus: 'Đã duyệt',
        rating: 4.2,
        totalTrips: 25,
        isOnline: true,
        location: const GeoPoint(latitude: 10.7772, longitude: 106.7012),
        walletBalance: 900000,
        isElectricVehicle: true,
        batteryPercent: 90,
      );
      final qualifiedEvDriver = DriverApplicantRecord(
        id: 'DRV-EV-PRO',
        fullName: 'Tài xế EV Chuẩn 5 Sao',
        phone: '0931000333',
        citizenId: '079099003333',
        vehicleType: 'Xe máy điện (VinFast EV)',
        vehicleColor: 'Xanh lục',
        licensePlate: '59-MD1 333.33',
        approvalStatus: 'Đã duyệt',
        rating: 4.95,
        totalTrips: 120,
        isOnline: true,
        location: const GeoPoint(latitude: 10.7780, longitude: 106.7020),
        walletBalance: 900000,
        isElectricVehicle: true,
        batteryPercent: 88,
      );

      final ranked = SmartDispatchEngine.rankDriversForPickup(
        pickupLocation: pickup,
        drivers: [lowBatEvDriver, lowRatingDriver, qualifiedEvDriver],
        requireElectricVehicle: true,
        preferElectricVehicle: true,
        totalOrderRouteMeters: 8000,
        declaredValueVnd: 6000000,
        codAmount: 500000,
        serviceType: DeliveryServiceType.express30m,
      );

      expect(ranked, hasLength(1));
      expect(ranked.single.driver.id, equals('DRV-EV-PRO'));
    },
  );

  testWidgets(
    'Feature 3 (GrabExpress): Public /track route renders live 3D tracking, OTP & masked phone without login',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      store.clearAuthenticatedSession();
      expect(store.activeAuthenticatedUser, isNull);

      final trackedOrder = store.createNewOrder(
        pickupAddress: 'Bitexco Financial Tower, Quận 1, TP. HCM',
        dropoffAddress: 'Landmark 81, Bình Thạnh, TP. HCM',
        recipientName: 'Trần Minh Khôi',
        recipientPhone: '0912345678',
        packageDescription: 'Máy ảnh kỹ thuật số khai giá',
        weightKg: 1.8,
        dimensionsCm: '30 x 20 x 15 cm',
        serviceType: DeliveryServiceType.express30m,
        codAmount: 0,
        paymentMethod: 'Tiền mặt (COD)',
        preferEcoEv: true,
        declaredValueVnd: 12000000,
        greenFundContributed: true,
      );
      final expectedOtp = SecurityAndBarcodeUtils.generateOrderDeliveryOtp4(
        trackedOrder.trackingCode,
      );
      final expectedMaskedPhone = SecurityAndBarcodeUtils.maskPhoneNumber(
        '0912345678',
        shouldMask: true,
      );

      await tester.pumpWidget(
        GpsDeliveryApp(
          initialRoute: '/track?code=${trackedOrder.trackingCode}',
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(tester.takeException(), isNull);
      expect(find.textContaining(trackedOrder.trackingCode), findsWidgets);
      expect(find.textContaining(expectedOtp), findsWidgets);
      expect(find.textContaining(expectedMaskedPhone), findsWidgets);
      expect(find.textContaining('0912345678'), findsNothing);
    },
  );

  test(
    'Feature 6a (GrabFood): Meal-slot detection, SQLite v8 + PostGIS B2B menu sync, multi-criteria GPS ranking, cold-bag cart checkout & reorder favorites',
    () async {
      // 1. MealTimeSlot contextual time-of-day detection
      expect(MealTimeSlot.resolveForHour(8), equals(MealTimeSlot.breakfast));
      expect(MealTimeSlot.resolveForHour(12), equals(MealTimeSlot.lunch));
      expect(
        MealTimeSlot.resolveForHour(15),
        equals(MealTimeSlot.afternoonTea),
      );
      expect(MealTimeSlot.resolveForHour(19), equals(MealTimeSlot.dinner));
      expect(MealTimeSlot.resolveForHour(23), equals(MealTimeSlot.lateNight));

      // 2. Register a B2B Partner Merchant and publish a real dish to SQLite v8
      store.registerUserAccountWithRole(
        phone: '0944556677',
        fullName: 'Chủ Quán Trà & Cơm B2B',
        password: '12345678',
        role: SubsystemRole.customer,
        activateSession: false,
      );
      store.registerOrUpdateMerchantKyc(
        ownerPhone: '0944556677',
        storeName: 'Bếp Xanh Sài Gòn B2B',
        businessType: 'Hộ kinh doanh',
        taxCode: '0318889990',
        representativeName: 'Chủ Quán Trà & Cơm B2B',
        bankName: 'Vietcombank',
        bankAccount: '0071009988776',
      );
      final partnerMer = store.merchantApplicants.firstWhere(
        (m) => m.ownerPhone == '0944556677',
      );
      store.updateMerchantApproval(partnerMer.id, 'Đã duyệt');
      final merUser = store.findUserByPhone('0944556677')!;
      store.applyAuthenticatedUserSession(
        merUser,
        activeWorkspaceRole: SubsystemRole.merchant,
      );

      final createdDish = await store.upsertMerchantMenuItem(
        name: 'Trà Trái Cây Nhiệt Đới Ít Đường',
        priceVnd: 52000,
        description: 'Cam vàng, ổi hồng, hạt chia ngâm lạnh tự nhiên',
        category: 'Cà phê & Trà sữa',
        prepMinutes: 7,
        mealSlots: const ['lunch', 'afternoonTea', 'dinner'],
        isEcoPackaging: true,
        isColdItem: true,
        hasPromoBadge: true,
        customStoreAddress: '68 Nguyễn Huệ, Quận 1, TP. HCM',
        customStoreLocation: const GeoPoint(
          latitude: 10.7745,
          longitude: 106.7035,
        ),
      );

      expect(createdDish.isPartnerMerchant, isTrue);
      expect(createdDish.storeName, equals('Bếp Xanh Sài Gòn B2B'));

      // Verify PostGIS normalization for merchant_menu_items
      final pgMenuRow = SupabasePostgisDatasource.normalizeForPostgisSchema(
        'merchant_menu_items',
        createdDish.toSqlRow(),
      );
      expect(
        pgMenuRow['store_location'],
        equals('SRID=4326;POINT(106.7035 10.7745)'),
      );
      expect(pgMenuRow['is_cold_item'], isTrue);

      // Verify SQLite v8 cold reload persistence
      await store.reloadFromSqlite();
      final reloadedDish = store.merchantMenuItems
          .where((m) => m.id == createdDish.id)
          .firstOrNull;
      expect(reloadedDish, isNotNull);
      expect(reloadedDish!.name, equals('Trà Trái Cây Nhiệt Đới Ít Đường'));

      // 3. Multi-criteria GPS ranking near District 1, HCMC
      const customerQ1 = GeoPoint(latitude: 10.7750, longitude: 106.7020);
      final afternoonVenues =
          GrabFoodRecommendationEngine.rankRecommendedVenues(
            customerLocation: customerQ1,
            partnerMenuItems: store.merchantMenuItems,
            selectedSlot: MealTimeSlot.afternoonTea,
            quickFilter: GrabFoodQuickFilter.coffeeMilkTea,
          );
      expect(afternoonVenues, isNotEmpty);
      expect(
        afternoonVenues.any((v) => v.storeName == 'Bếp Xanh Sài Gòn B2B'),
        isTrue,
      );
      // Hanoi café should rank far below nearby HCMC Q.1 venues
      final hcmcIdx = afternoonVenues.indexWhere(
        (v) => v.storeName == 'Bếp Xanh Sài Gòn B2B',
      );
      final hanoiIdx = afternoonVenues.indexWhere(
        (v) => v.storeName.contains('Giảng'),
      );
      if (hanoiIdx >= 0) {
        expect(hcmcIdx, lessThan(hanoiIdx));
      }

      // Near-me (< 3km) filter excludes far-away Hanoi venues
      final nearMeVenues = GrabFoodRecommendationEngine.rankRecommendedVenues(
        customerLocation: customerQ1,
        partnerMenuItems: store.merchantMenuItems,
        quickFilter: GrabFoodQuickFilter.nearMe,
      );
      expect(nearMeVenues.every((v) => v.roadDistanceKm <= 3.0), isTrue);

      // Toggle out-of-stock hides partner dish from recommendations
      await store.toggleMerchantMenuItemAvailability(createdDish.id);
      final afterOutStock = GrabFoodRecommendationEngine.rankRecommendedVenues(
        customerLocation: customerQ1,
        partnerMenuItems: store.merchantMenuItems,
        searchQuery: 'Bếp Xanh Sài Gòn B2B',
      );
      expect(afterOutStock, isEmpty);
      await store.toggleMerchantMenuItemAvailability(createdDish.id);

      // 4. Customer places a multi-item GrabFood cart order with cold item & EV preference
      store.registerUserAccountWithRole(
        phone: '0933888999',
        fullName: 'Khách Ẩm Thực Quận 1',
        password: '12345678',
        role: SubsystemRole.customer,
        activateSession: true,
      );
      final activePartnerDish = store.merchantMenuItems.firstWhere(
        (m) => m.id == createdDish.id,
      );
      final foodOrder = store.createGrabFoodOrder(
        cartEntries: [GrabFoodCartEntry(item: activePartnerDish, quantity: 2)],
        dropoffAddress: 'Bitexco Financial Tower, Quận 1, TP. HCM',
        customDropoffLocation: const GeoPoint(
          latitude: 10.7716,
          longitude: 106.7044,
        ),
        serviceType: DeliveryServiceType.express30m,
        preferEcoEv: true,
        greenFundContributed: true,
        kitchenNote: 'Ít đá, thêm muỗng gỗ',
      );

      // 2 x 52.000đ = 104.000đ food subtotal collected as COD for partner restaurant
      expect(foodOrder.codAmount, equals(104000.0));
      // Cold item auto-attaches [GIỮ LẠNH CHỐNG TAN ĐÁ] & +10.000đ thermal cold-bag surcharge
      expect(
        foodOrder.packageDescription,
        contains('[GrabFood • Bếp Xanh Sài Gòn B2B]'),
      );
      expect(
        foodOrder.packageDescription,
        contains('[GIỮ LẠNH CHỐNG TAN ĐÁ]'),
      );
      expect(foodOrder.surchargeFee, greaterThanOrEqualTo(10000.0));
      expect(foodOrder.preferEcoEv, isTrue);
      expect(activePartnerDish.soldCount, equals(2));

      // Reorder favorites extracts the ordered GrabFood venue for 1-tap reorder
      final reorders = GrabFoodRecommendationEngine.extractReorderFavorites(
        customerOrders: store.customerOrders,
        partnerMenuItems: store.merchantMenuItems,
      );
      expect(
        reorders.any((r) => r.storeName == 'Bếp Xanh Sài Gòn B2B'),
        isTrue,
      );

      // B2B Partner Merchant also sees incoming GrabFood order in merchantPersonalOrders
      store.applyAuthenticatedUserSession(
        merUser,
        activeWorkspaceRole: SubsystemRole.merchant,
      );
      expect(
        store.merchantPersonalOrders.any((o) => o.id == foodOrder.id),
        isTrue,
      );

      // Clean up test menu item
      await store.deleteMerchantMenuItem(createdDish.id);
      store.clearAuthenticatedSession();
    },
  );

  testWidgets(
    'Feature 6b (GrabFood UI): Customer Home Strip, GrabFood Screen (13) & Merchant Menu Manager (11) render cleanly at 360x800 and 1440x900',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      for (final viewport in const [
        Size(360, 800),
        Size(412, 915),
        Size(768, 1024),
        Size(1024, 768),
        Size(1440, 900),
        Size(1920, 1080),
      ]) {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1.0;

        // 1. Customer Home Dashboard (index 0) displays GrabFood discovery strip
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('gf_home_${viewport.width.toInt()}'),
            home: const Scaffold(
              body: CustomerSubsystemEntry(forcedScreenIndex: 0),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('Gợi ý Ăn uống quanh bạn (GrabFood)'),
          findsWidgets,
        );

        // 2. Customer Dedicated GrabFood Screen (index 13) renders meal slots, venues & cart
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('gf_cust13_${viewport.width.toInt()}'),
            home: const Scaffold(
              body: CustomerSubsystemEntry(forcedScreenIndex: 13),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Giỏ hàng GrabFood'), findsWidgets);

        // 3. Merchant B2B GrabFood Menu Manager Screen (index 11) renders cleanly
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('gf_mer11_${viewport.width.toInt()}'),
            home: const Scaffold(
              body: MerchantSubsystemEntry(forcedScreenIndex: 11),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('Quản lý Thực đơn Ăn uống Đối tác B2B'),
          findsWidgets,
        );
      }
    },
  );

  test(
    'Feature 7a (Shopee x Grab Promo Events): Flash Sale, 7-day Check-in, Lucky Spin Wheel, Mystery Blind Box Gacha & GrabChallenges persist in SQLite and discount real orders',
    () async {
      // 1. Register a clean customer account and verify starter wallet without pre-seeding vouchers
      final promoUser = store.registerUserAccountWithRole(
        phone: '0944555666',
        fullName: 'Khách Săn Thưởng Shopee Grab',
        password: '12345678',
        role: SubsystemRole.customer,
        activateSession: true,
      );

      final initialWallet = store.activeCustomerPromoWallet;
      expect(initialWallet.ghstCoins, equals(120));
      expect(initialWallet.spinTickets, equals(2));
      expect(initialWallet.blindBoxTickets, equals(1));
      expect(initialWallet.checkInStreak, equals(0));
      expect(initialWallet.openedBlindBoxes, isEmpty);

      // Verify probability weights sum to 100% and flash window resolver works
      final wheelWeightSum = PromoEventGamificationEngine.spinWheelSegments
          .fold<int>(0, (s, seg) => s + seg.weight);
      final boxWeightSum = PromoEventGamificationEngine.blindBoxPrizePool
          .fold<int>(0, (s, p) => s + p.weight);
      expect(wheelWeightSum, equals(100));
      expect(boxWeightSum, equals(100));
      final noonWindow = PromoEventGamificationEngine.resolveFlashCountdown(
        DateTime(2026, 10, 28, 12, 15),
      );
      expect(noonWindow.activeWindowLabel, contains('12:00'));

      // 2. Daily 7-day check-in streak + duplicate same-day guard
      final day1Time = DateTime(2026, 10, 28, 9, 0);
      final chk1 = store.claimDailyPromoCheckIn(nowOverride: day1Time);
      expect(chk1.success, isTrue);
      expect(chk1.coinsDelta, equals(50));
      expect(store.activeCustomerPromoWallet.checkInStreak, equals(1));

      final chk1Dup = store.claimDailyPromoCheckIn(
        nowOverride: DateTime(2026, 10, 28, 18, 30),
      );
      expect(chk1Dup.success, isFalse);

      final chk2 = store.claimDailyPromoCheckIn(
        nowOverride: DateTime(2026, 10, 29, 9, 0),
      );
      expect(chk2.success, isTrue);
      expect(chk2.coinsDelta, equals(100));
      expect(store.activeCustomerPromoWallet.ghstCoins, equals(270));

      // 3. Flash Sale campaign claim mints real voucher into SQLite
      final flashClaim = store.claimFlashSaleCampaign('CAMP_FLASH_0H_50P');
      expect(flashClaim.success, isTrue);
      expect(flashClaim.mintedVoucherCode, equals('FLASH50P'));
      expect(
        store.vouchers.any((v) => v.code == 'FLASH50P' && v.isUsable),
        isTrue,
      );
      expect(store.activeCustomerPromoWallet.ghstCoins, equals(290));
      expect(store.claimFlashSaleCampaign('CAMP_FLASH_0H_50P').success, isFalse);

      // 4. Lucky Spin Wheel: Jackpot 45K voucher + Blind Box Ticket slice + empty-ticket guard
      final spinJackpot = store.spinLuckyWheel(forcedSegmentIndex: 6);
      expect(spinJackpot.success, isTrue);
      expect(spinJackpot.rarity, equals(PromoRarityTier.legendary));
      expect(spinJackpot.mintedVoucherCode, isNotNull);
      final spinVoucherCode = spinJackpot.mintedVoucherCode!;
      expect(spinVoucherCode, startsWith('SPINJP45K-'));
      expect(store.activeCustomerPromoWallet.spinTickets, equals(1));

      final spinTicketSlice = store.spinLuckyWheel(forcedSegmentIndex: 3);
      expect(spinTicketSlice.success, isTrue);
      expect(spinTicketSlice.blindBoxTicketsDelta, equals(1));
      expect(store.activeCustomerPromoWallet.spinTickets, equals(0));
      expect(store.activeCustomerPromoWallet.blindBoxTickets, equals(2));

      // Out of spin tickets guard
      expect(store.spinLuckyWheel().success, isFalse);

      // 5. Mystery Blind Box Gacha: open SSR 60K box, prevent reopening same box until board reset
      final boxOpen = store.openMysteryBlindBox(
        0,
        forcedPrizeId: 'BB_SSR_60K',
      );
      expect(boxOpen.success, isTrue);
      expect(boxOpen.rarity, equals(PromoRarityTier.legendary));
      expect(boxOpen.mintedVoucherCode, startsWith('BOXSSR60K-'));
      expect(store.activeCustomerPromoWallet.openedBlindBoxes.containsKey(0), isTrue);

      // Reopening already-unsealed box #0 is blocked
      expect(store.openMysteryBlindBox(0).success, isFalse);

      // Resetting the 6-box board reseals all boxes while keeping rewards
      store.resetMysteryBlindBoxBoard();
      expect(store.activeCustomerPromoWallet.openedBlindBoxes, isEmpty);

      // 6. Exchange GHST Xu for +1 Spin Ticket
      final beforeExchangeSpins = store.activeCustomerPromoWallet.spinTickets;
      final exchangeRes = store.exchangePromoCoins(targetType: 'SPIN_TICKET');
      expect(exchangeRes.success, isTrue);
      expect(
        store.activeCustomerPromoWallet.spinTickets,
        equals(beforeExchangeSpins + 1),
      );

      // 7. Cold-reload from SQLite preserves minted vouchers and promo wallet state
      expect(promoUser, isNotNull);
      await store.reloadFromSqlite();
      store.applyAuthenticatedUserSession(
        promoUser!,
        activeWorkspaceRole: SubsystemRole.customer,
      );
      expect(
        store.vouchers.any((v) => v.code == spinVoucherCode && v.isUsable),
        isTrue,
      );
      expect(store.activeCustomerPromoWallet.totalSpinsCount, equals(2));
      expect(store.activeCustomerPromoWallet.totalBlindBoxesOpened, equals(1));

      // 8. Apply Spin Wheel voucher to a real GPS delivery order & claim GrabChallenges mission
      final discountedOrder = store.createNewOrder(
        pickupAddress: 'Chợ Bến Thành, Quận 1, TP. HCM',
        dropoffAddress: 'Landmark 81, Bình Thạnh, TP. HCM',
        recipientName: 'Người Nhận Ưu Đãi',
        recipientPhone: '0909123456',
        packageDescription: 'Quà tặng sự kiện Vòng Xoay',
        weightKg: 1.5,
        dimensionsCm: '20 x 15 x 10 cm',
        serviceType: DeliveryServiceType.express30m,
        codAmount: 0,
        paymentMethod: 'Tiền mặt (COD)',
        voucherCode: spinVoucherCode,
      );
      expect(discountedOrder.discountAmount, greaterThan(0));

      final missionClaim = store.claimPromoMissionReward('MIS_FIRST_SHIP');
      expect(missionClaim.success, isTrue);
      expect(missionClaim.spinTicketsDelta, equals(1));

      store.clearAuthenticatedSession();
    },
  );

  testWidgets(
    'Feature 7b (Promo Events UI): Home Banner, Flash Sale, Lucky Spin Wheel & Mystery Blind Box render cleanly across mobile/desktop and animate without overflow',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      for (final viewport in const [
        Size(360, 800),
        Size(412, 915),
        Size(768, 1024),
        Size(1024, 768),
        Size(1440, 900),
        Size(1920, 1080),
      ]) {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1.0;

        // 1. Customer Home Dashboard (index 0) shows Shopee x Grab Event banner
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('promo_home_${viewport.width.toInt()}'),
            home: const Scaffold(
              body: CustomerSubsystemEntry(forcedScreenIndex: 0),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('SHOPEE × GRAB EVENT'), findsWidgets);

        // 2. Promo & Gamification Hub (index 12) switches cleanly across all 4 sub-tabs
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('promo_hub_${viewport.width.toInt()}'),
            home: const Scaffold(
              body: CustomerSubsystemEntry(forcedScreenIndex: 12),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('SHOPEE FLASH × GRAB REWARDS'),
          findsOneWidget,
        );

        // Switch to Tab 1: Vòng Xoay May Mắn
        final spinTabFinder = find.text('Vòng Xoay May Mắn');
        await tester.ensureVisible(spinTabFinder);
        await tester.tap(spinTabFinder);
        await tester.pump(const Duration(milliseconds: 150));
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('100% TRÚNG QUÀ THẬT'),
          findsOneWidget,
        );

        // Animate a live Spin Wheel turn on 1440x900 desktop viewport
        if (viewport.width == 1440 &&
            store.activeCustomerPromoWallet.spinTickets > 0) {
          final spinBtn = find.text('Bấm Quay Thưởng (-1 Vé)');
          await tester.ensureVisible(spinBtn);
          await tester.tap(spinBtn);
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text('Vòng xoay đang chạy...'), findsOneWidget);
          await tester.pump(const Duration(milliseconds: 2700));
          expect(tester.takeException(), isNull);
          final closeDialogBtn = find.text('Tiếp tục săn thưởng');
          if (closeDialogBtn.evaluate().isNotEmpty) {
            await tester.tap(closeDialogBtn);
            await tester.pump(const Duration(milliseconds: 150));
          }
        }

        // Switch to Tab 2: Hộp Mù Bí Ẩn
        final boxTabFinder = find.text('Hộp Mù Bí Ẩn');
        await tester.ensureVisible(boxTabFinder);
        await tester.tap(boxTabFinder);
        await tester.pump(const Duration(milliseconds: 150));
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('Bàn Gacha 6 Hộp Mù Bí Ẩn (Mystery Blind Box)'),
          findsOneWidget,
        );
        expect(find.text('BOX #01'), findsOneWidget);
        expect(find.text('BOX #06'), findsOneWidget);

        // Switch to Tab 3: Kho Voucher
        final walletTabFinder = find.text('Kho Voucher');
        await tester.ensureVisible(walletTabFinder);
        await tester.tap(walletTabFinder);
        await tester.pump(const Duration(milliseconds: 150));
        expect(tester.takeException(), isNull);
      }
    },
  );
}
