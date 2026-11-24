import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/config/feature_flags.dart';
import 'package:gps_delivery_app/core/integrations/cloud_account_session.dart';
import 'package:gps_delivery_app/core/theme/app_theme.dart';
import 'package:gps_delivery_app/presentation/customer/ghst_home_screen.dart';
import 'package:gps_delivery_app/presentation/customer/ghst_user_shell.dart';
import 'package:gps_delivery_app/presentation/screens/cloud_orders_screen.dart';
import 'package:gps_delivery_app/presentation/screens/marketplace_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'unified_user_interface_test.dart' show UnifiedUserFixture;

/// The default build focuses on GPS delivery: commerce surfaces
/// (food & shopping, merchant storefronts, cart, promo games) stay hidden.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('commerce modules are disabled by default', () {
    expect(GhstFeatures.commerceEnabled, isFalse);
  });

  Future<(UnifiedUserFixture, CloudAccountSession)> setup(
    WidgetTester tester,
    double width,
    Set<String> roles,
  ) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    final api = UnifiedUserFixture()..roles = roles;
    final session = CloudAccountSession(service: api);
    addTearDown(() async {
      session.dispose();
      await api.changes.close();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await session.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: MarketplaceScreen(session: session),
      ),
    );
    await tester.pumpAndSettle();
    return (api, session);
  }

  GhstUserShell shell(WidgetTester tester) =>
      tester.widget<GhstUserShell>(find.byType(GhstUserShell));

  void expectNoCommerce() {
    for (final text in [
      'Ăn uống & Mua sắm',
      'Vòng Xoay May Mắn',
      'Hộp Mù Bí Ẩn',
      'Cửa hàng của tôi',
      'Đơn của cửa hàng',
    ]) {
      expect(find.text(text), findsNothing, reason: text);
    }
    expect(find.byTooltip('Giỏ hàng'), findsNothing);
    expect(find.byKey(const ValueKey('ghst-nav-food')), findsNothing);
    expect(find.byKey(const ValueKey('ghst-role-merchant')), findsNothing);
  }

  for (final width in [360.0, 1440.0]) {
    testWidgets('customer home shows delivery-only services at $width', (
      tester,
    ) async {
      await setup(tester, width, {});
      expect(find.byType(GhstHomeScreen), findsOneWidget);
      expect(find.text('Bạn muốn giao hàng đến đâu?'), findsOneWidget);
      expect(find.text('Dịch vụ Giao hàng định vị GPS'), findsOneWidget);
      expect(find.text('Theo dõi đơn hàng'), findsOneWidget);
      for (final service in ['Giao nhanh', 'Ghép đơn 2H', 'Xe tải nhẹ']) {
        expect(find.text(service), findsOneWidget, reason: service);
      }
      if (width >= 860) {
        expect(find.text('GIAO HÀNG ĐỊNH VỊ GPS'), findsOneWidget);
      } else {
        expect(find.byKey(const ValueKey('ghst-nav-tracking')), findsOneWidget);
      }
      expectNoCommerce();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'merchant role is hidden and falls back to customer at $width',
      (tester) async {
        await setup(tester, width, {'merchant'});
        expect(shell(tester).roleMode, GhstRoleMode.customer);
        expect(shell(tester).availableModes, [GhstRoleMode.customer]);
        expect(find.byType(GhstHomeScreen), findsOneWidget);
        expectNoCommerce();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('driver keeps dispatch workspace without merchant at $width', (
      tester,
    ) async {
      await setup(tester, width, {'merchant', 'driver'});
      expect(shell(tester).roleMode, GhstRoleMode.driver);
      expect(shell(tester).section, GhstUserSection.driverQueue);
      expect(shell(tester).availableModes, [
        GhstRoleMode.driver,
        GhstRoleMode.customer,
      ]);
      expect(
        tester
            .widget<CloudOrdersScreen>(find.byType(CloudOrdersScreen))
            .initialQueue,
        isTrue,
      );
      expectNoCommerce();

      await tester.tap(find.byKey(const ValueKey('ghst-role-customer')));
      await tester.pumpAndSettle();
      expect(find.byType(GhstHomeScreen), findsOneWidget);
      expectNoCommerce();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('orders tab lists shipping orders only at $width', (
      tester,
    ) async {
      await setup(tester, width, {});
      if (width < 860) {
        await tester.tap(find.byKey(const ValueKey('ghst-nav-orders')));
      } else {
        await tester.tap(
          find
              .descendant(
                of: find.byType(GhstUserShell),
                matching: find.text('Đơn hàng'),
              )
              .first,
        );
      }
      await tester.pumpAndSettle();
      expect(shell(tester).section, GhstUserSection.orders);
      expect(find.byType(CloudOrdersScreen), findsOneWidget);
      expect(find.text('Đơn mua'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
