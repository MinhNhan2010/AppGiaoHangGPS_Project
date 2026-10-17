import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/gps/gps_integrity_validator.dart';
import '../../core/gps/smart_dispatch_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/security_and_barcode_utils.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/enums/order_status.dart';
import '../widgets/animated_3d_ui_icons.dart';
import '../widgets/system_state_screens.dart';

/// Phân hệ Tài xế (Driver App) - 9 màn hình (Hình 8.15 - Hình 8.23)
/// Bao phủ đầy đủ UC13 - UC21 theo Thiết kế Giao diện Chương 8.2
class DriverSubsystemEntry extends StatefulWidget {
  const DriverSubsystemEntry({super.key});

  @override
  State<DriverSubsystemEntry> createState() => _DriverSubsystemEntryState();
}

class _DriverSubsystemEntryState extends State<DriverSubsystemEntry> {
  final AppStateStore _store = AppStateStore.instance;
  int _selectedScreenIndex = 1; // Mặc định: UC14 Trang chủ Tài xế Online/Offline

  // UC13: Hồ sơ đăng ký tài xế
  final TextEditingController _drvNameCtrl =
      TextEditingController(text: 'Nguyễn Văn Nam');
  final TextEditingController _drvCitizenCtrl =
      TextEditingController(text: '001095012345');
  final TextEditingController _drvPlateCtrl =
      TextEditingController(text: '29A-123.45');
  String _vehicleType = 'Xe máy';

  // UC15: Countdown 28s & Smart Dispatch
  int _countdownSeconds = 28;
  Timer? _dispatchCountdownTimer;
  final Set<String> _rejectedDriverIds = {};

  // UC18: POD & OTP 4 số
  final TextEditingController _podOtpCtrl =
      TextEditingController(text: '4829');
  final TextEditingController _podRecipientCtrl =
      TextEditingController(text: 'Nguyễn Thị Minh An');

  // UC19: Rút tiền Ví tài xế
  final TextEditingController _withdrawAmountCtrl =
      TextEditingController(text: '1000000');
  String _selectedBank = 'Vietcombank - 007100****889';

  // UC20: Báo cáo sự cố
  String _incidentType = 'Kẹt xe nghiêm trọng / Ngập nước';
  final TextEditingController _incidentNoteCtrl = TextEditingController();

  // UC21: Thống kê hiệu suất
  String _statsPeriod = 'Tuần này';

