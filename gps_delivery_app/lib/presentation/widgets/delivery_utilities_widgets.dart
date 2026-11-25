import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/gps/driver_multi_trip_planner.dart';
import '../../core/theme/ghst_theme_tokens.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/delivery_order_utilities.dart';
import '../../core/utils/security_and_barcode_utils.dart';
import '../../domain/entities/vehicle_class.dart';
import 'cloud_order_labels.dart';
import 'ghst_button_icon.dart';

/// Opens an interactive 5-vehicle × 5-service fare comparison dialog so users
/// can benchmark delivery costs across vehicle classes and pick one directly.
Future<void> showDeliveryFareComparisonSheet(
  BuildContext context, {
  required double initialDistanceKm,
  required double initialWeightKg,
  required VehicleClass selectedVehicle,
  required String selectedServiceType,
  required void Function(VehicleClass vehicle, String serviceType) onSelect,
}) => showDialog<void>(
  context: context,
  builder: (_) => _FareComparisonDialog(
    initialDistanceKm: initialDistanceKm,
    initialWeightKg: initialWeightKg,
    selectedVehicle: selectedVehicle,
    selectedServiceType: selectedServiceType,
    onSelect: onSelect,
  ),
);

class _FareComparisonDialog extends StatefulWidget {
  const _FareComparisonDialog({
    required this.initialDistanceKm,
    required this.initialWeightKg,
    required this.selectedVehicle,
    required this.selectedServiceType,
    required this.onSelect,
  });

  final double initialDistanceKm;
  final double initialWeightKg;
  final VehicleClass selectedVehicle;
  final String selectedServiceType;
  final void Function(VehicleClass vehicle, String serviceType) onSelect;

  @override
  State<_FareComparisonDialog> createState() => _FareComparisonDialogState();
}

class _FareComparisonDialogState extends State<_FareComparisonDialog> {
  late double _km = widget.initialDistanceKm.clamp(0.5, 200.0);
  late double _kg = widget.initialWeightKg.clamp(0.1, 1500.0);

