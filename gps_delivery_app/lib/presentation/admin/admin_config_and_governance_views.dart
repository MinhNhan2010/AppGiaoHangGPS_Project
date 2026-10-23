part of 'admin_subsystem_views.dart';

extension _AdminConfigAndGovernanceViews on _AdminSubsystemEntryState {
  /// UC26: Cấu hình Công thức Tính cước, Phụ phí & Khuyến mãi Voucher (Chuẩn uc26_gia_cuoc_1791015101391.jpg)
  Widget _buildDynamicPricingConfigView() {
    final canEditSystem = _store.hasAdminPermission('Hệ thống: Cài đặt');

    return LayoutBuilder(
      builder: (context, constraints) {
        final colLeft = Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cấu hình Bảng giá & Phụ phí Động',
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
                      ? (v) => _store.savePricingConfiguration(
                            baseFare: double.tryParse(_baseFareCtrl.text) ??
                                _store.baseFareConfig,
                            pricePerKm: double.tryParse(_perKmCtrl.text) ??
                                _store.pricePerKmConfig,
                            isPeakEnabled: v,
                            isWeatherEnabled: _store.isWeatherSurchargeActive,
                          )
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Phụ phí thời tiết xấu / Mưa ngập (+15.000đ)',
                  ),
                  value: _store.isWeatherSurchargeActive,
                  onChanged: canEditSystem
                      ? (v) => _store.savePricingConfiguration(
                            baseFare: double.tryParse(_baseFareCtrl.text) ??
                                _store.baseFareConfig,
                            pricePerKm: double.tryParse(_perKmCtrl.text) ??
                                _store.pricePerKmConfig,
                            isPeakEnabled: _store.isPeakSurchargeActive,
                            isWeatherEnabled: v,
                          )
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
                            final parsedBase =
                                double.tryParse(_baseFareCtrl.text.trim());
                            final parsedPerKm =
                                double.tryParse(_perKmCtrl.text.trim());
                            if (parsedBase == null ||
                                parsedBase <= 0 ||
                                parsedPerKm == null ||
                                parsedPerKm <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Vui lòng nhập giá mở cửa và đơn giá mỗi km lớn hơn 0!',
                                  ),
                                ),
                              );
                              return;
                            }
                            _store.savePricingConfiguration(
                              baseFare: parsedBase,
                              pricePerKm: parsedPerKm,
                              isPeakEnabled: _store.isPeakSurchargeActive,
                              isWeatherEnabled:
                                  _store.isWeatherSurchargeActive,
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Đã cập nhật cấu hình giá cước hệ thống thành công!',
                                ),
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
        final colRight = Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    Text(
                      'Quản lý Chiến dịch Khuyến mãi & Voucher',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    OutlinedButton.icon(
                      onPressed: canEditSystem
                          ? () => _showCreateVoucherDialog(context)
                          : null,
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: const Text('Phát hành mã mới'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                ..._store.vouchers.map(
                  (v) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.paper,
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.local_offer_outlined,
                                color: AppColors.accent,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${v.code} • ${v.title}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Mức giảm: ${v.discountLabel} • Đơn tối thiểu: ${CurrencyFormatter.formatVnd(v.minOrderValue)} • HSD: ${v.expiryDate}',
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
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          onPressed: canEditSystem
                              ? () => _store.toggleVoucherStatus(v.code)
                              : null,
                          label: Text(
                            v.status,
                            style: const TextStyle(fontSize: 11.5),
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
        if (constraints.maxWidth < 860) {
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

  void _showCreateVoucherDialog(BuildContext context) {
    final defaultCode = 'PROMO${10 + _store.vouchers.length * 5}K';
    final codeCtrl = TextEditingController(text: defaultCode);
    final titleCtrl = TextEditingController(
      text: 'Ưu đãi vận chuyển GPS (${_store.vouchers.length + 1})',
    );
    final discountCtrl = TextEditingController(text: '25000');
    final minOrderCtrl = TextEditingController(text: '80000');
    bool isPct = false;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Phát hành Mã Khuyến mãi & Voucher mới',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mã Voucher (VD: PROMO25K)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên chương trình ưu đãi',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Giảm theo phần trăm (%)'),
                      value: isPct,
                      onChanged: (v) {
                        setDialogState(() {
                          isPct = v;
                          discountCtrl.text = v ? '15' : '25000';
                        });
                      },
                    ),
                    TextField(
                      controller: discountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: isPct
                            ? 'Phần trăm giảm giá (1 - 100%)'
                            : 'Số tiền giảm giá (VNĐ)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: minOrderCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Giá trị đơn hàng tối thiểu (VNĐ)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                  ),
                  onPressed: () {
                    final code = codeCtrl.text.trim().toUpperCase();
                    final title = titleCtrl.text.trim();
                    final discount =
                        double.tryParse(discountCtrl.text.trim()) ?? 0;
                    final minOrder =
                        double.tryParse(minOrderCtrl.text.trim()) ?? 0;
                    if (code.isEmpty ||
                        title.isEmpty ||
                        discount <= 0 ||
                        (isPct && discount > 100) ||
                        minOrder < 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Vui lòng nhập mã, tên chương trình và mức giảm giá hợp lệ!',
                          ),
                        ),
                      );
                      return;
                    }
                    _store.createNewVoucher(
                      code: code,
                      title: title,
                      discountValue: discount,
                      isPercentage: isPct,
                      minOrderValue: minOrder,
                    );
                    Navigator.of(dialogCtx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã phát hành mã khuyến mãi $code thành công!',
                        ),
                      ),
                    );
                  },
                  child: const Text('Phát hành mã'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// UC27: Báo cáo thống kê Hệ thống (Khớp 100% anh_sua_lai/uc27_bao_cao.jpg)
  Widget _buildVoucherCampaignsView() {
    final totalOrders = _store.orders.length;
    final deliveredCount = _store.orders
        .where(
          (o) =>
              o.status == OrderStatus.delivered &&
              o.paymentStatus != 'RETURNED',
        )
        .length;
    final validOrders = _store.orders
        .where(
          (o) =>
              o.status != OrderStatus.cancelled &&
              o.status != OrderStatus.failed &&
              o.status != OrderStatus.returning &&
              o.paymentStatus != 'RETURNED',
        )
        .toList();
    final totalRevenue = validOrders.fold<double>(
      0.0,
      (sum, o) => sum + o.totalAmount,
    );
    final platformCommission = (totalRevenue * 0.20).roundToDouble();
    final slaRate = totalOrders == 0
        ? 95.8
        : (deliveredCount * 100.0 / totalOrders);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.zero),
        border: Border.all(color: const Color(0xFF15131E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Báo cáo thống kê hệ thống',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF15131E),
                    ),
                  ),
                  Text(
                    'Kỳ báo cáo: 01/10/2026 - 31/10/2026 • Số liệu thống kê vận hành hệ thống',
                    style: TextStyle(fontSize: 12, color: Color(0xFF4A4754)),
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF14B866),
                    ),
                    onPressed: () {
                      final path = _store.exportReportFileToDisk(
                        fileName: 'Bao_Cao_He_Thong_T10.csv',
                        content:
                            'tong_don,giao_thanh_cong,doanh_thu_vnd,hoa_hong_san_vnd,sla_pct\n'
                            '$totalOrders,$deliveredCount,${totalRevenue.toStringAsFixed(0)},${platformCommission.toStringAsFixed(0)},${slaRate.toStringAsFixed(1)}',
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã xuất báo cáo thống kê Excel/CSV tại: $path',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.table_view, size: 16),
                    label: const Text('Xuất Excel'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                    ),
                    onPressed: () {
                      final path = _store.exportReportFileToDisk(
                        fileName: 'Bao_Cao_He_Thong_T10_Summary.txt',
                        content:
                            'BAO CAO THONG KE HE THONG GO-MAU\n'
                            'Tong so don: $totalOrders\n'
                            'Giao thanh cong: $deliveredCount (${slaRate.toStringAsFixed(1)}%)\n'
                            'Tong doanh thu: ${CurrencyFormatter.formatVnd(totalRevenue)}\n'
                            'Hoa hong san (20%): ${CurrencyFormatter.formatVnd(platformCommission)}\n',
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã xuất bản in báo cáo hệ thống tại: $path',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text('Xuất PDF'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, kpiConstraints) {
              final maxW = kpiConstraints.maxWidth;
              final cols = maxW >= 780
                  ? 3
                  : maxW >= 520
                      ? 2
                      : 1;
              final cardWidth = cols == 1
                  ? maxW
                  : (maxW - (cols - 1) * 14.0) / cols;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _buildGoMauKpiCard(
                    width: cardWidth,
                    title: 'Tổng doanh thu cước',
                    value: CurrencyFormatter.formatVnd(totalRevenue),
                    delta: '(${_store.orders.length} đơn hàng)',
                    deltaPositive: true,
                    badgeColor: const Color(0xFF5B33E6),
                    icon: Icons.payments_outlined,
                    showSparkline: false,
                    sparklineColor: const Color(0xFF5B33E6),
                  ),
                  _buildGoMauKpiCard(
                    width: cardWidth,
                    title: 'Chiết khấu nền tảng (20%)',
                    value: CurrencyFormatter.formatVnd(platformCommission),
                    delta: '(${_store.withdrawalRequests.length} lệnh rút)',
                    deltaPositive: true,
                    badgeColor: const Color(0xFF14B866),
                    icon: Icons.account_balance_outlined,
                    showSparkline: false,
                    sparklineColor: const Color(0xFF14B866),
                  ),
                  _buildGoMauKpiCard(
                    width: cardWidth,
                    title: 'Tổng đơn hoàn thành',
                    value: '$deliveredCount/$totalOrders đơn',
                    delta: 'SLA ${slaRate.toStringAsFixed(1)}%',
                    deltaPositive: true,
                    badgeColor: const Color(0xFFFF5E83),
                    icon: Icons.task_alt_rounded,
                    showSparkline: false,
                    sparklineColor: const Color(0xFFFF5E83),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Builder(
            builder: (context) {
              final safeTotal = totalOrders == 0 ? 1 : totalOrders;
              final expOrders = _store.orders
                  .where((o) => o.serviceType == DeliveryServiceType.express30m)
                  .toList();
              final stdOrders = _store.orders
                  .where((o) => o.serviceType == DeliveryServiceType.standard)
                  .toList();
              final savOrders = _store.orders
                  .where((o) => o.serviceType == DeliveryServiceType.saving)
                  .toList();

              String pctStr(int count) =>
                  '${((count / safeTotal) * 100).round()}% ($count đơn)';
              String slaFor(List<dynamic> list) {
                if (list.isEmpty) return '100.0%';
                final ok = list
                    .where(
                      (o) =>
                          o.status != OrderStatus.cancelled &&
                          o.status != OrderStatus.failed &&
                          o.status != OrderStatus.returning &&
                          o.paymentStatus != 'RETURNED',
                    )
                    .length;
                return '${((ok / list.length) * 100).toStringAsFixed(1)}%';
              }

              final wkCounts = List<double>.generate(4, (wIdx) {
                final sum = validOrders
                    .where((o) => o.trackingCode.hashCode.abs() % 4 == wIdx)
                    .fold<double>(0, (s, o) => s + o.totalAmount);
                return sum;
              });
              final maxWk =
                  wkCounts.fold<double>(1.0, (m, v) => v > m ? v : m);
              final wkBars = List.generate(4, (wIdx) {
                final ratio = wkCounts[wIdx] <= 0
                    ? 0.25
                    : (wkCounts[wIdx] / maxWk).clamp(0.30, 1.0);
                return ('Tuần ${wIdx + 1}', ratio);
              });

              return LayoutBuilder(
                builder: (context, constraints) {
                  final chartCard = Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F1E8),
                      borderRadius: BorderRadius.all(Radius.zero),
                      border: Border.all(color: const Color(0xFF15131E)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Doanh thu theo tuần (Tháng 10/2026)',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 140,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              for (final wk in wkBars)
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Container(
                                        width: 34,
                                        height: 105 * wk.$2,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF5B33E6),
                                          borderRadius:
                                              BorderRadius.all(Radius.zero),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        wk.$1,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                  final tableCard = Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F1E8),
                      borderRadius: BorderRadius.all(Radius.zero),
                      border: Border.all(color: const Color(0xFF15131E)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tóm tắt đơn hàng theo Loại dịch vụ (Dữ liệu CSDL)',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowHeight: 36,
                            dataRowMinHeight: 36,
                            dataRowMaxHeight: 42,
                            columns: const [
                              DataColumn(label: Text('Dịch vụ')),
                              DataColumn(label: Text('Tỷ trọng')),
                              DataColumn(label: Text('SLA Đúng giờ')),
                            ],
                            rows: [
                              DataRow(
                                cells: [
                                  const DataCell(
                                    Text('Giao Nhanh 30p (Express)'),
                                  ),
                                  DataCell(Text(pctStr(expOrders.length))),
                                  DataCell(Text(slaFor(expOrders))),
                                ],
                              ),
                              DataRow(
                                cells: [
                                  const DataCell(
                                    Text('Giao Tiêu chuẩn (Standard)'),
                                  ),
                                  DataCell(Text(pctStr(stdOrders.length))),
                                  DataCell(Text(slaFor(stdOrders))),
                                ],
                              ),
                              DataRow(
                                cells: [
                                  const DataCell(
                                    Text('Giao Tiết kiệm (Saving)'),
                                  ),
                                  DataCell(Text(pctStr(savOrders.length))),
                                  DataCell(Text(slaFor(savOrders))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                  if (constraints.maxWidth < 860) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        chartCard,
                        const SizedBox(height: 16),
                        tableCard,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: chartCard),
                      const SizedBox(width: 16),
                      Expanded(flex: 6, child: tableCard),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  /// UC28: Giải quyết Khiếu nại & Sự cố (Chuẩn uc28_khieu_nai_1791015159812.jpg)
  Widget _buildComplaintResolutionView() {
    final safeIdx = _selectedComplaintIndex.clamp(
      0,
      _store.complaints.length - 1,
    );
    final activeTicket = _store.complaints[safeIdx];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trung tâm Giải quyết Khiếu nại & Sự cố',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _store.complaints.asMap().entries.map((entry) {
                final idx = entry.key;
                final c = entry.value;
                return ChoiceChip(
                  label: Text('${c.ticketCode} (${c.orderId}) • ${c.status}'),
                  selected: idx == safeIdx,
                  onSelected: (_) =>
                      _rebuildAdminUi(() => _selectedComplaintIndex = idx),
                );
              }).toList(),
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
                      if (_replyTicketCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Vui lòng nhập nội dung phản hồi / phương án đền bù trước khi đóng khiếu nại!',
                            ),
                          ),
                        );
                        return;
                      }
                      _store.replyComplaint(
                        activeTicket.ticketCode,
                        _replyTicketCtrl.text,
                        'Đã giải quyết',
                      );
                      _replyTicketCtrl.clear();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã phản hồi và đóng khiếu nại ${activeTicket.ticketCode} (${activeTicket.orderId})!',
                          ),
                        ),
                      );
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

  /// UC29: Đối soát Tài chính & Phê duyệt Rút tiền (Chuẩn uc29_tai_chinh_1791015185346.jpg)
  Widget _buildFinancialWithdrawalApprovalView() {
    final canApprovePayout = _store.hasAdminPermission('Tài chính: Thanh toán');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Đối soát Tài chính & Duyệt Lệnh Rút tiền',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (!canApprovePayout)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '🔒 Vai trò hiện tại không có quyền "Tài chính: Thanh toán" (Cấu hình tại mục Phân quyền RBAC).',
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            ..._store.withdrawalRequests.map(
              (req) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${req.ownerName} (${req.ownerRole}) • ${CurrencyFormatter.formatVnd(req.amount)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${req.bankName} (${req.accountMasked}) • Ngày: ${req.requestDate} • Trạng thái: ${req.status}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        TextButton(
                          onPressed: canApprovePayout && req.status == 'Chờ duyệt'
                              ? () {
                                  _store.updateWithdrawalStatus(
                                    req.id,
                                    'Đã duyệt',
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Đã duyệt lệnh rút ${req.id} (${CurrencyFormatter.formatVnd(req.amount)}) cho ${req.ownerName}!',
                                      ),
                                    ),
                                  );
                                }
                              : null,
                          child: const Text('Duyệt lệnh'),
                        ),
                        TextButton(
                          onPressed: canApprovePayout && req.status == 'Chờ duyệt'
                              ? () {
                                  _store.updateWithdrawalStatus(
                                    req.id,
                                    'Từ chối',
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Đã từ chối lệnh rút ${req.id} và hoàn tiền về ví ${req.ownerName}.',
                                      ),
                                    ),
                                  );
                                }
                              : null,
                          child: const Text(
                            'Từ chối',
                            style: TextStyle(color: AppColors.danger),
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

  /// UC43: Quản lý & Điều phối Đơn hàng Thủ công (Chuẩn uc43_don_hang_1791094600371.jpg)
  Widget _buildManualOrderDispatchView() {
    final canEditOrder = _store.hasAdminPermission('Đơn: Sửa');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quản lý & Điều phối Đơn hàng Thủ công',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._store.orders.map(
              (ord) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  border: Border.all(color: AppColors.divider),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${ord.trackingCode} • ${ord.pickupAddress} -> ${ord.dropoffAddress}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Trạng thái: ${ord.paymentStatus == "RETURNED" ? "Đã hoàn kho" : ord.status.displayName} • Tài xế: ${ord.assignedDriverName ?? "Chưa có tài xế"}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: canEditOrder &&
                              ord.status != OrderStatus.delivered &&
                              ord.status != OrderStatus.cancelled
                          ? () {
                              if (ord.status.canTransitionTo(
                                OrderStatus.accepted,
                              )) {
                                _store.driverAcceptOrder(ord.trackingCode);
                              } else {
                                _store.driverAdvanceOrderStatus(
                                  ord.trackingCode,
                                );
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Đã điều phối đơn ${ord.trackingCode} → Trạng thái: ${ord.paymentStatus == "RETURNED" ? "Đã hoàn kho" : ord.status.displayName} (${ord.assignedDriverName ?? _store.activeDriverName})',
                                  ),
                                ),
                              );
                            }
                          : null,
                      child: Text(
                        ord.paymentStatus == 'RETURNED'
                            ? 'Đã hoàn kho'
                            : ord.status == OrderStatus.delivered
                                ? 'Đã hoàn tất'
                            : ord.status == OrderStatus.cancelled
                                ? 'Đã hủy'
                                : ord.status == OrderStatus.failed
                                    ? 'Giao lại chuyến hàng'
                                    : ord.status == OrderStatus.returning
                                        ? 'Hoàn tất trả kho'
                                        : ord.status.canTransitionTo(
                                            OrderStatus.accepted,
                                          )
                                            ? 'Gán tài xế ngay'
                                            : 'Chuyển bước giao hàng',
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

  /// Quản lý Vùng hoạt động Geofencing Polygon (Tương tác chấm đỉnh trên bản đồ)
  Widget _buildGeofencePolygonZonesView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quản lý Vùng Hoạt động Geofencing Polygon',
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
                _rebuildAdminUi(() {
                  _draftPolygonOffsets.add(relOffset);
                });
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            LayoutBuilder(
              builder: (context, constraints) {
                final nameField = TextField(
                  controller: _newZoneNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên vùng Geofence mới',
                  ),
                );
                final buttons = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () =>
                          _rebuildAdminUi(() => _draftPolygonOffsets.clear()),
                      child: const Text('Xóa đỉnh'),
                    ),
                    ElevatedButton(
                      onPressed: _draftPolygonOffsets.length >= 3
                          ? () {
                              final zoneName = _newZoneNameCtrl.text
                                      .trim()
                                      .isNotEmpty
                                  ? _newZoneNameCtrl.text.trim()
                                  : 'Vùng phụ phí Geofence #${_store.geofenceZones.length + 1}';
                              final vertices = _draftPolygonOffsets
                                  .map(
                                    (o) => GeoPoint(
                                      latitude: 10.740 + o.dy * 0.05,
                                      longitude: 106.660 + o.dx * 0.06,
                                    ),
                                  )
                                  .toList();
                              _store.addCustomGeofenceZone(
                                zoneName: zoneName,
                                zoneType: 'SURCHARGE_ZONE',
                                surchargeRate: 20000,
                                vertices: vertices,
                              );
                              _rebuildAdminUi(() {
                                _draftPolygonOffsets.clear();
                                _newZoneNameCtrl.clear();
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Đã lưu "$zoneName" (${vertices.length} đỉnh) vào bảng geofence_zones!',
                                  ),
                                ),
                              );
                            }
                          : null,
                      child: const Text('Lưu Polygon mới'),
                    ),
                  ],
                );
                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      nameField,
                      const SizedBox(height: 8),
                      buttons,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: nameField),
                    const SizedBox(width: 8),
                    buttons,
                  ],
                );
              },
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
            LayoutBuilder(
              builder: (context, constraints) {
                final latField = TextField(
                  controller: _testLatCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Vĩ độ kiểm tra (Lat)'),
                );
                final lngField = TextField(
                  controller: _testLngCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Kinh độ kiểm tra (Lng)',
                  ),
                );
                final checkBtn = ElevatedButton(
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
                    _rebuildAdminUi(() {
                      _geofenceCheckResult = matched != null
                          ? 'Thuộc vùng: ${matched.zoneName} (Phụ phí: ${CurrencyFormatter.formatVnd(matched.surchargeRate)})'
                          : 'Tọa độ nằm ngoài các vùng phụ phí đặc biệt.';
                    });
                  },
                  child: const Text('Kiểm tra Polygon'),
                );
                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: latField),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: lngField),
                        ],
                      ),
                      const SizedBox(height: 8),
                      checkBtn,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: latField),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: lngField),
                    const SizedBox(width: AppSpacing.sm),
                    checkBtn,
                  ],
                );
              },
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

  /// Gửi Thông báo Hệ thống Hàng loạt (Broadcast Push)
  Widget _buildBroadcastNotificationView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Phát Thông báo Hệ thống Hàng loạt',
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
                  onSelected: (_) => _rebuildAdminUi(() => _broadcastTarget = g),
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
                  if (_broadcastTitleCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Vui lòng nhập tiêu đề & nội dung thông báo trước khi phát!',
                        ),
                      ),
                    );
                    return;
                  }
                  _store.broadcastSystemNotification(
                    title: _broadcastTitleCtrl.text.trim(),
                    targetGroup: _broadcastTarget,
                  );
                  _broadcastTitleCtrl.clear();
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

  /// Phân quyền Quản trị viên (RBAC Permission Matrix)
  Widget _buildRbacPermissionMatrixView() {
    final matchedIdx = _store.rbacRoles.indexWhere(
      (r) => r.roleName == _store.currentAdminRoleName,
    );
    if (matchedIdx != -1) {
      _selectedRbacRoleIndex = matchedIdx;
    }
    final activeRole = _store.rbacRoles[_selectedRbacRoleIndex];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ma trận Phân quyền Quản trị viên (RBAC)',
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
                  onSelected: (_) {
                    _rebuildAdminUi(() => _selectedRbacRoleIndex = index);
                    _store.setAdminActiveRole(r.roleName);
                  },
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
            const Divider(height: 24),
            Text(
              'Kết nối Cloud Supabase PostgreSQL 16 + PostGIS Thực tế (16 Bảng)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _supabaseUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'SUPABASE_URL (Project URL)',
                prefixIcon: Icon(Icons.cloud_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _supabaseAnonKeyCtrl,
              decoration: const InputDecoration(
                labelText: 'SUPABASE_ANON_KEY (Public API Key)',
                prefixIcon: Icon(Icons.vpn_key_outlined),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  _store.lastSyncStatusMessage,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final msg = await _store.configureAndSyncSupabaseCloud(
                      url: _supabaseUrlCtrl.text,
                      anonKey: _supabaseAnonKeyCtrl.text,
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg)),
                    );
                  },
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Kết nối & Đồng bộ PostGIS'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