  static const List<String> _screenTitles = [
    '8.15: UC13 Đăng ký & Tải giấy tờ KYC',
    '8.16: UC14 Trang chủ & Gạt Online/Offline',
    '8.17: UC15 Nhận cuốc xe mới (28s)',
    '8.18: UC16 Điều hướng 3D Turn-by-Turn',
    '8.19: UC17 Cập nhật tiến độ chuyến giao',
    '8.20: UC18 Chụp ảnh POD & Nhập OTP',
    '8.21: UC19 Ví thu nhập & Rút tiền',
    '8.22: UC20 Báo cáo sự cố trên đường',
    '8.23: UC21 Thống kê hiệu suất (Dark Mode)',
  ];

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _toggleDispatchTimer() {
    if (_dispatchCountdownTimer?.isActive ?? false) {
      _dispatchCountdownTimer?.cancel();
      setState(() {});
      return;
    }
    _dispatchCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_countdownSeconds > 1) {
          _countdownSeconds--;
        } else {
          _countdownSeconds = 28;
          t.cancel();
          _reassignToNextCandidate();
        }
      });
    });
    setState(() {});
  }

  void _reassignToNextCandidate() {
    final targetOrder = _store.orders.first;
    final ranked = SmartDispatchEngine.rankDriversForPickup(
      pickupLocation: targetOrder.pickupLocation,
      drivers: _store.drivers,
      excludedDriverIds: _rejectedDriverIds,
    );
    if (ranked.isNotEmpty) {
      _rejectedDriverIds.add(ranked.first.driver.id);
    }
  }

  @override
  void dispose() {
    _dispatchCountdownTimer?.cancel();
    _store.removeListener(_onStoreChanged);
    _drvNameCtrl.dispose();
    _drvCitizenCtrl.dispose();
    _drvPlateCtrl.dispose();
    _podOtpCtrl.dispose();
    _podRecipientCtrl.dispose();
    _withdrawAmountCtrl.dispose();
    _incidentNoteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OfflineQueueBanner(store: _store),
        _buildScreenSelectorBar(),
        const SizedBox(height: AppSpacing.md),
        _buildActiveDriverScreen(context),
      ],
    );
  }

  Widget _buildScreenSelectorBar() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _screenTitles.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, index) {
          final isSelected = _selectedScreenIndex == index;
          return ChoiceChip(
            label: Text(
              _screenTitles[index],
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.surface : AppColors.textPrimary,
              ),
            ),
            selected: isSelected,
            selectedColor: AppColors.primary,
            backgroundColor: AppColors.surface,
            onSelected: (_) => setState(() => _selectedScreenIndex = index),
          );
        },
      ),
    );
  }

  Widget _buildActiveDriverScreen(BuildContext context) {
    switch (_selectedScreenIndex) {
      case 0:
        return _buildDriverKycRegistrationView();
      case 1:
        return _buildDriverHomeOnlineView();
      case 2:
        return _buildIncomingOrderPopupView();
      case 3:
        return _buildTurnByTurnNavigationView();
      case 4:
        return _buildTripStepProgressView();
      case 5:
        return _buildPodConfirmationView();
      case 6:
        return _buildDriverWalletView();
      case 7:
        return _buildRoadIncidentReportView();
      case 8:
        return _buildDarkModeAnalyticsView();
      default:
        return _buildDriverHomeOnlineView();
    }
  }

  /// Hình 8.15: UC13 Đăng ký tài khoản Tài xế & Tải hồ sơ pháp lý
  Widget _buildDriverKycRegistrationView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.15: Đăng ký Đối tác Tài xế & Hồ sơ Pháp lý (UC13)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _drvNameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Họ và tên tài xế'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _drvCitizenCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Số CCCD (12 số)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _drvPlateCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Biển kiểm soát xe',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _vehicleType,
                    decoration:
                        const InputDecoration(labelText: 'Loại phương tiện'),
                    items: ['Xe máy', 'Xe tải 500kg', 'Xe Van 1 tấn']
                        .map(
                          (v) => DropdownMenuItem(value: v, child: Text(v)),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _vehicleType = v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Hồ sơ đính kèm bắt buộc (Đã tải lên):',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                Chip(
                  avatar: Icon(Icons.check_circle, color: AppColors.success),
                  label: Text('1. CCCD Mặt trước & Mặt sau'),
                ),
                Chip(
                  avatar: Icon(Icons.check_circle, color: AppColors.success),
                  label: Text('2. Giấy phép lái xe (Hạng A1/B2)'),
                ),
                Chip(
                  avatar: Icon(Icons.check_circle, color: AppColors.success),
                  label: Text('3. Cavet / Đăng ký xe chính chủ'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Đã gửi hồ sơ KYC sang cổng Admin xét duyệt (UC24)!',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Gửi hồ sơ chờ duyệt'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.16: UC14 Trang chủ Tài xế & Gạt trạng thái Online/Offline
  Widget _buildDriverHomeOnlineView() {
    final policy = GpsIntegrityValidator.resolvePolicy(
      batteryLevelPercent: _store.batteryPercent,
      isCharging: false,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Hình 8.16: Trang chủ Tài xế & Trạng thái Hoạt động (UC14)',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                Switch(
                  value: _store.isDriverOnline,
                  activeThumbColor: AppColors.success,
                  onChanged: (v) {
                    setState(() => _store.isDriverOnline = v);
                  },
                ),
                Text(
                  _store.isDriverOnline ? 'ĐANG ONLINE' : 'NGHỈ NGƠI',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _store.isDriverOnline
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Map3dPerspectiveWidget(
              is3dMode: _store.isMap3dEnabled,
              speedKmh: _store.currentSpeedKmh,
              onToggle3d: _store.toggleMap3d,
              nextTurnInstruction: _store.isDriverOnline
                  ? 'Đang phát sóng GPS • Chu kỳ lấy mẫu: ${policy.pingIntervalSeconds}s'
                  : 'Đã ngắt phát sóng GPS nền',
              roadName: 'Khu vực trung tâm Quận 1',
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _kpiTile(
                    'Thu nhập hôm nay',
                    '450.000 đ',
                    AppColors.accent,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _kpiTile('Số chuyến hoàn tất', '8 chuyến', AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _kpiTile('Điểm đánh giá', '4.9 ★', AppColors.success),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Hình 8.17: UC15 Nhận thông báo đơn hàng mới (Countdown 28s & Smart Dispatch RULE-DSP-01..04)
  Widget _buildIncomingOrderPopupView() {
    final targetOrder = _store.orders.first;
    final rankedCandidates = SmartDispatchEngine.rankDriversForPickup(
      pickupLocation: targetOrder.pickupLocation,
      drivers: _store.drivers,
      excludedDriverIds: _rejectedDriverIds,
    );
    final topCandidate =
        rankedCandidates.isNotEmpty ? rankedCandidates.first : null;
    final isTimerRunning = _dispatchCountdownTimer?.isActive ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Hình 8.17: Popup Nhận Cuốc Xe Mới (UC15 - Smart Dispatch)',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                InkWell(
                  onTap: _toggleDispatchTimer,
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor:
                        isTimerRunning ? AppColors.danger : AppColors.accent,
                    child: Text(
                      '${_countdownSeconds}s',
                      style: const TextStyle(
                        color: AppColors.surface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (topCandidate != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Animated3dIconBadge(
                      style: Icon3dStyle.gpsPinRadar,
                      size: 48,
                      showRadarPulse: true,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ứng viên #1 (Bán kính ${topCandidate.searchRadiusTierMeters ~/ 1000}km): ${topCandidate.driver.fullName} (${topCandidate.driver.licensePlate}) • Điểm Trọng số: ${topCandidate.totalScore.toStringAsFixed(3)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _toggleDispatchTimer,
                      child: Text(isTimerRunning ? 'Tạm dừng' : 'Chạy 28s'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accent, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${targetOrder.serviceType.displayName.toUpperCase()} • ${(targetOrder.distanceMeters / 1000).toStringAsFixed(1)} km',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      const Text(
                        'Thu nhập ròng: 55.000đ',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  Text('• Lấy hàng: ${targetOrder.pickupAddress}'),
                  const SizedBox(height: 4),
                  Text('• Giao đến: ${targetOrder.dropoffAddress}'),
                  const SizedBox(height: 4),
                  Text(
                    '• Ứng tiền COD: ${CurrencyFormatter.formatVnd(targetOrder.codAmount)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _countdownSeconds = 28;
                        _reassignToNextCandidate();
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Đã từ chối cuốc xe. Smart Dispatch tự động chuyển sang tài xế xếp hạng kế tiếp (RULE-DSP-02).',
                          ),
                        ),
                      );
                    },
                    child: const Text('Từ chối (Chuyển tiếp)'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                    ),
                    onPressed: () {
                      _dispatchCountdownTimer?.cancel();
                      _store.driverAcceptOrder(
                        targetOrder.trackingCode,
                        customDriverName: topCandidate?.driver.fullName,
                        customPlate: topCandidate?.driver.licensePlate,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã nhận cuốc xe ${targetOrder.trackingCode} thành công!',
                          ),
                        ),
                      );
                      setState(() => _selectedScreenIndex = 3);
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('NHẬN ĐƠN NGAY'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.18: UC16 Điều hướng 3D GPS Turn-by-Turn tới điểm lấy/giao hàng
  Widget _buildTurnByTurnNavigationView() {
    final activeOrder = _store.orders.first;
    final remMeters = _store.distanceFromDriverToDropoffMeters();
    final shouldMaskPhone = activeOrder.status == OrderStatus.delivered ||
        activeOrder.status == OrderStatus.cancelled;
    final displayPhone = SecurityAndBarcodeUtils.maskPhoneNumber(
      activeOrder.recipientPhone,
      shouldMask: shouldMaskPhone,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.18: Điều hướng 3D GPS Turn-by-Turn (UC16)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Map3dPerspectiveWidget(
              height: 300,
              is3dMode: _store.isMap3dEnabled,
              speedKmh: _store.currentSpeedKmh,
              onToggle3d: _store.toggleMap3d,
              progressFraction: _store.routeProgressStep / 10.0,
              nextTurnInstruction: 'Rẽ phải sau 150m vào Phố Huế',
              roadName:
                  'Còn ${(remMeters / 1000).toStringAsFixed(2)} km • Góc hướng: ${_store.activeDriverBearing.toStringAsFixed(0)}°',
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Khách nhận: ${activeOrder.recipientName} ($displayPhone)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _store.stepDriverAlongRoute(),
                  icon: const Icon(Icons.my_location, size: 16),
                  label: const Text('Bước tiến GPS'),
                ),
                const SizedBox(width: 6),
                ElevatedButton(
                  onPressed: () => setState(() => _selectedScreenIndex = 4),
                  child: const Text('Cập nhật (UC17)'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final msg = await _store.acquireRealHardwareGps();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg)),
                    );
                  },
                  icon: const Icon(Icons.satellite_alt, size: 16),
                  label: const Text(
                    'Đọc Chip GPS Phần Cứng (Geolocator)',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final msg = await _store.syncLiveOsrmRouteForActiveOrder();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg)),
                    );
                  },
                  icon: const Icon(Icons.alt_route, size: 16),
                  label: const Text(
                    'Đồng bộ Lộ trình OSRM Thực tế',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.19: UC17 Cập nhật tiến độ chuyến giao (Tuần tự theo RULE-ORD-01)
  Widget _buildTripStepProgressView() {
    final ord = _store.orders.first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.19: Cập nhật Trạng thái Đơn hàng (UC17 - RULE-ORD-01)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Mã vận đơn: ${ord.trackingCode} • Trạng thái hiện tại: ${ord.status.displayName}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _stepTile(
              'Bước 1: Đã nhận đơn (ACCEPTED)',
              ord.status.index >= OrderStatus.accepted.index,
            ),
            _stepTile(
              'Bước 2: Đã đến điểm lấy hàng (ARRIVING_PICKUP)',
              ord.status.index >= OrderStatus.arrivingPickup.index,
            ),
            _stepTile(
              'Bước 3: Đã lấy hàng & Đang giao (IN_TRANSIT)',
              ord.status.index >= OrderStatus.inTransit.index,
            ),
            _stepTile(
              'Bước 4: Đã giao hàng thành công (DELIVERED + POD)',
              ord.status == OrderStatus.delivered,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                    ),
                    onPressed: () {
                      if (ord.status == OrderStatus.inTransit) {
                        setState(() => _selectedScreenIndex = 5);
                      } else {
                        _store.driverAdvanceOrderStatus(ord.trackingCode);
                      }
                    },
                    icon: const Icon(Icons.double_arrow),
                    label: Text(
                      ord.status == OrderStatus.inTransit
                          ? 'Chuyển sang Xác nhận POD & OTP (UC18)'
                          : 'Vuốt chuyển bước tiếp theo',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepTile(String label, bool completed) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        completed ? Icons.check_circle : Icons.radio_button_unchecked,
        color: completed ? AppColors.success : AppColors.textSecondary,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: completed ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }

  /// Hình 8.20: UC18 Xác nhận giao hàng thành công (POD Photo + OTP 4 số + Kiểm tra <= 100m RULE-ORD-03)
  Widget _buildPodConfirmationView() {
    final ord = _store.orders.first;
    final distMeters = _store.distanceFromDriverToDropoffMeters();
    final isWithin100m = distMeters <= 100.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.20: Xác nhận Giao hàng POD & Mã OTP (UC18 - RULE-ORD-03)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            PodGpsWatermarkPhotoCard(
              driverLocation: _store.activeDriverLocation,
              recipientName: _podRecipientCtrl.text,
              otpCode: _podOtpCtrl.text,
              distanceToDropoffMeters: distMeters,
            ),
            if (!isWithin100m) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '⚠️ RULE-ORD-03: Tài xế phải cách điểm giao <= 100m mới được phép xác nhận hoàn tất POD.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        _store.stepDriverAlongRoute(snapToDropoff: true),
                    icon: const Icon(Icons.near_me, size: 16),
                    label: const Text('Tiến vào vùng < 100m'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _podRecipientCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration:
                        const InputDecoration(labelText: 'Tên người thực nhận'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _podOtpCtrl,
                    maxLength: 4,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Mã OTP xác nhận (4 chữ số)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isWithin100m ? AppColors.success : AppColors.textSecondary,
                ),
                onPressed: () async {
                  final otpInput = _podOtpCtrl.text.trim();
                  if (!RegExp(r'^[0-9]{4}$').hasMatch(otpInput)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Vui lòng nhập đúng mã OTP nhận hàng gồm 4 chữ số!',
                        ),
                      ),
                    );
                    return;
                  }
                  if (!isWithin100m) {
                    _store.stepDriverAlongRoute(snapToDropoff: true);
                  }
                  final svgFilePath = await SecurityAndBarcodeUtils
                      .exportPodWatermarkToSvgFile(
                    orderCode: ord.trackingCode,
                    recipientName: _podRecipientCtrl.text.trim(),
                    otpCode: otpInput,
                    driverLocation: _store.activeDriverLocation,
                    distanceMeters: _store.distanceFromDriverToDropoffMeters(),
                  );
                  _store.driverAdvanceOrderStatus(
                    ord.trackingCode,
                    podNote:
                        'POD: ${_podRecipientCtrl.text.trim()} • OTP $otpInput • GPS (${_store.activeDriverLocation.latitude.toStringAsFixed(4)}, ${_store.activeDriverLocation.longitude.toStringAsFixed(4)}) • Tệp: $svgFilePath',
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Hoàn tất đơn ${ord.trackingCode}! Đã lưu tệp bằng chứng POD tại: $svgFilePath',
                      ),
                    ),
                  );
                  setState(() => _selectedScreenIndex = 6);
                },
                icon: const Icon(Icons.task_alt),
                label: Text(
                  isWithin100m
                      ? 'HOÀN TẤT GIAO HÀNG & XUẤT TỆP BẰNG CHỨNG POD'
                      : 'DI CHUYỂN TỚI ĐIỂM GIAO (< 100M) & XUẤT BẰNG CHỨNG POD',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.21: UC19 Quản lý Ví thu nhập & Rút tiền về ngân hàng
  Widget _buildDriverWalletView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.21: Ví Thu nhập Tài xế & Rút tiền (UC19)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Animated3dIconBadge(
                    style: Icon3dStyle.walletVault,
                    size: 62,
                    showRadarPulse: true,
                    isSelected: true,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Số dư khả dụng (Ví Tài xế • Ký quỹ tối thiểu 200.000đ)',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          CurrencyFormatter.formatVnd(
                            _store.driverWalletBalance,
                          ),
                          style: const TextStyle(
                            color: AppColors.surface,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _withdrawAmountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Số tiền muốn rút (VNĐ)',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedBank,
                    decoration: const InputDecoration(
                      labelText: 'Ngân hàng thụ hưởng',
                    ),
                    items: [
                      'Vietcombank - 007100****889',
                      'BIDV - 314100****221',
                    ]
                        .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedBank = v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                ),
                onPressed: () {
                  final amt = double.tryParse(_withdrawAmountCtrl.text) ?? 0;
                  _store.requestWithdrawal(
                    ownerName: 'Nguyễn Văn Nam',
                    ownerRole: 'Tài xế',
                    amount: amt,
                    bankName: 'Vietcombank',
                    accountMasked: '007100****889',
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã gửi lệnh rút ${CurrencyFormatter.formatVnd(amt)} sang Admin duyệt (UC29)!',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Gửi yêu cầu rút tiền'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.22: UC20 Báo cáo sự cố trên đường
  Widget _buildRoadIncidentReportView() {
    final reasons = [
      'Kẹt xe nghiêm trọng / Ngập nước',
      'Xe gặp sự cố kỹ thuật / Thủng lốp',
      'Khách nhận không nghe máy quá 3 lần',
      'Địa chỉ giao hàng không tồn tại',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.22: Báo cáo Sự cố Trên đường (UC20)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: reasons.map((r) {
                return ChoiceChip(
                  label: Text(r),
                  selected: _incidentType == r,
                  onSelected: (_) => setState(() => _incidentType = r),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _incidentNoteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Ghi chú hiện trường & Tọa độ GPS đính kèm',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                onPressed: () {
                  _store.addIncidentOrComplaint(
                    orderId: _store.orders.first.trackingCode,
                    reporterName: 'Tài xế Nguyễn Văn Nam',
                    issueType: _incidentType,
                    description: _incidentNoteCtrl.text.trim().isEmpty
                        ? 'Báo cáo sự cố trên lộ trình: $_incidentType'
                        : _incidentNoteCtrl.text.trim(),
                  );
                  _incidentNoteCtrl.clear();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Đã gửi báo cáo sự cố khẩn cấp về Trung tâm Điều phối!',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.warning_amber_rounded),
                label: const Text('Gửi báo cáo sự cố ngay'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.23: UC21 Thống kê hiệu suất & thu nhập (Dark Mode Analytics #1A202C)
  Widget _buildDarkModeAnalyticsView() {
    final dailyBars = [
      ('T2', 0.55, '620K'),
      ('T3', 0.70, '780K'),
      ('T4', 0.65, '710K'),
      ('T5', 0.85, '950K'),
      ('T6', 0.95, '1.15M'),
      ('T7', 1.00, '1.25M'),
      ('CN', 0.75, '840K'),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.darkSidebar,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Hình 8.23: Thống kê Hiệu suất & Thu nhập (UC21 - Dark Mode)',
                  style: TextStyle(
                    color: AppColors.surface,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                children: ['Hôm nay', 'Tuần này', 'Tháng này'].map((p) {
                  final selected = _statsPeriod == p;
                  return ChoiceChip(
                    label: Text(p, style: const TextStyle(fontSize: 11)),
                    selected: selected,
                    selectedColor: AppColors.accent,
                    onSelected: (_) => setState(() => _statsPeriod = p),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Tổng thu nhập tuần: 6.300.000 VNĐ (+15% so với tuần trước)',
            style: TextStyle(
              color: AppColors.accent,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: dailyBars.map((bar) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      bar.$3,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 28,
                      height: 95 * bar.$2,
                      decoration: BoxDecoration(
                        color: bar.$2 == 1.0
                            ? AppColors.accent
                            : AppColors.routeRibbonFill,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      bar.$1,
                      style: const TextStyle(
                        color: AppColors.surface,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          const Divider(color: Colors.white24),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text(
                'Tỷ lệ nhận chuyến: 95%',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                'Tỷ lệ hoàn thành: 98.5%',
                style: TextStyle(color: AppColors.success, fontSize: 12),
              ),
              Text(
                'Đánh giá: 4.9 ★ (320 lượt)',
                style: TextStyle(color: AppColors.warning, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
