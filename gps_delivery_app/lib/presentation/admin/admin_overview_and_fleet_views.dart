part of 'admin_subsystem_views.dart';

extension _AdminOverviewAndFleetViews on _AdminSubsystemEntryState {
  /// UC22: Dashboard Tổng quan Hệ thống (Khớp 100% uc22_dashboard_1791014957650.jpg)
  Widget _buildSystemOverviewDashboard() {
    final totalOrders = _store.orders.length;
    final totalRevenue = _store.orders
        .where(
          (o) =>
              o.status != OrderStatus.cancelled &&
              o.status != OrderStatus.failed &&
              o.status != OrderStatus.returning &&
              o.paymentStatus != 'RETURNED',
        )
        .fold<double>(0.0, (sum, o) => sum + o.totalAmount);
    final onlineDriversCount =
        _store.drivers.where((d) => d.isOnline).length;
    final activeDeliveriesCount = _store.orders
        .where(
          (o) =>
              o.status == OrderStatus.inTransit ||
              o.status == OrderStatus.accepted ||
              o.status == OrderStatus.arrivingPickup ||
              o.status == OrderStatus.searching,
        )
        .length;

    final safeTotal = totalOrders > 0 ? totalOrders : 1;
    final deliveredCount = _store.orders
        .where(
          (o) =>
              o.status == OrderStatus.delivered &&
              o.paymentStatus != 'RETURNED',
        )
        .length;
    final inTransitCount = _store.orders
        .where(
          (o) =>
              o.status == OrderStatus.inTransit ||
              o.status == OrderStatus.accepted ||
              o.status == OrderStatus.arrivingPickup,
        )
        .length;
    final cancelledCount = _store.orders
        .where(
          (o) =>
              o.status == OrderStatus.cancelled ||
              o.paymentStatus == 'RETURNED',
        )
        .length;
    final otherCount =
        (totalOrders - deliveredCount - inTransitCount - cancelledCount)
            .clamp(0, totalOrders);

    final deliveredPct = ((deliveredCount / safeTotal) * 100).round();
    final inTransitPct = ((inTransitCount / safeTotal) * 100).round();
    final cancelledPct = ((cancelledCount / safeTotal) * 100).round();
    final otherPct =
        (100 - deliveredPct - inTransitPct - cancelledPct).clamp(0, 100);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tổng quan hệ thống',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF15131E),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Dashboard Tổng quan Hệ thống • ${_store.lastSyncStatusMessage}',
          style: const TextStyle(
            fontSize: 12.5,
            color: Color(0xFF4A4754),
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, kpiConstraints) {
            final maxW = kpiConstraints.maxWidth;
            final cols = maxW >= 960
                ? 4
                : maxW >= 540
                    ? 2
                    : 1;
            final cardWidth = cols == 1
                ? maxW
                : (maxW - (cols - 1) * 16.0) / cols;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildGoMauKpiCard(
                  width: cardWidth,
                  title: 'Tổng đơn hàng',
                  value: '$totalOrders',
                  delta: '(${_store.users.length} users)',
                  deltaPositive: true,
                  badgeColor: const Color(0xFF5B33E6),
                  icon: Icons.shopping_cart_rounded,
                  showSparkline: true,
                  sparklineColor: const Color(0xFF5B33E6),
                ),
                _buildGoMauKpiCard(
                  width: cardWidth,
                  title: 'Doanh thu',
                  value: CurrencyFormatter.formatVnd(totalRevenue),
                  delta: '(${_store.orders.where((o) => o.paymentStatus == "PAID").length} đã TT)',
                  deltaPositive: true,
                  badgeColor: const Color(0xFFFF5E83),
                  icon: Icons.monetization_on_rounded,
                  showSparkline: true,
                  sparklineColor: const Color(0xFFFF5E83),
                ),
                _buildGoMauKpiCard(
                  width: cardWidth,
                  title: 'Tài xế online',
                  value: '$onlineDriversCount/${_store.drivers.length}',
                  delta: '(Trực tuyến)',
                  deltaPositive: onlineDriversCount > 0,
                  badgeColor: const Color(0xFF14B866),
                  icon: Icons.sensors_rounded,
                  showSparkline: false,
                  sparklineColor: const Color(0xFF14B866),
                ),
                _buildGoMauKpiCard(
                  width: cardWidth,
                  title: 'Đơn đang giao',
                  value: '$activeDeliveriesCount',
                  delta: '(Hoạt động)',
                  deltaPositive: true,
                  badgeColor: const Color(0xFFEAB308),
                  icon: Icons.local_shipping_rounded,
                  showSparkline: false,
                  sparklineColor: const Color(0xFFEAB308),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, rowConstraints) {
            final isDesktopRow = rowConstraints.maxWidth >= 820;
            final revenueChartCard = Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: const Color(0xFF15131E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Biểu đồ Doanh thu (7 ngày gần nhất)',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Color(0xFF15131E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tổng cước thực tế trong CSDL: ${CurrencyFormatter.formatVnd(totalRevenue)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF4A4754),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 190,
                    width: double.infinity,
                    child: Builder(
                      builder: (_) {
                        final revShift =
                            ((totalRevenue / 500000.0) - 0.5).clamp(-0.20, 0.20);
                        final baseBlue = [
                          0.85,
                          0.34,
                          0.52,
                          0.10,
                          0.35,
                          0.48,
                          0.06,
                        ];
                        final baseOrange = [
                          0.80,
                          0.52,
                          0.60,
                          0.28,
                          0.62,
                          0.66,
                          0.30,
                        ];
                        return CustomPaint(
                          painter: _GoMauRevenueLineChartPainter(
                            blueNorm: baseBlue
                                .map((y) => (y - revShift).clamp(0.06, 0.92))
                                .toList(),
                            orangeNorm: baseOrange
                                .map(
                                  (y) =>
                                      (y - revShift * 0.65).clamp(0.10, 0.94),
                                )
                                .toList(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(child: Text('T2', style: TextStyle(fontSize: 9.5))),
                      Flexible(child: Text('T3', style: TextStyle(fontSize: 9.5))),
                      Flexible(child: Text('T4', style: TextStyle(fontSize: 9.5))),
                      Flexible(child: Text('T5', style: TextStyle(fontSize: 9.5))),
                      Flexible(child: Text('T6', style: TextStyle(fontSize: 9.5))),
                      Flexible(child: Text('T7', style: TextStyle(fontSize: 9.5))),
                      Flexible(child: Text('CN', style: TextStyle(fontSize: 9.5))),
                    ],
                  ),
                ],
              ),
            );

            final statusDonutCard = Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: const Color(0xFF15131E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Trạng thái Đơn hàng',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Color(0xFF15131E),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: SizedBox(
                      width: 136,
                      height: 136,
                      child: CustomPaint(
                        painter: _GoMauOrderDonutPainter(
                          deliveredRatio: deliveredPct / 100.0,
                          inTransitRatio: inTransitPct / 100.0,
                          cancelledRatio: cancelledPct / 100.0,
                          otherRatio: otherPct / 100.0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildDonutLegendRow(
                    const Color(0xFF5B33E6),
                    'Giao thành công: $deliveredPct% ($deliveredCount đơn)',
                  ),
                  const SizedBox(height: 5),
                  _buildDonutLegendRow(
                    const Color(0xFFFF5E83),
                    'Đang giao: $inTransitPct% ($inTransitCount đơn)',
                  ),
                  const SizedBox(height: 5),
                  _buildDonutLegendRow(
                    const Color(0xFFDC2626),
                    'Đã hủy: $cancelledPct% ($cancelledCount đơn)',
                  ),
                  const SizedBox(height: 5),
                  _buildDonutLegendRow(
                    const Color(0xFF94A3B8),
                    'Đang tìm xe / Khác: $otherPct% ($otherCount đơn)',
                  ),
                ],
              ),
            );

            final newestOrdersCard = Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: const Color(0xFF15131E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Đơn hàng mới nhất (${_store.orders.length} bản ghi CSDL)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Color(0xFF15131E),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Mã Đơn',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                            color: Color(0xFF4A4754),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Khách hàng',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                            color: Color(0xFF4A4754),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Tài xế',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                            color: Color(0xFF4A4754),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Giá trị',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                            color: Color(0xFF4A4754),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Trạng thái',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                            color: Color(0xFF4A4754),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  ..._store.orders.take(6).map((o) {
                    final isReturned = o.paymentStatus == 'RETURNED';
                    final isDone =
                        o.status == OrderStatus.delivered && !isReturned;
                    final isCancelled = o.status == OrderStatus.cancelled ||
                        o.status == OrderStatus.failed ||
                        o.status == OrderStatus.returning ||
                        isReturned;
                    return _buildNewestOrderRow(
                      code: o.trackingCode,
                      customer: o.customerName,
                      driver: o.assignedDriverName ?? 'Đang tìm tài xế',
                      amount: CurrencyFormatter.formatVnd(o.totalAmount),
                      statusLabel:
                          isReturned ? 'Đã hoàn kho' : o.status.displayName,
                      pillBg: isDone
                          ? const Color(0xFFDCFCE7)
                          : isCancelled
                              ? const Color(0xFFFEE2E2)
                              : const Color(0xFFE9E9E4),
                      pillFg: isDone
                          ? const Color(0xFF14B866)
                          : isCancelled
                              ? const Color(0xFFB91C1C)
                              : const Color(0xFF5B33E6),
                    );
                  }),
                ],
              ),
            );

