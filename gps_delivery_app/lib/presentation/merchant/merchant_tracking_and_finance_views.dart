part of 'merchant_subsystem_views.dart';

extension _MerchantTrackingAndFinanceViews on _MerchantSubsystemEntryState {
  /// UC35: Theo dõi trạng thái nhiều đơn hàng cùng lúc (Chuẩn uc35_theo_doi_don_shop)
  Widget _buildMultiOrderTrackingView() {
    final tabs = [
      'Tất cả',
      'Chờ lấy',
      'Đang giao',
      'Đã giao',
      'Giao thất bại',
      'Hoàn hàng',
    ];
    final filtered = _store.orders.where((o) {
      if (_shopOrderStatusTab == 'Tất cả') return true;
      if (_shopOrderStatusTab == 'Chờ lấy') {
        return o.status == OrderStatus.searching ||
            o.status == OrderStatus.accepted ||
            o.status == OrderStatus.arrivingPickup;
      }
      if (_shopOrderStatusTab == 'Đang giao') {
        return o.status == OrderStatus.inTransit;
      }
      if (_shopOrderStatusTab == 'Đã giao') {
        return o.status == OrderStatus.delivered &&
            o.paymentStatus != 'RETURNED';
      }
      if (_shopOrderStatusTab == 'Giao thất bại') {
        return o.status == OrderStatus.failed;
      }
      if (_shopOrderStatusTab == 'Hoàn hàng') {
        return o.status == OrderStatus.cancelled ||
            o.status == OrderStatus.returning ||
            o.paymentStatus == 'RETURNED';
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tabs.map((t) {
            final selected = _shopOrderStatusTab == t;
            return ChoiceChip(
              label: Text(t),
              selected: selected,
              selectedColor: const Color(0xFFFF5E83),
              labelStyle: TextStyle(
                color: selected ? Colors.white : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              onSelected: (_) => _rebuildMerchantUi(() => _shopOrderStatusTab = t),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final colLeft = Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: AppColors.divider),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    const Color(0xFFF5F1E8),
                  ),
                  columns: const [
                    DataColumn(label: Text('Mã đơn')),
                    DataColumn(label: Text('Người nhận')),
                    DataColumn(label: Text('Tài xế')),
                    DataColumn(label: Text('COD')),
                    DataColumn(label: Text('Trạng thái')),
                    DataColumn(label: Text('Thao tác')),
                  ],
                  rows: filtered.map((o) {
                    return DataRow(
                      cells: [
                        DataCell(
                          Text(
                            o.trackingCode,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF5B33E6),
                            ),
                          ),
                          onTap: () {
                            final idx = _store.orders.indexOf(o);
                            if (idx >= 0) {
                              _rebuildMerchantUi(
                                () => _selectedWaybillOrderIndex = idx,
                              );
                            }
                          },
                        ),
                        DataCell(Text(o.recipientName)),
                        DataCell(
                          Text(o.assignedDriverName ?? 'Đang tìm TX'),
                        ),
                        DataCell(
                          Text(CurrencyFormatter.formatVnd(o.codAmount)),
                        ),
                        DataCell(
                          Chip(
                            label: Text(
                              o.paymentStatus == 'RETURNED'
                                  ? 'Đã hoàn kho'
                                  : o.status.displayName,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                ),
                                onPressed: () {
                                  final idx = _store.orders.indexOf(o);
                                  _rebuildMerchantUi(() {
                                    if (idx >= 0) {
                                      _selectedWaybillOrderIndex = idx;
                                    }
                                    _selectedScreenIndex = 4;
                                  });
                                },
                                icon: const Icon(
                                  Icons.print_outlined,
                                  size: 14,
                                ),
                                label: const Text(
                                  'In A6',
                                  style: TextStyle(fontSize: 11.5),
                                ),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                ),
                                onPressed: () {
                                  final idx = _store.orders.indexOf(o);
                                  _rebuildMerchantUi(() {
                                    if (idx >= 0) {
                                      _selectedWaybillOrderIndex = idx;
                                    }
                                    _editOrderNameCtrl.text = o.recipientName;
                                    _editOrderPhoneCtrl.text = o.recipientPhone;
                                    _editOrderAddrCtrl.text = o.dropoffAddress;
                                    _editOrderCodCtrl.text =
                                        o.codAmount.toStringAsFixed(0);
                                    _lastSyncedEditOrderCode = o.trackingCode;
                                    _selectedScreenIndex = 6;
                                  });
                                },
                                icon: const Icon(
                                  Icons.edit_note_outlined,
                                  size: 15,
                                ),
                                label: const Text(
                                  'Sửa/Hủy',
                                  style: TextStyle(fontSize: 11.5),
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
            );
            final safeFocusIdx = _store.orders.isEmpty
                ? 0
                : _selectedWaybillOrderIndex.clamp(0, _store.orders.length - 1);
            final focusedOrd = filtered.isNotEmpty
                ? (filtered.contains(_store.orders[safeFocusIdx])
                    ? _store.orders[safeFocusIdx]
                    : filtered.first)
                : _store.orders[safeFocusIdx];
            final focusedRoutePoints =
                _store.activeOrderRecord?.trackingCode ==
                            focusedOrd.trackingCode &&
                        _store.activeRoutePolyline.length >= 2
                    ? _store.activeRoutePolyline
                    : SmartDispatchEngine.generateRoutePolyline(
                        focusedOrd.pickupLocation,
                        focusedOrd.dropoffLocation,
                        segments: 10,
                      );
            final colRight = Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vị trí Tài xế & Chi tiết đơn ${focusedOrd.trackingCode}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Map3dPerspectiveWidget(
                    height: 195,
                    mode: MapViewMode.fleetOverview,
                    is3dMode: _store.isMap3dEnabled,
                    speedKmh: _store.currentSpeedKmh,
                    onToggle3d: _store.toggleMap3d,
                    progressFraction: _store.routeProgressStep / 10.0,
                    routePoints: focusedRoutePoints,
                    pickupLabel: 'Lấy: ${focusedOrd.pickupAddress}',
                    dropoffLabel: 'Giao: ${focusedOrd.dropoffAddress}',
                    nextTurnInstruction:
                        'Giám sát trực tiếp ${filtered.length} vận đơn • Đang chọn: ${focusedOrd.trackingCode} (${focusedOrd.status.displayName})',
                    roadName: '${focusedOrd.pickupAddress} → ${focusedOrd.dropoffAddress}',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          _store.selectDriverOrder(focusedOrd.trackingCode);
                          final msg =
                              await _store.syncLiveOsrmRouteForActiveOrder();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(msg)),
                          );
                        },
                        icon: const Icon(Icons.alt_route_rounded, size: 15),
                        label: const Text(
                          'Đồng bộ lộ trình OSRM',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F1E8),
                      borderRadius: BorderRadius.all(Radius.zero),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          focusedOrd.podImageNote != null
                              ? Icons.verified_outlined
                              : Icons.local_shipping_outlined,
                          color: focusedOrd.podImageNote != null
                              ? AppColors.success
                              : const Color(0xFF5B33E6),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            focusedOrd.podImageNote != null
                                ? 'Bằng chứng POD (${focusedOrd.trackingCode}): ${focusedOrd.podImageNote}'
                                : 'Đơn ${focusedOrd.trackingCode} (${focusedOrd.status.displayName}) • Tài xế: ${focusedOrd.assignedDriverName ?? "Đang tìm TX"} • Ảnh POD sẽ đồng bộ ngay sau khi giao.',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
            if (constraints.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  colLeft,
                  const SizedBox(height: 14),
                  colRight,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: colLeft),
                const SizedBox(width: 14),
                Expanded(flex: 5, child: colRight),
              ],
            );
          },
        ),
      ],
    );
  }

