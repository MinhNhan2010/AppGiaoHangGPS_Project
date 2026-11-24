import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_orders_service.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import '../../core/theme/ghst_theme_tokens.dart';
import '../../domain/entities/vehicle_class.dart';
import '../widgets/cloud_session_boundary.dart';
import '../widgets/ghst_button_icon.dart';

/// KYC documents required from a driver partner, in display order.
const driverDocumentKinds = <String, String>{
  'citizen_front': 'CCCD mặt trước',
  'citizen_back': 'CCCD mặt sau',
  'license': 'Giấy phép lái xe',
  'vehicle_registration': 'Cà vẹt xe (đăng ký xe)',
  'portrait': 'Ảnh chân dung',
};

const driverApplicationStates = <String, String>{
  'pending': 'Đang chờ duyệt',
  'approved': 'Đã được duyệt',
  'rejected': 'Chưa được duyệt',
};

final _platePattern = RegExp(
  r'^[0-9]{2}[A-Z]{1,2}[0-9]?-?([0-9]{3}\.?[0-9]{2}|[0-9]{4})$',
);

String normalizeLicensePlate(String raw) =>
    raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');

bool isValidLicensePlate(String raw) =>
    _platePattern.hasMatch(normalizeLicensePlate(raw));

Future<void> openDriverPartnerApplication(
  BuildContext context,
  CloudAccountSession session,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => CloudSessionBoundary(
      session: session,
      builder: (_, lease) => Scaffold(
        appBar: AppBar(title: const Text('Đăng ký tài xế đối tác')),
        body: SafeArea(
          child: DriverPartnerApplicationScreen(session: session, lease: lease),
        ),
      ),
    ),
  ),
);

/// Driver partner registration: vehicle, licence, operating area and KYC
/// photos. Submitting creates a pending `driver` membership for operators.
class DriverPartnerApplicationScreen extends StatefulWidget {
  const DriverPartnerApplicationScreen({
    super.key,
    required this.session,
    this.lease,
    this.pickImage,
  });

  final CloudAccountSession session;
  final CloudSessionLease? lease;

  /// Test hook replacing the platform file picker.
  final Future<Uint8List?> Function(String kind)? pickImage;

  @override
  State<DriverPartnerApplicationScreen> createState() =>
      _DriverPartnerApplicationScreenState();
}

