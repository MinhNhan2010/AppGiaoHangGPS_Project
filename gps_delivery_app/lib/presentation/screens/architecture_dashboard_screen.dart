import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/env_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../domain/enums/service_type.dart';
import '../../domain/enums/user_role.dart';
import '../bloc/system_architecture_cubit.dart';

class ArchitectureDashboardScreen extends StatelessWidget {
  const ArchitectureDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SystemArchitectureCubit, SystemArchitectureState>(
      builder: (context, state) {
        final cubit = context.read<SystemArchitectureCubit>();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Hệ Thống Giao Hàng Định Vị GPS Đa Nền Tảng'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSubsystemSelectorCard(context, state, cubit),
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
              'Kiến trúc 4 Phân hệ Cốt lõi (46 Use Case & 16 Bảng PostGIS)',
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
              valueColor:
                  policy.enable3dBuildings ? AppColors.success : AppColors.warning,
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
