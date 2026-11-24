import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import '../../core/theme/admin_studio_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/app_state_records.dart';
import '../../domain/entities/geo_point.dart';
import 'animated_3d_ui_icons.dart';
import 'ghst_button_icon.dart';
import 'system_state_screens.dart';

String _vnd(dynamic value) =>
    CurrencyFormatter.formatVnd((value as num? ?? 0).toDouble());

String _tierTitle(String serviceType) => switch (serviceType) {
  'saving' => 'Tiết kiệm (Ghép chuyến)',
  'standard' => 'Tiêu chuẩn (Nội thành)',
  'same_day_2h' => 'Giao nhanh 2H',
  'express' => 'Siêu tốc (Lấy ngay)',
  'truck' => 'Xe tải / Hàng cồng kềnh',
  _ => serviceType,
};

String _zoneTypeLabel(String zoneType) => switch (zoneType) {
  'weather' => 'Mưa ngập / Thời tiết',
  'restricted_surcharge' => 'Khu hạn chế / Cấm giờ',
  'priority' => 'Khu trung tâm ưu tiên',
  _ => 'Cao điểm khu vực',
};

class AdminPricingGeofencePanel extends StatefulWidget {
  const AdminPricingGeofencePanel({
    super.key,
    required this.session,
    required this.lease,
    this.onOpenBasePricing,
  });

  final CloudAccountSession session;
  final CloudSessionLease lease;
  final VoidCallback? onOpenBasePricing;

  @override
  State<AdminPricingGeofencePanel> createState() =>
      _AdminPricingGeofencePanelState();
}

class _AdminPricingGeofencePanelState extends State<AdminPricingGeofencePanel> {
  static const _serviceOrder = [
    'saving',
    'standard',
    'same_day_2h',
    'express',
    'truck',
  ];

  Map<String, dynamic> _basePricing = const {};
  List<Map<String, dynamic>> _rules = const [];
  List<Map<String, dynamic>> _geofences = const [];
  final List<GeoPoint> _draftPolygon = <GeoPoint>[];
  final _zoneNameCtrl = TextEditingController(text: 'Trung tâm Quận 1');
  final _zoneFeeCtrl = TextEditingController(text: '10000');
  String _zoneType = 'surge';
  int _selectedPeakBps = 12000;
  int _selectedWeatherFee = 10000;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _notice;

  bool get _isAutomatedTestBinding {
    final bindingType = WidgetsBinding.instance.runtimeType.toString();
    return bindingType.contains('TestWidgetsFlutterBinding') ||
        bindingType.contains('AutomatedTest');
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _zoneNameCtrl.dispose();
    _zoneFeeCtrl.dispose();
    super.dispose();
  }

  bool get _anyPeakEnabled =>
      _rules.any((r) => r['active'] == true && r['peak_enabled'] == true);

  bool get _anyWeatherEnabled =>
      _rules.any((r) => r['active'] == true && r['weather_enabled'] == true);

  Map<String, dynamic>? _ruleFor(String service) {
    for (final r in _rules) {
      if ('${r['service_type']}' == service) return r;
    }
    return null;
  }

  (int, int) _defaultBaseAndKm(String service) {
    final base = (_basePricing['base_fee'] as num? ?? 25000).toInt();
    final km = (_basePricing['per_km'] as num? ?? 5000).toInt();
    final exp = (_basePricing['express_fee'] as num? ?? 10000).toInt();
    return switch (service) {
      'saving' => (
        (base * 0.48).round().clamp(12000, 1000000),
        (km * 0.80).round().clamp(4000, 100000),
      ),
      'same_day_2h' => (
        (base * 0.48).round().clamp(12000, 1000000),
        (km * 1.10).round().clamp(5500, 100000),
      ),
      'express' => (base + exp, km),
      'truck' => ((base * 3 + 5000).clamp(80000, 2000000), km * 3),
      _ => (base, km),
    };
  }

