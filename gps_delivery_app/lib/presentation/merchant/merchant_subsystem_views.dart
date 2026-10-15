import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/security_and_barcode_utils.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/enums/order_status.dart';
import '../../domain/enums/service_type.dart';

class _BatchCsvRow {
  final int rowNumber;
  final String recipientName;
  final String phone;
  final String address;
  final double codAmount;
  final String? validationError;

  const _BatchCsvRow({
    required this.rowNumber,
    required this.recipientName,
    required this.phone,
    required this.address,
    required this.codAmount,
    this.validationError,
  });

  bool get isValid => validationError == null;
}

/// Phân hệ Cửa hàng / Đối tác B2B (Merchant Web Portal) - 11 màn hình (Hình 8.36 - 8.46)
/// Bao phủ đầy đủ UC30 - UC40 theo Thiết kế Giao diện Chương 8.4
class MerchantSubsystemEntry extends StatefulWidget {
  const MerchantSubsystemEntry({super.key});

  @override
  State<MerchantSubsystemEntry> createState() => _MerchantSubsystemEntryState();
}

class _MerchantSubsystemEntryState extends State<MerchantSubsystemEntry> {
  final AppStateStore _store = AppStateStore.instance;
  int _selectedScreenIndex = 2; // Mặc định: UC32 Tạo đơn lẻ

  // UC30 & UC31: Thông tin cửa hàng
  late final TextEditingController _storeNameCtrl;
  late final TextEditingController _taxCodeCtrl;
  late final TextEditingController _bankAccountCtrl;

  // UC32: Tạo đơn lẻ
  final TextEditingController _singleNameCtrl =
      TextEditingController(text: 'Trần Thị Bích Ngọc');
  final TextEditingController _singlePhoneCtrl =
      TextEditingController(text: '0918223344');
  final TextEditingController _singleAddrCtrl = TextEditingController(
    text: '88 Nguyễn Huệ, Phường Bến Nghé, Quận 1, TP. HCM',
  );
  final TextEditingController _singleCodCtrl =
      TextEditingController(text: '650000');
  bool _isFragile = true;
  bool _isKeepCold = false;

  // UC33: Batch CSV/Excel Parser
  final TextEditingController _csvInputCtrl = TextEditingController(
    text: 'Nguyễn Văn A,0987654321,123 Đường Lê Lợi Q.1 TP.HCM,350000\n'
        'Trần Thị B,09123456,456 Nguyễn Huệ Phú Nhuận TP.HCM,500000\n'
        'Lê Văn C,0923560677,Đường Cách Mạng Tháng 8,210000\n'
        'Phạm Minh D,0909123456,789 Điện Biên Phủ Q.Bình Thạnh TP.HCM,420000',
  );
  List<_BatchCsvRow> _parsedRows = [];

  // UC36: Pickup Request
  final TextEditingController _pickupQtyCtrl =
      TextEditingController(text: '15');
  final TextEditingController _pickupWeightCtrl =
      TextEditingController(text: '25.5');
  String _pickupVehicle = 'Xe tải nhỏ (500kg)';

  // UC38: Rút tiền COD
  final TextEditingController _codWithdrawCtrl =
      TextEditingController(text: '2000000');

  static const List<String> _screenTitles = [
    '8.36: UC30 Đăng ký Đối tác Cửa hàng',
    '8.37: UC31 Cấu hình Shop & Nhiều Kho',
    '8.38: UC32 Tạo đơn giao hàng lẻ',
    '8.39-8.40: UC33 Nhập đơn Excel/CSV & Kiểm lỗi',
    '8.41: UC34 In vận đơn A6 (Barcode/QR)',
    '8.42: UC35 Theo dõi Đa vận đơn Real-time',
    '8.43: UC36 Gọi tài xế lấy hàng định kỳ',
    '8.44: UC37 Đối soát công nợ COD',
    '8.45: UC38 Rút tiền COD về Ngân hàng',
    '8.46: UC39/UC40 Đơn hoàn & Báo cáo tháng',
  ];

