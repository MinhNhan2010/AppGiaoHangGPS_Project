import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/gps/gps_integrity_validator.dart';
import 'package:gps_delivery_app/core/utils/geo_math.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/domain/entities/pricing_estimate.dart';
import 'package:gps_delivery_app/domain/enums/order_status.dart';
import 'package:gps_delivery_app/domain/enums/service_type.dart';
import 'package:gps_delivery_app/main.dart';

void main() {
  testWidgets('GpsDeliveryApp renders architecture dashboard and UC05 estimate', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const GpsDeliveryApp());

    expect(
      find.text('Hệ Thống Giao Hàng Định Vị GPS Đa Nền Tảng'),
      findsOneWidget,
    );
    expect(find.text('Phân hệ Khách hàng'), findsWidgets);
  });

  test('UC05 Express 14.5km + Peak + PROMO20K equals 138,250 VND (Hình 8.5)', () {
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
  });

  test('OrderStatus FSM enforces valid and invalid transitions (Table 22)', () {
    expect(OrderStatus.draft.canTransitionTo(OrderStatus.searching), isTrue);
    expect(OrderStatus.draft.canTransitionTo(OrderStatus.delivered), isFalse);
    expect(OrderStatus.inTransit.canTransitionTo(OrderStatus.delivered), isTrue);
    expect(OrderStatus.delivered.canTransitionTo(OrderStatus.cancelled), isFalse);
  });

  test('Ray-Casting Point-in-Polygon & Adaptive Battery Policy (Table 36)', () {
    const polygon = [
      GeoPoint(latitude: 10.76, longitude: 106.68),
      GeoPoint(latitude: 10.76, longitude: 106.71),
      GeoPoint(latitude: 10.79, longitude: 106.71),
      GeoPoint(latitude: 10.79, longitude: 106.68),
    ];
    const insidePoint = GeoPoint(latitude: 10.7769, longitude: 106.6953);
    expect(GeoMath.isPointInPolygon(insidePoint, polygon), isTrue);

    final lowBatteryPolicy = GpsIntegrityValidator.resolvePolicy(
      batteryLevelPercent: 15,
      isCharging: false,
    );
    expect(lowBatteryPolicy.enable3dBuildings, isFalse);
    expect(lowBatteryPolicy.cameraPitch, 0.0);
  });
}