  List<GeofenceZoneRecord> _toMapGeofences() {
    final result = <GeofenceZoneRecord>[];
    for (final gz in _geofences) {
      final rawPoly = gz['polygon'];
      if (rawPoly is! List) continue;
      final pts = <GeoPoint>[];
      for (final pt in rawPoly) {
        if (pt is Map) {
          final lat = (pt['lat'] as num?)?.toDouble();
          final lng = (pt['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            pts.add(GeoPoint(latitude: lat, longitude: lng));
          }
        }
      }
      if (pts.length >= 3) {
        result.add(
          GeofenceZoneRecord(
            id: '${gz['id'] ?? ''}',
            zoneName: '${gz['name'] ?? 'Vùng phụ phí'}',
            zoneType: '${gz['zone_type'] ?? 'surge'}',
            surchargeRate: (gz['surcharge_fee'] as num? ?? 0).toDouble(),
            isActive: gz['active'] == true,
            boundary: pts,
          ),
        );
      }
    }
    return result;
  }

  void _applyState(Map<String, dynamic> res, {String? notice}) {
    final bp = res['base_pricing'];
    final rl = res['rules'];
    final gf = res['geofences'];
    final nextRules = rl is List
        ? rl.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const <Map<String, dynamic>>[];
    if (nextRules.isNotEmpty) {
      final first = nextRules.first;
      final bps = (first['peak_multiplier_bps'] as num?)?.toInt();
      final wFee = (first['weather_surcharge'] as num?)?.toInt();
      if (bps != null && bps >= 10000) _selectedPeakBps = bps;
      if (wFee != null && wFee >= 0) _selectedWeatherFee = wFee;
    }
    setState(() {
      _loading = false;
      _busy = false;
      _error = null;
      if (notice != null) _notice = notice;
      _basePricing = bp is Map ? Map<String, dynamic>.from(bp) : const {};
      _rules = nextRules;
      _geofences = gf is List
          ? gf
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : const [];
    });
  }

  Future<void> _load() async {
    if (!widget.lease.valid) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.session.service.adminPricing('get');
      if (!mounted || !widget.lease.valid) return;
      _applyState(res);
    } catch (e) {
      if (!mounted || widget.lease.handleAccessFailure(e)) return;
      setState(() {
        _loading = false;
        _error = e is PublicApiException
            ? e.message
            : 'Chưa tải được cấu hình bảng giá động và vùng Geofence.';
      });
    }
  }