  @override
  void initState() {
    super.initState();
    _storeNameCtrl = TextEditingController(text: _store.merchantStoreName);
    _taxCodeCtrl = TextEditingController(text: _store.merchantTaxCode);
    _bankAccountCtrl = TextEditingController(text: _store.merchantBankAccount);
    _parseCsvBatch();
    _store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _parseCsvBatch() {
    final lines = _csvInputCtrl.text.split('\n');
    final result = <_BatchCsvRow>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final parts = line.split(',');
      final name = parts.isNotEmpty ? parts[0].trim() : '';
      final phone = parts.length > 1 ? parts[1].trim() : '';
      final addr = parts.length > 2 ? parts[2].trim() : '';
      final cod = parts.length > 3 ? (double.tryParse(parts[3].trim()) ?? 0) : 0.0;

      String? err;
      if (!RegExp(r'^0\d{9}$').hasMatch(phone)) {
        err = 'SĐT không hợp lệ (Phải đủ 10 chữ số)';
      } else if (!RegExp(r'\d+').hasMatch(addr) || addr.length < 18) {
        err = 'Địa chỉ thiếu số nhà hoặc Tỉnh/Thành phố';
      }

      result.add(
        _BatchCsvRow(
          rowNumber: i + 1,
          recipientName: name,
          phone: phone,
          address: addr,
          codAmount: cod,
          validationError: err,
        ),
      );
    }
    _parsedRows = result;
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _storeNameCtrl.dispose();
    _taxCodeCtrl.dispose();
    _bankAccountCtrl.dispose();
    _singleNameCtrl.dispose();
    _singlePhoneCtrl.dispose();
    _singleAddrCtrl.dispose();
    _singleCodCtrl.dispose();
    _csvInputCtrl.dispose();
    _pickupQtyCtrl.dispose();
    _pickupWeightCtrl.dispose();
    _codWithdrawCtrl.dispose();
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
                width: 250,
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
                        'MERCHANT PORTAL B2B\n${_store.merchantStoreName}',
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
                        selectedTileColor: AppColors.accent,
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
              Expanded(child: _buildActiveMerchantScreen(context)),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildScreenSelectorBar(),
            const SizedBox(height: AppSpacing.md),
            _buildActiveMerchantScreen(context),
          ],
        );
      },
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

  Widget _buildActiveMerchantScreen(BuildContext context) {
    switch (_selectedScreenIndex) {
      case 0:
        return _buildMerchantRegistrationView();
      case 1:
        return _buildStoreConfigAndWarehousesView();
      case 2:
        return _buildSingleOrderCreateView();
      case 3:
        return _buildBatchCsvUploadAndValidationView();
      case 4:
        return _buildWaybillA6PrintView();
      case 5:
        return _buildMultiOrderTrackingView();
      case 6:
        return _buildScheduledPickupRequestView();
      case 7:
        return _buildCodReconciliationView();
      case 8:
        return _buildCodWithdrawalView();
      case 9:
        return _buildReturnAndMonthlyAnalyticsView();
      default:
        return _buildSingleOrderCreateView();
    }
  }

  /// Hình 8.36: UC30 Đăng ký tài khoản Đối tác Cửa hàng
  Widget _buildMerchantRegistrationView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.36: Đăng ký Tài khoản Đối tác Cửa hàng (UC30)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _storeNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên thương hiệu / Cửa hàng',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _taxCodeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Mã số thuế doanh nghiệp',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _bankAccountCtrl,
              decoration: const InputDecoration(
                labelText: 'Tài khoản ngân hàng nhận đối soát COD (VPBank)',
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
                  setState(() {
                    _store.merchantStoreName = _storeNameCtrl.text;
                    _store.merchantTaxCode = _taxCodeCtrl.text;
                    _store.merchantBankAccount = _bankAccountCtrl.text;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Đã lưu hồ sơ Đối tác B2B & kích hoạt Kho lấy hàng!',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.storefront),
                label: const Text('Hoàn tất đăng ký Cửa hàng'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.37: UC31 Cập nhật thông tin cửa hàng & Danh sách Kho lấy hàng
  Widget _buildStoreConfigAndWarehousesView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.37: Quản lý Cửa hàng & Điểm lấy hàng (UC31)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Thương hiệu: ${_store.merchantStoreName} • MST: ${_store.merchantTaxCode} • Giờ mở cửa: ${_store.merchantOpenHours}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const Divider(),
            const Text(
              'Danh sách Kho lấy hàng đã cấu hình tọa độ GPS:',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            ..._store.merchantWarehouses.map(
              (wh) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.warehouse_outlined,
                  color: AppColors.primary,
                ),
                title: Text(
                  '${wh.name} (${wh.location.latitude}, ${wh.location.longitude})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(wh.address),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.38: UC32 Tạo đơn giao hàng lẻ (Cửa hàng)
  Widget _buildSingleOrderCreateView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.38: Tạo Đơn Giao hàng Lẻ B2B (UC32)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _singleNameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Tên khách nhận'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _singlePhoneCtrl,
                    decoration:
                        const InputDecoration(labelText: 'SĐT khách nhận'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _singleAddrCtrl,
              decoration:
                  const InputDecoration(labelText: 'Địa chỉ giao hàng'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _singleCodCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Thu hộ COD (VNĐ)'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilterChip(
                  label: const Text('Hàng dễ vỡ'),
                  selected: _isFragile,
                  onSelected: (v) => setState(() => _isFragile = v),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text('Giữ lạnh'),
                  selected: _isKeepCold,
                  onSelected: (v) => setState(() => _isKeepCold = v),
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
                  final ord = _store.createNewOrder(
                    pickupAddress: _store.merchantWarehouses.first.address,
                    dropoffAddress: _singleAddrCtrl.text,
                    recipientName: _singleNameCtrl.text,
                    recipientPhone: _singlePhoneCtrl.text,
                    packageDescription:
                        'Kiện hàng Shop (${_isFragile ? "Dễ vỡ" : "Tiêu chuẩn"})',
                    weightKg: 2.0,
                    dimensionsCm: '30x20x15 cm',
                    serviceType: DeliveryServiceType.express30m,
                    codAmount: double.tryParse(_singleCodCtrl.text) ?? 0,
                    paymentMethod: 'Tiền mặt (COD)',
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã tạo vận đơn B2B ${ord.trackingCode} thành công!',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.send_outlined),
                label: const Text('Tạo đơn & Gọi tài xế ngay (Phí: 45.000đ)'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.39 & Hình 8.40: UC33 Tạo đơn hàng loạt từ Excel/CSV & Kiểm lỗi tự động
  Widget _buildBatchCsvUploadAndValidationView() {
    final validCount = _parsedRows.where((r) => r.isValid).length;
    final errorCount = _parsedRows.length - validCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.39 & 8.40: Tạo đơn hàng loạt CSV/Excel & Kiểm lỗi (UC33)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Định dạng chuẩn: Tên người nhận, SĐT (10 số), Địa chỉ chi tiết, Tiền COD',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _csvInputCtrl,
              maxLines: 4,
              onChanged: (_) => setState(_parseCsvBatch),
              decoration: const InputDecoration(
                labelText: 'Dữ liệu dòng CSV/Excel nhập hàng loạt',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Chip(
                  backgroundColor: AppColors.success.withValues(alpha: 0.15),
                  label: Text(
                    'Hợp lệ: $validCount đơn',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  backgroundColor: AppColors.danger.withValues(alpha: 0.15),
                  label: Text(
                    'Lỗi định dạng: $errorCount đơn',
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            ..._parsedRows.map(
              (r) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: r.isValid
                      ? AppColors.background
                      : AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      r.isValid ? Icons.check_circle : Icons.error_outline,
                      color: r.isValid ? AppColors.success : AppColors.danger,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dòng #${r.rowNumber}: ${r.recipientName} (${r.phone}) - ${r.address} • COD: ${CurrencyFormatter.formatVnd(r.codAmount)}'
                        '${r.validationError != null ? "\n⚠️ ${r.validationError}" : ""}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: () {
                  for (final r in _parsedRows.where((x) => x.isValid)) {
                    _store.createNewOrder(
                      pickupAddress: _store.merchantWarehouses.first.address,
                      dropoffAddress: r.address,
                      recipientName: r.recipientName,
                      recipientPhone: r.phone,
                      packageDescription: 'Đơn hàng loạt Batch CSV',
                      weightKg: 1.2,
                      dimensionsCm: '25x20x10 cm',
                      serviceType: DeliveryServiceType.standard,
                      codAmount: r.codAmount,
                      paymentMethod: 'Tiền mặt (COD)',
                    );
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã phát hành thành công $validCount đơn hợp lệ!',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.playlist_add_check),
                label: Text('Xác nhận tạo $validCount đơn hợp lệ'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.41: UC34 Quản lý & In phiếu gửi hàng A6 (Barcode Code-128 & QR Code)
  Widget _buildWaybillA6PrintView() {
    final ord = _store.orders.first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.41: Bản xem trước Phiếu gửi hàng Khổ A6 (UC34)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.textPrimary, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Code128BarcodeWidget(
                          data: 'GHN-987654321-${ord.trackingCode}',
                          height: 44,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      QrMatrixPainterWidget(
                        payload:
                            '${ord.trackingCode}|${ord.recipientPhone}|${ord.codAmount.toStringAsFixed(0)}',
                        size: 68,
                      ),
                    ],
                  ),
                  const Divider(),
                  Text('Từ Shop: ${_store.merchantStoreName}'),
                  Text('Địa chỉ Kho: ${_store.merchantWarehouses.first.address}'),
                  const SizedBox(height: 6),
                  Text(
                    'Người nhận: ${ord.recipientName} (${ord.recipientPhone})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text('Giao đến: ${ord.dropoffAddress}'),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Hàng hóa: ${ord.packageDescription}'),
                      Text(
                        'THU HỘ COD: ${CurrencyFormatter.formatVnd(ord.codAmount)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Đã xuất file PDF khổ A6 sẵn sàng cho máy in nhiệt!',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.print_outlined),
                label: const Text('In hàng loạt (Khổ nhiệt A6 / A5)'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.42: UC35 Theo dõi trạng thái nhiều đơn hàng cùng lúc
  Widget _buildMultiOrderTrackingView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.42: Theo dõi Đa vận đơn Real-time (UC35)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._store.orders.map(
              (o) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.local_shipping,
                  color: AppColors.primary,
                ),
                title: Text(
                  '${o.trackingCode} • Khách: ${o.recipientName}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Tài xế: ${o.assignedDriverName ?? "Đang điều phối"} • Giao: ${o.dropoffAddress}',
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

  /// Hình 8.43: UC36 Gọi tài xế đến lấy hàng định kỳ (Pickup Request)
  Widget _buildScheduledPickupRequestView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.43: Đặt lịch Gọi Tài xế Đến Lấy hàng Định kỳ (UC36)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pickupQtyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Số lượng kiện hàng dự kiến',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _pickupWeightCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tổng khối lượng (kg)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _pickupVehicle,
              decoration:
                  const InputDecoration(labelText: 'Loại xe yêu cầu lấy hàng'),
              items: [
                'Xe máy (Dưới 30kg)',
                'Xe tải nhỏ (500kg)',
                'Xe Van nội thành (1 tấn)',
              ]
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _pickupVehicle = v);
              },
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
                    SnackBar(
                      content: Text(
                        'Đã đặt lịch điều xe $_pickupVehicle lấy ${_pickupQtyCtrl.text} kiện hàng lúc 14:00 - 16:00!',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.schedule_send),
                label: const Text('Gửi yêu cầu điều xe lấy hàng'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.44: UC37 Đối soát công nợ tiền thu hộ COD
  Widget _buildCodReconciliationView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.44: Bảng Đối soát Công nợ Tiền thu hộ COD (UC37)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _codCard('Tổng COD đã thu', '45.200.000 VNĐ', AppColors.primary),
                _codCard('Phí vận chuyển cấn trừ', '3.850.000 VNĐ', AppColors.danger),
                _codCard('Số dư thực nhận', '41.350.000 VNĐ', AppColors.success),
              ],
            ),
            const Divider(),
            ..._store.orders.map(
              (o) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${o.trackingCode} • COD: ${CurrencyFormatter.formatVnd(o.codAmount)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Phí ship: ${CurrencyFormatter.formatVnd(o.totalAmount)} • Thực nhận: ${CurrencyFormatter.formatVnd((o.codAmount - o.totalAmount).clamp(0, double.infinity))}',
                ),
                trailing: Text(
                  o.status == OrderStatus.delivered
                      ? 'Đã đối soát'
                      : 'Chờ đối soát',
                  style: TextStyle(
                    color: o.status == OrderStatus.delivered
                        ? AppColors.success
                        : AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _codCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11)),
          Text(
            value,
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

  /// Hình 8.45: UC38 Yêu cầu rút tiền COD về tài khoản ngân hàng
  Widget _buildCodWithdrawalView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.45: Rút Tiền Thu hộ COD Về Ngân hàng (UC38)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Số dư COD khả dụng: ${CurrencyFormatter.formatVnd(_store.merchantCodBalance)} (${_store.merchantBankName} - ${_store.merchantBankAccount})',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _codWithdrawCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Số tiền COD muốn rút (Tối thiểu 100.000đ)',
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
                  final amt = double.tryParse(_codWithdrawCtrl.text) ?? 0;
                  _store.requestWithdrawal(
                    ownerName: _store.merchantStoreName,
                    ownerRole: 'Cửa hàng (COD)',
                    amount: amt,
                    bankName: _store.merchantBankName,
                    accountMasked: _store.merchantBankAccount,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã tạo lệnh rút COD ${CurrencyFormatter.formatVnd(amt)}!',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Xác nhận rút tiền COD'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hình 8.46: UC39 & UC40 Quản lý đơn hoàn trả & Thống kê chi phí tháng
  Widget _buildReturnAndMonthlyAnalyticsView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hình 8.46: Quản lý Đơn hoàn & Báo cáo Doanh thu Tháng (UC39 & UC40)',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _codCard('Doanh thu tháng', '128.500.000 VNĐ', AppColors.primary),
                _codCard('Tổng số đơn', '450 đơn (94.2% Giao TC)', AppColors.success),
                _codCard('Tổng phí ship', '12.450.000 VNĐ', AppColors.accent),
              ],
            ),
            const Divider(),
            const Text(
              'Danh sách đơn giao thất bại / Đang hoàn về kho (UC39):',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('#DH992014 • Khách từ chối nhận hàng'),
              subtitle: const Text(
                'Tài xế đang hoàn trả về Kho chính (123 Lê Lợi, Q.1)',
              ),
              trailing: OutlinedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Đã xác nhận nhận lại hàng hoàn về kho!'),
                    ),
                  );
                },
                child: const Text('Đã nhận lại hàng'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
