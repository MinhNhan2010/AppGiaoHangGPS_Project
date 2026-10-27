import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/gps/gps_integrity_validator.dart';
import '../../core/gps/kalman_gps_filter.dart';
import '../../data/datasources/local/app_state_store.dart';
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
  final GeoPoint? lastSmoothedGps;
  final BatteryTrackingPolicy batteryPolicy;
  final int batteryPercent;
  final bool isOfflineMode;
  final int pendingOfflinePayloads;

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
    this.isOfflineMode = false,
    this.pendingOfflinePayloads = 0,
  });

  factory SystemArchitectureState.initial() {
    const defaultService = DeliveryServiceType.standard;
    const defaultDistMeters = 0;
    const defaultDurationSec = 0;
    const defaultVoucher = 0.0;
    final store = AppStateStore.instance;

    return SystemArchitectureState(
      selectedRole: SubsystemRole.customer,
      selectedService: defaultService,
      distanceMeters: defaultDistMeters,
      durationSeconds: defaultDurationSec,
      isPeakHour: false,
      voucherDiscount: defaultVoucher,
      estimate: PricingEstimate.calculate(
        serviceType: defaultService,
        distanceMeters: defaultDistMeters,
        durationSeconds: defaultDurationSec,
        isPeakHour: false,
        voucherDiscount: defaultVoucher,
        configuredStandardPeakSurcharge: store.peakHourSurchargeConfig,
      ),
      lastSmoothedGps: store.liveDeviceLocation,
      batteryPolicy: GpsIntegrityValidator.resolvePolicy(
        batteryLevelPercent: 85,
        isCharging: false,
      ),
      batteryPercent: 85,
      isOfflineMode: store.isOfflineMode,
      pendingOfflinePayloads: store.offlineQueueCount,
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
    batteryPolicy,
    batteryPercent,
    isOfflineMode,
    pendingOfflinePayloads,
  ];
}

class SystemArchitectureCubit extends Cubit<SystemArchitectureState> {
  final KalmanGpsFilter _kalmanFilter = KalmanGpsFilter();
  late final VoidCallback _storeListener;

  SystemArchitectureCubit() : super(SystemArchitectureState.initial()) {
    _storeListener = _handleStoreChanged;
    AppStateStore.instance.addListener(_storeListener);
  }

  PricingEstimate _computeEstimate({
    required DeliveryServiceType serviceType,
    required bool isPeakHour,
  }) {
    final store = AppStateStore.instance;
    final baseScale = (store.baseFareConfig / 25000.0).clamp(0.4, 5.0);
    final kmScale = (store.pricePerKmConfig / 5000.0).clamp(0.4, 5.0);
    final weatherFee = store.isWeatherSurchargeActive
        ? store.badWeatherSurchargeConfig
        : 0.0;
    return PricingEstimate.calculate(
      serviceType: serviceType,
      distanceMeters: state.distanceMeters,
      durationSeconds: state.durationSeconds,
      isPeakHour: isPeakHour,
      geofenceSurcharge: weatherFee,
      voucherDiscount: state.voucherDiscount,
      baseFareScale: baseScale,
      pricePerKmScale: kmScale,
      configuredStandardPeakSurcharge: store.peakHourSurchargeConfig,
    );
  }

  void _handleStoreChanged() {
    if (isClosed) return;
    final store = AppStateStore.instance;
    final nextRole = store.activeAuthenticatedUser?.role ?? state.selectedRole;
    final nextEstimate = _computeEstimate(
      serviceType: state.selectedService,
      isPeakHour: store.isPeakSurchargeActive,
    );
    emit(
      SystemArchitectureState(
        selectedRole: nextRole,
        selectedService: state.selectedService,
        distanceMeters: state.distanceMeters,
        durationSeconds: state.durationSeconds,
        isPeakHour: store.isPeakSurchargeActive,
        voucherDiscount: state.voucherDiscount,
        estimate: nextEstimate,
        lastSmoothedGps: state.lastSmoothedGps,
        batteryPolicy: state.batteryPolicy,
        batteryPercent: store.batteryPercent,
        isOfflineMode: store.isOfflineMode,
        pendingOfflinePayloads: store.offlineQueueCount,
      ),
    );
  }

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
        isOfflineMode: state.isOfflineMode,
        pendingOfflinePayloads: state.pendingOfflinePayloads,
      ),
    );
  }

  void updateServiceAndPricing({
    DeliveryServiceType? serviceType,
    bool? isPeakHour,
  }) {
    final nextService = serviceType ?? state.selectedService;
    final nextPeak = isPeakHour ?? state.isPeakHour;
    final nextEstimate = _computeEstimate(
      serviceType: nextService,
      isPeakHour: nextPeak,
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
        isOfflineMode: state.isOfflineMode,
        pendingOfflinePayloads: state.pendingOfflinePayloads,
      ),
    );
  }

  void updateBatteryLevel(
    int batteryPercent, {
    bool isCharging = false,
    GeoPoint? rawGpsSample,
    double accuracyMeters = 4.5,
  }) {
    final clampedBattery = batteryPercent.clamp(1, 100);
    AppStateStore.instance.batteryPercent = clampedBattery;
    final nextPolicy = GpsIntegrityValidator.resolvePolicy(
      batteryLevelPercent: clampedBattery,
      isCharging: isCharging,
    );
    final smoothed = rawGpsSample != null
        ? _kalmanFilter.filter(
            rawPoint: rawGpsSample,
            accuracyMeters: accuracyMeters,
            timestampMs: DateTime.now().millisecondsSinceEpoch,
          )
        : AppStateStore.instance.activeDriverLocation;

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
        batteryPercent: clampedBattery,
        isOfflineMode: state.isOfflineMode,
        pendingOfflinePayloads: state.pendingOfflinePayloads,
      ),
    );
  }

  @override
  Future<void> close() {
    AppStateStore.instance.removeListener(_storeListener);
    return super.close();
  }
}
