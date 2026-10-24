import 'package:flutter/material.dart';
import '../../core/gps/smart_dispatch_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/geo_math.dart';
import '../../core/utils/security_and_barcode_utils.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/entities/geo_point.dart';
import '../../domain/entities/pricing_estimate.dart';
import '../../domain/enums/order_status.dart';
import '../../domain/enums/service_type.dart';
import '../widgets/animated_3d_ui_icons.dart';
import '../widgets/system_state_screens.dart';

part 'customer_auth_and_address_views.dart';
part 'customer_order_and_pricing_views.dart';
part 'customer_history_and_profile_views.dart';

/// Phân hệ Khách hàng (Customer App) - 14 màn hình chuẩn thiết kế gốc (uc02..uc12, uc41, uc42)
class CustomerSubsystemEntry extends StatefulWidget {
  final int? forcedScreenIndex;
  final int? forcedAuthTabIndex;
  final VoidCallback? onLogout;

  const CustomerSubsystemEntry({
    super.key,
    this.forcedScreenIndex,
    this.forcedAuthTabIndex,
    this.onLogout,
  });

  @override
  State<CustomerSubsystemEntry> createState() => _CustomerSubsystemEntryState();
}

class _CustomerSubsystemEntryState extends State<CustomerSubsystemEntry> {
  final AppStateStore _store = AppStateStore.instance;
  int _selectedScreenIndex = 0; // Mặc định: Trang chủ tổng quan Khách hàng

  // Trạng thái (Tạo đơn hàng, Gói dịch vụ, Thanh toán & Voucher)
  final TextEditingController _pickupCtrl = TextEditingController();
  final TextEditingController _dropoffCtrl = TextEditingController();
  final TextEditingController _recipientNameCtrl = TextEditingController();
  final TextEditingController _recipientPhoneCtrl = TextEditingController();
  String _pkgCategory = 'Quần áo & Thời trang';
  final TextEditingController _pkgDescCtrl = TextEditingController();
  final TextEditingController _weightCtrl = TextEditingController(text: '1.0');
  final TextEditingController _dimCtrl =
      TextEditingController(text: '20 x 15 x 10 cm');
  final TextEditingController _codCtrl = TextEditingController(text: '0');
  final TextEditingController _voucherCtrl = TextEditingController();
  DeliveryServiceType _selectedService = DeliveryServiceType.express30m;
  bool _isScheduledDelivery = false;
  String _scheduledDeliverySlot = '13:00 - 15:00';
  String _selectedPaymentMethod = 'Tiền mặt (COD)';
  List<GeoPoint>? _osrmPreviewPoints;
  int? _osrmDistMeters;
  int? _osrmDurationSec;
  bool _isPreOrderPaid = false;

  // Trạng thái Sổ địa chỉ (UC02)
  String _selectedAddressTag = 'Nhà riêng';
  int _selectedSavedAddressIndex = 0;
  final TextEditingController _newAddressCtrl = TextEditingController();

  // Trạng thái Chat nội bộ (UC09)
  final TextEditingController _chatInputCtrl = TextEditingController();

  // Trạng thái Hủy đơn (UC12)
  String _selectedCancelReason = 'Thời gian chờ quá lâu';
  final TextEditingController _cancelDetailCtrl = TextEditingController();

  // Trạng thái Lịch sử đơn hàng
  String _historyFilterTab = 'Tất cả';
  final TextEditingController _historySearchCtrl = TextEditingController();

  // Trạng thái Đánh giá 5 sao & Tiền thưởng Tip
  int _ratingStars = 5;
  int _selectedTipVnd = 10000;
  final Set<String> _selectedFeedbackChips = {
    'Thái độ thân thiện',
    'Giao hàng nhanh',
    'Đúng giờ',
  };
  final TextEditingController _ratingCommentCtrl = TextEditingController();

  // Trạng thái Khiếu nại / Hỗ trợ
  String _complaintType = 'Hàng hư hỏng';
  int _customerComplaintPhotos = 1;
  final TextEditingController _complaintDescCtrl = TextEditingController();

