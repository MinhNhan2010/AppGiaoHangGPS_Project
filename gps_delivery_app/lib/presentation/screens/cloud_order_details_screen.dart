import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env_config.dart';
import '../../core/gps/delivery_live_telemetry.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/integrations/delivery_weather_service.dart';
import '../../core/network/public_json_api.dart';
import '../../core/theme/ghst_theme_tokens.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/delivery_order_utilities.dart';
import '../../domain/entities/vehicle_class.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/entities/geo_point.dart';
import '../widgets/cloud_commerce_dialog.dart';
import '../widgets/cloud_logistics_panels.dart';
import '../widgets/cloud_order_form.dart';
import '../widgets/cloud_order_labels.dart';
import '../widgets/cloud_session_boundary.dart';
import '../widgets/delivery_utilities_widgets.dart';
import '../widgets/delivery_weather_strip.dart';
import '../widgets/market_commercial_sheets.dart';
import '../widgets/recipient_signature_pad.dart';
import '../widgets/system_state_screens.dart';
import '../widgets/ghst_button_icon.dart';

class CloudOrderDetailsScreen extends StatefulWidget {
  const CloudOrderDetailsScreen({
    super.key,
    required this.lease,
    required this.order,
    this.merchants = const [],
    this.onReorder,
    this.weatherService,
  });

  final CloudSessionLease lease;
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> merchants;
  final ValueChanged<Map<String, dynamic>>? onReorder;
  final DeliveryWeatherService? weatherService;

  @override
  State<CloudOrderDetailsScreen> createState() =>
      _CloudOrderDetailsScreenState();
}

class _CloudOrderDetailsScreenState extends State<CloudOrderDetailsScreen> {
  late Map<String, dynamic> _currentOrder = Map<String, dynamic>.from(
    widget.order,
  );
  List<Map<String, dynamic>>? _history;
  Map<String, dynamic>? _liveGps;
  Map<String, dynamic>? _driverProfile;
  Map<String, dynamic>? _senderProfile;
  Map<String, dynamic>? _driverReview;
  List<Map<String, dynamic>> _chatMessages = const [];
  Set<String> _completedCheckpoints = <String>{};
  bool _hasPodFromLive = false;
  String? _podPhotoPath;
  bool _hasSignatureFromLive = false;
  String? _signaturePath;
  String? _recipientSignerName;
  bool _busy = false;
  bool _chatBusy = false;
  bool _localRevoked = false;
  int _generation = 0;
  String? _error;
  Timer? _livePollTimer;
  StreamSubscription<AuthState>? _auth;
  final _chatCtrl = TextEditingController();

  bool get _isAutomatedTestBinding {
    final bindingType = WidgetsBinding.instance.runtimeType.toString();
    return bindingType.contains('TestWidgetsFlutterBinding') ||
        bindingType.contains('AutomatedTest');
  }

  bool get _allowed => !_localRevoked && widget.lease.valid;
  Map<String, dynamic> get _order => _currentOrder;
  Map get _details => _order['details'] as Map? ?? const {};
  String get _userId => widget.lease.session.service.userId;
  bool get _isOwner => _order['owner_id'] == _userId;
  bool get _isAssignedDriver =>
      _order['driver_id'] != null && _order['driver_id'] == _userId;
  bool get _isDriverRole => widget.lease.session.hasRole('driver');
  bool get _isMerchantOrOperator =>
      widget.lease.session.isOperator || _order['merchant_id'] == _userId;
  bool get _isShopStaffViewer =>
      !_isOwner &&
      !_isAssignedDriver &&
      !_isMerchantOrOperator &&
      widget.lease.session.hasMerchantAccess;

  String get _effectiveStatus {
    final history = _history;
    final latest = history != null && history.isNotEmpty ? history.last : null;
    return '${latest != null && latest['version'] >= (_order['version'] as int? ?? 0) ? latest['status'] : _order['status']}';
  }

  bool get _isActiveJourney => const {
    'searching',
    'accepted',
    'arrivingPickup',
    'inTransit',
    'returning',
  }.contains(_effectiveStatus);

