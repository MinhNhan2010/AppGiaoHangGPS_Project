import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/env_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/enums/service_type.dart';
import '../../domain/enums/user_role.dart';
import '../admin/admin_subsystem_views.dart';
import '../bloc/system_architecture_cubit.dart';
import '../customer/customer_subsystem_views.dart';
import '../driver/driver_subsystem_views.dart';
import '../merchant/merchant_subsystem_views.dart';
import '../widgets/system_state_screens.dart';

class ArchitectureDashboardScreen extends StatefulWidget {
  const ArchitectureDashboardScreen({super.key});

  @override
  State<ArchitectureDashboardScreen> createState() =>
      _ArchitectureDashboardScreenState();
}

class _ArchitectureDashboardScreenState
    extends State<ArchitectureDashboardScreen> {
  final AppStateStore _store = AppStateStore.instance;
  bool _showOnboardingPreview = false;
  bool _showSkeletonPreview = false;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreUpdated);
  }

  void _onStoreUpdated() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreUpdated);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showOnboardingPreview) {
      return OnboardingStateScreen(
        onGetStarted: () => setState(() => _showOnboardingPreview = false),
      );
    }

    return BlocBuilder<SystemArchitectureCubit, SystemArchitectureState>(
      builder: (context, state) {
        final cubit = context.read<SystemArchitectureCubit>();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Hệ Thống Giao Hàng Định Vị GPS Đa Nền Tảng'),
            actions: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.surface),
                onPressed: () =>
                    _store.toggleOfflineSimulation(!_store.isOfflineMode),
                icon: Icon(
                  _store.isOfflineMode ? Icons.wifi_off : Icons.wifi,
                  size: 18,
                ),
                label: Text(_store.isOfflineMode ? 'Offline' : 'Online'),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSubsystemSelectorCard(context, state, cubit),
                const SizedBox(height: AppSpacing.md),
                _buildActiveSubsystemView(state.selectedRole),
                const SizedBox(height: AppSpacing.md),
                _buildSystemStateShowcaseCard(context),
                const SizedBox(height: AppSpacing.md),
                _buildPricingCalculatorCard(context, state, cubit),
                const SizedBox(height: AppSpacing.md),
                _buildGpsAnd3dMapPolicyCard(context, state, cubit),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveSubsystemView(SubsystemRole role) {
    switch (role) {
      case SubsystemRole.customer:
        return const CustomerSubsystemEntry();
      case SubsystemRole.driver:
        return const DriverSubsystemEntry();
      case SubsystemRole.merchant:
        return const MerchantSubsystemEntry();
      case SubsystemRole.admin:
        return const AdminSubsystemEntry();
    }
  }

  Widget _buildSubsystemSelectorCard(
    BuildContext context,
    SystemArchitectureState state,
    SystemArchitectureCubit cubit,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kiến trúc 4 Phân hệ Cốt lõi (46 Use Case, 51 Màn hình & 16 Bảng PostGIS)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: SubsystemRole.values.map((role) {
                final isSelected = state.selectedRole == role;
                return ChoiceChip(
                  label: Text(role.title),
                  selected: isSelected,
                  selectedColor: AppColors.accent.withValues(alpha: 0.2),
                  onSelected: (_) => cubit.selectRole(role),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppSpacing.sm),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_outlined, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${state.selectedRole.title}: ${state.selectedRole.coverageSummary}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemStateShowcaseCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trạng thái Hệ thống & Bản đồ 3D (Hình 8.47 - Hình 8.51)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.rocket_launch_outlined, size: 16),
                  label: const Text('Hình 8.47: Mở Onboarding'),
                  onPressed: () =>
                      setState(() => _showOnboardingPreview = true),
                ),
                FilterChip(
                  label: const Text('Hình 8.49: Mô phỏng Mất mạng (SQLite)'),
                  selected: _store.isOfflineMode,
                  onSelected: (v) => _store.toggleOfflineSimulation(v),
                ),
                FilterChip(
                  label: const Text('Hình 8.50: Shimmer Skeleton Loading'),
                  selected: _showSkeletonPreview,
                  onSelected: (v) => setState(() => _showSkeletonPreview = v),
                ),
                FilterChip(
                  label: const Text('Hình 8.51: Bật/Tắt Bản đồ 3D Pitch 55°'),
                  selected: _store.isMap3dEnabled,
                  onSelected: (_) => _store.toggleMap3d(),
                ),
              ],
            ),
            if (_showSkeletonPreview) ...[
              const SizedBox(height: AppSpacing.sm),
              const SkeletonOrderListWidget(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPricingCalculatorCard(
    BuildContext context,
    SystemArchitectureState state,
    SystemArchitectureCubit cubit,
  ) {
    final est = state.estimate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bộ tính Cước phí GPS & Khuyến mãi (UC04, UC05, UC26)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: DeliveryServiceType.values.map((svc) {
                final isSelected = state.selectedService == svc;
                return ChoiceChip(
                  label: Text('${svc.displayName} (${svc.etaLabel})'),
                  selected: isSelected,
                  onSelected: (_) =>
                      cubit.updateServiceAndPricing(serviceType: svc),
                );
              }).toList(),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Áp dụng Phụ phí Giờ cao điểm'),
              value: state.isPeakHour,
              onChanged: (v) => cubit.updateServiceAndPricing(isPeakHour: v),
            ),
            const Divider(),
            _buildPriceRow(
              'Quãng đường & Thời gian dự kiến',
              '${CurrencyFormatter.formatDistanceKm(state.distanceMeters)} • ${CurrencyFormatter.formatDurationMinutes(state.durationSeconds)}',
            ),
            _buildPriceRow(
              'Phí cơ bản',
              CurrencyFormatter.formatVnd(est.baseFare),
            ),
            _buildPriceRow(
              'Phí theo km (${est.distanceKm.toStringAsFixed(1)} km)',
              CurrencyFormatter.formatVnd(est.distanceFare),
            ),
            _buildPriceRow(
              'Phụ phí giờ cao điểm',
              CurrencyFormatter.formatVnd(est.surchargeFee),
            ),
            _buildPriceRow(
              'Mã giảm giá (PROMO20K)',
              '-${CurrencyFormatter.formatVnd(est.discountAmount)}',
              valueColor: AppColors.accent,
            ),
            const Divider(),
            _buildPriceRow(
              'Tổng cộng thanh toán',
              CurrencyFormatter.formatVnd(est.totalAmount),
              isBold: true,
              valueColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsAnd3dMapPolicyCard(
    BuildContext context,
    SystemArchitectureState state,
    SystemArchitectureCubit cubit,
  ) {
    final policy = state.batteryPolicy;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Engine Bản đồ 3D, Kalman Filter & Điều tiết Pin (Chương 4, 8.6, 15)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Mức pin thiết bị: ${state.batteryPercent}% (Tự động hạ từ 3D về 2D khi <= ${EnvConfig.lowBattery2dFallbackPercent}%)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Slider(
              value: state.batteryPercent.toDouble(),
              min: 5,
              max: 100,
              divisions: 19,
              label: '${state.batteryPercent}%',
              onChanged: (v) => cubit.updateBatteryLevel(v.round()),
            ),
            _buildPriceRow(
              'Tọa độ sau lọc Kalman 2D',
              '${state.lastSmoothedGps.latitude.toStringAsFixed(5)}, ${state.lastSmoothedGps.longitude.toStringAsFixed(5)}',
            ),
            _buildPriceRow(
              'Chế độ Camera Bản đồ',
              policy.enable3dBuildings
                  ? '3D Perspective (Pitch ${policy.cameraPitch.toStringAsFixed(0)}° • ${policy.targetFps} FPS)'
                  : '2D Tiết kiệm Pin (Pitch 0° • ${policy.targetFps} FPS)',
              valueColor: policy.enable3dBuildings
                  ? AppColors.success
                  : AppColors.warning,
            ),
            _buildPriceRow(
              'Chu kỳ phát GPS / Độ lệch tối thiểu',
              '${policy.pingIntervalSeconds} giây / ${policy.distanceFilterMeters} mét',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
                color: valueColor ?? AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
