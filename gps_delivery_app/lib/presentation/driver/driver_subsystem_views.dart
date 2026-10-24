import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/gps/gps_integrity_validator.dart';
import '../../core/gps/smart_dispatch_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/security_and_barcode_utils.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/entities/geo_point.dart';
import '../../domain/enums/order_status.dart';
import '../widgets/animated_3d_ui_icons.dart';
import '../widgets/system_state_screens.dart';

part 'driver_onboarding_and_dispatch_views.dart';
part 'driver_wallet_and_analytics_views.dart';

/// Phân hệ Tài xế (Driver App) - 9 màn hình chuẩn thiết kế gốc (uc13..uc21)
class DriverSubsystemEntry extends StatefulWidget {
  final int? forcedScreenIndex;
  final VoidCallback? onLogout;

  const DriverSubsystemEntry({
    super.key,
    this.forcedScreenIndex,
    this.onLogout,
  });

  @override
  State<DriverSubsystemEntry> createState() => _DriverSubsystemEntryState();
}

class _DriverSubsystemEntryState extends State<DriverSubsystemEntry> {
  final AppStateStore _store = AppStateStore.instance;
  int _selectedScreenIndex = 1; // Mặc định: Trang chủ Tài xế Online/Offline (UC14)

  // Hồ sơ đăng ký tài xế (UC13)
  final TextEditingController _drvNameCtrl =
      TextEditingController(text: 'Nguyễn Văn Nam');
  final TextEditingController _drvPhoneCtrl =
      TextEditingController(text: '0987654321');
  final TextEditingController _drvCitizenCtrl =
      TextEditingController(text: '079095001234');
  final TextEditingController _drvPlateCtrl =
      TextEditingController(text: '59X1-123.45');
  String _vehicleType = 'Xe máy';

  // Countdown 28s & Smart Dispatch (UC15)
  int _countdownSeconds = 28;
  Timer? _dispatchCountdownTimer;
  final Set<String> _rejectedDriverIds = {};

  // POD & OTP 4 số (UC17) & Chat hai chiều với Khách (UC16)
  final TextEditingController _podOtpCtrl = TextEditingController();
  final TextEditingController _podRecipientCtrl = TextEditingController();
  final TextEditingController _podNoteCtrl = TextEditingController();
  final TextEditingController _driverChatInputCtrl = TextEditingController();
  bool _showDriverChatPanel = false;
  String? _lastSyncedDriverOrderCode;
  String? _lastSyncedDriverProfileKey;

  // Rút tiền Ví tài xế (UC18)
  final TextEditingController _withdrawAmountCtrl =
      TextEditingController(text: '1000000');
  String _selectedBank = 'Vietcombank - 007100****889';
  String _incomePeriod = 'Tuần';

  // Lịch sử giao hàng (UC19)
  String _driverHistoryPeriod = 'Hôm nay';

  // Báo cáo sự cố (UC20)
  String _incidentType = 'Hàng bị hỏng';
  final TextEditingController _incidentNoteCtrl = TextEditingController();
  final Set<String> _attachedKycDocs = {'CCCD mặt trước', 'Giấy phép lái xe'};
  int _attachedIncidentPhotos = 1;

  // Thống kê hiệu suất (UC21)
  String _statsPeriod = 'Tuần này';

