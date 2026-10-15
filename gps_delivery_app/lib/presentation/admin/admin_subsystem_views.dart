import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/geo_math.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/entities/geo_point.dart';
import '../widgets/system_state_screens.dart';

/// Phân hệ Quản trị viên (Admin Web Portal) - 12 màn hình (Hình 8.24 - 8.35)
/// Bao phủ đầy đủ UC22 - UC29, UC43 - UC46 theo Thiết kế Giao diện Chương 8.3
class AdminSubsystemEntry extends StatefulWidget {
  const AdminSubsystemEntry({super.key});

  @override
  State<AdminSubsystemEntry> createState() => _AdminSubsystemEntryState();
}

class _AdminSubsystemEntryState extends State<AdminSubsystemEntry> {
  final AppStateStore _store = AppStateStore.instance;
  int _selectedScreenIndex = 0; // Mặc định: UC22 Dashboard Tổng quan

  // UC26: Cấu hình giá cước
  late final TextEditingController _baseFareCtrl;
  late final TextEditingController _perKmCtrl;

  // UC28: Trả lời khiếu nại
  final TextEditingController _replyTicketCtrl = TextEditingController();

  // UC44: Kiểm tra điểm Geofence & Vẽ Polygon trực tiếp trên bản đồ
  final TextEditingController _testLatCtrl =
      TextEditingController(text: '10.7520');
  final TextEditingController _testLngCtrl =
      TextEditingController(text: '106.6720');
  final TextEditingController _newZoneNameCtrl = TextEditingController(
    text: 'Vùng Phụ phí Khu Công nghệ cao Q.9',
  );
  final List<Offset> _draftPolygonOffsets = [
    const Offset(0.25, 0.45),
    const Offset(0.55, 0.42),
    const Offset(0.60, 0.72),
    const Offset(0.28, 0.75),
  ];
  String _geofenceCheckResult =
      'Nhấn Kiểm tra để xác định vùng Geofence bằng thuật toán Ray-Casting';

  // UC45: Gửi thông báo Broadcast
  final TextEditingController _broadcastTitleCtrl = TextEditingController(
    text: 'Bảo trì nâng cấp cụm máy chủ định vị PostGIS lúc 02:00 sáng mai',
  );
  String _broadcastTarget = 'Tất cả người dùng';

  // UC46: Chọn nhóm quyền RBAC
  int _selectedRbacRoleIndex = 1; // Mặc định: Điều phối viên

  static const List<String> _screenTitles = [
    '8.24: UC22 Dashboard Tổng quan Hệ thống',
    '8.25: UC23 Quản lý Người dùng & Cửa hàng',
    '8.26: UC24 Duyệt Hồ sơ Tài xế (KYC)',
    '8.27: UC25 Bản đồ Giám sát Đội xe GPS',
    '8.28: UC26 Cấu hình Bảng giá & Phụ phí',
    '8.29: UC27 Quản lý Chiến dịch Voucher',
    '8.30: UC28 Giải quyết Khiếu nại (Ticket)',
    '8.31: UC29 Đối soát & Duyệt Rút tiền',
    '8.32: UC43 Điều phối Đơn hàng Thủ công',
    '8.33: UC44 Bản đồ Vùng Geofencing Polygon',
    '8.34: UC45 Gửi Thông báo Hàng loạt (Push)',
    '8.35: UC46 Phân quyền Quản trị viên (RBAC)',
  ];