  String _fmtNum(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    final kmOptions = <double>{
      widget.initialDistanceKm.clamp(0.5, 200.0),
      3,
      5,
      10,
      20,
      60,
    }.toList()..sort();
    final kgOptions = <double>{
      widget.initialWeightKg.clamp(0.1, 1500.0),
      2,
      15,
      100,
      400,
      1000,
    }.toList()..sort();
    final rows = estimateDeliveryFareMatrix(distanceKm: _km, weightKg: _kg);

    return AlertDialog(
      title: const Text('Bảng so sánh cước 5 loại xe & 5 gói dịch vụ'),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Quãng đường ước tính (${_fmtNum(_km)} km)',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: tokens.ink,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final km in kmOptions)
                    ChoiceChip(
                      key: ValueKey('fare-km-${_fmtNum(km)}'),
                      label: Text('${_fmtNum(km)} km'),
                      selected: (_km - km).abs() < 0.05,
                      onSelected: (_) => setState(() => _km = km),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Khối lượng hàng (${_fmtNum(_kg)} kg)',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: tokens.ink,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final kg in kgOptions)
                    ChoiceChip(
                      key: ValueKey('fare-kg-${_fmtNum(kg)}'),
                      label: Text('${_fmtNum(kg)} kg'),
                      selected: (_kg - kg).abs() < 0.05,
                      onSelected: (_) => setState(() => _kg = kg),
                    ),
                ],
              ),
              const Divider(height: 20),
              for (final row in rows)
                Builder(
                  builder: (context) {
                    final selected =
                        row.vehicle == widget.selectedVehicle &&
                        row.serviceType == widget.selectedServiceType;
                    final selectable = row.selectable;
                    return Opacity(
                      opacity: selectable ? 1.0 : 0.55,
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: selected
                                ? tokens.sapphire.foreground
                                : tokens.border,
                            width: selected ? 1.6 : 1.0,
                          ),
                        ),
                        child: ListTile(
                          key: ValueKey(
                            'fare-row-${row.vehicle.id}-${row.serviceType}',
                          ),
                          enabled: selectable,
                          onTap: selectable
                              ? () {
                                  widget.onSelect(row.vehicle, row.serviceType);
                                  Navigator.of(context).pop();
                                }
                              : null,
                          leading: GhstButtonIcon(
                            row.vehicle.heavy
                                ? Icons.local_shipping_outlined
                                : Icons.two_wheeler_rounded,
                            color: selected
                                ? tokens.sapphire.foreground
                                : tokens.inkSecondary,
                          ),
                          title: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '${row.vehicle.label} · ${row.serviceLabel}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                              if (selected)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tokens.sapphire.fill,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'Đang chọn',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: tokens.sapphire.foreground,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            row.disabledReason ??
                                'Tải tối đa ${row.vehicle.maxKg} kg · Chạm để chọn',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: row.disabledReason != null
                                  ? tokens.rose.foreground
                                  : tokens.inkSecondary,
                            ),
                          ),
                          trailing: Text(
                            CurrencyFormatter.formatVnd(
                              row.estimatedFee.toDouble(),
                            ),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              color: tokens.ink,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}

/// Shows an A6 printable waybill preview with Code-128 barcode, QR lookup matrix,
/// COD/fee summary, and export button (`HTML` A6 print sheet).
Future<void> showCloudWaybillA6Dialog(
  BuildContext context, {
  required Map<String, dynamic> order,
}) => showDialog<void>(
  context: context,
  builder: (_) => _CloudWaybillA6Dialog(order: order),
);

class _CloudWaybillA6Dialog extends StatefulWidget {
  const _CloudWaybillA6Dialog({required this.order});
  final Map<String, dynamic> order;

  @override
  State<_CloudWaybillA6Dialog> createState() => _CloudWaybillA6DialogState();
}

class _CloudWaybillA6DialogState extends State<_CloudWaybillA6Dialog> {
  bool _exporting = false;
  String? _exportedPath;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final details = order['details'] is Map
        ? order['details'] as Map
        : const <String, dynamic>{};
    final trackingCode = '${order['tracking_code'] ?? order['id'] ?? 'GHST'}';
    final pickup = '${details['pickup_address'] ?? ''}';
    final dropoff = '${details['dropoff_address'] ?? ''}';
    final recName = '${details['recipient_name'] ?? ''}';
    final recPhone = '${details['recipient_phone'] ?? ''}';
    final pkg = '${details['package_description'] ?? ''}';
    final weight = '${details['weight_kg'] ?? ''}';
    final vehicle = VehicleClass.resolve(
      vehicleType: details['vehicle_type'],
      serviceType: details['service_type'],
      preferEv: details['prefer_ev'] == true,
    );
    final service =
        cloudServiceTypes[details['service_type']] ??
        '${details['service_type'] ?? 'Tiêu chuẩn'}';
    final cod = (order['cod_amount'] as num? ?? 0).toDouble();
    final recipientFee = details['payment_method'] == 'recipient_cash'
        ? cloudOrderPayableFee(order).toDouble()
        : 0.0;
    final totalCollect = cod + recipientFee;
    final qrPayload =
        (Uri.base.scheme == 'http' || Uri.base.scheme == 'https') &&
            Uri.base.host.isNotEmpty
        ? '${Uri.base.origin}/#/track?code=$trackingCode'
        : 'GHST|$trackingCode|$recPhone';

    final tokens = GhstThemeTokens.of(context);
    return AlertDialog(
      title: Text('Phiếu gửi hàng A6 · $trackingCode'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF1E3A8A),
                    width: 1.6,
                  ),
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'GHST EXPRESS · A6',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13.5,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                          Text(
                            '${vehicle.shortLabel} · $service',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Code128BarcodeWidget(
                              data: trackingCode,
                              height: 46,
                            ),
                          ),
                          const SizedBox(width: 10),
                          QrMatrixPainterWidget(payload: qrPayload, size: 88),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text('Điểm lấy: $pickup'),
                      const SizedBox(height: 4),
                      Text(
                        'Người nhận: $recName${recPhone.isNotEmpty ? ' · $recPhone' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text('Điểm giao: $dropoff'),
                      const SizedBox(height: 4),
                      Text(
                        'Hàng hóa: $pkg${weight.isNotEmpty ? ' ($weight kg)' : ''}',
                      ),
                      const Divider(height: 16),
                      Text(
                        'COD: ${CurrencyFormatter.formatVnd(cod)} · Cước người nhận trả: ${CurrencyFormatter.formatVnd(recipientFee)}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tổng thu người nhận: ${CurrencyFormatter.formatVnd(totalCollect)}',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_exportedPath != null) ...[
                const SizedBox(height: 10),
                Container(
                  key: const ValueKey('waybill-a6-exported'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: tokens.emerald.fill,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tokens.emerald.border),
                  ),
                  child: Text(
                    'Đã tạo phiếu in A6: $_exportedPath',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tokens.emerald.foreground,
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
        FilledButton.icon(
          key: const ValueKey('waybill-a6-export'),
          onPressed: _exporting
              ? null
              : () async {
                  setState(() {
                    _exporting = true;
                    _error = null;
                  });
                  try {
                    final path =
                        await SecurityAndBarcodeUtils.exportA6LabelToHtmlFile(
                          trackingCode: trackingCode,
                          storeName: 'GHST EXPRESS (${vehicle.label})',
                          warehouseAddress: pickup,
                          recipientName: recName,
                          recipientPhone: recPhone,
                          dropoffAddress: dropoff,
                          packageDescription: '$pkg ($weight kg)',
                          codAmount: cod,
                          recipientShippingFee: recipientFee,
                          qrPayload: qrPayload,
                        );
                    if (mounted) setState(() => _exportedPath = path);
                  } catch (_) {
                    if (mounted) {
                      setState(() => _error = 'Chưa xuất được phiếu A6.');
                    }
                  } finally {
                    if (mounted) setState(() => _exporting = false);
                  }
                },
          icon: const GhstButtonIcon(Icons.print_outlined, size: 17),
          label: Text(_exporting ? 'Đang tạo...' : 'Tải / In phiếu A6'),
        ),
      ],
    );
  }
}

/// Dialog letting a driver report a quick route incident to the live journey
/// chat (`[SỰ CỐ CHUYẾN GIAO] ...`) with optional details.
Future<String?> showDriverIncidentDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (_) => const _DriverIncidentDialog(),
    );

class _DriverIncidentDialog extends StatefulWidget {
  const _DriverIncidentDialog();

