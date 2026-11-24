import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/env_config.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/integrations/delivery_weather_service.dart';
import '../../core/network/public_json_api.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/entities/geo_point.dart';
import '../../domain/entities/vehicle_class.dart';
import 'animated_3d_ui_icons.dart';
import 'delivery_weather_strip.dart';
import 'ghst_button_icon.dart';

String _formatVnd(dynamic value) =>
    CurrencyFormatter.formatVnd((value as num? ?? 0).toDouble());

String _formatDistanceKm(dynamic metersRaw) {
  final meters = (metersRaw as num? ?? 0).toDouble();
  if (meters <= 0) return '0.0 km';
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000.0).toStringAsFixed(1)} km';
}

String _vehicleLabel(String raw) => VehicleClass.byId(raw).label;

String _serviceLabel(String raw) => switch (raw) {
  'saving' => 'Tiết kiệm',
  'same_day_2h' => 'Nội thành 2H',
  'express' => 'Siêu tốc',
  'truck' => 'Xe tải',
  _ => 'Tiêu chuẩn',
};

class DriverDispatchPresenceBar extends StatefulWidget {
  const DriverDispatchPresenceBar({
    super.key,
    required this.lease,
    this.onOrderAccepted,
    this.onPresenceChanged,
    this.compact = false,
    this.weatherService,
  });

  final CloudSessionLease lease;
  final ValueChanged<Map<String, dynamic>>? onOrderAccepted;
  final VoidCallback? onPresenceChanged;
  final bool compact;
  final DeliveryWeatherService? weatherService;

  @override
  State<DriverDispatchPresenceBar> createState() =>
      _DriverDispatchPresenceBarState();
}

class _DriverDispatchPresenceBarState extends State<DriverDispatchPresenceBar> {
  Map<String, dynamic>? _presence;
  Map<String, dynamic>? _activeOffer;
  int _activeTripsCount = 0;
  bool _loading = true;
  bool _busy = false;
  bool _offerDialogOpen = false;
  String? _shownOfferId;
  String? _error;
  String? _notice;
  Timer? _heartbeatTimer;

  bool get _isAutomatedTestBinding {
    final bindingType = WidgetsBinding.instance.runtimeType.toString();
    return bindingType.contains('TestWidgetsFlutterBinding') ||
        bindingType.contains('AutomatedTest');
  }

  bool get _isOnline => _presence?['is_online'] == true;
  String get _vehicleType => '${_presence?['vehicle_type'] ?? 'motorbike'}';

  /// Vehicle from the operator-approved partner application, if any; the
  /// server forces presence to it, so the chip row is locked.
  String? get _approvedVehicle {
    final raw = _presence?['approved_vehicle_type'];
    return raw is String && VehicleClass.tryById(raw) != null ? raw : null;
  }

