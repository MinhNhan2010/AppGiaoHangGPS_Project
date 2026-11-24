import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/theme/admin_studio_theme.dart';
import 'package:gps_delivery_app/core/theme/app_theme.dart';
import 'package:gps_delivery_app/presentation/widgets/admin_pricing_geofence_panel.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_session_boundary.dart';
import 'package:gps_delivery_app/presentation/widgets/driver_dispatch_cockpit.dart';
import 'package:gps_delivery_app/presentation/widgets/recipient_signature_pad.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RealtimeDispatchPricingFixture extends CloudOrdersService {
  bool authenticated = true;
  bool operator = false;
  String id = 'driver-1';
  String role = 'driver';
  final changes = StreamController<AuthState>.broadcast();
  final calls = <Map<String, dynamic>>[];

  bool isOnline = false;
  String vehicleType = 'motorbike';
  bool allowBatching = true;
  Map<String, dynamic>? pendingOffer;
  List<Map<String, dynamic>> bundles = [
    {
      'bundle_key': 'ord-1:ord-2',
      'order_ids': ['ord-1', 'ord-2'],
      'tracking_codes': ['CL-101', 'CL-102'],
      'order_count': 2,
      'pickup_summary': 'Quận 1 -> Quận 1',
      'dropoff_summary': 'Quận 3 -> Quận 3',
      'pickup_gap_meters': 420,
      'dropoff_gap_meters': 650,
      'bearing_delta_deg': 14.5,
      'corridor_meters': 3800,
      'total_shipping_fee': 50000,
      'estimated_earning': 40000,
      'total_cod_amount': 150000,
    },
  ];

  Map<String, dynamic> basePricing = {
    'id': true,
    'base_fee': 25000,
    'per_km': 5000,
    'express_fee': 10000,
    'extra_kg': 3000,
    'version': 1,
  };
  List<Map<String, dynamic>> pricingRules = [];
  List<Map<String, dynamic>> geofences = [];

  @override
  bool get signedIn => authenticated;

  @override
  String get userId => authenticated ? id : '';

  @override
  String get email => '$id@ghst.vn';

  @override
  String get project => 'ghst-prod';

  @override
  String get identityScope => 'ghst-prod:$userId';

  @override
  Stream<AuthState> get authChanges => changes.stream;

  @override
  Future<void> signOut() async {
    authenticated = false;
    changes.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  @override
  Future<Map<String, dynamic>> command(
    String path,
    Map<String, dynamic> payload,
  ) async {
    calls.add({'method': 'command', 'path': path, 'body': payload});
    return request(path, body: payload);
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add({'path': path, 'body': body, 'query': query});
    if (path == 'profile') {
      return {
        'operator': operator,
        'schema_version': 3,
        'account': {
          'user_id': id,
          'full_name': operator ? 'Điều hành viên GHST' : 'Tài xế Minh Quân',
          'phone': '0942223344',
          'role': role,
          'blocked': false,
          'requested_role': null,
          'approved_roles': role == 'driver' ? ['driver'] : <String>[],
          'memberships': role == 'driver'
              ? [
                  {'role': 'driver', 'state': 'active', 'version': 1},
                ]
              : <Map<String, dynamic>>[],
          'staff_shops': const <Map<String, dynamic>>[],
          'coin_balance': 0,
        },
      };
    }

    if (path.startsWith('driver-dispatch/')) {
      final action = path.substring('driver-dispatch/'.length);
      if (action == 'get_presence') {
        return {
          'presence': {
            'is_online': isOnline,
            'vehicle_type': vehicleType,
            'allow_batching': allowBatching,
            'latitude': 10.7755,
            'longitude': 106.7032,
          },
          'active_trips_count': 0,
        };
      }
      if (action == 'set_presence') {
        isOnline = body?['is_online'] == true;
        vehicleType = '${body?['vehicle_type'] ?? vehicleType}';
        allowBatching = body?['allow_batching'] != false;
        if (isOnline && pendingOffer == null) {
          pendingOffer = {
            'id': 'offer-28s-1',
            'order_id': 'order-near-1',
            'tracking_code': 'CL-NEAR28',
            'distance_to_pickup_meters': 350,
            'order_distance_meters': 2400,
            'radius_tier_km': 3,
            'shipping_fee': 30000,
            'payable_fee': 30000,
            'cod_amount': 120000,
            'estimated_earning': 24000,
            'service_type': 'standard',
            'payment_method': 'sender_cash',
            'prefer_ev': true,
            'require_pod': true,
            'require_signature': true,
            'pickup_area': 'Bến Nghé, Quận 1',
            'dropoff_area': 'Võ Thị Sáu, Quận 3',
            'remaining_seconds': 26,
          };
        }
        return {
          'presence': {
            'is_online': isOnline,
            'vehicle_type': vehicleType,
            'allow_batching': allowBatching,
          },
          'active_trips_count': 0,
          'active_offer': isOnline ? pendingOffer : null,
        };
      }
      if (action == 'poll_offer') {
        return {
          'presence': {
            'is_online': isOnline,
            'vehicle_type': vehicleType,
            'allow_batching': allowBatching,
          },
          'active_trips_count': 0,
          'active_offer': isOnline ? pendingOffer : null,
        };
      }
      if (action == 'respond_offer') {
        final decision = '${body?['decision']}';
        pendingOffer = null;
        if (decision == 'accept') {
          return {
            'accepted': true,
            'order': {
              'id': 'order-near-1',
              'tracking_code': 'CL-NEAR28',
              'status': 'accepted',
              'version': 2,
            },
          };
        }
        return {'accepted': false, 'rejected': true};
      }
      if (action == 'batch_suggestions') {
        return {'bundles': bundles, 'active_trips_count': 0};
      }
      if (action == 'claim_batch') {
        bundles = [];
        return {
          'batch_group_id': 'batch-group-1',
          'orders': [
            {
              'id': 'ord-1',
              'tracking_code': 'CL-101',
              'status': 'accepted',
              'batch_group_id': 'batch-group-1',
              'batch_sequence': 1,
            },
            {
              'id': 'ord-2',
              'tracking_code': 'CL-102',
              'status': 'accepted',
              'batch_group_id': 'batch-group-1',
              'batch_sequence': 2,
            },
          ],
        };
      }
    }

    if (path.startsWith('admin-pricing/')) {
      final action = path.substring('admin-pricing/'.length);
      if (action == 'toggle_surge') {
        final peakOn = body?['peak_enabled'] == true;
        final peakBps = (body?['peak_multiplier_bps'] as num? ?? 12000).toInt();
        pricingRules = [
          {
            'service_type': 'standard',
            'base_fee': 25000,
            'per_km': 5000,
            'peak_enabled': peakOn,
            'peak_multiplier_bps': peakBps,
            'weather_enabled': body?['weather_enabled'] == true,
            'weather_surcharge':
                (body?['weather_surcharge'] as num? ?? 10000).toInt(),
            'active': true,
          },
        ];
        basePricing = {...basePricing, 'version': (basePricing['version'] as int) + 1};
      } else if (action == 'save_geofence') {
        geofences = [
          ...geofences,
          {
            'id': 'geo-q1',
            'name': body?['name'] ?? 'Trung tâm Quận 1',
            'zone_type': body?['zone_type'] ?? 'surge',
            'surcharge_fee': body?['surcharge_fee'] ?? 9000,
            'polygon': body?['polygon'] ?? const [],
            'active': true,
          },
        ];
        basePricing = {...basePricing, 'version': (basePricing['version'] as int) + 1};
      }
      return {
        'base_pricing': basePricing,
        'rules': pricingRules,
        'geofences': geofences,
      };
    }

    return const <String, dynamic>{};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  Future<void> pumpShort(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'Driver radar toggles online, accepts 28s proximity offer & claims corridor Trip Bundle',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fixture = RealtimeDispatchPricingFixture();
      final session = CloudAccountSession(service: fixture)..start();
      addTearDown(() async {
        session.dispose();
        await fixture.changes.close();
      });
      await session.refresh();

      Map<String, dynamic>? acceptedOrder;
      List<Map<String, dynamic>>? claimedBatch;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: CloudSessionBoundary(
              session: session,
              roles: const {'driver'},
              builder: (_, lease) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DriverDispatchPresenceBar(
                    lease: lease,
                    onOrderAccepted: (ord) => acceptedOrder = ord,
                  ),
                  DriverBatchSuggestionsPanel(
                    lease: lease,
                    onBatchClaimed: (list) => claimedBatch = list,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await pumpShort(tester);

      // Corridor Trip Bundle is visible
      expect(find.textContaining('CL-101 + CL-102'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('driver-claim-batch-0')));
      await pumpShort(tester);
      expect(claimedBatch, isNotNull);
      expect(claimedBatch!.length, 2);

      // Toggle online -> receives 28s incoming offer popup
      await tester.tap(find.byKey(const ValueKey('driver-presence-toggle')));
      await pumpShort(tester);

      expect(
        find.byKey(const ValueKey('driver-incoming-offer-dialog')),
        findsOneWidget,
      );
      expect(find.textContaining('CL-NEAR28'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('driver-offer-accept')));
      await pumpShort(tester);

      expect(acceptedOrder, isNotNull);
      expect(acceptedOrder!['tracking_code'], 'CL-NEAR28');
    },
  );

  testWidgets(
    'RecipientSignaturePad exports valid PNG receipt & masked contact sheet hides phone digits',
    (tester) async {
      expect(maskPhoneNumber('0912345678'), '0912***678');

      final sigCtrl = RecipientSignatureController();
      String? quickMsgSent;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  RecipientSignaturePad(
                    controller: sigCtrl,
                    requiredSignature: true,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey('open-safe-sheet'),
                    onPressed: () => showMaskedContactSheet(
                      context: ctx,
                      roleLabel: 'Người nhận hàng',
                      contactName: 'Nguyễn Văn Nhận',
                      rawPhone: '0912345678',
                      maskedPhone: null,
                      onCall: (_) async {},
                      onSendQuickMessage: (msg) async => quickMsgSent = msg,
                      quickPresets: const ['Tài xế đã tới sảnh'],
                    ),
                    icon: const SizedBox(width: 12, height: 12),
                    label: const Text('Mở liên hệ ẩn số'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(sigCtrl.hasSignature, isFalse);
      await tester.drag(
        find.byKey(const ValueKey('recipient-signature-canvas')),
        const Offset(140, 24),
      );
      await tester.pumpAndSettle();
      expect(sigCtrl.hasSignature, isTrue);

      final png = await tester.runAsync(
        () => sigCtrl.toPngBytes(
          trackingCode: 'CL-SIG01',
          signerName: 'Nguyễn Văn Nhận',
        ),
      );
      expect(png, isNotNull);
      expect(png!.take(4).toList(), [137, 80, 78, 71]);

      await tester.tap(find.byKey(const ValueKey('open-safe-sheet')));
      await tester.pumpAndSettle();

      expect(find.textContaining('0912***678'), findsWidgets);
      expect(find.text('0912345678'), findsNothing);

      await tester.tap(find.text('Tài xế đã tới sảnh'));
      await tester.pumpAndSettle();
      expect(quickMsgSent, 'Tài xế đã tới sảnh');

      sigCtrl.dispose();
    },
  );

  testWidgets(
    'Operator Dynamic Pricing & Polygon Geofence Studio saves surge and polygon zone',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fixture = RealtimeDispatchPricingFixture()
        ..operator = true
        ..id = 'admin-1'
        ..role = 'customer';
      final session = CloudAccountSession(service: fixture)..start();
      addTearDown(() async {
        session.dispose();
        await fixture.changes.close();
      });
      await session.refresh();

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminStudioTheme.themeData(),
          home: Scaffold(
            body: CloudSessionBoundary(
              session: session,
              operator: true,
              builder: (_, lease) => AdminPricingGeofencePanel(
                session: session,
                lease: lease,
              ),
            ),
          ),
        ),
      );
      await pumpShort(tester);

      expect(
        find.byKey(const ValueKey('admin-pricing-geofence-panel')),
        findsOneWidget,
      );

      // Toggle peak surge ON
      await tester.tap(find.byKey(const ValueKey('admin-surge-peak-switch')));
      await pumpShort(tester);
      expect(
        fixture.calls.any((c) => c['path'] == 'admin-pricing/toggle_surge'),
        isTrue,
      );

      // Scroll ListView down to Geofence Studio, load Q1 preset polygon and save Geofence
      await tester.drag(
        find.byKey(const ValueKey('admin-pricing-geofence-panel')),
        const Offset(0, -560),
      );
      await pumpShort(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('admin-geofence-preset-q1')),
      );
      await pumpShort(tester);
      await tester.tap(find.byKey(const ValueKey('admin-geofence-preset-q1')));
      await pumpShort(tester);

      await tester.drag(
        find.byKey(const ValueKey('admin-pricing-geofence-panel')),
        const Offset(0, -260),
      );
      await pumpShort(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('admin-geofence-save')),
      );
      await pumpShort(tester);
      await tester.tap(find.byKey(const ValueKey('admin-geofence-save')));
      await pumpShort(tester);

      expect(fixture.geofences.length, 1);
      expect(find.text('Trung tâm Quận 1'), findsWidgets);
    },
  );
}
