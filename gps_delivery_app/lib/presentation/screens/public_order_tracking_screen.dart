import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/gps/smart_dispatch_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/security_and_barcode_utils.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/enums/order_status.dart';
import '../widgets/system_state_screens.dart';

/// Màn hình Theo dõi Hành trình Công khai (/track) không cần đăng nhập (mô hình GrabExpress Share My Ride)
/// Tự động che số điện thoại nhạy cảm (0912***678), hiển thị Bản đồ GPS 3D, Tiến độ đa điểm dừng và Mã OTP nhận hàng.
class PublicOrderTrackingScreen extends StatefulWidget {
  final String? initialQuery;

  const PublicOrderTrackingScreen({super.key, this.initialQuery});

  static String? _extractQueryParamRaw(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final regexMatch = RegExp(r'[?&](?:code|token)=([^&]+)').firstMatch(trimmed);
    if (regexMatch != null) {
      final rawVal = regexMatch.group(1)?.trim() ?? '';
      if (rawVal.isNotEmpty) {
        try {
          return Uri.decodeQueryComponent(rawVal).trim();
        } catch (_) {
          return rawVal;
        }
      }
    }
    final parsed = Uri.tryParse(trimmed);
    final code =
        parsed?.queryParameters['code'] ?? parsed?.queryParameters['token'];
    if (code != null && code.trim().isNotEmpty) {
      return code.trim();
    }
    return null;
  }

  static String? extractQueryFromRouteName(String? routeName) {
    if (routeName != null && routeName.trim().isNotEmpty) {
      final fromRoute = _extractQueryParamRaw(routeName);
      if (fromRoute != null && fromRoute.isNotEmpty) {
        return fromRoute;
      }
    }
    final baseCode =
        Uri.base.queryParameters['code'] ?? Uri.base.queryParameters['token'];
    if (baseCode != null && baseCode.trim().isNotEmpty) {
      return baseCode.trim();
    }
    final frag = Uri.base.fragment;
    if (frag.isNotEmpty) {
      final fromFrag = _extractQueryParamRaw(
        frag.startsWith('/') ? frag : '/$frag',
      );
      if (fromFrag != null && fromFrag.isNotEmpty) {
        return fromFrag;
      }
    }
    return null;
  }

  @override
  State<PublicOrderTrackingScreen> createState() =>
      _PublicOrderTrackingScreenState();
}

class _PublicOrderTrackingScreenState extends State<PublicOrderTrackingScreen> {
  final AppStateStore _store = AppStateStore.instance;
  late final TextEditingController _searchCtrl;
  String _activeQuery = '';