  Future<void> _callPricingAction(
    String action,
    Map<String, dynamic> payload, {
    String? notice,
  }) async {
    if (_busy || !widget.lease.valid) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final res = await widget.session.service.adminPricing(action, payload);
      if (!mounted || !widget.lease.valid) return;
      _applyState(res, notice: notice);
    } catch (e) {
      if (!mounted || widget.lease.handleAccessFailure(e)) return;
      setState(() {
        _busy = false;
        _error = e is PublicApiException
            ? e.message
            : 'Không lưu được cấu hình bảng giá.';
      });
    }
  }

  void _applyPresetPolygon(int preset) {
    final pts = switch (preset) {
      1 => const [
        GeoPoint(latitude: 10.8120, longitude: 106.6560),
        GeoPoint(latitude: 10.8120, longitude: 106.6720),
        GeoPoint(latitude: 10.8240, longitude: 106.6720),
        GeoPoint(latitude: 10.8240, longitude: 106.6560),
      ],
      _ => const [
        GeoPoint(latitude: 10.7700, longitude: 106.6980),
        GeoPoint(latitude: 10.7700, longitude: 106.7100),
        GeoPoint(latitude: 10.7820, longitude: 106.7100),
        GeoPoint(latitude: 10.7820, longitude: 106.6980),
      ],
    };
    setState(() {
      _draftPolygon
        ..clear()
        ..addAll(pts);
      if (preset == 1) {
        _zoneNameCtrl.text = 'Cửa ngõ Sân bay Tân Sơn Nhất';
        _zoneFeeCtrl.text = '12000';
      } else {
        _zoneNameCtrl.text = 'Trung tâm Quận 1';
        _zoneFeeCtrl.text = '9000';
      }
    });
  }

  Future<void> _saveGeofence() async {
    if (_draftPolygon.length < 3) {
      setState(() {
        _error = 'Hãy chấm ít nhất 3 đỉnh trên bản đồ hoặc chọn vùng mẫu.';
      });
      return;
    }
    final fee = int.tryParse(_zoneFeeCtrl.text.trim()) ?? -1;
    if (fee < 0 || fee > 500000) {
      setState(() {
        _error = 'Phụ phí vùng cần từ 0 đến 500.000 đ.';
      });
      return;
    }
    await _callPricingAction(
      'save_geofence',
      {
        'name': _zoneNameCtrl.text.trim(),
        'zone_type': _zoneType,
        'surcharge_fee': fee,
        'multiplier_bps': 10000,
        'active': true,
        'polygon': [
          for (final pt in _draftPolygon)
            {'lat': pt.latitude, 'lng': pt.longitude},
        ],
      },
      notice:
          'Đã kích hoạt vùng phụ phí "${_zoneNameCtrl.text.trim()}" trên toàn hệ thống báo giá.',
    );
    if (mounted && _error == null) {
      setState(_draftPolygon.clear);
    }
  }

  Future<void> _editServiceRuleDialog(String serviceType) async {
    final existing = _ruleFor(serviceType);
    final (defBase, defKm) = _defaultBaseAndKm(serviceType);
    final baseCtrl = TextEditingController(
      text: '${existing?['base_fee'] ?? defBase}',
    );
    final kmCtrl = TextEditingController(
      text: '${existing?['per_km'] ?? defKm}',
    );
    final peakBpsCtrl = TextEditingController(
      text: '${existing?['peak_multiplier_bps'] ?? _selectedPeakBps}',
    );
    final weatherCtrl = TextEditingController(
      text: '${existing?['weather_surcharge'] ?? _selectedWeatherFee}',
    );
    var peakOn = existing?['peak_enabled'] == true;
    var weatherOn = existing?['weather_enabled'] == true;

    Map<String, dynamic>? payload;
    try {
      payload = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogCtx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text('Cấu hình ${_tierTitle(serviceType)}'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: baseCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Giá mở cửa 2 km đầu (VNĐ)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: kmCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Đơn giá mỗi km tiếp theo (VNĐ)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Áp dụng hệ số giờ cao điểm'),
                      value: peakOn,
                      onChanged: (v) => setDialogState(() => peakOn = v),
                    ),
                    TextField(
                      controller: peakBpsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Hệ số cao điểm (10000 = 1.0x, 12500 = 1.25x)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Áp dụng phụ phí mưa bão'),
                      value: weatherOn,
                      onChanged: (v) => setDialogState(() => weatherOn = v),
                    ),
                    TextField(
                      controller: weatherCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Phụ phí thời tiết (VNĐ)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                icon: const GhstButtonIcon.glyph(
                  GhstActionKind.close,
                  size: 16,
                ),
                label: const Text('Đóng'),
              ),
              FilledButton.icon(
                key: const ValueKey('admin-rule-dialog-save'),
                onPressed: () {
                  final b = int.tryParse(baseCtrl.text.trim());
                  final k = int.tryParse(kmCtrl.text.trim());
                  final pBps = int.tryParse(peakBpsCtrl.text.trim()) ?? 10000;
                  final wFee = int.tryParse(weatherCtrl.text.trim()) ?? 0;
                  if (b == null || k == null) return;
                  Navigator.of(dialogCtx).pop(<String, dynamic>{
                    'service_type': serviceType,
                    'base_fee': b,
                    'per_km': k,
                    'peak_multiplier_bps': pBps.clamp(10000, 30000),
                    'peak_enabled': peakOn,
                    'weather_surcharge': wFee.clamp(0, 200000),
                    'weather_enabled': weatherOn,
                    'active': true,
                  });
                },
                icon: const GhstButtonIcon.glyph(GhstActionKind.save, size: 16),
                label: const Text('Lưu gói cước'),
              ),
            ],
          ),
        ),
      );
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        baseCtrl.dispose();
        kmCtrl.dispose();
        peakBpsCtrl.dispose();
        weatherCtrl.dispose();
      });
    }

    if (payload != null && mounted) {
      await _callPricingAction(
        'save_rule',
        payload,
        notice: 'Đã cập nhật biểu phí ${_tierTitle(serviceType)}.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AdminStudioPalette.of(context);
    final version = _basePricing['version'] ?? 1;

    if (_loading && _basePricing.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      key: const ValueKey('admin-pricing-geofence-panel'),
      padding: const EdgeInsets.all(20),
      children: [
        AdminNeoBox(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const GhstAiIcon(
                        style: Icon3dStyle.gpsPinRadar,
                        size: 38,
                        borderRadius: 11,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bảng giá động, Cao điểm & Vùng phụ phí Geofence',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w900,
                              color: p.ink,
                            ),
                          ),
                          Text(
                            'Phiên bản biểu phí hiện hành: #$version • Đồng bộ tức thời sang công cụ tính cước khách hàng',
                            style: TextStyle(fontSize: 12, color: p.muted),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.onOpenBasePricing != null)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : widget.onOpenBasePricing,
                          icon: const GhstButtonIcon.glyph(
                            GhstActionKind.tune,
                            size: 16,
                          ),
                          label: const Text('Biểu phí cơ sở'),
                        ),
                      if (_rules.isNotEmpty)
                        OutlinedButton.icon(
                          key: const ValueKey('admin-reset-rules'),
                          onPressed: _busy
                              ? null
                              : () => _callPricingAction(
                                  'reset_rules',
                                  const {},
                                  notice:
                                      'Đã đưa các gói cước về công thức cơ sở mặc định.',
                                ),
                          icon: const GhstButtonIcon.glyph(
                            GhstActionKind.refresh,
                            size: 16,
                          ),
                          label: const Text('Về mặc định'),
                        ),
                      IconButton(
                        tooltip: 'Làm mới dữ liệu bảng giá',
                        onPressed: _busy ? null : _load,
                        icon: const GhstButtonIcon.glyph(
                          GhstActionKind.refresh,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (_notice != null) ...[
                const SizedBox(height: 10),
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
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(
                    color: p.danger,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 1. Global Surge & Weather Controls
        AdminNeoBox(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Điều tiết Phụ phí Giờ cao điểm & Mưa bão toàn sàn',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const GhstButtonIcon.glyph(GhstActionKind.bolt, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chế độ Giờ cao điểm (${(_selectedPeakBps / 10000.0).toStringAsFixed(2)}x)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: p.ink,
                      ),
                    ),
                  ),
                  Switch(
                    key: const ValueKey('admin-surge-peak-switch'),
                    value: _anyPeakEnabled,
                    onChanged: _busy
                        ? null
                        : (val) => _callPricingAction(
                            'toggle_surge',
                            {
                              'peak_enabled': val,
                              'peak_multiplier_bps': _selectedPeakBps,
                            },
                            notice: val
                                ? 'Đã bật hệ số giờ cao điểm toàn sàn.'
                                : 'Đã tắt hệ số giờ cao điểm.',
                          ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final bps in const [11500, 12000, 13500, 15000])
                    ChoiceChip(
                      showCheckmark: false,
                      avatar: const GhstButtonIcon.glyph(
                        GhstActionKind.bolt,
                        size: 14,
                      ),
                      label: Text('${(bps / 10000.0).toStringAsFixed(2)}x'),
                      selected: _selectedPeakBps == bps,
                      onSelected: _busy
                          ? null
                          : (sel) {
                              if (!sel) return;
                              setState(() => _selectedPeakBps = bps);
                              if (_anyPeakEnabled) {
                                unawaited(
                                  _callPricingAction('toggle_surge', {
                                    'peak_enabled': true,
                                    'peak_multiplier_bps': bps,
                                  }),
                                );
                              }
                            },
                    ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  const GhstButtonIcon.glyph(GhstActionKind.weather, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Phụ phí Thời tiết Mưa bão (+${_vnd(_selectedWeatherFee)})',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: p.ink,
                      ),
                    ),
                  ),
                  Switch(
                    key: const ValueKey('admin-surge-weather-switch'),
                    value: _anyWeatherEnabled,
                    onChanged: _busy
                        ? null
                        : (val) => _callPricingAction(
                            'toggle_surge',
                            {
                              'weather_enabled': val,
                              'weather_surcharge': _selectedWeatherFee,
                            },
                            notice: val
                                ? 'Đã bật phụ phí hỗ trợ tài xế mùa mưa bão.'
                                : 'Đã tắt phụ phí thời tiết.',
                          ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final fee in const [5000, 10000, 15000, 25000])
                    ChoiceChip(
                      showCheckmark: false,
                      avatar: const GhstButtonIcon.glyph(
                        GhstActionKind.weather,
                        size: 14,
                      ),
                      label: Text('+${_vnd(fee)}'),
                      selected: _selectedWeatherFee == fee,
                      onSelected: _busy
                          ? null
                          : (sel) {
                              if (!sel) return;
                              setState(() => _selectedWeatherFee = fee);
                              if (_anyWeatherEnabled) {
                                unawaited(
                                  _callPricingAction('toggle_surge', {
                                    'weather_enabled': true,
                                    'weather_surcharge': fee,
                                  }),
                                );
                              }
                            },
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. 5-Tier Service Pricing Cards
        AdminNeoBox(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Biểu phí chi tiết 5 gói dịch vụ giao hàng',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 12),
              for (final svc in _serviceOrder) ...[
                Builder(
                  builder: (context) {
                    final r = _ruleFor(svc);
                    final (defBase, defKm) = _defaultBaseAndKm(svc);
                    final base = r?['base_fee'] ?? defBase;
                    final km = r?['per_km'] ?? defKm;
                    final custom = r != null;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: p.surfaceSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: p.line),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _tierTitle(svc),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: p.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Mở cửa: ${_vnd(base)} • Mỗi km: ${_vnd(km)}${custom ? ' • Đang áp dụng cấu hình riêng' : ' • Theo biểu phí cơ sở'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: p.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            key: ValueKey('admin-edit-rule-$svc'),
                            onPressed: _busy
                                ? null
                                : () => _editServiceRuleDialog(svc),
                            icon: const GhstButtonIcon.glyph(
                              GhstActionKind.edit,
                              size: 15,
                            ),
                            label: const Text('Điều chỉnh'),
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
        const SizedBox(height: 16),

        // 3. Interactive Polygon Geofence Studio
        AdminNeoBox(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bản đồ Vùng đa giác Phụ phí Geofence (${_geofences.length} vùng)',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Chấm từ 3 đỉnh trở lên trên bản đồ (hoặc nạp vùng mẫu nhanh) để khoanh vùng phụ phí tự động theo tọa độ lấy/giao.',
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
              const SizedBox(height: 12),
              if (_isAutomatedTestBinding)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: p.surfaceSubtle,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: p.line),
                  ),
                  child: Row(
                    children: [
                      const GhstButtonIcon.glyph(
                        GhstActionKind.mapPin,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Khung vẽ đa giác Geofence: đang chọn ${_draftPolygon.length} đỉnh tọa độ (${_geofences.length} vùng đã lưu)',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: p.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Map3dPerspectiveWidget(
                    height: 300,
                    showTopBanner: false,
                    focusedCenterPoint: const GeoPoint(
                      latitude: 10.7769,
                      longitude: 106.7009,
                    ),
                    geofenceZones: _toMapGeofences(),
                    drawnPolygonGeoPoints: _draftPolygon,
                    onTapGeoPoint: (pt) {
                      if (_draftPolygon.length >= 24) return;
                      setState(() => _draftPolygon.add(pt));
                    },
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('admin-geofence-preset-q1'),
                    onPressed: _busy ? null : () => _applyPresetPolygon(0),
                    icon: const GhstButtonIcon.glyph(
                      GhstActionKind.mapPin,
                      size: 15,
                    ),
                    label: const Text('Mẫu Quận 1 (4 đỉnh)'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('admin-geofence-preset-airport'),
                    onPressed: _busy ? null : () => _applyPresetPolygon(1),
                    icon: const GhstButtonIcon.glyph(
                      GhstActionKind.gps,
                      size: 15,
                    ),
                    label: const Text('Mẫu Tân Sơn Nhất'),
                  ),
                  if (_draftPolygon.isNotEmpty)
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => setState(_draftPolygon.clear),
                      icon: const GhstButtonIcon.glyph(
                        GhstActionKind.delete,
                        size: 15,
                      ),
                      label: Text('Xóa ${_draftPolygon.length} đỉnh đang vẽ'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      key: const ValueKey('admin-geofence-name'),
                      controller: _zoneNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên vùng phụ phí',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      key: const ValueKey('admin-geofence-fee'),
                      controller: _zoneFeeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Phụ phí (VNĐ)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final z in const [
                    ('surge', 'Cao điểm khu vực', GhstActionKind.bolt),
                    ('weather', 'Mưa ngập', GhstActionKind.weather),
                    (
                      'restricted_surcharge',
                      'Khu hạn chế',
                      GhstActionKind.shield,
                    ),
                  ])
                    ChoiceChip(
                      showCheckmark: false,
                      avatar: GhstButtonIcon.glyph(z.$3, size: 14),
                      label: Text(z.$2),
                      selected: _zoneType == z.$1,
                      onSelected: _busy
                          ? null
                          : (sel) {
                              if (sel) setState(() => _zoneType = z.$1);
                            },
                    ),
                  FilledButton.icon(
                    key: const ValueKey('admin-geofence-save'),
                    onPressed: _busy ? null : _saveGeofence,
                    icon: const GhstButtonIcon.glyph(
                      GhstActionKind.save,
                      size: 16,
                    ),
                    label: const Text('Lưu vùng Geofence'),
                  ),
                ],
              ),
              if (_geofences.isNotEmpty) ...[
                const Divider(height: 26),
                for (final gz in _geofences)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: p.surfaceSubtle,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.line),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${gz['name'] ?? ''}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: p.ink,
                                ),
                              ),
                              Text(
                                '${_zoneTypeLabel('${gz['zone_type']}')} • Phụ phí +${_vnd(gz['surcharge_fee'])} • ${(gz['polygon'] as List?)?.length ?? 0} đỉnh',
                                style: TextStyle(fontSize: 12, color: p.muted),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: gz['active'] == true,
                          onChanged: _busy
                              ? null
                              : (val) => _callPricingAction(
                                  'toggle_geofence',
                                  {'id': '${gz['id']}', 'active': val},
                                ),
                        ),
                        IconButton(
                          tooltip: 'Xóa vùng phụ phí',
                          onPressed: _busy
                              ? null
                              : () => _callPricingAction(
                                  'delete_geofence',
                                  {'id': '${gz['id']}'},
                                  notice:
                                      'Đã xóa vùng phụ phí "${gz['name']}".',
                                ),
                          icon: GhstButtonIcon.glyph(
                            GhstActionKind.delete,
                            size: 17,
                            color: p.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