class _DriverPartnerApplicationScreenState
    extends State<DriverPartnerApplicationScreen> {
  final _form = GlobalKey<FormState>();
  final _plate = TextEditingController();
  final _brand = TextEditingController();
  final _color = TextEditingController();
  final _license = TextEditingController();
  final _area = TextEditingController();
  late final _scope = widget.session.service.identityScope;

  VehicleClass _vehicle = VehicleClass.motorbike;
  String? _licenseClass;
  final _documents = <String, String>{};
  final _previews = <String, Uint8List>{};
  final _uploading = <String>{};
  Map<String, dynamic>? _application;
  bool _loading = true, _submitting = false, _editing = false;
  String? _error, _notice;

  CloudOrdersService get _service => widget.session.service;

  bool get _valid =>
      mounted &&
      widget.session.canUseBusiness &&
      _service.identityScope == _scope &&
      (widget.lease?.valid ?? true);

  String? get _state => _application?['state'] as String?;

  bool get _showForm =>
      _application == null || (_state == 'rejected' && _editing);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_plate, _brand, _color, _license, _area]) {
      c.dispose();
    }
    super.dispose();
  }

  String _message(Object error, String fallback) =>
      error is PublicApiException ? error.message : fallback;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _service.driverApplication('get');
      if (!_valid) return;
      final app = res['application'];
      setState(() {
        _application = app is Map ? Map<String, dynamic>.from(app) : null;
        _loading = false;
      });
      if (_application != null) _prefill(_application!);
    } catch (e) {
      if (!_valid || (widget.lease?.handleAccessFailure(e) ?? false)) return;
      setState(() {
        _loading = false;
        _error = _message(e, 'Chưa tải được hồ sơ đối tác.');
      });
    }
  }

  void _prefill(Map<String, dynamic> app) {
    _vehicle = VehicleClass.byId(app['vehicle_type']);
    _plate.text = '${app['license_plate'] ?? ''}';
    _brand.text = '${app['vehicle_brand'] ?? ''}';
    _color.text = '${app['vehicle_color'] ?? ''}';
    _license.text = '${app['license_number'] ?? ''}';
    _area.text = '${app['operating_area'] ?? ''}';
    final cls = '${app['license_class'] ?? ''}';
    _licenseClass = _vehicle.acceptsLicense(cls) ? cls : null;
    final docs = app['documents'];
    if (docs is Map) {
      _documents
        ..clear()
        ..addAll({
          for (final e in docs.entries)
            if (e.value is String && driverDocumentKinds.containsKey(e.key))
              '${e.key}': e.value as String,
        });
    }
  }

  Future<Uint8List?> _pick(String kind) async {
    if (widget.pickImage != null) return widget.pickImage!(kind);
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Ảnh giấy tờ',
          extensions: ['jpg', 'jpeg', 'png', 'webp'],
        ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > 5000000) {
      throw const PublicApiException('Ảnh tối đa 5 MB.');
    }
    return file.readAsBytes();
  }

  Future<void> _upload(String kind) async {
    if (_uploading.contains(kind) || _submitting) return;
    setState(() => _error = null);
    try {
      final bytes = await _pick(kind);
      if (bytes == null || !_valid) return;
      if (bytes.length > 5000000) {
        throw const PublicApiException('Ảnh tối đa 5 MB.');
      }
      if (CloudOrdersService.imageContentType(bytes) == null) {
        throw const PublicApiException('Chỉ nhận ảnh JPG, PNG hoặc WEBP.');
      }
      setState(() => _uploading.add(kind));
      final path = await _service.uploadDriverDocument(
        kind: kind,
        bytes: bytes,
      );
      if (!_valid) return;
      setState(() {
        _documents[kind] = path;
        _previews[kind] = bytes;
      });
    } catch (e) {
      if (!_valid || (widget.lease?.handleAccessFailure(e) ?? false)) return;
      setState(() => _error = _message(e, 'Chưa tải được ảnh giấy tờ.'));
    } finally {
      if (mounted) setState(() => _uploading.remove(kind));
    }
  }

  Future<void> _submit() async {
    if (_submitting || !_form.currentState!.validate()) return;
    final missing = driverDocumentKinds.keys
        .where((k) => !_documents.containsKey(k))
        .map((k) => driverDocumentKinds[k])
        .toList();
    if (missing.isNotEmpty) {
      setState(() => _error = 'Vui lòng tải đủ ảnh: ${missing.join(', ')}.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await _service.driverApplication('submit', {
        'vehicle_type': _vehicle.id,
        'license_plate': normalizeLicensePlate(_plate.text),
        'vehicle_brand': _brand.text.trim(),
        'vehicle_color': _color.text.trim(),
        'license_number': _license.text.trim(),
        'license_class': _licenseClass,
        'operating_area': _area.text.trim(),
        'documents': Map<String, String>.from(_documents),
      });
      if (!_valid) return;
      final app = res['application'];
      setState(() {
        _application = app is Map
            ? Map<String, dynamic>.from(app)
            : {..._application ?? {}, 'state': 'pending'};
        _editing = false;
        _notice = 'Đã gửi hồ sơ. Quản trị viên sẽ xét duyệt sớm.';
      });
      await widget.session.refresh().catchError((Object _) {});
    } catch (e) {
      if (!_valid || (widget.lease?.handleAccessFailure(e) ?? false)) return;
      setState(() => _error = _message(e, 'Chưa gửi được hồ sơ đối tác.'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_application != null && !_showForm)
                    _statusCard(tokens)
                  else if (widget.session.hasRole('driver') &&
                      _application == null)
                    _infoCard(
                      tokens,
                      'Bạn đã là tài xế đối tác',
                      'Tài khoản đã được cấp quyền tài xế. Bạn có thể bổ sung hồ sơ phương tiện bên dưới.',
                    ),
                  if (_notice != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _notice!,
                      key: const ValueKey('driver-app-notice'),
                      style: TextStyle(
                        color: tokens.emerald.foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (_showForm) _formBody(tokens),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      key: const ValueKey('driver-app-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _infoCard(GhstThemeTokens tokens, String title, String body) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(body),
        ],
      ),
    ),
  );

  Widget _statusCard(GhstThemeTokens tokens) {
    final app = _application!;
    final state = _state ?? 'pending';
    final tone = switch (state) {
      'approved' => tokens.emerald,
      'rejected' => tokens.rose,
      _ => tokens.amber,
    };
    final reason = '${app['reason'] ?? ''}'.trim();
    final vehicle = VehicleClass.byId(app['vehicle_type']);
    return Card(
      key: const ValueKey('driver-app-status'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: tone.fill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: tone.border),
              ),
              child: Text(
                driverApplicationStates[state] ?? state,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: tone.foreground,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _row('Loại xe', vehicle.label),
            _row('Biển số', '${app['license_plate'] ?? ''}'),
            _row(
              'Xe',
              '${app['vehicle_brand'] ?? ''} · ${app['vehicle_color'] ?? ''}',
            ),
            _row(
              'GPLX',
              'Hạng ${app['license_class'] ?? ''} · ${app['license_number'] ?? ''}',
            ),
            _row('Khu vực', '${app['operating_area'] ?? ''}'),
            if (state == 'pending')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Hồ sơ đang được quản trị viên kiểm tra. Bạn sẽ nhận thông báo khi có kết quả.',
                ),
              ),
            if (state == 'approved')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Bạn có thể chuyển sang vai trò "Đối tác Tài xế" để bật nhận chuyến.',
                ),
              ),
            if (state == 'rejected') ...[
              if (reason.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Lý do: $reason',
                    style: TextStyle(
                      color: tokens.rose.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const ValueKey('driver-app-edit'),
                onPressed: () => setState(() {
                  _editing = true;
                  _notice = null;
                }),
                icon: const GhstButtonIcon(Icons.edit_outlined, size: 16),
                label: const Text('Sửa và gửi lại hồ sơ'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );

  Widget _formBody(GhstThemeTokens tokens) {
    final enabled = !_submitting;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(
            '1. Phương tiện',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: tokens.ink,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in VehicleClass.all)
                ChoiceChip(
                  key: ValueKey('apply-vehicle-${v.id}'),
                  label: Text('${v.label} · ${v.maxKg} kg'),
                  selected: v == _vehicle,
                  onSelected: enabled
                      ? (_) => setState(() {
                          _vehicle = v;
                          if (_licenseClass != null &&
                              !v.acceptsLicense(_licenseClass!)) {
                            _licenseClass = null;
                          }
                        })
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('driver-plate'),
            controller: _plate,
            enabled: enabled,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Biển số xe',
              hintText: 'VD: 59X1-123.45 hoặc 51C-123.45',
              border: OutlineInputBorder(),
            ),
            validator: (v) => isValidLicensePlate(v ?? '')
                ? null
                : 'Biển số không hợp lệ (VD: 59X1-123.45)',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('driver-brand'),
                  controller: _brand,
                  enabled: enabled,
                  decoration: const InputDecoration(
                    labelText: 'Hãng / dòng xe',
                    hintText: 'VD: Honda Wave',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    return t.length < 2 || t.length > 60
                        ? 'Nhập 2–60 ký tự'
                        : null;
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('driver-color'),
                  controller: _color,
                  enabled: enabled,
                  decoration: const InputDecoration(
                    labelText: 'Màu xe',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    return t.length < 2 || t.length > 30
                        ? 'Nhập 2–30 ký tự'
                        : null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '2. Giấy phép lái xe & khu vực',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: tokens.ink,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  key: const ValueKey('driver-license'),
                  controller: _license,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  maxLength: 12,
                  decoration: const InputDecoration(
                    labelText: 'Số GPLX (12 số)',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  validator: (v) =>
                      RegExp(r'^\d{12}$').hasMatch((v ?? '').trim())
                      ? null
                      : 'Số GPLX gồm 12 chữ số',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('driver-license-class-${_vehicle.id}'),
                  initialValue: _licenseClass,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Hạng GPLX',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final c in _vehicle.licenseClasses)
                      DropdownMenuItem(value: c, child: Text('Hạng $c')),
                  ],
                  onChanged: enabled
                      ? (v) => setState(() => _licenseClass = v)
                      : null,
                  validator: (v) =>
                      v == null ? 'Chọn hạng phù hợp ${_vehicle.label}' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('driver-area'),
            controller: _area,
            enabled: enabled,
            decoration: const InputDecoration(
              labelText: 'Khu vực hoạt động',
              hintText: 'VD: TP.HCM - Quận 1, 3, 10',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              return t.length < 2 || t.length > 120 ? 'Nhập 2–120 ký tự' : null;
            },
          ),
          const SizedBox(height: 16),
          Text(
            '3. Ảnh giấy tờ (JPG/PNG/WEBP, tối đa 5 MB)',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: tokens.ink,
            ),
          ),
          const SizedBox(height: 8),
          for (final entry in driverDocumentKinds.entries)
            _documentTile(tokens, entry.key, entry.value),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('driver-app-submit'),
            onPressed: enabled && _uploading.isEmpty ? _submit : null,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const GhstButtonIcon(Icons.send_rounded, size: 16),
            label: Text(
              _submitting ? 'Đang gửi hồ sơ...' : 'Gửi hồ sơ đăng ký',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Ảnh giấy tờ được lưu riêng tư, chỉ quản trị viên xét duyệt mới xem được.',
            style: TextStyle(fontSize: 12, color: tokens.inkSecondary),
          ),
        ],
      ),
    );
  }

  Widget _documentTile(GhstThemeTokens tokens, String kind, String label) {
    final done = _documents.containsKey(kind);
    final busy = _uploading.contains(kind);
    final preview = _previews[kind];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        key: ValueKey('driver-doc-$kind'),
        leading: preview != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(
                  preview,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const GhstButtonIcon(Icons.image_outlined),
                ),
              )
            : GhstButtonIcon(
                done ? Icons.check_circle_rounded : Icons.badge_outlined,
                color: done ? tokens.emerald.foreground : null,
              ),
        title: Text(label),
        subtitle: Text(done ? 'Đã tải lên' : 'Chưa có ảnh'),
        trailing: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                key: ValueKey('driver-doc-pick-$kind'),
                onPressed: _submitting ? null : () => _upload(kind),
                child: Text(done ? 'Đổi ảnh' : 'Chọn ảnh'),
              ),
      ),
    );
  }
}