            if (isDesktopRow) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: revenueChartCard),
                  const SizedBox(width: 16),
                  Expanded(flex: 3, child: statusDonutCard),
                  const SizedBox(width: 16),
                  Expanded(flex: 5, child: newestOrdersCard),
                ],
              );
            }
            return Column(
              children: [
                revenueChartCard,
                const SizedBox(height: 16),
                statusDonutCard,
                const SizedBox(height: 16),
                newestOrdersCard,
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildGoMauKpiCard({
    double? width,
    required String title,
    required String value,
    required String delta,
    required bool deltaPositive,
    required Color badgeColor,
    required IconData icon,
    required bool showSparkline,
    required Color sparklineColor,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.zero),
        border: Border.all(color: const Color(0xFF15131E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.all(Radius.zero),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF4A4754),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: [
                        Text(
                          value,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF15131E),
                          ),
                        ),
                        Text(
                          delta,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: deltaPositive
                                ? const Color(0xFF14B866)
                                : const Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showSparkline) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 28,
              width: double.infinity,
              child: CustomPaint(
                painter: _MiniSparklinePainter(color: sparklineColor),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDonutLegendRow(Color dotColor, String text) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNewestOrderRow({
    required String code,
    required String customer,
    required String driver,
    required String amount,
    required String statusLabel,
    required Color pillBg,
    required Color pillFg,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              customer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              driver,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              amount,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: pillBg,
                borderRadius: BorderRadius.all(Radius.zero),
              ),
              child: Text(
                statusLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: pillFg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  /// UC23: Quản lý Người dùng & Cửa hàng (Chuẩn uc23_nguoi_dung_1791015002658.jpg)
  Widget _buildUserAndMerchantManagementView() {
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
            runSpacing: 8,
            children: [
              Text(
                'Quản lý Tài khoản Người dùng & Đối tác (${_store.users.length} tài khoản)',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Color(0xFF15131E),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B33E6),
                ),
                onPressed: () => _showCreateUserAccountDialog(context),
                icon: const Icon(Icons.person_add_alt_1, size: 16),
                label: const Text('+ Thêm tài khoản'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ('ALL', 'Tất cả vai trò'),
              ('CUSTOMER', 'Khách hàng (CUSTOMER)'),
              ('DRIVER', 'Tài xế (DRIVER)'),
              ('MERCHANT', 'Cửa hàng (MERCHANT)'),
              ('ADMIN', 'Quản trị (ADMIN)'),
            ].map((item) {
              return ChoiceChip(
                label: Text(item.$2),
                selected: _userRoleFilter == item.$1,
                onSelected: (_) => _rebuildAdminUi(() => _userRoleFilter = item.$1),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                const Color(0xFFF5F1E8),
              ),
              columns: const [
                DataColumn(label: Text('ID')),
                DataColumn(label: Text('Họ và tên')),
                DataColumn(label: Text('Số điện thoại')),
                DataColumn(label: Text('Email')),
                DataColumn(label: Text('Vai trò')),
                DataColumn(label: Text('Trạng thái')),
              ],
              rows: _store.users
                  .where(
                    (u) =>
                        _userRoleFilter == 'ALL' ||
                        u.roleDbCode == _userRoleFilter,
                  )
                  .map((u) {
                return DataRow(
                  cells: [
                    DataCell(Text(u.id)),
                    DataCell(
                      Text(
                        u.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DataCell(Text(u.phone)),
                    DataCell(
                      Text(u.email.isEmpty ? 'Chưa cập nhật' : u.email),
                    ),
                    DataCell(
                      Chip(
                        label: Text(
                          u.roleDbCode,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ActionChip(
                        onPressed: () => _store.toggleUserAccountStatus(u.id),
                        backgroundColor: u.status == 'ACTIVE'
                            ? AppColors.success.withValues(alpha: 0.14)
                            : AppColors.danger.withValues(alpha: 0.14),
                        label: Text(
                          u.status == 'ACTIVE' ? 'Hoạt động' : 'Đã khóa',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: u.status == 'ACTIVE'
                                ? AppColors.success
                                : AppColors.danger,
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

  void _showCreateUserAccountDialog(BuildContext context) {
    final nextIdx = _store.users.length + 1;
    final nameCtrl =
        TextEditingController(text: 'Tài khoản Đối tác #$nextIdx');
    final phoneCtrl = TextEditingController(text: '09080010$nextIdx');
    final emailCtrl =
        TextEditingController(text: 'user$nextIdx@giaohanggps.vn');
    final pwdCtrl = TextEditingController(text: '12345678');
    SubsystemRole selectedRole = SubsystemRole.customer;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Thêm tài khoản Người dùng / Đối tác',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Họ và tên / Tên đơn vị',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Số điện thoại (9-11 chữ số)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email liên hệ',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: pwdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mật khẩu khởi tạo',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<SubsystemRole>(
                      initialValue: selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Phân quyền vai trò (Role)',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: SubsystemRole.customer,
                          child: Text('Khách hàng (CUSTOMER)'),
                        ),
                        DropdownMenuItem(
                          value: SubsystemRole.driver,
                          child: Text('Tài xế (DRIVER)'),
                        ),
                        DropdownMenuItem(
                          value: SubsystemRole.merchant,
                          child: Text('Cửa hàng B2B (MERCHANT)'),
                        ),
                        DropdownMenuItem(
                          value: SubsystemRole.admin,
                          child: Text('Quản trị viên (ADMIN)'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => selectedRole = v);
                        }
                      },
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
                    backgroundColor: const Color(0xFF5B33E6),
                  ),
                  onPressed: () {
                    final created = _store.registerUserAccountWithRole(
                      phone: phoneCtrl.text.trim(),
                      fullName: nameCtrl.text.trim(),
                      password: pwdCtrl.text.trim(),
                      role: selectedRole,
                      email: emailCtrl.text.trim(),
                      activateSession: false,
                    );
                    if (created == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Vui lòng nhập Họ tên và Số điện thoại hợp lệ (tối thiểu 9 chữ số)!',
                          ),
                        ),
                      );
                      return;
                    }
                    Navigator.of(dialogCtx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã thêm tài khoản ${created.id} (${created.phone} • ${created.roleDbCode}) vào bảng users SQLite!',
                        ),
                      ),
                    );
                  },
                  child: const Text('Tạo tài khoản'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// UC24: Xét duyệt Hồ sơ Tài xế & Đối tác Cửa hàng B2B KYC
  Widget _buildDriverKycApprovalView() {
    final canApproveDriver = _store.hasAdminPermission('Tài xế: Phê duyệt');
    final safeDrvIdx = _store.drivers.isEmpty
        ? 0
        : _selectedKycDriverIndex.clamp(0, _store.drivers.length - 1);
    final featuredDriver = _store.drivers[safeDrvIdx];

    return LayoutBuilder(
      builder: (context, constraints) {
        final colLeft = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.zero),
            border: Border.all(color: const Color(0xFF15131E)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '1. Danh sách Hồ sơ Đăng ký Tài xế (Driver KYC)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                'Khi bấm "Duyệt hồ sơ", hệ thống tự động nâng cấp tài khoản Khách hàng tương ứng lên vai trò Tài xế (DRIVER) và mở khóa giao diện Tài xế.',
                style: TextStyle(fontSize: 12, color: Color(0xFF4A4754)),
              ),
              if (!canApproveDriver)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    '🔒 Vai trò hiện tại không có quyền "Tài xế: Phê duyệt" (Cấu hình tại mục Phân quyền RBAC).',
                    style: TextStyle(color: AppColors.danger, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),
              ..._store.drivers.asMap().entries.map((entry) {
                final idx = entry.key;
                final drv = entry.value;
                final isSelected = idx == safeDrvIdx;
                return InkWell(
                  onTap: () =>
                      _rebuildAdminUi(() => _selectedKycDriverIndex = idx),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFEDE9FE)
                          : const Color(0xFFF5F1E8),
                      borderRadius: BorderRadius.all(Radius.zero),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.violet
                            : const Color(0xFF15131E),
                        width: isSelected ? 1.8 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${drv.id} • ${drv.fullName} (${drv.phone})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'CCCD: ${drv.citizenId} • Xe: ${drv.vehicleType} (${drv.licensePlate}) • Trạng thái: ${drv.approvalStatus}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                              ),
                              onPressed: canApproveDriver &&
                                      drv.approvalStatus != 'Đã duyệt'
                                  ? () {
                                      _rebuildAdminUi(
                                        () => _selectedKycDriverIndex = idx,
                                      );
                                      _store.updateDriverApproval(
                                        drv.id,
                                        'Đã duyệt',
                                      );
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Đã duyệt hồ sơ tài xế ${drv.fullName} (${drv.id})!',
                                          ),
                                        ),
                                      );
                                    }
                                  : null,
                              child: Text(
                                drv.approvalStatus == 'Đã duyệt'
                                    ? 'Đã duyệt'
                                    : 'Duyệt hồ sơ',
                              ),
                            ),
                            OutlinedButton(
                              onPressed: canApproveDriver &&
                                      drv.approvalStatus != 'Từ chối'
                                  ? () {
                                      _rebuildAdminUi(
                                        () => _selectedKycDriverIndex = idx,
                                      );
                                      _store.updateDriverApproval(
                                        drv.id,
                                        'Từ chối',
                                      );
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Đã từ chối hồ sơ tài xế ${drv.fullName} (${drv.id}).',
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
                );
              }),
              const Divider(height: 24),
              const Text(
                '2. Danh sách Hồ sơ Đăng ký Cửa hàng B2B (Merchant KYC)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                'Khi bấm "Duyệt cửa hàng", hệ thống tự động nâng cấp tài khoản tương ứng lên vai trò Cửa hàng B2B (MERCHANT) và mở khóa Merchant Web Portal.',
                style: TextStyle(fontSize: 12, color: Color(0xFF4A4754)),
              ),
              const SizedBox(height: 12),
              ..._store.merchantApplicants.map(
                (mer) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F1E8),
                    borderRadius: BorderRadius.all(Radius.zero),
                    border: Border.all(color: const Color(0xFF15131E)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${mer.id} • ${mer.storeName} (${mer.ownerPhone})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'MST: ${mer.taxCode} • Loại hình: ${mer.businessType} • Đại diện: ${mer.representativeName}\nNgân hàng COD: ${mer.bankName} (${mer.bankAccount}) • Trạng thái: ${mer.approvalStatus}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                            ),
                            onPressed: canApproveDriver &&
                                    mer.approvalStatus != 'Đã duyệt'
                                ? () {
                                    _store.updateMerchantApproval(
                                      mer.id,
                                      'Đã duyệt',
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Đã duyệt cửa hàng ${mer.storeName} (${mer.id})!',
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                            child: Text(
                              mer.approvalStatus == 'Đã duyệt'
                                  ? 'Đã duyệt'
                                  : 'Duyệt cửa hàng',
                            ),
                          ),
                          OutlinedButton(
                            onPressed: canApproveDriver &&
                                    mer.approvalStatus != 'Từ chối'
                                ? () {
                                    _store.updateMerchantApproval(
                                      mer.id,
                                      'Từ chối',
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Đã từ chối hồ sơ cửa hàng ${mer.storeName} (${mer.id}).',
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
        );
        final colRight = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.zero),
            border: Border.all(color: const Color(0xFF15131E)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Chi tiết Hồ sơ Pháp lý: ${featuredDriver.fullName}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              Text('• Mã định danh: ${featuredDriver.id} (${featuredDriver.phone})'),
              Text('• Số CCCD gắn chip: ${featuredDriver.citizenId}'),
              Text(
                '• Phương tiện: ${featuredDriver.vehicleType} (${featuredDriver.licensePlate})',
              ),
              Text('• Trạng thái xét duyệt: ${featuredDriver.approvalStatus}'),
              const Divider(height: 20),
              const Text(
                'Tài liệu đính kèm đã tải lên:',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 8),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: Icon(Icons.badge_outlined, size: 16),
                    label: Text('CCCD Mặt trước & sau'),
                  ),
                  Chip(
                    avatar: Icon(Icons.credit_card, size: 16),
                    label: Text('Bằng lái xe A1/B2'),
                  ),
                  Chip(
                    avatar: Icon(Icons.two_wheeler, size: 16),
                    label: Text('Đăng ký xe (Cà vẹt)'),
                  ),
                ],
              ),
            ],
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
            Expanded(flex: 6, child: colLeft),
            const SizedBox(width: 16),
            Expanded(flex: 5, child: colRight),
          ],
        );
      },
    );
  }

  /// UC25: Bản đồ Giám sát Đội xe GPS Toàn Thành phố (Chuẩn uc25_giam_sat_gps)
  Widget _buildFleetLiveGpsMonitorView() {
    final totalDrivers = _store.drivers.length;
    final busyDriverNames = _store.orders
        .where(
          (o) =>
              o.status == OrderStatus.accepted ||
              o.status == OrderStatus.arrivingPickup ||
              o.status == OrderStatus.inTransit,
        )
        .map((o) => o.assignedDriverName)
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toSet();
    final onlineApprovedDrivers = _store.drivers
        .where((d) => d.isOnline && d.approvalStatus == 'Đã duyệt')
        .toList();
    final busyCount = busyDriverNames.length;
    final freeOnlineCount = onlineApprovedDrivers
        .where((d) => !busyDriverNames.contains(d.fullName))
        .length;
    final offlineOrPendingCount =
        (totalDrivers - onlineApprovedDrivers.length).clamp(0, totalDrivers);
    final activeOrder = _store.activeOrderRecord ?? _store.orders.first;
    final fleetRoutePoints = _store.activeRoutePolyline.length >= 2
        ? _store.activeRoutePolyline
        : <GeoPoint>[
            activeOrder.pickupLocation,
            _store.activeDriverLocation,
            activeOrder.dropoffLocation,
          ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bản đồ Giám sát Đội xe GPS Thời gian thực',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children: [
                Chip(label: Text('Đang rảnh: $freeOnlineCount xe (Xanh lá)')),
                Chip(
                  label: Text('Đang giao hàng: $busyCount xe (Cam)'),
                ),
                Chip(
                  label: Text(
                    'Chờ duyệt / Ngoại tuyến: $offlineOrPendingCount xe (Xám)',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Map3dPerspectiveWidget(
              height: 260,
              mode: MapViewMode.fleetOverview,
              is3dMode: _store.isMap3dEnabled,
              speedKmh: _store.currentSpeedKmh,
              onToggle3d: _store.toggleMap3d,
              progressFraction: _store.routeProgressStep / 10.0,
              routePoints: fleetRoutePoints,
              nextTurnInstruction:
                  'Trung tâm Điều hành PostGIS • ${onlineApprovedDrivers.length}/$totalDrivers Tài xế đang phát tọa độ',
              roadName:
                  'Đơn hoạt động: ${activeOrder.trackingCode} • Tọa độ xe: (${_store.activeDriverLocation.latitude.toStringAsFixed(4)}, ${_store.activeDriverLocation.longitude.toStringAsFixed(4)})',
            ),
          ],
        ),
      ),
    );
  }
}
