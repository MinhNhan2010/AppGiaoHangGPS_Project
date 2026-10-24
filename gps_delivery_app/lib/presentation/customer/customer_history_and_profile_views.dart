part of 'customer_subsystem_views.dart';

extension _CustomerHistoryAndProfileViews on _CustomerSubsystemEntryState {
  /// UC08: Liên hệ tài xế (Chat nội bộ & Gọi điện - Khớp 100% uc08_lien_he_1791014536835.jpg)
  Widget _buildInAppChatView() {
    final activeOrder = _store.activeCustomerOrderRecord ?? _store.orders.first;
    final hasAssignedDriver = activeOrder.assignedDriverName != null &&
        activeOrder.assignedDriverName!.trim().isNotEmpty;
    final assignedDriverRecord = hasAssignedDriver
        ? _store.drivers
            .where((d) => d.fullName == activeOrder.assignedDriverName)
            .firstOrNull
        : null;
    final orderMessages = _store.chatMessages
        .where((m) => m.orderId == activeOrder.trackingCode)
        .toList();
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            color: const Color(0xFF5B33E6),
            child: Row(
              children: [
                InkWell(
                  onTap: () => _rebuildCustomerUi(() => _selectedScreenIndex = 4),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.delivery_dining_rounded,
                    color: Color(0xFF5B33E6),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasAssignedDriver
                            ? '${activeOrder.assignedDriverName} • ${activeOrder.assignedDriverPlate ?? assignedDriverRecord?.licensePlate ?? "59X1-123.45"}'
                            : 'Chưa có tài xế nhận đơn (${activeOrder.trackingCode})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.circle,
                            color: hasAssignedDriver
                                ? const Color(0xFF14B866)
                                : const Color(0xFFF59E0B),
                            size: 9,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              hasAssignedDriver
                                  ? 'Đang hoạt động • ${activeOrder.trackingCode}'
                                  : 'Hệ thống đang điều phối tài xế',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFDCFCE7),
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF14B866),
                  ),
                  icon: const Icon(Icons.phone, color: Colors.white, size: 18),
                  onPressed: () {
                    if (!hasAssignedDriver) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đơn ${activeOrder.trackingCode} chưa có tài xế nhận chuyến để gọi điện.',
                          ),
                        ),
                      );
                      return;
                    }
                    final rawPhone = assignedDriverRecord?.phone ??
                        _store.activeDriverRecord?.phone ??
                        _store.activeDriverPhone;
                    final isClosed =
                        activeOrder.status == OrderStatus.delivered ||
                            activeOrder.status == OrderStatus.cancelled;
                    final maskedPhone = SecurityAndBarcodeUtils.maskPhoneNumber(
                      rawPhone,
                      shouldMask: isClosed,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đang kết nối cuộc gọi tới tài xế $maskedPhone...',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_store.customerOrders.length > 1) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _store.customerOrders.map((ordItem) {
                      final isCur =
                          ordItem.trackingCode == activeOrder.trackingCode;
                      return ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${ordItem.trackingCode} (${ordItem.status.displayName})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: isCur ? Colors.white : AppColors.ink,
                          ),
                        ),
                        selected: isCur,
                        selectedColor: const Color(0xFF5B33E6),
                        onSelected: (_) => _rebuildCustomerUi(() {
                          _store.selectCustomerOrder(ordItem.trackingCode);
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  height: 240,
                  child: ListView(
                    children: [
                      if (orderMessages.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Text(
                              'Chưa có tin nhắn trao đổi với tài xế trong chuyến hàng này.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF4A4754),
                              ),
                            ),
                          ),
                        ),
                      ...orderMessages.map((msg) {
                        return Align(
                          alignment: msg.isCustomer
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: msg.isCustomer
                                  ? const Color(0xFF5B33E6)
                                  : const Color(0xFFF5F1E8),
                              borderRadius: BorderRadius.all(Radius.zero),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg.text,
                                  style: TextStyle(
                                    color: msg.isCustomer
                                        ? Colors.white
                                        : const Color(0xFF15131E),
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  msg.timeLabel,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: msg.isCustomer
                                        ? Colors.white70
                                        : const Color(0xFF4A4754),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      if (activeOrder.podImageNote != null &&
                          activeOrder.podImageNote!.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F1E8),
                              borderRadius: BorderRadius.all(Radius.zero),
                              border: Border.all(color: const Color(0xFF15131E)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.image_rounded,
                                  color: Color(0xFF5B33E6),
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Ảnh xác nhận kiện hàng (${activeOrder.trackingCode}): ${activeOrder.podImageNote}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF334155),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    'Tôi đang xuống lấy hàng',
                    'Để hàng ở lễ tân giúp mình',
                    'Gọi điện khi tới nơi nhé',
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatInputCtrl,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Nhập tin nhắn...',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF5B33E6),
                      ),
                      icon: const Icon(Icons.send_rounded, size: 18),
                      onPressed: () {
                        if (_chatInputCtrl.text.trim().isEmpty) return;
                        _store.sendChatMessage(
                          activeOrder.trackingCode,
                          _chatInputCtrl.text.trim(),
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
        ],
      ),
    );
  }

  /// UC12: Hủy đơn hàng & Chọn lý do hủy (Khớp 100% uc12_huy_don_1791014622336.jpg)
  Widget _buildCancelOrderSheetView() {
    final targetOrder = _store.activeCustomerOrderRecord;
    final canCancel = targetOrder != null &&
        targetOrder.status.canTransitionTo(OrderStatus.cancelled);
    final hasDriverAccepted = targetOrder != null &&
        (targetOrder.status == OrderStatus.accepted ||
            targetOrder.status == OrderStatus.arrivingPickup);
    final reasons = [
      'Đổi ý, không muốn gửi nữa',
      'Tìm được tài xế / dịch vụ khác',
      'Tài xế yêu cầu hủy đơn',
      'Thời gian chờ quá lâu',
      'Lý do khác',
    ];
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Hủy đơn hàng',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF15131E),
              ),
            ),
            if (targetOrder != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F1E8),
                  border: Border.all(color: const Color(0xFF15131E)),
                ),
                child: Text(
                  'Đơn đang chọn: ${targetOrder.trackingCode} (${targetOrder.status.displayName})\nLộ trình: ${targetOrder.pickupAddress} → ${targetOrder.dropoffAddress}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF15131E),
                  ),
                ),
              ),
              if (_store.customerOrders.length > 1) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _store.customerOrders.map((ordItem) {
                    final isCur =
                        ordItem.trackingCode == targetOrder.trackingCode;
                    return ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        '${ordItem.trackingCode} (${ordItem.status.displayName})',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isCur ? Colors.white : AppColors.ink,
                        ),
                      ),
                      selected: isCur,
                      selectedColor: const Color(0xFF5B33E6),
                      onSelected: (_) => _rebuildCustomerUi(() {
                        _store.selectCustomerOrder(ordItem.trackingCode);
                      }),
                    );
                  }).toList(),
                ),
              ],
            ],
            const SizedBox(height: 12),
            const Text(
              'Vui lòng chọn lý do hủy đơn:',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
            ),
            const SizedBox(height: 6),
            RadioGroup<String>(
              groupValue: _selectedCancelReason,
              onChanged: (v) {
                if (v != null) _rebuildCustomerUi(() => _selectedCancelReason = v);
              },
              child: Column(
                children: reasons
                    .map(
                      (r) => RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          r,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        value: r,
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _cancelDetailCtrl,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Nhập lý do cụ thể...',
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F1E8),
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: const Color(0xFFFDBA74)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFFF5E83),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      !canCancel && targetOrder != null
                          ? 'Đơn ${targetOrder.trackingCode} đang ở trạng thái "${targetOrder.status.displayName}" nên không thể hủy theo quy tắc FSM.'
                          : hasDriverAccepted
                              ? 'Quý khách lưu ý: Tài xế đã nhận chuyến, việc hủy đơn hàng này có thể phát sinh phí hủy (15.000đ).'
                              : 'Đơn hàng đang ở bước tìm tài xế: Quý khách được hỗ trợ hủy đơn miễn phí (0đ).',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9A3412),
                        fontWeight: FontWeight.w700,
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
                  backgroundColor: canCancel
                      ? const Color(0xFFDC2626)
                      : AppColors.textSecondary,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.zero),
                  ),
                ),
                onPressed: canCancel
                    ? () {
                        final target = targetOrder.trackingCode;
                        final reason = _cancelDetailCtrl.text.trim().isNotEmpty
                            ? '$_selectedCancelReason (${_cancelDetailCtrl.text.trim()})'
                            : _selectedCancelReason;
                        final ok = _store.cancelOrder(target, reason);
                        if (ok) {
                          _cancelDetailCtrl.clear();
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Đã hủy đơn $target (Lý do: $reason)'
                                  : 'Đơn $target đang ở trạng thái "${targetOrder.status.displayName}", không thể hủy.',
                            ),
                          ),
                        );
                      }
                    : null,
                child: Text(
                  canCancel ? 'Xác nhận hủy đơn' : 'Không thể hủy đơn này',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.zero),
                  ),
                ),
                onPressed: () => _rebuildCustomerUi(() => _selectedScreenIndex = 4),
                child: const Text(
                  'Quay lại',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// UC09: Lịch sử đơn hàng + Empty State + Skeleton (Khớp 100% uc09_lich_su_1791014563307.jpg, ui_state_02_empty.jpg, ui_state_04_skeleton.jpg)
  Widget _buildOrderHistoryAndPodView() {
    final query = _historySearchCtrl.text.trim().toLowerCase();
    final filtered = _store.customerOrders.where((o) {
      final isReturned = o.paymentStatus == 'RETURNED';
      if (_historyFilterTab == 'Đang giao' &&
          (o.status == OrderStatus.delivered ||
              o.status == OrderStatus.cancelled ||
              o.status == OrderStatus.failed ||
              o.status == OrderStatus.returning ||
              isReturned)) {
        return false;
      }
      if (_historyFilterTab == 'Hoàn thành' &&
          (o.status != OrderStatus.delivered || isReturned)) {
        return false;
      }
      if (_historyFilterTab == 'Đã hủy' &&
          o.status != OrderStatus.cancelled &&
          o.status != OrderStatus.failed &&
          o.status != OrderStatus.returning &&
          !isReturned) {
        return false;
      }
      if (query.isNotEmpty) {
        return o.trackingCode.toLowerCase().contains(query) ||
            o.pickupAddress.toLowerCase().contains(query) ||
            o.dropoffAddress.toLowerCase().contains(query);
      }
      return true;
    }).toList();

    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFF5B33E6),
            child: const Text(
              'Lịch sử đơn hàng',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _historySearchCtrl,
                        onChanged: (_) => _rebuildCustomerUi(() {}),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Tìm theo mã đơn hàng...',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        _rebuildCustomerUi(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Đã cập nhật danh sách ${_store.customerOrders.length} vận đơn của bạn',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: const Text(
                        'Làm mới',
                        style: TextStyle(fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: ['Tất cả', 'Đang giao', 'Hoàn thành', 'Đã hủy']
                      .map((tab) {
                    return ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(tab),
                      selected: _historyFilterTab == tab,
                      onSelected: (_) => _rebuildCustomerUi(() {
                        _historyFilterTab = tab;
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  EmptyOrdersStateWidget(
                    onCreateOrder: () => _rebuildCustomerUi(() {
                      _selectedScreenIndex = 2;
                    }),
                  )
                else
                  ...filtered.map((ord) {
                    final isReturned = ord.paymentStatus == 'RETURNED';
                    final isDone =
                        ord.status == OrderStatus.delivered && !isReturned;
                    final isCancelled = ord.status == OrderStatus.cancelled ||
                        ord.status == OrderStatus.failed ||
                        ord.status == OrderStatus.returning ||
                        isReturned;
                    final badgeBg = isDone
                        ? const Color(0xFFDCFCE7)
                        : isCancelled
                            ? const Color(0xFFFEE2E2)
                            : const Color(0xFFE9E9E4);
                    final badgeFg = isDone
                        ? const Color(0xFF14B866)
                        : isCancelled
                            ? const Color(0xFFDC2626)
                            : const Color(0xFFFF5E83);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
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
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Text(
                                ord.trackingCode,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  color: Color(0xFF15131E),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  borderRadius: BorderRadius.all(Radius.zero),
                                ),
                                child: Text(
                                  isReturned
                                      ? 'Đã hoàn kho'
                                      : ord.status.displayName,
                                  style: TextStyle(
                                    color: badgeFg,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Từ: ${ord.pickupAddress} → Đến: ${ord.dropoffAddress}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  ord.podImageNote != null &&
                                          ord.podImageNote!.isNotEmpty
                                      ? 'Dịch vụ: ${ord.serviceType.displayName} • POD: ${ord.podImageNote}'
                                      : isDone
                                          ? 'Dịch vụ: ${ord.serviceType.displayName} • POD: Đã ký nhận'
                                          : ord.status == OrderStatus.cancelled
                                              ? 'Dịch vụ: ${ord.serviceType.displayName} • Hủy: ${ord.cancelReason ?? "Khách hủy đơn"}'
                                              : 'Dịch vụ: ${ord.serviceType.displayName} • TT: ${ord.paymentStatus == "PAID" ? "Đã thanh toán" : "Chưa thanh toán (${ord.paymentMethod})"}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF4A4754),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                CurrencyFormatter.formatVnd(ord.totalAmount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  color: Color(0xFF5B33E6),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  _store.selectCustomerOrder(ord.trackingCode);
                                  _rebuildCustomerUi(
                                    () => _selectedScreenIndex = 4,
                                  );
                                },
                                icon: const Icon(Icons.my_location, size: 15),
                                label: const Text('Xem chi tiết >'),
                              ),
                              TextButton.icon(
                                onPressed: isDone
                                    ? () {
                                        _store.selectCustomerOrder(
                                          ord.trackingCode,
                                        );
                                        _rebuildCustomerUi(
                                          () => _selectedScreenIndex = 8,
                                        );
                                      }
                                    : null,
                                icon: Icon(
                                  ord.ratingStars != null
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  size: 15,
                                  color: ord.ratingStars != null
                                      ? const Color(0xFFF59E0B)
                                      : null,
                                ),
                                label: Text(
                                  ord.ratingStars != null
                                      ? 'Đã đánh giá (${ord.ratingStars}★)'
                                      : 'Đánh giá & Tip',
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  _store.selectCustomerOrder(ord.trackingCode);
                                  _rebuildCustomerUi(
                                    () => _selectedScreenIndex = 9,
                                  );
                                },
                                icon: const Icon(
                                  Icons.support_agent_outlined,
                                  size: 15,
                                ),
                                label: const Text('Khiếu nại'),
                              ),
                            ],
                          ),
                        ],
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

  /// UC10: Đánh giá chuyến hàng & Tiền thưởng Tip (Khớp 100% uc10_danh_gia_1791014585673.jpg)
  Widget _buildRateDriverView() {
    final currentSelected = _store.activeCustomerOrderRecord;
    final activeOrder = (currentSelected != null &&
            currentSelected.status == OrderStatus.delivered &&
            currentSelected.paymentStatus != 'RETURNED')
        ? currentSelected
        : (_store.customerOrders
                .where(
                  (o) =>
                      o.status == OrderStatus.delivered &&
                      o.paymentStatus != 'RETURNED',
                )
                .firstOrNull ??
            currentSelected ??
            _store.orders.first);
    final canRateOrder = activeOrder.status == OrderStatus.delivered &&
        activeOrder.paymentStatus != 'RETURNED';
    if (_lastSyncedRatingOrderCode != activeOrder.trackingCode) {
      _lastSyncedRatingOrderCode = activeOrder.trackingCode;
      if (activeOrder.ratingStars != null) {
        _ratingStars = activeOrder.ratingStars!;
      } else {
        _ratingStars = 5;
      }
    }
    final assignedDrv = activeOrder.assignedDriverName != null
        ? _store.drivers
            .where((d) => d.fullName == activeOrder.assignedDriverName)
            .firstOrNull
        : _store.activeDriverRecord;
    final chips = [
      'Thái độ thân thiện',
      'Giao hàng nhanh',
      'Hàng hóa cẩn thận',
      'Đúng giờ',
    ];
    const tipOptions = [0, 5000, 10000, 20000];

    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFF5B33E6),
            child: Row(
              children: [
                InkWell(
                  onTap: () => _rebuildCustomerUi(() => _selectedScreenIndex = 4),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Đánh giá chuyến hàng (${activeOrder.trackingCode})',
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
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                if (_store.customerOrders.length > 1) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _store.customerOrders.map((ordItem) {
                      final isCur =
                          ordItem.trackingCode == activeOrder.trackingCode;
                      return ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${ordItem.trackingCode} (${ordItem.status.displayName})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: isCur ? Colors.white : AppColors.ink,
                          ),
                        ),
                        selected: isCur,
                        selectedColor: const Color(0xFF5B33E6),
                        onSelected: (_) => _rebuildCustomerUi(() {
                          _store.selectCustomerOrder(ordItem.trackingCode);
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                ],
                const CircleAvatar(
                  radius: 32,
                  backgroundColor: Color(0xFFE9E9E4),
                  child: Icon(
                    Icons.person_rounded,
                    size: 38,
                    color: Color(0xFF5B33E6),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  activeOrder.assignedDriverName ?? _store.activeDriverName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${assignedDrv?.vehicleType ?? _store.activeDriverRecord?.vehicleType ?? "Xe máy"} - ${activeOrder.assignedDriverPlate ?? assignedDrv?.licensePlate ?? _store.activeDriverRecord?.licensePlate ?? "59X1-123.45"}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF4A4754),
                  ),
                ),
                if (!canRateOrder) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    color: const Color(0xFFFEF3C7),
                    child: Text(
                      'Đơn ${activeOrder.trackingCode} (${activeOrder.paymentStatus == "RETURNED" ? "Đã hoàn kho" : activeOrder.status.displayName}) chưa hoàn tất giao tới người nhận nên chưa thể đánh giá.',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ] else if (activeOrder.ratingStars != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    color: const Color(0xFFDCFCE7),
                    child: Text(
                      activeOrder.ratingComment != null &&
                              activeOrder.ratingComment!.isNotEmpty
                          ? 'Đơn ${activeOrder.trackingCode} đã được đánh giá ${activeOrder.ratingStars}★: "${activeOrder.ratingComment}"'
                          : 'Đơn ${activeOrder.trackingCode} đã được đánh giá ${activeOrder.ratingStars}★ (Có thể cập nhật nhận xét)',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF166534),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final starNum = index + 1;
                    return IconButton(
                      onPressed: () => _rebuildCustomerUi(() => _ratingStars = starNum),
                      icon: Icon(
                        starNum <= _ratingStars
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: const Color(0xFFF59E0B),
                        size: 36,
                      ),
                    );
                  }),
                ),
                Text(
                  _ratingStars == 5
                      ? 'Tuyệt vời!'
                      : _ratingStars == 4
                          ? 'Rất hài lòng'
                          : 'Cần cải thiện',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFFF5E83),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: chips.map((chip) {
                    final selected = _selectedFeedbackChips.contains(chip);
                    return FilterChip(
                      label: Text(chip),
                      selected: selected,
                      selectedColor: const Color(0xFFE9E9E4),
                      onSelected: (v) {
                        _rebuildCustomerUi(() {
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
                const SizedBox(height: 12),
                TextField(
                  controller: _ratingCommentCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Chia sẻ thêm trải nghiệm của bạn...',
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    activeOrder.ratingStars != null
                        ? 'Tiền thưởng cho tài xế (Đã chốt ở lần đánh giá đầu):'
                        : 'Tiền thưởng cho tài xế (Tip):',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: tipOptions.map((tip) {
                    final selected = _selectedTipVnd == tip;
                    final label = tip == 0
                        ? 'Không'
                        : CurrencyFormatter.formatVnd(tip.toDouble());
                    final alreadyRated = activeOrder.ratingStars != null;
                    return OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: selected
                            ? const Color(0xFFFF5E83)
                            : Colors.white,
                        foregroundColor: selected
                            ? Colors.white
                            : const Color(0xFF15131E),
                        side: BorderSide(
                          color: selected
                              ? const Color(0xFFFF5E83)
                              : const Color(0xFF15131E),
                        ),
                      ),
                      onPressed: alreadyRated
                          ? null
                          : () => _rebuildCustomerUi(() => _selectedTipVnd = tip),
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
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
                    onPressed: canRateOrder
                        ? () {
                            final isFirstRating =
                                activeOrder.ratingStars == null;
                            final effectiveTip =
                                isFirstRating ? _selectedTipVnd : 0;
                            final tipNote = effectiveTip > 0
                                ? ' [Tip: ${CurrencyFormatter.formatVnd(effectiveTip.toDouble())}]'
                                : '';
                            final chipTags = _selectedFeedbackChips.isNotEmpty
                                ? '[${_selectedFeedbackChips.join(', ')}] '
                                : '';
                            _store.submitDriverRating(
                              activeOrder.trackingCode,
                              _ratingStars,
                              '$chipTags${_ratingCommentCtrl.text}$tipNote',
                              tipVnd: effectiveTip.toDouble(),
                            );
                            _rebuildCustomerUi(() {
                              _ratingCommentCtrl.clear();
                              _selectedFeedbackChips.clear();
                              _selectedTipVnd = 0;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isFirstRating
                                      ? 'Đã gửi đánh giá $_ratingStars sao$tipNote cho tài xế!'
                                      : 'Đã cập nhật đánh giá $_ratingStars sao cho đơn ${activeOrder.trackingCode}!',
                                ),
                              ),
                            );
                          }
                        : null,
                    child: const Text(
                      'Gửi đánh giá',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
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

  /// Gửi khiếu nại đơn hàng kèm ảnh bằng chứng
  Widget _buildSubmitComplaintView() {
    final targetOrder = _store.activeCustomerOrderRecord ?? _store.orders.first;
    final myComplaints = _store.complaints
        .where(
          (c) =>
              c.customerName.trim().toLowerCase() ==
                  _store.customerFullName.trim().toLowerCase() ||
              c.orderId == targetOrder.trackingCode,
        )
        .toList();
    final types = [
      'Hàng hư hỏng',
      'Giao hàng chậm',
      'Thái độ tài xế',
      'Sai phí cước',
    ];
    return Card(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: AppColors.ink, width: 1.5),
      ),
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
                  'Gửi khiếu nại & Yêu cầu hỗ trợ đơn hàng',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _rebuildCustomerUi(() => _selectedScreenIndex = 7),
                  icon: const Icon(Icons.arrow_back_rounded, size: 15),
                  label: const Text('Quay lại Lịch sử đơn'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_store.customerOrders.length > 1) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _store.customerOrders.map((o) {
                  final selected = o.trackingCode == targetOrder.trackingCode;
                  return ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${o.trackingCode} (${o.status.displayName})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : const Color(0xFF15131E),
                      ),
                    ),
                    selected: selected,
                    selectedColor: const Color(0xFF5B33E6),
                    onSelected: (_) => _rebuildCustomerUi(
                      () => _store.selectCustomerOrder(o.trackingCode),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F1E8),
                border: Border.all(color: const Color(0xFF15131E)),
              ),
              child: Text(
                'Đơn hàng đang chọn: ${targetOrder.trackingCode} (${targetOrder.status.displayName}) • ${targetOrder.pickupAddress} → ${targetOrder.dropoffAddress}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF15131E),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children: types.map((t) {
                return ChoiceChip(
                  label: Text(t),
                  selected: _complaintType == t,
                  onSelected: (_) => _rebuildCustomerUi(() => _complaintType = t),
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _customerComplaintPhotos >= 3
                      ? null
                      : () => _rebuildCustomerUi(() {
                            _customerComplaintPhotos =
                                (_customerComplaintPhotos + 1).clamp(0, 3);
                          }),
                  icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                  label: Text(
                    'Đính kèm ảnh ($_customerComplaintPhotos/3)',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                for (var i = 1; i <= _customerComplaintPhotos; i++)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(
                      Icons.check_circle,
                      size: 15,
                      color: Color(0xFF14B866),
                    ),
                    label: Text(
                      'bang_chung_0$i.jpg',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onDeleted: () => _rebuildCustomerUi(() {
                      _customerComplaintPhotos =
                          (_customerComplaintPhotos - 1).clamp(0, 3);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                onPressed: () {
                  final rawDesc = _complaintDescCtrl.text.trim().isEmpty
                      ? 'Yêu cầu kiểm tra lộ trình & tình trạng kiện hàng'
                      : _complaintDescCtrl.text.trim();
                  _store.addIncidentOrComplaint(
                    orderId: targetOrder.trackingCode,
                    reporterName: _store.customerFullName,
                    issueType: _complaintType,
                    description:
                        '$rawDesc (Đính kèm $_customerComplaintPhotos/3 ảnh bằng chứng)',
                  );
                  _complaintDescCtrl.clear();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã gửi yêu cầu khiếu nại cho đơn ${targetOrder.trackingCode} ($_customerComplaintPhotos/3 ảnh) tới Trung tâm Hỗ trợ!',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.report_problem_outlined),
                label: const Text('Gửi yêu cầu hỗ trợ / Khiếu nại'),
              ),
            ),
            if (myComplaints.isNotEmpty) ...[
              const Divider(height: 24),
              const Text(
                'Lịch sử Khiếu nại & Phản hồi từ Admin',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 8),
              ...myComplaints.map(
                (c) => Container(
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
                        '${c.ticketCode} (${c.orderId}) • ${c.issueType} • Trạng thái: ${c.status}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...c.replies.map(
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
    );
  }

  /// UC41: Quản lý Hồ sơ cá nhân (Khớp 100% uc41_ho_so_1791094539435.jpg)
  Widget _buildCustomerProfileView() {
    final deliveredCount = _store.customerOrders
        .where(
          (o) =>
              o.status == OrderStatus.delivered &&
              o.paymentStatus != 'RETURNED',
        )
        .length;
    final loyaltyPoints = deliveredCount * 100;
    final loyaltyLabel = loyaltyPoints >= 500
        ? 'Hạng Vàng - $loyaltyPoints điểm'
        : 'Thành viên • $loyaltyPoints điểm tích lũy';
    final hasPhone = _store.hasUserProvidedPhone;

    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            color: const Color(0xFF5B33E6),
            child: Column(
              children: [
                const Text(
                  'Hồ sơ cá nhân',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Stack(
                  children: [
                    Builder(
                      builder: (context) {
                        const avatarThemes = [
                          (Color(0xFFE9E9E4), Color(0xFF5B33E6), Icons.person_rounded),
                          (Color(0xFFDCFCE7), Color(0xFF14B866), Icons.verified_user_rounded),
                          (Color(0xFFFEF3C7), Color(0xFFD97706), Icons.workspace_premium_rounded),
                          (Color(0xFFDBEAFE), Color(0xFF1D4ED8), Icons.face_retouching_natural_rounded),
                        ];
                        final theme = avatarThemes[_store.customerAvatarBadgeIndex % avatarThemes.length];
                        return Container(
                          width: 78,
                          height: 78,
                          decoration: BoxDecoration(
                            color: theme.$1,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                          child: Icon(
                            theme.$3,
                            size: 46,
                            color: theme.$2,
                          ),
                        );
                      },
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: InkWell(
                        onTap: () {
                          final nextIdx = (_store.customerAvatarBadgeIndex + 1) % 4;
                          _store.updateCustomerProfile(
                            fullName: _profileNameCtrl.text.trim(),
                            phone: _profilePhoneCtrl.text.trim(),
                            email: _profileEmailCtrl.text.trim(),
                            defaultAddress: _profileAddressCtrl.text.trim(),
                            gender: _profileGender,
                            avatarBadgeIndex: nextIdx,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Đã đổi biểu tượng đại diện hồ sơ (#${nextIdx + 1})!',
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF5B33E6),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _store.customerFullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.all(Radius.zero),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.workspace_premium_rounded,
                        size: 15,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          loyaltyLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _profileNameCtrl,
                    decoration: const InputDecoration(labelText: 'Họ và tên'),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final phoneField = TextField(
                        controller: _profilePhoneCtrl,
                        decoration: InputDecoration(
                          labelText: 'Số điện thoại',
                          hintText: 'Nhập số điện thoại liên hệ',
                          suffixIcon: Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: hasPhone
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.all(Radius.zero),
                            ),
                            child: Text(
                              hasPhone ? 'Đã xác thực' : 'Chưa cập nhật',
                              style: TextStyle(
                                color: hasPhone
                                    ? const Color(0xFF14B866)
                                    : const Color(0xFFD97706),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      );
                      final emailField = TextField(
                        controller: _profileEmailCtrl,
                        decoration: const InputDecoration(labelText: 'Email'),
                      );
                      if (constraints.maxWidth < 520) {
                        return Column(
                          children: [
                            phoneField,
                            const SizedBox(height: 12),
                            emailField,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: phoneField),
                          const SizedBox(width: 12),
                          Expanded(child: emailField),
                        ],
                      );
                    },
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _profileAddressCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Địa chỉ mặc định'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Giới tính',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                RadioGroup<String>(
                  groupValue: _profileGender,
                  onChanged: (v) {
                    if (v != null) _rebuildCustomerUi(() => _profileGender = v);
                  },
                  child: const Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: 'Nam',
                          title: Text('Nam'),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: 'Nữ',
                          title: Text('Nữ'),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: 'Khác',
                          title: Text('Khác'),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 20),
                const Text(
                  'Liên kết tài khoản',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    radius: 14,
                    backgroundColor: Color(0xFFFEE2E2),
                    child: Text(
                      'G',
                      style: TextStyle(
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  title: const Text('Google'),
                  trailing: Switch(
                    value: _store.isCustomerGoogleLinked,
                    onChanged: (v) {
                      _store.toggleCustomerSocialLink(
                        provider: 'GOOGLE',
                        linked: v,
                      );
                    },
                  ),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    radius: 14,
                    backgroundColor: Color(0xFFDCFCE7),
                    child: Icon(
                      Icons.shield_outlined,
                      size: 15,
                      color: Color(0xFF14B866),
                    ),
                  ),
                  title: const Text('Xác thực OTP Bảo mật 2 lớp (Email / SMS)'),
                  trailing: Switch(
                    value: _store.isCustomerTwoFactorEnabled,
                    onChanged: (v) {
                      _store.toggleCustomerSocialLink(
                        provider: 'TWO_FACTOR_OTP',
                        linked: v,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5B33E6),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.zero),
                      ),
                    ),
                    onPressed: () {
                      if (_profileNameCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Vui lòng nhập họ và tên hợp lệ!'),
                          ),
                        );
                        return;
                      }
                      _store.updateCustomerProfile(
                        fullName: _profileNameCtrl.text.trim(),
                        phone: _profilePhoneCtrl.text.trim(),
                        email: _profileEmailCtrl.text.trim(),
                        defaultAddress: _profileAddressCtrl.text.trim(),
                        gender: _profileGender,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã lưu thay đổi hồ sơ cá nhân (${_profileNameCtrl.text.trim()} • Giới tính: $_profileGender)!',
                          ),
                        ),
                      );
                    },
                    child: const Text(
                      'Lưu thay đổi hồ sơ',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const Divider(height: 24),
                _buildPartnerKycApplicationSection(context),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  }

  Widget _buildPartnerKycApplicationSection(BuildContext context) {
    final normPhone = _profilePhoneCtrl.text
        .trim()
        .replaceAll(RegExp(r'[^0-9]'), '');
    final drvRecord = _store.drivers
        .where(
          (d) =>
              d.phone.replaceAll(RegExp(r'[^0-9]'), '') == normPhone &&
              normPhone.isNotEmpty,
        )
        .firstOrNull;
    final merRecord = _store.merchantApplicants
        .where(
          (m) =>
              m.ownerPhone.replaceAll(RegExp(r'[^0-9]'), '') == normPhone &&
              normPhone.isNotEmpty,
        )
        .firstOrNull;

    Widget statusBadge(String? status) {
      final label = status ?? 'Chưa đăng ký';
      final isApproved = label == 'Đã duyệt';
      final isPending = label == 'Chờ duyệt';
      final isRejected = label == 'Từ chối';
      final bg = isApproved
          ? const Color(0xFFDCFCE7)
          : isPending
              ? const Color(0xFFFEF3C7)
              : isRejected
                  ? const Color(0xFFFEE2E2)
                  : const Color(0xFFF5F1E8);
      final fg = isApproved
          ? const Color(0xFF14B866)
          : isPending
              ? const Color(0xFFD97706)
              : isRejected
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF4A4754);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.all(Radius.zero),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: fg,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F1E8),
        border: Border.all(color: const Color(0xFF15131E)),
      ),
      child: Material(
        color: Colors.transparent,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
          initiallyExpanded: drvRecord != null || merRecord != null,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: const Icon(
            Icons.verified_user_rounded,
            color: Color(0xFF5B33E6),
            size: 20,
          ),
          title: const Text(
            'Đăng ký Đối tác Tài xế / Cửa hàng B2B (KYC)',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
              color: Color(0xFF15131E),
            ),
          ),
          subtitle: const Text(
            'Mở rộng nếu bạn muốn nộp hồ sơ định danh trở thành Tài xế hoặc Cửa hàng B2B',
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFF4A4754),
            ),
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFF15131E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.two_wheeler_rounded,
                        size: 18,
                        color: Color(0xFF5B33E6),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Đối tác Tài xế Giao hàng',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      statusBadge(drvRecord?.approvalStatus),
                    ],
                  ),
                  if (drvRecord != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Mã hồ sơ: ${drvRecord.id} • CCCD: ${drvRecord.citizenId}\nPhương tiện: ${drvRecord.vehicleType} (${drvRecord.licensePlate} - ${drvRecord.vehicleColor})',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showDriverKycApplicationDialog(
                        context,
                        existing: drvRecord,
                      ),
                      icon:
                          const Icon(Icons.assignment_ind_outlined, size: 16),
                      label: Text(
                        drvRecord == null
                            ? 'Đăng ký làm Đối tác Tài xế (Nộp KYC)'
                            : 'Cập nhật hồ sơ Tài xế (KYC)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFF15131E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.storefront_rounded,
                        size: 18,
                        color: Color(0xFFFF5E83),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Đối tác Cửa hàng / Doanh nghiệp B2B',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      statusBadge(merRecord?.approvalStatus),
                    ],
                  ),
                  if (merRecord != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Mã hồ sơ: ${merRecord.id} • Cửa hàng: ${merRecord.storeName}\nMST: ${merRecord.taxCode} • NH: ${merRecord.bankName} (${merRecord.bankAccount})',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showMerchantKycApplicationDialog(
                        context,
                        existing: merRecord,
                      ),
                      icon: const Icon(
                        Icons.business_center_outlined,
                        size: 16,
                      ),
                      label: Text(
                        merRecord == null
                            ? 'Đăng ký Cửa hàng B2B (Nộp KYC)'
                            : 'Cập nhật hồ sơ Cửa hàng B2B (KYC)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  void _showDriverKycApplicationDialog(
    BuildContext context, {
    DriverApplicantRecord? existing,
  }) {
    final citizenCtrl = TextEditingController(
      text: existing?.citizenId ?? '',
    );
    final plateCtrl = TextEditingController(
      text: existing?.licensePlate ?? '',
    );
    final colorCtrl = TextEditingController(
      text: existing?.vehicleColor ?? '',
    );
    String selectedVehicle = existing?.vehicleType ?? 'Xe máy';

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Hồ sơ Đăng ký Đối tác Tài xế (KYC)',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: citizenCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Số CCCD gắn chip (12 chữ số)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedVehicle,
                        decoration: const InputDecoration(
                          labelText: 'Loại phương tiện đăng ký',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Xe máy',
                            child: Text('Xe máy giao hàng nhanh'),
                          ),
                          DropdownMenuItem(
                            value: 'Xe tải 500kg',
                            child: Text('Xe tải nhẹ 500kg'),
                          ),
                          DropdownMenuItem(
                            value: 'Xe bán tải',
                            child: Text('Xe bán tải / Van'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setDialogState(() => selectedVehicle = v);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: plateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Biển kiểm soát phương tiện',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: colorCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Màu sơn phương tiện',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (citizenCtrl.text.trim().isEmpty ||
                        plateCtrl.text.trim().isEmpty) {
                      return;
                    }
                    _store.registerOrUpdateDriverKyc(
                      fullName: _profileNameCtrl.text.trim().isNotEmpty
                          ? _profileNameCtrl.text.trim()
                          : _store.customerFullName,
                      phone: _profilePhoneCtrl.text.trim().isNotEmpty
                          ? _profilePhoneCtrl.text.trim()
                          : _store.customerPhone,
                      citizenId: citizenCtrl.text.trim(),
                      vehicleType: selectedVehicle,
                      licensePlate: plateCtrl.text.trim(),
                      vehicleColor: colorCtrl.text.trim().isNotEmpty
                          ? colorCtrl.text.trim()
                          : 'Xanh đen',
                    );
                    Navigator.of(dialogCtx).pop();
                    _rebuildCustomerUi(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Đã gửi hồ sơ Đối tác Tài xế (Trạng thái: Chờ duyệt) tới Admin!',
                        ),
                      ),
                    );
                  },
                  child: const Text('Gửi hồ sơ chờ Admin duyệt'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMerchantKycApplicationDialog(
    BuildContext context, {
    MerchantApplicantRecord? existing,
  }) {
    final storeNameCtrl = TextEditingController(
      text: existing?.storeName ?? '',
    );
    final taxCtrl = TextEditingController(
      text: existing?.taxCode ?? '',
    );
    final repCtrl = TextEditingController(
      text: existing?.representativeName ?? _profileNameCtrl.text.trim(),
    );
    final bankNameCtrl = TextEditingController(
      text: existing?.bankName ?? '',
    );
    final bankAccCtrl = TextEditingController(
      text: existing?.bankAccount ?? '',
    );
    String businessType = existing?.businessType ?? 'Hộ kinh doanh cá thể';

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Hồ sơ Đăng ký Đối tác Cửa hàng B2B (KYC)',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: storeNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Tên cửa hàng / Thương hiệu B2B',
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: businessType,
                        decoration: const InputDecoration(
                          labelText: 'Loại hình kinh doanh',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Hộ kinh doanh cá thể',
                            child: Text('Hộ kinh doanh cá thể'),
                          ),
                          DropdownMenuItem(
                            value: 'Công ty TNHH',
                            child: Text('Công ty TNHH'),
                          ),
                          DropdownMenuItem(
                            value: 'Công ty Cổ phần',
                            child: Text('Công ty Cổ phần'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setDialogState(() => businessType = v);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: taxCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Mã số thuế doanh nghiệp / Hộ KD',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: repCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Người đại diện pháp luật',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: bankNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Ngân hàng nhận đối soát COD',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: bankAccCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Số tài khoản ngân hàng',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (storeNameCtrl.text.trim().isEmpty ||
                        taxCtrl.text.trim().isEmpty) {
                      return;
                    }
                    _store.registerOrUpdateMerchantKyc(
                      ownerPhone: _profilePhoneCtrl.text.trim().isNotEmpty
                          ? _profilePhoneCtrl.text.trim()
                          : _store.customerPhone,
                      storeName: storeNameCtrl.text.trim(),
                      businessType: businessType,
                      taxCode: taxCtrl.text.trim(),
                      representativeName: repCtrl.text.trim(),
                      bankName: bankNameCtrl.text.trim(),
                      bankAccount: bankAccCtrl.text.trim(),
                    );
                    Navigator.of(dialogCtx).pop();
                    _rebuildCustomerUi(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Đã gửi hồ sơ Cửa hàng B2B (Trạng thái: Chờ duyệt) tới Admin!',
                        ),
                      ),
                    );
                  },
                  child: const Text('Gửi hồ sơ chờ Admin duyệt'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// UC42: Trung tâm Thông báo (Khớp 100% uc42_thong_bao_1791094562197.jpg)
  Widget _buildNotificationCenterView() {
    final items = _store.customerNotifications.where((n) {
      if (_notiFilter == 'Tất cả') return true;
      return n.category == _notiFilter;
    }).toList();

    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFF5B33E6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Thông báo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _store.markAllNotificationsAsRead();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Đã đánh dấu tất cả thông báo là đã đọc!',
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'Đánh dấu tất cả đã đọc',
                    style: TextStyle(
                      color: Color(0xFFDCEBFF),
                      fontSize: 12,
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
                Wrap(
                  spacing: 8,
                  children: ['Tất cả', 'Đơn hàng', 'Khuyến mãi', 'Hệ thống']
                      .map((cat) {
                    return ChoiceChip(
                      label: Text(cat),
                      selected: _notiFilter == cat,
                      onSelected: (_) => _rebuildCustomerUi(() => _notiFilter = cat),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 28,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F1E8),
                      border: Border.all(color: const Color(0xFF15131E)),
                    ),
                    child: const Center(
                      child: Text(
                        'Hiện chưa có thông báo mới trong mục này.',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4A4754),
                        ),
                      ),
                    ),
                  ),
                ...items.map((n) {
                  final isOrder = n.category == 'Đơn hàng';
                  final isPromo = n.category == 'Khuyến mãi';
                  final iconColor = isOrder
                      ? const Color(0xFF14B866)
                      : isPromo
                          ? const Color(0xFFFF5E83)
                          : const Color(0xFF5B33E6);
                  final iconData = isOrder
                      ? Icons.local_shipping_rounded
                      : isPromo
                          ? Icons.card_giftcard_rounded
                          : Icons.shield_outlined;

                  return InkWell(
                    onTap: () {
                      _store.markNotificationAsRead(n.id);
                      final match =
                          RegExp(r'#DH[0-9A-Za-z-]+').firstMatch(n.title);
                      if (n.title.toLowerCase().contains('khiếu nại') ||
                          n.title.contains('KN-')) {
                        if (match != null) {
                          _store.selectCustomerOrder(match.group(0)!);
                        }
                        _rebuildCustomerUi(() => _selectedScreenIndex = 9);
                      } else if (match != null) {
                        _store.selectCustomerOrder(match.group(0)!);
                        _rebuildCustomerUi(() => _selectedScreenIndex = 4);
                      } else if (n.category == 'Khuyến mãi') {
                        _rebuildCustomerUi(() => _selectedScreenIndex = 14);
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: !n.isRead
                            ? const Color(0xFFF5F1E8)
                            : Colors.white,
                        borderRadius: BorderRadius.all(Radius.zero),
                        border: Border.all(color: const Color(0xFF15131E)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: iconColor.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(iconData, color: iconColor, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  n.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${n.category} • ${n.timeAgo}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF4A4754),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!n.isRead)
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              width: 9,
                              height: 9,
                              decoration: const BoxDecoration(
                                color: Color(0xFF5B33E6),
                                shape: BoxShape.circle,
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
}