  bool get _canRepeat =>
      _allowed &&
      _history != null &&
      widget.lease.session.canCreateShippingOrder &&
      _isOwner;

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
        lat.abs() > 90 ||
        lng.abs() > 180) {
      return null;
    }
    return GeoPoint(latitude: lat, longitude: lng);
  }

  void _hydrateEmbeddedFieldsFromOrder() {
    if (_order['driver_profile'] is Map) {
      _driverProfile = Map<String, dynamic>.from(
        _order['driver_profile'] as Map,
      );
    }
    if (_order['sender_profile'] is Map) {
      _senderProfile = Map<String, dynamic>.from(
        _order['sender_profile'] as Map,
      );
    }
    if (_order['latest_gps'] is Map) {
      _liveGps = Map<String, dynamic>.from(_order['latest_gps'] as Map);
    }
    if (_order['driver_review'] is Map) {
      _driverReview = Map<String, dynamic>.from(_order['driver_review'] as Map);
    }
    final initialPodPath = '${_order['pod_photo_path'] ?? ''}'.trim();
    if (initialPodPath.isNotEmpty) {
      _podPhotoPath = initialPodPath;
      _hasPodFromLive = true;
    } else if (_order['has_pod'] == true) {
      _hasPodFromLive = true;
    }
    final initialSigPath = '${_order['signature_path'] ?? ''}'.trim();
    if (initialSigPath.isNotEmpty) {
      _signaturePath = initialSigPath;
      _hasSignatureFromLive = true;
    } else if (_order['has_signature'] == true) {
      _hasSignatureFromLive = true;
    }
    final initialSigner = '${_order['recipient_signer_name'] ?? ''}'.trim();
    if (initialSigner.isNotEmpty) {
      _recipientSignerName = initialSigner;
    }
    final rawCheckpoints =
        _order['completed_checkpoints'] ?? _details['completed_checkpoints'];
    if (rawCheckpoints is List) {
      _completedCheckpoints = {
        for (final item in rawCheckpoints)
          if (item is Map && item['key'] != null)
            '${item['key']}'
          else if (item is String && item.trim().isNotEmpty)
            item.trim(),
      };
    }
  }

  @override
  void initState() {
    super.initState();
    _hydrateEmbeddedFieldsFromOrder();
    final openingSession = widget.lease.session.service.authSession;
    _auth = widget.lease.session.service.authChanges.listen((event) {
      if (!_allowed ||
          event.event == AuthChangeEvent.signedOut ||
          event.event == AuthChangeEvent.signedIn &&
              (event.session == null ||
                  !identical(event.session, openingSession))) {
        _localRevoked = true;
        _invalidate();
      }
    });
    widget.lease.addListener(_invalidate);
    _load();
  }

  void _syncLivePolling() {
    _livePollTimer?.cancel();
    _livePollTimer = null;
    if (_isAutomatedTestBinding ||
        !_allowed ||
        _history == null ||
        !_isActiveJourney) {
      return;
    }
    _livePollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || !_allowed || _busy || !_isActiveJourney) return;
      unawaited(_refreshLiveSnapshot());
    });
  }

  void _invalidate() {
    if (!mounted) return;
    _generation++;
    _livePollTimer?.cancel();
    _livePollTimer = null;
    setState(() {
      if (!_allowed) _busy = false;
      _history = null;
      _chatMessages = const [];
      _driverProfile = null;
      _senderProfile = null;
      _liveGps = null;
      _error = null;
    });
  }

  @override
  void dispose() {
    _generation++;
    _livePollTimer?.cancel();
    _auth?.cancel();
    widget.lease.removeListener(_invalidate);
    _chatCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy || !_allowed) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _history = null;
      _error = null;
    });
    try {
      final result = await widget.lease.session.service.request(
        'orders/${_order['id']}/history',
      );
      if (!mounted || !_allowed || generation != _generation) return;
      final raw = result['history'];
      if (raw is! List) throw const FormatException('Invalid order history');
      final versions = <int>{};
      final history =
          raw.map((row) {
            if (row is! Map ||
                row['order_id'] != _order['id'] ||
                row['version'] is! int ||
                row['version'] < 1 ||
                !versions.add(row['version'] as int) ||
                !cloudActions.containsKey(row['action']) ||
                !cloudStatuses.containsKey(row['status']) ||
                DateTime.tryParse('${row['created_at']}') == null ||
                row['reason'] != null && row['reason'] is! String) {
              throw const FormatException('Invalid order history entry');
            }
            return Map<String, dynamic>.unmodifiable(
              Map<String, dynamic>.from(row),
            );
          }).toList()..sort(
            (a, b) => (a['version'] as int).compareTo(b['version'] as int),
          );
      setState(() => _history = List.unmodifiable(history));
      _syncLivePolling();
      unawaited(_refreshLiveSnapshot(expectedGeneration: generation));
    } catch (error) {
      if (!mounted || !_allowed || generation != _generation) return;
      if (error is PublicApiException &&
          [401, 403].contains(error.statusCode)) {
        widget.lease.session.invalidateVerification();
        return;
      }
      setState(
        () => _error = error is PublicApiException && error.statusCode == 404
            ? 'Đơn hàng không còn khả dụng với tài khoản này.'
            : 'Không tải được chi tiết đơn hàng. Vui lòng thử lại.',
      );
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _refreshLiveSnapshot({int? expectedGeneration}) async {
    if (!_allowed || _history == null) return;
    final gen = expectedGeneration ?? _generation;
    try {
      final snap = await widget.lease.session.service.orderLive('snapshot', {
        'order_id': '${_order['id']}',
      });
      if (!mounted || !_allowed || gen != _generation || snap.isEmpty) return;
      final enriched = snap['order'] is Map
          ? Map<String, dynamic>.from(snap['order'] as Map)
          : snap;
      final rawMessages = snap['messages'] ?? snap['chat_messages'];
      setState(() {
        if (enriched['status'] is String &&
            cloudStatuses.containsKey(enriched['status'])) {
          _currentOrder['status'] = enriched['status'];
        }
        if (enriched['version'] is int) {
          _currentOrder['version'] = enriched['version'];
        }
        if (enriched['driver_profile'] is Map) {
          _driverProfile = Map<String, dynamic>.from(
            enriched['driver_profile'] as Map,
          );
        }
        if (enriched['sender_profile'] is Map) {
          _senderProfile = Map<String, dynamic>.from(
            enriched['sender_profile'] as Map,
          );
        }
        final rawLiveGps = enriched['latest_gps'] ?? snap['gps'];
        if (rawLiveGps is Map) {
          _liveGps = Map<String, dynamic>.from(rawLiveGps);
        }
        if (enriched['driver_review'] is Map) {
          _driverReview = Map<String, dynamic>.from(
            enriched['driver_review'] as Map,
          );
        }
        final livePodPath = '${enriched['pod_photo_path'] ?? ''}'.trim();
        if (livePodPath.isNotEmpty) {
          _podPhotoPath = livePodPath;
          _hasPodFromLive = true;
        } else if (enriched['has_pod'] == true) {
          _hasPodFromLive = true;
        }
        final liveSigPath = '${enriched['signature_path'] ?? ''}'.trim();
        if (liveSigPath.isNotEmpty) {
          _signaturePath = liveSigPath;
          _hasSignatureFromLive = true;
        } else if (enriched['has_signature'] == true) {
          _hasSignatureFromLive = true;
        }
        final liveSigner = '${enriched['recipient_signer_name'] ?? ''}'.trim();
        if (liveSigner.isNotEmpty) {
          _recipientSignerName = liveSigner;
        }
        if (rawMessages is List) {
          _chatMessages = rawMessages
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList(growable: false);
        }
        final rawCheckpoints =
            enriched['completed_checkpoints'] ?? snap['completed_checkpoints'];
        if (rawCheckpoints is List) {
          _completedCheckpoints = {
            for (final item in rawCheckpoints)
              if (item is Map && item['key'] != null)
                '${item['key']}'
              else if (item is String && item.trim().isNotEmpty)
                item.trim(),
          };
        }
      });
      _syncLivePolling();
    } catch (_) {}
  }

  String _text(dynamic value) =>
      value == null || '$value'.trim().isEmpty ? 'Chưa có thông tin' : '$value';
  String _money(dynamic value) => value is num && value.isFinite && value >= 0
      ? CurrencyFormatter.formatVnd(value.toDouble())
      : 'Chưa có thông tin';
  String get _status => cloudStatuses[_effectiveStatus] ?? 'Đang cập nhật';

  String get _payment => cloudOrderPaymentLabel(_order, detailedReview: true);
  String get _payer => switch (_details['payment_method']) {
    'sender_cash' => 'Người gửi trả phí',
    'recipient_cash' => 'Người nhận trả phí',
    _ => 'Chưa có thông tin',
  };

  Map<String, String> get _summary => {
    'Trạng thái': _status,
    'Ngày tạo': cloudDate(_order['created_at']),
    'Điểm lấy': _text(_details['pickup_address']),
    'Điểm giao': _text(_details['dropoff_address']),
    'Người nhận': _text(_details['recipient_name']),
    'Điện thoại': _text(_details['recipient_phone']),
    'Hàng hóa': _text(_details['package_description']),
    'Khối lượng': '${_text(_details['weight_kg'])} kg',
    'Cước vận chuyển': _money(_order['shipping_fee']),
    if ((_order['coin_discount'] as num? ?? 0) > 0) ...{
      'Đổi Xu giảm cước': '-${_money(_order['coin_discount'])}',
      'Cước cần thanh toán': _money(
        _order['payable_fee'] ?? _order['shipping_fee'],
      ),
    },
    'Tiền thu hộ COD': _money(_order['cod_amount']),
    'Trả phí': _payer,
    'Thanh toán': _payment,
    if ((_order['cash_collected_fee'] as num? ?? 0) > 0)
      'Tiền mặt cước đã thu': _money(_order['cash_collected_fee']),
    if ((_order['cash_collected_cod'] as num? ?? 0) > 0)
      'Tiền mặt COD đã thu': _money(_order['cash_collected_cod']),
    if (_order['cash_collected_at'] != null)
      'Thời điểm thu tiền mặt': cloudDate(_order['cash_collected_at']),
  };

  Future<void> _copy({bool receipt = false}) async {
    if (!_allowed || _history == null) return;
    final text = receipt
        ? [
            'THÔNG TIN ĐƠN GIAO HÀNG',
            'Mã vận đơn: ${_order['tracking_code']}',
            ..._summary.entries.map((e) => '${e.key}: ${e.value}'),
          ].join('\n')
        : '${_order['tracking_code']}';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted && _allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            receipt ? 'Đã sao chép thông tin đơn.' : 'Đã sao chép mã vận đơn.',
          ),
        ),
      );
    }
  }

  Future<void> _launchPhoneCall(String rawPhone) async {
    final cleaned = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: cleaned);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openExternalNavigation() async {
    final status = _effectiveStatus;
    final goingToPickup = status == 'accepted' || status == 'arrivingPickup';
    final pickup = _parsePoint(_details['pickup_lat'], _details['pickup_lng']);
    final dropoff = _parsePoint(
      _details['dropoff_lat'],
      _details['dropoff_lng'],
    );
    final destination = goingToPickup
        ? (pickup != null
              ? '${pickup.latitude},${pickup.longitude}'
              : '${_details['pickup_address'] ?? ''}'.trim())
        : (dropoff != null
              ? '${dropoff.latitude},${dropoff.longitude}'
              : '${_details['dropoff_address'] ?? ''}'.trim());
    if (destination.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Chưa có tọa độ hoặc địa chỉ điểm đến.'),
          ),
        );
      }
      return;
    }
    final extraStops = (_details['extra_stops'] as List? ?? const [])
        .whereType<Map>()
        .map((s) => _parsePoint(s['lat'], s['lng']))
        .whereType<GeoPoint>()
        .toList();
    final query = <String, String>{
      'api': '1',
      if (!goingToPickup && pickup != null)
        'origin': '${pickup.latitude},${pickup.longitude}',
      'destination': destination,
      if (!goingToPickup && extraStops.isNotEmpty)
        'waypoints': extraStops
            .map((p) => '${p.latitude},${p.longitude}')
            .join('|'),
      'travelmode': 'driving',
    };
    final uri = Uri.https('www.google.com', '/maps/dir/', query);
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Đã sao chép liên kết chỉ đường Google Maps.'),
        ),
      );
    }
  }

  Future<void> _callRecipient() async {
    final phone = '${_details['recipient_phone'] ?? ''}'.trim();
    if (phone.isEmpty) return;
    var launched = false;
    try {
      launched = await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      await Clipboard.setData(ClipboardData(text: phone));
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Đã sao chép SĐT người nhận: $phone'),
        ),
      );
    }
  }

  Future<void> _reportDriverIncident() async {
    final message = await showDriverIncidentDialog(context);
    if (message == null || message.trim().isEmpty || !mounted || !_allowed) {
      return;
    }
    await _sendOrderChat(message);
  }

  Future<void> _broadcastRealDriverGps() async {
    if (_busy || !_allowed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pos = await AppStateStore.instance.startRealTimeDeviceGpsTracking(
        syncDriverLocation: true,
        forcePromptPermission: true,
      );
      if (!mounted || !_allowed) return;
      if (pos == null) {
        setState(() => _error = AppStateStore.instance.liveGpsStatusMessage);
        return;
      }
      final res = await widget.lease.session.service.orderLive('push_gps', {
        'order_id': '${_order['id']}',
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'heading': AppStateStore.instance.activeDriverBearing,
      });
      if (!mounted || !_allowed) return;
      if (res['latest_gps'] is Map) {
        setState(
          () => _liveGps = Map<String, dynamic>.from(res['latest_gps'] as Map),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã phát tọa độ GPS thực tế lên hành trình.'),
        ),
      );
    } catch (e) {
      if (mounted && !_leaseHandled(e)) {
        setState(
          () => _error = e is PublicApiException
              ? e.message
              : 'Chưa gửi được định vị GPS.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markCheckpoint(String checkpointKey, String label) async {
    if (_busy || !_allowed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.lease.session.service.orderLive(
        'mark_checkpoint',
        {
          'order_id': '${_order['id']}',
          'checkpoint_key': checkpointKey,
          'note': label,
        },
      );
      if (!mounted || !_allowed) return;
      final updatedOrder = res['order'] is Map
          ? Map<String, dynamic>.from(res['order'] as Map)
          : null;
      final rawCps =
          updatedOrder?['completed_checkpoints'] ??
          res['completed_checkpoints'];
      setState(() {
        if (updatedOrder != null) {
          _currentOrder = updatedOrder;
        }
        _completedCheckpoints = {..._completedCheckpoints, checkpointKey};
        if (rawCps is List) {
          _completedCheckpoints = {
            for (final item in rawCps)
              if (item is Map && item['key'] != null)
                '${item['key']}'
              else if (item is String && item.trim().isNotEmpty)
                item.trim(),
          };
        }
        _busy = false;
      });
      await _load();
    } catch (e) {
      if (mounted && !_leaseHandled(e)) {
        setState(
          () => _error = e is PublicApiException
              ? e.message
              : 'Chưa ghi nhận được điểm dừng.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendOrderChat([String? preset]) async {
    final text = (preset ?? _chatCtrl.text).trim();
    if (text.isEmpty || _chatBusy || !_allowed) return;
    setState(() {
      _chatBusy = true;
      _error = null;
    });
    try {
      final res = await widget.lease.session.service.orderLive('send_chat', {
        'order_id': '${_order['id']}',
        'text': text,
      });
      if (!mounted || !_allowed) return;
      if (preset == null) _chatCtrl.clear();
      setState(() {
        if (res['message'] is Map) {
          _chatMessages = [
            ..._chatMessages,
            Map<String, dynamic>.from(res['message'] as Map),
          ];
        }
      });
    } catch (e) {
      if (mounted && !_leaseHandled(e)) {
        setState(
          () => _error = e is PublicApiException
              ? e.message
              : 'Chưa gửi được tin nhắn chuyến giao.',
        );
      }
    } finally {
      if (mounted) setState(() => _chatBusy = false);
    }
  }

  Future<T?> _privateDialog<T>(Widget Function(BuildContext dialog) builder) =>
      showDialog<T>(
        context: context,
        builder: (_) => CloudSessionBoundary(
          session: widget.lease.session,
          operator: widget.lease.session.isOperator,
          dialog: true,
          builder: (dialog, _) => builder(dialog),
        ),
      );

  Future<void> _executeTransition(String action) async {
    if (_busy || !_allowed) return;
    final service = widget.lease.session.service;
    final currentVersion = (_history != null && _history!.isNotEmpty
        ? (_history!.last['version'] as int)
        : (_order['version'] as int? ?? 1));
    String reason = '';
    var collectCashBeforeDeliver = false;

    if (const ['cancel', 'fail', 'return'].contains(action)) {
      final ctrl = TextEditingController();
      final entered = await _privateDialog<String>(
        (dialog) => AlertDialog(
          title: Text(cloudActions[action] ?? 'Cập nhật trạng thái'),
          content: TextField(
            controller: ctrl,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Lý do · tối thiểu 3 ký tự',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(dialog),
              icon: const GhstButtonIcon.glyph(GhstActionKind.back, size: 16),

              label: const Text('Quay lại'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialog, ctrl.text.trim()),
              icon: const GhstButtonIcon.glyph(
                GhstActionKind.checkCircle,
                size: 16,
              ),

              label: const Text('Xác nhận'),
            ),
          ],
        ),
      );
      Future<void>.delayed(const Duration(seconds: 1), ctrl.dispose);
      if (entered == null || !mounted || !_allowed) return;
      if (entered.length < 3) {
        setState(() => _error = 'Lý do cần ít nhất 3 ký tự.');
        return;
      }
      reason = entered;
    } else if (action == 'collect_cash') {
      final feeDue = cloudOrderPendingCashFee(_order);
      final codDue = cloudOrderPendingCashCod(_order);
      final ok = await _privateDialog<bool>(
        (dialog) => AlertDialog(
          title: const Text('Xác nhận thu tiền mặt'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mã vận đơn: ${_order['tracking_code']}'),
              const SizedBox(height: 8),
              if (feeDue > 0)
                Text(
                  'Cước vận chuyển thu tiền mặt: ${CurrencyFormatter.formatVnd(feeDue.toDouble())}',
                ),
              if (codDue > 0)
                Text(
                  'Tiền thu hộ COD: ${CurrencyFormatter.formatVnd(codDue.toDouble())}',
                ),
              if (feeDue > 0 && codDue > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Tổng cần thu: ${CurrencyFormatter.formatVnd((feeDue + codDue).toDouble())}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(dialog, false),
              icon: const GhstButtonIcon.glyph(GhstActionKind.back, size: 16),

              label: const Text('Quay lại'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialog, true),
              icon: const GhstButtonIcon.glyph(GhstActionKind.wallet, size: 16),

              label: const Text('Xác nhận đã thu'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted || !_allowed) return;
    } else if (action == 'deliver') {
      final needPod = _details['require_pod'] == true;
      final needOtp = _details['require_otp'] == true;
      final needSignature = _details['require_signature'] == true;
      final needCash = cloudOrderCanCollectCash(_order);
      final feeDue = cloudOrderPendingCashFee(_order);
      final codDue = cloudOrderPendingCashCod(_order);
      var podReady =
          _hasPodFromLive ||
          (_order['pod_photo_path'] as String? ?? '').isNotEmpty;
      var signatureReady =
          _hasSignatureFromLive ||
          (_order['signature_path'] as String? ?? '').isNotEmpty;
      var cashConfirmed = !needCash;
      var uploading = false;
      String? dialogErr;
      final otpCtrl = TextEditingController();
      final noteCtrl = TextEditingController();
      final signerNameCtrl = TextEditingController(
        text: '${_details['recipient_name'] ?? ''}'.trim(),
      );
      final sigCtrl = RecipientSignatureController();
      final deliverPayload = await _privateDialog<({String reason, bool collectCash})>(
        (dialog) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Hoàn tất giao hàng'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (uploading) const LinearProgressIndicator(),
                    if (dialogErr != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          dialogErr!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (needCash) ...[
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: cashConfirmed,
                        onChanged: (v) =>
                            update(() => cashConfirmed = v ?? false),
                        title: Text(
                          'Đã thu đủ tiền mặt · ${CurrencyFormatter.formatVnd((feeDue + codDue).toDouble())}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            if (feeDue > 0)
                              'Cước: ${CurrencyFormatter.formatVnd(feeDue.toDouble())}',
                            if (codDue > 0)
                              'COD: ${CurrencyFormatter.formatVnd(codDue.toDouble())}',
                          ].join(' · '),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (needPod) ...[
                      OutlinedButton.icon(
                        onPressed: uploading
                            ? null
                            : () async {
                                final file = await openFile(
                                  acceptedTypeGroups: const [
                                    XTypeGroup(
                                      label: 'Ảnh POD',
                                      extensions: [
                                        'jpg',
                                        'jpeg',
                                        'png',
                                        'webp',
                                      ],
                                    ),
                                  ],
                                );
                                if (file == null) return;
                                if (await file.length() > 5000000) {
                                  update(() => dialogErr = 'Ảnh tối đa 5 MB.');
                                  return;
                                }
                                update(() {
                                  uploading = true;
                                  dialogErr = null;
                                });
                                try {
                                  final uploadedPath = await service.uploadPod(
                                    trackingCode: '${_order['tracking_code']}',
                                    bytes: await file.readAsBytes(),
                                  );
                                  if (dialog.mounted) {
                                    update(() {
                                      uploading = false;
                                      podReady = true;
                                      _hasPodFromLive = true;
                                      _podPhotoPath = uploadedPath;
                                    });
                                  }
                                } catch (e) {
                                  if (dialog.mounted) {
                                    update(() {
                                      uploading = false;
                                      dialogErr = e is PublicApiException
                                          ? e.message
                                          : 'Chưa tải được ảnh POD.';
                                    });
                                  }
                                }
                              },
                        icon: GhstButtonIcon(
                          podReady
                              ? Icons.check_circle_outline
                              : Icons.camera_alt_outlined,
                        ),
                        label: Text(
                          podReady
                              ? 'Đã tải lên ảnh POD'
                              : 'Tải ảnh bằng chứng giao hàng',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      key: const ValueKey('deliver-signer-name'),
                      controller: signerNameCtrl,
                      maxLength: 120,
                      decoration: InputDecoration(
                        labelText: needSignature
                            ? 'Họ tên người ký nhận (bắt buộc)'
                            : 'Họ tên người ký nhận (tùy chọn)',
                        border: const OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 10),
                    RecipientSignaturePad(
                      controller: sigCtrl,
                      enabled: !uploading,
                      requiredSignature: needSignature,
                    ),
                    if (signatureReady)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Đã lưu chữ ký điện tử người nhận lên hệ thống.',
                          style: TextStyle(
                            color: Color(0xFF047857),
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (needOtp)
                      TextField(
                        controller: otpCtrl,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Mã OTP 6 số người nhận',
                          border: OutlineInputBorder(),
                        ),
                      )
                    else
                      TextField(
                        controller: noteCtrl,
                        maxLength: 200,
                        decoration: const InputDecoration(
                          labelText: 'Ghi chú người nhận · tùy chọn',
                          hintText: 'Ví dụ: Chính chủ nhận / Lễ tân nhận',
                          border: OutlineInputBorder(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.pop(dialog),
                icon: const GhstButtonIcon.glyph(GhstActionKind.back, size: 16),

                label: const Text('Quay lại'),
              ),
              FilledButton.icon(
                key: const ValueKey('deliver-dialog-confirm'),
                onPressed: uploading
                    ? null
                    : () async {
                        if (needCash && !cashConfirmed) {
                          update(
                            () => dialogErr = 'Xác nhận đã thu đủ tiền mặt trước khi hoàn tất.',
                          );
                          return;
                        }
                        if (needPod && !podReady) {
                          update(
                            () => dialogErr =
                                'Cần tải ảnh POD trước khi hoàn tất giao.',
                          );
                          return;
                        }
                        if (!signatureReady && sigCtrl.hasSignature) {
                          update(() {
                            uploading = true;
                            dialogErr = null;
                          });
                          try {
                            final pngBytes = await sigCtrl.toPngBytes(
                              trackingCode: '${_order['tracking_code']}',
                              signerName: signerNameCtrl.text.trim(),
                            );
                            if (pngBytes != null) {
                              final uploadedSig = await service.uploadPod(
                                trackingCode: '${_order['tracking_code']}',
                                bytes: pngBytes,
                                evidenceType: 'signature',
                                signerName: signerNameCtrl.text.trim(),
                              );
                              signatureReady = true;
                              _hasSignatureFromLive = true;
                              _signaturePath = uploadedSig;
                              _recipientSignerName = signerNameCtrl.text.trim();
                            }
                            if (dialog.mounted) {
                              update(() => uploading = false);
                            }
                          } catch (e) {
                            if (dialog.mounted) {
                              update(() {
                                uploading = false;
                                dialogErr = e is PublicApiException
                                    ? e.message
                                    : 'Chưa lưu được chữ ký điện tử người nhận.';
                              });
                            }
                            return;
                          }
                        }
                        if (needSignature && !signatureReady) {
                          update(
                            () => dialogErr = 'Đơn hàng yêu cầu chữ ký tay điện tử của người nhận.',
                          );
                          return;
                        }
                        final otp = otpCtrl.text.trim();
                        if (needOtp && !RegExp(r'^[0-9]{6}$').hasMatch(otp)) {
                          update(
                            () => dialogErr =
                                'Nhập đúng 6 chữ số mã OTP người nhận.',
                          );
                          return;
                        }
                        if (!dialog.mounted) return;
                        Navigator.pop(dialog, (
                          reason: needOtp ? otp : noteCtrl.text.trim(),
                          collectCash: needCash,
                        ));
                      },
                icon: const GhstButtonIcon.glyph(
                  GhstActionKind.scooter,
                  size: 16,
                ),

                label: const Text('Xác nhận đã giao'),
              ),
            ],
          ),
        ),
      );
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        otpCtrl.dispose();
        noteCtrl.dispose();
        signerNameCtrl.dispose();
        sigCtrl.dispose();
      });
      if (deliverPayload == null || !mounted || !_allowed) return;
      reason = deliverPayload.reason;
      collectCashBeforeDeliver = deliverPayload.collectCash;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var nextVersion = currentVersion;
      if (collectCashBeforeDeliver) {
        final cashRes = await service.command(
          'orders/${_order['id']}/transition',
          {'action': 'collect_cash', 'version': nextVersion, 'reason': ''},
        );
        if (cashRes['order'] is Map) {
          _currentOrder = Map<String, dynamic>.from(cashRes['order'] as Map);
          nextVersion = (_currentOrder['version'] as int?) ?? (nextVersion + 1);
        } else {
          nextVersion += 1;
        }
      }
      final res = await service.command('orders/${_order['id']}/transition', {
        'action': action,
        'version': nextVersion,
        'reason': reason,
      });
      if (!mounted || !_allowed) return;
      if (res['order'] is Map) {
        setState(() {
          _currentOrder = Map<String, dynamic>.from(res['order'] as Map);
          _hydrateEmbeddedFieldsFromOrder();
          _busy = false;
        });
      } else {
        setState(() => _busy = false);
      }
      await _load();
      unawaited(widget.lease.session.refresh().catchError((Object _) {}));
    } catch (e) {
      if (mounted && !_leaseHandled(e)) {
        setState(() {
          _busy = false;
          _error = e is PublicApiException
              ? e.message
              : 'Chưa cập nhật được trạng thái chuyến giao.';
        });
      }
    }
  }

  Future<void> _showOtp() async {
    if (_busy || !_allowed) return;
    setState(() => _busy = true);
    try {
      final res = await widget.lease.session.service.orderOtp(
        '${_order['id']}',
      );
      if (!mounted || !_allowed) return;
      final otp = '${res['otp_code'] ?? res['recipient_otp'] ?? ''}'.trim();
      await showDialog<void>(
        context: context,
        builder: (_) => CloudSessionBoundary(
          session: widget.lease.session,
          dialog: true,
          builder: (dialog, _) => AlertDialog(
            title: const Text('Mã OTP giao hàng người nhận'),
            content: SelectableText(
              otp.isEmpty ? 'Đơn hàng này không yêu cầu OTP.' : otp,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            actions: [
              if (otp.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: otp)).ignore();
                    Navigator.pop(dialog);
                  },
                  icon: const GhstButtonIcon(Icons.copy),
                  label: const Text('Sao chép'),
                ),
              TextButton.icon(
                onPressed: () => Navigator.pop(dialog),
                icon: const GhstButtonIcon.glyph(
                  GhstActionKind.close,
                  size: 16,
                ),

                label: const Text('Đóng'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted && !_leaseHandled(e)) {
        setState(
          () => _error = e is PublicApiException
              ? e.message
              : 'Chưa tải được mã OTP.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _viewPod() async {
    final podPath = (_podPhotoPath ?? '${_order['pod_photo_path'] ?? ''}')
        .trim();
    if (_busy || !_allowed || podPath.isEmpty) return;
    setState(() => _busy = true);
    try {
      final url = await widget.lease.session.service.signPod(podPath);
      if (!mounted || !_allowed) return;
      await showDialog<void>(
        context: context,
        builder: (_) => CloudSessionBoundary(
          session: widget.lease.session,
          dialog: true,
          builder: (dialog, _) => AlertDialog(
            title: const Text('Ảnh bằng chứng giao hàng'),
            content: SizedBox(
              width: 480,
              height: 360,
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Center(child: Text('Không hiển thị được ảnh POD.')),
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.pop(dialog),
                icon: const GhstButtonIcon.glyph(
                  GhstActionKind.close,
                  size: 16,
                ),

                label: const Text('Đóng'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted && !_leaseHandled(e)) {
        setState(
          () => _error = e is PublicApiException
              ? e.message
              : 'Chưa mở được ảnh POD.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _viewSignature() async {
    final sigPath = (_signaturePath ?? '${_order['signature_path'] ?? ''}')
        .trim();
    if (_busy || !_allowed || sigPath.isEmpty) return;
    setState(() => _busy = true);
    try {
      final url = await widget.lease.session.service.signPod(sigPath);
      if (!mounted || !_allowed) return;
      final signer =
          (_recipientSignerName ?? '${_order['recipient_signer_name'] ?? ''}')
              .trim();
      await showDialog<void>(
        context: context,
        builder: (_) => CloudSessionBoundary(
          session: widget.lease.session,
          dialog: true,
          builder: (dialog, _) => AlertDialog(
            title: Text(
              signer.isNotEmpty
                  ? 'Chữ ký người nhận · $signer'
                  : 'Chữ ký điện tử người nhận',
            ),
            content: SizedBox(
              width: 480,
              height: 280,
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Center(
                    child: Text('Không hiển thị được biên nhận chữ ký.'),
                  ),
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.pop(dialog),
                icon: const GhstButtonIcon.glyph(
                  GhstActionKind.close,
                  size: 16,
                ),
                label: const Text('Đóng'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted && !_leaseHandled(e)) {
        setState(
          () => _error = e is PublicApiException
              ? e.message
              : 'Chưa mở được chữ ký người nhận.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manageShares() async {
    if (_busy || !_allowed) return;
    setState(() => _busy = true);
    List<Map<String, dynamic>> shares = [];
    try {
      final res = await widget.lease.session.service.orderShares(
        '${_order['id']}',
      );
      shares = (res['shares'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      if (mounted && !_leaseHandled(e)) {
        setState(() {
          _busy = false;
          _error = e is PublicApiException
              ? e.message
              : 'Chưa tải được danh sách liên kết chia sẻ.';
        });
      }
      return;
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted || !_allowed) return;
    await showDialog<void>(
      context: context,
      builder: (_) => CloudSessionBoundary(
        session: widget.lease.session,
        dialog: true,
        builder: (dialog, lease) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Chia sẻ hành trình đơn hàng'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: () async {
                        final created = await widget.lease.session.service
                            .orderShares('${_order['id']}', create: true);
                        final url =
                            created['share_url'] as String? ??
                            '${created['token']}';
                        try {
                          await Clipboard.setData(ClipboardData(text: url));
                        } catch (_) {}
                        final refreshed = await widget.lease.session.service
                            .orderShares('${_order['id']}');
                        if (dialog.mounted && lease.valid) {
                          update(() {
                            shares = (refreshed['shares'] as List? ?? const [])
                                .map((e) => Map<String, dynamic>.from(e as Map))
                                .toList();
                          });
                        }
                      },
                      icon: const GhstButtonIcon(Icons.add_link),
                      label: const Text('Tạo & sao chép liên kết mới'),
                    ),
                    const SizedBox(height: 12),
                    if (shares.isEmpty)
                      const Text('Chưa có liên kết chia sẻ đang mở.'),
                    for (final s in shares)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: SelectableText('Mã liên kết · ${s['id']}'),
                        subtitle: Text(
                          s['revoked_at'] != null
                              ? 'Đã thu hồi'
                              : 'Hiệu lực đến: ${cloudDate(s['expires_at'])}',
                        ),
                        trailing: s['revoked_at'] != null
                            ? null
                            : IconButton(
                                tooltip: 'Thu hồi liên kết',
                                icon: const GhstButtonIcon(Icons.link_off),
                                onPressed: () async {
                                  await widget.lease.session.service
                                      .orderShares(
                                        '${_order['id']}',
                                        revokeId: '${s['id']}',
                                      );
                                  final refreshed = await widget
                                      .lease
                                      .session
                                      .service
                                      .orderShares('${_order['id']}');
                                  if (dialog.mounted && lease.valid) {
                                    update(() {
                                      shares =
                                          (refreshed['shares'] as List? ??
                                                  const [])
                                              .map(
                                                (e) =>
                                                    Map<String, dynamic>.from(
                                                      e as Map,
                                                    ),
                                              )
                                              .toList();
                                    });
                                  }
                                },
                              ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.pop(dialog),
                icon: const GhstButtonIcon.glyph(
                  GhstActionKind.close,
                  size: 16,
                ),

                label: const Text('Đóng'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _leaseHandled(Object error) {
    if (error is PublicApiException && [401, 403].contains(error.statusCode)) {
      widget.lease.session.invalidateVerification();
      return true;
    }
    return false;
  }

  Future<void> _repeat() async {
    if (!_canRepeat) return;
    final reorderDetails = buildReorderInitialDetails(_order);
    if (widget.onReorder != null) {
      widget.onReorder!(reorderDetails);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(false);
      }
      return;
    }
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CloudSessionBoundary(
          session: widget.lease.session,
          roles: const {'customer', 'merchant'},
          builder: (_, lease) => CloudOrderForm(
            service: widget.lease.session.service,
            lease: lease,
            merchants: widget.merchants,
            initialDetails: reorderDetails,
          ),
        ),
      ),
    );
    if (mounted && _allowed && result == true) Navigator.of(context).pop(true);
  }

  Widget _buildJourneyStepper(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    final status = _effectiveStatus;
    final stageIndex = switch (status) {
      'searching' => 0,
      'accepted' => 1,
      'arrivingPickup' => 2,
      'inTransit' || 'returning' => 3,
      'delivered' => 4,
      _ => -1,
    };
    const stages = [
      '1. Đặt đơn',
      '2. Ghép tài xế',
      '3. Tại điểm lấy',
      '4. Vận chuyển',
      '5. Hoàn tất',
    ];
    final terminalTone = switch (status) {
      'cancelled' => tokens.rose,
      'failed' => tokens.amber,
      'returned' => tokens.violet,
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < stages.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: stageIndex >= i
                      ? (stageIndex == i
                            ? tokens.sapphire.fill
                            : tokens.emerald.fill)
                      : tokens.cardSubtle,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: stageIndex >= i
                        ? (stageIndex == i
                              ? tokens.sapphire.border
                              : tokens.emerald.border)
                        : tokens.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GhstButtonIcon(
                      stageIndex > i
                          ? Icons.check_circle_rounded
                          : (stageIndex == i
                                ? Icons.radio_button_checked_rounded
                                : Icons.circle_outlined),
                      size: 13.5,
                      color: stageIndex >= i
                          ? (stageIndex == i
                                ? tokens.sapphire.foreground
                                : tokens.emerald.foreground)
                          : tokens.inkMuted,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        stages[i],
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: stageIndex >= i
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: stageIndex >= i
                              ? (stageIndex == i
                                    ? tokens.sapphire.foreground
                                    : tokens.emerald.foreground)
                              : tokens.inkSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (terminalTone != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: terminalTone.fill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: terminalTone.border),
            ),
            child: Text(
              'Trạng thái kết thúc: $_status',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: terminalTone.foreground,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLiveJourneyMap(BuildContext context) {
    final pickup = _parsePoint(_details['pickup_lat'], _details['pickup_lng']);
    final dropoff = _parsePoint(
      _details['dropoff_lat'],
      _details['dropoff_lng'],
    );
    if (pickup == null || dropoff == null) return const SizedBox.shrink();
    final tokens = GhstThemeTokens.of(context);
    final rawStops = (_details['extra_stops'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final extraPts = <GeoPoint>[];
    final extraLbls = <String>[];
    for (var i = 0; i < rawStops.length; i++) {
      final pt = _parsePoint(rawStops[i]['lat'], rawStops[i]['lng']);
      if (pt != null) {
        extraPts.add(pt);
        final done =
            _completedCheckpoints.contains('stop:$i') ||
            _completedCheckpoints.contains('stop_${i + 1}');
        extraLbls.add(done ? 'Điểm #${i + 1} ✓' : 'Điểm #${i + 1}');
      }
    }
    final isRoundTrip = _details['is_round_trip'] == true;
    final routePts = <GeoPoint>[
      pickup,
      ...extraPts,
      dropoff,
      if (isRoundTrip && extraPts.length + 2 < 7) pickup,
    ];
    final driverPt = _liveGps != null
        ? _parsePoint(
            _liveGps!['latitude'] ?? _liveGps!['lat'],
            _liveGps!['longitude'] ?? _liveGps!['lng'],
          )
        : null;

    return GhstLuminousCard(
      accentGlow: tokens.sapphire.glow,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 16),
      borderRadius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GhstButtonIcon(
                    Icons.explore_outlined,
                    size: 18,
                    color: tokens.sapphire.icon,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Bản đồ hành trình trực tiếp',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: tokens.ink,
                      ),
                    ),
                  ),
                ],
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _openExternalNavigation,
                icon: const GhstButtonIcon(Icons.directions_outlined, size: 16),
                label: const Text('Mở trên Google Maps'),
              ),
            ],
          ),
          if (driverPt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Vị trí tài xế cập nhật lúc ${cloudDate(_liveGps!['updated_at'])}',
              style: TextStyle(
                fontSize: 12,
                color: tokens.emerald.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_isActiveJourney)
              Builder(
                builder: (context) {
                  final telemetry = computeLiveTripTelemetry(
                    order: {..._order, 'status': _effectiveStatus},
                    liveGps: _liveGps!,
                    completedCheckpoints: _completedCheckpoints,
                  );
                  if (telemetry == null) return const SizedBox.shrink();
                  Widget telemetryPill(String text, TonePair tone) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tone.fill,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: tone.border),
                    ),
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: tone.foreground,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  );

                  final etaText = telemetry.etaMinutes == 0
                      ? 'ETA: Đã gần tới'
                      : 'ETA: ~${telemetry.etaMinutes} phút (${formatTelemetryClock(telemetry.estimatedArrival)})';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (telemetry.isArrivingSoon) ...[
                        const SizedBox(height: 8),
                        Container(
                          key: const ValueKey('order-arriving-soon-banner'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.emerald.fill,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: tokens.emerald.border),
                          ),
                          child: Row(
                            children: [
                              GhstButtonIcon(
                                Icons.notifications_active_outlined,
                                size: 17,
                                color: tokens.emerald.icon,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Tài xế sắp đến ${telemetry.targetLabel} (còn ~${formatTelemetryDistance(telemetry.straightDistanceMeters)})${_details['require_otp'] == true ? ' — vui lòng chuẩn bị mã OTP 6 số.' : ' — vui lòng chú ý điện thoại.'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: tokens.emerald.foreground,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        key: const ValueKey('order-live-telemetry-strip'),
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: tokens.cardSubtle,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            telemetryPill(
                              'Đích: ${telemetry.targetLabel}',
                              tokens.sapphire,
                            ),
                            telemetryPill(
                              'Còn ~${formatTelemetryDistance(telemetry.estimatedRoadMeters)}',
                              tokens.violet,
                            ),
                            telemetryPill(etaText, tokens.cyan),
                            if (telemetry.usedLiveSpeed)
                              telemetryPill(
                                '${telemetry.effectiveSpeedKmh.round()} km/h',
                                tokens.sapphire,
                              ),
                            telemetryPill(
                              formatGpsAgeLabel(telemetry.gpsAgeSeconds),
                              telemetry.isSignalStale
                                  ? tokens.amber
                                  : tokens.emerald,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
          if (widget.weatherService != null ||
              EnvConfig.deliveryApiBaseUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            DeliveryWeatherStrip(
              point: driverPt ?? dropoff,
              service: widget.weatherService,
            ),
          ],
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Map3dPerspectiveWidget(
              key: ValueKey('order-journey-map-${_order['id']}'),
              height: 290,
              showTopBanner: false,
              mode: MapViewMode.customerLiveTracking,
              customFleetDrivers: const [],
              useGlobalFallbackRoute: false,
              routePoints: routePts,
              explicitDropoffPoint: dropoff,
              extraStopPoints: extraPts,
              extraStopLabels: extraLbls,
              driverLocation: driverPt,
              driverLabel: 'Tài xế đang giao',
              pickupLabel: 'Lấy [A]',
              dropoffLabel: 'Giao [B]',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartnerAndReviewSection(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    final cards = <Widget>[];

    if (_driverProfile != null && !_isAssignedDriver) {
      final name = _text(_driverProfile!['full_name']);
      final phone = '${_driverProfile!['phone'] ?? ''}'.trim();
      final masked =
          '${_driverProfile!['masked_phone'] ?? ''}'.trim().isNotEmpty
          ? '${_driverProfile!['masked_phone']}'.trim()
          : maskPhoneNumber(phone);
      final ratingAvg = (_driverProfile!['rating_avg'] as num? ?? 0).toDouble();
      final ratingCount = (_driverProfile!['rating_count'] as num? ?? 0)
          .toInt();
      cards.add(
        GhstLuminousCard(
          accentGlow: tokens.emerald.glow,
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(top: 16),
          borderRadius: 16,
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    backgroundColor: tokens.emerald.fill,
                    foregroundColor: tokens.emerald.foreground,
                    child: const GhstButtonIcon(Icons.two_wheeler_rounded),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tài xế phụ trách: $name',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: tokens.ink,
                          ),
                        ),
                        Text(
                          ratingCount > 0
                              ? '★ ${ratingAvg.toStringAsFixed(1)} · $ratingCount đánh giá${masked.isNotEmpty ? ' · $masked' : ''}'
                              : (masked.isNotEmpty
                                    ? 'Số ẩn bảo mật: $masked'
                                    : 'Đối tác tài xế đã xác minh'),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: tokens.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (phone.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('details-safe-contact-driver'),
                      onPressed: () => showMaskedContactSheet(
                        context: context,
                        roleLabel: 'Tài xế phụ trách',
                        contactName: name,
                        rawPhone: phone,
                        maskedPhone: masked,
                        onCall: _launchPhoneCall,
                        onSendQuickMessage: _sendOrderChat,
                        quickPresets: const [
                          'Vui lòng gọi trước 5 phút',
                          'Tôi đang chờ tại sảnh',
                          'Gửi tại lễ tân giúp tôi',
                        ],
                      ),
                      icon: const GhstButtonIcon(
                        Icons.shield_outlined,
                        size: 16,
                      ),
                      label: const Text('Liên hệ an toàn'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _launchPhoneCall(phone),
                      icon: const GhstButtonIcon(Icons.call_outlined, size: 17),
                      label: const Text('Gọi tài xế'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
    }

    if (_isAssignedDriver ||
        (_isDriverRole && _effectiveStatus == 'searching')) {
      final senderName = _senderProfile != null
          ? _text(_senderProfile!['full_name'])
          : 'Người gửi đơn';
      final senderPhone = '${_senderProfile?['phone'] ?? ''}'.trim();
      final senderMasked =
          '${_senderProfile?['masked_phone'] ?? ''}'.trim().isNotEmpty
          ? '${_senderProfile?['masked_phone']}'.trim()
          : maskPhoneNumber(senderPhone);
      final recipientName = _text(_details['recipient_name']);
      final recipientPhone = '${_details['recipient_phone'] ?? ''}'.trim();
      final recipientMasked =
          '${_order['recipient_masked_phone'] ?? ''}'.trim().isNotEmpty
          ? '${_order['recipient_masked_phone']}'.trim()
          : maskPhoneNumber(recipientPhone);
      if (senderPhone.isNotEmpty || recipientPhone.isNotEmpty) {
        cards.add(
          GhstLuminousCard(
            accentGlow: tokens.sapphire.glow,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(top: 16),
            borderRadius: 16,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Liên hệ chuyến giao · Người gửi: $senderName',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: tokens.ink,
                      ),
                    ),
                    Text(
                      'Che số bảo mật: Người gửi $senderMasked · Người nhận $recipientMasked',
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.inkSecondary,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (recipientPhone.isNotEmpty)
                      OutlinedButton.icon(
                        key: const ValueKey('details-safe-contact-recipient'),
                        onPressed: () => showMaskedContactSheet(
                          context: context,
                          roleLabel: 'Người nhận hàng',
                          contactName: recipientName,
                          rawPhone: recipientPhone,
                          maskedPhone: recipientMasked,
                          onCall: _launchPhoneCall,
                          onSendQuickMessage: _sendOrderChat,
                          quickPresets: const [
                            'Tài xế đang trên đường giao đến',
                            'Tài xế đã tới điểm giao hàng',
                            'Vui lòng để ý điện thoại nhận hàng',
                          ],
                        ),
                        icon: const GhstButtonIcon(
                          Icons.shield_outlined,
                          size: 16,
                        ),
                        label: const Text('Liên hệ an toàn'),
                      ),
                    if (senderPhone.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => _launchPhoneCall(senderPhone),
                        icon: const GhstButtonIcon(
                          Icons.call_outlined,
                          size: 16,
                        ),
                        label: const Text('Gọi người gửi'),
                      ),
                    if (recipientPhone.isNotEmpty)
                      FilledButton.tonalIcon(
                        onPressed: () => _launchPhoneCall(recipientPhone),
                        icon: const GhstButtonIcon(
                          Icons.phone_forwarded_outlined,
                          size: 16,
                        ),
                        label: const Text('Gọi người nhận'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
    }

    if (_driverReview != null) {
      final stars = (_driverReview!['rating'] as num? ?? 5).toInt();
      final comment =
          '${_driverReview!['body'] ?? _driverReview!['comment'] ?? ''}'.trim();
      final reply = '${_driverReview!['reply'] ?? ''}'.trim();
      cards.add(
        GhstLuminousCard(
          accentGlow: tokens.amber.glow,
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(top: 16),
          borderRadius: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GhstButtonIcon(
                    Icons.stars_rounded,
                    color: tokens.amber.icon,
                    size: 19,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Đánh giá chuyến giao · $stars/5 sao',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: tokens.ink,
                      ),
                    ),
                  ),
                ],
              ),
              if (comment.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(comment, style: TextStyle(color: tokens.ink)),
              ],
              if (reply.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: tokens.cardSubtle,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Text(
                    'Phản hồi của tài xế: $reply',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: tokens.inkSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: cards,
    );
  }

  Widget _buildOrderLiveChatCard(BuildContext context) {
    final canChat =
        _isOwner ||
        _isAssignedDriver ||
        _isMerchantOrOperator ||
        _isShopStaffViewer;
    if (!canChat) return const SizedBox.shrink();
    final tokens = GhstThemeTokens.of(context);
    final quickReplies = _isAssignedDriver
        ? const [
            'Đang trên đường đến',
            'Tài xế đã tới điểm hẹn',
            'Vui lòng để ý điện thoại',
          ]
        : const [
            'Tôi đang chờ tại điểm lấy',
            'Vui lòng gọi trước 5 phút',
            'Gửi tại lễ tân giúp tôi',
          ];

    return GhstLuminousCard(
      accentGlow: tokens.violet.glow,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(top: 16),
      borderRadius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GhstButtonIcon(
                Icons.forum_outlined,
                size: 18,
                color: tokens.violet.icon,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Trao đổi trực tiếp chuyến giao',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: tokens.ink,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Làm mới tin nhắn chuyến giao',
                onPressed: _chatBusy ? null : _refreshLiveSnapshot,
                icon: const GhstButtonIcon(Icons.sync, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_chatMessages.isEmpty)
            Text(
              'Chưa có tin nhắn nào giữa khách hàng và tài xế trên chuyến này.',
              style: TextStyle(fontSize: 12.5, color: tokens.inkSecondary),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _chatMessages.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final msg = _chatMessages[index];
                  final mine = msg['sender_id'] == _userId;
                  final senderRole = switch (msg['sender_role']) {
                    'driver' => 'Tài xế',
                    'merchant' => 'Cửa hàng',
                    'operator' => 'Điều hành',
                    _ => 'Khách hàng',
                  };
                  final senderName = '${msg['sender_name'] ?? ''}'.trim();
                  final senderHeader = senderName.isNotEmpty
                      ? '$senderRole · $senderName · ${cloudDate(msg['created_at'])}'
                      : '$senderRole · ${cloudDate(msg['created_at'])}';
                  final msgText = '${msg['text'] ?? msg['body'] ?? ''}';
                  final isIncident = isDriverIncidentMessage(msgText);
                  return Align(
                    alignment: mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isIncident
                            ? tokens.amber.fill
                            : mine
                            ? tokens.sapphire.fill
                            : tokens.cardSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isIncident
                              ? tokens.amber.border
                              : mine
                              ? tokens.sapphire.border
                              : tokens.border,
                          width: isIncident ? 1.4 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isIncident
                                ? 'CẢNH BÁO SỰ CỐ · $senderHeader'
                                : senderHeader,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: isIncident
                                  ? tokens.amber.foreground
                                  : mine
                                  ? tokens.sapphire.foreground
                                  : tokens.inkMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          SelectableText(
                            msgText,
                            style: TextStyle(fontSize: 13, color: tokens.ink),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          if (_isActiveJourney) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chip in quickReplies)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: const GhstButtonIcon.glyph(
                      GhstActionKind.chat,
                      size: 14,
                    ),
                    label: Text(chip, style: const TextStyle(fontSize: 11.5)),
                    onPressed: _chatBusy ? null : () => _sendOrderChat(chip),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('order-live-chat-input'),
                    controller: _chatCtrl,
                    enabled: !_chatBusy,
                    maxLength: 500,
                    onSubmitted: (_) => _sendOrderChat(),
                    decoration: const InputDecoration(
                      hintText: 'Nhắn cho đối tác trên chuyến giao...',
                      isDense: true,
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const ValueKey('order-live-chat-send'),
                  onPressed: _chatBusy ? null : _sendOrderChat,
                  icon: const GhstButtonIcon(Icons.send_rounded, size: 16),
                  label: const Text('Gửi'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDriverAndCustomerOperationsBar(BuildContext context) {
    final status = _effectiveStatus;
    final carrier = _order['fulfillment_provider'] == 'ghn';
    final canOperateDriver =
        !carrier && (_isAssignedDriver || widget.lease.session.isOperator);
    final canClaimFromDetails =
        !carrier &&
        status == 'searching' &&
        _order['driver_id'] == null &&
        _isDriverRole &&
        !_isOwner;
    final rawStops = (_details['extra_stops'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final isRoundTrip = _details['is_round_trip'] == true;

    final buttons = <Widget>[
      if (canClaimFromDetails)
        FilledButton.icon(
          key: const ValueKey('details-action-claim'),
          onPressed: _busy ? null : () => _executeTransition('claim'),
          icon: const GhstButtonIcon(Icons.electric_moped_rounded),
          label: const Text('Nhận chuyến giao'),
        ),
      if (!carrier &&
          status == 'searching' &&
          _order['merchant_ready'] != true &&
          _isMerchantOrOperator)
        FilledButton.tonalIcon(
          onPressed: _busy ? null : () => _executeTransition('ready'),
          icon: const GhstButtonIcon(Icons.storefront_outlined),
          label: const Text('Sẵn sàng lấy hàng'),
        ),
      if (canOperateDriver) ...[
        if (status == 'accepted')
          FilledButton.icon(
            key: const ValueKey('details-action-arrive'),
            onPressed: _busy ? null : () => _executeTransition('arrive'),
            icon: const GhstButtonIcon(Icons.place_outlined),
            label: const Text('Báo đã đến điểm lấy'),
          ),
        if (status == 'arrivingPickup')
          FilledButton.icon(
            key: const ValueKey('details-action-pickup'),
            onPressed: _busy ? null : () => _executeTransition('pickup'),
            icon: const GhstButtonIcon(Icons.inventory_2_outlined),
            label: const Text('Xác nhận đã lấy hàng'),
          ),
        if (const {
          'accepted',
          'arrivingPickup',
          'inTransit',
          'returning',
        }.contains(status))
          OutlinedButton.icon(
            key: const ValueKey('details-action-push-gps'),
            onPressed: _busy ? null : _broadcastRealDriverGps,
            icon: const GhstButtonIcon(Icons.my_location_rounded),
            label: const Text('Phát định vị GPS'),
          ),
        if (const {'inTransit', 'returning'}.contains(status)) ...[
          for (var i = 0; i < rawStops.length; i++)
            (_completedCheckpoints.contains('stop:$i') ||
                    _completedCheckpoints.contains('stop_${i + 1}'))
                ? Chip(
                    avatar: const GhstButtonIcon(Icons.check_circle, size: 16),
                    label: Text('Đã qua điểm #${i + 1}'),
                  )
                : OutlinedButton.icon(
                    key: ValueKey('details-checkpoint-stop-$i'),
                    onPressed: _busy
                        ? null
                        : () => _markCheckpoint(
                            'stop:$i',
                            'Đã hoàn tất điểm dừng #${i + 1}',
                          ),
                    icon: const GhstButtonIcon(Icons.flag_outlined),
                    label: Text('Hoàn tất điểm dừng #${i + 1}'),
                  ),
          if (isRoundTrip)
            (_completedCheckpoints.contains('return_leg') ||
                    _completedCheckpoints.contains('return_origin'))
                ? const Chip(
                    avatar: GhstButtonIcon(Icons.check_circle, size: 16),
                    label: Text('Đã quay về điểm lấy'),
                  )
                : OutlinedButton.icon(
                    key: const ValueKey('details-checkpoint-return'),
                    onPressed: _busy
                        ? null
                        : () => _markCheckpoint(
                            'return_leg',
                            'Đã quay lại điểm lấy khứ hồi',
                          ),
                    icon: const GhstButtonIcon(Icons.sync_alt_rounded),
                    label: const Text('Xác nhận quay về điểm lấy'),
                  ),
        ],
        if (cloudOrderCanCollectCash(_order))
          OutlinedButton.icon(
            key: const ValueKey('details-action-collect-cash'),
            onPressed: _busy ? null : () => _executeTransition('collect_cash'),
            icon: const GhstButtonIcon(Icons.payments_outlined),
            label: const Text('Thu tiền mặt'),
          ),
        if (status == 'inTransit') ...[
          FilledButton.icon(
            key: const ValueKey('details-action-deliver'),
            onPressed: _busy ? null : () => _executeTransition('deliver'),
            icon: const GhstButtonIcon(Icons.task_alt_rounded),
            label: const Text('Hoàn tất giao hàng'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _executeTransition('fail'),
            icon: const GhstButtonIcon(Icons.report_problem_outlined),
            label: const Text('Báo giao thất bại'),
          ),
        ],
        if (status == 'failed') ...[
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _executeTransition('retry'),
            icon: const GhstButtonIcon(Icons.refresh_rounded),
            label: const Text('Thử giao lại'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _executeTransition('return'),
            icon: const GhstButtonIcon(Icons.keyboard_return_rounded),
            label: const Text('Chuyển hoàn hàng'),
          ),
        ],
        if (status == 'returning')
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _executeTransition('complete_return'),
            icon: const GhstButtonIcon(Icons.assignment_returned_outlined),
            label: const Text('Đã trả hàng cho người gửi'),
          ),
        if (const {
          'accepted',
          'arrivingPickup',
          'inTransit',
          'returning',
        }.contains(status)) ...[
          OutlinedButton.icon(
            key: const ValueKey('details-action-navigate'),
            onPressed: _busy ? null : _openExternalNavigation,
            icon: const GhstButtonIcon(Icons.directions_outlined),
            label: const Text('Chỉ đường Google Maps'),
          ),
          if ('${_details['recipient_phone'] ?? ''}'.trim().isNotEmpty)
            OutlinedButton.icon(
              key: const ValueKey('details-action-call-recipient'),
              onPressed: _busy ? null : _callRecipient,
              icon: const GhstButtonIcon(Icons.call_outlined),
              label: const Text('Gọi người nhận'),
            ),
          OutlinedButton.icon(
            key: const ValueKey('details-action-report-incident'),
            onPressed: _busy || _chatBusy ? null : _reportDriverIncident,
            icon: const GhstButtonIcon(Icons.warning_amber_outlined),
            label: const Text('Báo sự cố chuyến giao'),
          ),
        ],
      ],
      if (!carrier &&
          (_isOwner || _isMerchantOrOperator) &&
          const {'searching', 'accepted', 'arrivingPickup'}.contains(status))
        OutlinedButton.icon(
          key: const ValueKey('details-action-cancel'),
          onPressed: _busy ? null : () => _executeTransition('cancel'),
          icon: const GhstButtonIcon(Icons.cancel_outlined),
          label: const Text('Hủy đơn giao'),
        ),
      if (!carrier &&
          _isOwner &&
          CloudDeliveryInstructionButton.editableStatuses.contains(status))
        CloudDeliveryInstructionButton(
          service: widget.lease.session.service,
          order: _order,
          onUpdated: () => unawaited(_load()),
        ),
    ];

    if (buttons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: buttons),
    );
  }

  Widget _buildStatusPill(
    BuildContext context, {
    required String label,
    required TonePair tone,
    bool pulse = false,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: tone.fill,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: tone.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pulse) ...[
          GhstPulseBeacon(color: tone.icon, size: 8),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: tone.foreground,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildDetailCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required TonePair tone,
    String? badgeText,
    required Widget child,
  }) {
    final tokens = GhstThemeTokens.of(context);
    return GhstLuminousCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      accentGlow: tone.glow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tone.fill,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: tone.border),
                ),
                child: Center(
                  child: GhstButtonIcon(icon, size: 17, color: tone.icon),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: tokens.ink,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (badgeText != null && badgeText.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tone.fill,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: tone.border),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: tone.foreground,
                    ),
                  ),
                ),
            ],
          ),
          Divider(height: 22, color: tokens.border),
          child,
        ],
      ),
    );
  }

  Widget _buildKeyValueRow(
    BuildContext context, {
    required String label,
    required String value,
    Widget? trailing,
    bool tabular = false,
  }) {
    final tokens = GhstThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: tokens.inkMuted,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: tokens.ink,
                    fontFeatures: tabular
                        ? const [FontFeature.tabularFigures()]
                        : null,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpecTile(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final tokens = GhstThemeTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.cardSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: tokens.inkMuted,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: tokens.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerRow(
    BuildContext context, {
    required String label,
    String? value,
    Color? valueColor,
    bool emphasize = false,
    Widget? pillValue,
  }) {
    final tokens = GhstThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                color: tokens.inkMuted,
              ),
            ),
            if (pillValue != null)
              pillValue
            else if (value != null)
              SelectableText(
                value,
                style: TextStyle(
                  fontSize: emphasize ? 14.5 : 13.5,
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? tokens.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackageSpecsCard(
    BuildContext context,
    Map<String, String> summary,
    VehicleClass vehicle,
    String serviceLabel,
  ) {
    final tokens = GhstThemeTokens.of(context);
    final specs = <(String, String)>[
      ('Hàng hóa', summary['Hàng hóa']!),
      ('Khối lượng', summary['Khối lượng']!),
      ('Dịch vụ', serviceLabel),
      ('Loại xe', vehicle.label),
      if ((_details['length_cm'] as num? ?? 0) > 0 &&
          (_details['width_cm'] as num? ?? 0) > 0 &&
          (_details['height_cm'] as num? ?? 0) > 0)
        (
          'Kích thước',
          '${_details['length_cm']} × ${_details['width_cm']} × ${_details['height_cm']} cm',
        ),
      if ((_details['declared_value'] as num? ?? 0) > 0)
        ('Khai giá bảo hiểm', _money(_details['declared_value'])),
    ];
    final buyerNote = '${_details['buyer_note'] ?? ''}'.trim();
    final deliveryInstruction = '${_order['delivery_instruction'] ?? ''}'
        .trim();

    return _buildDetailCard(
      context: context,
      title: 'Kiện hàng',
      icon: Icons.inventory_2_outlined,
      tone: tokens.sapphire,
      badgeText: vehicle.shortLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final twoCols = box.maxWidth >= 300;
              final tileWidth = twoCols
                  ? (box.maxWidth - 10) / 2
                  : box.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final spec in specs)
                    SizedBox(
                      width: tileWidth,
                      child: _buildSpecTile(
                        context,
                        label: spec.$1,
                        value: spec.$2,
                      ),
                    ),
                ],
              );
            },
          ),
          if (buyerNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tokens.cardSubtle,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tokens.border),
              ),
              child: SelectableText(
                'Ghi chú: $buyerNote',
                style: TextStyle(fontSize: 12.5, color: tokens.inkSecondary),
              ),
            ),
          ],
          if (deliveryInstruction.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tokens.amber.fill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tokens.amber.border),
              ),
              child: SelectableText(
                'Chỉ dẫn giao hàng: $deliveryInstruction',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: tokens.amber.foreground,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPricingSummaryCard(
    BuildContext context,
    Map<String, String> summary,
  ) {
    final tokens = GhstThemeTokens.of(context);
    final codValue = (_order['cod_amount'] as num? ?? 0).toInt();
    final paymentStatus = '${_order['payment_status'] ?? 'UNPAID'}';
    final paymentTone = paymentStatus == 'PAID' ? tokens.emerald : tokens.amber;

    return _buildDetailCard(
      context: context,
      title: 'Cước và thu hộ',
      icon: Icons.receipt_long_outlined,
      tone: tokens.emerald,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLedgerRow(
            context,
            label: 'Cước vận chuyển',
            value: summary['Cước vận chuyển']!,
            valueColor: summary.containsKey('Cước cần thanh toán')
                ? null
                : tokens.sapphire.foreground,
            emphasize: !summary.containsKey('Cước cần thanh toán'),
          ),
          if (summary.containsKey('Đổi Xu giảm cước'))
            _buildLedgerRow(
              context,
              label: 'Đổi Xu giảm cước',
              value: summary['Đổi Xu giảm cước']!,
              valueColor: tokens.emerald.foreground,
            ),
          if (summary.containsKey('Cước cần thanh toán'))
            _buildLedgerRow(
              context,
              label: 'Cước cần thanh toán',
              value: summary['Cước cần thanh toán']!,
              valueColor: tokens.sapphire.foreground,
              emphasize: true,
            ),
          _buildLedgerRow(
            context,
            label: 'Tiền thu hộ COD',
            value: summary['Tiền thu hộ COD']!,
            valueColor: codValue > 0 ? tokens.amber.foreground : null,
            emphasize: codValue > 0,
          ),
          Divider(height: 16, color: tokens.border),
          _buildLedgerRow(context, label: 'Trả phí', value: _payer),
          _buildLedgerRow(
            context,
            label: 'Thanh toán cước',
            pillValue: _buildStatusPill(
              context,
              label: _payment,
              tone: paymentTone,
            ),
          ),
          if (summary.containsKey('Tiền mặt cước đã thu'))
            _buildLedgerRow(
              context,
              label: 'Tiền mặt cước đã thu',
              value: summary['Tiền mặt cước đã thu']!,
            ),
          if (summary.containsKey('Tiền mặt COD đã thu'))
            _buildLedgerRow(
              context,
              label: 'Tiền mặt COD đã thu',
              value: summary['Tiền mặt COD đã thu']!,
            ),
          if (summary.containsKey('Thời điểm thu tiền mặt'))
            _buildLedgerRow(
              context,
              label: 'Thời điểm thu tiền mặt',
              value: summary['Thời điểm thu tiền mặt']!,
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryTimelineCard(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    final events = _history!;
    return _buildDetailCard(
      context: context,
      title: 'Lịch sử đơn hàng',
      icon: Icons.timeline_rounded,
      tone: tokens.sapphire,
      badgeText: '${events.length} mốc',
      child: events.isEmpty
          ? Text(
              'Chưa có lịch sử cập nhật.',
              style: TextStyle(color: tokens.inkMuted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < events.length; i++)
                  Builder(
                    builder: (context) {
                      final event = events[i];
                      final isLast = i == events.length - 1;
                      final eventStatus = '${event['status'] ?? ''}';
                      final dotTone = switch (eventStatus) {
                        'delivered' => tokens.emerald,
                        'cancelled' || 'failed' => tokens.rose,
                        'searching' => tokens.amber,
                        'returning' || 'returned' => tokens.violet,
                        _ => tokens.sapphire,
                      };
                      final reason = (event['reason'] as String? ?? '').trim();
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 24,
                              child: Column(
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 3),
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: dotTone.fill,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: dotTone.icon,
                                        width: 2.2,
                                      ),
                                    ),
                                  ),
                                  if (!isLast)
                                    Expanded(
                                      child: Container(
                                        width: 2,
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        color: tokens.borderStrong,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  bottom: isLast ? 0 : 16,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          cloudActions[event['action']] ??
                                              '${event['action'] ?? 'Cập nhật'}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13.5,
                                            color: tokens.ink,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: dotTone.fill,
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: dotTone.border,
                                            ),
                                          ),
                                          child: Text(
                                            cloudStatuses[eventStatus] ??
                                                eventStatus,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: dotTone.foreground,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      cloudDate(event['created_at']),
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: tokens.inkMuted,
                                      ),
                                    ),
                                    if (reason.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: tokens.amber.fill,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: tokens.amber.border,
                                          ),
                                        ),
                                        child: SelectableText(
                                          'Lý do: $reason',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: tokens.amber.foreground,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _allowed && _history != null;
    final summary = visible ? _summary : const <String, String>{};
    final tokens = GhstThemeTokens.of(context);
    final hasPod = (_podPhotoPath ?? '${_order['pod_photo_path'] ?? ''}')
        .trim()
        .isNotEmpty;
    final hasSignature = (_signaturePath ?? '${_order['signature_path'] ?? ''}')
        .trim()
        .isNotEmpty;
    final statusTone = switch (_effectiveStatus) {
      'delivered' => tokens.emerald,
      'cancelled' || 'failed' => tokens.rose,
      'searching' => tokens.amber,
      'returning' || 'returned' => tokens.violet,
      _ => tokens.sapphire,
    };
    final vehicle = VehicleClass.resolve(
      vehicleType: _details['vehicle_type'],
      serviceType: _details['service_type'],
      preferEv: _details['prefer_ev'] == true,
    );
    final serviceLabel =
        cloudServiceTypes[_details['service_type']] ?? 'Tiêu chuẩn';
    final topActionButtons = <Widget>[
      if (_canRepeat)
        FilledButton.icon(
          onPressed: _repeat,
          icon: const GhstButtonIcon(Icons.replay),
          label: const Text('Gửi lại đơn'),
        ),
      if ((_isOwner || widget.lease.session.isOperator) &&
          _details['payment_method'] == 'sender_cash' &&
          _order['payment_status'] != 'PAID')
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => CloudSessionBoundary(
                      session: widget.lease.session,
                      operator: widget.lease.session.isOperator,
                      dialog: true,
                      builder: (_, lease) => CloudCommerceDialog(
                        service: widget.lease.session.service,
                        order: _order,
                        operator: widget.lease.session.isOperator,
                        lease: lease,
                      ),
                    ),
                  );
                  if (mounted && _allowed) await _load();
                },
          icon: const GhstButtonIcon(Icons.qr_code_2_rounded),
          label: const Text('Thanh toán Ngân hàng · Mã QR'),
        ),
      if ((_isOwner || _isMerchantOrOperator) &&
          _details['require_otp'] == true)
        OutlinedButton.icon(
          onPressed: _busy ? null : _showOtp,
          icon: const GhstButtonIcon(Icons.pin_outlined),
          label: const Text('Mã OTP người nhận'),
        ),
      if (_isOwner || _isMerchantOrOperator)
        OutlinedButton.icon(
          onPressed: _busy ? null : _manageShares,
          icon: const GhstButtonIcon(Icons.share_outlined),
          label: const Text('Chia sẻ hành trình'),
        ),
      if (_isOwner || _isMerchantOrOperator || _isAssignedDriver)
        OutlinedButton.icon(
          key: const ValueKey('details-print-waybill'),
          onPressed: _busy
              ? null
              : () => showCloudWaybillA6Dialog(context, order: _order),
          icon: const GhstButtonIcon(Icons.print_outlined),
          label: const Text('In phiếu gửi A6'),
        ),
      if (hasPod)
        OutlinedButton.icon(
          onPressed: _busy ? null : _viewPod,
          icon: const GhstButtonIcon(Icons.photo_camera_outlined),
          label: const Text('Xem ảnh POD'),
        ),
      if (hasSignature)
        OutlinedButton.icon(
          key: const ValueKey('details-view-signature'),
          onPressed: _busy ? null : _viewSignature,
          icon: const GhstButtonIcon(Icons.draw_outlined),
          label: const Text('Xem chữ ký người nhận'),
        ),
      if (_order['batch_group_id'] != null)
        Chip(
          avatar: const GhstButtonIcon.glyph(GhstActionKind.hub, size: 15),
          label: Text('Chuyến ghép #${_order['batch_sequence'] ?? 1}'),
        ),
      if (_isOwner &&
          _effectiveStatus == 'delivered' &&
          _order['driver_id'] != null &&
          _driverReview == null)
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  await showPartnerReviewDialog(
                    context,
                    session: widget.lease.session,
                    targetKind: 'driver',
                    cloudOrderId: '${_order['id']}',
                  );
                  if (mounted && _allowed) {
                    await _refreshLiveSnapshot();
                  }
                },
          icon: const GhstButtonIcon(Icons.star_outline),
          label: const Text('Đánh giá tài xế'),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết đơn hàng'),
        actions: [
          IconButton(
            tooltip: 'Tải lại lịch sử',
            onPressed: _busy || !_allowed ? null : _load,
            icon: const GhstButtonIcon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sao chép thông tin đơn',
            onPressed: visible ? () => _copy(receipt: true) : null,
            icon: const GhstButtonIcon(Icons.content_copy_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (!_allowed)
                    const Text(
                      'Phiên làm việc đã thay đổi. Vui lòng mở lại đơn hàng.',
                    ),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _load,
                        icon: const GhstButtonIcon(Icons.refresh),
                        label: const Text('Thử lại'),
                      ),
                    ),
                  ],
                  if (visible) ...[
                    GhstLuminousCard(
                      accentGlow: statusTone.glow,
                      borderColor: _isActiveJourney
                          ? statusTone.border
                          : tokens.border,
                      padding: const EdgeInsets.all(18),
                      borderRadius: 18,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: SelectableText(
                                      _text(_order['tracking_code']),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.3,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Sao chép mã vận đơn',
                                    onPressed: _copy,
                                    icon: const GhstButtonIcon(
                                      Icons.copy_outlined,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _buildStatusPill(
                                    context,
                                    label: _status,
                                    tone: statusTone,
                                    pulse: _isActiveJourney,
                                  ),
                                  _buildStatusPill(
                                    context,
                                    label: vehicle.label,
                                    tone: tokens.violet,
                                  ),
                                  _buildStatusPill(
                                    context,
                                    label: serviceLabel,
                                    tone: tokens.sapphire,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              GhstButtonIcon(
                                Icons.schedule_outlined,
                                size: 14,
                                color: tokens.inkMuted,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  cloudDate(_order['created_at']),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: tokens.inkMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _buildJourneyStepper(context),
                        ],
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final opsBar = _buildDriverAndCustomerOperationsBar(
                          context,
                        );
                        final hasOps = opsBar is! SizedBox;
                        if (topActionButtons.isEmpty && !hasOps) {
                          return const SizedBox.shrink();
                        }
                        return GhstLuminousCard(
                          margin: const EdgeInsets.only(top: 14),
                          padding: const EdgeInsets.all(14),
                          borderRadius: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (topActionButtons.isNotEmpty)
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: topActionButtons,
                                ),
                              if (hasOps) opsBar,
                            ],
                          ),
                        );
                      },
                    ),
                    _buildLiveJourneyMap(context),
                    _buildPartnerAndReviewSection(context),
                    _buildOrderLiveChatCard(context),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final recipientPhone = summary['Điện thoại']!;
                        final pickupCard = _buildDetailCard(
                          context: context,
                          title: 'Lấy hàng',
                          icon: Icons.trip_origin_rounded,
                          tone: tokens.emerald,
                          badgeText: 'Điểm A',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildKeyValueRow(
                                context,
                                label: 'Địa chỉ',
                                value: summary['Điểm lấy']!,
                              ),
                              if ((_details['scheduled_at'] as String? ?? '')
                                  .isNotEmpty)
                                _buildKeyValueRow(
                                  context,
                                  label: 'Hẹn lấy hàng',
                                  value: cloudDate(_details['scheduled_at']),
                                ),
                            ],
                          ),
                        );
                        final dropoffCard = _buildDetailCard(
                          context: context,
                          title: 'Giao hàng',
                          icon: Icons.location_on_outlined,
                          tone: tokens.rose,
                          badgeText: 'Điểm B',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildKeyValueRow(
                                context,
                                label: 'Địa chỉ',
                                value: summary['Điểm giao']!,
                              ),
                              _buildKeyValueRow(
                                context,
                                label: 'Người nhận',
                                value: summary['Người nhận']!,
                              ),
                              _buildKeyValueRow(
                                context,
                                label: 'Điện thoại',
                                value: recipientPhone,
                                tabular: true,
                                trailing:
                                    recipientPhone != 'Chưa có thông tin' &&
                                        recipientPhone.trim().isNotEmpty
                                    ? IconButton(
                                        visualDensity: VisualDensity.compact,
                                        tooltip: 'Sao chép SĐT người nhận',
                                        onPressed: () async {
                                          final messenger =
                                              ScaffoldMessenger.maybeOf(
                                                context,
                                              );
                                          await Clipboard.setData(
                                            ClipboardData(text: recipientPhone),
                                          );
                                          if (!mounted) return;
                                          messenger?.showSnackBar(
                                            const SnackBar(
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              content: Text(
                                                'Đã sao chép số điện thoại.',
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const GhstButtonIcon(
                                          Icons.content_copy_outlined,
                                          size: 16,
                                        ),
                                      )
                                    : null,
                              ),
                              if (_details['extra_stops'] is List &&
                                  (_details['extra_stops'] as List).isNotEmpty)
                                _buildKeyValueRow(
                                  context,
                                  label: 'Điểm dừng trung gian',
                                  value: (_details['extra_stops'] as List)
                                      .map(
                                        (s) => '${(s as Map)['address'] ?? ''}',
                                      )
                                      .join(' -> '),
                                ),
                            ],
                          ),
                        );
                        return constraints.maxWidth < 680
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  pickupCard,
                                  const SizedBox(height: 14),
                                  dropoffCard,
                                ],
                              )
                            : IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(child: pickupCard),
                                    const SizedBox(width: 16),
                                    Expanded(child: dropoffCard),
                                  ],
                                ),
                              );
                      },
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final packageCard = _buildPackageSpecsCard(
                          context,
                          summary,
                          vehicle,
                          serviceLabel,
                        );
                        final pricingCard = _buildPricingSummaryCard(
                          context,
                          summary,
                        );
                        return constraints.maxWidth < 720
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  packageCard,
                                  const SizedBox(height: 14),
                                  pricingCard,
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: packageCard),
                                  const SizedBox(width: 16),
                                  Expanded(child: pricingCard),
                                ],
                              );
                      },
                    ),
                    if (_order['fulfillment_provider'] == 'ghn') ...[
                      const SizedBox(height: 16),
                      _buildDetailCard(
                        context: context,
                        title: 'Vận chuyển GHN',
                        icon: Icons.local_shipping_outlined,
                        tone: tokens.violet,
                        child: _buildKeyValueRow(
                          context,
                          label: 'Mã vận đơn hãng',
                          value: _text(_order['carrier_code']),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildHistoryTimelineCard(context),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
