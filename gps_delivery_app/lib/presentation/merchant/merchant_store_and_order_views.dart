part of 'merchant_subsystem_views.dart';

extension _MerchantStoreAndOrderViews on _MerchantSubsystemEntryState {
  /// UC30: Đăng ký & xác thực cửa hàng (Khớp 100% uc30_dang_ky_cua_hang.jpg)
  Widget _buildMerchantRegistrationView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Đăng ký & xác thực cửa hàng',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Color(0xFF15131E),
          ),
        ),
        const SizedBox(height: 20),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildMerchantStepDot(
                    icon: Icons.storefront_rounded,
                    label: 'Thông tin cửa hàng',
                    active: _storeNameCtrl.text.trim().isNotEmpty &&
                        _taxCodeCtrl.text.trim().isNotEmpty,
                  ),
                  _buildMerchantStepConnector(
                    active: _attachedMerchantDocs.isNotEmpty,
                  ),
                  _buildMerchantStepDot(
                    icon: Icons.description_outlined,
                    label: 'Giấy tờ (${_attachedMerchantDocs.length}/2)',
                    active: _attachedMerchantDocs.isNotEmpty,
                  ),
                  _buildMerchantStepConnector(
                    active: _bankAccountCtrl.text.trim().isNotEmpty,
                  ),
                  _buildMerchantStepDot(
                    icon: Icons.account_balance_outlined,
                    label: 'Tài khoản ngân hàng',
                    active: _bankAccountCtrl.text.trim().isNotEmpty,
                  ),
                  _buildMerchantStepConnector(
                    active: _store.activeMerchantRecord != null,
                  ),
                  _buildMerchantStepDot(
                    icon: _store.activeMerchantRecord?.approvalStatus ==
                            'Đã duyệt'
                        ? Icons.verified_rounded
                        : Icons.access_time_rounded,
                    label: _store.activeMerchantRecord?.approvalStatus ??
                        'Chờ duyệt',
                    active: _store.activeMerchantRecord != null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: const Color(0xFF15131E)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final col1 = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Thông tin cơ bản',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _storeNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Tên cửa hàng',
                              hintText: 'Nhập tên cửa hàng của bạn',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _taxCodeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Mã số thuế',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _shopPhoneCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'SĐT',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _shopEmailCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                      final col2 = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Thông tin liên hệ',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _businessCategory,
                            decoration: const InputDecoration(
                              labelText: 'Loại hình kinh doanh',
                            ),
                            items: const [
                              'Gốm sứ & Nội thất',
                              'Thời trang & Phụ kiện',
                              'Thực phẩm & Đồ uống',
                              'Điện tử & Gia dụng',
                            ]
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(
                                      e,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                _rebuildMerchantUi(() => _businessCategory = v);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _repNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Người đại diện',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _shopAddressCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Địa chỉ',
                            ),
                          ),
                        ],
                      );
                      if (constraints.maxWidth < 640) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            col1,
                            const SizedBox(height: 16),
                            col2,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: col1),
                          const SizedBox(width: 20),
                          Expanded(child: col2),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Giấy tờ & Hình ảnh',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDashedUploadBox(
                          title: 'Giấy phép kinh doanh',
                          subtitle: 'Kéo thả hoặc bấm để tải lên (Đã đính kèm)',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildDashedUploadBox(
                          title: 'Biển hiệu cửa hàng',
                          subtitle: 'Kéo thả hoặc bấm để tải lên (Đã đính kèm)',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Thông tin thanh toán',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final bankDrop = DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _selectedBankName,
                        decoration: const InputDecoration(
                          labelText: 'Ngân hàng',
                        ),
                        items: const [
                          'Ngân hàng VPBank (VPB)',
                          'Ngân hàng Vietcombank (VCB)',
                          'Ngân hàng Techcombank (TCB)',
                        ]
                            .map(
                              (b) => DropdownMenuItem(
                                value: b,
                                child: Text(
                                  b,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            _rebuildMerchantUi(() => _selectedBankName = v);
                          }
                        },
                      );
                      final accField = TextField(
                        controller: _bankAccountCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Số tài khoản nhận COD',
                        ),
                      );
                      if (constraints.maxWidth < 640) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            bankDrop,
                            const SizedBox(height: 12),
                            accField,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: bankDrop),
                          const SizedBox(width: 16),
                          Expanded(child: accField),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5E83),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.zero),
                        ),
                      ),
                      onPressed: () {
                        final sName = _storeNameCtrl.text.trim();
                        final tCode = _taxCodeCtrl.text.trim();
                        final repName = _repNameCtrl.text.trim();
                        final sPhone = _shopPhoneCtrl.text.trim();
                        final bAcc = _bankAccountCtrl.text.trim();
                        if (sName.isEmpty ||
                            tCode.isEmpty ||
                            repName.isEmpty ||
                            sPhone.isEmpty ||
                            bAcc.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Vui lòng điền đầy đủ Tên cửa hàng, Mã số thuế, Người đại diện, SĐT và Số tài khoản!',
                              ),
                            ),
                          );
                          return;
                        }
                        if (_store.activeMerchantRecord == null ||
                            _store.activeMerchantRecord!.approvalStatus ==
                                'Từ chối') {
                          _store.registerOrUpdateMerchantKyc(
                            ownerPhone: sPhone,
                            storeName: sName,
                            businessType: _businessCategory,
                            taxCode: tCode,
                            representativeName: repName,
                            bankName: _selectedBankName,
                            bankAccount: bAcc,
                          );
                        }
                        _store.updateMerchantProfile(
                          storeName: sName,
                          taxCode: tCode,
                          businessType: _businessCategory,
                          representativeName: repName,
                          phone: sPhone,
                          bankName: _selectedBankName,
                          bankAccount: bAcc,
                          warehouseAddress: _shopAddressCtrl.text.trim(),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Đã lưu hồ sơ đăng ký & xác thực Cửa hàng thành công!',
                            ),
                          ),
                        );
                      },
                      child: const Text(
                        'Gửi hồ sơ',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
  }

  Widget _buildMerchantStepDot({
    required IconData icon,
    required String label,
    required bool active,
  }) {
    final color = active ? const Color(0xFFFF5E83) : const Color(0xFF15131E);
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: active ? Colors.white : const Color(0xFF4A4754),
            size: 20,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? const Color(0xFFFF5E83) : const Color(0xFF4A4754),
          ),
        ),
      ],
    );
  }

  Widget _buildMerchantStepConnector({required bool active}) {
    return Container(
      width: 65,
      height: 2,
      margin: const EdgeInsets.only(bottom: 20, left: 6, right: 6),
      color: active ? const Color(0xFFFF5E83) : const Color(0xFF15131E),
    );
  }

  Widget _buildDashedUploadBox({
    required String title,
    required String subtitle,
  }) {
    final isAttached = _attachedMerchantDocs.contains(title);
    return InkWell(
      onTap: () {
        _rebuildMerchantUi(() {
          if (isAttached && _attachedMerchantDocs.length > 1) {
            _attachedMerchantDocs.remove(title);
          } else {
            _attachedMerchantDocs.add(title);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _attachedMerchantDocs.contains(title)
                  ? 'Đã đính kèm hồ sơ pháp lý: $title'
                  : 'Đã gỡ đính kèm: $title',
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: isAttached ? const Color(0xFFDCFCE7) : const Color(0xFFF5F1E8),
          borderRadius: BorderRadius.all(Radius.zero),
          border: Border.all(
            color: isAttached ? AppColors.success : const Color(0xFF15131E),
            width: isAttached ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(
              isAttached ? Icons.check_circle_rounded : Icons.upload_rounded,
              size: 26,
              color: isAttached ? AppColors.success : const Color(0xFF334155),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              isAttached ? subtitle : 'Bấm để chọn tệp tài liệu tải lên',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF4A4754)),
            ),
          ],
        ),
      ),
    );
  }

  /// UC31: Quản lý Điểm lấy hàng & Cấu hình Kho 3 Cột (Khớp 100% uc31_diem_lay_hang_1791015242689.jpg)
  Widget _buildStoreConfigAndWarehousesView() {
    final safeWhIdx = _store.merchantWarehouses.isEmpty
        ? 0
        : _selectedWarehouseIndex.clamp(
            0,
            _store.merchantWarehouses.length - 1,
          );
    final wh = _store.merchantWarehouses[safeWhIdx];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Quản lý Điểm lấy hàng & Cấu hình Kho',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF15131E),
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final col1 = Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: const Color(0xFF15131E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Danh sách Điểm lấy hàng',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._store.merchantWarehouses.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final w = entry.value;
                    final isSelected = idx == safeWhIdx;
                    return InkWell(
                      onTap: () {
                        _rebuildMerchantUi(() {
                          _selectedWarehouseIndex = idx;
                          _shopAddressCtrl.text = w.address;
                          _selectedWarehouseName = '${w.name} - ${w.address}';
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFF5F1E8)
                              : Colors.white,
                          borderRadius: BorderRadius.all(Radius.zero),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFFF5E83)
                                : const Color(0xFF15131E),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    w.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                                if (idx == 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFF5E83),
                                      borderRadius: BorderRadius.all(Radius.zero),
                                    ),
                                    child: const Text(
                                      'Mặc định',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              w.address,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF4A4754),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'GPS: ${w.location.latitude.toStringAsFixed(4)}, ${w.location.longitude.toStringAsFixed(4)} • ${_store.merchantOpenHours}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF4A4754),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 6),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5E83),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      final nextNum = _store.merchantWarehouses.length + 1;
                      final created = _store.addMerchantWarehouse(
                        name: 'Kho chi nhánh #$nextNum',
                        address: _shopAddressCtrl.text.trim().isNotEmpty
                            ? _shopAddressCtrl.text.trim()
                            : '789 Nguyễn Thị Minh Khai, Quận 3, TP. HCM',
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã thêm ${created.name} (${created.id}) thành công!',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Thêm điểm lấy hàng mới'),
                  ),
                ],
              ),
            );
            final col2 = Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: const Color(0xFF15131E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Cập nhật Điểm lấy hàng',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _storeNameCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Tên điểm lấy hàng / Thương hiệu',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _repNameCtrl,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Người liên hệ',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _shopPhoneCtrl,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'SĐT liên hệ',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _shopAddressCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Địa chỉ chi tiết (08:00 - 21:00)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5E83),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: () {
                      if (_storeNameCtrl.text.trim().isEmpty ||
                          _shopAddressCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Vui lòng nhập Tên điểm lấy hàng và Địa chỉ chi tiết!',
                            ),
                          ),
                        );
                        return;
                      }
                      _store.updateMerchantProfile(
                        storeName: _storeNameCtrl.text.trim(),
                        taxCode: _taxCodeCtrl.text.trim(),
                        businessType: _businessCategory,
                        representativeName: _repNameCtrl.text.trim(),
                        phone: _shopPhoneCtrl.text.trim(),
                        bankName: _selectedBankName,
                        bankAccount: _bankAccountCtrl.text.trim(),
                        warehouseAddress: _shopAddressCtrl.text.trim(),
                        warehouseIndex: safeWhIdx,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Đã lưu cấu hình Điểm lấy hàng mặc định!',
                          ),
                        ),
                      );
                    },
                    child: const Text(
                      'Lưu thay đổi',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            );
            final col3 = Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: const Color(0xFF15131E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Bản đồ vị trí',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.all(Radius.zero),
                      border: Border.all(color: const Color(0xFF15131E)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Map3dPerspectiveWidget(
                      height: 195,
                      mode: MapViewMode.customerPreview,
                      is3dMode: _store.isMap3dEnabled,
                      speedKmh: 0,
                      onToggle3d: _store.toggleMap3d,
                      routePoints: [
                        wh.location,
                        GeoPoint(
                          latitude: wh.location.latitude + 0.0045,
                          longitude: wh.location.longitude + 0.0055,
                        ),
                      ],
                      pickupLabel: '📍 ${wh.name}',
                      dropoffLabel: 'Vùng giao',
                      nextTurnInstruction: 'Vị trí Kho lấy hàng: ${wh.name}',
                      roadName: wh.address,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Kinh độ: ${wh.location.longitude.toStringAsFixed(6)} | Vĩ độ: ${wh.location.latitude.toStringAsFixed(6)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4A4754),
                    ),
                  ),
                ],
              ),
            );
            if (constraints.maxWidth < 860) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  col1,
                  const SizedBox(height: 16),
                  col2,
                  const SizedBox(height: 16),
                  col3,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: col1),
                const SizedBox(width: 16),
                Expanded(flex: 4, child: col2),
                const SizedBox(width: 16),
                Expanded(flex: 3, child: col3),
              ],
            );
          },
        ),
      ],
    );
  }

  /// UC32: Tạo đơn gửi hàng (Khớp 100% uc32_tao_don_gui_1791015282651.jpg)
  Widget _buildSingleOrderCreateView() {
    final warehouseOptions = _store.merchantWarehouses
        .map((w) => '${w.name} - ${w.address}')
        .toList();
    final activeWarehouseLabel =
        warehouseOptions.contains(_selectedWarehouseName)
            ? _selectedWarehouseName
            : (warehouseOptions.isNotEmpty
                ? warehouseOptions.first
                : _selectedWarehouseName);
    final selectedWhObj = _store.merchantWarehouses
        .where((w) => '${w.name} - ${w.address}' == activeWarehouseLabel)
        .firstOrNull;
    final pickupAddr = selectedWhObj?.address ??
        (_store.merchantWarehouses.isNotEmpty
            ? _store.merchantWarehouses.first.address
            : _shopAddressCtrl.text);
    final pCoord = SmartDispatchEngine.resolveAddressToCoordinate(
      pickupAddr,
      fallback: const GeoPoint(latitude: 10.7731, longitude: 106.7012),
    );
    final dCoord = SmartDispatchEngine.resolveAddressToCoordinate(
      _singleAddrCtrl.text,
      fallback: const GeoPoint(latitude: 10.7850, longitude: 106.6880),
    );
    final rawAirMeters = GeoMath.distanceMeters(pCoord, dCoord);
    final distMeters = (rawAirMeters * 1.28).round().clamp(1500, 45000);
    final durationSec = ((distMeters / 1000.0) * 180).round();
    final distKm = distMeters / 1000.0;
    final etaMins = _merchantServiceType == DeliveryServiceType.express30m
        ? (15 + (distKm * 3.5).round())
        : _merchantServiceType == DeliveryServiceType.standard
            ? (30 + (distKm * 4.5).round())
            : (45 + (distKm * 6.0).round());
    final weightVal = double.tryParse(_singleWeightCtrl.text) ?? 2.5;
    double geofenceFee = 0;
    for (final z in _store.geofenceZones) {
      if (z.isActive &&
          z.surchargeRate > 0 &&
          GeoMath.isPointInPolygon(dCoord, z.boundary)) {
        geofenceFee += z.surchargeRate;
      }
    }
    if (_store.isWeatherSurchargeActive) {
      geofenceFee += _store.badWeatherSurchargeConfig;
    }
    if (weightVal > 5.0) {
      geofenceFee += ((weightVal - 5.0) * 3000).roundToDouble();
    }
    if (_isFragile) {
      geofenceFee += 5000;
    }
    if (_isKeepCold) {
      geofenceFee += 10000;
    }
    final merchantEst = PricingEstimate.calculate(
      serviceType: _merchantServiceType,
      distanceMeters: distMeters,
      durationSeconds: durationSec,
      isPeakHour: _store.isPeakSurchargeActive,
      geofenceSurcharge: geofenceFee,
      voucherDiscount: 0,
      baseFareScale: (_store.baseFareConfig / 25000.0).clamp(0.4, 5.0),
      pricePerKmScale: (_store.pricePerKmConfig / 5000.0).clamp(0.4, 5.0),
    );
    final codVal = double.tryParse(_singleCodCtrl.text.trim()) ?? 0.0;
    final totalEstimated = merchantEst.totalAmount;
    final previewMerchantRoute = SmartDispatchEngine.generateRoutePolyline(
      pCoord,
      dCoord,
      segments: 10,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tạo đơn gửi hàng',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF15131E),
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Tạo Đơn Giao hàng Lẻ B2B',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF4A4754)),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, innerConstraints) {
            final twoCol = innerConstraints.maxWidth >= 680;
            final leftFormCard = Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: const Color(0xFF15131E)),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Điểm lấy hàng',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: activeWarehouseLabel,
                      decoration: const InputDecoration(
                        hintText: 'Chọn điểm lấy hàng',
                      ),
                      items: warehouseOptions
                          .map(
                            (w) => DropdownMenuItem(
                              value: w,
                              child: Text(w, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          final idx = warehouseOptions.indexOf(v);
                          _rebuildMerchantUi(() {
                            _selectedWarehouseName = v;
                            if (idx >= 0 &&
                                idx < _store.merchantWarehouses.length) {
                              _selectedWarehouseIndex = idx;
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Thông tin người nhận',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _singleNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Tên người nhận',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _singlePhoneCtrl,
                            decoration: const InputDecoration(
                              labelText: 'SĐT',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _singleAddrCtrl,
                      onChanged: (_) => _rebuildMerchantUi(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Địa chỉ giao (Thành phố, Quận/Huyện/Phường)',
                        suffixIcon: Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: SmartDispatchEngine.searchAddressSuggestions(
                        _singleAddrCtrl.text,
                      )
                          .take(3)
                          .map(
                            (place) => ActionChip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                place.title,
                                style: const TextStyle(fontSize: 11),
                              ),
                              onPressed: () => _rebuildMerchantUi(
                                () => _singleAddrCtrl.text = place.fullAddress,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Thông tin kiện hàng',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _singlePkgCategory,
                            decoration: const InputDecoration(
                              labelText: 'Loại hàng',
                            ),
                            items: const [
                              'Quần áo, Điện tử',
                              'Gốm sứ & Đồ dễ vỡ',
                              'Thực phẩm khô',
                              'Tài liệu / Hợp đồng',
                            ]
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(
                                      c,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                _rebuildMerchantUi(() => _singlePkgCategory = v);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _singleWeightCtrl,
                            onChanged: (_) => _rebuildMerchantUi(() {}),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Trọng lượng (kg)',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _singleDimCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Kích thước (cm) (D x R x C)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _singleCodCtrl,
                            onChanged: (_) => _rebuildMerchantUi(() {}),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Tiền thu hộ COD',
                              suffixText: 'VND',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _singleNoteCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Ghi chú cho tài xế',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('Hàng dễ vỡ'),
                          selected: _isFragile,
                          onSelected: (v) => _rebuildMerchantUi(() => _isFragile = v),
                        ),
                        FilterChip(
                          label: const Text('Giữ lạnh'),
                          selected: _isKeepCold,
                          onSelected: (v) => _rebuildMerchantUi(() => _isKeepCold = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Người trả phí vận chuyển',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                    RadioGroup<String>(
                      groupValue: _feePayer,
                      onChanged: (v) {
                        if (v != null) _rebuildMerchantUi(() => _feePayer = v);
                      },
                      child: const Row(
                        children: [
                          Expanded(
                            child: RadioListTile<String>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: 'Người gửi trả phí',
                              title: Text(
                                'Người gửi trả phí',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<String>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: 'Người nhận trả phí',
                              title: Text(
                                'Người nhận trả phí',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Loại dịch vụ',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                    RadioGroup<DeliveryServiceType>(
                      groupValue: _merchantServiceType,
                      onChanged: (v) {
                        if (v != null) _rebuildMerchantUi(() => _merchantServiceType = v);
                      },
                      child: const Row(
                        children: [
                          Expanded(
                            child: RadioListTile<DeliveryServiceType>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: DeliveryServiceType.express30m,
                              title: Text(
                                'Giao nhanh',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<DeliveryServiceType>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: DeliveryServiceType.standard,
                              title: Text(
                                'Tiêu chuẩn',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<DeliveryServiceType>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: DeliveryServiceType.saving,
                              title: Text(
                                'Tiết kiệm',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );

            final rightSummaryCol = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.all(Radius.zero),
                    border: Border.all(color: const Color(0xFF15131E)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Map3dPerspectiveWidget(
                    height: 225,
                    mode: MapViewMode.customerPreview,
                    is3dMode: _store.isMap3dEnabled,
                    speedKmh: 0,
                    onToggle3d: _store.toggleMap3d,
                    routePoints: previewMerchantRoute,
                    pickupLabel: '[A] Kho Shop',
                    dropoffLabel: '[B] Điểm giao',
                    nextTurnInstruction:
                        'Lộ trình Kho → Điểm giao (${distKm.toStringAsFixed(1)} km)',
                    roadName: _selectedWarehouseName,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.zero),
                    border: Border.all(color: const Color(0xFF15131E)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Phí ước tính',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _merchantEstimateRow(
                        'Khoảng cách',
                        '${distKm.toStringAsFixed(1)} km',
                      ),
                      const SizedBox(height: 8),
                      _merchantEstimateRow(
                        'Thời gian dự kiến',
                        '$etaMins phút',
                      ),
                      const SizedBox(height: 8),
                      _merchantEstimateRow(
                        'Phí vận chuyển',
                        CurrencyFormatter.formatVnd(totalEstimated),
                      ),
                      const SizedBox(height: 8),
                      _merchantEstimateRow(
                        'Tiền thu hộ COD',
                        CurrencyFormatter.formatVnd(codVal),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _feePayer == 'Người nhận trả phí'
                                  ? 'Tổng thu người nhận (Cước + COD)'
                                  : 'Tổng cước vận chuyển',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            CurrencyFormatter.formatVnd(
                              _feePayer == 'Người nhận trả phí'
                                  ? totalEstimated + codVal
                                  : totalEstimated,
                            ),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF15131E),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5E83),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.zero),
                      ),
                    ),
                    onPressed: () {
                      final rName = _singleNameCtrl.text.trim();
                      final rPhone =
                          _singlePhoneCtrl.text.trim().replaceAll(' ', '');
                      final rAddr = _singleAddrCtrl.text.trim();
                      if (rName.isEmpty || rPhone.isEmpty || rAddr.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Vui lòng nhập đầy đủ Tên, SĐT và Địa chỉ người nhận!',
                            ),
                          ),
                        );
                        return;
                      }
                      if (!RegExp(r'^(\+84|0)[0-9]{8,10}$').hasMatch(rPhone)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Số điện thoại người nhận không hợp lệ (gồm 10 chữ số)!',
                            ),
                          ),
                        );
                        return;
                      }
                      final tags = <String>[
                        _isFragile ? 'Dễ vỡ' : 'Tiêu chuẩn',
                        if (_isKeepCold) 'Giữ lạnh',
                      ];
                      final noteStr = _singleNoteCtrl.text.trim();
                      final pkgDesc = noteStr.isNotEmpty
                          ? '$_singlePkgCategory (${tags.join(", ")}) • Ghi chú: $noteStr'
                          : '$_singlePkgCategory (${tags.join(", ")})';
                      final ord = _store.createNewOrder(
                        pickupAddress: pickupAddr,
                        dropoffAddress: rAddr,
                        recipientName: rName,
                        recipientPhone: rPhone,
                        packageDescription: pkgDesc,
                        weightKg: weightVal,
                        dimensionsCm: _singleDimCtrl.text.trim(),
                        serviceType: _merchantServiceType,
                        codAmount: codVal,
                        paymentMethod: _feePayer,
                      );
                      _rebuildMerchantUi(() {
                        _singleNameCtrl.clear();
                        _singlePhoneCtrl.clear();
                        _singleAddrCtrl.clear();
                        _singleNoteCtrl.clear();
                        _singleCodCtrl.text = '0';
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã tạo vận đơn B2B ${ord.trackingCode} thành công!',
                          ),
                        ),
                      );
                    },
                    child: const Text(
                      'Tạo đơn',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            );

            if (twoCol) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: leftFormCard),
                  const SizedBox(width: 20),
                  Expanded(flex: 4, child: rightSummaryCol),
                ],
              );
            }
            return Column(
              children: [
                leftFormCard,
                const SizedBox(height: 16),
                rightSummaryCol,
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _merchantEstimateRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF4A4754), fontSize: 13.5),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              color: Color(0xFF15131E),
            ),
          ),
        ),
      ],
    );
  }


  /// UC33: Tạo đơn hàng loạt từ Excel/CSV & Kiểm lỗi tự động (Chuẩn uc33_don_hang_loat_v2)
  Widget _buildBatchCsvUploadAndValidationView() {
    final validCount = _parsedRows.where((r) => r.isValid).length;
    final errorCount = _parsedRows.length - validCount;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.zero),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFFF5E83),
              borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
            ),
            child: const Text(
              'Tạo đơn hàng loạt (Excel / CSV)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5B33E6),
                      ),
                      onPressed: () {
                        final path = _store.exportReportFileToDisk(
                          fileName: 'Mau_Tao_Don_Hang_Loat.csv',
                          content:
                              'ten_nguoi_nhan,sdt_nguoi_nhan,dia_chi_giao,mo_ta_hang,khoi_luong_kg,tien_cod_vnd,loai_dich_vu\n'
                              '${_csvInputCtrl.text}',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Đã xuất mẫu file chuẩn tại: $path',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Tải mẫu Excel (.xlsx)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        final path = _store.exportReportFileToDisk(
                          fileName: 'Mau_Tao_Don_Hang_Loat.csv',
                          content:
                              'ten_nguoi_nhan,sdt_nguoi_nhan,dia_chi_giao,tien_cod_vnd\n'
                              '${_csvInputCtrl.text}',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Đã lưu file mẫu CSV thực tế tại: $path',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.description_outlined, size: 16),
                      label: const Text('Tải mẫu CSV (.csv)'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F1E8),
                    borderRadius: BorderRadius.all(Radius.zero),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.cloud_upload_outlined,
                            color: Color(0xFF5B33E6),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Kéo thả file Excel/CSV hoặc nhập dữ liệu hàng loạt để kiểm lỗi trực tiếp:',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _csvInputCtrl,
                        maxLines: 3,
                        onChanged: (_) => _rebuildMerchantUi(_parseCsvBatch),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText:
                              'Tên người nhận, SĐT (10 số), Địa chỉ chi tiết, Tiền COD',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    const Text(
                      'Bảng xem trước dữ liệu & Kiểm lỗi (Preview)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.all(Radius.zero),
                          ),
                          child: Text(
                            'Hợp lệ: $validCount đơn',
                            style: const TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.all(Radius.zero),
                          ),
                          child: Text(
                            'Lỗi: $errorCount đơn',
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      const Color(0xFFF5F1E8),
                    ),
                    columns: const [
                      DataColumn(label: Text('Dòng')),
                      DataColumn(label: Text('Người nhận')),
                      DataColumn(label: Text('Số điện thoại')),
                      DataColumn(label: Text('Địa chỉ giao hàng')),
                      DataColumn(label: Text('COD (đ)')),
                      DataColumn(label: Text('Trạng thái kiểm lỗi')),
                    ],
                    rows: _parsedRows.map((r) {
                      return DataRow(
                        color: WidgetStateProperty.all(
                          r.isValid
                              ? Colors.white
                              : AppColors.danger.withValues(alpha: 0.06),
                        ),
                        cells: [
                          DataCell(Text('#${r.rowNumber}')),
                          DataCell(
                            Text(
                              r.recipientName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          DataCell(Text(r.phone)),
                          DataCell(Text(r.address)),
                          DataCell(
                            Text(CurrencyFormatter.formatVnd(r.codAmount)),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  r.isValid
                                      ? Icons.check_circle
                                      : Icons.cancel,
                                  size: 16,
                                  color: r.isValid
                                      ? AppColors.success
                                      : AppColors.danger,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  r.isValid
                                      ? 'Hợp lệ'
                                      : (r.validationError ?? 'Lỗi'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: r.isValid
                                        ? AppColors.success
                                        : AppColors.danger,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5E83),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 13,
                      ),
                    ),
                    onPressed: validCount == 0
                        ? null
                        : () {
                            final safeWhIdx = _store.merchantWarehouses.isEmpty
                                ? 0
                                : _selectedWarehouseIndex.clamp(
                                    0,
                                    _store.merchantWarehouses.length - 1,
                                  );
                            final selectedWhAddr =
                                _store.merchantWarehouses[safeWhIdx].address;
                            for (final r
                                in _parsedRows.where((x) => x.isValid)) {
                              _store.createNewOrder(
                                pickupAddress: selectedWhAddr,
                                dropoffAddress: r.address,
                                recipientName: r.recipientName,
                                recipientPhone: r.phone,
                                packageDescription: r.packageDescription,
                                weightKg: r.weightKg,
                                dimensionsCm: '25x20x10 cm',
                                serviceType: r.serviceType,
                                codAmount: r.codAmount,
                                paymentMethod: r.codAmount > 0
                                    ? 'Tiền mặt (COD)'
                                    : 'Đã thanh toán trước',
                              );
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Đã tạo thành công $validCount đơn hàng hợp lệ vào cơ sở dữ liệu!',
                                ),
                              ),
                            );
                          },
                    icon: const Icon(Icons.playlist_add_check),
                    label: Text(
                      'Xác nhận tạo $validCount đơn hợp lệ',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// UC34: Quản lý & In phiếu gửi hàng A6 (Chuẩn uc34_in_phieu_v2)
  Widget _buildWaybillA6PrintView() {
    final safeIdx = _selectedWaybillOrderIndex.clamp(
      0,
      _store.orders.length - 1,
    );
    final ord = _store.orders[safeIdx];
    return LayoutBuilder(
      builder: (context, constraints) {
        final colLeft = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.zero),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  const Text(
                    'Chọn đơn cần in phiếu gửi hàng',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5E83),
                    ),
                    onPressed: () async {
                      final savedPath = await SecurityAndBarcodeUtils
                          .exportA6LabelToHtmlFile(
                        trackingCode: ord.trackingCode,
                        storeName: _store.merchantStoreName,
                        warehouseAddress: ord.pickupAddress.isNotEmpty
                            ? ord.pickupAddress
                            : _store.merchantWarehouses.first.address,
                        recipientName: ord.recipientName,
                        recipientPhone: ord.recipientPhone,
                        dropoffAddress: ord.dropoffAddress,
                        packageDescription: ord.packageDescription,
                        codAmount: ord.codAmount,
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã kết xuất tệp vận đơn khổ A6 thực tế tại: $savedPath',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.print, size: 16),
                    label: Text('In phiếu A6 (${ord.trackingCode})'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  showCheckboxColumn: false,
                  headingRowColor: WidgetStateProperty.all(
                    const Color(0xFFF5F1E8),
                  ),
                  columns: const [
                    DataColumn(label: Text('Chọn')),
                    DataColumn(label: Text('Mã đơn')),
                    DataColumn(label: Text('Người nhận')),
                    DataColumn(label: Text('Thu hộ COD')),
                    DataColumn(label: Text('Trạng thái')),
                  ],
                  rows: _store.orders.asMap().entries.map((entry) {
                    final rowIdx = entry.key;
                    final o = entry.value;
                    final isSelected = rowIdx == safeIdx;
                    return DataRow(
                      selected: isSelected,
                      onSelectChanged: (_) {
                        _rebuildMerchantUi(() => _selectedWaybillOrderIndex = rowIdx);
                      },
                      cells: [
                        DataCell(
                          Icon(
                            isSelected
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            color: const Color(0xFFFF5E83),
                            size: 18,
                          ),
                        ),
                        DataCell(
                          Text(
                            o.trackingCode,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        DataCell(Text(o.recipientName)),
                        DataCell(
                          Text(CurrencyFormatter.formatVnd(o.codAmount)),
                        ),
                        DataCell(
                          Text(
                            o.paymentStatus == 'RETURNED'
                                ? 'Đã hoàn kho'
                                : o.status.displayName,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
        final colRight = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.zero),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Xem trước Phiếu gửi hàng (Khổ A6)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.zero),
                  border: Border.all(color: Colors.black87, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Code128BarcodeWidget(
                            data: 'GHN-987654321-${ord.trackingCode}',
                            height: 42,
                          ),
                        ),
                        const SizedBox(width: 10),
                        QrMatrixPainterWidget(
                          payload:
                              '${ord.trackingCode}|${ord.recipientPhone}|${ord.codAmount.toStringAsFixed(0)}',
                          size: 62,
                        ),
                      ],
                    ),
                    const Divider(),
                    Text(
                      'NGƯỜI GỬI: ${_store.merchantStoreName}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'Kho lấy: ${ord.pickupAddress.isNotEmpty ? ord.pickupAddress : _store.merchantWarehouses.first.address}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    const Divider(),
                    Text(
                      'NGƯỜI NHẬN: ${ord.recipientName} - ${ord.recipientPhone}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                    Text(
                      'Địa chỉ: ${ord.dropoffAddress}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Hàng hóa: ${ord.packageDescription}',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'COD: ${CurrencyFormatter.formatVnd(ord.codAmount)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.danger,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
        if (constraints.maxWidth < 820) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              colLeft,
              const SizedBox(height: 16),
              colRight,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: colLeft),
            const SizedBox(width: 16),
            Expanded(flex: 5, child: colRight),
          ],
        );
      },
    );
  }
}