  // Trạng thái Hồ sơ cá nhân
  late final TextEditingController _profileNameCtrl;
  late final TextEditingController _profilePhoneCtrl;
  late final TextEditingController _profileEmailCtrl;
  late final TextEditingController _profileAddressCtrl;
  String _profileGender = 'Nam';
  String? _lastSyncedCustomerProfileKey;
  String? _lastSyncedRatingOrderCode;

  // Trạng thái Trung tâm thông báo
  String _notiFilter = 'Tất cả';

  static const List<String> _screenTitles = [
    'Trang chủ',
    'Sổ địa chỉ nhận hàng',
    'Tạo đơn hàng mới',
    'Chi tiết cước phí & Ưu đãi',
    'Theo dõi hành trình GPS',
    'Trò chuyện với Tài xế',
    'Yêu cầu hủy đơn hàng',
    'Lịch sử đơn hàng',
    'Đánh giá chuyến giao hàng',
    'Gửi khiếu nại & Hỗ trợ',
    'Hồ sơ cá nhân',
    'Trung tâm thông báo',
    'Chọn gói dịch vụ giao hàng',
    'Thanh toán đơn hàng',
    'Kho mã ưu đãi & Khuyến mãi',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.forcedScreenIndex != null && widget.forcedScreenIndex! >= 0) {
      _selectedScreenIndex = widget.forcedScreenIndex!;
    }
    _profileNameCtrl = TextEditingController(text: _store.customerFullName);
    _profilePhoneCtrl =
        TextEditingController(text: _store.displayCustomerPhone);
    _profileEmailCtrl = TextEditingController(text: _store.customerEmail);
    _profileAddressCtrl =
        TextEditingController(text: _store.customerDefaultAddress);
    _profileGender = _store.customerGender;
    _lastSyncedCustomerProfileKey =
        '${_store.customerFullName}|${_store.displayCustomerPhone}|${_store.customerEmail}|${_store.customerDefaultAddress}|${_store.customerGender}';
    _syncCustomerControllersFromDb();
    _store.addListener(_onStoreChanged);
  }

  void _syncCustomerControllersFromDb() {
    if (_pickupCtrl.text.isEmpty && _store.customerDefaultAddress.isNotEmpty) {
      _pickupCtrl.text = _store.customerDefaultAddress;
    }
  }

  @override
  void didUpdateWidget(covariant CustomerSubsystemEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forcedScreenIndex != null &&
        widget.forcedScreenIndex! > 0 &&
        widget.forcedScreenIndex != oldWidget.forcedScreenIndex) {
      _selectedScreenIndex = widget.forcedScreenIndex!;
    }
  }

  void _onStoreChanged() {
    if (!mounted) return;
    final profileKey =
        '${_store.customerFullName}|${_store.displayCustomerPhone}|${_store.customerEmail}|${_store.customerDefaultAddress}|${_store.customerGender}';
    if (_lastSyncedCustomerProfileKey != profileKey) {
      _lastSyncedCustomerProfileKey = profileKey;
      _profileNameCtrl.text = _store.customerFullName;
      _profilePhoneCtrl.text = _store.displayCustomerPhone;
      _profileEmailCtrl.text = _store.customerEmail;
      _profileAddressCtrl.text = _store.customerDefaultAddress;
      _profileGender = _store.customerGender;
    }
    _syncCustomerControllersFromDb();
    setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _pickupCtrl.dispose();
    _dropoffCtrl.dispose();
    _recipientNameCtrl.dispose();
    _recipientPhoneCtrl.dispose();
    _pkgDescCtrl.dispose();
    _weightCtrl.dispose();
    _dimCtrl.dispose();
    _codCtrl.dispose();
    _voucherCtrl.dispose();
    _newAddressCtrl.dispose();
    _chatInputCtrl.dispose();
    _cancelDetailCtrl.dispose();
    _historySearchCtrl.dispose();
    _ratingCommentCtrl.dispose();
    _complaintDescCtrl.dispose();
    _profileNameCtrl.dispose();
    _profilePhoneCtrl.dispose();
    _profileEmailCtrl.dispose();
    _profileAddressCtrl.dispose();
    super.dispose();
  }

  // 4-tab bottom navigation giống hệt uc03, uc06, uc41, uc42:
  // 0: Trang chủ | 1: Đơn hàng | 2: Thông báo | 3: Hồ sơ
  int _bottomNavIndexForScreen(int screenIdx) {
    if (screenIdx == 0 ||
        screenIdx == 2 ||
        screenIdx == 3 ||
        screenIdx == 1 ||
        screenIdx == 12 ||
        screenIdx == 13 ||
        screenIdx == 14) {
      return 0; // Trang chủ & Đặt đơn
    }
    if (screenIdx == 4 ||
        screenIdx == 7 ||
        screenIdx == 6 ||
        screenIdx == 8 ||
        screenIdx == 9) {
      return 1; // Đơn hàng & Theo dõi GPS
    }
    if (screenIdx == 5 || screenIdx == 11) return 2; // Thông báo
    return 3; // Hồ sơ (10)
  }

  void _onBottomNavTapped(int navIdx) {
    setState(() {
      switch (navIdx) {
        case 0:
          _selectedScreenIndex = 0; // Trang chủ tổng quan
          break;
        case 1:
          _selectedScreenIndex = 7; // Lịch sử đơn hàng
          break;
        case 2:
          _selectedScreenIndex = 11; // Thông báo
          break;
        case 3:
          _selectedScreenIndex = 10; // Hồ sơ cá nhân
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 860;
        if (isWide) {
          final sidebarWidth = (constraints.maxWidth * 0.185).clamp(210.0, 290.0);
          final contentPadding = (constraints.maxWidth * 0.02).clamp(16.0, 32.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCustomerStudioSidebar(sidebarWidth),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCustomerWhiteTopBar(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(contentPadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OfflineQueueBanner(store: _store),
                            _buildActiveCustomerScreen(context),
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
            _buildCustomerTopAppBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(mobilePadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OfflineQueueBanner(store: _store),
                    _buildActiveCustomerScreen(context),
                  ],
                ),
              ),
            ),
            _buildDesignCustomerBottomBar(),
          ],
        );
      },
    );
  }

  Widget _buildCustomerStudioSidebar(double sidebarWidth) {
    const menuItems = <(IconData, String, int)>[
      (Icons.home_outlined, 'Trang chủ', 0),
      (Icons.add_box_outlined, 'Tạo đơn hàng mới', 2),
      (Icons.my_location_rounded, 'Theo dõi hành trình GPS', 4),
      (Icons.receipt_long_outlined, 'Lịch sử đơn hàng', 7),
      (Icons.bookmarks_outlined, 'Sổ địa chỉ nhận hàng', 1),
      (Icons.local_offer_outlined, 'Kho mã ưu đãi', 14),
      (Icons.notifications_none_rounded, 'Trung tâm thông báo', 11),
      (Icons.person_outline_rounded, 'Hồ sơ cá nhân', 10),
    ];

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
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 18),
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
                      Icons.local_shipping_outlined,
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
                          'GHST EXPRESS',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15.5,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          'GIAO HÀNG SIÊU TỐC',
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
                          (item.$3 == 2 &&
                              (_selectedScreenIndex == 3 ||
                                  _selectedScreenIndex == 12 ||
                                  _selectedScreenIndex == 13)) ||
                          (item.$3 == 4 &&
                              (_selectedScreenIndex == 5 ||
                                  _selectedScreenIndex == 6 ||
                                  _selectedScreenIndex == 8));
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
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerWhiteTopBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showProfileText = constraints.maxWidth >= 720;
        final isCompactBar = constraints.maxWidth < 600;
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
                style: Icon3dStyle.scooterExpress,
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
              if (_selectedScreenIndex != 0 && _selectedScreenIndex != 2) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.violet,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  onPressed: () => setState(() => _selectedScreenIndex = 2),
                  icon: const Icon(Icons.add_box_outlined, size: 16),
                  label: const Text(
                    'Tạo đơn hàng mới',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Trung tâm thông báo',
                    onPressed: () => setState(() => _selectedScreenIndex = 11),
                    icon: const Icon(
                      Icons.notifications_none_rounded,
                      color: AppColors.ink,
                      size: 22,
                    ),
                  ),
                  if (_store.customerNotifications.any((n) => !n.isRead))
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
                          '${_store.customerNotifications.where((n) => !n.isRead).length}',
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
              const SizedBox(width: 8),
              InkWell(
                onTap: () => setState(() => _selectedScreenIndex = 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.acid,
                        border: Border.all(color: AppColors.ink, width: 1.2),
                      ),
                      child: Icon(
                        const [
                          Icons.person,
                          Icons.sentiment_very_satisfied_rounded,
                          Icons.verified_user_rounded,
                          Icons.workspace_premium_rounded,
                        ][_store.customerAvatarBadgeIndex % 4],
                        color: AppColors.ink,
                        size: 19,
                      ),
                    ),
                    if (showProfileText) ...[
                      const SizedBox(width: 8),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _store.customerFullName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12.5,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            (_store.customerEmail.isNotEmpty &&
                                    !_store.customerEmail.endsWith(
                                      '@giaohanggps.vn',
                                    ))
                                ? _store.customerEmail
                                : _store.displayCustomerPhone,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontFamily: 'Consolas',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool get _isCustomerSubScreen =>
      _selectedScreenIndex != 0 &&
      _selectedScreenIndex != 7 &&
      _selectedScreenIndex != 11 &&
      _selectedScreenIndex != 10;

  void _navigateBackFromCustomerSubScreen() {
    setState(() {
      if (_selectedScreenIndex == 3 ||
          _selectedScreenIndex == 12 ||
          _selectedScreenIndex == 13) {
        _selectedScreenIndex = 2;
      } else if (_selectedScreenIndex == 5 ||
          _selectedScreenIndex == 6 ||
          _selectedScreenIndex == 8 ||
          _selectedScreenIndex == 9) {
        _selectedScreenIndex = 4;
      } else {
        _selectedScreenIndex = 0;
      }
    });
  }

  Widget _buildCustomerTopAppBar(BuildContext context) {
    final activeOrder = _store.activeCustomerOrderRecord;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.techBg,
        border: Border.all(color: AppColors.ink, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: AppColors.violet,
            offset: Offset(6, 6),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          if (_isCustomerSubScreen) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Quay lại',
              onPressed: _navigateBackFromCustomerSubScreen,
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: AppColors.acid,
                size: 22,
              ),
            ),
            const SizedBox(width: 4),
          ] else ...[
            const Animated3dIconBadge(
              style: Icon3dStyle.scooterExpress,
              size: 38,
              showRadarPulse: false,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedScreenIndex == 0
                      ? 'VỊ TRÍ LẤY HÀNG • ${_store.customerDefaultAddress.isNotEmpty ? _store.customerDefaultAddress : "TP. Hồ Chí Minh"}'
                      : 'GHST EXPRESS • KHÁCH HÀNG',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.acid,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Consolas',
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
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
                if (activeOrder != null && _selectedScreenIndex != 0)
                  Text(
                    'Đơn: ${activeOrder.trackingCode} (${activeOrder.status.displayName})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.techMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Consolas',
                    ),
                  ),
              ],
            ),
          ),
          if (widget.onLogout != null) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
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
              ),
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout_rounded, size: 14),
              label: const Text(
                'Đăng xuất',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDesignCustomerBottomBar() {
    final activeNav = _bottomNavIndexForScreen(_selectedScreenIndex);
    const items = [
      (Icons.home_rounded, 'Trang chủ'),
      (Icons.inventory_2_outlined, 'Đơn hàng'),
      (Icons.notifications_none_rounded, 'Thông báo'),
      (Icons.person_outline_rounded, 'Hồ sơ'),
    ];

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.techBg,
        border: Border.all(color: AppColors.ink, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: AppColors.violet,
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
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(items[idx].$1, color: color, size: 22),
                        if (idx == 2 &&
                            _store.customerNotifications.any((n) => !n.isRead))
                          Positioned(
                            right: -8,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              color: AppColors.pink,
                              child: Text(
                                '${_store.customerNotifications.where((n) => !n.isRead).length}',
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

  Widget _buildActiveCustomerScreen(BuildContext context) {
    switch (_selectedScreenIndex) {
      case 0:
        return _buildCustomerHomeDashboardView();
      case 1:
        return _buildSavedAddressesView();
      case 2:
      case 12:
        return _buildCreateOrderView();
      case 3:
      case 13:
        return _buildPricingAndVoucherView();
      case 4:
        return _buildLiveGpsTrackingView();
      case 5:
        return _buildInAppChatView();
      case 6:
        return _buildCancelOrderSheetView();
      case 7:
        return _buildOrderHistoryAndPodView();
      case 8:
        return _buildRateDriverView();
      case 9:
        return _buildSubmitComplaintView();
      case 10:
        return _buildCustomerProfileView();
      case 11:
        return _buildNotificationCenterView();
      case 14:
        return _buildDedicatedVoucherUc11View();
      default:
        return _buildCustomerHomeDashboardView();
    }
  }

  Widget _buildCustomerHomeDashboardView() {
    final myOrders = _store.customerOrders;
    final recentOrders = myOrders;
    final activeOrders = myOrders
        .where(
          (o) =>
              o.status != OrderStatus.delivered &&
              o.status != OrderStatus.cancelled &&
              o.status != OrderStatus.failed &&
              o.status != OrderStatus.returning,
        )
        .toList();
    final activeOrdersCount = activeOrders.length;
    final selectedActive = _store.activeCustomerOrderRecord;
    final primaryActiveOrder = (selectedActive != null &&
            activeOrders.any((o) => o.trackingCode == selectedActive.trackingCode))
        ? selectedActive
        : (activeOrders.isNotEmpty ? activeOrders.first : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. GrabExpress-style Hero & Quick "Where to deliver?" Route Box
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.techBg,
            border: Border.all(color: AppColors.ink, width: 1.8),
            boxShadow: const [
              BoxShadow(
                color: AppColors.violet,
                offset: Offset(6, 6),
                blurRadius: 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Animated3dIconBadge(
                        style: Icon3dStyle.scooterExpress,
                        size: 64,
                        showRadarPulse: false,
                        isSelected: true,
                        onTap: () => setState(() => _selectedScreenIndex = 4),
                      ),
                      const SizedBox(width: 14),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              color: AppColors.acid,
                              child: const Text(
                                'GHST EXPRESS • GIAO NHẬN TỨC THÌ',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'Consolas',
                                  color: AppColors.techBg,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Xin chào, ${_store.customerFullName}!',
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.6,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _store.customerDefaultAddress.isNotEmpty
                                  ? 'Lấy hàng tại: ${_store.customerDefaultAddress}'
                                  : 'Chọn điểm giao bên dưới để đặt xe lấy hàng ngay',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.techMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          side: const BorderSide(
                            color: AppColors.techLine,
                            width: 1.2,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        onPressed: () =>
                            setState(() => _selectedScreenIndex = 1),
                        icon: const Icon(
                          Icons.bookmarks_outlined,
                          size: 16,
                          color: AppColors.acid,
                        ),
                        label: const Text(
                          'Sổ địa chỉ',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          side: const BorderSide(
                            color: AppColors.acid,
                            width: 1.2,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        onPressed: () =>
                            setState(() => _selectedScreenIndex = 14),
                        icon: const Icon(
                          Icons.local_offer_outlined,
                          size: 16,
                          color: AppColors.acid,
                        ),
                        label: Text(
                          'Ưu đãi (${_store.vouchers.where((v) => v.status == "Đang hoạt động").length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // GrabExpress "Giao hàng đến đâu?" Interactive Quick Search Bar
              Material(
                color: Colors.white,
                child: InkWell(
                  onTap: () => setState(() => _selectedScreenIndex = 2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.acid, width: 2.0),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          color: AppColors.pink,
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Bạn muốn giao hàng đến đâu?',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  color: AppColors.ink,
                                ),
                              ),
                              Text(
                                _dropoffCtrl.text.isNotEmpty
                                    ? 'Điểm nhận: ${_dropoffCtrl.text}'
                                    : 'Chạm để nhập địa chỉ người nhận, chọn gói cước & đặt tài xế ngay...',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          color: AppColors.ink,
                          child: const Text(
                            'ĐẶT ĐƠN →',
                            style: TextStyle(
                              color: AppColors.acid,
                              fontWeight: FontWeight.w900,
                              fontSize: 11.5,
                              fontFamily: 'Consolas',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Live Active Order Banner (giống thanh tiến trình đơn đang giao trên Grab)
        if (primaryActiveOrder != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              border: Border.all(color: AppColors.ink, width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.ink,
                  offset: Offset(4, 4),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: AppColors.ink,
                      child: const Icon(
                        Icons.radar_rounded,
                        color: AppColors.acid,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ĐƠN ĐANG GIAO ${primaryActiveOrder.trackingCode} • ${primaryActiveOrder.status.displayName.toUpperCase()}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12.5,
                              color: AppColors.ink,
                              fontFamily: 'Consolas',
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tài xế: ${primaryActiveOrder.assignedDriverName ?? "Đang điều phối"} • Giao tới: ${primaryActiveOrder.dropoffAddress}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF166534),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.ink,
                        foregroundColor: AppColors.acid,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                      ),
                      onPressed: () {
                        _store.selectCustomerOrder(
                          primaryActiveOrder.trackingCode,
                        );
                        setState(() => _selectedScreenIndex = 4);
                      },
                      icon: const Icon(Icons.my_location_rounded, size: 15),
                      label: const Text(
                        'Bản đồ GPS',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.ink,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                      ),
                      onPressed: () {
                        _store.selectCustomerOrder(
                          primaryActiveOrder.trackingCode,
                        );
                        setState(() => _selectedScreenIndex = 5);
                      },
                      icon: const Icon(Icons.chat_bubble_outline, size: 14),
                      label: const Text(
                        'Chat TX',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        // 2. Quick Service Cards (4 gói dịch vụ gắn Hoạt ảnh Biểu tượng 3D 60 FPS & Giá cước CSDL)
        const Text(
          'Dịch vụ giao nhận nổi bật',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWideGrid = constraints.maxWidth >= 720;
            final baseFare = _store.baseFareConfig;
            final serviceItems = [
              (
                'Giao nhanh 30 phút',
                'Lấy & giao tức thì nội thành',
                'Từ ${CurrencyFormatter.formatVnd(baseFare * 1.4)}',
                Icon3dStyle.scooterExpress,
                AppColors.pink,
                DeliveryServiceType.express30m,
                false,
              ),
              (
                'Giao tiêu chuẩn 2 giờ',
                'Tối ưu chi phí trong ngày',
                'Từ ${CurrencyFormatter.formatVnd(baseFare)}',
                Icon3dStyle.parcelBox,
                AppColors.violet,
                DeliveryServiceType.standard,
                false,
              ),
              (
                'Giao tiết kiệm 4 giờ',
                'Ghép tuyến thông minh giá rẻ',
                'Từ ${CurrencyFormatter.formatVnd(baseFare * 0.8)}',
                Icon3dStyle.walletVault,
                AppColors.success,
                DeliveryServiceType.saving,
                false,
              ),
              (
                'Đặt lịch hẹn giờ',
                'Chủ động chọn khung giờ lấy',
                'Từ ${CurrencyFormatter.formatVnd(baseFare)}',
                Icon3dStyle.gpsPinRadar,
                AppColors.ink,
                DeliveryServiceType.standard,
                true,
              ),
            ];
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: serviceItems.map((item) {
                final cardWidth = isWideGrid
                    ? (constraints.maxWidth - 42) / 4
                    : (constraints.maxWidth - 14) / 2;
                final isCurrentService =
                    _selectedService == item.$6 && _isScheduledDelivery == item.$7;
                return SizedBox(
                  width: cardWidth,
                  child: InkWell(
                    onTap: () => setState(() {
                      _selectedService = item.$6;
                      _isScheduledDelivery = item.$7;
                      _selectedScreenIndex = 2;
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                          color: isCurrentService ? item.$5 : AppColors.ink,
                          width: isCurrentService ? 2.0 : 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isCurrentService ? item.$5 : AppColors.ink,
                            offset: const Offset(4, 4),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              Animated3dIconBadge(
                                style: item.$4,
                                size: isWideGrid ? 52 : 42,
                                showRadarPulse: isWideGrid,
                                isSelected: isCurrentService,
                                onTap: () => setState(() {
                                  _selectedService = item.$6;
                                  _isScheduledDelivery = item.$7;
                                  _selectedScreenIndex = 2;
                                }),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.paper,
                                  border: Border.all(
                                    color: AppColors.ink,
                                    width: 1.0,
                                  ),
                                ),
                                child: Text(
                                  item.$3,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'Consolas',
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            item.$1,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.$2,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 22),
        // 3. Two-Column Dashboard Content: Recent Orders & Account Utilities
        LayoutBuilder(
          builder: (context, constraints) {
            final isSplit = constraints.maxWidth >= 740;
            final ordersPanel = Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.ink, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.ink,
                    offset: Offset(4, 4),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Đơn hàng gần đây ($activeOrdersCount đang giao)',
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _selectedScreenIndex = 7),
                        child: const Text(
                          'Xem tất cả →',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (recentOrders.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 28,
                        horizontal: 18,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.paper,
                        border: Border.all(color: AppColors.ink, width: 1.2),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.inbox_outlined,
                            size: 38,
                            color: AppColors.violet,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Bạn chưa có đơn hàng nào',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tạo đơn hàng mới để bắt đầu gửi hàng và theo dõi lộ trình GPS 3D thời gian thực.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () =>
                                setState(() => _selectedScreenIndex = 2),
                            icon: const Icon(Icons.add_box_outlined, size: 16),
                            label: const Text('Đặt đơn giao ngay'),
                          ),
                        ],
                      ),
                    )
                  else
                    ...recentOrders.map((ord) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.paper,
                          border: Border.all(color: AppColors.ink, width: 1.2),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.violet,
                                border: Border.all(
                                  color: AppColors.ink,
                                  width: 1.2,
                                ),
                              ),
                              child: const Icon(
                                Icons.inventory_2_outlined,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
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
                                        ord.trackingCode,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13.5,
                                          fontFamily: 'Consolas',
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        color: AppColors.acid,
                                        child: Text(
                                          ord.status.displayName,
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.ink,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${ord.pickupAddress} → ${ord.dropoffAddress}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                minimumSize: Size.zero,
                              ),
                              onPressed: () {
                                _store.selectCustomerOrder(ord.trackingCode);
                                setState(() => _selectedScreenIndex = 4);
                              },
                              child: const Text(
                                'Định vị',
                                style: TextStyle(fontSize: 11.5),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            );

            final activeVouchers = _store.vouchers
                .where((v) => v.status == 'Đang hoạt động')
                .toList();
            final utilitiesPanel = Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.ink, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.ink,
                    offset: Offset(4, 4),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Ưu đãi đang áp dụng & Biểu phí',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => _selectedScreenIndex = 14),
                          child: const Text(
                            'Kho mã →',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...activeVouchers.map((v) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.paper,
                          border: Border.all(color: AppColors.ink, width: 1.2),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              color: AppColors.pink,
                              child: Text(
                                v.discountLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${v.code} • ${v.title}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  Text(
                                    'Đơn từ ${CurrencyFormatter.formatVnd(v.minOrderValue)} • HSD: ${v.expiryDate}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                minimumSize: Size.zero,
                              ),
                              onPressed: () => setState(() {
                                _voucherCtrl.text = v.code;
                                _selectedScreenIndex = 2;
                              }),
                              child: const Text(
                                'Dùng mã',
                                style: TextStyle(fontSize: 11.5),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.paper,
                        border: Border.all(color: AppColors.ink, width: 1.0),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Cấu hình cước phí minh bạch hiện hành',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '• Cước mở cửa (2 km đầu): ${CurrencyFormatter.formatVnd(_store.baseFareConfig)}\n'
                            '• Đơn giá các km tiếp theo: ${CurrencyFormatter.formatVnd(_store.pricePerKmConfig)}/km\n'
                            '• Giờ cao điểm: ${_store.isPeakSurchargeActive ? "Đang áp dụng phụ phí" : "Không áp dụng phụ phí"}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );

            if (isSplit) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: ordersPanel),
                  const SizedBox(width: 20),
                  Expanded(flex: 5, child: utilitiesPanel),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ordersPanel,
                const SizedBox(height: 16),
                utilitiesPanel,
              ],
            );
          },
        ),
      ],
    );
  }

  void _rebuildCustomerUi(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }
}
