import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/theme/ghst_theme_tokens.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/delivery_order_utilities.dart';
import '../../data/models/app_state_records.dart';
import '../../domain/entities/geo_point.dart';
import '../../domain/entities/vehicle_class.dart';
import '../screens/cloud_order_details_screen.dart';
import 'cloud_order_labels.dart';
import 'cloud_session_boundary.dart';
import 'ghst_button_icon.dart';
import 'system_state_screens.dart';

/// Bảng bản đồ radar đội xe & lọc vận đơn dành cho Quản trị viên.
class AdminFleetRadarPanel extends StatefulWidget {
  const AdminFleetRadarPanel({
    super.key,
    required this.session,
    required this.lease,
    this.initialOrders,
    this.initialGpsByOrderId,
  });

  final CloudAccountSession session;
  final CloudSessionLease lease;
  final List<Map<String, dynamic>>? initialOrders;
  final Map<String, Map<String, dynamic>>? initialGpsByOrderId;

  @override
  State<AdminFleetRadarPanel> createState() => _AdminFleetRadarPanelState();
}

class _AdminFleetRadarPanelState extends State<AdminFleetRadarPanel> {
  static const _activeStatuses = {
    'accepted',
    'arrivingPickup',
    'inTransit',
    'returning',
  };

  List<Map<String, dynamic>> _orders = const [];
  Map<String, Map<String, dynamic>> _gpsByOrderId = const {};
  Map<String, Map<String, dynamic>> _driverByOrderId = const {};
  String? _vehicleFilter;
  String _statusFilter = 'all';
  bool _staleOnly = false;
  String? _selectedOrderId;
  bool _loading = false;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialOrders != null) {
      _orders = widget.initialOrders!;
      _gpsByOrderId = Map<String, Map<String, dynamic>>.from(
        widget.initialGpsByOrderId ?? const {},
      );
      if (_orders.isNotEmpty) {
        _selectedOrderId = '${_orders.first['id'] ?? ''}';
      }
    } else {
      unawaited(_load());
    }
  }

  static GeoPoint? _parsePoint(Object? rawLat, Object? rawLng) {
    final lat = rawLat is num
        ? rawLat.toDouble()
        : double.tryParse('${rawLat ?? ''}'.trim());
    final lng = rawLng is num
        ? rawLng.toDouble()
        : double.tryParse('${rawLng ?? ''}'.trim());
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        (lat == 0 && lng == 0) ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      return null;
    }
    return GeoPoint(latitude: lat, longitude: lng);
  }

  Future<void> _load() async {
    if (!mounted || !widget.lease.valid) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.session.service.request('orders');
      final rawOrders = ((res['orders'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final activeWithDriver = rawOrders
          .where(
            (o) =>
                _activeStatuses.contains('${o['status'] ?? ''}') &&
                o['driver_id'] != null,
          )
          .take(10)
          .toList();

      final nextGps = <String, Map<String, dynamic>>{};
      final nextDrivers = <String, Map<String, dynamic>>{};

      await Future.wait(
        activeWithDriver.map((order) async {
          final orderId = '${order['id'] ?? ''}'.trim();
          if (orderId.isEmpty) return;
          try {
            final snap = await widget.session.service.orderLive('snapshot', {
              'order_id': orderId,
            });
            final gps = snap['gps'];
            if (gps is Map &&
                _parsePoint(gps['latitude'], gps['longitude']) != null) {
              nextGps[orderId] = Map<String, dynamic>.from(gps);
            }
            final drv = snap['driver'];
            if (drv is Map) {
              nextDrivers[orderId] = Map<String, dynamic>.from(drv);
            }
          } catch (_) {
            // Best-effort snapshot: 1 đơn lỗi không chặn cả đội xe.
          }
        }),
      );

      if (!mounted) return;
      setState(() {
        _orders = rawOrders;
        _gpsByOrderId = nextGps;
        _driverByOrderId = nextDrivers;
        if (_selectedOrderId == null && rawOrders.isNotEmpty) {
          _selectedOrderId = '${rawOrders.first['id'] ?? ''}';
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  VehicleClass _resolveOrderVehicle(Map<String, dynamic> order) {
    final details = order['details'] as Map? ?? const {};
    return VehicleClass.resolve(
      vehicleType:
          details['vehicle_type'] ??
          order['vehicle_type'] ??
          details['vehicle_class'],
      serviceType: '${details['service_type'] ?? order['service_type'] ?? ''}',
      preferEv: details['prefer_ev'] == true,
    );
  }

  List<Map<String, dynamic>> get _filteredOrders {
    return _orders.where((order) {
      final vehicle = _resolveOrderVehicle(order);
      if (_vehicleFilter != null && vehicle.id != _vehicleFilter) {
        return false;
      }
      final status = '${order['status'] ?? ''}';
      return switch (_statusFilter) {
        'active' => _activeStatuses.contains(status),
        'searching' => status == 'searching',
        'delivered' => status == 'delivered',
        _ => true,
      };
    }).toList();
  }

  Future<void> _exportCsv(List<Map<String, dynamic>> orders) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final savedLabel = await exportOrdersCsvFile(orders);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Đã xuất CSV ${orders.length} vận đơn: $savedLabel'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Không xuất được CSV: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openDetails(Map<String, dynamic> order) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CloudSessionBoundary(
          session: widget.session,
          operator: true,
          builder: (_, lease) =>
              CloudOrderDetailsScreen(lease: lease, order: order),
        ),
      ),
    );
    if (mounted && widget.initialOrders == null) {
      await _load();
    }
  }

  Widget _buildSlaMetricsCard(
    BuildContext context,
    GhstThemeTokens tokens,
    AdminFleetOperationsMetrics metrics,
  ) {
    final co2Label = metrics.totalEvCo2SavedGrams >= 1000
        ? '${(metrics.totalEvCo2SavedGrams / 1000).toStringAsFixed(2)} kg'
        : '${metrics.totalEvCo2SavedGrams.round()} g';
    final kpis = <(String, String, TonePair)>[
      (
        'Tỷ lệ hoàn tất',
        '${metrics.completionRatePct.toStringAsFixed(1)}%',
        tokens.emerald,
      ),
      (
        'Lỗi / Hoàn hàng',
        '${metrics.failureReturnRatePct.toStringAsFixed(1)}%',
        metrics.failedOrReturned > 0 ? tokens.rose : tokens.sapphire,
      ),
      (
        'Tỷ lệ xe xanh EV',
        '${metrics.evAdoptionPct.toStringAsFixed(1)}%',
        tokens.cyan,
      ),
      ('CO₂ xanh tiết kiệm', co2Label, tokens.emerald),
    ];
    final activeVehicleRevs = VehicleClass.all
        .where((vc) => (metrics.revenueByVehicle[vc.id] ?? 0) > 0)
        .toList();

    return GhstLuminousCard(
      key: const ValueKey('admin-fleet-sla-metrics-card'),
      padding: const EdgeInsets.all(14),
      borderRadius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GhstButtonIcon(
                Icons.analytics_outlined,
                size: 18,
                color: tokens.sapphire.icon,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Phân tích SLA & Cơ cấu đội xe',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, box) {
              final cols = box.maxWidth >= 640 ? 4 : 2;
              final tileWidth = (box.maxWidth - 8 * (cols - 1)) / cols;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final kpi in kpis)
                    SizedBox(
                      width: tileWidth,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: kpi.$3.fill,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: kpi.$3.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              kpi.$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: tokens.inkMuted,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              kpi.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: kpi.$3.foreground,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          if (activeVehicleRevs.isEmpty)
            Text(
              'Chưa phát sinh doanh thu cước.',
              style: TextStyle(fontSize: 12, color: tokens.inkMuted),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final vc in activeVehicleRevs)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.cardSubtle,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Text(
                      '${vc.shortLabel}: ${CurrencyFormatter.formatVnd(metrics.revenueByVehicle[vc.id] ?? 0)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: tokens.inkSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    final fleetMetrics = computeAdminFleetMetrics(_orders);
    final allSummary = summarizeAdminOrders(_orders);
    final baseFiltered = _filteredOrders;
    final filtered = _staleOnly
        ? baseFiltered
              .where(
                (o) =>
                    fleetMetrics.staleSearchingIds.contains('${o['id'] ?? ''}'),
              )
              .toList()
        : baseFiltered;
    final vehicleCounts = <String, int>{
      for (final vc in VehicleClass.all) vc.id: 0,
    };
    for (final order in _orders) {
      final vid = _resolveOrderVehicle(order).id;
      vehicleCounts[vid] = (vehicleCounts[vid] ?? 0) + 1;
    }
    final selected = filtered.cast<Map<String, dynamic>?>().firstWhere(
      (o) => '${o?['id'] ?? ''}' == _selectedOrderId,
      orElse: () => filtered.isNotEmpty ? filtered.first : null,
    );

    final fleetDrivers = <DriverApplicantRecord>[];
    final seenDrivers = <String>{};
    for (final order in filtered) {
      final orderId = '${order['id'] ?? ''}';
      final gps = _gpsByOrderId[orderId];
      final point = gps == null
          ? null
          : _parsePoint(gps['latitude'], gps['longitude']);
      if (point == null) continue;
      final driverId = '${order['driver_id'] ?? orderId}';
      if (!seenDrivers.add(driverId)) continue;
      final drv = _driverByOrderId[orderId] ?? const <String, dynamic>{};
      final details = order['details'] as Map? ?? const {};
      final vehicle = _resolveOrderVehicle(order);
      fleetDrivers.add(
        DriverApplicantRecord(
          id: driverId,
          fullName:
              '${drv['full_name'] ?? details['driver_name'] ?? 'Tài xế #${driverId.substring(0, driverId.length > 6 ? 6 : driverId.length)}'}',
          phone: '${drv['phone'] ?? ''}',
          citizenId: '',
          licensePlate:
              '${drv['license_plate'] ?? details['license_plate'] ?? ''}',
          vehicleType: vehicle.label,
          vehicleColor: '',
          approvalStatus: 'Đã duyệt',
          isOnline: true,
          location: point,
        ),
      );
    }

    final selDetails = selected?['details'] as Map? ?? const {};
    final selId = '${selected?['id'] ?? ''}';
    final selGps = _gpsByOrderId[selId];
    final selDriverPt = selGps == null
        ? null
        : _parsePoint(selGps['latitude'], selGps['longitude']);
    final selPickupPt = _parsePoint(
      selDetails['pickup_lat'],
      selDetails['pickup_lng'],
    );
    final selDropoffPt = _parsePoint(
      selDetails['dropoff_lat'],
      selDetails['dropoff_lng'],
    );
    final routePoints = <GeoPoint>[?selPickupPt, ?selDriverPt, ?selDropoffPt];
    final focusCenter =
        selDriverPt ??
        selPickupPt ??
        (fleetDrivers.isNotEmpty
            ? fleetDrivers.first.location
            : const GeoPoint(latitude: 10.7769, longitude: 106.7009));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        GhstLuminousCard(
          padding: const EdgeInsets.all(14),
          borderRadius: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(
                    avatar: const GhstButtonIcon(
                      Icons.local_shipping_outlined,
                      size: 16,
                    ),
                    label: Text('Đơn hiển thị: ${filtered.length}'),
                  ),
                  Chip(
                    avatar: const GhstButtonIcon(Icons.gps_fixed, size: 16),
                    label: Text('Xe có GPS live: ${fleetDrivers.length}'),
                  ),
                  if (allSummary.staleSearching > 0 || _staleOnly)
                    FilterChip(
                      key: const ValueKey('radar-stale-sla-filter'),
                      selected: _staleOnly,
                      selectedColor: tokens.amber.fill,
                      backgroundColor: tokens.amber.fill,
                      side: BorderSide(color: tokens.amber.border),
                      avatar: GhstButtonIcon(
                        Icons.schedule_outlined,
                        size: 16,
                        color: tokens.amber.foreground,
                      ),
                      label: Text(
                        'Đơn chờ >15p: ${allSummary.staleSearching}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: tokens.amber.foreground,
                        ),
                      ),
                      onSelected: (sel) => setState(() => _staleOnly = sel),
                    ),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const GhstButtonIcon(Icons.refresh),
                    label: const Text('Làm mới radar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _exporting || filtered.isEmpty
                        ? null
                        : () => _exportCsv(filtered),
                    icon: const GhstButtonIcon(Icons.download_outlined),
                    label: const Text('Xuất CSV'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: const Text('Tất cả xe'),
                        selected: _vehicleFilter == null,
                        onSelected: (_) =>
                            setState(() => _vehicleFilter = null),
                      ),
                    ),
                    for (final vc in VehicleClass.all)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          key: ValueKey('radar-vehicle-${vc.id}'),
                          label: Text(
                            '${vc.shortLabel} (${vehicleCounts[vc.id] ?? 0})',
                          ),
                          selected: _vehicleFilter == vc.id,
                          onSelected: (_) => setState(
                            () => _vehicleFilter = _vehicleFilter == vc.id
                                ? null
                                : vc.id,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final opt in const [
                      ('all', 'Tất cả trạng thái'),
                      ('active', 'Đang chạy'),
                      ('searching', 'Chờ nhận'),
                      ('delivered', 'Hoàn tất'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(opt.$2),
                          selected: _statusFilter == opt.$1,
                          onSelected: (_) =>
                              setState(() => _statusFilter = opt.$1),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildSlaMetricsCard(context, tokens, fleetMetrics),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tokens.rose.fill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tokens.rose.border),
            ),
            child: Text(
              _error!,
              style: TextStyle(color: tokens.rose.foreground, fontSize: 12.5),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Map3dPerspectiveWidget(
            height: 290,
            mode: MapViewMode.fleetOverview,
            showTopBanner: false,
            useGlobalFallbackRoute: false,
            customFleetDrivers: fleetDrivers,
            driverLocation: selDriverPt,
            focusedCenterPoint: focusCenter,
            routePoints: routePoints,
            explicitDropoffPoint: selDropoffPt,
            pickupLabel: '${selDetails['pickup_address'] ?? 'Điểm lấy'}',
            dropoffLabel: '${selDetails['dropoff_address'] ?? 'Điểm giao'}',
            driverLabel:
                '${_driverByOrderId[selId]?['full_name'] ?? 'Đội xe GHST'}',
          ),
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty && !_loading)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: tokens.cardSubtle,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tokens.border),
            ),
            child: Center(
              child: Text(
                'Không có vận đơn phù hợp bộ lọc hiện tại.',
                style: TextStyle(color: tokens.inkMuted),
              ),
            ),
          )
        else
          for (final order in filtered.take(30)) ...[
            Builder(
              builder: (context) {
                final id = '${order['id'] ?? ''}';
                final isSelected = id == selId;
                final details = order['details'] as Map? ?? const {};
                final status = '${order['status'] ?? ''}';
                final vehicle = _resolveOrderVehicle(order);
                final hasLiveGps = _gpsByOrderId.containsKey(id);
                final statusTone = switch (status) {
                  'delivered' => tokens.emerald,
                  'cancelled' || 'failed' => tokens.rose,
                  'searching' => tokens.amber,
                  'returning' || 'returned' => tokens.violet,
                  _ => tokens.sapphire,
                };
                Widget radarRouteRow(Color dotColor, String text) => Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: tokens.inkMuted,
                        ),
                      ),
                    ),
                  ],
                );
                return GhstLuminousCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  borderRadius: 16,
                  accentGlow: isSelected ? tokens.sapphire.glow : null,
                  borderColor: isSelected
                      ? tokens.sapphire.foreground
                      : tokens.border,
                  onTap: () => setState(() => _selectedOrderId = id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${order['tracking_code'] ?? id}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              color: tokens.ink,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasLiveGps)
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tokens.emerald.fill,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: tokens.emerald.border,
                                    ),
                                  ),
                                  child: Text(
                                    'GPS LIVE',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: tokens.emerald.foreground,
                                    ),
                                  ),
                                ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: statusTone.fill,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: statusTone.border),
                                ),
                                child: Text(
                                  cloudStatuses[status] ?? status,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: statusTone.foreground,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${vehicle.label} · ${CurrencyFormatter.formatVnd(cloudOrderPayableFee(order))}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: tokens.sapphire.foreground,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 6),
                      radarRouteRow(
                        tokens.emerald.icon,
                        'Lấy: ${details['pickup_address'] ?? '—'}',
                      ),
                      const SizedBox(height: 3),
                      radarRouteRow(
                        tokens.rose.icon,
                        'Giao: ${details['dropoff_address'] ?? '—'}',
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: () => _openDetails(order),
                          icon: const GhstButtonIcon(
                            Icons.receipt_long_outlined,
                          ),
                          label: const Text('Chi tiết'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
      ],
    );
  }
}
