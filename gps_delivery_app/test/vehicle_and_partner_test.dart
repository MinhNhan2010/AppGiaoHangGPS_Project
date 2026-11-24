import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/integrations/cloud_session_lease.dart';
import 'package:gps_delivery_app/core/theme/app_theme.dart';
import 'package:gps_delivery_app/domain/entities/vehicle_class.dart';
import 'package:gps_delivery_app/presentation/screens/driver_partner_application_screen.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_order_form.dart';
import 'package:gps_delivery_app/presentation/widgets/driver_dispatch_cockpit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_orders_test.dart' show CloudFixture;

class PartnerFixture extends CloudOrdersService {
  final calls = <Map<String, dynamic>>[];
  Map<String, dynamic>? application;
  String? approvedVehicle;
  int uploads = 0;

  @override
  bool get signedIn => true;
  @override
  String get userId => 'driver-1';
  @override
  String get email => 'driver@example.com';
  @override
  String get project => 'partner-fixture';

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add({'path': path, 'body': body});
    if (path == 'profile') {
      return {
        'schema_version': 3,
        'operator': false,
        'account': {
          'user_id': 'driver-1',
          'role': 'customer',
          'full_name': 'Tài xế thử nghiệm',
          'phone': '0901234567',
          'blocked': false,
          'approved_roles': approvedVehicle == null ? [] : ['driver'],
          'memberships': approvedVehicle == null
              ? []
              : [
                  {'role': 'driver', 'state': 'active', 'version': 2},
                ],
        },
      };
    }
    if (path == 'driver-application/get') {
      return {'application': application};
    }
    if (path == 'driver-application/upload_document') {
      uploads++;
      return {
        'kind': body!['kind'],
        'path': 'driver-applications/driver-1/${body['kind']}-$uploads.png',
      };
    }
    if (path == 'driver-application/submit') {
      application = {...body!, 'state': 'pending', 'reason': '', 'version': 1};
      return {'application': application};
    }
    if (path.startsWith('driver-dispatch/')) {
      return {
        'presence': {
          'is_online': false,
          'vehicle_type': approvedVehicle ?? 'motorbike',
          'allow_batching': true,
          'approved_vehicle_type': approvedVehicle,
        },
        'active_trips_count': 0,
      };
    }
    return {};
  }
}

