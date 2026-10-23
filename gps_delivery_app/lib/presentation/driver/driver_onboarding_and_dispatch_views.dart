part of 'driver_subsystem_views.dart';

extension _DriverOnboardingAndDispatchViews on _DriverSubsystemEntryState {
  /// UC13: ĐĂNG KÝ TÀI KHOẢN TÀI XẾ (Khớp 100% uc13_dang_ky_tai_xe_1791014665242.jpg)
  Widget _buildDriverKycRegistrationView() {
    final docCount = _attachedKycDocs.length;
    final kycProgress = (0.34 + (docCount / 4.0) * 0.66).clamp(0.34, 1.0);
    final stepLabel = docCount >= 4 ? 'Bước 3/3 (Đủ 4/4)' : 'Bước 2/3 ($docCount/4)';
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            color: const Color(0xFF15131E),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'ĐĂNG KÝ TÀI KHOẢN TÀI XẾ',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    stepLabel,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          LinearProgressIndicator(
            value: kycProgress,
            minHeight: 5,
            backgroundColor: const Color(0xFFD1FAE5),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF14B866)),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '1. Thông tin cá nhân',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _drvNameCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Họ và tên'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _drvPhoneCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Số điện thoại'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _drvCitizenCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Số CCCD / CMND'),
                ),
                const SizedBox(height: 16),
                const Text(
                  '2. Thông tin phương tiện',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _vehicleType,
                        decoration:
                            const InputDecoration(labelText: 'Loại xe'),
                        items: ['Xe máy', 'Xe tải nhỏ', 'Xe Van']
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(
                                  v,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) _rebuildDriverUi(() => _vehicleType = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _drvPlateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Biển số xe',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  '3. Tải lên giấy tờ (Chụp ảnh)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildKycCameraBox('CCCD mặt trước')),
                    const SizedBox(width: 10),
                    Expanded(child: _buildKycCameraBox('CCCD mặt sau')),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildKycCameraBox('Giấy phép lái xe')),
                    const SizedBox(width: 10),
                    Expanded(child: _buildKycCameraBox('Đăng ký xe')),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF15131E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.zero),
                      ),
                    ),
                    onPressed: () {
                      final fName = _drvNameCtrl.text.trim();
                      final phone = _drvPhoneCtrl.text.trim();
                      final citizen = _drvCitizenCtrl.text.trim();
                      final plate = _drvPlateCtrl.text.trim();
                      if (fName.isEmpty ||
                          phone.isEmpty ||
                          citizen.isEmpty ||
                          plate.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Vui lòng điền đầy đủ Họ tên, SĐT, CCCD và Biển số xe trước khi gửi hồ sơ!',
                            ),
                          ),
                        );
                        return;
                      }
                      _store.registerOrUpdateDriverKyc(
                        fullName: fName,
                        phone: phone,
                        citizenId: citizen,
                        vehicleType: _vehicleType,
                        licensePlate: plate,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Đã gửi hồ sơ đăng ký Tài xế chờ duyệt thành công!',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text(
                      'GỬI HỒ SƠ CHỜ DUYỆT',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
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

  Widget _buildKycCameraBox(String label) {
    final isAttached = _attachedKycDocs.contains(label);
    return InkWell(
      borderRadius: BorderRadius.all(Radius.zero),
      onTap: () {
        _rebuildDriverUi(() {
          if (isAttached) {
            _attachedKycDocs.remove(label);
          } else {
            _attachedKycDocs.add(label);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: isAttached ? const Color(0xFFDCFCE7) : const Color(0xFFF5F1E8),
          borderRadius: BorderRadius.all(Radius.zero),
          border: Border.all(
            color: const Color(0xFF14B866),
            width: isAttached ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(
              isAttached
                  ? Icons.check_circle_rounded
                  : Icons.camera_alt_outlined,
              color: const Color(0xFF15131E),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              isAttached ? '$label (Đã đính kèm)' : label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF065F46),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Trang chủ Tài xế & Gạt trạng thái Online/Offline (Khớp 100% uc14_bat_tat_trang_thai_1791021276770.jpg)
  Widget _buildDriverHomeOnlineView() {
    final policy = GpsIntegrityValidator.resolvePolicy(
      batteryLevelPercent: _store.batteryPercent,
      isCharging: false,
    );
    final activeDrv = _store.activeDriverRecord ??
        (_store.drivers.isNotEmpty ? _store.drivers.first : null);
    final todayOrderCount = _store.orders
        .where(
          (o) =>
              o.status != OrderStatus.cancelled &&
              o.status != OrderStatus.failed &&
              o.status != OrderStatus.returning,
        )
        .length;
    final driverRating = activeDrv?.rating ?? 4.9;

    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thanh trạng thái Tài xế độc lập phía trên Bản đồ (không đè lên bản đồ)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: AppColors.ink, width: 1.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Animated3dIconBadge(
                      style: Icon3dStyle.scooterExpress,
                      size: 46,
                      showRadarPulse: _store.isDriverOnline,
                      isSelected: _store.isDriverOnline,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Xin chào, ${_store.activeDriverName}!',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: Color(0xFF15131E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _store.isDriverOnline
                                      ? const Color(0xFF14B866)
                                      : const Color(0xFF94A3B8),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  _store.isDriverOnline
                                      ? 'Đang Online - Sẵn sàng nhận đơn'
                                      : 'Đang Offline - Nghỉ ngơi',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _store.isDriverOnline
                                        ? const Color(0xFF14B866)
                                        : const Color(0xFF4A4754),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _store.isDriverOnline
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFF5F1E8),
                        borderRadius: const BorderRadius.all(Radius.zero),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _store.isDriverOnline ? 'ON' : 'OFF',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              color: _store.isDriverOnline
                                  ? const Color(0xFF14B866)
                                  : const Color(0xFF4A4754),
                            ),
                          ),
                          Switch(
                            value: _store.isDriverOnline,
                            activeThumbColor: const Color(0xFF14B866),
                            onChanged: (v) {
                              _store.setDriverOnlineStatus(v);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 6,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF5F1E8),
                          borderRadius: BorderRadius.all(Radius.zero),
                        ),
                        child: Text(
                          'Đơn hôm nay: $todayOrderCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF15131E),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 6,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF5F1E8),
                          borderRadius: BorderRadius.all(Radius.zero),
                        ),
                        child: Text(
                          'Ví: ${CurrencyFormatter.formatVnd(_store.driverWalletBalance)}',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF14B866),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 6,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF5F1E8),
                          borderRadius: BorderRadius.all(Radius.zero),
                        ),
                        child: Text(
                          'Đánh giá: ${driverRating.toStringAsFixed(1)}★',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFD97706),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Map3dPerspectiveWidget(
            height: 310,
            mode: MapViewMode.driverRadar,
            is3dMode: _store.isMap3dEnabled,
            speedKmh: _store.currentSpeedKmh,
            onToggle3d: _store.toggleMap3d,
            routePoints: _store.activeOrderRecord != null
                ? [
                    _store.activeDriverLocation,
                    _store.activeOrderRecord!.pickupLocation,
                    _store.activeOrderRecord!.dropoffLocation,
                  ]
                : [
                    _store.activeDriverLocation,
                    GeoPoint(
                      latitude: _store.activeDriverLocation.latitude + 0.0040,
                      longitude: _store.activeDriverLocation.longitude + 0.0048,
                    ),
                  ],
            nextTurnInstruction: _store.isDriverOnline
                ? 'Đang tìm đơn hàng quanh bạn • Chu kỳ GPS: ${policy.pingIntervalSeconds}s'
                : 'Bật trạng thái ON để nhận đơn hàng mới',
            roadName: _store.activeOrderRecord?.pickupAddress ??
                'Tọa độ GPS: ${_store.activeDriverLocation.latitude.toStringAsFixed(4)}, ${_store.activeDriverLocation.longitude.toStringAsFixed(4)}',
          ),
          Builder(
            builder: (context) {
              final activeOrd = _store.activeOrderRecord;
              if (!_store.isDriverOnline) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  color: AppColors.paper,
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Bạn đang ở chế độ Nghỉ ngơi (Offline). Bật trực tuyến để hệ thống tự động phát cuốc xe gần bạn.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF14B866),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _store.setDriverOnlineStatus(true),
                        icon: const Icon(
                          Icons.power_settings_new_rounded,
                          size: 18,
                        ),
                        label: const Text('BẬT ONLINE NGAY'),
                      ),
                    ],
                  ),
                );
              }

              if (activeOrd != null &&
                  activeOrd.status == OrderStatus.searching) {
                final estNet =
                    (activeOrd.deliveryFee + activeOrd.surchargeFee) * 0.80;
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFDCFCE7),
                    border: Border(
                      top: BorderSide(color: AppColors.ink, width: 1.5),
                    ),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CÓ ĐƠN HÀNG MỚI QUANH BẠN • ${activeOrd.trackingCode} (Thu nhập: ${CurrencyFormatter.formatVnd(estNet)})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: Color(0xFF166534),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Lấy: ${activeOrd.pickupAddress} → Giao: ${activeOrd.dropoffAddress}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.ink,
                              fontWeight: FontWeight.w600,
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
                              backgroundColor: const Color(0xFF14B866),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () =>
                                _rebuildDriverUi(() => _selectedScreenIndex = 2),
                            icon: const Icon(
                              Icons.notifications_active_outlined,
                              size: 18,
                            ),
                            label: const Text('Xem & Nhận đơn (28s)'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }

              if (activeOrd != null &&
                  activeOrd.status != OrderStatus.delivered &&
                  activeOrd.status != OrderStatus.cancelled) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: AppColors.paper,
                    border: Border(
                      top: BorderSide(color: AppColors.ink, width: 1.5),
                    ),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CUỐC XE ĐANG THỰC HIỆN: ${activeOrd.trackingCode} (${activeOrd.status.displayName})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Điểm giao: ${activeOrd.dropoffAddress} • Khách: ${activeOrd.recipientName}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () =>
                                _rebuildDriverUi(() => _selectedScreenIndex = 3),
                            icon: const Icon(
                              Icons.navigation_outlined,
                              size: 18,
                            ),
                            label: const Text('Điều hướng GPS'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () =>
                                _rebuildDriverUi(() => _selectedScreenIndex = 5),
                            icon: const Icon(
                              Icons.fact_check_outlined,
                              size: 18,
                            ),
                            label: const Text('Xác nhận POD'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }

              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  /// UC15: Nhận thông báo đơn hàng mới (Khớp 100% uc15_nhan_tu_choi_don_1791021299473.jpg)
  Widget _buildIncomingOrderPopupView() {
    final searchingOrders = _store.orders
        .where((o) => o.status == OrderStatus.searching)
        .toList();
    final targetOrder = searchingOrders.isNotEmpty
        ? searchingOrders.first
        : (_store.activeOrderRecord ?? _store.orders.first);
    final rankedCandidates = SmartDispatchEngine.rankDriversForPickup(
      pickupLocation: targetOrder.pickupLocation,
      drivers: _store.drivers,
      excludedDriverIds: _rejectedDriverIds,
    );
    final topCandidate =
        rankedCandidates.isNotEmpty ? rankedCandidates.first : null;
    final isTimerRunning = _dispatchCountdownTimer?.isActive ?? false;
    final expectedNetDriverEarning =
        (targetOrder.deliveryFee + targetOrder.surchargeFee) * 0.80;
    final isNewSearching = targetOrder.status == OrderStatus.searching;

    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.all(Radius.zero),
                        ),
                        child: Text(
                          '${targetOrder.serviceType.displayName.toUpperCase()} • ${(targetOrder.distanceMeters / 1000).toStringAsFixed(1)} KM',
                          style: const TextStyle(
                            color: Color(0xFF14B866),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isNewSearching
                            ? 'ĐƠN HÀNG MỚI!'
                            : 'CUỐC XE ${targetOrder.trackingCode} (${targetOrder.status.displayName})',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF15131E),
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: _toggleDispatchTimer,
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: _countdownSeconds / 28.0,
                          strokeWidth: 5,
                          backgroundColor: const Color(0xFF15131E),
                          color: isTimerRunning
                              ? AppColors.danger
                              : const Color(0xFF14B866),
                        ),
                        Text(
                          '${_countdownSeconds}s',
                          style: const TextStyle(
                            color: Color(0xFF14B866),
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (topCandidate != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F1E8),
                  borderRadius: BorderRadius.all(Radius.zero),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: [
                    const Animated3dIconBadge(
                      style: Icon3dStyle.gpsPinRadar,
                      size: 44,
                      showRadarPulse: true,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ứng viên #1 (Bán kính ${topCandidate.searchRadiusTierMeters ~/ 1000}km): ${topCandidate.driver.fullName} (${topCandidate.driver.licensePlate}) • Điểm Trọng số: ${topCandidate.totalScore.toStringAsFixed(3)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF166534),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _toggleDispatchTimer,
                      child: Text(isTimerRunning ? 'Tạm dừng' : 'Chạy 28s'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F1E8),
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: const Color(0xFF14B866), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        'Thu nhập dự kiến (80%): ${CurrencyFormatter.formatVnd(expectedNetDriverEarning)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: Color(0xFF14B866),
                        ),
                      ),
                      Text(
                        'Khoảng cách: ${(targetOrder.distanceMeters / 1000).toStringAsFixed(1)} km',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF15131E),
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  Text('• Điểm lấy hàng: ${targetOrder.pickupAddress}'),
                  const SizedBox(height: 4),
                  Text('• Điểm giao hàng: ${targetOrder.dropoffAddress}'),
                  const SizedBox(height: 4),
                  Text(
                    '• Ứng tiền COD: ${CurrencyFormatter.formatVnd(targetOrder.codAmount)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: isNewSearching
                        ? () {
                            _rebuildDriverUi(() {
                              _countdownSeconds = 28;
                              _reassignToNextCandidate();
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Đã từ chối cuốc xe. Hệ thống tự động chuyển đơn cho tài xế phù hợp tiếp theo.',
                                ),
                              ),
                            );
                          }
                        : null,
                    child: const Text('Từ chối (Chuyển tiếp)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF14B866),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: () {
                      _dispatchCountdownTimer?.cancel();
                      if (!_store.isDriverOnline) {
                        _store.setDriverOnlineStatus(true);
                      }
                      _store.selectDriverOrder(targetOrder.trackingCode);
                      if (isNewSearching) {
                        final currentActiveDrv = _store.activeDriverRecord;
                        final assignedName = (currentActiveDrv != null &&
                                currentActiveDrv.approvalStatus != 'Từ chối')
                            ? currentActiveDrv.fullName
                            : topCandidate?.driver.fullName;
                        final assignedPlate = (currentActiveDrv != null &&
                                currentActiveDrv.approvalStatus != 'Từ chối')
                            ? currentActiveDrv.licensePlate
                            : topCandidate?.driver.licensePlate;
                        _store.driverAcceptOrder(
                          targetOrder.trackingCode,
                          customDriverName: assignedName,
                          customPlate: assignedPlate,
                        );
                      }
                      _podRecipientCtrl.text = targetOrder.recipientName;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isNewSearching
                                ? 'Đã nhận cuốc xe ${targetOrder.trackingCode} thành công!'
                                : 'Đang mở điều hướng cho cuốc xe ${targetOrder.trackingCode} (${targetOrder.status.displayName}).',
                          ),
                        ),
                      );
                      _rebuildDriverUi(() => _selectedScreenIndex = 3);
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(
                      isNewSearching ? 'NHẬN ĐƠN NGAY' : 'ĐIỀU HƯỚNG CUỐC XE',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// UC16: Điều hướng 3D GPS Turn-by-Turn tới điểm lấy/giao hàng (Khớp 100% uc16_dieu_huong_gps_1791021319175.jpg)
  Widget _buildTurnByTurnNavigationView() {
    final activeOrder = _store.activeOrderRecord ?? _store.orders.first;
    final remMeters = _store.distanceFromDriverToDropoffMeters();
    final isHeadingToPickup = activeOrder.status == OrderStatus.searching ||
        activeOrder.status == OrderStatus.accepted ||
        activeOrder.status == OrderStatus.arrivingPickup;
    final targetAddress = isHeadingToPickup
        ? activeOrder.pickupAddress
        : activeOrder.dropoffAddress;
    final nextTurnMeters = (remMeters * 0.25).round().clamp(40, 600);
    final navHeadline = remMeters <= 100
        ? 'Đã tới khu vực đích ($targetAddress)'
        : 'Rẽ hướng ${_store.activeDriverBearing.toStringAsFixed(0)}° sau $nextTurnMeters m tới $targetAddress';
    final navSubline =
        'Chặng: ${isHeadingToPickup ? "Tới điểm lấy hàng [A]" : "Tới điểm giao hàng [B]"} • Còn ${(remMeters / 1000).toStringAsFixed(2)} km';
    final shouldMaskPhone = activeOrder.status == OrderStatus.delivered ||
        activeOrder.status == OrderStatus.cancelled;
    final displayPhone = SecurityAndBarcodeUtils.maskPhoneNumber(
      activeOrder.recipientPhone,
      shouldMask: shouldMaskPhone,
    );

    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dark Navy Turn-by-Turn Instruction Banner (#0F172A)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFF15131E),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF14B866),
                    borderRadius: BorderRadius.all(Radius.zero),
                  ),
                  child: Icon(
                    remMeters <= 100
                        ? Icons.flag_rounded
                        : Icons.turn_right_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        navHeadline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        navSubline,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Map3dPerspectiveWidget(
                  height: 300,
                  mode: MapViewMode.driverTurnByTurn,
                  showTopBanner: false,
                  is3dMode: _store.isMap3dEnabled,
                  speedKmh: _store.currentSpeedKmh,
                  onToggle3d: _store.toggleMap3d,
                  progressFraction: _store.routeProgressStep / 10.0,
                  routePoints: _store.activeRoutePolyline.length >= 2
                      ? _store.activeRoutePolyline
                      : <GeoPoint>[
                          activeOrder.pickupLocation,
                          _store.activeDriverLocation,
                          activeOrder.dropoffLocation,
                        ],
                  pickupLabel: 'Lấy: ${activeOrder.pickupAddress}',
                  dropoffLabel: 'Giao: ${activeOrder.dropoffAddress}',
                  nextTurnInstruction: navHeadline,
                  roadName:
                      'Còn ${(remMeters / 1000).toStringAsFixed(2)} km • Góc hướng: ${_store.activeDriverBearing.toStringAsFixed(0)}°',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Khách nhận: ${activeOrder.recipientName} ($displayPhone)',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _store.stepDriverAlongRoute(),
                      icon: const Icon(Icons.my_location, size: 16),
                      label: const Text('Cập nhật vị trí'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14B866),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _rebuildDriverUi(() => _selectedScreenIndex = 4),
                      icon: const Icon(Icons.flag_rounded, size: 16),
                      label: const Text('Đã đến nơi / Cập nhật tiến độ'),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                      ),
                      onPressed: () => _rebuildDriverUi(() => _selectedScreenIndex = 5),
                      icon: const Icon(Icons.camera_alt_outlined, size: 16),
                      label: const Text('Xác nhận POD & OTP'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _rebuildDriverUi(() => _selectedScreenIndex = 7),
                      icon: const Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: AppColors.danger,
                      ),
                      label: const Text('Báo cáo sự cố'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final msg = await _store.acquireRealHardwareGps();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(msg)),
                        );
                      },
                      icon: const Icon(Icons.satellite_alt, size: 16),
                      label: const Text(
                        'Định vị GPS Thiết bị',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final msg =
                            await _store.syncLiveOsrmRouteForActiveOrder();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(msg)),
                        );
                      },
                      icon: const Icon(Icons.alt_route, size: 16),
                      label: const Text(
                        'Cập nhật lộ trình tối ưu',
                        style: TextStyle(fontSize: 12),
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
  }

  /// UC17: Cập nhật tiến độ chuyến giao (Khớp 100% uc17_cap_nhat_trang_thai_pod_1791021350773.jpg)
  Widget _buildTripStepProgressView() {
    final ord = _store.activeOrderRecord ?? _store.orders.first;
    final isNormalFlow = ord.status.index >= OrderStatus.accepted.index &&
        ord.status.index <= OrderStatus.delivered.index;
    final isTerminal = ord.status == OrderStatus.delivered ||
        ord.status == OrderStatus.cancelled;
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF14B866),
                borderRadius: BorderRadius.all(Radius.zero),
              ),
              child: Text(
                'Cập nhật trạng thái đơn ${ord.trackingCode}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_store.orders.length > 1) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _store.orders.map((o) {
                  final selected = o.trackingCode == ord.trackingCode;
                  final statusText = o.paymentStatus == 'RETURNED'
                      ? 'Đã hoàn kho'
                      : o.status.displayName;
                  return ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${o.trackingCode} ($statusText)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : const Color(0xFF15131E),
                      ),
                    ),
                    selected: selected,
                    selectedColor: const Color(0xFF14B866),
                    onSelected: (_) => _rebuildDriverUi(
                      () => _store.selectDriverOrder(o.trackingCode),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Mã vận đơn: ${ord.trackingCode} • Trạng thái hiện tại: ${ord.status.displayName}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF14B866),
              ),
            ),
            const SizedBox(height: 10),
            _stepTile(
              'Bước 1: Đã nhận đơn (ACCEPTED)',
              isNormalFlow && ord.status.index >= OrderStatus.accepted.index,
            ),
            _stepTile(
              'Bước 2: Đã đến điểm lấy hàng (ARRIVING_PICKUP)',
              isNormalFlow &&
                  ord.status.index >= OrderStatus.arrivingPickup.index,
            ),
            _stepTile(
              'Bước 3: Đã lấy hàng & Đang giao (IN_TRANSIT)',
              isNormalFlow && ord.status.index >= OrderStatus.inTransit.index,
            ),
            _stepTile(
              'Bước 4: Đã giao hàng thành công (DELIVERED + POD)',
              ord.status == OrderStatus.delivered,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF14B866),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: isTerminal
                        ? null
                        : () {
                            if (ord.status == OrderStatus.inTransit) {
                              _rebuildDriverUi(() => _selectedScreenIndex = 5);
                            } else if (ord.status == OrderStatus.searching ||
                                ord.status == OrderStatus.draft) {
                              _store.driverAcceptOrder(ord.trackingCode);
                            } else {
                              _store.driverAdvanceOrderStatus(ord.trackingCode);
                            }
                          },
                    icon: const Icon(Icons.double_arrow),
                    label: Text(
                      ord.status == OrderStatus.delivered
                          ? 'Đã hoàn tất giao hàng'
                          : ord.status == OrderStatus.cancelled
                              ? 'Đơn hàng đã hủy'
                              : ord.status == OrderStatus.failed
                                  ? 'Giao lại chuyến hàng (IN_TRANSIT)'
                                  : ord.status == OrderStatus.returning
                                      ? 'Xác nhận hoàn trả về Kho'
                                      : ord.status == OrderStatus.inTransit
                                          ? 'Chuyển sang Xác nhận POD & OTP'
                                          : 'Vuốt chuyển bước tiếp theo',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepTile(String label, bool completed) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        completed ? Icons.check_circle : Icons.radio_button_unchecked,
        color: completed ? const Color(0xFF14B866) : AppColors.textSecondary,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: completed ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }

  /// UC17: Xác nhận giao hàng thành công (POD Photo + OTP 4 số + Kiểm tra <= 100m)
  Widget _buildPodConfirmationView() {
    final ord = _store.activeOrderRecord ?? _store.orders.first;
    final distMeters = _store.distanceFromDriverToDropoffMeters();
    final isWithin100m = distMeters <= 100.0;
    final isOrderClosed = ord.status == OrderStatus.delivered ||
        ord.status == OrderStatus.cancelled;

    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF14B866),
                borderRadius: BorderRadius.all(Radius.zero),
              ),
              child: Text(
                'Xác nhận Giao hàng POD & Mã OTP (${ord.trackingCode})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            PodGpsWatermarkPhotoCard(
              driverLocation: _store.activeDriverLocation,
              recipientName: _podRecipientCtrl.text,
              otpCode: _podOtpCtrl.text,
              distanceToDropoffMeters: distMeters,
            ),
            if (!isWithin100m) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    '⚠️ Yêu cầu vị trí: Tài xế phải cách điểm giao <= 100m mới được phép xác nhận hoàn tất POD.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        _store.stepDriverAlongRoute(snapToDropoff: true),
                    icon: const Icon(Icons.near_me, size: 16),
                    label: const Text('Tiến vào vùng < 100m'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _podRecipientCtrl,
                    onChanged: (_) => _rebuildDriverUi(() {}),
                    decoration:
                        const InputDecoration(labelText: 'Tên người thực nhận'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _podOtpCtrl,
                    maxLength: 4,
                    onChanged: (_) => _rebuildDriverUi(() {}),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Mã OTP xác nhận (4 chữ số)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isOrderClosed
                      ? AppColors.textSecondary
                      : isWithin100m
                          ? const Color(0xFF14B866)
                          : AppColors.textSecondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
                onPressed: isOrderClosed
                    ? null
                    : () async {
                        final recName = _podRecipientCtrl.text.trim();
                        if (recName.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Vui lòng nhập tên người thực nhận trước khi xác nhận POD!',
                              ),
                            ),
                          );
                          return;
                        }
                        final otpInput = _podOtpCtrl.text.trim();
                        if (!RegExp(r'^[0-9]{4}$').hasMatch(otpInput)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Vui lòng nhập đúng mã OTP nhận hàng gồm 4 chữ số!',
                              ),
                            ),
                          );
                          return;
                        }
                        if (!isWithin100m) {
                          _store.stepDriverAlongRoute(snapToDropoff: true);
                        }
                        final svgFilePath = await SecurityAndBarcodeUtils
                            .exportPodWatermarkToSvgFile(
                          orderCode: ord.trackingCode,
                          recipientName: recName,
                          otpCode: otpInput,
                          driverLocation: _store.activeDriverLocation,
                          distanceMeters:
                              _store.distanceFromDriverToDropoffMeters(),
                        );
                        while (ord.status != OrderStatus.inTransit &&
                            ord.status != OrderStatus.delivered &&
                            ord.status != OrderStatus.cancelled) {
                          _store.driverAdvanceOrderStatus(ord.trackingCode);
                        }
                        _store.driverAdvanceOrderStatus(
                          ord.trackingCode,
                          podNote:
                              'POD: $recName • OTP $otpInput • GPS (${_store.activeDriverLocation.latitude.toStringAsFixed(4)}, ${_store.activeDriverLocation.longitude.toStringAsFixed(4)}) • Tệp: $svgFilePath',
                        );
                        _podOtpCtrl.clear();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Hoàn tất đơn ${ord.trackingCode}! Đã lưu tệp bằng chứng POD tại: $svgFilePath',
                            ),
                          ),
                        );
                        _rebuildDriverUi(() => _selectedScreenIndex = 6);
                      },
                icon: const Icon(Icons.task_alt),
                label: Text(
                  ord.status == OrderStatus.delivered
                      ? 'ĐƠN HÀNG ĐÃ HOÀN TẤT POD'
                      : ord.status == OrderStatus.cancelled
                          ? 'ĐƠN HÀNG ĐÃ HỦY'
                          : isWithin100m
                              ? 'XÁC NHẬN ĐÃ GIAO & XUẤT TỆP BẰNG CHỨNG POD'
                              : 'DI CHUYỂN TỚI ĐIỂM GIAO (< 100M) & XUẤT BẰNG CHỨNG POD',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