  @override
  void initState() {
    super.initState();
    final initial =
        widget.initialQuery ??
        PublicOrderTrackingScreen.extractQueryFromRouteName(null) ??
        '';
    _activeQuery = initial.trim();
    _searchCtrl = TextEditingController(text: _activeQuery);
    _store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _submitSearch() {
    setState(() {
      _activeQuery = _searchCtrl.text.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final matchedOrder = _activeQuery.isEmpty
        ? null
        : _store.findOrderForPublicTracking(_activeQuery);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.radar_rounded, size: 20, color: AppColors.acid),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tra cứu & Theo dõi Hành trình Trực tiếp',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).pushReplacementNamed('/');
              }
            },
            icon: const Icon(
              Icons.login_rounded,
              size: 16,
              color: AppColors.acid,
            ),
            label: const Text(
              'Trang chủ',
              style: TextStyle(
                color: AppColors.acid,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.ink, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NHẬP MÃ VẬN ĐƠN HOẶC MÃ CHIA SẺ HÀNH TRÌNH',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Người nhận có thể theo dõi vị trí tài xế GPS 3D thời gian thực mà không cần đăng nhập tài khoản. SĐT cá nhân được che tự động bảo vệ quyền riêng tư.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              onSubmitted: (_) => _submitSearch(),
                              decoration: const InputDecoration(
                                hintText:
                                    'Ví dụ: GH-2026... hoặc TRK-...',
                                prefixIcon: Icon(Icons.search_rounded),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.violet,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                            onPressed: _submitSearch,
                            icon: const Icon(
                              Icons.gps_fixed_rounded,
                              size: 17,
                            ),
                            label: const Text('Tra cứu'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_activeQuery.isEmpty)
                  _buildEmptyOrNotFoundBox(
                    title: 'Sẵn sàng tra cứu hành trình GPS trực tiếp',
                    subtitle:
                        'Nhập mã vận đơn do người gửi hoặc cửa hàng chia sẻ để xem vị trí tài xế 3D, lộ trình đa điểm dừng và mã OTP nhận hàng.',
                    icon: Icons.share_location_rounded,
                  )
                else if (matchedOrder == null)
                  _buildEmptyOrNotFoundBox(
                    title: 'Không tìm thấy vận đơn "$_activeQuery"',
                    subtitle:
                        'Vui lòng kiểm tra lại chính xác mã vận đơn (VD: GH-...) hoặc liên kết chia sẻ từ người gửi.',
                    icon: Icons.find_in_page_outlined,
                  )
                else
                  _buildLivePublicTrackingDetail(matchedOrder),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyOrNotFoundBox({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ink, width: 1.4),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F1E8),
              border: Border.all(color: AppColors.ink),
            ),
            child: Icon(icon, size: 30, color: AppColors.violet),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLivePublicTrackingDetail(ActiveOrderRecord order) {
    final remMeters = _store.distanceFromDriverToOrderDropoffMeters(order);
    final etaMinutes = (remMeters / 500.0).ceil().clamp(1, 60);
    final deliveryOtp4 = SecurityAndBarcodeUtils.generateOrderDeliveryOtp4(
      order.trackingCode,
    );
    final isSearching =
        order.status == OrderStatus.searching ||
        order.status == OrderStatus.draft;
    final isAccepted =
        order.status == OrderStatus.accepted ||
        order.status == OrderStatus.arrivingPickup;
    final isInTransit = order.status == OrderStatus.inTransit;
    final isDelivered = order.status == OrderStatus.delivered;
    final isCancelled = order.status == OrderStatus.cancelled;
    final isFailedOrReturning =
        order.status == OrderStatus.failed ||
        order.status == OrderStatus.returning;

    final assignedDriver = order.assignedDriverName == null
        ? null
        : _store.drivers
              .where(
                (d) =>
                    d.fullName.trim().toLowerCase() ==
                    order.assignedDriverName!.trim().toLowerCase(),
              )
              .firstOrNull;
    final maskedRecipientPhone = SecurityAndBarcodeUtils.maskPhoneNumber(
      order.recipientPhone,
      shouldMask: true,
    );
    final maskedDriverPhone = assignedDriver == null
        ? 'Đang điều phối'
        : SecurityAndBarcodeUtils.maskPhoneNumber(
            assignedDriver.phone,
            shouldMask: true,
          );
    final distRatio = order.distanceMeters > 0
        ? (1.0 - (remMeters / order.distanceMeters).clamp(0.0, 1.0))
        : 0.0;
    final mapProgress = isDelivered
        ? 1.0
        : (isSearching || isCancelled || isFailedOrReturning
              ? 0.0
              : distRatio.clamp(isInTransit ? 0.25 : 0.08, 0.95));
    final shareLink =
        'https://ghst.vn/#/track?code=${Uri.encodeComponent(order.trackingCode)}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ink, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vận đơn ${order.trackingCode.startsWith('#') ? order.trackingCode : '#${order.trackingCode}'} • ${order.serviceType.displayName}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.violet,
                    ),
                  ),
                  Text(
                    isDelivered
                        ? 'Đã giao thành công • Hoàn tất 100%'
                        : isCancelled
                        ? 'Đã hủy • ${order.cancelReason ?? "Khách hủy"}'
                        : isSearching
                        ? 'Trạng thái: ${order.status.displayName}'
                        : 'Dự kiến giao: ~$etaMinutes phút nữa (${(remMeters / 1000).toStringAsFixed(2)} km)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (!isDelivered && !isCancelled)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        border: Border.all(color: const Color(0xFF16A34A)),
                      ),
                      child: Text(
                        'Mã OTP nhận hàng: $deliveryOtp4',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF166534),
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: shareLink));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Đã sao chép link chia sẻ: $shareLink'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.link_rounded, size: 16),
                    label: const Text('Sao chép Link'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (order.preferEcoEv || order.co2SavedGrams > 0)
                _buildPublicFeatureBadge(
                  icon: Icons.eco_rounded,
                  label:
                      'Giao Xanh EV • Giảm ${order.co2SavedGrams.toStringAsFixed(0)}g CO₂',
                  bg: const Color(0xFFDCFCE7),
                  fg: const Color(0xFF166534),
                ),
              if (order.batchGroupId != null &&
                  order.batchGroupId!.trim().isNotEmpty)
                _buildPublicFeatureBadge(
                  icon: Icons.hub_rounded,
                  label: 'Ghép đơn cùng hướng 2H (${order.batchGroupId})',
                  bg: const Color(0xFFEDE9FE),
                  fg: const Color(0xFF5B33E6),
                ),
              if (order.declaredValueVnd > 0)
                _buildPublicFeatureBadge(
                  icon: Icons.verified_user_rounded,
                  label:
                      'Bảo hiểm hàng hóa ${CurrencyFormatter.formatVnd(order.declaredValueVnd)}',
                  bg: const Color(0xFFFFF7ED),
                  fg: const Color(0xFF9A3412),
                ),
              if (order.isRoundTrip)
                _buildPublicFeatureBadge(
                  icon: Icons.sync_alt_rounded,
                  label: 'Giao khứ hồi 2 chiều',
                  bg: const Color(0xFFE0F2FE),
                  fg: const Color(0xFF075985),
                ),
              if (order.extraStopCount > 0)
                _buildPublicFeatureBadge(
                  icon: Icons.alt_route_rounded,
                  label: 'Đa điểm dừng (+${order.extraStopCount} trạm phụ)',
                  bg: const Color(0xFFFCE7F3),
                  fg: const Color(0xFF9D174D),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Map3dPerspectiveWidget(
            height: 360,
            mode: MapViewMode.customerLiveTracking,
            is3dMode: _store.isMap3dEnabled,
            speedKmh: (isAccepted || isInTransit) ? _store.currentSpeedKmh : 0.0,
            onToggle3d: _store.toggleMap3d,
            driverLocation: _store.verifiedLocationForOrder(order),
            progressFraction: mapProgress,
            routePoints: SmartDispatchEngine.generateRoutePolyline(
              order.pickupLocation,
              order.dropoffLocation,
              segments: 10,
            ),
            pickupLabel: '[A] Điểm lấy',
            dropoffLabel: '[B] Điểm giao',
            nextTurnInstruction: isDelivered
                ? 'Đơn ${order.trackingCode} đã giao hoàn tất'
                : isSearching
                ? 'Đang điều phối tài xế gần điểm lấy hàng'
                : 'Tài xế cách điểm giao ${(remMeters / 1000).toStringAsFixed(2)} km (~$etaMinutes phút)',
            roadName: '${order.pickupAddress} → ${order.dropoffAddress}',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F1E8),
              border: Border.all(color: AppColors.ink),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStepPill(
                  '1. Đã tạo đơn',
                  done: !isSearching && !isCancelled,
                  active: isSearching,
                ),
                _buildStepPill(
                  '2. Tài xế nhận',
                  done: isInTransit || isDelivered,
                  active: isAccepted,
                ),
                _buildStepPill(
                  '3. Đang giao',
                  done: isDelivered,
                  active: isInTransit,
                ),
                _buildStepPill(
                  '4. Hoàn thành',
                  done: isDelivered,
                  active: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border.all(color: AppColors.ink),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'THÔNG TIN GIAO NHẬN (ĐÃ CHE SĐT BẢO MẬT)',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '• Người gửi: ${order.customerName} | Điểm lấy: ${order.pickupAddress}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '• Người nhận: ${order.recipientName} ($maskedRecipientPhone) | Điểm giao: ${order.dropoffAddress}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '• Tài xế phụ trách: ${order.assignedDriverName ?? "Đang tìm tài xế"} • Biển số: ${order.assignedDriverPlate ?? "---"} • SĐT: $maskedDriverPhone',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '• Thu hộ COD: ${CurrencyFormatter.formatVnd(order.codAmount)} • Tổng cước: ${CurrencyFormatter.formatVnd(order.totalAmount)} (${order.paymentMethod})',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _store.orderStopsFor(order.id),
            builder: (context, snapshot) {
              final stops = snapshot.data ?? const [];
              if (stops.length <= 2) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.ink),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TIẾN ĐỘ LỘ TRÌNH ĐA ĐIỂM DỪNG (${stops.length} TRẠM)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: AppColors.violet,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...stops.map((st) {
                      final seq = (st['sequence_no'] as num?)?.toInt() ?? 0;
                      final stopType = (st['stop_type'] ?? 'DROPOFF').toString();
                      final isDone =
                          (st['status'] ?? '').toString() == 'COMPLETED' ||
                          isDelivered;
                      final rawPhone = (st['recipient_phone'] ?? '').toString();
                      final maskedStopPhone = rawPhone.isEmpty
                          ? ''
                          : SecurityAndBarcodeUtils.maskPhoneNumber(
                              rawPhone,
                              shouldMask: true,
                            );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Icon(
                              isDone
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 16,
                              color: isDone
                                  ? AppColors.success
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '[Trạm ${seq + 1} - $stopType] ${st['address']}'
                                '${maskedStopPhone.isNotEmpty ? " • $maskedStopPhone" : ""}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: isDone
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              color: isDone
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFF1F5F9),
                              child: Text(
                                isDone ? 'ĐÃ XONG' : 'ĐANG CHỜ',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: isDone
                                      ? const Color(0xFF166534)
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPublicFeatureBadge({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: fg.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepPill(
    String label, {
    required bool done,
    required bool active,
  }) {
    final color = done
        ? AppColors.success
        : active
        ? AppColors.violet
        : AppColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          done
              ? Icons.check_circle_rounded
              : active
              ? Icons.timelapse_rounded
              : Icons.circle_outlined,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: (done || active) ? FontWeight.w800 : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