/// Operator review dialog showing a driver's application and KYC photos.
Future<void> showDriverApplicationReview(
  BuildContext context, {
  required CloudOrdersService service,
  required String userId,
  String? displayName,
}) => showDialog<void>(
  context: context,
  builder: (_) => _DriverApplicationReviewDialog(
    service: service,
    userId: userId,
    displayName: displayName,
  ),
);

class _DriverApplicationReviewDialog extends StatefulWidget {
  const _DriverApplicationReviewDialog({
    required this.service,
    required this.userId,
    this.displayName,
  });
  final CloudOrdersService service;
  final String userId;
  final String? displayName;

  @override
  State<_DriverApplicationReviewDialog> createState() =>
      _DriverApplicationReviewDialogState();
}

class _DriverApplicationReviewDialogState
    extends State<_DriverApplicationReviewDialog> {
  Map<String, dynamic>? _app;
  Map<String, String> _urls = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.service.driverApplication('admin_get', {
        'user_id': widget.userId,
      });
      if (!mounted) return;
      final app = res['application'];
      final urls = res['document_urls'];
      setState(() {
        _app = app is Map ? Map<String, dynamic>.from(app) : null;
        _urls = urls is Map
            ? {
                for (final e in urls.entries)
                  if (e.value is String) '${e.key}': e.value as String,
              }
            : const {};
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is PublicApiException
            ? e.message
            : 'Chưa tải được hồ sơ tài xế.';
      });
    }
  }

  Widget _image(String url) {
    Widget broken() => const SizedBox(
      height: 120,
      child: Center(child: Text('Không hiển thị được ảnh')),
    );
    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      try {
        return Image.memory(
          base64Decode(url.substring(comma + 1)),
          height: 160,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => broken(),
        );
      } catch (_) {
        return broken();
      }
    }
    return Image.network(
      url,
      height: 160,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => broken(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    return AlertDialog(
      title: Text('Hồ sơ tài xế ${widget.displayName ?? ''}'.trim()),
      content: SizedBox(
        width: 560,
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
            ? Text(_error!)
            : app == null
            ? const Text(
                'Tài khoản này chưa nộp hồ sơ phương tiện (đăng ký theo cách cũ).',
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trạng thái: ${driverApplicationStates[app['state']] ?? app['state']}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Loại xe: ${VehicleClass.byId(app['vehicle_type']).label}',
                    ),
                    Text('Biển số: ${app['license_plate'] ?? ''}'),
                    Text(
                      'Xe: ${app['vehicle_brand'] ?? ''} · ${app['vehicle_color'] ?? ''}',
                    ),
                    Text(
                      'GPLX: hạng ${app['license_class'] ?? ''} · số ${app['license_number'] ?? ''}',
                    ),
                    Text('Khu vực: ${app['operating_area'] ?? ''}'),
                    if ('${app['reason'] ?? ''}'.trim().isNotEmpty)
                      Text('Ghi chú xét duyệt: ${app['reason']}'),
                    const Divider(height: 24),
                    for (final entry in driverDocumentKinds.entries) ...[
                      Text(
                        entry.value,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      if (_urls[entry.key] != null)
                        _image(_urls[entry.key]!)
                      else
                        const Text('Chưa có ảnh'),
                      const SizedBox(height: 12),
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
      ],
    );
  }
}
