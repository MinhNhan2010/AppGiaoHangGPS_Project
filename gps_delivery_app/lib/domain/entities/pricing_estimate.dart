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
  final double insuranceFee;
  final double multiStopFee;
  final double roundTripFee;
  final double greenContributionFee;
  final double estimatedCo2SavedGrams;

  static const double maxInsuredDeclaredValueVnd = 30000000.0;
  static const double extraStopFeePerStopVnd = 5000.0;
  static const double greenFundContributionUnitVnd = 1000.0;

  const PricingEstimate({
    required this.serviceType,
    required this.distanceKm,
    required this.durationSeconds,
    required this.baseFare,
    required this.distanceFare,
    required this.surchargeFee,
    required this.discountAmount,
    required this.totalAmount,
    this.insuranceFee = 0.0,
    this.multiStopFee = 0.0,
    this.roundTripFee = 0.0,
    this.greenContributionFee = 0.0,
    this.estimatedCo2SavedGrams = 0.0,
  });

  /// Tính phí bảo hiểm khai giá hàng hóa (0.5% giá trị khai báo, tối thiểu 2.000đ, tối đa 150.000đ, đền bù tối đa 30.000.000đ).
  static double calculateInsuranceFee(double declaredValueVnd) {
    if (!declaredValueVnd.isFinite || declaredValueVnd <= 0) return 0.0;
    final clamped = declaredValueVnd.clamp(0.0, maxInsuredDeclaredValueVnd);
    return (clamped * 0.005).clamp(2000.0, 150000.0).roundToDouble();
  }

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
    double declaredValueVnd = 0.0,
    int extraStopCount = 0,
    bool isRoundTrip = false,
    bool greenFundContribution = false,
    bool preferEcoEv = false,
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

    final insuranceFee = calculateInsuranceFee(declaredValueVnd);
    final multiStopFee = math.max(0, extraStopCount) * extraStopFeePerStopVnd;
    final roundTripFee =
        isRoundTrip ? ((baseFare + distanceFare) * 0.60).roundToDouble() : 0.0;
    final greenContributionFee =
        greenFundContribution ? greenFundContributionUnitVnd : 0.0;
    final estimatedCo2SavedGrams = preferEcoEv ? (distanceKm * 48.0) : 0.0;

    final surchargeFee = peakFee +
        safeGeofence +
        multiStopFee +
        roundTripFee +
        insuranceFee +
        greenContributionFee;
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
      insuranceFee: insuranceFee,
      multiStopFee: multiStopFee,
      roundTripFee: roundTripFee,
      greenContributionFee: greenContributionFee,
      estimatedCo2SavedGrams: estimatedCo2SavedGrams,
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
        insuranceFee,
        multiStopFee,
        roundTripFee,
        greenContributionFee,
        estimatedCo2SavedGrams,
      ];
}
