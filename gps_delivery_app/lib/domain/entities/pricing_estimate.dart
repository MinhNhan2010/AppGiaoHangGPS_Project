import 'dart:math' as math;
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
    double? configuredStandardPeakSurcharge,
  }) {
    final safeDistMeters = math.max(0, distanceMeters);
    final safeDurationSec = math.max(0, durationSeconds);
    final safeBaseScale = baseFareScale.isFinite && baseFareScale > 0
        ? baseFareScale
        : 1.0;
    final safeKmScale = pricePerKmScale.isFinite && pricePerKmScale > 0
        ? pricePerKmScale
        : 1.0;
    final safeGeofence = geofenceSurcharge.isFinite
        ? math.max(0.0, geofenceSurcharge)
        : 0.0;
    final safeVoucher = voucherDiscount.isFinite
        ? math.max(0.0, voucherDiscount)
        : 0.0;

    final distanceKm = safeDistMeters / 1000.0;
    final baseFare =
        (serviceType.defaultBaseFare * safeBaseScale).roundToDouble();
    final distanceFare =
        (distanceKm * serviceType.defaultPricePerKm * safeKmScale)
            .roundToDouble();
    final resolvedStandardPeak =
        (configuredStandardPeakSurcharge != null &&
                configuredStandardPeakSurcharge.isFinite)
            ? math.max(0.0, configuredStandardPeakSurcharge)
            : serviceType.defaultPeakSurcharge;
    final peakFee = isPeakHour
        ? (serviceType == DeliveryServiceType.standard
              ? resolvedStandardPeak
              : serviceType.defaultPeakSurcharge)
        : 0.0;
    final surchargeFee = peakFee + safeGeofence;
    final subtotal = baseFare + distanceFare + surchargeFee;
    final effectiveDiscount = safeVoucher.clamp(0.0, subtotal);
    final totalAmount = math.max(0.0, subtotal - effectiveDiscount);

    return PricingEstimate(
      serviceType: serviceType,
      distanceKm: distanceKm,
      durationSeconds: safeDurationSec,
      baseFare: baseFare,
      distanceFare: distanceFare,
      surchargeFee: surchargeFee,
      discountAmount: effectiveDiscount,
      totalAmount: totalAmount,
    );
  }

  @override
  List<Object?> get props => [
        serviceType,
        distanceKm,
        durationSeconds,
        baseFare,
        distanceFare,
        surchargeFee,
        discountAmount,
        totalAmount,
      ];
}
