part of 'driver_subsystem_views.dart';

extension _DriverWalletAndAnalyticsViews on _DriverSubsystemEntryState {
  /// UC18: Thu nhập và rút tiền (Khớp 100% anh_sua_lai/uc18_thu_nhap.jpg)
  Widget _buildDriverWalletView() {
    final deliveredOrders = _store.orders
        .where(
          (o) =>
              o.status == OrderStatus.delivered &&
              o.paymentStatus != 'RETURNED',
        )
        .toList();
    final now = DateTime.now();
    final todayPrefix = now.day.toString().padLeft(2, '0');
    int? daysSinceDeliveredOrder(ActiveOrderRecord o) {
      if (o.createdDateLabel == 'Hôm nay' ||
          o.createdDateLabel.startsWith(todayPrefix)) {
        return 0;
      }
      if (o.createdDateLabel == 'Hôm qua') return 1;
      final parts = o.createdDateLabel.split('/');
      if (parts.length == 3) {
        final d = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (d != null && m != null && y != null) {
          return DateTime(now.year, now.month, now.day)
              .difference(DateTime(y, m, d))
              .inDays
              .abs();
        }
      }
      return null;
    }

    final todayMatchedOrders = deliveredOrders
        .where((o) => daysSinceDeliveredOrder(o) == 0)
        .toList();
    final todayDeliveredSum = todayMatchedOrders.fold<double>(
      0,
      (sum, o) => sum + ((o.deliveryFee + o.surchargeFee) * 0.80),
    );
    final weekMatchedOrders = deliveredOrders.where((o) {
      final diff = daysSinceDeliveredOrder(o);
      return diff != null && diff <= 7;
    }).toList();
    final weekDeliveredSum = weekMatchedOrders.fold<double>(
      0,
      (sum, o) => sum + ((o.deliveryFee + o.surchargeFee) * 0.80),
    );
    final deliveredSum = deliveredOrders.fold<double>(
      0,
      (sum, o) => sum + ((o.deliveryFee + o.surchargeFee) * 0.80),
    );
    final periodEarning = _incomePeriod == 'Ngày'
        ? todayDeliveredSum
        : _incomePeriod == 'Tuần'
            ? weekDeliveredSum
            : deliveredSum;
    final yesterdaySum = deliveredOrders
        .where((o) => daysSinceDeliveredOrder(o) == 1)
        .fold<double>(
          0,
          (sum, o) => sum + ((o.deliveryFee + o.surchargeFee) * 0.80),
        );
    final olderDeliveredSum = deliveredOrders
        .where((o) {
          final diff = daysSinceDeliveredOrder(o);
          return diff == null || diff > 1;
        })
        .fold<double>(
          0,
          (sum, o) => sum + ((o.deliveryFee + o.surchargeFee) * 0.80),
        );
    final driverWithdrawnSum = _store.withdrawalRequests
        .where((w) => w.ownerRole == 'Tài xế' && w.status != 'Từ chối')
        .fold<double>(0, (sum, w) => sum + w.amount);
    final w1Val = olderDeliveredSum;
    final w2Val = driverWithdrawnSum;
    final w3Val = yesterdaySum;
    final w4Val = todayDeliveredSum;
    final maxW = [w1Val, w2Val, w3Val, w4Val, 1.0].reduce((a, b) => a > b ? a : b);
    String fmtShort(double v) => v >= 1000000
        ? '${(v / 1000000).toStringAsFixed(2)}M'
        : '${(v / 1000).toStringAsFixed(0)}k';
    final weeklyBars = [
      ('Trước đó', (w1Val / maxW).clamp(0.15, 1.0), fmtShort(w1Val)),
      ('Đã rút', (w2Val / maxW).clamp(0.15, 1.0), fmtShort(w2Val)),
      ('Hôm qua', (w3Val / maxW).clamp(0.15, 1.0), fmtShort(w3Val)),
      ('Hôm nay', (w4Val / maxW).clamp(0.15, 1.0), fmtShort(w4Val)),
    ];
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            color: const Color(0xFF14B866),
            child: Column(
              children: [
                const Text(
                  'Thu nhập của tôi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  CurrencyFormatter.formatVnd(periodEarning),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.all(Radius.zero),
                  ),
                  child: Text(
                    'Đã hoàn tất ${deliveredOrders.length}/${_store.orders.length} chuyến • Số dư khả dụng: ${CurrencyFormatter.formatVnd(_store.driverWalletBalance)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: ['Ngày', 'Tuần', 'Tháng'].map((tab) {
                    final selected = _incomePeriod == tab;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Center(child: Text(tab)),
                          selected: selected,
                          selectedColor: const Color(0xFF14B866),
                          labelStyle: TextStyle(
                            color: selected
                                ? Colors.white
                                : const Color(0xFF15131E),
                            fontWeight: FontWeight.w800,
                          ),
                          onSelected: (_) =>
                              _rebuildDriverUi(() => _incomePeriod = tab),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F1E8),
                    borderRadius: BorderRadius.all(Radius.zero),
                    border: Border.all(color: const Color(0xFF15131E)),
                  ),
                  child: SizedBox(
                    height: 120,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: weeklyBars.map((b) {
                        return Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                b.$3,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF4A4754),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: 32,
                                height: 76 * b.$2,
                                decoration: BoxDecoration(
                                  color: b.$2 > 0.9
                                      ? const Color(0xFF14B866)
                                      : const Color(0xFF86EFAC),
                                  borderRadius: BorderRadius.all(Radius.zero),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                b.$1,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.zero),
                    border: Border.all(color: const Color(0xFF15131E)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Số dư ví có thể rút',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF4A4754),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  CurrencyFormatter.formatVnd(
                                    _store.driverWalletBalance,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF15131E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF15131E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(Radius.zero),
                              ),
                            ),
                            onPressed: () {
                              final amt = double.tryParse(
                                _withdrawAmountCtrl.text
                                    .trim()
                                    .replaceAll(RegExp(r'[^0-9.]'), ''),
                              );
                              if (amt == null || amt < 50000) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Vui lòng nhập số tiền rút hợp lệ (Tối thiểu 50.000đ)!',
                                    ),
                                  ),
                                );
                                return;
                              }
                              final parts = _selectedBank.split(' - ');
                              final parsedBank =
                                  parts.isNotEmpty ? parts.first.trim() : 'Vietcombank';
                              final parsedMask = parts.length > 1
                                  ? parts.last.trim()
                                  : '007100****889';
                              final ok = _store.requestWithdrawal(
                                ownerName: _store.activeDriverName,
                                ownerRole: 'Tài xế',
                                amount: amt,
                                bankName: parsedBank,
                                accountMasked: parsedMask,
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok
                                        ? 'Đã gửi yêu cầu rút ${CurrencyFormatter.formatVnd(amt)} về $_selectedBank!'
                                        : 'Không thể rút tiền: Số dư ví sau khi rút phải giữ tối thiểu 200.000đ tiền ký quỹ.',
                                  ),
                                ),
                              );
                            },
                            child: const Text(
                              'Rút tiền',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final amountField = TextField(
                            controller: _withdrawAmountCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Số tiền rút (VNĐ)',
                            ),
                          );
                          final bankField = DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _selectedBank,
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Ngân hàng liên kết',
                            ),
                            items: [
                              'Vietcombank - 007100****889',
                              'BIDV - 314100****221',
                            ]
                                .map(
                                  (b) => DropdownMenuItem(
                                    value: b,
                                    child: Text(
                                      b,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                _rebuildDriverUi(() => _selectedBank = v);
                              }
                            },
                          );
                          if (constraints.maxWidth < 480) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                amountField,
                                const SizedBox(height: 10),
                                bankField,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: amountField),
                              const SizedBox(width: 10),
                              Expanded(child: bankField),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                if (_store.withdrawalRequests
                    .any((w) => w.ownerRole == 'Tài xế')) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Lịch sử lệnh rút tiền Ví Tài xế (Đồng bộ Admin UC29)',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._store.withdrawalRequests
                      .where((w) => w.ownerRole == 'Tài xế')
                      .map((w) {
                    final isApproved = w.status == 'Đã duyệt';
                    final isRejected = w.status == 'Từ chối';
                    final statusColor = isApproved
                        ? const Color(0xFF14B866)
                        : isRejected
                            ? AppColors.danger
                            : const Color(0xFFD97706);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFF15131E)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '#${w.id} • ${CurrencyFormatter.formatVnd(w.amount)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '${w.bankName} (${w.accountMasked}) • ${w.requestDate}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF4A4754),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.14),
                              border: Border.all(color: statusColor),
                            ),
                            child: Text(
                              w.status,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 14),
                const Text(
                  'Chuyến xe gần đây (Bấm để xem lộ trình)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(height: 8),
                ..._store.orders.map((ord) {
                  final isCancelledOrFailed =
                      ord.status == OrderStatus.cancelled ||
                      ord.status == OrderStatus.failed ||
                      ord.status == OrderStatus.returning;
                  final isDone = ord.status == OrderStatus.delivered;
                  final driverNetFee = isCancelledOrFailed
                      ? 0.0
                      : ((ord.deliveryFee + ord.surchargeFee) * 0.80)
                            .roundToDouble();
                  return InkWell(
                    onTap: () {
                      _store.selectDriverOrder(ord.trackingCode);
                      _rebuildDriverUi(() => _selectedScreenIndex = 3);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.all(Radius.zero),
                        border: Border.all(color: const Color(0xFF15131E)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Đơn ${ord.trackingCode} • ${ord.serviceType.displayName} (${ord.status.displayName})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '${ord.pickupAddress} → ${ord.dropoffAddress}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF4A4754),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                isCancelledOrFailed
                                    ? '0 đ'
                                    : '+${CurrencyFormatter.formatVnd(driverNetFee)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  color: isCancelledOrFailed
                                      ? AppColors.danger
                                      : const Color(0xFF14B866),
                                ),
                              ),
                              Text(
                                isCancelledOrFailed
                                    ? '${ord.status.displayName} / 0%'
                                    : (isDone ? 'Thực nhận 80%' : 'Dự kiến 80%'),
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF6B667A),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// UC19: Lịch sử giao hàng của Tài xế (Khớp 100% uc19_lich_su_giao_1791014821234.jpg)
  Widget _buildDriverTripHistoryUc19View() {
    final now = DateTime.now();
    final todayPrefix = now.day.toString().padLeft(2, '0');
    int? daysSinceOrder(ActiveOrderRecord o) {
      if (o.createdDateLabel == 'Hôm nay' ||
          o.createdDateLabel.startsWith(todayPrefix)) {
        return 0;
      }
      if (o.createdDateLabel == 'Hôm qua') return 1;
      final parts = o.createdDateLabel.split('/');
      if (parts.length == 3) {
        final d = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (d != null && m != null && y != null) {
          return DateTime(now.year, now.month, now.day)
              .difference(DateTime(y, m, d))
              .inDays
              .abs();
        }
      }
      return null;
    }

    final filteredTrips = _driverHistoryPeriod == 'Hôm nay'
        ? _store.orders.where((o) => daysSinceOrder(o) == 0).toList()
        : _driverHistoryPeriod == 'Tuần này'
            ? _store.orders.where((o) {
                final diff = daysSinceOrder(o);
                return diff != null && diff <= 7;
              }).toList()
            : _store.orders;
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFF14B866),
            child: Row(
              children: [
                InkWell(
                  onTap: () => _rebuildDriverUi(() => _selectedScreenIndex = 1),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Lịch sử giao hàng',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  children: ['Hôm nay', 'Tuần này', 'Tháng này'].map((period) {
                    final selected = _driverHistoryPeriod == period;
                    return ChoiceChip(
                      label: Text(period),
                      selected: selected,
                      selectedColor: const Color(0xFF14B866),
                      labelStyle: TextStyle(
                        color:
                            selected ? Colors.white : const Color(0xFF15131E),
                        fontWeight: FontWeight.w800,
                      ),
                      onSelected: (_) =>
                          _rebuildDriverUi(() => _driverHistoryPeriod = period),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                ...filteredTrips.map((ord) {
                  final isReturned = ord.paymentStatus == 'RETURNED';
                  final isCancelledOrFailed =
                      ord.status == OrderStatus.cancelled ||
                      ord.status == OrderStatus.failed ||
                      ord.status == OrderStatus.returning ||
                      isReturned;
                  final statusDisplay =
                      isReturned ? 'Đã hoàn kho' : ord.status.displayName;
                  final driverNetFee = isCancelledOrFailed
                      ? 0.0
                      : ((ord.deliveryFee + ord.surchargeFee) * 0.80)
                            .roundToDouble();
                  return InkWell(
                    onTap: () => _rebuildDriverUi(() {
                      _store.selectDriverOrder(ord.trackingCode);
                      _selectedScreenIndex =
                          ord.status == OrderStatus.delivered ? 5 : 3;
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.all(Radius.zero),
                        border: Border.all(color: const Color(0xFF15131E)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Hình thu nhỏ lộ trình GPS bên trái giống uc19_lich_su_giao_1791014821234.jpg
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.all(Radius.zero),
                              border: Border.all(color: const Color(0xFF86EFAC)),
                            ),
                            child: const Stack(
                              children: [
                                Center(
                                  child: Icon(
                                    Icons.route_rounded,
                                    color: Color(0xFF14B866),
                                    size: 32,
                                  ),
                                ),
                                Positioned(
                                  top: 6,
                                  left: 6,
                                  child: Icon(
                                    Icons.circle,
                                    size: 8,
                                    color: Color(0xFF5B33E6),
                                  ),
                                ),
                                Positioned(
                                  bottom: 6,
                                  right: 6,
                                  child: Icon(
                                    Icons.location_on,
                                    size: 14,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${ord.trackingCode} • ${ord.createdDateLabel}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isCancelledOrFailed
                                            ? const Color(0xFFFEE2E2)
                                            : const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.all(Radius.zero),
                                      ),
                                      child: Text(
                                        isCancelledOrFailed
                                            ? statusDisplay
                                            : ord.ratingStars != null
                                                ? '${ord.ratingStars}.0 ★'
                                                : 'Chưa ĐG',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: isCancelledOrFailed
                                              ? AppColors.danger
                                              : const Color(0xFFD97706),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Từ: ${ord.pickupAddress}\nĐến: ${ord.dropoffAddress}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF4A4754),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        statusDisplay,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: isCancelledOrFailed
                                              ? AppColors.danger
                                              : const Color(0xFF14B866),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isCancelledOrFailed
                                          ? '0 đ'
                                          : '+ ${CurrencyFormatter.formatVnd(driverNetFee)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14.5,
                                        color: isCancelledOrFailed
                                            ? AppColors.danger
                                            : const Color(0xFF14B866),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// UC20: Báo cáo sự cố trên đường (Khớp 100% anh_sua_lai/uc20_bao_cao_su_co.jpg)
  Widget _buildRoadIncidentReportView() {
    final activeOrder = _store.activeOrderRecord ?? _store.orders.first;
    final driverIncidents = _store.complaints
        .where(
          (c) =>
              c.customerName.startsWith('Tài xế') ||
              c.driverName == _store.activeDriverName,
        )
        .toList();
    final reasons = [
      'Hàng bị hỏng',
      'Khách không nhận hàng',
      'Tai nạn / Xe hỏng',
      'Kẹt xe nghiêm trọng / Khác',
    ];
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFF14B866),
            child: Row(
              children: [
                InkWell(
                  onTap: () => _rebuildDriverUi(() => _selectedScreenIndex = 3),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Báo cáo sự cố (${activeOrder.trackingCode})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_store.orders.length > 1) ...[
                  const Text(
                    'Chọn vận đơn gặp sự cố',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _store.orders.map((o) {
                      final isCur = o.trackingCode == activeOrder.trackingCode;
                      return ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${o.trackingCode} (${o.status.displayName})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isCur ? Colors.white : const Color(0xFF15131E),
                          ),
                        ),
                        selected: isCur,
                        selectedColor: const Color(0xFF14B866),
                        onSelected: (_) => _rebuildDriverUi(
                          () => _store.selectDriverOrder(o.trackingCode),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                const Text(
                  'Chọn loại sự cố',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: reasons.contains(_incidentType)
                      ? _incidentType
                      : reasons.first,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.report_problem_outlined),
                  ),
                  items: reasons
                      .map(
                        (r) => DropdownMenuItem(
                          value: r,
                          child: Text(r, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _rebuildDriverUi(() => _incidentType = v);
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'Mô tả sự cố',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _incidentNoteCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Nhập chi tiết tình trạng hiện tại...',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Hình ảnh minh chứng',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: InkWell(
                        borderRadius: BorderRadius.all(Radius.zero),
                        onTap: () {
                          _rebuildDriverUi(() {
                            _attachedIncidentPhotos =
                                (_attachedIncidentPhotos % 4) + 1;
                          });
                        },
                        child: Container(
                          height: 68,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F1E8),
                            borderRadius: BorderRadius.all(Radius.zero),
                            border: Border.all(color: const Color(0xFF14B866)),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.camera_alt_outlined,
                                color: Color(0xFF14B866),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Chụp ảnh ($_attachedIncidentPhotos/4)',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    for (int i = 0; i < 3; i++) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.all(Radius.zero),
                          onTap: () {
                            _rebuildDriverUi(() {
                              _attachedIncidentPhotos = i + 2;
                            });
                          },
                          child: Container(
                            height: 68,
                            decoration: BoxDecoration(
                              color: _attachedIncidentPhotos > i + 1
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFF5F1E8),
                              borderRadius: BorderRadius.all(Radius.zero),
                              border: Border.all(
                                color: _attachedIncidentPhotos > i + 1
                                    ? const Color(0xFF14B866)
                                    : const Color(0xFF15131E),
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                _attachedIncidentPhotos > i + 1
                                    ? Icons.check_circle_rounded
                                    : Icons.add,
                                color: _attachedIncidentPhotos > i + 1
                                    ? const Color(0xFF14B866)
                                    : const Color(0xFF4A4754),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.all(Radius.zero),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: Color(0xFF14B866),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Vị trí hiện tại đã được đính kèm (${_store.activeDriverLocation.latitude.toStringAsFixed(4)}, ${_store.activeDriverLocation.longitude.toStringAsFixed(4)})',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF166534),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF14B866),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.zero),
                      ),
                    ),
                    onPressed: activeOrder.status == OrderStatus.delivered ||
                            activeOrder.status == OrderStatus.cancelled
                        ? null
                        : () {
                            final activeOrd =
                                _store.activeOrderRecord ?? _store.orders.first;
                            final rawDesc =
                                _incidentNoteCtrl.text.trim().isEmpty
                                    ? 'Báo cáo sự cố trên lộ trình: $_incidentType'
                                    : _incidentNoteCtrl.text.trim();
                            final gpsTag =
                                '(${_store.activeDriverLocation.latitude.toStringAsFixed(4)}, ${_store.activeDriverLocation.longitude.toStringAsFixed(4)})';
                            _store.addIncidentOrComplaint(
                              orderId: activeOrd.trackingCode,
                              reporterName: 'Tài xế ${_store.activeDriverName}',
                              issueType: _incidentType,
                              description:
                                  '$rawDesc • Đính kèm $_attachedIncidentPhotos/4 ảnh minh chứng • GPS: $gpsTag',
                            );
                            _incidentNoteCtrl.clear();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Đã gửi báo cáo sự cố đơn ${activeOrd.trackingCode} ($_attachedIncidentPhotos/4 ảnh) kèm tọa độ GPS về Trung tâm Điều phối!',
                                ),
                              ),
                            );
                          },
                    child: Text(
                      activeOrder.status == OrderStatus.delivered ||
                              activeOrder.status == OrderStatus.cancelled
                          ? 'Đơn đã hoàn tất / Đã hủy (Không thể báo sự cố)'
                          : 'Gửi báo cáo',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                if (driverIncidents.isNotEmpty) ...[
                  const Divider(height: 24),
                  const Text(
                    'Lịch sử báo cáo sự cố & Phản hồi từ Trung tâm Điều phối',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                  ),
                  const SizedBox(height: 8),
                  ...driverIncidents.map(
                    (inc) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F1E8),
                        border: Border.all(color: const Color(0xFF15131E)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${inc.ticketCode} • Đơn ${inc.orderId} • ${inc.issueType} (${inc.status})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...inc.replies.map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                '• $r',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// UC21: Thống kê hoạt động (Dark Mode Analytics - Khớp 100% anh_sua_lai/uc21_thong_ke.jpg)
  Widget _buildDarkModeAnalyticsView() {
    final allOrders = _store.orders;
    final now = DateTime.now();
    final todayPrefix = now.day.toString().padLeft(2, '0');
    int? daysSinceStatsOrder(ActiveOrderRecord o) {
      if (o.createdDateLabel == 'Hôm nay' ||
          o.createdDateLabel.startsWith(todayPrefix)) {
        return 0;
      }
      if (o.createdDateLabel == 'Hôm qua') return 1;
      final parts = o.createdDateLabel.split('/');
      if (parts.length == 3) {
        final d = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (d != null && m != null && y != null) {
          return DateTime(now.year, now.month, now.day)
              .difference(DateTime(y, m, d))
              .inDays
              .abs();
        }
      }
      return null;
    }

    final todayOrders =
        allOrders.where((o) => daysSinceStatsOrder(o) == 0).toList();
    final weekOrders = allOrders.where((o) {
      final diff = daysSinceStatsOrder(o);
      return diff != null && diff <= 7;
    }).toList();
    final periodOrders = _statsPeriod == 'Hôm nay'
        ? todayOrders
        : (_statsPeriod == 'Tuần này' ? weekOrders : allOrders);
    final totalOrdersCount = periodOrders.length;
    final safeTotal = totalOrdersCount == 0 ? 1 : totalOrdersCount;
    final deliveredCount = periodOrders
        .where(
          (o) =>
              o.status == OrderStatus.delivered &&
              o.paymentStatus != 'RETURNED',
        )
        .length;
    final nonCancelledCount = periodOrders
        .where(
          (o) =>
              o.status != OrderStatus.cancelled &&
              o.status != OrderStatus.failed &&
              o.status != OrderStatus.returning &&
              o.paymentStatus != 'RETURNED',
        )
        .length;
    final acceptRatio = (nonCancelledCount / safeTotal).clamp(0.0, 1.0);
    final acceptPct = (acceptRatio * 100).round();
    final ratedOrders = periodOrders
        .where((o) => o.ratingStars != null)
        .toList();
    final avgRating = ratedOrders.isNotEmpty
        ? (ratedOrders.fold<int>(0, (s, o) => s + o.ratingStars!) /
            ratedOrders.length)
        : (_store.activeDriverRecord?.rating ??
            (_store.drivers.isNotEmpty ? _store.drivers.first.rating : 5.0));

    final dayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    int weekdayIndexOfOrder(ActiveOrderRecord o) {
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
      return periodOrders
          .where((o) => weekdayIndexOfOrder(o) == idx)
          .length;
    });
    final maxDayCount = dayCounts.fold<int>(1, (m, c) => c > m ? c : m);
    final dailyBars = List.generate(7, (idx) {
      final c = dayCounts[idx];
      final ratio = c == 0 ? 0.18 : (c / maxDayCount).clamp(0.25, 1.0);
      return (dayLabels[idx], ratio, '$c');
    });
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.all(Radius.zero),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              const Text(
                'Thống kê hoạt động',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ['Hôm nay', 'Tuần này', 'Tháng này'].map((p) {
                  final selected = _statsPeriod == p;
                  return ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      p,
                      style: TextStyle(
                        fontSize: 11,
                        color: selected ? Colors.white : const Color(0xFF15131E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    selected: selected,
                    selectedColor: const Color(0xFF14B866),
                    onSelected: (_) => _rebuildDriverUi(() => _statsPeriod = p),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 3 thẻ KPI chuẩn anh_sua_lai/uc21_thong_ke.jpg
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF15131E),
              borderRadius: BorderRadius.all(Radius.zero),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Số đơn hoàn thành / Tổng cuốc xe',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$deliveredCount / $totalOrdersCount đơn',
                        style: const TextStyle(
                          color: Color(0xFF4ADE80),
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Color(0xFF4ADE80),
                  size: 36,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF15131E),
                    borderRadius: BorderRadius.all(Radius.zero),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tỷ lệ chấp nhận đơn',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              value: acceptRatio,
                              strokeWidth: 4,
                              color: const Color(0xFF14B866),
                              backgroundColor: Colors.white24,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              '$acceptPct%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF15131E),
                    borderRadius: BorderRadius.all(Radius.zero),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Điểm đánh giá TB',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            avgRating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFF59E0B),
                            size: 24,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF15131E),
              borderRadius: BorderRadius.all(Radius.zero),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Đơn hàng theo thời gian',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 120,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: dailyBars.map((bar) {
                      return Expanded(
                        child: Column(
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
                              width: 22,
                              height: 75 * bar.$2,
                              decoration: BoxDecoration(
                                color: bar.$2 == 1.0
                                    ? const Color(0xFF14B866)
                                    : const Color(0xFF38BDF8),
                                borderRadius: BorderRadius.all(Radius.zero),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              bar.$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Đánh giá gần đây từ khách hàng',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 8),
          ..._store.orders
              .where((o) => o.ratingStars != null)
              .map((ratedOrder) {
            final starsStr = '★' * (ratedOrder.ratingStars ?? 5);
            return InkWell(
              onTap: () => _rebuildDriverUi(() {
                _store.selectDriverOrder(ratedOrder.trackingCode);
                _selectedScreenIndex = 9;
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF15131E),
                  borderRadius: BorderRadius.all(Radius.zero),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Khách hàng ${ratedOrder.customerName} (${ratedOrder.trackingCode})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          starsStr,
                          style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '"${ratedOrder.ratingComment ?? 'Giao nhanh, nhiệt tình, đóng gói nguyên vẹn!'}"',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (widget.onLogout != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF87171),
                  side: const BorderSide(color: Color(0xFFF87171)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: widget.onLogout,
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text(
                  'Đăng xuất tài khoản Tài xế',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
