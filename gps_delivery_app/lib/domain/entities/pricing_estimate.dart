import 'package:equatable/equatable.dart';
import '../enums/service_type.dart';

class PricingEstimate extends Equatable {
  final DeliveryServiceType serviceType;
  final double distanceKm;
  final int durationSeconds;
  final double baseFare;
  final double distanceFare;
  final double surchargeFee;
  final double discountAmount;
  final double totalAmount;

  const PricingEstimate({
    required this.serviceType,
    required this.distanceKm,
    required this.durationSeconds,
    required this.baseFare,
    required this.distanceFare,
    required this.surchargeFee,
    required this.discountAmount,
    required this.totalAmount,
  });

  /// Tính toán chính xác cước phí giao hàng theo bảng giá dịch vụ và phụ phí.
  factory PricingEstimate.calculate({
    required DeliveryServiceType serviceType,
    required int distanceMeters,
    required int durationSeconds,
    bool isPeakHour = false,
    double geofenceSurcharge = 0.0,
    double voucherDiscount = 0.0,
    double baseFareScale = 1.0,
    double pricePerKmScale = 1.0,
  }) {
    final distanceKm = distanceMeters / 1000.0;
    final baseFare =
        (serviceType.defaultBaseFare * baseFareScale).roundToDouble();
    final distanceFare =
        (distanceKm * serviceType.defaultPricePerKm * pricePerKmScale)
            .roundToDouble();
    final peakFee = isPeakHour ? serviceType.defaultPeakSurcharge : 0.0;
    final surchargeFee = peakFee + geofenceSurcharge;
    final rawTotal = baseFare + distanceFare + surchargeFee - voucherDiscount;
    final totalAmount = rawTotal < 0 ? 0.0 : rawTotal;

    return PricingEstimate(
      serviceType: serviceType,
      distanceKm: distanceKm,
      durationSeconds: durationSeconds,
      baseFare: baseFare,
      distanceFare: distanceFare,
      surchargeFee: surchargeFee,
      discountAmount: voucherDiscount,
      totalAmount: totalAmount,
    );
  }

  @override
  List<Object?> get props => [
        serviceType,
        distanceKm,
        baseFare,
        distanceFare,
        surchargeFee,
        discountAmount,
        totalAmount,
      ];
}