  static const List<String> _screenTitles = [
    'Hồ sơ & Pháp lý Tài xế',
    'Trang chủ Tài xế & Trạng thái Hoạt động',
    'ĐƠN HÀNG MỚI! (28s)',
    'Điều hướng GPS Turn-by-Turn',
    'Cập nhật tiến độ vận đơn',
    'Xác nhận Giao hàng POD & Mã OTP',
    'Thu nhập và rút tiền',
    'Báo cáo sự cố trên đường',
    'Thống kê hoạt động & Hồ sơ',
    'Lịch sử giao hàng',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.forcedScreenIndex != null) {
      _selectedScreenIndex = widget.forcedScreenIndex!;
    }
    _syncDriverControllersFromDb();
    _store.addListener(_onStoreChanged);
  }

  void _syncDriverControllersFromDb() {
    final d = _store.activeDriverRecord;
    if (d != null) {
      final profileKey =
          '${d.id}|${d.fullName}|${d.phone}|${d.citizenId}|${d.licensePlate}|${d.vehicleType}';
      if (_lastSyncedDriverProfileKey != profileKey) {
        _lastSyncedDriverProfileKey = profileKey;
        _drvNameCtrl.text = d.fullName;
        _drvPhoneCtrl.text = d.phone;
        _drvCitizenCtrl.text = d.citizenId;
        _drvPlateCtrl.text = d.licensePlate;
        if (d.vehicleType.isNotEmpty) {
          _vehicleType = d.vehicleType;
        }
      }
    }
    final activeOrd = _store.activeOrderRecord;
    if (activeOrd != null) {
      if (_lastSyncedDriverOrderCode != activeOrd.trackingCode) {
        _lastSyncedDriverOrderCode = activeOrd.trackingCode;
        _podRecipientCtrl.text = activeOrd.recipientName;
        if (activeOrd.status == OrderStatus.delivered) {
          _podOtpCtrl.text = SecurityAndBarcodeUtils.generateOrderDeliveryOtp4(
            activeOrd.trackingCode,
          );
        } else {
          _podOtpCtrl.clear();
        }
      } else if (_podRecipientCtrl.text.trim().isEmpty) {
        _podRecipientCtrl.text = activeOrd.recipientName;
      }
      if (activeOrd.podImageNote != null &&
          activeOrd.podImageNote!.isNotEmpty &&
          _podNoteCtrl.text.trim().isEmpty) {
        _podNoteCtrl.text = activeOrd.podImageNote!;
      }
    }
  }

  @override
  void didUpdateWidget(covariant DriverSubsystemEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forcedScreenIndex != null &&
        widget.forcedScreenIndex != oldWidget.forcedScreenIndex) {
      _selectedScreenIndex = widget.forcedScreenIndex!;
    }
  }

  void _onStoreChanged() {
    if (!mounted) return;
    _syncDriverControllersFromDb();
    setState(() {});
  }

  void _reassignToNextCandidate() {
    final targetOrder = _store.orders
            .where((o) => o.status == OrderStatus.searching)
            .firstOrNull ??
        _store.activeOrderRecord ??
        _store.orders.firstOrNull;
    if (targetOrder == null) return;
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
    _drvPhoneCtrl.dispose();
    _drvCitizenCtrl.dispose();
    _drvPlateCtrl.dispose();
    _podOtpCtrl.dispose();
    _podRecipientCtrl.dispose();
    _podNoteCtrl.dispose();
    _driverChatInputCtrl.dispose();
    _withdrawAmountCtrl.dispose();
    _incidentNoteCtrl.dispose();
    super.dispose();
  }

  // Thanh điều hướng đáy 4 tab màu xanh đen #0F172A giống hệt uc14, uc18, uc19, uc21:
  // 0: Trang chủ | 1: Đơn hàng | 2: Thu nhập | 3: Hồ sơ
  int _bottomNavIndexForScreen(int screenIdx) {
    if (screenIdx == 1) return 0; // Trang chủ
    if (screenIdx == 2 ||
        screenIdx == 3 ||
        screenIdx == 4 ||
        screenIdx == 5 ||
        screenIdx == 7 ||
        screenIdx == 9) {
      return 1; // Đơn hàng / Nhận đơn / Điều hướng / POD / Lịch sử giao
    }
    if (screenIdx == 6) return 2; // Thu nhập
    return 3; // Hồ sơ & Thống kê (0, 8)
  }

  void _onBottomNavTapped(int navIdx) {
    setState(() {
      switch (navIdx) {
        case 0:
          _selectedScreenIndex = 1; // Trang chủ (UC14)
          break;
        case 1:
          _selectedScreenIndex = 9; // Lịch sử giao hàng (UC19)
          break;
        case 2:
          _selectedScreenIndex = 6; // Thu nhập và rút tiền (UC18)
          break;
        case 3:
          _selectedScreenIndex = 8; // Thống kê hoạt động & Hồ sơ (UC21/UC13)
          break;
      }
    });
  }

  bool get _isDriverSubScreen =>
      _selectedScreenIndex == 0 ||
      _selectedScreenIndex == 3 ||
      _selectedScreenIndex == 4 ||
      _selectedScreenIndex == 5 ||
      _selectedScreenIndex == 7 ||
      _selectedScreenIndex == 9;

  void _navigateBackFromDriverSubScreen() {
    setState(() {
      if (_selectedScreenIndex == 0) {
        _selectedScreenIndex = 8;
      } else if (_selectedScreenIndex == 4 ||
          _selectedScreenIndex == 5 ||
          _selectedScreenIndex == 7) {
        _selectedScreenIndex = 3;
      } else {
        _selectedScreenIndex = 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 860;
        if (isWide) {
          final sidebarWidth = (constraints.maxWidth * 0.185).clamp(210.0, 285.0);
          final contentPadding = (constraints.maxWidth * 0.02).clamp(16.0, 32.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDriverStudioSidebar(sidebarWidth),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDriverWhiteTopBar(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(contentPadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OfflineQueueBanner(store: _store),
                            if (_isDriverSubScreen) ...[
                              _buildDriverSubScreenHeader(),
                              const SizedBox(height: 14),
                            ],
                            _buildActiveDriverScreen(context),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final mobilePadding = (constraints.maxWidth * 0.035).clamp(10.0, 18.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDriverHeaderBanner(),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(mobilePadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OfflineQueueBanner(store: _store),
                    if (_isDriverSubScreen) ...[
                      _buildDriverSubScreenHeader(),
                      const SizedBox(height: 8),
                    ],
                    _buildActiveDriverScreen(context),
                  ],
                ),
              ),
            ),
            _buildDesignDriverDarkBottomBar(),
          ],
        );
      },
    );
  }

  Widget _buildDriverStudioSidebar(double sidebarWidth) {
    const menuItems = <(IconData, String, int)>[
      (Icons.radar_rounded, 'Trạng thái & Bản đồ GPS', 1),
      (Icons.history_rounded, 'Lịch sử giao hàng', 9),
      (Icons.account_balance_wallet_outlined, 'Thu nhập & Ví tài xế', 6),
      (Icons.insights_rounded, 'Hiệu suất & Hồ sơ KYC', 8),
    ];
    final activeOrd = _store.activeOrderRecord;
    final hasActiveTrip = _store.isDriverOnline &&
        activeOrd != null &&
        activeOrd.status != OrderStatus.delivered &&
        activeOrd.status != OrderStatus.cancelled &&
        activeOrd.status != OrderStatus.failed;

    return Container(
      width: sidebarWidth,
      decoration: const BoxDecoration(
        color: AppColors.techBg,
        border: Border(
          right: BorderSide(color: AppColors.ink, width: 1.6),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 16, 18),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.acid,
                      border: Border.all(color: AppColors.techBg),
                    ),
                    child: const Icon(
                      Icons.two_wheeler_rounded,
                      color: AppColors.techBg,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GHST DRIVER',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15.5,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          'ĐỐI TÁC TÀI XẾ • STUDIO',
                          style: TextStyle(
                            color: AppColors.acid,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Consolas',
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.techLine, height: 1),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...menuItems.map((item) {
                      final selected = _selectedScreenIndex == item.$3 ||
                          (item.$3 == 1 &&
                              (_selectedScreenIndex == 2 ||
                                  _selectedScreenIndex == 3 ||
                                  _selectedScreenIndex == 4 ||
                                  _selectedScreenIndex == 5 ||
                                  _selectedScreenIndex == 7)) ||
                          (item.$3 == 8 && _selectedScreenIndex == 0);
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        child: InkWell(
                          onTap: () =>
                              setState(() => _selectedScreenIndex = item.$3),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.violet.withValues(alpha: 0.25)
                                  : Colors.transparent,
                              border: selected
                                  ? const Border(
                                      left: BorderSide(
                                        color: AppColors.acid,
                                        width: 4.0,
                                      ),
                                    )
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  item.$1,
                                  size: 19,
                                  color: selected
                                      ? AppColors.acid
                                      : AppColors.techMuted,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    item.$2,
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : AppColors.techMuted,
                                      fontSize: 13,
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    if (hasActiveTrip) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: InkWell(
                          onTap: () => setState(() {
                            _selectedScreenIndex =
                                activeOrd.status == OrderStatus.searching
                                    ? 2
                                    : 3;
                          }),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.acid.withValues(alpha: 0.14),
                              border: Border.all(
                                color: AppColors.acid,
                                width: 1.2,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: AppColors.acid,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        activeOrd.status ==
                                                OrderStatus.searching
                                            ? 'CUỐC XE MỚI ĐANG CHỜ'
                                            : 'CUỐC XE ĐANG CHẠY',
                                        style: const TextStyle(
                                          color: AppColors.acid,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          fontFamily: 'Consolas',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${activeOrd.trackingCode} • ${activeOrd.status.displayName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  activeOrd.status == OrderStatus.searching
                                      ? 'Chạm để nhận cuốc xe ngay →'
                                      : 'Chạm để mở Điều hướng GPS →',
                                  style: const TextStyle(
                                    color: AppColors.techMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Divider(color: AppColors.techLine, height: 1),
            ),
            if (widget.onLogout != null)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: const Icon(
                  Icons.logout_rounded,
                  color: AppColors.pink,
                  size: 19,
                ),
                title: const Text(
                  'Đăng xuất',
                  style: TextStyle(
                    color: AppColors.pink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onTap: widget.onLogout,
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverWhiteTopBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showPlateBadge = constraints.maxWidth >= 900;
        final isCompactBar = constraints.maxWidth < 680;
        return Container(
          height: 64,
          padding: EdgeInsets.symmetric(horizontal: isCompactBar ? 14 : 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: AppColors.ink, width: 1.5),
            ),
          ),
          child: Row(
            children: [
              const Animated3dIconBadge(
                style: Icon3dStyle.gpsPinRadar,
                size: 38,
                showRadarPulse: false,
                isSelected: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _screenTitles[_selectedScreenIndex],
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              if (showPlateBadge) ...[
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.paper,
                      border: Border.all(color: AppColors.ink, width: 1.2),
                    ),
                    child: Text(
                      'Biển số: ${_store.activeDriverRecord?.licensePlate ?? _store.drivers.firstOrNull?.licensePlate ?? "59X1-123.45"} • Ví: ${CurrencyFormatter.formatVnd(_store.driverWalletBalance)}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Consolas',
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Thông báo Đối tác Tài xế',
                    onPressed: () => _showDriverNotificationsDialog(context),
                    icon: const Icon(
                      Icons.notifications_none_rounded,
                      color: AppColors.ink,
                      size: 22,
                    ),
                  ),
                  if (_store.driverNotifications.any((n) => !n.isRead))
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        color: AppColors.pink,
                        child: Text(
                          '${_store.driverNotifications.where((n) => !n.isRead).length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _store.isDriverOnline
                      ? const Color(0xFF14B866)
                      : AppColors.ink,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () =>
                    _store.setDriverOnlineStatus(!_store.isDriverOnline),
                icon: Icon(
                  _store.isDriverOnline
                      ? Icons.sensors_rounded
                      : Icons.power_settings_new_rounded,
                  size: 15,
                ),
                label: Text(
                  _store.isDriverOnline ? 'ĐANG ONLINE' : 'OFFLINE',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (widget.onLogout != null) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    backgroundColor: AppColors.acid,
                    side: const BorderSide(color: AppColors.ink, width: 1.2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout_rounded, size: 15),
                  label: const Text(
                    'Đăng xuất',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildDriverHeaderBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.techBg,
        border: Border.all(color: AppColors.ink, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: AppColors.pink,
            offset: Offset(6, 6),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          const Animated3dIconBadge(
            style: Icon3dStyle.gpsPinRadar,
            size: 40,
            showRadarPulse: false,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _screenTitles[_selectedScreenIndex],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tài xế: ${_store.activeDriverName} • Ví: ${CurrencyFormatter.formatVnd(_store.driverWalletBalance)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.acid,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Consolas',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _showDriverNotificationsDialog(context),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.notifications_none_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                if (_store.driverNotifications.any((n) => !n.isRead))
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      color: AppColors.pink,
                      child: Text(
                        '${_store.driverNotifications.where((n) => !n.isRead).length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _store.isDriverOnline
                  ? const Color(0xFF14B866)
                  : AppColors.techLine,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: Size.zero,
            ),
            onPressed: () =>
                _store.setDriverOnlineStatus(!_store.isDriverOnline),
            child: Text(
              _store.isDriverOnline ? 'ONLINE' : 'OFFLINE',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
          ),
          if (widget.onLogout != null) ...[
            const SizedBox(width: 6),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.transparent,
                side: const BorderSide(color: AppColors.techLine),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                minimumSize: Size.zero,
              ),
              onPressed: widget.onLogout,
              child: const Text(
                'Đăng xuất',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDesignDriverDarkBottomBar() {
    final activeNav = _bottomNavIndexForScreen(_selectedScreenIndex);
    const items = [
      (Icons.home_rounded, 'Trang chủ'),
      (Icons.inventory_2_outlined, 'Đơn hàng'),
      (Icons.account_balance_wallet_outlined, 'Thu nhập'),
      (Icons.person_outline_rounded, 'Hồ sơ'),
    ];

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.techBg,
        border: Border.all(color: AppColors.ink, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: AppColors.pink,
            offset: Offset(5, 5),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: List.generate(items.length, (idx) {
          final selected = activeNav == idx;
          final color = selected ? AppColors.acid : AppColors.techMuted;
          return Expanded(
            child: InkWell(
              onTap: () => _onBottomNavTapped(idx),
              child: Container(
                decoration: BoxDecoration(
                  border: selected
                      ? const Border(
                          top: BorderSide(color: AppColors.acid, width: 3),
                        )
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(items[idx].$1, color: color, size: 22),
                    const SizedBox(height: 3),
                    Text(
                      items[idx].$2,
                      style: TextStyle(
                        color: color,
                        fontSize: 11.5,
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDriverSubScreenHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ink, width: 1.4),
        boxShadow: const [
          BoxShadow(
            color: AppColors.ink,
            offset: Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _navigateBackFromDriverSubScreen,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 15),
            label: const Text('Quay lại'),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _screenTitles[_selectedScreenIndex],
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13.5,
                color: AppColors.violet,
              ),
            ),
          ),
        ],
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
      case 9:
        return _buildDriverTripHistoryUc19View();
      default:
        return _buildDriverHomeOnlineView();
    }
  }

  void _showDriverNotificationsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final items = _store.driverNotifications;
            return AlertDialog(
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
                side: BorderSide(color: AppColors.ink, width: 1.8),
              ),
              titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              title: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Text(
                    'Thông báo Đối tác Tài xế (${items.where((n) => !n.isRead).length} chưa đọc)',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _store.markAllNotificationsAsRead();
                      setDialogState(() {});
                    },
                    child: const Text(
                      'Đánh dấu đã đọc',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                height: 360,
                child: items.isEmpty
                    ? const Center(
                        child: Text(
                          'Chưa có thông báo nào dành cho Tài xế.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, idx) {
                          final n = items[idx];
                          final orderMatch = RegExp(
                            r'#DH[0-9A-Za-z-]+',
                          ).firstMatch(n.title);
                          final orderCode = orderMatch?.group(0);
                          return InkWell(
                            onTap: () {
                              _store.markNotificationAsRead(n.id);
                              setDialogState(() {});
                              if (orderCode != null) {
                                _store.selectDriverOrder(orderCode);
                                final ord = _store.orders
                                    .where((o) => o.trackingCode == orderCode)
                                    .firstOrNull;
                                Navigator.of(dialogCtx).pop();
                                setState(() {
                                  _selectedScreenIndex =
                                      ord?.status == OrderStatus.searching
                                          ? 2
                                          : 3;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: n.isRead
                                    ? Colors.white
                                    : const Color(0xFFF0FDF4),
                                border: Border.all(
                                  color: AppColors.ink,
                                  width: n.isRead ? 1.0 : 1.5,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          n.category,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 11,
                                            color: AppColors.violet,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        n.timeAgo,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          color: AppColors.textSecondary,
                                          fontFamily: 'Consolas',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    n.title,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: n.isRead
                                          ? FontWeight.w600
                                          : FontWeight.w900,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  if (orderCode != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'Nhấn để mở chuyến xe $orderCode →',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.violet,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Đóng'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _rebuildDriverUi(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }
}