  @override
  State<_DriverIncidentDialog> createState() => _DriverIncidentDialogState();
}

class _DriverIncidentDialogState extends State<_DriverIncidentDialog> {
  String? _selectedCode;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  ({String code, String title, String detail})? get _selected {
    for (final p in driverIncidentPresets) {
      if (p.code == _selectedCode) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    return AlertDialog(
      title: const Text('Báo sự cố nhanh trên chuyến giao'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Chọn tình huống đang gặp để thông báo ngay cho khách hàng và điều hành:',
                style: TextStyle(fontSize: 12.5, color: tokens.inkSecondary),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in driverIncidentPresets)
                    ChoiceChip(
                      key: ValueKey('incident-preset-${preset.code}'),
                      label: Text(preset.title),
                      selected: _selectedCode == preset.code,
                      onSelected: (_) => setState(() {
                        _selectedCode = preset.code;
                        if (_note.text.trim().isEmpty ||
                            driverIncidentPresets.any(
                              (p) => p.detail == _note.text.trim(),
                            )) {
                          _note.text = preset.detail;
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('incident-note-field'),
                controller: _note,
                maxLines: 3,
                maxLength: 250,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú chi tiết (không bắt buộc)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          key: const ValueKey('incident-submit-btn'),
          onPressed: _selected == null
              ? null
              : () => Navigator.of(context).pop(
                  formatDriverIncidentMessage(_selected!.title, _note.text),
                ),
          icon: const GhstButtonIcon(Icons.warning_amber_rounded, size: 17),
          label: const Text('Gửi cảnh báo sự cố'),
        ),
      ],
    );
  }
}

/// Dialog displaying an optimized precedence-constrained multi-trip route
/// sequence for a driver partner, with total distance/ETA savings and 1-tap
/// external Google Maps navigation.
Future<void> showDriverMultiTripPlanDialog(
  BuildContext context, {
  required DriverMultiTripPlan plan,
  void Function(String orderId)? onOpenOrder,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) {
    final tokens = GhstThemeTokens.of(dialogContext);

    TonePair toneForKind(DriverStopKind kind) => switch (kind) {
      DriverStopKind.pickup => tokens.emerald,
      DriverStopKind.extraStop => tokens.amber,
      DriverStopKind.dropoff => tokens.rose,
      DriverStopKind.returnPickup => tokens.violet,
    };

    return AlertDialog(
      title: Text('Lộ trình gộp đa chuyến (${plan.activeOrderCount} đơn)'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                key: const ValueKey('driver-multi-trip-summary'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.cardSubtle,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.border),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const GhstButtonIcon(
                        Icons.pin_drop_outlined,
                        size: 16,
                      ),
                      label: Text('${plan.stops.length} điểm'),
                    ),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const GhstButtonIcon(
                        Icons.route_outlined,
                        size: 16,
                      ),
                      label: Text(
                        '${plan.optimizedDistanceKm.toStringAsFixed(1)} km · ~${plan.estimatedTotalMinutes} phút',
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (plan.savedDistanceKm >= 0.1)
                      Container(
                        key: const ValueKey('driver-multi-trip-saved-badge'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.emerald.fill,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: tokens.emerald.border),
                        ),
                        child: Text(
                          'Tiết kiệm ${plan.savedDistanceKm.toStringAsFixed(1)} km',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: tokens.emerald.foreground,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (plan.stops.isEmpty)
                Text(
                  'Chưa có điểm dừng nào có tọa độ GPS hợp lệ.',
                  style: TextStyle(color: tokens.inkMuted),
                )
              else
                for (final stop in plan.stops) ...[
                  Builder(
                    builder: (context) {
                      final tone = toneForKind(stop.kind);
                      return Container(
                        key: ValueKey(
                          'multi-trip-stop-${stop.orderId}-${stop.stopIndex}',
                        ),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: tokens.cardSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: tone.fill,
                                shape: BoxShape.circle,
                                border: Border.all(color: tone.border),
                              ),
                              child: Text(
                                '${stop.stopIndex}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: tone.foreground,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: tone.fill,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: tone.border,
                                          ),
                                        ),
                                        child: Text(
                                          stop.label,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: tone.foreground,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        stop.trackingCode,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: tokens.ink,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    stop.address,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: tokens.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${stop.recipientName} · +${stop.legDistanceKm.toStringAsFixed(1)} km · tích lũy ${stop.cumulativeKm.toStringAsFixed(1)} km (~${stop.etaMinutes}p)',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: tokens.inkSecondary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (onOpenOrder != null)
                              TextButton(
                                key: ValueKey(
                                  'multi-trip-open-${stop.orderId}-${stop.stopIndex}',
                                ),
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  onOpenOrder(stop.orderId);
                                },
                                child: const Text('Chi tiết'),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
            ],
          ),
        ),
      ),
      actions: [
        if (plan.googleMapsDirectionsUri != null)
          OutlinedButton.icon(
            key: const ValueKey('driver-multi-trip-open-maps'),
            onPressed: () => launchUrl(
              plan.googleMapsDirectionsUri!,
              mode: LaunchMode.externalApplication,
            ),
            icon: const GhstButtonIcon(Icons.map_outlined, size: 17),
            label: const Text('Mở Google Maps'),
          ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  },
);