  /// UC36: Sửa / Hủy đơn hàng & Yêu cầu Giao lại / Hoàn hàng (Chuẩn uc36_sua_huy_don_v2)
  Widget _buildScheduledPickupRequestView() {
    final safeIdx = _selectedWaybillOrderIndex.clamp(
      0,
      _store.orders.length - 1,
    );
    final ord = _store.orders[safeIdx];
    if (_lastSyncedEditOrderCode != ord.trackingCode) {
      _editOrderNameCtrl.text = ord.recipientName;
      _editOrderPhoneCtrl.text = ord.recipientPhone;
      _editOrderAddrCtrl.text = ord.dropoffAddress;
      _editOrderCodCtrl.text = ord.codAmount.toStringAsFixed(0);
      _lastSyncedEditOrderCode = ord.trackingCode;
    }
    final cancelReasons = [
      'Khách hàng báo hủy đơn',
      'Shop hết hàng / Đổi mẫu sản phẩm',
      'Nhập sai địa chỉ hoặc tiền thu hộ COD',
      'Khách không nghe máy sau 3 lần gọi',
    ];

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
                spacing: 6,
                runSpacing: 6,
                children: _store.orders.asMap().entries.map((e) {
                  final idx = e.key;
                  final item = e.value;
                  final selected = idx == safeIdx;
                  final statusLabel = item.paymentStatus == 'RETURNED'
                      ? 'Đã hoàn kho'
                      : item.status.displayName;
                  return ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${item.trackingCode} ($statusLabel)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                    selected: selected,
                    selectedColor: const Color(0xFF5B33E6),
                    onSelected: (_) => _rebuildMerchantUi(() {
                      _selectedWaybillOrderIndex = idx;
                      _editOrderNameCtrl.text = item.recipientName;
                      _editOrderPhoneCtrl.text = item.recipientPhone;
                      _editOrderAddrCtrl.text = item.dropoffAddress;
                      _editOrderCodCtrl.text = item.codAmount.toStringAsFixed(0);
                      _lastSyncedEditOrderCode = item.trackingCode;
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF5B33E6),
                  borderRadius: BorderRadius.all(Radius.zero),
                ),
                child: Text(
                  'Chỉnh sửa đơn hàng ${ord.trackingCode} (${ord.status.displayName})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _editOrderNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tên người nhận',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _editOrderPhoneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại người nhận',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _editOrderAddrCtrl,
                decoration: const InputDecoration(
                  labelText: 'Địa chỉ giao hàng mới',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _editOrderCodCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tiền thu hộ COD (VNĐ)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF14B866),
                  ),
                  onPressed: ord.status == OrderStatus.delivered ||
                          ord.status == OrderStatus.cancelled
                      ? null
                      : () {
                          if (_editOrderNameCtrl.text.trim().isEmpty ||
                              _editOrderPhoneCtrl.text.trim().isEmpty ||
                              _editOrderAddrCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Vui lòng nhập đầy đủ Tên, SĐT và Địa chỉ người nhận mới!',
                                ),
                              ),
                            );
                            return;
                          }
                          final newCod = double.tryParse(
                                _editOrderCodCtrl.text.replaceAll(
                                  RegExp(r'[^0-9.]'),
                                  '',
                                ),
                              ) ??
                              ord.codAmount;
                          final ok = _store.updateExistingOrderDetails(
                            trackingCode: ord.trackingCode,
                            recipientName: _editOrderNameCtrl.text,
                            recipientPhone: _editOrderPhoneCtrl.text,
                            dropoffAddress: _editOrderAddrCtrl.text,
                            codAmount: newCod,
                          );
                          if (!ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.danger,
                                content: Text(
                                  'Không thể chỉnh sửa đơn ${ord.trackingCode} vì đơn đã ở trạng thái ${ord.status.displayName}.',
                                ),
                              ),
                            );
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Đã lưu thay đổi thông tin đơn ${ord.trackingCode} vào CSDL SQLite!',
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Lưu thay đổi thông tin đơn'),
                ),
              ),
            ],
          ),
        );
        final colRight = Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.all(Radius.zero),
                    ),
                    child: Text(
                      'Hủy đơn hàng ${ord.trackingCode}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Material(
                    color: Colors.transparent,
                    child: RadioGroup<String>(
                      groupValue: _shopCancelReason,
                      onChanged: (v) {
                        if (v != null) _rebuildMerchantUi(() => _shopCancelReason = v);
                      },
                      child: Column(
                        children: cancelReasons
                            .map(
                              (r) => RadioListTile<String>(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: r,
                                title: Text(
                                  r,
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                      ),
                      onPressed: ord.status.canTransitionTo(OrderStatus.cancelled)
                          ? () {
                              final ok = _store.cancelOrder(
                                ord.trackingCode,
                                _shopCancelReason,
                              );
                              if (!ok) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: AppColors.danger,
                                    content: Text(
                                      'Không thể hủy đơn ${ord.trackingCode}: Tài xế đã lấy hàng hoặc đang giao (${ord.status.displayName}).',
                                    ),
                                  ),
                                );
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Đã hủy đơn ${ord.trackingCode}: $_shopCancelReason',
                                  ),
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Xác nhận Hủy đơn hàng'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Hành động nhanh (Đơn giao thất bại)',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ord.status == OrderStatus.failed
                        ? 'Đơn ${ord.trackingCode} đang ở trạng thái Giao thất bại. Vui lòng chọn Giao lại hoặc Hoàn hàng về kho:'
                        : 'Chỉ kích hoạt khi vận đơn ${ord.trackingCode} chuyển sang trạng thái Giao thất bại (hiện tại: ${ord.status.displayName}).',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ord.status == OrderStatus.failed
                          ? AppColors.danger
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5E83),
                        ),
                        onPressed: ord.status != OrderStatus.failed
                            ? null
                            : () {
                                final ok = _store.requeueOrReturnOrder(
                                  ord.trackingCode,
                                  isReturn: false,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      ok
                                          ? 'Đã kích hoạt lệnh Giao lại cho đơn ${ord.trackingCode} trong CSDL!'
                                          : 'Không thể giao lại đơn ${ord.trackingCode} đã hoàn tất!',
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.replay, size: 16),
                        label: const Text('Yêu cầu Giao lại'),
                      ),
                      OutlinedButton.icon(
                        onPressed: ord.status != OrderStatus.failed
                            ? null
                            : () {
                                final ok = _store.requeueOrReturnOrder(
                                  ord.trackingCode,
                                  isReturn: true,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      ok
                                          ? 'Đã cập nhật trạng thái Hoàn hàng về kho cho ${ord.trackingCode}!'
                                          : 'Không thể hoàn hàng đơn ${ord.trackingCode}!',
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(
                          Icons.assignment_return_outlined,
                          size: 16,
                        ),
                        label: const Text('Hoàn hàng về điểm lấy'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
        if (constraints.maxWidth < 760) {
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
            Expanded(child: colLeft),
            const SizedBox(width: 16),
            Expanded(child: colRight),
          ],
        );
      },
    );
  }

  /// UC37: Đối soát công nợ tiền thu hộ COD (Chuẩn uc37_doi_soat_v2)
  Widget _buildCodReconciliationView() {
    double shipDeductedFromMerchantCod(ActiveOrderRecord o) {
      if (o.codAmount <= 0) return 0.0;
      final isRecipientOrPrepaid = o.paymentMethod == 'Người nhận trả phí' ||
          o.paymentMethod.contains('MoMo') ||
          o.paymentMethod.contains('VNPay') ||
          o.paymentMethod.contains('ZaloPay');
      return isRecipientOrPrepaid ? 0.0 : o.totalAmount;
    }

    double codHandlingFeeOf(ActiveOrderRecord o) {
      return o.codAmount > 2000000
          ? (o.codAmount * 0.005).roundToDouble()
          : 0.0;
    }

    final deliveredCodOrders = _store.orders.where(
      (o) =>
          o.status == OrderStatus.delivered &&
          o.paymentStatus != 'RETURNED',
    );
    final totalCod = deliveredCodOrders.fold<double>(
      0,
      (sum, o) => sum + o.codAmount,
    );
    final totalShipFee = deliveredCodOrders.fold<double>(
      0,
      (sum, o) => sum + shipDeductedFromMerchantCod(o),
    );
    final totalCodHandlingFee = deliveredCodOrders.fold<double>(
      0,
      (sum, o) => sum + codHandlingFeeOf(o),
    );
    final netCod = (totalCod - totalShipFee - totalCodHandlingFee)
        .clamp(0.0, double.infinity);

    return Container(
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
            spacing: 12,
            runSpacing: 8,
            children: [
              const Text(
                'Đối soát Công nợ & Tiền thu hộ COD',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF14B866),
                ),
                onPressed: () {
                  final csvLines = <String>[
                    'ma_don,nguoi_nhan,tien_cod_vnd,phi_giao_vnd,phi_cod_vnd,thuc_nhan_vnd,trang_thai',
                    ..._store.orders.map((o) {
                      final isVoided = o.status == OrderStatus.cancelled ||
                          o.status == OrderStatus.failed ||
                          o.status == OrderStatus.returning ||
                          o.paymentStatus == 'RETURNED';
                      final isSettled =
                          o.status == OrderStatus.delivered && !isVoided;
                      final codFee = isVoided ? 0.0 : codHandlingFeeOf(o);
                      final shipDeduct =
                          isVoided ? 0.0 : shipDeductedFromMerchantCod(o);
                      final netVal = !isSettled
                          ? 0.0
                          : (o.codAmount - shipDeduct - codFee)
                              .clamp(0.0, double.infinity);
                      return '${o.trackingCode},${o.recipientName},${o.codAmount.toStringAsFixed(0)},${shipDeduct.toStringAsFixed(0)},${codFee.toStringAsFixed(0)},${netVal.toStringAsFixed(0)},${o.status.displayName}';
                    }),
                  ];
                  final path = _store.exportReportFileToDisk(
                    fileName: 'Doi_Soat_COD.csv',
                    content: csvLines.join('\n'),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã xuất bảng đối soát công nợ tại: $path',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.table_view, size: 16),
                label: const Text('Xuất Excel'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, codConstraints) {
              final maxW = codConstraints.maxWidth;
              final cols = maxW >= 680
                  ? 3
                  : maxW >= 440
                      ? 2
                      : 1;
              final cardW = cols == 1 ? maxW : (maxW - (cols - 1) * 12.0) / cols;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _codCard(
                    'Tổng COD đã thu',
                    CurrencyFormatter.formatVnd(totalCod),
                    const Color(0xFF5B33E6),
                    width: cardW,
                  ),
                  _codCard(
                    'Tổng Phí vận chuyển',
                    '-${CurrencyFormatter.formatVnd(totalShipFee)}',
                    AppColors.danger,
                    width: cardW,
                  ),
                  _codCard(
                    'Thực nhận (COD - Phí)',
                    CurrencyFormatter.formatVnd(netCod),
                    AppColors.success,
                    width: cardW,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                const Color(0xFFF5F1E8),
              ),
              columns: const [
                DataColumn(label: Text('Mã đơn')),
                DataColumn(label: Text('Ngày giao')),
                DataColumn(label: Text('Tiền COD')),
                DataColumn(label: Text('Phí giao')),
                DataColumn(label: Text('Phí COD')),
                DataColumn(label: Text('Thực nhận')),
                DataColumn(label: Text('Trạng thái')),
              ],
              rows: _store.orders.map((o) {
                final isReturnedToWarehouse =
                    o.paymentStatus == 'RETURNED' ||
                    o.status == OrderStatus.returning;
                final isVoided = o.status == OrderStatus.cancelled ||
                    o.status == OrderStatus.failed ||
                    isReturnedToWarehouse;
                final done =
                    o.status == OrderStatus.delivered && !isReturnedToWarehouse;
                final codHandlingFee =
                    isVoided ? 0.0 : codHandlingFeeOf(o);
                final shipDeduct =
                    isVoided ? 0.0 : shipDeductedFromMerchantCod(o);
                final expectedNet = isVoided
                    ? 0.0
                    : (o.codAmount - shipDeduct - codHandlingFee)
                        .clamp(0.0, double.infinity);
                final net = done ? expectedNet : 0.0;
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        o.trackingCode,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DataCell(Text(o.createdDateLabel)),
                    DataCell(
                      Text(
                        isVoided
                            ? '0 đ'
                            : CurrencyFormatter.formatVnd(o.codAmount),
                      ),
                    ),
                    DataCell(
                      Text(
                        isVoided || shipDeduct == 0
                            ? '0 đ (${o.paymentMethod})'
                            : '-${CurrencyFormatter.formatVnd(shipDeduct)}',
                      ),
                    ),
                    DataCell(
                      Text(
                        codHandlingFee > 0
                            ? '-${CurrencyFormatter.formatVnd(codHandlingFee)}'
                            : '0 đ (Miễn phí)',
                      ),
                    ),
                    DataCell(
                      Text(
                        done
                            ? CurrencyFormatter.formatVnd(net)
                            : isVoided
                                ? '0 đ'
                                : '0 đ (Dự kiến: ${CurrencyFormatter.formatVnd(expectedNet)})',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: isVoided
                              ? AppColors.danger
                              : done
                                  ? AppColors.success
                                  : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    DataCell(
                      Chip(
                        backgroundColor: isVoided
                            ? AppColors.danger.withValues(alpha: 0.14)
                            : done
                                ? AppColors.success.withValues(alpha: 0.14)
                                : const Color(0xFFF5F1E8),
                        label: Text(
                          isReturnedToWarehouse
                              ? 'Đã hoàn kho'
                              : isVoided
                                  ? 'Đã hủy / Thất bại'
                                  : done
                                      ? 'Đã chuyển'
                                      : 'Chờ thu COD',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isVoided
                                ? AppColors.danger
                                : done
                                    ? AppColors.success
                                    : const Color(0xFFFF5E83),
                          ),
                        ),
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
  }

  Widget _codCard(String title, String value, Color color, {double? width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F1E8),
        borderRadius: BorderRadius.all(Radius.zero),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// UC38: Nhận tiền COD về tài khoản ngân hàng (Chuẩn uc38_nhan_tien_cod)
  Widget _buildCodWithdrawalView() {
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
              const Text(
                'Số dư COD khả dụng',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                CurrencyFormatter.formatVnd(_store.merchantCodBalance),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFFF5E83),
                ),
              ),
              const Divider(height: 22),
              Text(
                'Ngân hàng liên kết: ${_store.merchantBankName}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                'Số tài khoản: ${_store.merchantBankAccount}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F1E8),
                  borderRadius: BorderRadius.all(Radius.zero),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.event_repeat,
                      size: 18,
                      color: Color(0xFF5B33E6),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Lịch chuyển tự động: Thứ 2, Thứ 4, Thứ 6 hàng tuần',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5B33E6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _codWithdrawCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số tiền muốn rút ngay (VNĐ)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5E83),
                  ),
                  onPressed: () {
                    final amt = double.tryParse(_codWithdrawCtrl.text) ?? 0;
                    final ok = _store.requestWithdrawal(
                      ownerName: _store.merchantStoreName,
                      ownerRole: 'Cửa hàng (COD)',
                      amount: amt,
                      bankName: _store.merchantBankName,
                      accountMasked: _store.merchantBankAccount,
                    );
                    if (!ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppColors.danger,
                          content: Text(
                            amt <= 0
                                ? 'Vui lòng nhập số tiền rút COD hợp lệ (> 0đ).'
                                : 'Rút tiền thất bại: Số tiền vượt quá số dư COD khả dụng (${CurrencyFormatter.formatVnd(_store.merchantCodBalance)}).',
                          ),
                        ),
                      );
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã tạo lệnh rút COD ${CurrencyFormatter.formatVnd(amt)}!',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Yêu cầu Rút tiền ngay'),
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
          child: Material(
            color: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Lịch sử nhận tiền COD',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 10),
                ..._store.withdrawalRequests
                    .where((w) => w.ownerRole.contains('Cửa hàng'))
                    .map(
                      (w) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.account_balance_wallet_outlined,
                          color: AppColors.success,
                        ),
                        title: Text(
                          '#${w.id} • ${CurrencyFormatter.formatVnd(w.amount)}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text('${w.bankName} (${w.accountMasked})'),
                        trailing: Chip(
                          label: Text(
                            w.status,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        );
        if (constraints.maxWidth < 760) {
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
            Expanded(flex: 5, child: colLeft),
            const SizedBox(width: 16),
            Expanded(flex: 6, child: colRight),
          ],
        );
      },
    );
  }

  /// UC39: Báo cáo & Thống kê Cửa hàng (Chuẩn anh_sua_lai/uc39_bao_cao_shop.jpg)
  Widget _buildReturnAndMonthlyAnalyticsView() {
    final totalOrders = _store.orders.length;
    final safeTotal = totalOrders == 0 ? 1 : totalOrders;
    final deliveredOrders = _store.orders
        .where(
          (o) =>
              o.status == OrderStatus.delivered &&
              o.paymentStatus != 'RETURNED',
        )
        .toList();
    final deliveredCount = deliveredOrders.length;
    final failedOnlyCount =
        _store.orders.where((o) => o.status == OrderStatus.failed).length;
    final returnedCount = _store.orders
        .where(
          (o) =>
              o.status == OrderStatus.cancelled ||
              o.status == OrderStatus.returning ||
              o.paymentStatus == 'RETURNED',
        )
        .length;
    final failedCount = failedOnlyCount + returnedCount;
    final successRate = deliveredCount * 100.0 / safeTotal;
    final failedRate = failedOnlyCount * 100.0 / safeTotal;
    final returnedRate = returnedCount * 100.0 / safeTotal;
    final totalCod = deliveredOrders.fold<double>(
      0,
      (sum, o) => sum + o.codAmount,
    );
    final totalShip = deliveredOrders.fold<double>(
      0,
      (sum, o) => sum + o.totalAmount,
    );
    final dayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    int weekdayIndexOfMerchantOrder(ActiveOrderRecord o) {
      final parts = o.createdDateLabel.split('/');
      if (parts.length == 3) {
        final d = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (d != null && m != null && y != null) {
          return (DateTime(y, m, d).weekday - 1).clamp(0, 6);
        }
      }
      return (DateTime.now().weekday - 1).clamp(0, 6);
    }

    final dayCounts = List<int>.generate(7, (idx) {
      return _store.orders
          .where((o) => weekdayIndexOfMerchantOrder(o) == idx)
          .length;
    });
    final maxDay = dayCounts.fold<int>(1, (m, c) => c > m ? c : m);
    final dailyChartItems = List.generate(7, (idx) {
      final ratio = dayCounts[idx] == 0
          ? 0.22
          : (dayCounts[idx] / maxDay).clamp(0.25, 1.0);
      return (dayLabels[idx], ratio);
    });

    return Container(
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
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                'Báo cáo & Thống kê Cửa hàng (Tháng ${DateTime.now().month}/${DateTime.now().year})',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5E83),
                ),
                onPressed: () {
                  final reportContent =
                      'BAO CAO THONG KE CUA HANG (${_store.merchantStoreName})\n'
                      'Tong don gui: $totalOrders\n'
                      'Giao thanh cong: $deliveredCount (${successRate.toStringAsFixed(1)}%)\n'
                      'Giao that bai / Hoan hang: $failedCount\n'
                      'Tong COD: ${totalCod.toStringAsFixed(0)} VND\n'
                      'Tong phi ship: ${totalShip.toStringAsFixed(0)} VND\n';
                  final path = _store.exportReportFileToDisk(
                    fileName: 'Bao_Cao_Shop_T${DateTime.now().month}.csv',
                    content: reportContent,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã xuất báo cáo thống kê cửa hàng tại: $path',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Xuất báo cáo ↗'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, kpiConstraints) {
              final maxW = kpiConstraints.maxWidth;
              final cols = maxW >= 860
                  ? 3
                  : maxW >= 460
                      ? 2
                      : 1;
              final cardW = cols == 1 ? maxW : (maxW - (cols - 1) * 10.0) / cols;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _codCard(
                    'Tổng đơn gửi',
                    '$totalOrders đơn',
                    const Color(0xFF5B33E6),
                    width: cardW,
                  ),
                  _codCard(
                    'Giao thành công',
                    '$deliveredCount (${successRate.toStringAsFixed(1)}%)',
                    AppColors.success,
                    width: cardW,
                  ),
                  _codCard(
                    'Giao thất bại',
                    '$failedOnlyCount đơn (${failedRate.toStringAsFixed(1)}%)',
                    AppColors.danger,
                    width: cardW,
                  ),
                  _codCard(
                    'Hoàn hàng',
                    '$returnedCount đơn (${returnedRate.toStringAsFixed(1)}%)',
                    const Color(0xFFFF5E83),
                    width: cardW,
                  ),
                  _codCard(
                    'Tổng phí ship',
                    CurrencyFormatter.formatVnd(totalShip),
                    const Color(0xFF5B33E6),
                    width: cardW,
                  ),
                  _codCard(
                    'Tổng COD đã nhận',
                    CurrencyFormatter.formatVnd(totalCod),
                    AppColors.success,
                    width: cardW,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final chartBox = Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F1E8),
                  borderRadius: BorderRadius.all(Radius.zero),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Biểu đồ Số đơn gửi theo ngày (Tháng ${DateTime.now().month})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 120,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final item in dailyChartItems)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    FractionallySizedBox(
                                      widthFactor: 0.65,
                                      child: Container(
                                        height: 85 * item.$2,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF5B33E6),
                                          borderRadius: BorderRadius.all(
                                            Radius.zero,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.$1,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              final statusBox = Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F1E8),
                  borderRadius: BorderRadius.all(Radius.zero),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tỷ lệ trạng thái đơn hàng',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.circle,
                          color: AppColors.success,
                        ),
                        title: Text(
                          'Thành công: ${successRate.toStringAsFixed(1)}% ($deliveredCount đơn)',
                        ),
                      ),
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.circle,
                          color: AppColors.danger,
                        ),
                        title: Text(
                          'Thất bại: ${failedRate.toStringAsFixed(1)}% ($failedOnlyCount đơn)',
                        ),
                      ),
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.circle,
                          color: Color(0xFFFF5E83),
                        ),
                        title: Text(
                          'Hoàn hàng / Đã hủy: ${returnedRate.toStringAsFixed(1)}% ($returnedCount đơn)',
                        ),
                      ),
                    ],
                  ),
                ),
              );
              if (constraints.maxWidth < 760) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    chartBox,
                    const SizedBox(height: 14),
                    statusBox,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: chartBox),
                  const SizedBox(width: 14),
                  Expanded(flex: 5, child: statusBox),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// UC40: Khiếu nại & Hỗ trợ Cửa hàng (Chuẩn uc40_khieu_nai_shop_v2_1791015801837.jpg)
  Widget _buildMerchantComplaintSupportUc40View() {
    final complaintTypes = [
      'Hàng hư hỏng / Mất hàng',
      'Sai lệch tiền thu hộ COD',
      'Tài xế lấy / giao hàng trễ hẹn',
      'Sai cước phí vận chuyển',
    ];

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
              const Text(
                'Gửi khiếu nại mới',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _store.orders.map((ord) {
                  final selected =
                      _shopComplaintOrderCtrl.text.trim() == ord.trackingCode;
                  return ActionChip(
                    backgroundColor: selected
                        ? const Color(0xFFEDE9FE)
                        : const Color(0xFFF5F1E8),
                    label: Text(
                      '${ord.trackingCode} (${ord.status.displayName})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    onPressed: () {
                      _rebuildMerchantUi(() {
                        _shopComplaintOrderCtrl.text = ord.trackingCode;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _shopComplaintOrderCtrl,
                decoration: const InputDecoration(
                  labelText: 'Chọn đơn hàng cần khiếu nại',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _shopComplaintType,
                decoration: const InputDecoration(
                  labelText: 'Loại khiếu nại',
                  isDense: true,
                ),
                items: complaintTypes
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) _rebuildMerchantUi(() => _shopComplaintType = v);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _shopComplaintDescCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Mô tả chi tiết sự cố / yêu cầu bồi thường',
                  hintText:
                      'Nhập tình trạng kiện hàng hoặc chênh lệch COD...',
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () {
                  _rebuildMerchantUi(() {
                    _attachedShopEvidenceCount =
                        (_attachedShopEvidenceCount % 5) + 1;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã đính kèm $_attachedShopEvidenceCount/5 file ảnh/video bằng chứng đối soát!',
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F1E8),
                    borderRadius: BorderRadius.all(Radius.zero),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: Color(0xFF5B33E6),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Đính kèm ảnh/video bằng chứng (Đã chọn: $_attachedShopEvidenceCount/5 file - Bấm để thêm)',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5E83),
                  ),
                  onPressed: () {
                    final baseDesc = _shopComplaintDescCtrl.text.trim().isEmpty
                        ? 'Yêu cầu kiểm tra đối soát / bồi thường đơn hàng'
                        : _shopComplaintDescCtrl.text.trim();
                    _store.addIncidentOrComplaint(
                      orderId: _shopComplaintOrderCtrl.text.trim(),
                      reporterName: _store.merchantStoreName,
                      issueType: 'Shop KN: $_shopComplaintType',
                      description:
                          '$baseDesc • Đính kèm: $_attachedShopEvidenceCount file bằng chứng',
                    );
                    _shopComplaintDescCtrl.clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Đã gửi hồ sơ khiếu nại của Cửa hàng lên bộ phận CSKH Admin!',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.send_outlined, size: 16),
                  label: const Text('Gửi khiếu nại'),
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
                'Danh sách khiếu nại đã gửi',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
              ),
              const SizedBox(height: 12),
              ..._store.complaints.map(
                (c) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F1E8),
                    borderRadius: BorderRadius.all(Radius.zero),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Text(
                            '#${c.ticketCode} - Đơn ${c.orderId}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                            ),
                          ),
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              'Theo dõi ${c.orderId}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: () {
                              final ordIdx = _store.orders.indexWhere(
                                (o) => o.trackingCode == c.orderId,
                              );
                              _rebuildMerchantUi(() {
                                if (ordIdx != -1) {
                                  _selectedWaybillOrderIndex = ordIdx;
                                }
                                _selectedScreenIndex = 5;
                              });
                            },
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              c.status,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Loại: ${c.issueType}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: Color(0xFF5B33E6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        c.description,
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (c.replies.length > 1) ...[
                        const Divider(),
                        ...c.replies.skip(1).map(
                          (rep) => Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              '• $rep',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.success,
                              ),
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
        if (constraints.maxWidth < 760) {
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
            Expanded(flex: 5, child: colLeft),
            const SizedBox(width: 16),
            Expanded(flex: 6, child: colRight),
          ],
        );
      },
    );
  }
}
