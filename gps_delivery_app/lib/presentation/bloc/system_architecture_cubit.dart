import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/gps/gps_integrity_validator.dart';
import '../../core/gps/kalman_gps_filter.dart';
import '../../domain/entities/geo_point.dart';
import '../../domain/entities/pricing_estimate.dart';
import '../../domain/enums/service_type.dart';
import '../../domain/enums/user_role.dart';

class SystemArchitectureState extends Equatable {
  final SubsystemRole selectedRole;
  final DeliveryServiceType selectedService;
  final int distanceMeters;
  final int durationSeconds;
  final bool isPeakHour;
  final double voucherDiscount;
  final PricingEstimate estimate;
  final GeoPoint lastSmoothedGps;
  final BatteryTrackingPolicy batteryPolicy;
  final int batteryPercent;

  const SystemArchitectureState({
    required this.selectedRole,
    required this.selectedService,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.isPeakHour,
    required this.voucherDiscount,
    required this.estimate,
    required this.lastSmoothedGps,
    required this.batteryPolicy,
    required this.batteryPercent,
  });

  factory SystemArchitectureState.initial() {
    const defaultService = DeliveryServiceType.express30m;
    const defaultDistMeters = 14500; // 14.5 km from Hình 8.5 (UC05)
    const defaultDurationSec = 2700; // 45 minutes from Hình 8.5 (UC05)
    const defaultVoucher = 20000.0; // PROMO20K (-20.000 đ) from Hình 8.5

    return SystemArchitectureState(
      selectedRole: SubsystemRole.customer,
      selectedService: defaultService,
      distanceMeters: defaultDistMeters,
      durationSeconds: defaultDurationSec,
      isPeakHour: true,
      voucherDiscount: defaultVoucher,
      estimate: PricingEstimate.calculate(
        serviceType: defaultService,
        distanceMeters: defaultDistMeters,
        durationSeconds: defaultDurationSec,
        isPeakHour: true,
        voucherDiscount: defaultVoucher,
      ),
      lastSmoothedGps: const GeoPoint(
        latitude: 10.7769,
        longitude: 106.6953,
      ),
      batteryPolicy: GpsIntegrityValidator.resolvePolicy(
        batteryLevelPercent: 85,
        isCharging: false,
      ),
      batteryPercent: 85,
    );
  }

  @override
  List<Object?> get props => [
        selectedRole,
        selectedService,
        distanceMeters,
        durationSeconds,
        isPeakHour,
        voucherDiscount,
        estimate,
        lastSmoothedGps,
        batteryPercent,
      ];
}

class SystemArchitectureCubit extends Cubit<SystemArchitectureState> {
  final KalmanGpsFilter _kalmanFilter = KalmanGpsFilter();

  SystemArchitectureCubit() : super(SystemArchitectureState.initial());

  void selectRole(SubsystemRole role) {
    emit(
      SystemArchitectureState(
        selectedRole: role,
        selectedService: state.selectedService,
        distanceMeters: state.distanceMeters,
        durationSeconds: state.durationSeconds,
        isPeakHour: state.isPeakHour,
        voucherDiscount: state.voucherDiscount,
        estimate: state.estimate,
        lastSmoothedGps: state.lastSmoothedGps,
        batteryPolicy: state.batteryPolicy,
        batteryPercent: state.batteryPercent,
      ),
    );
  }

  void updateServiceAndPricing({
    DeliveryServiceType? serviceType,
    bool? isPeakHour,
  }) {
    final nextService = serviceType ?? state.selectedService;
    final nextPeak = isPeakHour ?? state.isPeakHour;
    final nextEstimate = PricingEstimate.calculate(
      serviceType: nextService,
      distanceMeters: state.distanceMeters,
      durationSeconds: state.durationSeconds,
      isPeakHour: nextPeak,
      voucherDiscount: state.voucherDiscount,
    );

    emit(
      SystemArchitectureState(
        selectedRole: state.selectedRole,
        selectedService: nextService,
        distanceMeters: state.distanceMeters,
        durationSeconds: state.durationSeconds,
        isPeakHour: nextPeak,
        voucherDiscount: state.voucherDiscount,
        estimate: nextEstimate,
        lastSmoothedGps: state.lastSmoothedGps,
        batteryPolicy: state.batteryPolicy,
        batteryPercent: state.batteryPercent,
      ),
    );
  }

  void updateBatteryLevel(int batteryPercent) {
    final nextPolicy = GpsIntegrityValidator.resolvePolicy(
      batteryLevelPercent: batteryPercent,
      isCharging: false,
    );
    final rawPoint = GeoPoint(
      latitude: state.lastSmoothedGps.latitude + 0.0002,
      longitude: state.lastSmoothedGps.longitude + 0.0002,
    );
    final smoothed = _kalmanFilter.filter(
      rawPoint: rawPoint,
      accuracyMeters: 4.5,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );

    emit(
      SystemArchitectureState(
        selectedRole: state.selectedRole,
        selectedService: state.selectedService,
        distanceMeters: state.distanceMeters,
        durationSeconds: state.durationSeconds,
        isPeakHour: state.isPeakHour,
        voucherDiscount: state.voucherDiscount,
        estimate: state.estimate,
        lastSmoothedGps: smoothed,
        batteryPolicy: nextPolicy,
        batteryPercent: batteryPercent,
      ),
    );
  }
}