  bool get _allowBatching => _presence?['allow_batching'] != false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPresence());
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  void _syncHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (_isAutomatedTestBinding || !_isOnline || !widget.lease.valid) return;
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 7),
      (_) => unawaited(_pollOffer(silent: true)),
    );
  }

  (double, double) _resolveDriverGps() {
    final loc =
        AppStateStore.instance.liveDeviceLocation ??
        AppStateStore.instance.activeDriverLocation;
    final lat = loc.latitude.abs() <= 90 ? loc.latitude : 10.7769;
    final lng = loc.longitude.abs() <= 180 ? loc.longitude : 106.7009;
    return (lat, lng);
  }

  Future<void> _loadPresence() async {
    if (!widget.lease.valid) return;
    try {
      final res = await widget.lease.session.service.driverDispatch(
        'get_presence',
      );
      if (!mounted || !widget.lease.valid) return;
      final p = res['presence'];
      setState(() {
        _presence = p is Map ? Map<String, dynamic>.from(p) : null;
        _activeTripsCount = (res['active_trips_count'] as num? ?? 0).toInt();
        _loading = false;
        _error = null;
      });
      _syncHeartbeatTimer();
      if (_isOnline) {
        unawaited(_pollOffer(silent: true));
      }
    } catch (e) {
      if (!mounted || widget.lease.handleAccessFailure(e)) return;
      setState(() {
        _loading = false;
        _error = e is PublicApiException
            ? e.message
            : 'Chưa kết nối được radar điều phối trực tuyến.';
      });
    }
  }

  Future<void> _updatePresence({
    bool? isOnline,
    String? vehicleType,
    bool? allowBatching,
  }) async {
    if (_busy || !widget.lease.valid) return;
    final (lat, lng) = _resolveDriverGps();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final res = await widget.lease.session.service.driverDispatch(
        'set_presence',
        {
          'is_online': isOnline ?? _isOnline,
          'latitude': lat,
          'longitude': lng,
          'heading': 90.0,
          'vehicle_type': vehicleType ?? _vehicleType,
          'allow_batching': allowBatching ?? _allowBatching,
        },
      );
      if (!mounted || !widget.lease.valid) return;
      _applyPollResponse(
        res,
        notice: (isOnline ?? _isOnline)
            ? 'Đã bật trực tuyến radar GPS — sẵn sàng nhận cuốc tự động.'
            : 'Đã chuyển sang tạm nghỉ nhận cuốc tự động.',
      );
      widget.onPresenceChanged?.call();
    } catch (e) {
      if (!mounted || widget.lease.handleAccessFailure(e)) return;
      setState(() {
        _busy = false;
        _error = e is PublicApiException
            ? e.message
            : 'Không cập nhật được trạng thái trực tuyến.';
      });
    }
  }

  Future<void> _pollOffer({bool silent = false}) async {
    if (!widget.lease.valid) return;
    if (!silent) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    final (lat, lng) = _resolveDriverGps();
    try {
      final res = await widget.lease.session.service.driverDispatch(
        'poll_offer',
        {'latitude': lat, 'longitude': lng, 'heading': 90.0},
      );
      if (!mounted || !widget.lease.valid) return;
      _applyPollResponse(
        res,
        notice: !silent && res['active_offer'] == null
            ? 'Radar đã quét bán kính 3–8 km — hiện chưa có cuốc đẩy mới.'
            : null,
      );
    } catch (e) {
      if (!mounted || widget.lease.handleAccessFailure(e)) return;
      if (!silent) {
        setState(() {
          _busy = false;
          _error = e is PublicApiException
              ? e.message
              : 'Không thể làm mới radar điều phối.';
        });
      }
    }
  }

  void _applyPollResponse(Map<String, dynamic> res, {String? notice}) {
    final p = res['presence'];
    final offer = res['active_offer'];
    final offerMap = offer is Map ? Map<String, dynamic>.from(offer) : null;
    setState(() {
      _busy = false;
      _loading = false;
      if (p is Map) _presence = Map<String, dynamic>.from(p);
      _activeTripsCount = (res['active_trips_count'] as num? ?? 0).toInt();
      _activeOffer = offerMap;
      if (notice != null) _notice = notice;
    });
    _syncHeartbeatTimer();
    if (offerMap != null) {
      final offerId = '${offerMap['id'] ?? ''}';
      if (offerId.isNotEmpty && !_offerDialogOpen && _shownOfferId != offerId) {
        _shownOfferId = offerId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_presentIncomingOfferDialog(offerMap));
        });
      }
    }
  }

  Future<void> _presentIncomingOfferDialog(Map<String, dynamic> offer) async {
    if (_offerDialogOpen || !mounted || !widget.lease.valid) return;
    _offerDialogOpen = true;
    try {
      final outcome = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => DriverIncomingOfferDialog(
          lease: widget.lease,
          offer: offer,
          isAutomatedTest: _isAutomatedTestBinding,
        ),
      );
      if (!mounted || !widget.lease.valid) return;
      if (outcome != null && outcome['accepted'] == true) {
        final acceptedOrder = outcome['order'];
        setState(() {
          _activeOffer = null;
          _activeTripsCount += 1;
          _notice =
              'Đã nhận cuốc ${offer['tracking_code'] ?? ''} — chuyển sang buồng lái giao hàng!';
        });
        widget.onPresenceChanged?.call();
        if (acceptedOrder is Map) {
          widget.onOrderAccepted?.call(
            Map<String, dynamic>.from(acceptedOrder),
          );
        }
      } else if (outcome != null && outcome['rejected'] == true) {
        setState(() {
          _activeOffer = null;
          _notice = 'Đã bỏ qua đề xuất cuốc — hệ thống đã chuyển ngay cho tài xế kế tiếp.';
        });
        widget.onPresenceChanged?.call();
      }
    } finally {
      _offerDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final online = _isOnline;
    final activeOffer = _activeOffer;
    final (lat, lng) = _resolveDriverGps();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(widget.compact ? 12 : 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: online
              ? [
                  const Color(0xFF065F46).withValues(alpha: 0.14),
                  scheme.surfaceContainerLow,
                ]
              : [
                  scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                  scheme.surfaceContainerLow,
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: online
              ? const Color(0xFF10B981).withValues(alpha: 0.45)
              : scheme.outlineVariant,
          width: online ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GhstButtonIcon.ai(
                Icon3dStyle.gpsPinRadar,
                size: widget.compact ? 32 : 38,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            online
                                ? 'Đang trực tuyến — Radar đẩy cuốc GPS (3–8 km)'
                                : 'Tạm nghỉ — Bật trực tuyến để nhận cuốc tự động',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      online
                          ? 'Phương tiện: ${_vehicleLabel(_vehicleType)} • Đang chạy: $_activeTripsCount chuyến${_allowBatching ? ' • Ưu tiên ghép tuyến' : ''}'
                          : 'Hệ thống sẽ tự động đẩy cuốc gần nhất kèm đếm ngược 28 giây khi bạn bật trực tuyến.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                key: const ValueKey('driver-presence-toggle'),
                value: online,
                onChanged: _loading || _busy
                    ? null
                    : (val) => _updatePresence(isOnline: val),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final entry in [
                for (final v in VehicleClass.all)
                  if (_approvedVehicle == null || _approvedVehicle == v.id)
                    (
                      v.id,
                      _approvedVehicle == v.id
                          ? '${v.label} · đã duyệt'
                          : v.shortLabel,
                      switch (v.id) {
                        'ev_scooter' => GhstActionKind.eco,
                        'motorbike' => GhstActionKind.scooter,
                        _ => GhstActionKind.truck,
                      },
                    ),
              ])
                ChoiceChip(
                  key: ValueKey('driver-vehicle-${entry.$1}'),
                  showCheckmark: false,
                  avatar: GhstButtonIcon.glyph(entry.$3, size: 15),
                  label: Text(entry.$2),
                  selected: _vehicleType == entry.$1,
                  onSelected: _busy || _approvedVehicle != null
                      ? null
                      : (sel) {
                          if (sel && _vehicleType != entry.$1) {
                            unawaited(_updatePresence(vehicleType: entry.$1));
                          }
                        },
                ),
              FilterChip(
                key: const ValueKey('driver-batching-chip'),
                showCheckmark: false,
                avatar: const GhstButtonIcon.glyph(
                  GhstActionKind.hub,
                  size: 15,
                ),
                label: const Text('Ghép đơn cùng tuyến'),
                selected: _allowBatching,
                onSelected: _busy
                    ? null
                    : (sel) => unawaited(_updatePresence(allowBatching: sel)),
              ),
              OutlinedButton.icon(
                key: const ValueKey('driver-radar-poll'),
                onPressed: _busy ? null : () => _pollOffer(silent: false),
                icon: const GhstButtonIcon.glyph(GhstActionKind.gps, size: 16),
                label: Text(_busy ? 'Đang quét...' : 'Quét cuốc gần tôi'),
              ),
              if (online) ...[
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const GhstButtonIcon(Icons.gps_fixed, size: 15),
                  label: Text(
                    'GPS: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('driver-refresh-gps'),
                  onPressed: _busy
                      ? null
                      : () => _updatePresence(isOnline: true),
                  icon: const GhstButtonIcon(
                    Icons.my_location_rounded,
                    size: 16,
                  ),
                  label: const Text('Cập nhật GPS'),
                ),
              ],
            ],
          ),
          if (widget.weatherService != null ||
              EnvConfig.deliveryApiBaseUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            DeliveryWeatherStrip(
              point: GeoPoint(latitude: lat, longitude: lng),
              service: widget.weatherService,
            ),
          ],
          if (activeOffer != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF59E0B)),
              ),
              child: Row(
                children: [
                  const GhstButtonIcon.glyph(
                    GhstActionKind.bolt,
                    size: 18,
                    color: Color(0xFFB45309),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Có đề xuất cuốc ${activeOffer['tracking_code'] ?? ''} cách ${_formatDistanceKm(activeOffer['distance_to_pickup_meters'])} • Thực nhận ${_formatVnd(activeOffer['estimated_earning'])}',
                      style: const TextStyle(
                        color: Color(0xFF78350F),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('driver-reopen-offer'),
                    onPressed: () => _presentIncomingOfferDialog(activeOffer),
                    icon: const GhstButtonIcon.glyph(
                      GhstActionKind.forward,
                      size: 15,
                    ),
                    label: const Text('Mở đề xuất'),
                  ),
                ],
              ),
            ),
          ],
          if (_notice != null) ...[
            const SizedBox(height: 8),
            Text(
              _notice!,
              style: const TextStyle(
                color: Color(0xFF047857),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                color: scheme.error,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class DriverIncomingOfferDialog extends StatefulWidget {
  const DriverIncomingOfferDialog({
    super.key,
    required this.lease,
    required this.offer,
    this.isAutomatedTest = false,
  });

  final CloudSessionLease lease;
  final Map<String, dynamic> offer;
  final bool isAutomatedTest;

  @override
  State<DriverIncomingOfferDialog> createState() =>
      _DriverIncomingOfferDialogState();
}

class _DriverIncomingOfferDialogState extends State<DriverIncomingOfferDialog> {
  late int _remainingSeconds =
      ((widget.offer['remaining_seconds'] as num?)?.toInt() ?? 28).clamp(1, 28);
  bool _submitting = false;
  String? _error;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    if (!widget.isAutomatedTest) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_remainingSeconds <= 1) {
          timer.cancel();
          if (!_submitting) {
            Navigator.of(context).pop(<String, dynamic>{'expired': true});
          }
          return;
        }
        setState(() => _remainingSeconds -= 1);
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _respond(String decision) async {
    if (_submitting || !widget.lease.valid) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await widget.lease.session.service.driverDispatch(
        'respond_offer',
        {'offer_id': '${widget.offer['id'] ?? ''}', 'decision': decision},
      );
      if (!mounted) return;
      Navigator.of(context).pop(res);
    } catch (e) {
      if (!mounted || widget.lease.handleAccessFailure(e)) return;
      setState(() {
        _submitting = false;
        _error = e is PublicApiException
            ? e.message
            : 'Không gửi được phản hồi nhận cuốc.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final scheme = Theme.of(context).colorScheme;
    final progress = (_remainingSeconds / 28.0).clamp(0.0, 1.0);
    final cod = (offer['cod_amount'] as num? ?? 0).toInt();

    return AlertDialog(
      key: const ValueKey('driver-incoming-offer-dialog'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      title: Row(
        children: [
          GhstButtonIcon.ai(Icon3dStyle.scooterExpress, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đề xuất cuốc mới • Vòng ${offer['radius_tier_km'] ?? 3} km',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${offer['tracking_code'] ?? ''} • ${_serviceLabel('${offer['service_type'] ?? 'standard'}')}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _remainingSeconds <= 8
                  ? const Color(0xFFFEE2E2)
                  : const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${_remainingSeconds}s',
              key: const ValueKey('driver-offer-countdown'),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: _remainingSeconds <= 8
                    ? const Color(0xFFB91C1C)
                    : const Color(0xFF047857),
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  color: _remainingSeconds <= 8
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF10B981),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF065F46).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Thu nhập ròng tài xế (80%)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatVnd(offer['estimated_earning']),
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF047857),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Cách lấy: ${_formatDistanceKm(offer['distance_to_pickup_meters'])}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                        Text(
                          'Lộ trình: ${_formatDistanceKm(offer['order_distance_meters'])}',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _OfferRouteRow(
                icon: GhstActionKind.gps,
                label: 'Khu vực lấy hàng',
                value: '${offer['pickup_area'] ?? 'Nội thành'}',
              ),
              const SizedBox(height: 8),
              _OfferRouteRow(
                icon: GhstActionKind.mapPin,
                label: 'Khu vực giao hàng',
                value: '${offer['dropoff_area'] ?? 'Điểm nhận'}',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (cod > 0)
                    Chip(
                      avatar: const GhstButtonIcon.glyph(
                        GhstActionKind.wallet,
                        size: 14,
                      ),
                      label: Text('Ứng/Thu hộ COD ${_formatVnd(cod)}'),
                    ),
                  if (offer['require_pod'] == true)
                    const Chip(
                      avatar: GhstButtonIcon.glyph(
                        GhstActionKind.camera,
                        size: 14,
                      ),
                      label: Text('Yêu cầu ảnh POD'),
                    ),
                  if (offer['require_signature'] == true)
                    const Chip(
                      avatar: GhstButtonIcon.glyph(
                        GhstActionKind.edit,
                        size: 14,
                      ),
                      label: Text('Ký nhận điện tử'),
                    ),
                  if (offer['prefer_ev'] == true)
                    const Chip(
                      avatar: GhstButtonIcon.glyph(
                        GhstActionKind.eco,
                        size: 14,
                      ),
                      label: Text('Ưu tiên xe điện'),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton.icon(
          key: const ValueKey('driver-offer-reject'),
          onPressed: _submitting ? null : () => _respond('reject'),
          icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),
          label: const Text('Bỏ qua'),
        ),
        FilledButton.icon(
          key: const ValueKey('driver-offer-accept'),
          onPressed: _submitting ? null : () => _respond('accept'),
          icon: const GhstButtonIcon.glyph(GhstActionKind.check, size: 16),
          label: Text(_submitting ? 'Đang nhận...' : 'Nhận cuốc ngay'),
        ),
      ],
    );
  }
}

class _OfferRouteRow extends StatelessWidget {
  const _OfferRouteRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final GhstActionKind icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          GhstButtonIcon.glyph(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DriverBatchSuggestionsPanel extends StatefulWidget {
  const DriverBatchSuggestionsPanel({
    super.key,
    required this.lease,
    this.onBatchClaimed,
  });

  final CloudSessionLease lease;
  final ValueChanged<List<Map<String, dynamic>>>? onBatchClaimed;

  @override
  State<DriverBatchSuggestionsPanel> createState() =>
      _DriverBatchSuggestionsPanelState();
}

class _DriverBatchSuggestionsPanelState
    extends State<DriverBatchSuggestionsPanel> {
  List<Map<String, dynamic>> _bundles = const [];
  int _activeTripsCount = 0;
  bool _loading = true;
  bool _claiming = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBundles());
  }

  Future<void> _loadBundles() async {
    if (!widget.lease.valid) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.lease.session.service.driverDispatch(
        'batch_suggestions',
      );
      if (!mounted || !widget.lease.valid) return;
      final raw = res['bundles'];
      setState(() {
        _bundles = raw is List
            ? raw
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
            : const [];
        _activeTripsCount = (res['active_trips_count'] as num? ?? 0).toInt();
        _loading = false;
      });
    } catch (e) {
      if (!mounted || widget.lease.handleAccessFailure(e)) return;
      setState(() {
        _loading = false;
        _error = e is PublicApiException
            ? e.message
            : 'Chưa tải được gợi ý ghép đơn cùng tuyến.';
      });
    }
  }

  Future<void> _claimBundle(Map<String, dynamic> bundle) async {
    if (_claiming || !widget.lease.valid) return;
    final rawIds = bundle['order_ids'];
    final ids = rawIds is List
        ? rawIds.map((e) => '$e').where((s) => s.isNotEmpty).toList()
        : const <String>[];
    if (ids.length < 2) return;

    setState(() {
      _claiming = true;
      _error = null;
      _notice = null;
    });
    try {
      final res = await widget.lease.session.service.driverDispatch(
        'claim_batch',
        {'order_ids': ids, 'request_key': const Uuid().v4()},
      );
      if (!mounted || !widget.lease.valid) return;
      final rawOrders = res['orders'];
      final claimedOrders = rawOrders is List
          ? rawOrders
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : const <Map<String, dynamic>>[];
      setState(() {
        _claiming = false;
        _notice =
            'Đã nhận cụm ${claimedOrders.length} đơn cùng tuyến — chuyển sang Chuyến của tôi!';
      });
      await _loadBundles();
      widget.onBatchClaimed?.call(claimedOrders);
    } catch (e) {
      if (!mounted || widget.lease.handleAccessFailure(e)) return;
      setState(() {
        _claiming = false;
        _error = e is PublicApiException
            ? e.message
            : 'Không thể nhận cụm đơn ghép tuyến.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _bundles.isEmpty) {
      return const SizedBox.shrink();
    }
    if (_bundles.isEmpty && _notice == null && _error == null) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('driver-batch-suggestions-panel'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF06B6D4).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GhstButtonIcon.ai(Icon3dStyle.hub2hBatch, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gợi ý ghép đơn cùng tuyến (${_bundles.length} cụm khả dụng)',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Điểm lấy cách nhau <= 3 km & cùng hướng di chuyển (<= 55°) giúp tối ưu thu nhập chuyến.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Làm mới gợi ý ghép đơn',
                onPressed: _loading || _claiming ? null : _loadBundles,
                icon: const GhstButtonIcon.glyph(
                  GhstActionKind.refresh,
                  size: 18,
                ),
              ),
            ],
          ),
          if (_notice != null) ...[
            const SizedBox(height: 8),
            Text(
              _notice!,
              style: const TextStyle(
                color: Color(0xFF047857),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
          for (var i = 0; i < _bundles.length; i++) ...[
            const SizedBox(height: 10),
            _BundleCard(
              index: i,
              bundle: _bundles[i],
              busy: _claiming || _activeTripsCount > 0,
              onClaim: () => _claimBundle(_bundles[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _BundleCard extends StatelessWidget {
  const _BundleCard({
    required this.index,
    required this.bundle,
    required this.busy,
    required this.onClaim,
  });

  final int index;
  final Map<String, dynamic> bundle;
  final bool busy;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final codes =
        (bundle['tracking_codes'] as List?)?.map((e) => '$e').join(' + ') ??
        '2 đơn cùng tuyến';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Cụm #${index + 1}: $codes',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Thực nhận ${_formatVnd(bundle['estimated_earning'])}',
                  style: const TextStyle(
                    color: Color(0xFF047857),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Lấy hàng: ${bundle['pickup_summary'] ?? ''} (cách ${_formatDistanceKm(bundle['pickup_gap_meters'])})',
            style: const TextStyle(fontSize: 12.5),
          ),
          Text(
            'Giao hàng: ${bundle['dropoff_summary'] ?? ''} • Lệch hướng ${bundle['bearing_delta_deg'] ?? 0}°',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: ValueKey('driver-claim-batch-$index'),
              onPressed: busy ? null : onClaim,
              icon: const GhstButtonIcon.glyph(GhstActionKind.hub, size: 16),
              label: const Text('Nhận cụm 2 đơn'),
            ),
          ),
        ],
      ),
    );
  }
}
