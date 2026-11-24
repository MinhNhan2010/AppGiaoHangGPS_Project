import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/integrations/cloud_orders_service.dart';
import 'package:gps_delivery_app/core/theme/app_theme.dart';
import 'package:gps_delivery_app/presentation/screens/marketplace_view.dart';
import 'package:gps_delivery_app/presentation/widgets/cloud_session_boundary.dart';
import 'package:gps_delivery_app/presentation/widgets/driver_cloud_wallet_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WalletShowcaseFixture extends CloudOrdersService {
  bool authenticated = true;
  bool operator = false;
  String id = 'driver-1';
  String role = 'driver';
  final changes = StreamController<AuthState>.broadcast();
  final calls = <Map<String, dynamic>>[];

  int walletBalance = 320000;
  int lockedBalance = 0;
  int totalEarned = 480000;
  int totalCommission = 120000;
  String bankBin = '970422';
  String bankName = 'MB Bank';
  String bankAccountNo = '0941112233';
  String bankAccountName = 'NGUYEN VAN TAI';

  final List<Map<String, dynamic>> walletRequests = [];
  final List<Map<String, dynamic>> walletLedger = [
    {
      'id': 'led-1',
      'delta': 28000,
      'balance_after': 320000,
      'kind': 'trip_earning_80',
      'note': 'Cộng 80% cước chuyến GHST-8899',
      'created_at': '2026-11-09T09:00:00Z',
    },
  ];

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
          'full_name': operator ? 'Điều hành viên' : 'Tài xế Nguyễn Tài',
          'phone': '0941112233',
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
          'coin_balance': 5000,
        },
      };
    }
    if (path.startsWith('preferences/')) {
      return {'ui_preferences': const <String, dynamic>{}};
    }
    if (path == 'marketplace/catalog' || path == 'marketplace/browse') {
      final filterShopId = body?['shop_id'] as String?;
      final shops = [
        {
          'id': 'shop-tea',
          'name': 'The Gong & Highlands Tea Bar',
          'address': '68 Nguyễn Huệ, Quận 1, TP.HCM',
          'banner_url': '',
          'category_group': 'Trà Sữa & Cà Phê',
          'is_showcase': true,
          'product_count': 5,
          'rating_avg': 4.9,
        },
        {
          'id': 'shop-pho',
          'name': 'Bếp Phở Thìn & Cơm Tấm Sài Gòn',
          'address': '118 Pasteur, Quận 1, TP.HCM',
          'banner_url': '',
          'category_group': 'Cơm & Món Nước',
          'is_showcase': true,
          'product_count': 4,
          'rating_avg': 4.9,
        },
      ];
      final allProducts = [
        {
          'id': 'prod-tea-1',
          'shop_id': 'shop-tea',
          'shop_name': 'The Gong & Highlands Tea Bar',
          'sku': 'TS-TRAN-CHAU-01',
          'name': 'Trà Sữa Trân Châu Đường Đen Kem Cheese',
          'category': 'Trà Sữa & Cà Phê',
          'price': 49000,
          'stock': 120,
          'available': true,
          'preparation_minutes': 8,
          'variants_count': 2,
          'image_url': '',
          'option_groups': const [],
          'flash_sale': {'id': 'fs-1', 'sale_price': 39000},
        },
        {
          'id': 'prod-pho-1',
          'shop_id': 'shop-pho',
          'shop_name': 'Bếp Phở Thìn & Cơm Tấm Sài Gòn',
          'sku': 'PHO-TAI-LAN-01',
          'name': 'Phở Bò Tái Lăn Hà Nội Đặc Biệt',
          'category': 'Cơm & Món Nước',
          'price': 68000,
          'stock': 80,
          'available': true,
          'preparation_minutes': 10,
          'variants_count': 2,
          'image_url': '',
          'option_groups': const [],
        },
      ];
      if (filterShopId != null) {
        final target = shops.firstWhere((s) => s['id'] == filterShopId);
        return {
          'shop': {
            'id': target['id'],
            'name': target['name'],
            'description': 'Trà sữa ủ lạnh chuẩn vị.',
            'address': target['address'],
            'paused': false,
            'open': true,
            'opening_schedule': const [],
          },
          'shop_meta': {
            'banner_url': '',
            'service_radius_km': 18,
            'following': false,
            'is_showcase': true,
            'category_group': target['category_group'],
          },
          'categories': const ['Trà Sữa & Cà Phê'],
          'products': allProducts
              .where((p) => p['shop_id'] == filterShopId)
              .toList(),
        };
      }
      return {
        'shops': shops,
        'categories': const ['Trà Sữa & Cà Phê', 'Cơm & Món Nước'],
        'products': allProducts,
      };
    }
    if (path == 'driver-wallet/summary') {
      return {
        'wallet': {
          'user_id': id,
          'balance': walletBalance,
          'locked_balance': lockedBalance,
          'total_earned': totalEarned,
          'total_commission': totalCommission,
          'escrow_target': 200000,
          'bank_bin': bankBin,
          'bank_name': bankName,
          'bank_account_no': bankAccountNo,
          'bank_account_name': bankAccountName,
          'cod_holding': 95000,
          'trips_settled_count': 12,
        },
        'ledger': walletLedger,
        'requests': walletRequests,
      };
    }
    if (path == 'driver-wallet/request_topup') {
      final amount = (body?['amount'] as num?)?.toInt() ?? 200000;
      final req = {
        'id': 'req-topup-1',
        'kind': 'topup',
        'amount': amount,
        'state': 'pending',
        'transfer_code': 'GHST NAP ABCD1234',
        'driver_note': body?['driver_note'] ?? '',
        'created_at': '2026-11-09T10:00:00Z',
      };
      walletRequests.insert(0, req);
      return {'request': req, 'wallet': {'balance': walletBalance}};
    }
    if (path == 'driver-wallet/request_withdraw') {
      final amount = (body?['amount'] as num?)?.toInt() ?? 100000;
      walletBalance -= amount;
      lockedBalance += amount;
      final req = {
        'id': 'req-wd-1',
        'kind': 'withdraw',
        'amount': amount,
        'state': 'pending',
        'transfer_code': 'GHST RUT EFGH5678',
        'bank_bin': body?['bank_bin'] ?? bankBin,
        'bank_name': body?['bank_name'] ?? bankName,
        'bank_account_no': body?['bank_account_no'] ?? bankAccountNo,
        'bank_account_name': body?['bank_account_name'] ?? bankAccountName,
        'driver_note': body?['driver_note'] ?? '',
        'created_at': '2026-11-09T10:05:00Z',
      };
      walletRequests.insert(0, req);
      return {'request': req, 'wallet': {'balance': walletBalance}};
    }
    if (path == 'driver-wallet/admin_list') {
      return {
        'kpis': {
          'pending_topups': walletRequests
              .where((r) => r['state'] == 'pending' && r['kind'] == 'topup')
              .length,
          'pending_withdrawals': walletRequests
              .where((r) => r['state'] == 'pending' && r['kind'] == 'withdraw')
              .length,
          'total_driver_balances': walletBalance,
          'total_platform_commission': totalCommission,
        },
        'requests': [
          for (final r in walletRequests)
            if (body?['state'] == 'all' || r['state'] == body?['state'])
              {
                ...r,
                'driver_name': 'Tài xế Nguyễn Tài',
                'driver_phone': '0941112233',
                'driver_balance': walletBalance,
                'driver_locked_balance': lockedBalance,
              },
        ],
      };
    }
    if (path == 'driver-wallet/admin_resolve') {
      final targetId = body?['request_id'];
      for (final r in walletRequests) {
        if (r['id'] == targetId) {
          r['state'] = body?['decision'] == 'approve' ? 'approved' : 'rejected';
          r['admin_note'] = body?['admin_note'] ?? '';
        }
      }
      return {'ok': true};
    }
    return const {};
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpShort(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets(
    'Marketplace catalog renders featured virtual restaurants & beverage storefront strip with prep time and Flash Sale',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = WalletShowcaseFixture()
        ..id = 'buyer-1'
        ..role = 'customer';
      final session = CloudAccountSession(service: service)..start();
      addTearDown(() async {
        session.dispose();
        await service.changes.close();
      });
      await session.refresh();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: CloudSessionBoundary(
              session: session,
              builder: (_, lease) => MarketplaceView(
                session: session,
                view: MarketView.catalog,
                lease: lease,
              ),
            ),
          ),
        ),
      );
      await pumpShort(tester);

      expect(
        find.text('Quán ngon & Cửa hàng nổi bật (2)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Trà Sữa & Cà Phê · ★ 4.9'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Flash Sale'),
        findsOneWidget,
      );
      expect(
        find.textContaining('~8p'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('featured-shop-shop-tea')));
      await pumpShort(tester);

      expect(find.text('Trà sữa ủ lạnh chuẩn vị.'), findsOneWidget);
      expect(find.text('Phạm vi giao hàng: 18 km'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Driver 80/20 wallet renders settlement stats, opens VietQR top-up and locks balance on bank withdrawal',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = WalletShowcaseFixture();
      final session = CloudAccountSession(service: service)..start();
      addTearDown(() async {
        session.dispose();
        await service.changes.close();
      });
      await session.refresh();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: CloudSessionBoundary(
              session: session,
              roles: const {'driver'},
              builder: (_, lease) => ListView(
                children: [
                  DriverCloudWalletPanel(session: session, lease: lease),
                ],
              ),
            ),
          ),
        ),
      );
      await pumpShort(tester);

      expect(find.text('Ví Tài xế & Đối soát'), findsOneWidget);
      expect(find.text('12 chuyến'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('btn-driver-wallet-topup')));
      await pumpShort(tester);

      await tester.enterText(
        find.byKey(const ValueKey('driver-wallet-topup-amount')),
        '250000',
      );
      await tester.tap(
        find.byKey(const ValueKey('driver-wallet-topup-submit')),
      );
      await pumpShort(tester);

      expect(find.text('Quét mã VietQR nạp ký quỹ'), findsOneWidget);
      expect(find.textContaining('GHST NAP ABCD1234'), findsWidgets);
      await tester.tap(find.text('Đã lưu mã / Đóng'));
      await pumpShort(tester);

      await tester.tap(
        find.byKey(const ValueKey('btn-driver-wallet-withdraw')),
      );
      await pumpShort(tester);
      await tester.enterText(
        find.byKey(const ValueKey('driver-wallet-withdraw-amount')),
        '120000',
      );
      await tester.tap(
        find.byKey(const ValueKey('driver-wallet-withdraw-submit')),
      );
      await pumpShort(tester);

      expect(service.walletBalance, 200000);
      expect(service.lockedBalance, 120000);
      expect(find.textContaining('Đang khóa chờ rút'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Operator admin driver wallet reconciliation lists pending requests and approves with audit note',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = WalletShowcaseFixture()
        ..id = 'admin-1'
        ..role = 'customer'
        ..operator = true;
      service.walletRequests.add({
        'id': 'req-pending-topup',
        'kind': 'topup',
        'amount': 300000,
        'state': 'pending',
        'transfer_code': 'GHST NAP 99887766',
        'driver_note': 'Nạp ký quỹ đầu ca',
        'created_at': '2026-11-09T11:00:00Z',
      });

      final session = CloudAccountSession(service: service)..start();
      addTearDown(() async {
        session.dispose();
        await service.changes.close();
      });
      await session.refresh();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: CloudSessionBoundary(
              session: session,
              operator: true,
              builder: (_, lease) => AdminDriverWalletRequestsSection(
                session: session,
                lease: lease,
              ),
            ),
          ),
        ),
      );
      await pumpShort(tester);

      expect(find.textContaining('GHST NAP 99887766'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('admin-wallet-approve-req-pending-topup')),
      );
      await pumpShort(tester);

      await tester.tap(find.text('Phê duyệt'));
      await pumpShort(tester);

      expect(
        service.calls.any(
          (c) =>
              c['path'] == 'driver-wallet/admin_resolve' &&
              (c['body'] as Map?)?['request_id'] == 'req-pending-topup' &&
              (c['body'] as Map?)?['decision'] == 'approve',
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
