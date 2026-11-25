import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/gps/delivery_live_telemetry.dart';
import 'package:gps_delivery_app/core/gps/driver_multi_trip_planner.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/integrations/delivery_weather_service.dart';
import 'package:gps_delivery_app/core/network/public_json_api.dart';
import 'package:gps_delivery_app/core/theme/app_theme.dart';
import 'package:gps_delivery_app/core/utils/delivery_order_utilities.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/presentation/customer/ghst_home_screen.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_order_details_screen.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_orders_screen.dart';
import 'package:gps_delivery_app/presentation/widgets/admin_fleet_radar_panel.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_session_boundary.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _AdvancedFeatureFixture extends CloudOrdersService {
  _AdvancedFeatureFixture({
    this.actorId = 'user-1',
    this.role = 'customer',
    this.approvedRoles = const [],
    this.isOperator = false,
    List<Map<String, dynamic>>? orders,
    Map<String, Map<String, dynamic>>? gpsByOrderId,
  }) : orders = orders ?? [],
       gpsByOrderId = gpsByOrderId ?? {};

  final String actorId;
  final String role;
  final List<String> approvedRoles;
  final bool isOperator;
  final List<Map<String, dynamic>> orders;
  final Map<String, Map<String, dynamic>> gpsByOrderId;
  final _changes = StreamController<AuthState>.broadcast();

  @override
  bool get signedIn => true;
  @override
  String get userId => actorId;
  @override
  String get email => '$actorId@example.com';
  @override
  String get project => 'advanced-gps-fixture';
  @override
  Stream<AuthState> get authChanges => _changes.stream;

  Future<void> close() => _changes.close();

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == 'profile') {
      return {
        'schema_version': 3,
        'operator': isOperator,
        'account': {
          'user_id': actorId,
          'role': role,
          'full_name': 'Người dùng kiểm thử',
          'phone': '0901234567',
          'blocked': false,
          'approved_roles': approvedRoles,
          'memberships': [
            for (final r in approvedRoles.where((e) => e != 'customer'))
              {'role': r, 'state': 'active', 'version': 1},
          ],
          'coin_balance': 2000,
        },
      };
    }
    if (path == 'addresses') return {'addresses': const []};
    if (path == 'merchants') return {'merchants': const []};
    if (path == 'orders') return {'orders': orders, 'has_more': false};
    if (path == 'order-live/snapshot') {
      final orderId = '${body?['order_id'] ?? ''}';
      final gps =
          gpsByOrderId[orderId] ??
          {
            'latitude': 10.7755,
            'longitude': 106.7020,
            'speed_kmh': 32.0,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          };
      return {
        'gps': gps,
        'latest_gps': gps,
        'order': {'id': orderId, 'latest_gps': gps},
        'driver': {
          'full_name': 'Nguyễn Văn Tài',
          'phone': '0909888777',
          'license_plate': '59X1-999.88',
        },
        'chat': const [],
        'checkpoints': const [],
      };
    }
    if (path.endsWith('/history')) {
      final parts = path.split('/');
      final requestedId = parts.length >= 2
          ? parts[parts.length - 2]
          : (orders.isNotEmpty ? '${orders.first['id']}' : 'ord-1');
      return {
        'history': [
          {
            'order_id': requestedId,
            'version': 2,
            'action': 'pickup',
            'status': 'inTransit',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
          {
            'order_id': requestedId,
            'version': 1,
            'action': 'create',
            'status': 'searching',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
        ],
      };
    }
    if (path == 'driver-dispatch/get_presence') {
      return {
        'presence': {
          'is_online': false,
          'vehicle_type': 'motorbike',
          'allow_batching': true,
        },
        'active_trips_count': orders.length,
      };
    }
    if (path == 'driver-dispatch/poll_offer') {
      return {'offer': null};
    }
    if (path == 'pricing') {
      return {'rules': const [], 'version': 1};
    }
    return {};
  }
}