final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  ...List<int>.filled(2048, 0),
]);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('VehicleClass', () {
    test('legacy clients resolve to the same vehicle as the backend', () {
      expect(VehicleClass.resolve(serviceType: 'standard').id, 'motorbike');
      expect(
        VehicleClass.resolve(serviceType: 'express', preferEv: true).id,
        'ev_scooter',
      );
      expect(VehicleClass.resolve(serviceType: 'truck').id, 'van');
      expect(
        VehicleClass.resolve(vehicleType: 'truck', serviceType: 'x').id,
        'truck',
      );
    });

    test('service tiers, capacity rule, suggestion and fee', () {
      expect(VehicleClass.motorbike.allowsService('express'), isTrue);
      expect(VehicleClass.motorbike.allowsService('truck'), isFalse);
      expect(VehicleClass.tricycle.allowsService('truck'), isTrue);
      expect(VehicleClass.van.allowsService('standard'), isFalse);

      expect(VehicleClass.evScooter.canServe(VehicleClass.motorbike), isTrue);
      expect(VehicleClass.motorbike.canServe(VehicleClass.evScooter), isFalse);
      expect(VehicleClass.truck.canServe(VehicleClass.tricycle), isTrue);
      expect(VehicleClass.van.canServe(VehicleClass.truck), isFalse);

      expect(VehicleClass.suggestFor(12).id, 'motorbike');
      expect(VehicleClass.suggestFor(120).id, 'tricycle');
      expect(VehicleClass.suggestFor(450).id, 'van');
      expect(VehicleClass.suggestFor(1200).id, 'truck');

      expect(VehicleClass.motorbike.estimateFee(10), 0);
      expect(VehicleClass.van.estimateFee(1.5), 60000);
      expect(VehicleClass.van.estimateFee(5.2), 60000 + 4 * 3000);
      expect(VehicleClass.truck.estimateFee(12), 150000 + 10 * 8000);
    });

    test('licence classes and Vietnamese plates', () {
      expect(VehicleClass.motorbike.acceptsLicense('a1'), isTrue);
      expect(VehicleClass.truck.acceptsLicense('B'), isFalse);
      expect(VehicleClass.van.acceptsLicense('C1'), isTrue);
      for (final ok in ['59X1-123.45', '51c 123.45', '30A-1234', '29LD12345']) {
        expect(isValidLicensePlate(ok), isTrue, reason: ok);
      }
      for (final bad in ['ABC', '5X1-12345', '59X1-12', '']) {
        expect(isValidLicensePlate(bad), isFalse, reason: bad);
      }
    });
  });

  testWidgets('order form suggests a bigger vehicle and sends vehicle_type', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final api = CloudFixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: CloudOrderForm(
          service: api,
          merchants: const [],
          initialDetails: const {
            'pickup_address': 'Chợ Bến Thành, Quận 1',
            'dropoff_address': 'Landmark 81, Bình Thạnh',
            'pickup_lat': 10.7725,
            'pickup_lng': 106.698,
            'dropoff_lat': 10.795,
            'dropoff_lng': 106.7218,
            'recipient_name': 'Người nhận',
            'recipient_phone': '0912345678',
            'package_description': 'Tủ lạnh mini',
            'weight_kg': 120,
            'service_type': 'standard',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chọn loại xe theo yêu cầu'), findsOneWidget);
    for (final v in VehicleClass.all) {
      expect(find.byKey(ValueKey('vehicle-${v.id}')), findsOneWidget);
    }
    expect(find.textContaining('vượt tải Xe máy'), findsOneWidget);
    expect(find.byKey(const ValueKey('service-tier-truck')), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('vehicle-suggest')));
    await tester.tap(find.byKey(const ValueKey('vehicle-suggest')));
    await tester.pumpAndSettle();
    expect(find.textContaining('vượt tải'), findsNothing);
    expect(find.byKey(const ValueKey('service-tier-truck')), findsOneWidget);
    expect(find.byKey(const ValueKey('service-tier-standard')), findsNothing);

    await tester.ensureVisible(find.text('Lấy báo giá'));
    await tester.tap(find.text('Lấy báo giá'));
    await tester.pumpAndSettle();
    final quote =
        api.calls.lastWhere((c) => c['path'] == 'quote')['body']
            as Map<String, dynamic>;
    expect(quote['vehicle_type'], 'tricycle');
    expect(quote['service_type'], 'truck');
    expect(quote['weight_kg'], 120);

    await tester.ensureVisible(find.byKey(const ValueKey('vehicle-motorbike')));
    await tester.tap(find.byKey(const ValueKey('vehicle-motorbike')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('service-tier-truck')), findsNothing);
    expect(find.byKey(const ValueKey('service-tier-standard')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('driver partner application validates and submits full KYC', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    final api = PartnerFixture();
    final session = CloudAccountSession(service: api);
    addTearDown(() {
      session.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await session.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: DriverPartnerApplicationScreen(
            session: session,
            pickImage: (_) async => _png,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Missing everything: form validation blocks the request.
    await tester.ensureVisible(find.byKey(const ValueKey('driver-app-submit')));
    await tester.tap(find.byKey(const ValueKey('driver-app-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Biển số không hợp lệ (VD: 59X1-123.45)'), findsOneWidget);
    expect(
      api.calls.any((c) => c['path'] == 'driver-application/submit'),
      isFalse,
    );

    await tester.tap(find.byKey(const ValueKey('apply-vehicle-van')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('driver-plate')),
      '51c-123.45',
    );
    await tester.enterText(
      find.byKey(const ValueKey('driver-brand')),
      'Suzuki Carry',
    );
    await tester.enterText(find.byKey(const ValueKey('driver-color')), 'Trắng');
    await tester.enterText(
      find.byKey(const ValueKey('driver-license')),
      '012345678901',
    );
    await tester.enterText(
      find.byKey(const ValueKey('driver-area')),
      'TP.HCM - Quận 1',
    );
    await tester.tap(find.byKey(const ValueKey('driver-license-class-van')));
    await tester.pumpAndSettle();
    expect(find.text('Hạng A1'), findsNothing); // filtered by vehicle
    await tester.tap(find.text('Hạng B').last);
    await tester.pumpAndSettle();

    // Documents still missing.
    await tester.tap(find.byKey(const ValueKey('driver-app-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('driver-app-error')), findsOneWidget);

    for (final kind in driverDocumentKinds.keys) {
      final pick = find.byKey(ValueKey('driver-doc-pick-$kind'));
      await tester.ensureVisible(pick);
      await tester.tap(pick);
      await tester.pumpAndSettle();
    }
    expect(api.uploads, 5);
    final uploadBody =
        api.calls.firstWhere(
              (c) => c['path'] == 'driver-application/upload_document',
            )['body']
            as Map;
    expect(uploadBody['content_type'], 'image/png');

    await tester.ensureVisible(find.byKey(const ValueKey('driver-app-submit')));
    await tester.tap(find.byKey(const ValueKey('driver-app-submit')));
    await tester.pumpAndSettle();
    final submit =
        api.calls.lastWhere(
              (c) => c['path'] == 'driver-application/submit',
            )['body']
            as Map;
    expect(submit['vehicle_type'], 'van');
    expect(submit['license_plate'], '51C-123.45');
    expect(submit['license_class'], 'B');
    expect(
      (submit['documents'] as Map).keys.toSet(),
      driverDocumentKinds.keys.toSet(),
    );
    expect(find.byKey(const ValueKey('driver-app-status')), findsOneWidget);
    expect(find.text('Đang chờ duyệt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejected application can be edited and resubmitted', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    final api = PartnerFixture()
      ..application = {
        'vehicle_type': 'motorbike',
        'license_plate': '59X1-123.45',
        'vehicle_brand': 'Honda Wave',
        'vehicle_color': 'Đỏ',
        'license_number': '012345678901',
        'license_class': 'A1',
        'operating_area': 'TP.HCM',
        'documents': {
          for (final k in driverDocumentKinds.keys)
            k: 'driver-applications/driver-1/$k.png',
        },
        'state': 'rejected',
        'reason': 'Ảnh GPLX bị mờ',
        'version': 1,
      };
    final session = CloudAccountSession(service: api);
    addTearDown(() {
      session.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await session.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: DriverPartnerApplicationScreen(
            session: session,
            pickImage: (_) async => _png,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chưa được duyệt'), findsOneWidget);
    expect(find.text('Lý do: Ảnh GPLX bị mờ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('driver-app-edit')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '59X1-123.45'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('driver-app-submit')));
    await tester.tap(find.byKey(const ValueKey('driver-app-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Đang chờ duyệt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('approved vehicle locks the dispatch vehicle chips', (
    tester,
  ) async {
    final api = PartnerFixture()..approvedVehicle = 'van';
    final session = CloudAccountSession(service: api);
    await session.refresh();
    final lease = CloudSessionLease(session: session);
    addTearDown(() {
      lease.dispose();
      session.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: DriverDispatchPresenceBar(lease: lease),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('driver-vehicle-van')), findsOneWidget);
    expect(find.text('Xe van · đã duyệt'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('driver-vehicle-motorbike')),
      findsNothing,
    );
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('driver-vehicle-van')),
    );
    expect(chip.onSelected, isNull);
    expect(tester.takeException(), isNull);
  });
}
