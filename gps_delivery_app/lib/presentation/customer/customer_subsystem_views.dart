import 'package:flutter/material.dart';
import '../../core/gps/smart_dispatch_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/security_and_barcode_utils.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/entities/pricing_estimate.dart';
import '../../domain/enums/order_status.dart';
import '../../domain/enums/service_type.dart';
import '../widgets/system_state_screens.dart';

/// Phân hệ Khách hàng (Customer App) - 14 màn hình (Hình 8.1 - Hình 8.14)
/// Bao phủ đầy đủ UC01 - UC12, UC41, UC42 theo Thiết kế Giao diện Chương 8.1
class CustomerSubsystemEntry extends StatefulWidget {
  const CustomerSubsystemEntry({super.key});

  @override
  State<CustomerSubsystemEntry> createState() => _CustomerSubsystemEntryState();
}

class _CustomerSubsystemEntryState extends State<CustomerSubsystemEntry> {
  final AppStateStore _store = AppStateStore.instance;
  int _selectedScreenIndex = 2; // Mặc định: UC03 Trang chủ & Tạo đơn

  // State cho UC01 & UC02 (Auth / OTP / Forgot Password)
  int _authTabIndex = 0; // 0: Đăng nhập, 1: Đăng ký, 2: OTP, 3: Quên mật khẩu
  final TextEditingController _phoneAuthCtrl =
      TextEditingController(text: '0912345678');
  final TextEditingController _otpCtrl = TextEditingController(text: '589210');

  // State cho UC03 & UC05 & UC06 (Tạo đơn hàng, Gói dịch vụ, Thanh toán & Voucher)
  final TextEditingController _pickupCtrl = TextEditingController(
    text: '145 Phố Huế, Hai Bà Trưng, Hà Nội',
  );
  final TextEditingController _dropoffCtrl = TextEditingController(
    text: 'Số 15, Ngõ 100, Đường Lê Trọng Tấn, Thanh Xuân, Hà Nội',
  );
  final TextEditingController _recipientNameCtrl =
      TextEditingController(text: 'Nguyễn Thị Minh An');
  final TextEditingController _recipientPhoneCtrl =
      TextEditingController(text: '0912345678');
  final TextEditingController _pkgDescCtrl =
      TextEditingController(text: '2x Áo thun Polo (Size M, Xanh)');
  final TextEditingController _weightCtrl = TextEditingController(text: '1.8');
  final TextEditingController _dimCtrl =
      TextEditingController(text: '30 x 20 x 10 cm');
  final TextEditingController _codCtrl =
      TextEditingController(text: '1500000');
  final TextEditingController _voucherCtrl =
      TextEditingController(text: 'PROMO20K');
  DeliveryServiceType _selectedService = DeliveryServiceType.express30m;
  String _selectedPaymentMethod = 'Tiền mặt (COD)';

  // State cho UC04 (Sổ địa chỉ)
  String _selectedAddressTag = 'Nhà';
  final TextEditingController _newAddressCtrl = TextEditingController();

  // State cho UC08 (Chat nội bộ)
  final TextEditingController _chatInputCtrl = TextEditingController();

  // State cho UC09 (Hủy đơn)
  String _selectedCancelReason = 'Tài xế ở quá xa';

  // State cho UC10 (Lịch sử đơn hàng)
  String _historyFilterTab = 'Tất cả';

  // State cho UC11 (Đánh giá 5 sao)
  int _ratingStars = 5;
  final Set<String> _selectedFeedbackChips = {
    'Thân thiện',
    'Đúng giờ',
    'Cẩn thận',
  };
  final TextEditingController _ratingCommentCtrl = TextEditingController(
    text: 'Tài xế giao hàng siêu tốc, đóng gói nguyên vẹn!',
  );

  // State cho UC12 (Khiếu nại)
  String _complaintType = 'Hàng hư hỏng';
  final TextEditingController _complaintDescCtrl = TextEditingController();