DeliveryWeatherService _fakeWeatherService() {
  final api = PublicJsonApi(
    client: MockClient(
      (_) async => http.Response(
        jsonEncode({
          'properties': {
            'timeseries': [
              {
                'time': DateTime.now().toUtc().toIso8601String(),
                'data': {
                  'instant': {
                    'details': {'air_temperature': 30.5, 'wind_speed': 3.2},
                  },
                  'next_1_hours': {
                    'summary': {'symbol_code': 'partlycloudy_day'},
                    'details': {'precipitation_amount': 0.2},
                  },
                },
              },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    ),
  );
  return DeliveryWeatherService(api: api);
}

Map<String, dynamic> _mkOrder({
  required String id,
  required String code,
  String status = 'inTransit',
  String ownerId = 'user-1',
  String? driverId = 'drv-1',
  String vehicleType = 'motorbike',
  String serviceType = 'express',
  bool preferEv = false,
  bool requireOtp = false,
  bool isRoundTrip = false,
  int fee = 40000,
  String pickupAddress = '12 Lê Lợi, Q1',
  String dropoffAddress = '88 Nguyễn Huệ, Q1',
  double pickupLat = 10.7720,
  double pickupLng = 106.6980,
  double dropoffLat = 10.7760,
  double dropoffLng = 106.7030,
  List<Map<String, dynamic>> extraStops = const [],
  String recipientPhone = '0912345678',
  String recipientName = 'Khách Nhận',
  String? createdAt,
}) => {
  'id': id,
  'tracking_code': code,
  'status': status,
  'version': 2,
  'owner_id': ownerId,
  'driver_id': driverId,
  'shipping_fee': fee,
  'payable_fee': fee,
  'cod_amount': 0,
  'estimated_earning': (fee * 0.8).round(),
  'payment_status': 'PAID',
  'created_at': createdAt ?? DateTime.now().toUtc().toIso8601String(),
  'details': {
    'pickup_address': pickupAddress,
    'dropoff_address': dropoffAddress,
    'pickup_lat': pickupLat,
    'pickup_lng': pickupLng,
    'dropoff_lat': dropoffLat,
    'dropoff_lng': dropoffLng,
    if (extraStops.isNotEmpty) 'extra_stops': extraStops,
    'recipient_name': recipientName,
    'recipient_phone': recipientPhone,
    'package_description': 'Tài liệu',
    'weight_kg': 2.0,
    'vehicle_type': vehicleType,
    'service_type': serviceType,
    'prefer_ev': preferEv,
    'require_otp': requireOtp,
    'is_round_trip': isRoundTrip,
    'payment_method': 'sender_cash',
  },
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Pure logic: Telemetry, Multi-Trip Planner & Analytics', () {
    test('computeLiveTripTelemetry resolves active targets, live/fallback speed, proximity & stale signal', () {
      final now = DateTime.utc(2026, 11, 25, 8, 30, 0);
      final orderWithStop = _mkOrder(
        id: 't1',
        code: 'GH-T1',
        status: 'arrivingPickup',
        vehicleType: 'truck',
        serviceType: 'truck',
        pickupLat: 10.7720,
        pickupLng: 106.6980,
        dropoffLat: 10.7850,
        dropoffLng: 106.7150,
        extraStops: const [
          {'address': 'Chợ Bến Thành', 'lat': 10.7725, 'lng': 106.6981},
        ],
      );

      final tPickup = computeLiveTripTelemetry(
        order: orderWithStop,
        liveGps: {
          'latitude': 10.7725,
          'longitude': 106.6980,
          'speed_kmh': 36.0,
          'updated_at': now
              .subtract(const Duration(seconds: 20))
              .toIso8601String(),
        },
        now: now,
      );
      expect(tPickup, isNotNull);
      expect(tPickup!.targetLabel, 'Điểm lấy hàng [A]');
      expect(tPickup.usedLiveSpeed, isTrue);
      expect(tPickup.effectiveSpeedKmh, 36.0);
      expect(tPickup.isArrivingSoon, isTrue);
      expect(tPickup.isSignalStale, isFalse);
      expect(formatGpsAgeLabel(tPickup.gpsAgeSeconds), 'Vừa cập nhật');

      final orderTransit = {...orderWithStop, 'status': 'inTransit'};
      final tExtraStop = computeLiveTripTelemetry(
        order: orderTransit,
        liveGps: {
          'latitude': 10.7750,
          'longitude': 106.7000,
          'updated_at': now
              .subtract(const Duration(seconds: 185))
              .toIso8601String(),
        },
        now: now,
      );
      expect(tExtraStop, isNotNull);
      expect(tExtraStop!.targetLabel, 'Điểm dừng #1');
      expect(tExtraStop.usedLiveSpeed, isFalse);
      expect(tExtraStop.effectiveSpeedKmh, 24.0);
      expect(tExtraStop.isSignalStale, isTrue);
      expect(formatGpsAgeLabel(tExtraStop.gpsAgeSeconds), 'Tín hiệu cũ (3p)');

      final tDropoffAfterStop = computeLiveTripTelemetry(
        order: orderTransit,
        liveGps: {'latitude': 10.7750, 'longitude': 106.7000},
        completedCheckpoints: const {'stop:0'},
        now: now,
      );
      expect(tDropoffAfterStop!.targetLabel, 'Điểm giao hàng [B]');

      final tReturning = computeLiveTripTelemetry(
        order: {...orderWithStop, 'status': 'returning'},
        liveGps: {'latitude': 10.7800, 'longitude': 106.7100},
        now: now,
      );
      expect(tReturning!.targetLabel, 'Điểm hoàn hàng [A]');

      expect(
        computeLiveTripTelemetry(
          order: {...orderWithStop, 'status': 'delivered'},
          liveGps: {'latitude': 10.7800, 'longitude': 106.7100},
          now: now,
        ),
        isNull,
      );
    });

    test('buildOptimalDriverTripPlan enforces per-order precedence, saves distance and creates Google Maps URL', () {
      // Two orders whose pickups are right next to each other in Q1,
      // while ord-1 drops off far north in Thu Duc and ord-2 drops off in Binh Thanh.
      // Baseline order chain visits A1 -> B1(far) -> A2(back to Q1!) -> B2.
      // Optimal plan picks up A1 -> A2 -> B2 -> B1, strictly saving distance
      // while keeping pickup before dropoff for both orders.
      final ord1 = _mkOrder(
        id: 'o1',
        code: 'GH-01',
        status: 'accepted',
        driverId: 'drv-1',
        pickupLat: 10.7720,
        pickupLng: 106.6980,
        dropoffLat: 10.8520,
        dropoffLng: 106.7720,
        pickupAddress: 'Q1 Pick 1',
        dropoffAddress: 'Thủ Đức Drop 1',
      );
      final ord2 = _mkOrder(
        id: 'o2',
        code: 'GH-02',
        status: 'arrivingPickup',
        driverId: 'drv-1',
        pickupLat: 10.7728,
        pickupLng: 106.6986,
        dropoffLat: 10.8050,
        dropoffLng: 106.7180,
        pickupAddress: 'Q1 Pick 2',
        dropoffAddress: 'Bình Thạnh Drop 2',
      );
      final otherDriverOrder = _mkOrder(
        id: 'o3',
        code: 'GH-03',
        status: 'inTransit',
        driverId: 'drv-other',
      );

      final plan = buildOptimalDriverTripPlan(
        orders: [ord1, ord2, otherDriverOrder],
        driverUserId: 'drv-1',
        driverLocation: const GeoPoint(latitude: 10.7715, longitude: 106.6975),
      );

      expect(plan.activeOrderCount, 2);
      expect(plan.stops.length, 4);
      expect(plan.savedDistanceKm, greaterThan(5.0));
      expect(plan.optimizedDistanceKm, lessThan(plan.originalDistanceKm));

      // Precedence invariant: pickup before dropoff for both orders
      for (final oid in ['o1', 'o2']) {
        final pickIdx = plan.stops.indexWhere(
          (s) => s.orderId == oid && s.kind == DriverStopKind.pickup,
        );
        final dropIdx = plan.stops.indexWhere(
          (s) => s.orderId == oid && s.kind == DriverStopKind.dropoff,
        );
        expect(pickIdx, isNonNegative);
        expect(dropIdx, greaterThan(pickIdx));
      }

      expect(plan.googleMapsDirectionsUri, isNotNull);
      expect(plan.googleMapsDirectionsUri!.host, 'www.google.com');
      expect(
        plan.googleMapsDirectionsUri!.queryParameters['waypoints'],
        isNotEmpty,
      );
    });

    test('summarizeCustomerDeliveryInsights, extractFrequentRoutes and computeAdminFleetMetrics produce accurate metrics', () {
      final now = DateTime.utc(2026, 11, 25, 10, 0, 0);
      final o1 = _mkOrder(
        id: 'c1',
        code: 'GH-C1',
        status: 'delivered',
        vehicleType: 'ev_scooter',
        preferEv: true,
        fee: 30000,
        pickupAddress: 'Kho A',
        dropoffAddress: 'Nhà B',
        recipientPhone: '0901112233',
        createdAt: now.subtract(const Duration(days: 2)).toIso8601String(),
      );
      final o2 = _mkOrder(
        id: 'c2',
        code: 'GH-C2',
        status: 'inTransit',
        vehicleType: 'ev_scooter',
        preferEv: true,
        fee: 35000,
        pickupAddress: 'Kho A',
        dropoffAddress: 'Nhà B',
        recipientPhone: '0901112233',
        createdAt: now.subtract(const Duration(hours: 1)).toIso8601String(),
      );
      final o3 = _mkOrder(
        id: 'c3',
        code: 'GH-C3',
        status: 'searching',
        vehicleType: 'truck',
        serviceType: 'truck',
        fee: 150000,
        pickupAddress: 'Xưởng C',
        dropoffAddress: 'Cảng D',
        recipientPhone: '0987654321',
        createdAt: now.subtract(const Duration(minutes: 25)).toIso8601String(),
      );
      final o4Cancelled = _mkOrder(
        id: 'c4',
        code: 'GH-C4',
        status: 'cancelled',
        vehicleType: 'ev_scooter',
        preferEv: true,
        fee: 50000,
        pickupAddress: 'Kho E',
        dropoffAddress: 'Nhà F',
        recipientPhone: '0977665544',
      );

      final insights = summarizeCustomerDeliveryInsights([
        o1,
        o2,
        o3,
        o4Cancelled,
      ]);
      expect(insights.totalOrders, 4);
      expect(insights.activeOrders, 2);
      expect(insights.deliveredOrders, 1);
      expect(insights.evOrders, 2);
      expect(insights.totalShippingSpendVnd, 215000);
      expect(insights.co2SavedGrams, greaterThan(40));

      final routes = extractFrequentRoutes([o1, o2, o3], limit: 2);
      expect(routes.length, 2);
      expect(routes.first.pickupAddress, 'Kho A');
      expect(routes.first.orderCount, 2);

      final metrics = computeAdminFleetMetrics([
        o1,
        o2,
        o3,
        o4Cancelled,
      ], now: now);
      expect(metrics.total, 4);
      expect(metrics.delivered, 1);
      expect(metrics.completionRatePct, closeTo(25.0, 0.1));
      expect(metrics.evOrders, 3);
      expect(metrics.revenueByVehicle['ev_scooter'], 65000);
      expect(metrics.revenueByVehicle['truck'], 150000);
      expect(metrics.staleSearchingIds, {'c3'});
    });
  });

  group('Widget integration: Telemetry, Customer Insights, Multi-Trip & Radar SLA', () {
    for (final width in [360.0, 1440.0]) {
      testWidgets(
        'CloudOrderDetailsScreen displays live telemetry strip & proximity alert at width $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          final order = _mkOrder(
            id: 'ord-tel',
            code: 'GH-TEL-1',
            status: 'inTransit',
            requireOtp: true,
            dropoffLat: 10.7760,
            dropoffLng: 106.7030,
          );
          final api = _AdvancedFeatureFixture(
            actorId: 'user-1',
            orders: [order],
            gpsByOrderId: {
              'ord-tel': {
                // ~165m from dropoff -> triggers isArrivingSoon <= 300m
                'latitude': 10.7749,
                'longitude': 106.7020,
                'speed_kmh': 30.0,
                'updated_at': DateTime.now()
                    .toUtc()
                    .subtract(const Duration(seconds: 15))
                    .toIso8601String(),
              },
            },
          );
          final session = CloudAccountSession(service: api);
          addTearDown(() async {
            session.dispose();
            await api.close();
          });
          await session.refresh();
          final weather = _fakeWeatherService();

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: CloudSessionBoundary(
                session: session,
                builder: (_, lease) => CloudOrderDetailsScreen(
                  lease: lease,
                  order: order,
                  weatherService: weather,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('order-live-telemetry-strip')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('order-arriving-soon-banner')),
            findsOneWidget,
          );
          expect(find.textContaining('chuẩn bị mã OTP 6 số'), findsOneWidget);
          expect(find.textContaining('ETA:'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'GhstHomeScreen shows EV insights, quick fare/tracking & 1-tap frequent route reorder at width $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          final ev1 = _mkOrder(
            id: 'h1',
            code: 'GH-H1',
            status: 'delivered',
            vehicleType: 'ev_scooter',
            preferEv: true,
            pickupAddress: '12 Lê Lợi, Q1',
            dropoffAddress: '88 Nguyễn Huệ, Q1',
          );
          final ev2 = _mkOrder(
            id: 'h2',
            code: 'GH-H2',
            status: 'delivered',
            vehicleType: 'ev_scooter',
            preferEv: true,
            pickupAddress: '12 Lê Lợi, Q1',
            dropoffAddress: '88 Nguyễn Huệ, Q1',
          );
          final api = _AdvancedFeatureFixture(
            actorId: 'user-1',
            orders: [ev1, ev2],
          );
          final session = CloudAccountSession(service: api);
          addTearDown(() async {
            session.dispose();
            await api.close();
          });
          await session.refresh();

          Map<String, dynamic>? capturedPrefill;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: GhstHomeScreen(
                  session: session,
                  onCreateOrder: (prefill) => capturedPrefill = prefill,
                  onCatalog: () {},
                  onAddresses: () {},
                  onOrders: () {},
                  onAddressChanged: (_) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('home-delivery-insights-card')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('home-frequent-routes-card')),
            findsOneWidget,
          );
          expect(find.text('CO₂ xanh EV'), findsOneWidget);

          final quickSendBtn = find.byKey(
            const ValueKey('home-frequent-route-send-0'),
          );
          await tester.ensureVisible(quickSendBtn);
          await tester.tap(quickSendBtn);
          await tester.pumpAndSettle();

          expect(capturedPrefill, isNotNull);
          expect(capturedPrefill!['vehicle_type'], 'ev_scooter');
          expect(capturedPrefill!['pickup_address'], '12 Lê Lợi, Q1');

          final fareBtn = find.byKey(const ValueKey('home-quick-fare-compare'));
          await tester.ensureVisible(fareBtn);
          await tester.tap(fareBtn);
          await tester.pumpAndSettle();
          expect(
            find.text('Bảng so sánh cước 5 loại xe & 5 gói dịch vụ'),
            findsOneWidget,
          );
          await tester.tap(find.text('Đóng'));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'CloudOrdersScreen driver view opens Lộ trình gộp multi-trip planner dialog cleanly',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final d1 = _mkOrder(
          id: 'd1',
          code: 'GH-D1',
          status: 'accepted',
          driverId: 'drv-1',
          pickupLat: 10.7720,
          pickupLng: 106.6980,
          dropoffLat: 10.8520,
          dropoffLng: 106.7720,
          pickupAddress: 'Kho Quận 1',
          dropoffAddress: 'Thủ Đức',
        );
        final d2 = _mkOrder(
          id: 'd2',
          code: 'GH-D2',
          status: 'arrivingPickup',
          driverId: 'drv-1',
          pickupLat: 10.7725,
          pickupLng: 106.6985,
          dropoffLat: 10.8020,
          dropoffLng: 106.7150,
          pickupAddress: 'Kho Bến Thành',
          dropoffAddress: 'Bình Thạnh',
        );
        final api = _AdvancedFeatureFixture(
          actorId: 'drv-1',
          role: 'driver',
          approvedRoles: const ['driver'],
          orders: [d1, d2],
        );
        final session = CloudAccountSession(service: api);
        addTearDown(() async {
          session.dispose();
          await api.close();
        });
        await session.refresh();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: CloudOrdersScreen(session: session, initialQueue: false),
          ),
        );
        await tester.pumpAndSettle();

        final plannerBtn = find.byKey(
          const ValueKey('driver-multi-trip-planner-btn'),
        );
        expect(plannerBtn, findsOneWidget);
        await tester.tap(plannerBtn);
        await tester.pumpAndSettle();

        expect(find.text('Lộ trình gộp đa chuyến (2 đơn)'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('driver-multi-trip-summary')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('driver-multi-trip-saved-badge')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('driver-multi-trip-open-maps')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'AdminFleetRadarPanel renders SLA/EV metrics and filters stale searching orders',
      (tester) async {
        tester.view.physicalSize = const Size(360, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final staleOrder = _mkOrder(
          id: 'r-stale',
          code: 'GH-STALE',
          status: 'searching',
          driverId: null,
          vehicleType: 'truck',
          serviceType: 'truck',
          fee: 180000,
          createdAt: DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 25))
              .toIso8601String(),
        );
        final deliveredEv = _mkOrder(
          id: 'r-ev',
          code: 'GH-EV-DONE',
          status: 'delivered',
          driverId: 'drv-2',
          vehicleType: 'ev_scooter',
          preferEv: true,
          fee: 32000,
        );
        final api = _AdvancedFeatureFixture(
          actorId: 'op-1',
          isOperator: true,
          orders: [staleOrder, deliveredEv],
        );
        final session = CloudAccountSession(service: api);
        addTearDown(() async {
          session.dispose();
          await api.close();
        });
        await session.refresh();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: CloudSessionBoundary(
                session: session,
                operator: true,
                builder: (_, lease) =>
                    AdminFleetRadarPanel(session: session, lease: lease),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('admin-fleet-sla-metrics-card')),
          findsOneWidget,
        );
        expect(find.text('Phân tích SLA & Cơ cấu đội xe'), findsOneWidget);
        expect(find.text('Tỷ lệ hoàn tất'), findsOneWidget);

        await tester.drag(find.byType(ListView), const Offset(0, -650));
        await tester.pumpAndSettle();
        expect(find.text('GH-STALE'), findsOneWidget);
        expect(find.text('GH-EV-DONE'), findsOneWidget);

        await tester.drag(find.byType(ListView), const Offset(0, 650));
        await tester.pumpAndSettle();
        final staleChip = find.byKey(const ValueKey('radar-stale-sla-filter'));
        await tester.ensureVisible(staleChip);
        await tester.tap(staleChip);
        await tester.pumpAndSettle();

        await tester.drag(find.byType(ListView), const Offset(0, -650));
        await tester.pumpAndSettle();
        expect(find.text('GH-STALE'), findsOneWidget);
        expect(find.text('GH-EV-DONE'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
