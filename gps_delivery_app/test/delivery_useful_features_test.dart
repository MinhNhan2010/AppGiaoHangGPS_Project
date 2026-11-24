import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/integrations/delivery_api_client.dart';
import 'package:gps_delivery_app/core/integrations/delivery_weather_service.dart';
import 'package:gps_delivery_app/core/network/public_json_api.dart';
import 'package:gps_delivery_app/core/theme/app_theme.dart';
import 'package:gps_delivery_app/core/utils/delivery_order_utilities.dart';
import 'package:gps_delivery_app/core/utils/security_and_barcode_utils.dart';
import 'package:gps_delivery_app/domain/entities/vehicle_class.dart';
import 'package:gps_delivery_app/presentation/screens/admin_portal_screen.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_order_details_screen.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_orders_screen.dart';
import 'package:gps_delivery_app/presentation/widgets/admin_accounts_panel.dart';
import 'package:gps_delivery_app/presentation/widgets/admin_fleet_radar_panel.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_order_form.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_session_boundary.dart';
import 'package:gps_delivery_app/presentation/widgets/delivery_weather_strip.dart';
import 'package:gps_delivery_app/presentation/widgets/driver_dispatch_cockpit.dart';
import 'package:gps_delivery_app/presentation/widgets/shipping_label_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _UtilityFixture extends CloudOrdersService {
  _UtilityFixture({
    this.actorId = 'user-1',
    this.role = 'customer',
    this.approvedRoles = const [],
    this.isOperator = false,
    List<Map<String, dynamic>>? orders,
    List<Map<String, dynamic>>? queueOrders,
    List<Map<String, dynamic>>? accounts,
  }) : orders = orders ?? [],
       queueOrders = queueOrders ?? [],
       accounts = accounts ?? [];

  final String actorId;
  final String role;
  final List<String> approvedRoles;
  final bool isOperator;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> queueOrders;
  final List<Map<String, dynamic>> accounts;
  final calls = <Map<String, dynamic>>[];
  final chatMessages = <Map<String, dynamic>>[];
  bool presenceOnline = true;
  final _changes = StreamController<AuthState>.broadcast();

  @override
  bool get signedIn => true;
  @override
  String get userId => actorId;
  @override
  String get email => '$actorId@example.com';
  @override
  String get project => 'utility-fixture';
  @override
  Stream<AuthState> get authChanges => _changes.stream;

  void close() => _changes.close();

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add({'path': path, 'body': body, 'query': query});
    if (path == 'profile') {
      return {
        'schema_version': 3,
        'operator': isOperator,
        'account': {
          'user_id': actorId,
          'role': role,
          'full_name': isOperator ? 'Quản trị viên' : 'Người dùng mẫu',
          'phone': '0901234567',
          'blocked': false,
          'approved_roles': approvedRoles,
          'memberships': [
            for (final r in approvedRoles.where((e) => e != 'customer'))
              {'role': r, 'state': 'active', 'version': 1},
          ],
          'coin_balance': 5000,
        },
      };
    }
    if (path == 'merchants') return {'merchants': const []};
    if (path == 'orders') {
      if (query?['queue'] == 'true') {
        return {'orders': queueOrders, 'has_more': false};
      }
      return {'orders': orders, 'has_more': false};
    }
    if (path == 'order-live/snapshot') {
      final orderId = '${body?['order_id'] ?? ''}';
      return {
        'gps': {
          'latitude': 10.7785,
          'longitude': 106.7015,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        'driver': {
          'full_name': 'Tài xế GPS $orderId',
          'phone': '0909111222',
          'license_plate': '59X1-123.45',
        },
        'chat': chatMessages,
        'checkpoints': const [],
      };
    }
    if (path == 'order-live/send_chat') {
      final msg = {
        'id': 'chat-${chatMessages.length + 1}',
        'sender_id': actorId,
        'sender_role': role,
        'sender_name': 'Tài xế Minh',
        'text': body?['text'] ?? '',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      chatMessages.add(msg);
      return {'message': msg};
    }
    if (path.endsWith('/history')) {
      return {
        'history': [
          {
            'order_id': orders.isNotEmpty ? orders.first['id'] : 'ord-1',
            'version': 2,
            'action': 'arrive',
            'status': 'arrivingPickup',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
          {
            'order_id': orders.isNotEmpty ? orders.first['id'] : 'ord-1',
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
          'is_online': presenceOnline,
          'vehicle_type': 'motorbike',
          'allow_batching': true,
        },
        'active_trips_count': 1,
      };
    }
    if (path == 'driver-dispatch/set_presence') {
      presenceOnline = body?['is_online'] == true;
      return {
        'presence': {
          'is_online': presenceOnline,
          'vehicle_type': body?['vehicle_type'] ?? 'motorbike',
          'allow_batching': body?['allow_batching'] != false,
        },
        'active_trips_count': 1,
      };
    }
    if (path == 'driver-dispatch/poll_offer') {
      return {'offer': null};
    }
    if (path == 'admin-accounts/list') {
      return {
        'accounts': accounts,
        'summary': {
          'total_accounts': accounts.length,
          'completed_profiles': accounts.length,
          'incomplete_profiles': 0,
          'operators': 1,
          'active_drivers': 1,
          'active_merchants': 0,
        },
      };
    }
    if (path == 'marketplace/admin_analytics') {
      return {
        'cloud_orders': {
          'total': 4,
          'searching': 1,
          'in_transit': 1,
          'delivered': 2,
          'shipping_fee_delivered': 75000,
        },
        'finance_totals': {'pending_requests': 0},
        'memberships_pending': 1,
      };
    }
    if (path == 'pricing') {
      return {'rules': const [], 'version': 1};
    }
    return {};
  }
}

Map<String, dynamic> _sampleOrder({
  String id = 'ord-1',
  String code = 'GH-1001',
  String status = 'inTransit',
  String ownerId = 'cust-1',
  String? driverId = 'drv-1',
  String vehicleType = 'motorbike',
  String serviceType = 'express',
  int fee = 45000,
  int cod = 150000,
  int estimatedEarning = 36000,
  String? createdAt,
  bool codRemitted = false,
}) => {
  'id': id,
  'tracking_code': code,
  'status': status,
  'version': 2,
  'owner_id': ownerId,
  'driver_id': driverId,
  'merchant_id': 'shop-9',
  'shipping_fee': fee,
  'payable_fee': fee,
  'cod_amount': cod,
  'estimated_earning': estimatedEarning,
  'cod_remitted': codRemitted,
  'payment_status': 'UNPAID',
  'created_at': createdAt ?? DateTime.now().toUtc().toIso8601String(),
  'details': {
    'pickup_address': '12 Lê Lợi, Quận 1, TP.HCM',
    'dropoff_address': '88 Nguyễn Huệ, Quận 1, TP.HCM',
    'pickup_lat': 10.7725,
    'pickup_lng': 106.6980,
    'dropoff_lat': 10.7755,
    'dropoff_lng': 106.7035,
    'recipient_name': 'Nguyễn Văn A',
    'recipient_phone': '0912345678',
    'package_description': 'Tài liệu hợp đồng',
    'weight_kg': 2.0,
    'vehicle_type': vehicleType,
    'service_type': serviceType,
    'payment_method': 'recipient_cash',
    'require_pod': true,
    'scheduled_at': '2025-01-01T08:00:00Z',
    'use_coins': true,
  },
};

DeliveryWeatherService _fakeWeatherService() {
  final api = PublicJsonApi(
    client: MockClient((_) async {
      return http.Response(
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
      );
    }),
  );
  return DeliveryWeatherService(api: api);
}

Future<void> _waitForSnackBar(WidgetTester tester, String prefix) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (find.textContaining(prefix).evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 250));
      return;
    }
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Pure delivery utilities', () {
    test(
      'buildReorderInitialDetails copies core fields and top-level fallbacks',
      () {
        final order = _sampleOrder(vehicleType: 'ev_scooter', cod: 250000);
        final details = buildReorderInitialDetails(order);
        expect(details['pickup_address'], '12 Lê Lợi, Quận 1, TP.HCM');
        expect(details['dropoff_address'], '88 Nguyễn Huệ, Quận 1, TP.HCM');
        expect(details['vehicle_type'], 'ev_scooter');
        expect(details['prefer_ev'], isTrue);
        expect(details['cod_amount'], 250000);
        expect(details['merchant_id'], 'shop-9');
        expect(details.containsKey('scheduled_at'), isFalse);
        expect(details.containsKey('use_coins'), isFalse);
      },
    );

    test('estimateDeliveryFareMatrix covers all 5 classes and weight/distance limits', () {
      final rows = estimateDeliveryFareMatrix(distanceKm: 60, weightKg: 100);
      expect(rows.any((r) => r.vehicle == VehicleClass.motorbike), isTrue);
      expect(rows.any((r) => r.vehicle == VehicleClass.evScooter), isTrue);
      expect(rows.any((r) => r.vehicle == VehicleClass.tricycle), isTrue);
      expect(rows.any((r) => r.vehicle == VehicleClass.van), isTrue);
      expect(rows.any((r) => r.vehicle == VehicleClass.truck), isTrue);

      final moto = rows.firstWhere((r) => r.vehicle == VehicleClass.motorbike);
      expect(moto.selectable, isFalse);
      expect(moto.disabledReason, 'Vượt tải 30 kg');

      final rowsLightLong = estimateDeliveryFareMatrix(
        distanceKm: 60,
        weightKg: 5,
      );
      final sameDay2h = rowsLightLong.firstWhere(
        (r) =>
            r.vehicle == VehicleClass.motorbike &&
            r.serviceType == 'same_day_2h',
      );
      expect(sameDay2h.selectable, isFalse);
      expect(sameDay2h.disabledReason, 'Chỉ hỗ trợ ≤ 50 km');
    });

    test('incident formatter and detector', () {
      final msg = formatDriverIncidentMessage(
        'Kẹt xe / Đường ngập nặng',
        'Ngã tư Hàng Xanh',
      );
      expect(msg, startsWith(driverIncidentTag));
      expect(isDriverIncidentMessage(msg), isTrue);
      expect(isDriverIncidentMessage('Tôi đang tới nơi'), isFalse);
    });

    test('buildOrdersCsv & buildAccountsCsv include BOM and neutralize CSV formulas', () {
      final order = _sampleOrder();
      (order['details'] as Map)['recipient_name'] = '=CMD|calc';
      final csv = buildOrdersCsv([order]);
      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(csv, contains("'=CMD|calc"));
      expect(csv, contains('GH-1001'));

      final accountsCsv = buildAccountsCsv([
        {
          'user_id': 'u-1',
          'full_name': '+SUM(1,2)',
          'email': '@evil.com',
          'phone': '0901234567',
          'citizen_id': '-123',
          'approved_roles': ['driver'],
          'memberships': [
            {'role': 'driver', 'state': 'pending'},
          ],
          'is_operator': false,
          'blocked': false,
          'has_profile': true,
          'orders_count': 3,
          'driver_orders_count': 7,
          'coin_balance': 1200,
        },
      ]);
      expect(accountsCsv.startsWith('\uFEFF'), isTrue);
      expect(accountsCsv, contains("'+SUM(1,2)"));
      expect(accountsCsv, contains("'@evil.com"));
      expect(accountsCsv, contains("'-123"));
      expect(accountsCsv, contains('Tài xế'));
    });

    test('summarizeDriverOrders & summarizeAdminOrders compute shift and stale KPIs', () {
      final now = DateTime.utc(2026, 11, 20, 12, 0);
      final orders = [
        _sampleOrder(
          id: '1',
          status: 'searching',
          driverId: null,
          fee: 30000,
          cod: 0,
          createdAt: now
              .subtract(const Duration(minutes: 25))
              .toIso8601String(),
        ),
        _sampleOrder(
          id: '2',
          status: 'searching',
          driverId: null,
          fee: 20000,
          cod: 50000,
          createdAt: now.subtract(const Duration(minutes: 5)).toIso8601String(),
        ),
        _sampleOrder(
          id: '3',
          status: 'inTransit',
          driverId: 'drv-1',
          fee: 40000,
          cod: 200000,
        ),
        _sampleOrder(
          id: '4',
          status: 'delivered',
          driverId: 'drv-1',
          fee: 50000,
          cod: 100000,
          estimatedEarning: 40000,
          codRemitted: true,
        ),
      ];

      final drvSummary = summarizeDriverOrders(orders, 'drv-1');
      expect(drvSummary.activeCount, 1);
      expect(drvSummary.deliveredCount, 1);
      expect(drvSummary.estimatedEarningsVnd, 40000);
      expect(drvSummary.codHoldingVnd, 200000);

      final adminSummary = summarizeAdminOrders(orders, now: now);
      expect(adminSummary.total, 4);
      expect(adminSummary.searching, 2);
      expect(adminSummary.staleSearching, 1);
      expect(adminSummary.active, 1);
      expect(adminSummary.delivered, 1);
      expect(adminSummary.totalShippingFee, 140000);
      expect(adminSummary.totalCod, 350000);
    });
  });

  group('UI integrations for useful GPS delivery utilities', () {
    testWidgets(
      'CloudOrderForm wires OCR scanner, weather strip & 5x5 fare comparison',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final api = _UtilityFixture();
        addTearDown(api.close);
        final ocrApi = DeliveryApiClient(
          client: MockClient((_) async => http.Response('{}', 200)),
        );
        final weather = _fakeWeatherService();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: CloudOrderForm(
              service: api,
              merchants: const [],
              ocrApi: ocrApi,
              weatherService: weather,
              initialDetails: const {
                'pickup_address': '12 Lê Lợi',
                'dropoff_address': '88 Nguyễn Huệ',
                'pickup_lat': 10.7725,
                'pickup_lng': 106.698,
                'dropoff_lat': 10.7755,
                'dropoff_lng': 106.7035,
                'weight_kg': 2,
                'service_type': 'standard',
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DeliveryWeatherStrip), findsOneWidget);
        expect(find.byType(ShippingLabelScanner), findsOneWidget);

        final compareBtn = find.byKey(const ValueKey('open-fare-comparison'));
        await tester.ensureVisible(compareBtn);
        await tester.tap(compareBtn);
        await tester.pumpAndSettle();

        expect(
          find.text('Bảng so sánh cước 5 loại xe & 5 gói dịch vụ'),
          findsOneWidget,
        );
        final vanRow = find.byKey(const ValueKey('fare-row-van-truck'));
        await tester.ensureVisible(vanRow);
        await tester.tap(vanRow);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('service-tier-truck')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'CloudOrderDetailsScreen supports A6 waybill, navigation, call & driver incident report',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final order = _sampleOrder(status: 'arrivingPickup', driverId: 'drv-1');
        final api = _UtilityFixture(
          actorId: 'drv-1',
          role: 'driver',
          approvedRoles: const ['driver'],
          orders: [order],
        );
        final session = CloudAccountSession(service: api);
        addTearDown(() {
          session.dispose();
          api.close();
        });
        await session.refresh();
        final weather = _fakeWeatherService();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: CloudSessionBoundary(
              session: session,
              roles: const {'customer', 'driver'},
              builder: (_, lease) => CloudOrderDetailsScreen(
                lease: lease,
                order: order,
                weatherService: weather,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DeliveryWeatherStrip), findsOneWidget);
        expect(
          find.byKey(const ValueKey('details-action-navigate')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('details-action-call-recipient')),
          findsOneWidget,
        );

        // 1. A6 Waybill dialog
        await tester.tap(find.byKey(const ValueKey('details-print-waybill')));
        await tester.pumpAndSettle();
        expect(find.text('Phiếu gửi hàng A6 · GH-1001'), findsOneWidget);
        expect(find.byType(Code128BarcodeWidget), findsOneWidget);
        expect(find.byType(QrMatrixPainterWidget), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('waybill-a6-export')));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
        // Cleanup temp file if generated on native
        final generatedChip = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .firstWhere(
              (s) => s.startsWith('Đã tạo phiếu in A6: '),
              orElse: () => '',
            );
        if (generatedChip.isNotEmpty) {
          final f = File(
            generatedChip.replaceFirst('Đã tạo phiếu in A6: ', ''),
          );
          if (f.existsSync()) f.deleteSync();
        }
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();

        // 2. Driver Incident quick report
        final reportBtn = find.byKey(
          const ValueKey('details-action-report-incident'),
        );
        await tester.ensureVisible(reportBtn);
        await tester.tap(reportBtn);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('incident-preset-traffic_flood')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('incident-submit-btn')));
        await tester.pumpAndSettle();

        expect(
          api.calls.any(
            (c) =>
                c['path'] == 'order-live/send_chat' &&
                '${(c['body'] as Map?)?['text']}'.startsWith(driverIncidentTag),
          ),
          isTrue,
        );
        expect(find.textContaining('CẢNH BÁO SỰ CỐ'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'DriverDispatchPresenceBar displays GPS coords, update action & weather strip',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final api = _UtilityFixture(
          actorId: 'drv-1',
          role: 'driver',
          approvedRoles: const ['driver'],
        );
        final session = CloudAccountSession(service: api);
        addTearDown(() {
          session.dispose();
          api.close();
        });
        await session.refresh();
        final weather = _fakeWeatherService();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: CloudSessionBoundary(
                session: session,
                roles: const {'driver'},
                builder: (_, lease) => SingleChildScrollView(
                  child: DriverDispatchPresenceBar(
                    lease: lease,
                    weatherService: weather,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('GPS: '), findsOneWidget);
        expect(
          find.byKey(const ValueKey('driver-refresh-gps')),
          findsOneWidget,
        );
        expect(find.byType(DeliveryWeatherStrip), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('driver-refresh-gps')));
        await tester.pumpAndSettle();
        expect(
          api.calls.any((c) => c['path'] == 'driver-dispatch/set_presence'),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'CloudOrdersScreen supports customer reorder, driver queue sorting/summary & admin KPI/CSV',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1. Customer view: Reorder + 5-vehicle filter
        Map<String, dynamic>? reorderedDetails;
        final custOrder = _sampleOrder(
          id: 'c1',
          code: 'GH-CUST-1',
          status: 'delivered',
          ownerId: 'cust-1',
          vehicleType: 'van',
          serviceType: 'truck',
        );
        final motoOrder = _sampleOrder(
          id: 'c2',
          code: 'GH-MOTO-2',
          status: 'searching',
          ownerId: 'cust-1',
          vehicleType: 'motorbike',
          serviceType: 'standard',
        );
        final custApi = _UtilityFixture(
          actorId: 'cust-1',
          orders: [custOrder, motoOrder],
        );
        final custSession = CloudAccountSession(service: custApi);
        await custSession.refresh();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: CloudOrdersScreen(
              key: const ValueKey('test-orders-cust'),
              session: custSession,
              onReorder: (d) => reorderedDetails = d,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('order-reorder-c1')));
        await tester.pumpAndSettle();
        expect(reorderedDetails, isNotNull);
        expect(reorderedDetails!['vehicle_type'], 'van');

        await tester.tap(find.byKey(const ValueKey('orders-vehicle-filter')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Xe van').last);
        await tester.pumpAndSettle();
        expect(find.textContaining('GH-CUST-1'), findsOneWidget);
        expect(find.textContaining('GH-MOTO-2'), findsNothing);
        custSession.dispose();
        custApi.close();

        // 2. Driver queue sorting & zero-COD filter + Shift Summary on trips tab
        final q1 = _sampleOrder(
          id: 'q1',
          code: 'GH-HIGH-EARN',
          status: 'searching',
          driverId: null,
          cod: 500000,
          estimatedEarning: 120000,
        );
        final q2 = _sampleOrder(
          id: 'q2',
          code: 'GH-NO-COD',
          status: 'searching',
          driverId: null,
          cod: 0,
          estimatedEarning: 45000,
        );
        final tripDelivered = _sampleOrder(
          id: 'd1',
          code: 'GH-DONE-1',
          status: 'delivered',
          driverId: 'drv-1',
          fee: 50000,
          cod: 100000,
          estimatedEarning: 40000,
        );
        final drvApi = _UtilityFixture(
          actorId: 'drv-1',
          role: 'driver',
          approvedRoles: const ['driver'],
          orders: [tripDelivered],
          queueOrders: [q2, q1],
        );
        final drvSession = CloudAccountSession(service: drvApi);
        await drvSession.refresh();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: CloudOrdersScreen(
              key: const ValueKey('test-orders-drv'),
              session: drvSession,
              initialQueue: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('driver-sort-earning_desc')),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('GH-HIGH-EARN'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('driver-queue-zero-cod')));
        await tester.pumpAndSettle();
        expect(find.textContaining('GH-HIGH-EARN'), findsNothing);
        expect(find.textContaining('GH-NO-COD'), findsOneWidget);

        await tester.tap(find.text('Chuyến của tôi'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('driver-shift-summary')),
          findsOneWidget,
        );
        expect(find.textContaining('Thực nhận 80%:'), findsOneWidget);
        drvSession.dispose();
        drvApi.close();

        // 3. Admin KPI strip + Export CSV
        final staleOrder = _sampleOrder(
          id: 'a1',
          code: 'GH-STALE-1',
          status: 'searching',
          driverId: null,
          createdAt: DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 40))
              .toIso8601String(),
        );
        final adminApi = _UtilityFixture(
          actorId: 'op-1',
          role: 'customer',
          approvedRoles: const [],
          isOperator: true,
          orders: [staleOrder],
        );
        final adminSession = CloudAccountSession(service: adminApi);
        await adminSession.refresh();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: CloudOrdersScreen(
              key: const ValueKey('test-orders-admin'),
              session: adminSession,
              admin: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('admin-orders-kpi-strip')),
          findsOneWidget,
        );
        expect(find.textContaining('Chờ >15p: 1'), findsOneWidget);
        final exportOrdersBtn = find.byKey(const ValueKey('orders-export-csv'));
        expect(exportOrdersBtn, findsOneWidget);
        await tester.ensureVisible(exportOrdersBtn);
        await tester.tap(exportOrdersBtn);
        await tester.pump();
        await _waitForSnackBar(tester, 'Đã xuất CSV 1 đơn:');
        expect(find.textContaining('Đã xuất CSV 1 đơn:'), findsOneWidget);
        adminSession.dispose();
        adminApi.close();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'AdminFleetRadarPanel, AdminAccountsPanel CSV & AdminPortalScreen shortcuts work seamlessly',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final staleOrder = _sampleOrder(
          id: 'rad-1',
          code: 'GH-RADAR-1',
          status: 'searching',
          driverId: null,
          vehicleType: 'truck',
          serviceType: 'truck',
          createdAt: DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 30))
              .toIso8601String(),
        );
        final activeMoto = _sampleOrder(
          id: 'rad-2',
          code: 'GH-RADAR-2',
          status: 'inTransit',
          driverId: 'drv-2',
          vehicleType: 'motorbike',
          serviceType: 'express',
        );
        final adminApi = _UtilityFixture(
          actorId: 'op-1',
          role: 'customer',
          approvedRoles: const [],
          isOperator: true,
          orders: [staleOrder, activeMoto],
          accounts: [
            {
              'user_id': 'u-acc-1',
              'full_name': 'Trần Tài Xế',
              'email': 'tx@example.com',
              'phone': '0988777666',
              'citizen_id': '079095001122',
              'approved_roles': ['driver'],
              'memberships': [
                {'role': 'driver', 'state': 'active', 'version': 1},
              ],
              'is_operator': false,
              'blocked': false,
              'has_profile': true,
              'orders_count': 2,
              'driver_orders_count': 9,
              'coin_balance': 500,
            },
          ],
        );
        final session = CloudAccountSession(service: adminApi);
        addTearDown(() {
          session.dispose();
          adminApi.close();
        });
        await session.refresh();

        // 1. Direct AdminFleetRadarPanel test
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

        expect(find.text('Đơn chờ >15p: 1'), findsOneWidget);
        expect(find.text('Xe máy (1)'), findsOneWidget);
        expect(find.text('Tải 1,5T (1)'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('radar-vehicle-truck')));
        await tester.pumpAndSettle();
        expect(find.text('GH-RADAR-1'), findsOneWidget);
        expect(find.text('GH-RADAR-2'), findsNothing);

        // 2. AdminAccountsPanel CSV export
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: CloudSessionBoundary(
                session: session,
                operator: true,
                builder: (_, lease) =>
                    AdminAccountsPanel(session: session, lease: lease),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final accExportBtn = find.byKey(
          const ValueKey('admin-accounts-export-csv'),
        );
        await tester.ensureVisible(accExportBtn);
        await tester.tap(accExportBtn);
        await tester.pump();
        await _waitForSnackBar(tester, 'Đã xuất CSV 1 tài khoản:');
        expect(find.textContaining('Đã xuất CSV 1 tài khoản:'), findsOneWidget);

        // 3. AdminPortalScreen quick shortcut navigates straight to Fleet Radar subtab
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: AdminPortalScreen(session: session),
          ),
        );
        await tester.pumpAndSettle();

        final radarShortcut = find.byKey(
          const ValueKey('admin-shortcut-fleet-radar'),
        );
        await tester.ensureVisible(radarShortcut);
        await tester.tap(radarShortcut);
        await tester.pumpAndSettle();

        expect(find.byType(AdminFleetRadarPanel), findsOneWidget);
        expect(find.text('Vận đơn & Điều phối'), findsOneWidget);
        expect(find.text('Bảng giá động & Geofence'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