  // State cho UC41 (Hồ sơ cá nhân)
  late final TextEditingController _profileNameCtrl;
  late final TextEditingController _profilePhoneCtrl;
  late final TextEditingController _profileEmailCtrl;
  late final TextEditingController _profileAddressCtrl;

  // State cho UC42 (Trung tâm thông báo)
  String _notiFilter = 'Tất cả';

  static const List<String> _screenTitles = [
    '8.1-8.2: UC01/UC02 Đăng nhập & OTP',
    '8.3: UC04 Sổ địa chỉ đã lưu',
    '8.4: UC03 Tạo đơn & Chọn gói dịch vụ',
    '8.5: UC05/UC06 Xác nhận giá & Voucher',
    '8.6: UC07 Theo dõi GPS 3D Real-time',
    '8.7: UC08 Chat & Gọi tài xế',
    '8.8: UC09 Hủy đơn hàng & Lý do',
    '8.9-8.10: UC10 Lịch sử & Chi tiết POD',
    '8.11: UC11 Đánh giá tài xế 5 sao',
    '8.12: UC12 Gửi khiếu nại & Bằng chứng',
    '8.13: UC41 Quản lý Hồ sơ cá nhân',
    '8.14: UC42 Trung tâm Thông báo',
  ];

  @override
  void initState() {
    super.initState();
    _profileNameCtrl = TextEditingController(text: _store.customerFullName);
    _profilePhoneCtrl = TextEditingController(text: _store.customerPhone);
    _profileEmailCtrl = TextEditingController(text: _store.customerEmail);
    _profileAddressCtrl =
        TextEditingController(text: _store.customerDefaultAddress);
    _store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _phoneAuthCtrl.dispose();
    _otpCtrl.dispose();
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
    _ratingCommentCtrl.dispose();
    _complaintDescCtrl.dispose();
    _profileNameCtrl.dispose();
    _profilePhoneCtrl.dispose();
    _profileEmailCtrl.dispose();
    _profileAddressCtrl.dispose();
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
        _buildActiveCustomerScreen(context),
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

  Widget _buildActiveCustomerScreen(BuildContext context) {
    switch (_selectedScreenIndex) {
      case 0:
        return _buildAuthAndOtpView();
      case 1:
        return _buildSavedAddressesView();
      case 2:
        return _buildCreateOrderView();
      case 3:
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
      default:
        return _buildCreateOrderView();
    }
  }

  /// Hình 8.1 & Hình 8.2: UC01 (Đăng ký & OTP 6 số) + UC02 (Đăng nhập & Quên mật khẩu)
  Widget _buildAuthAndOtpView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_user, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Hình 8.1 & 8.2: Xác thực Người dùng (UC01 & UC02)',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Đăng nhập'),
                  selected: _authTabIndex == 0,
                  onSelected: (_) => setState(() => _authTabIndex = 0),
                ),
                ChoiceChip(
                  label: const Text('Đăng ký'),
                  selected: _authTabIndex == 1,
                  onSelected: (_) => setState(() => _authTabIndex = 1),
                ),
                ChoiceChip(
                  label: const Text('Xác thực OTP (6 số)'),
                  selected: _authTabIndex == 2,
                  onSelected: (_) => setState(() => _authTabIndex = 2),
                ),
                ChoiceChip(
                  label: const Text('Quên mật khẩu'),
                  selected: _authTabIndex == 3,
                  onSelected: (_) => setState(() => _authTabIndex = 3),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _phoneAuthCtrl,
              decoration: const InputDecoration(
                labelText: 'Số điện thoại (+84)',
                prefixIcon: Icon(Icons.phone_android),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_authTabIndex == 0 || _authTabIndex == 1) ...[
              const TextField(
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Mật khẩu bảo mật (Bcrypt)',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              if (_authTabIndex == 1) ...[
                const SizedBox(height: AppSpacing.sm),
                const TextField(
                  decoration: InputDecoration(
                    labelText: 'Họ và tên khách hàng',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
              ],
            ] else if (_authTabIndex == 2) ...[
              TextField(
                controller: _otpCtrl,
                maxLength: 6,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Mã xác thực OTP 6 chữ số (Hiệu lực 120s)',
                  prefixIcon: Icon(Icons.pin_outlined),
                ),
              ),
              const Text(
                'Đếm ngược gửi lại mã: 00:54s',
                style: TextStyle(color: AppColors.accent, fontSize: 12),
              ),
            ] else ...[
              const Text(
                'Nhập số điện thoại đã đăng ký để nhận mã OTP đặt lại mật khẩu mới.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Xác thực JWT Token thành công! Đã chuyển sang Trang chủ.',
                      ),
                    ),
                  );
                  setState(() => _selectedScreenIndex = 2);
                },
                child: Text(
                  _authTabIndex == 0
                      ? 'Đăng nhập ngay'
                      : _authTabIndex == 1
                          ? 'Gửi mã OTP đăng ký'
                          : _authTabIndex == 2
                              ? 'Xác nhận OTP (6 số)'
                              : 'Khôi phục mật khẩu',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.3: UC04 Quản lý sổ địa chỉ đã lưu (Nhà, Cơ quan, Khác)
  Widget _buildSavedAddressesView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.3: Sổ địa chỉ đã lưu & Ghim bản đồ (UC04)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children: ['Nhà', 'Cơ quan', 'Khác'].map((tag) {
                return ChoiceChip(
                  label: Text(tag),
                  selected: _selectedAddressTag == tag,
                  onSelected: (_) => setState(() => _selectedAddressTag = tag),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newAddressCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Nhập địa chỉ mới hoặc ghim trên bản đồ...',
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton(
                  onPressed: () {
                    if (_newAddressCtrl.text.trim().isEmpty) return;
                    _store.addCustomerAddress(
                      _selectedAddressTag,
                      _newAddressCtrl.text.trim(),
                    );
                    _newAddressCtrl.clear();
                  },
                  child: const Text('+ Thêm mới'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ..._store.savedAddresses.map(
              (addr) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: Icon(
                    addr.label == 'Nhà'
                        ? Icons.home_outlined
                        : addr.label == 'Cơ quan'
                            ? Icons.business_outlined
                            : Icons.bookmark_border,
                    color: AppColors.primary,
                  ),
                ),
                title: Text(
                  '${addr.label} • (${addr.location.latitude.toStringAsFixed(4)}, ${addr.location.longitude.toStringAsFixed(4)})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(addr.fullAddress),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () {
                        _dropoffCtrl.text = addr.fullAddress;
                        setState(() => _selectedScreenIndex = 2);
                      },
                      child: const Text('Chọn giao'),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppColors.danger,
                      ),
                      onPressed: () => _store.removeCustomerAddress(addr.id),
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

  /// Hình 8.4: UC03 Tạo đơn hàng giao nhận & Chọn gói dịch vụ (Siêu tốc 30p, Tiêu chuẩn, Tiết kiệm)
  Widget _buildCreateOrderView() {
    final dropoffSuggestions =
        SmartDispatchEngine.searchAddressSuggestions(_dropoffCtrl.text);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.4: Tạo đơn hàng & Chọn gói dịch vụ (UC03)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _pickupCtrl,
              decoration: const InputDecoration(
                labelText: 'Điểm lấy hàng (Pickup Point - Màu xanh lá)',
                prefixIcon: Icon(Icons.my_location, color: AppColors.success),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _dropoffCtrl,
              decoration: const InputDecoration(
                labelText: 'Điểm giao hàng (Drop-off Point - Màu cam)',
                prefixIcon: Icon(Icons.location_on, color: AppColors.accent),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            const Text(
              'Gợi ý Geocoding Autocomplete (Chạm để chọn tọa độ GPS thực):',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: dropoffSuggestions.map((place) {
                return ActionChip(
                  avatar: const Icon(
                    Icons.place,
                    size: 14,
                    color: AppColors.accent,
                  ),
                  label: Text(
                    '${place.title} (${place.location.latitude.toStringAsFixed(4)}, ${place.location.longitude.toStringAsFixed(4)})',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: () =>
                      setState(() => _dropoffCtrl.text = place.fullAddress),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _recipientNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên người nhận',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _recipientPhoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'SĐT người nhận',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _pkgDescCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Mô tả hàng hóa',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _weightCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Khối lượng (kg)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Chọn gói dịch vụ vận chuyển:',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: DeliveryServiceType.values.map((svc) {
                final selected = _selectedService == svc;
                return ChoiceChip(
                  label: Text(
                    '${svc.displayName} (${CurrencyFormatter.formatVnd(svc.defaultBaseFare)})',
                  ),
                  selected: selected,
                  selectedColor: AppColors.accent,
                  labelStyle: TextStyle(
                    color: selected ? AppColors.surface : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) => setState(() => _selectedService = svc),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                ),
                onPressed: () => setState(() => _selectedScreenIndex = 3),
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('Tính cước tự động & Áp mã giảm giá (UC05)'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.5: UC05 & UC06 Xác nhận giá cước minh bạch, áp Voucher & chọn phương thức thanh toán
  Widget _buildPricingAndVoucherView() {
    double discountVal = 0;
    final code = _voucherCtrl.text.trim().toUpperCase();
    final matchedVoucher =
        _store.vouchers.where((v) => v.code == code).firstOrNull;
    if (matchedVoucher != null) {
      discountVal = matchedVoucher.discountValue;
    }

    final estimate = PricingEstimate.calculate(
      serviceType: _selectedService,
      distanceMeters: 14500,
      durationSeconds: 2700,
      isPeakHour: _store.isPeakSurchargeActive,
      geofenceSurcharge: 10000,
      voucherDiscount: discountVal,
    );

    final paymentSig = SecurityAndBarcodeUtils.generatePaymentSignature(
      orderCode: '#DH${100000 + _store.orders.length * 1423}',
      amount: estimate.totalAmount,
      method: _selectedPaymentMethod,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.5: Xác nhận giá cước & Áp dụng Voucher (UC05 & UC06)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _priceRow(
                    'Phí mở cửa (${_selectedService.displayName})',
                    CurrencyFormatter.formatVnd(estimate.baseFare),
                  ),
                  _priceRow(
                    'Phí quãng đường (${estimate.distanceKm.toStringAsFixed(1)} km)',
                    CurrencyFormatter.formatVnd(estimate.distanceFare),
                  ),
                  _priceRow(
                    'Phụ phí giờ cao điểm & Geofence',
                    CurrencyFormatter.formatVnd(estimate.surchargeFee),
                  ),
                  _priceRow(
                    'Khuyến mãi ($code)',
                    '-${CurrencyFormatter.formatVnd(estimate.discountAmount)}',
                    valueColor: AppColors.success,
                  ),
                  const Divider(),
                  _priceRow(
                    'Tổng thanh toán (Tự động tính)',
                    CurrencyFormatter.formatVnd(estimate.totalAmount),
                    isBold: true,
                    valueColor: AppColors.accent,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _voucherCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Mã giảm giá (VD: PROMO20K, GHN-OFF50K)',
                      prefixIcon: Icon(Icons.confirmation_number_outlined),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _codCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Tiền thu hộ COD (đ)',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Phương thức thanh toán (UC06):',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Wrap(
              spacing: 8,
              children: [
                'Tiền mặt (COD)',
                'Ví MoMo',
                'VNPay / VietQR',
                'ZaloPay',
              ].map((m) {
                return ChoiceChip(
                  label: Text(m),
                  selected: _selectedPaymentMethod == m,
                  onSelected: (_) => setState(() => _selectedPaymentMethod = m),
                );
              }).toList(),
            ),
            if (_selectedPaymentMethod != 'Tiền mặt (COD)') ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary),
                ),
                child: Row(
                  children: [
                    QrMatrixPainterWidget(
                      payload: '$_selectedPaymentMethod|$paymentSig',
                      size: 72,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mã QR Thanh toán $_selectedPaymentMethod (RULE-FIN-04)',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            'Idempotency Hash: $paymentSig',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: AppColors.primary,
                            ),
                          ),
                          const Text(
                            'Trạng thái Webhook IPN: Sẵn sàng xác thực tự động',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                ),
                onPressed: () {
                  final created = _store.createNewOrder(
                    pickupAddress: _pickupCtrl.text,
                    dropoffAddress: _dropoffCtrl.text,
                    recipientName: _recipientNameCtrl.text,
                    recipientPhone: _recipientPhoneCtrl.text,
                    packageDescription: _pkgDescCtrl.text,
                    weightKg: double.tryParse(_weightCtrl.text) ?? 1.5,
                    dimensionsCm: _dimCtrl.text,
                    serviceType: _selectedService,
                    codAmount: double.tryParse(_codCtrl.text) ?? 0,
                    paymentMethod: _selectedPaymentMethod,
                    voucherCode: _voucherCtrl.text,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã tạo đơn hàng ${created.trackingCode} thành công!',
                      ),
                    ),
                  );
                  setState(() => _selectedScreenIndex = 4);
                },
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Đặt giao hàng ngay'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              fontSize: isBold ? 16 : 14,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// Hình 8.6: UC07 Theo dõi vị trí Tài xế trên bản đồ 3D Real-time
  Widget _buildLiveGpsTrackingView() {
    final activeOrder = _store.orders.first;
    final remMeters = _store.distanceFromDriverToDropoffMeters();
    final etaMinutes = (remMeters / 500.0).ceil().clamp(1, 45);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.6: Theo dõi Tài xế GPS 3D Real-time (UC07)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Map3dPerspectiveWidget(
              is3dMode: _store.isMap3dEnabled,
              speedKmh: _store.currentSpeedKmh,
              onToggle3d: _store.toggleMap3d,
              progressFraction: _store.routeProgressStep / 10.0,
              nextTurnInstruction:
                  'Tài xế cách điểm giao ${(remMeters / 1000).toStringAsFixed(2)} km (ETA: $etaMinutes phút)',
              roadName:
                  'Kalman GPS: (${_store.activeDriverLocation.latitude.toStringAsFixed(4)}, ${_store.activeDriverLocation.longitude.toStringAsFixed(4)})',
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                const CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.two_wheeler, color: AppColors.surface),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${activeOrder.assignedDriverName ?? "Nguyễn Văn Nam"} • ★ 4.9',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'Biển số: ${activeOrder.assignedDriverPlate ?? "29-P1 123.45"} • Mã đơn: ${activeOrder.trackingCode}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    activeOrder.status.displayName,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                  ),
                  onPressed: () => _store.stepDriverAlongRoute(),
                  icon: const Icon(Icons.gps_fixed, size: 18),
                  label: const Text('Bước tiến GPS (Kalman 2D)'),
                ),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _selectedScreenIndex = 5),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Nhắn tin tài xế (UC08)'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _selectedScreenIndex = 6),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Hủy đơn (UC09)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.7: UC08 Liên hệ tài xế (Chat nội bộ & Gọi điện)
  Widget _buildInAppChatView() {
    final activeOrder = _store.orders.first;
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
                    'Hình 8.7: Chat với Tài xế Nguyễn Văn Nam (UC08)',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.phone_in_talk, color: AppColors.success),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đang gọi tới tài xế 0987 654 321...'),
                      ),
                    );
                  },
                ),
              ],
            ),
            const Divider(),
            SizedBox(
              height: 210,
              child: ListView.builder(
                itemCount: _store.chatMessages.length,
                itemBuilder: (context, index) {
                  final msg = _store.chatMessages[index];
                  return Align(
                    alignment: msg.isCustomer
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: msg.isCustomer
                            ? AppColors.accent
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg.text,
                            style: TextStyle(
                              color: msg.isCustomer
                                  ? AppColors.surface
                                  : AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            msg.timeLabel,
                            style: TextStyle(
                              fontSize: 10,
                              color: msg.isCustomer
                                  ? Colors.white70
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 6,
              children: [
                'Tôi đang xuống sảnh',
                'Để hàng ở lễ tân giúp mình',
                'Gọi khi tới nơi nhé',
              ].map((quick) {
                return ActionChip(
                  label: Text(quick, style: const TextStyle(fontSize: 11)),
                  onPressed: () => _store.sendChatMessage(
                    activeOrder.trackingCode,
                    quick,
                    isCustomer: true,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatInputCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Nhập tin nhắn gửi tài xế...',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.accent,
                  ),
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    _store.sendChatMessage(
                      activeOrder.trackingCode,
                      _chatInputCtrl.text,
                      isCustomer: true,
                    );
                    _chatInputCtrl.clear();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.8: UC09 Hủy đơn hàng & Chọn lý do hủy
  Widget _buildCancelOrderSheetView() {
    final reasons = [
      'Tài xế ở quá xa',
      'Đặt nhầm địa chỉ giao/nhận',
      'Thay đổi ý định / Chưa cần gửi gấp',
      'Không liên lạc được với người nhận',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.8: Hủy đơn hàng & Chọn lý do (UC09 - RULE-ORD-02)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Lưu ý: Miễn phí hủy khi đơn ở trạng thái Đang tìm tài xế hoặc Tài xế vừa nhận < 2 phút.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.sm),
            RadioGroup<String>(
              groupValue: _selectedCancelReason,
              onChanged: (v) {
                if (v != null) setState(() => _selectedCancelReason = v);
              },
              child: Column(
                children: reasons
                    .map(
                      (r) => RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: Text(r),
                        value: r,
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                onPressed: () {
                  final target = _store.orders.first.trackingCode;
                  _store.cancelOrder(target, _selectedCancelReason);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã hủy đơn $target (Lý do: $_selectedCancelReason)',
                      ),
                    ),
                  );
                },
                child: const Text('Xác nhận hủy đơn hàng'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.9 & Hình 8.10: UC10 Xem lịch sử đơn hàng & Chi tiết hóa đơn + Ảnh POD
  Widget _buildOrderHistoryAndPodView() {
    final filtered = _store.orders.where((o) {
      if (_historyFilterTab == 'Đang giao') {
        return o.status != OrderStatus.delivered &&
            o.status != OrderStatus.cancelled;
      }
      if (_historyFilterTab == 'Hoàn thành') {
        return o.status == OrderStatus.delivered;
      }
      if (_historyFilterTab == 'Đã hủy') {
        return o.status == OrderStatus.cancelled;
      }
      return true;
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.9 & 8.10: Lịch sử đơn hàng & Ảnh xác nhận POD (UC10)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children: ['Tất cả', 'Đang giao', 'Hoàn thành', 'Đã hủy']
                  .map((tab) {
                return ChoiceChip(
                  label: Text(tab),
                  selected: _historyFilterTab == tab,
                  onSelected: (_) => setState(() => _historyFilterTab = tab),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (filtered.isEmpty)
              EmptyOrdersStateWidget(
                onCreateOrder: () => setState(() => _selectedScreenIndex = 2),
              )
            else
              ...filtered.map(
                (ord) => Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${ord.trackingCode} • ${ord.serviceType.displayName}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            CurrencyFormatter.formatVnd(ord.totalAmount),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Từ: ${ord.pickupAddress}\nĐến: ${ord.dropoffAddress}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.verified_outlined,
                            size: 16,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Trạng thái: ${ord.status.displayName} • POD: ${ord.podImageNote ?? "Đang vận chuyển"}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
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

  /// Hình 8.11: UC11 Đánh giá tài xế 5 sao & Nhận xét nhanh
  Widget _buildRateDriverView() {
    final chips = [
      'Thân thiện',
      'Đúng giờ',
      'Cẩn thận',
      'Xe sạch',
      'Giao tận tay',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.11: Đánh giá Tài xế 5 sao (UC11)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starNum = index + 1;
                return IconButton(
                  onPressed: () => setState(() => _ratingStars = starNum),
                  icon: Icon(
                    starNum <= _ratingStars ? Icons.star : Icons.star_border,
                    color: AppColors.warning,
                    size: 34,
                  ),
                );
              }),
            ),
            Wrap(
              spacing: 8,
              children: chips.map((chip) {
                final selected = _selectedFeedbackChips.contains(chip);
                return FilterChip(
                  label: Text(chip),
                  selected: selected,
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        _selectedFeedbackChips.add(chip);
                      } else {
                        _selectedFeedbackChips.remove(chip);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _ratingCommentCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Nhận xét chi tiết cho tài xế Nguyễn Văn Nam',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                ),
                onPressed: () {
                  _store.submitDriverRating(
                    _store.orders.first.trackingCode,
                    _ratingStars,
                    _ratingCommentCtrl.text,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Cảm ơn bạn đã gửi đánh giá $_ratingStars sao cho tài xế!',
                      ),
                    ),
                  );
                },
                child: const Text('Gửi đánh giá'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.12: UC12 Gửi khiếu nại đơn hàng kèm ảnh bằng chứng
  Widget _buildSubmitComplaintView() {
    final types = [
      'Hàng hư hỏng',
      'Giao hàng chậm',
      'Thái độ tài xế',
      'Sai phí cước',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.12: Gửi khiếu nại đơn hàng (UC12)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children: types.map((t) {
                return ChoiceChip(
                  label: Text(t),
                  selected: _complaintType == t,
                  onSelected: (_) => setState(() => _complaintType = t),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _complaintDescCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Mô tả chi tiết sự cố & đính kèm tối đa 3 ảnh',
                hintText: 'Nhập nội dung khiếu nại để Admin kiểm tra GPS...',
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
                    reporterName: _store.customerFullName,
                    issueType: _complaintType,
                    description: _complaintDescCtrl.text.trim().isEmpty
                        ? 'Yêu cầu kiểm tra lộ trình & tình trạng kiện hàng'
                        : _complaintDescCtrl.text.trim(),
                  );
                  _complaintDescCtrl.clear();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Đã tạo Ticket khiếu nại gửi tới cổng Admin (UC28)!',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.report_problem_outlined),
                label: const Text('Gửi yêu cầu hỗ trợ / Khiếu nại'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.13: UC41 Quản lý Hồ sơ cá nhân
  Widget _buildCustomerProfileView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.13: Hồ sơ cá nhân - Hạng Thành viên Vàng (UC41)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _profileNameCtrl,
              decoration: const InputDecoration(labelText: 'Họ và tên'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _profilePhoneCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Số điện thoại'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _profileEmailCtrl,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _profileAddressCtrl,
              decoration:
                  const InputDecoration(labelText: 'Địa chỉ mặc định'),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                ),
                onPressed: () {
                  setState(() {
                    _store.customerFullName = _profileNameCtrl.text;
                    _store.customerPhone = _profilePhoneCtrl.text;
                    _store.customerEmail = _profileEmailCtrl.text;
                    _store.customerDefaultAddress = _profileAddressCtrl.text;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Đã lưu thay đổi hồ sơ cá nhân!'),
                    ),
                  );
                },
                child: const Text('Lưu thay đổi'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.14: UC42 Trung tâm Thông báo
  Widget _buildNotificationCenterView() {
    final items = _store.notifications.where((n) {
      if (_notiFilter == 'Tất cả') return true;
      return n.category == _notiFilter;
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.14: Trung tâm Thông báo (UC42)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children: ['Tất cả', 'Đơn hàng', 'Khuyến mãi', 'Hệ thống']
                  .map((cat) {
                return ChoiceChip(
                  label: Text(cat),
                  selected: _notiFilter == cat,
                  onSelected: (_) => setState(() => _notiFilter = cat),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...items.map(
              (n) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppColors.accent.withValues(alpha: 0.14),
                  child: const Icon(
                    Icons.notifications_active_outlined,
                    color: AppColors.accent,
                  ),
                ),
                title: Text(
                  n.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('${n.category} • ${n.timeAgo}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