  @override
  void initState() {
    super.initState();
    _baseFareCtrl =
        TextEditingController(text: _store.baseFareConfig.toStringAsFixed(0));
    _perKmCtrl =
        TextEditingController(text: _store.pricePerKmConfig.toStringAsFixed(0));
    _store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _baseFareCtrl.dispose();
    _perKmCtrl.dispose();
    _replyTicketCtrl.dispose();
    _testLatCtrl.dispose();
    _testLngCtrl.dispose();
    _newZoneNameCtrl.dispose();
    _broadcastTitleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 265,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.darkSidebar,
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Text(
                        'ADMIN PORTAL CMS\nVai trò: ${_store.currentAdminRoleName}',
                        style: const TextStyle(
                          color: AppColors.surface,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Divider(color: Colors.white24),
                    ...List.generate(_screenTitles.length, (index) {
                      final selected = _selectedScreenIndex == index;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        selectedTileColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        title: Text(
                          _screenTitles[index],
                          style: TextStyle(
                            color:
                                selected ? AppColors.surface : Colors.white70,
                            fontSize: 12,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        onTap: () =>
                            setState(() => _selectedScreenIndex = index),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildActiveAdminRoleHeader(),
                    const SizedBox(height: AppSpacing.sm),
                    _buildActiveAdminScreen(context),
                  ],
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildActiveAdminRoleHeader(),
            const SizedBox(height: AppSpacing.xs),
            _buildScreenSelectorBar(),
            const SizedBox(height: AppSpacing.md),
            _buildActiveAdminScreen(context),
          ],
        );
      },
    );
  }

  Widget _buildActiveAdminRoleHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.admin_panel_settings_outlined,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 6),
          const Text(
            'Phiên quyền RBAC:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _store.rbacRoles.map((r) {
                  final active = _store.currentAdminRoleName == r.roleName;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        r.roleName,
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: active,
                      onSelected: (_) => _store.setAdminActiveRole(r.roleName),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
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

  Widget _buildActiveAdminScreen(BuildContext context) {
    switch (_selectedScreenIndex) {
      case 0:
        return _buildSystemOverviewDashboard();
      case 1:
        return _buildUserAndMerchantManagementView();
      case 2:
        return _buildDriverKycApprovalView();
      case 3:
        return _buildFleetLiveGpsMonitorView();
      case 4:
        return _buildDynamicPricingConfigView();
      case 5:
        return _buildVoucherCampaignsView();
      case 6:
        return _buildComplaintResolutionView();
      case 7:
        return _buildFinancialWithdrawalApprovalView();
      case 8:
        return _buildManualOrderDispatchView();
      case 9:
        return _buildGeofencePolygonZonesView();
      case 10:
        return _buildBroadcastNotificationView();
      case 11:
        return _buildRbacPermissionMatrixView();
      default:
        return _buildSystemOverviewDashboard();
    }
  }

  /// Hình 8.24: UC22 Dashboard Tổng quan Hệ thống
  Widget _buildSystemOverviewDashboard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.24: Dashboard Tổng quan Hệ thống (UC22)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _adminKpi('Đơn hàng hôm nay', '1,248 (+12.5%)', AppColors.primary),
                _adminKpi('Tài xế trực tuyến', '312 (+5.2%)', AppColors.success),
                _adminKpi('Doanh thu ngày', '45.6M VNĐ (+8.4%)', AppColors.accent),
                _adminKpi('Tỷ lệ thành công', '98.2%', AppColors.success),
              ],
            ),
            const Divider(),
            Text(
              'Trạng thái Đồng bộ CSDL: ${_store.lastSyncStatusMessage}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Danh sách vận đơn thời gian thực trên toàn hệ thống:',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            ..._store.orders.map(
              (o) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${o.trackingCode} • Khách: ${o.customerName} -> ${o.recipientName}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Tài xế: ${o.assignedDriverName ?? "Chưa gán"} • Phí: ${CurrencyFormatter.formatVnd(o.totalAmount)}',
                ),
                trailing: Chip(
                  label: Text(
                    o.status.displayName,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adminKpi(String label, String val, Color color) {
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
          const SizedBox(height: 2),
          Text(
            val,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Hình 8.25: UC23 Quản lý Người dùng & Cửa hàng
  Widget _buildUserAndMerchantManagementView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.25: Quản lý Tài khoản Người dùng & Đối tác (UC23)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Text('KH')),
              title: Text(
                '${_store.customerFullName} (${_store.customerPhone})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle:
                  Text('Vai trò: CUSTOMER • Email: ${_store.customerEmail}'),
              trailing: const Chip(label: Text('Hoạt động')),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Text('B2B')),
              title: Text(
                '${_store.merchantStoreName} (MST: ${_store.merchantTaxCode})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Vai trò: MERCHANT • Đại diện: ${_store.merchantRepresentative}',
              ),
              trailing: const Chip(label: Text('Đã xác thực')),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.26: UC24 Xét duyệt Hồ sơ Tài xế (KYC + Kiểm tra quyền RBAC 'Tài xế: Phê duyệt')
  Widget _buildDriverKycApprovalView() {
    final canApproveDriver = _store.hasAdminPermission('Tài xế: Phê duyệt');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.26: Xét duyệt Hồ sơ Đăng ký Tài xế KYC (UC24)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (!canApproveDriver)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '🔒 Vai trò hiện tại không có quyền "Tài xế: Phê duyệt" (Cấu hình tại UC46).',
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            ..._store.drivers.map(
              (drv) => Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${drv.id} • ${drv.fullName} (${drv.phone})',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'CCCD: ${drv.citizenId} • Xe: ${drv.vehicleType} (${drv.licensePlate}) • Trạng thái: ${drv.approvalStatus}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: canApproveDriver
                          ? () =>
                              _store.updateDriverApproval(drv.id, 'Đã duyệt')
                          : null,
                      child: const Text('Duyệt hồ sơ'),
                    ),
                    TextButton(
                      onPressed: canApproveDriver
                          ? () => _store.updateDriverApproval(drv.id, 'Từ chối')
                          : null,
                      child: const Text(
                        'Từ chối',
                        style: TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.27: UC25 Bản đồ Giám sát Đội xe GPS Toàn Thành phố
  Widget _buildFleetLiveGpsMonitorView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.27: Bản đồ Giám sát Đội xe GPS Thời gian thực (UC25)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children: const [
                Chip(label: Text('Đang rảnh: 340 xe (Xanh lá)')),
                Chip(label: Text('Đang giao hàng: 180 xe (Cam)')),
                Chip(label: Text('Ngoại tuyến: 45 xe (Xám)')),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Map3dPerspectiveWidget(
              height: 250,
              is3dMode: _store.isMap3dEnabled,
              speedKmh: _store.currentSpeedKmh,
              onToggle3d: _store.toggleMap3d,
              progressFraction: _store.routeProgressStep / 10.0,
              nextTurnInstruction:
                  'Trung tâm Điều hành PostGIS • 520 Tài xế đang phát tọa độ',
              roadName:
                  'Tọa độ xe #1: (${_store.activeDriverLocation.latitude.toStringAsFixed(4)}, ${_store.activeDriverLocation.longitude.toStringAsFixed(4)})',
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.28: UC26 Cấu hình Công thức Tính cước & Phụ phí
  Widget _buildDynamicPricingConfigView() {
    final canEditSystem = _store.hasAdminPermission('Hệ thống: Cài đặt');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.28: Cấu hình Bảng giá & Phụ phí Động (UC26 - RULE-PRC-01)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _baseFareCtrl,
                    enabled: canEditSystem,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Giá mở cửa 2km đầu (VNĐ)',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _perKmCtrl,
                    enabled: canEditSystem,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Đơn giá mỗi km tiếp theo (VNĐ/km)',
                    ),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Phụ phí giờ cao điểm (+10.000đ)'),
              subtitle: const Text('Áp dụng từ 17:00 - 19:00'),
              value: _store.isPeakSurchargeActive,
              onChanged: canEditSystem
                  ? (v) => setState(() => _store.isPeakSurchargeActive = v)
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Phụ phí thời tiết xấu / Mưa ngập (+15.000đ)'),
              value: _store.isWeatherSurchargeActive,
              onChanged: canEditSystem
                  ? (v) => setState(() => _store.isWeatherSurchargeActive = v)
                  : null,
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                ),
                onPressed: canEditSystem
                    ? () {
                        setState(() {
                          _store.baseFareConfig =
                              double.tryParse(_baseFareCtrl.text) ?? 25000;
                          _store.pricePerKmConfig =
                              double.tryParse(_perKmCtrl.text) ?? 5000;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Đã cập nhật cấu hình giá cước hệ thống!'),
                          ),
                        );
                      }
                    : null,
                child: const Text('Lưu cấu hình Bảng giá'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.29: UC27 Quản lý Chiến dịch Khuyến mãi & Mã giảm giá
  Widget _buildVoucherCampaignsView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.29: Quản lý Chiến dịch Khuyến mãi & Voucher (UC27)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._store.vouchers.map(
              (v) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.local_offer_outlined,
                  color: AppColors.accent,
                ),
                title: Text(
                  '${v.code} • ${v.title}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Mức giảm: ${v.discountLabel} • Đơn tối thiểu: ${CurrencyFormatter.formatVnd(v.minOrderValue)} • HSD: ${v.expiryDate}',
                ),
                trailing: Chip(label: Text(v.status)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.30: UC28 Giải quyết Khiếu nại & Sự cố
  Widget _buildComplaintResolutionView() {
    final activeTicket = _store.complaints.first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.30: Trung tâm Giải quyết Khiếu nại & Sự cố (UC28)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Ticket đang chọn: ${activeTicket.ticketCode} (${activeTicket.orderId}) • Loại: ${activeTicket.issueType} • Trạng thái: ${activeTicket.status}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            ...activeTicket.replies.map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• $r', style: const TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _replyTicketCtrl,
              decoration: const InputDecoration(
                labelText: 'Phản hồi của Quản trị viên / Phương án đền bù',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                    ),
                    onPressed: () {
                      _store.replyComplaint(
                        activeTicket.ticketCode,
                        _replyTicketCtrl.text,
                        'Đã giải quyết',
                      );
                      _replyTicketCtrl.clear();
                    },
                    child: const Text('Phản hồi & Đóng khiếu nại'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.31: UC29 Đối soát Tài chính & Phê duyệt Rút tiền (Kiểm tra quyền RBAC 'Tài chính: Thanh toán')
  Widget _buildFinancialWithdrawalApprovalView() {
    final canApprovePayout = _store.hasAdminPermission('Tài chính: Thanh toán');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.31: Đối soát Tài chính & Duyệt Lệnh Rút tiền (UC29)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (!canApprovePayout)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '🔒 Vai trò hiện tại không có quyền "Tài chính: Thanh toán" (Cấu hình tại UC46).',
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            ..._store.withdrawalRequests.map(
              (req) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${req.ownerName} (${req.ownerRole}) • ${CurrencyFormatter.formatVnd(req.amount)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${req.bankName} (${req.accountMasked}) • Ngày: ${req.requestDate} • Trạng thái: ${req.status}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: canApprovePayout
                          ? () =>
                              _store.updateWithdrawalStatus(req.id, 'Đã duyệt')
                          : null,
                      child: const Text('Duyệt lệnh'),
                    ),
                    TextButton(
                      onPressed: canApprovePayout
                          ? () =>
                              _store.updateWithdrawalStatus(req.id, 'Từ chối')
                          : null,
                      child: const Text(
                        'Từ chối',
                        style: TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.32: UC43 Quản lý & Điều phối Đơn hàng Thủ công
  Widget _buildManualOrderDispatchView() {
    final canEditOrder = _store.hasAdminPermission('Đơn: Sửa');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.32: Quản lý & Điều phối Đơn hàng Thủ công (UC43)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._store.orders.map(
              (ord) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${ord.trackingCode} • ${ord.pickupAddress} -> ${ord.dropoffAddress}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Trạng thái: ${ord.status.displayName} • Tài xế: ${ord.assignedDriverName ?? "Chưa có tài xế"}',
                ),
                trailing: ElevatedButton(
                  onPressed: canEditOrder
                      ? () => _store.driverAcceptOrder(ord.trackingCode)
                      : null,
                  child: const Text('Gán tài xế ngay'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.33: UC44 Quản lý Vùng hoạt động Geofencing Polygon (Tương tác chấm đỉnh trên bản đồ)
  Widget _buildGeofencePolygonZonesView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.33: Quản lý Vùng Hoạt động Geofencing Polygon (UC44)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Chạm trực tiếp lên bản đồ bên dưới để thêm đỉnh đa giác (Polygon Vertex) mới:',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Map3dPerspectiveWidget(
              height: 220,
              is3dMode: false,
              drawnPolygonPoints: _draftPolygonOffsets,
              nextTurnInstruction:
                  'Công cụ Vẽ Đa giác PostGIS • Đã chấm ${_draftPolygonOffsets.length} đỉnh',
              roadName: 'Chạm lên bản đồ để thêm đỉnh Polygon',
              onTapRelativePoint: (relOffset) {
                setState(() {
                  _draftPolygonOffsets.add(relOffset);
                });
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newZoneNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên vùng Geofence mới',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => setState(() => _draftPolygonOffsets.clear()),
                  child: const Text('Xóa đỉnh'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _draftPolygonOffsets.length >= 3
                      ? () {
                          final vertices = _draftPolygonOffsets
                              .map(
                                (o) => GeoPoint(
                                  latitude: 10.740 + o.dy * 0.05,
                                  longitude: 106.660 + o.dx * 0.06,
                                ),
                              )
                              .toList();
                          _store.addCustomGeofenceZone(
                            zoneName: _newZoneNameCtrl.text,
                            zoneType: 'SURCHARGE_ZONE',
                            surchargeRate: 20000,
                            vertices: vertices,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Đã lưu vùng Polygon mới vào bảng geofence_zones!',
                              ),
                            ),
                          );
                        }
                      : null,
                  child: const Text('Lưu Polygon mới'),
                ),
              ],
            ),
            const Divider(),
            ..._store.geofenceZones.map(
              (z) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${z.zoneName} (${z.zoneType})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Phụ phí vùng: ${CurrencyFormatter.formatVnd(z.surchargeRate)} • Số đỉnh Polygon: ${z.boundary.length}',
                ),
                value: z.isActive,
                onChanged: (v) => _store.toggleGeofenceZone(z.id, v),
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _testLatCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Vĩ độ kiểm tra (Lat)'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _testLngCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Kinh độ kiểm tra (Lng)',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton(
                  onPressed: () {
                    final pt = GeoPoint(
                      latitude: double.tryParse(_testLatCtrl.text) ?? 10.752,
                      longitude: double.tryParse(_testLngCtrl.text) ?? 106.672,
                    );
                    final matched = _store.geofenceZones
                        .where(
                          (z) =>
                              z.isActive &&
                              GeoMath.isPointInPolygon(pt, z.boundary),
                        )
                        .firstOrNull;
                    setState(() {
                      _geofenceCheckResult = matched != null
                          ? 'Thuộc vùng: ${matched.zoneName} (Phụ phí: ${CurrencyFormatter.formatVnd(matched.surchargeRate)})'
                          : 'Tọa độ nằm ngoài các vùng phụ phí đặc biệt.';
                    });
                  },
                  child: const Text('Kiểm tra Polygon'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _geofenceCheckResult,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.34: UC45 Gửi Thông báo Hệ thống Hàng loạt (Broadcast Push)
  Widget _buildBroadcastNotificationView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.34: Phát Thông báo Hệ thống Hàng loạt (UC45)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children: [
                'Tất cả người dùng',
                'Khách hàng',
                'Tài xế',
                'Cửa hàng B2B',
              ].map((g) {
                return ChoiceChip(
                  label: Text(g),
                  selected: _broadcastTarget == g,
                  onSelected: (_) => setState(() => _broadcastTarget = g),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _broadcastTitleCtrl,
              decoration: const InputDecoration(
                labelText: 'Tiêu đề & Nội dung thông báo Push Notification',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                ),
                onPressed: () {
                  _store.broadcastSystemNotification(
                    title: _broadcastTitleCtrl.text,
                    targetGroup: _broadcastTarget,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã phát thông báo tới nhóm: $_broadcastTarget!',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Gửi thông báo ngay (FCM Push)'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.35: UC46 Phân quyền Quản trị viên (RBAC Permission Matrix)
  Widget _buildRbacPermissionMatrixView() {
    final activeRole = _store.rbacRoles[_selectedRbacRoleIndex];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.35: Ma trận Phân quyền Quản trị viên RBAC (UC46)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children: List.generate(_store.rbacRoles.length, (index) {
                final r = _store.rbacRoles[index];
                return ChoiceChip(
                  label: Text(r.roleName),
                  selected: _selectedRbacRoleIndex == index,
                  onSelected: (_) =>
                      setState(() => _selectedRbacRoleIndex = index),
                );
              }),
            ),
            const Divider(),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: activeRole.permissions.entries.map((entry) {
                return FilterChip(
                  label: Text(entry.key),
                  selected: entry.value,
                  onSelected: (v) => _store.toggleRbacPermission(
                    activeRole.roleName,
                    entry.key,
                    v,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
