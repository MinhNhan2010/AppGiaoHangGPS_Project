part of 'customer_subsystem_views.dart';

extension _CustomerOrderAndPricingViews on _CustomerSubsystemEntryState {
  /// UC03 & UC04: Tạo đơn hàng mới & Chọn dịch vụ 2x2 Grid (Khớp 100% uc03 & uc04)
  Widget _buildCreateOrderView() {
    final pickupSuggestions =
        SmartDispatchEngine.searchAddressSuggestions(_pickupCtrl.text);
    final dropoffSuggestions =
        SmartDispatchEngine.searchAddressSuggestions(_dropoffCtrl.text);
    final pPt = SmartDispatchEngine.resolveAddressToCoordinate(
      _pickupCtrl.text,
      fallback: const GeoPoint(latitude: 10.7769, longitude: 106.6953),
    );
    final dPt = SmartDispatchEngine.resolveAddressToCoordinate(
      _dropoffCtrl.text,
      fallback: const GeoPoint(latitude: 10.7550, longitude: 106.6750),
    );
    final rawAirMeters = GeoMath.distanceMeters(pPt, dPt);
    final isDefaultRoute = _pickupCtrl.text.contains('Phố Huế') &&
        _dropoffCtrl.text.contains('Lê Trọng Tấn');
    final resolvedDistMeters = _osrmDistMeters ??
        (isDefaultRoute
            ? 14500
            : (rawAirMeters * 1.28).round().clamp(1500, 45000));
    final resolvedDurSec = _osrmDurationSec ??
        (isDefaultRoute
            ? 2700
            : ((resolvedDistMeters / 1000.0) * 180).round());
    final estDistKm = (resolvedDistMeters / 1000.0).clamp(0.5, 65.0);
    final estDurationMin = (resolvedDurSec / 60.0).round().clamp(5, 240);
    final previewRoutePoints =
        (_osrmPreviewPoints != null && _osrmPreviewPoints!.length >= 2)
            ? _osrmPreviewPoints!
            : SmartDispatchEngine.generateRoutePolyline(
                pPt,
                dPt,
                segments: 10,
              );

    Widget buildLeftFormColumn() {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.ink, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: AppColors.ink,
              offset: Offset(4, 4),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tạo đơn hàng mới',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Nhập lộ trình lấy/giao và thông tin kiện hàng',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                  ),
                  onPressed: () =>
                      _rebuildCustomerUi(() => _selectedScreenIndex = 1),
                  icon: const Icon(Icons.bookmarks_outlined, size: 15),
                  label: const Text('Sổ địa chỉ'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '1. Lộ trình lấy & giao hàng',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pickupCtrl,
              decoration: InputDecoration(
                labelText: 'Điểm lấy hàng (Người gửi)',
                prefixIcon: const Icon(
                  Icons.radio_button_checked_rounded,
                  color: AppColors.violet,
                  size: 18,
                ),
                suffixIcon: IconButton(
                  tooltip: 'Tra cứu điểm lấy thực tế từ OpenStreetMap',
                  onPressed: () async {
                    final results = await SmartDispatchEngine
                        .fetchLiveNominatimSuggestions(_pickupCtrl.text);
                    if (!mounted) return;
                    _rebuildCustomerUi(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã tìm thấy ${results.length} địa điểm lấy hàng cho "${_pickupCtrl.text}"',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.travel_explore_rounded,
                    color: AppColors.violet,
                  ),
                ),
              ),
              onChanged: (_) => _rebuildCustomerUi(() {
                _osrmPreviewPoints = null;
                _osrmDistMeters = null;
                _osrmDurationSec = null;
              }),
            ),
            if (_store.customerSavedAddresses.isNotEmpty ||
                pickupSuggestions.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ..._store.customerSavedAddresses.map((addr) {
                    return ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(
                        Icons.bookmark_rounded,
                        size: 13,
                        color: AppColors.violet,
                      ),
                      label: Text(
                        'Lấy tại: ${addr.label}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () => _rebuildCustomerUi(() {
                        _pickupCtrl.text = addr.fullAddress;
                        _osrmPreviewPoints = null;
                        _osrmDistMeters = null;
                        _osrmDurationSec = null;
                      }),
                    );
                  }),
                  ...pickupSuggestions.take(2).map((place) {
                    return ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(
                        Icons.my_location_rounded,
                        size: 13,
                        color: AppColors.violet,
                      ),
                      label: Text(
                        place.title,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onPressed: () => _rebuildCustomerUi(() {
                        _pickupCtrl.text = place.fullAddress;
                        _osrmPreviewPoints = null;
                        _osrmDistMeters = null;
                        _osrmDurationSec = null;
                      }),
                    );
                  }),
                ],
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _dropoffCtrl,
              decoration: InputDecoration(
                labelText: 'Điểm giao hàng (Người nhận)',
                prefixIcon: const Icon(
                  Icons.location_on,
                  color: AppColors.pink,
                  size: 20,
                ),
                suffixIcon: IconButton(
                  tooltip: 'Tra cứu địa chỉ thực tế từ OpenStreetMap',
                  onPressed: () async {
                    final results = await SmartDispatchEngine
                        .fetchLiveNominatimSuggestions(_dropoffCtrl.text);
                    if (!mounted) return;
                    _rebuildCustomerUi(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã tìm thấy ${results.length} địa điểm thực tế cho "${_dropoffCtrl.text}"',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.travel_explore_rounded,
                    color: AppColors.violet,
                  ),
                ),
              ),
              onChanged: (_) => _rebuildCustomerUi(() {
                _osrmPreviewPoints = null;
                _osrmDistMeters = null;
                _osrmDurationSec = null;
              }),
            ),
            if (_store.customerSavedAddresses.isNotEmpty ||
                dropoffSuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ..._store.customerSavedAddresses.map((addr) {
                    return ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(
                        Icons.bookmark_border_rounded,
                        size: 13,
                        color: AppColors.pink,
                      ),
                      label: Text(
                        'Giao tới: ${addr.label}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () => _rebuildCustomerUi(() {
                        _dropoffCtrl.text = addr.fullAddress;
                        _osrmPreviewPoints = null;
                        _osrmDistMeters = null;
                        _osrmDurationSec = null;
                      }),
                    );
                  }),
                  ...dropoffSuggestions.take(3).map((place) {
                    return ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(
                        Icons.place,
                        size: 13,
                        color: AppColors.pink,
                      ),
                      label: Text(
                        place.title,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onPressed: () => _rebuildCustomerUi(() {
                        _dropoffCtrl.text = place.fullAddress;
                        _osrmPreviewPoints = null;
                        _osrmDistMeters = null;
                        _osrmDurationSec = null;
                      }),
                    );
                  }),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              '2. Thông tin người nhận',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _recipientNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Họ tên người nhận',
                      prefixIcon: Icon(Icons.person_outline, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _recipientPhoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại nhận',
                      prefixIcon: Icon(Icons.phone_outlined, size: 18),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '3. Đặc tính kiện hàng',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _pkgCategory,
              decoration: const InputDecoration(
                labelText: 'Phân loại hàng hóa',
                prefixIcon: Icon(Icons.inventory_2_outlined, size: 18),
              ),
              items: const [
                'Quần áo & Thời trang',
                'Tài liệu & Hợp đồng',
                'Thực phẩm & Đồ uống',
                'Điện tử & Hàng dễ vỡ',
              ]
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(c, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) _rebuildCustomerUi(() => _pkgCategory = v);
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _weightCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Trọng lượng (kg)',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _dimCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Kích thước (D x R x C)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pkgDescCtrl,
              decoration: const InputDecoration(
                labelText: 'Ghi chú cho tài xế khi lấy/giao',
                prefixIcon: Icon(Icons.notes_rounded, size: 18),
              ),
            ),
          ],
        ),
      );
    }

    Widget buildRightMapAndServiceColumn() {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.ink, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: AppColors.ink,
              offset: Offset(4, 4),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Bản đồ Lộ trình 3D & Dịch vụ',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final res = await SmartDispatchEngine.fetchLiveOsrmRoute(
                      pPt,
                      dPt,
                    );
                    if (!mounted) return;
                    if (res.polylinePoints.length >= 2) {
                      _store.activeRoutePolyline = res.polylinePoints;
                    }
                    _rebuildCustomerUi(() {
                      if (res.polylinePoints.length >= 2) {
                        _osrmPreviewPoints = res.polylinePoints;
                      }
                      _osrmDistMeters = res.distanceMeters;
                      _osrmDurationSec = res.durationSeconds;
                    });
                    final km = (res.distanceMeters / 1000.0).toStringAsFixed(1);
                    final mins =
                        (res.durationSeconds / 60).round().clamp(5, 240);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã cập nhật lộ trình thực tế: $km km (~$mins phút, ${res.polylinePoints.length} điểm tọa độ)',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.alt_route, size: 15),
                  label: const Text(
                    'Cập nhật tuyến',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.ink, width: 1.4),
              ),
              child: Map3dPerspectiveWidget(
                height: 215,
                mode: MapViewMode.customerPreview,
                is3dMode: _store.isMap3dEnabled,
                speedKmh: _store.currentSpeedKmh,
                onToggle3d: _store.toggleMap3d,
                progressFraction: 0.35,
                routePoints: previewRoutePoints,
                pickupLabel: '[A] Điểm lấy',
                dropoffLabel: '[B] Điểm giao',
                nextTurnInstruction:
                    'Quãng đường: ${estDistKm.toStringAsFixed(1)} km • Dự kiến ~$estDurationMin phút',
                roadName: (_pickupCtrl.text.trim().isEmpty &&
                        _dropoffCtrl.text.trim().isEmpty)
                    ? 'Chưa chọn lộ trình lấy & giao hàng'
                    : '${_pickupCtrl.text.trim().isEmpty ? "Chưa chọn điểm lấy" : _pickupCtrl.text.trim()} → ${_dropoffCtrl.text.trim().isEmpty ? "Chưa chọn điểm giao" : _dropoffCtrl.text.trim()}',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Chọn gói dịch vụ giao hàng',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ),
                Animated3dIconBadge(
                  style: _selectedService == DeliveryServiceType.express30m
                      ? Icon3dStyle.scooterExpress
                      : _selectedService == DeliveryServiceType.standard
                          ? Icon3dStyle.parcelBox
                          : Icon3dStyle.gpsPinRadar,
                  size: 36,
                  showRadarPulse: false,
                  isSelected: true,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildUc04ServiceCard(
                    title: 'Giao nhanh (Express)',
                    eta: 'Siêu tốc 30 phút',
                    priceLabel:
                        'Từ ${CurrencyFormatter.formatVnd(_store.baseFareConfig * 1.4)}',
                    icon: Icons.bolt_rounded,
                    iconColor: AppColors.pink,
                    selected: !_isScheduledDelivery &&
                        _selectedService == DeliveryServiceType.express30m,
                    onTap: () => _rebuildCustomerUi(() {
                      _isScheduledDelivery = false;
                      _selectedService = DeliveryServiceType.express30m;
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildUc04ServiceCard(
                    title: 'Giao tiêu chuẩn',
                    eta: 'Trong 2 giờ',
                    priceLabel:
                        'Từ ${CurrencyFormatter.formatVnd(_store.baseFareConfig)}',
                    icon: Icons.local_shipping_rounded,
                    iconColor: AppColors.violet,
                    selected: !_isScheduledDelivery &&
                        _selectedService == DeliveryServiceType.standard,
                    onTap: () => _rebuildCustomerUi(() {
                      _isScheduledDelivery = false;
                      _selectedService = DeliveryServiceType.standard;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildUc04ServiceCard(
                    title: 'Giao tiết kiệm',
                    eta: 'Trong 4 giờ',
                    priceLabel:
                        'Từ ${CurrencyFormatter.formatVnd(_store.baseFareConfig * 0.8)}',
                    icon: Icons.savings_rounded,
                    iconColor: AppColors.success,
                    selected: !_isScheduledDelivery &&
                        _selectedService == DeliveryServiceType.saving,
                    onTap: () => _rebuildCustomerUi(() {
                      _isScheduledDelivery = false;
                      _selectedService = DeliveryServiceType.saving;
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildUc04ServiceCard(
                    title: 'Đặt lịch hẹn giờ',
                    eta: _isScheduledDelivery
                        ? 'Khung: $_scheduledDeliverySlot'
                        : 'Chọn khung giờ',
                    priceLabel:
                        'Từ ${CurrencyFormatter.formatVnd(_store.baseFareConfig)}',
                    icon: Icons.event_available_rounded,
                    iconColor: AppColors.violet,
                    selected: _isScheduledDelivery,
                    onTap: () => _rebuildCustomerUi(() {
                      _isScheduledDelivery = true;
                      _selectedService = DeliveryServiceType.standard;
                    }),
                  ),
                ),
              ],
            ),
            if (_isScheduledDelivery) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: const [
                  '09:00 - 11:00',
                  '13:00 - 15:00',
                  '15:00 - 17:00',
                  '18:00 - 20:00',
                ].map((slot) {
                  final isSlotSelected = _scheduledDeliverySlot == slot;
                  return ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      slot,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: isSlotSelected ? Colors.white : AppColors.ink,
                      ),
                    ),
                    selected: isSlotSelected,
                    selectedColor: AppColors.violet,
                    onSelected: (_) =>
                        _rebuildCustomerUi(() => _scheduledDeliverySlot = slot),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.violet,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  if (!_validateOrderFormInputs()) return;
                  _rebuildCustomerUi(() => _selectedScreenIndex = 3);
                },
                icon: const Icon(Icons.receipt_long_rounded, size: 18),
                label: const Text(
                  'XEM CHI TIẾT CƯỚC PHÍ & ĐẶT ĐƠN',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 740) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: buildLeftFormColumn()),
              const SizedBox(width: 20),
              Expanded(flex: 5, child: buildRightMapAndServiceColumn()),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildLeftFormColumn(),
            const SizedBox(height: 16),
            buildRightMapAndServiceColumn(),
          ],
        );
      },
    );
  }

  bool _validateOrderFormInputs() {
    if (_pickupCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập Địa chỉ lấy hàng (Điểm đi)!'),
        ),
      );
      return false;
    }
    if (_dropoffCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập Địa chỉ giao hàng (Điểm đến)!'),
        ),
      );
      return false;
    }
    if (_recipientNameCtrl.text.trim().isEmpty ||
        _recipientPhoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập đầy đủ Họ tên và SĐT người nhận!'),
        ),
      );
      return false;
    }
    return true;
  }

  Widget _buildUc04ServiceCard({
    required String title,
    required String eta,
    required String priceLabel,
    required IconData icon,
    required Color iconColor,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.all(Radius.zero),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF5F1E8) : Colors.white,
          borderRadius: BorderRadius.all(Radius.zero),
          border: Border.all(
            color: selected ? const Color(0xFF5B33E6) : const Color(0xFF15131E),
            width: selected ? 2.0 : 1.0,
          ),
        ),
        child: Stack(
          children: [
            if (selected)
              const Positioned(
                top: 0,
                right: 0,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: Color(0xFFFF5E83),
                  child: Icon(Icons.check, size: 13, color: Colors.white),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.all(Radius.zero),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: Color(0xFF15131E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  eta,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF4A4754),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  priceLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: selected
                        ? const Color(0xFFFF5E83)
                        : const Color(0xFF5B33E6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// UC05, UC11 & UC07: Xem ước tính chi phí, Mã giảm giá & Thanh toán đơn hàng
  Widget _buildPricingAndVoucherView() {
    final pickupPt = SmartDispatchEngine.resolveAddressToCoordinate(
      _pickupCtrl.text,
      fallback: const GeoPoint(latitude: 10.7769, longitude: 106.6953),
    );
    final dropoffPt = SmartDispatchEngine.resolveAddressToCoordinate(
      _dropoffCtrl.text,
      fallback: const GeoPoint(latitude: 10.7550, longitude: 106.6750),
    );
    final rawAirMeters = GeoMath.distanceMeters(pickupPt, dropoffPt);
    final isDefaultRoute = _pickupCtrl.text.contains('Phố Huế') &&
        _dropoffCtrl.text.contains('Lê Trọng Tấn');
    final distMeters = _osrmDistMeters ??
        (isDefaultRoute
            ? 14500
            : (rawAirMeters * 1.28).round().clamp(1500, 45000));
    final durationSec = _osrmDurationSec ??
        (isDefaultRoute
            ? 2700
            : ((distMeters / 1000.0) * 180).round());

    double geofenceFee = 0;
    for (final z in _store.geofenceZones) {
      if (z.isActive &&
          z.surchargeRate > 0 &&
          GeoMath.isPointInPolygon(dropoffPt, z.boundary)) {
        geofenceFee += z.surchargeRate;
      }
    }
    if (_store.isWeatherSurchargeActive) {
      geofenceFee += _store.badWeatherSurchargeConfig;
    }
    final weightVal = double.tryParse(_weightCtrl.text.trim()) ?? 1.5;
    if (weightVal > 5.0) {
      geofenceFee += ((weightVal - 5.0) * 3000).roundToDouble();
    }
    final combinedDesc = '$_pkgCategory ${_pkgDescCtrl.text}'.toLowerCase();
    if (combinedDesc.contains('dễ vỡ')) {
      geofenceFee += 5000;
    }
    if (combinedDesc.contains('giữ lạnh')) {
      geofenceFee += 10000;
    }

    final baseScale = (_store.baseFareConfig / 25000.0).clamp(0.4, 5.0);
    final kmScale = (_store.pricePerKmConfig / 5000.0).clamp(0.4, 5.0);

    final preEst = PricingEstimate.calculate(
      serviceType: _selectedService,
      distanceMeters: distMeters,
      durationSeconds: durationSec,
      isPeakHour: _store.isPeakSurchargeActive,
      geofenceSurcharge: geofenceFee,
      voucherDiscount: 0,
      baseFareScale: baseScale,
      pricePerKmScale: kmScale,
    );

    double discountVal = 0;
    final code = _voucherCtrl.text.trim().toUpperCase();
    final codVal = double.tryParse(_codCtrl.text) ?? 0.0;
    final matchedVoucher =
        _store.vouchers.where((v) => v.code == code).firstOrNull;
    if (matchedVoucher != null &&
        matchedVoucher.status == 'Đang hoạt động' &&
        (preEst.totalAmount + codVal) >= matchedVoucher.minOrderValue) {
      if (matchedVoucher.isPercentage) {
        discountVal =
            (preEst.totalAmount * (matchedVoucher.discountValue / 100.0))
                .clamp(0.0, matchedVoucher.maxDiscount);
      } else {
        discountVal = matchedVoucher.discountValue;
      }
    }

    final estimate = PricingEstimate.calculate(
      serviceType: _selectedService,
      distanceMeters: distMeters,
      durationSeconds: durationSec,
      isPeakHour: _store.isPeakSurchargeActive,
      geofenceSurcharge: geofenceFee,
      voucherDiscount: discountVal,
      baseFareScale: baseScale,
      pricePerKmScale: kmScale,
    );

    final nextOrderCode = '#DH${100000 + _store.orders.length * 1423}';
    final emvVietQr = SecurityAndBarcodeUtils.generateEmvVietQrPayload(
      orderCode: nextOrderCode,
      amountVnd: estimate.totalAmount,
    );

    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Animated3dIconBadge(
                      style: Icon3dStyle.walletVault,
                      size: 46,
                      showRadarPulse: false,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Xem ước tính chi phí',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF5B33E6),
                            ),
                          ),
                          Text(
                            'Xác nhận giá cước & Áp dụng Voucher (${estimate.distanceKm.toStringAsFixed(1)} km • ~${(durationSec / 60).round().clamp(5, 240)} phút)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4A4754),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _rebuildCustomerUi(() => _selectedScreenIndex = 2),
                  icon: const Icon(Icons.arrow_back_rounded, size: 15),
                  label: const Text(
                    'Quay lại sửa đơn',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Hộp Tóm tắt ước tính với Header xanh dương #1565C0 giống uc05_uoc_tinh_chi_phi.jpg
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: const Color(0xFF15131E)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    color: const Color(0xFF5B33E6),
                    child: const Text(
                      'Tóm tắt ước tính',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        _priceRow(
                          'Phí cơ bản (2 km đầu - ${_selectedService.displayName})',
                          CurrencyFormatter.formatVnd(estimate.baseFare),
                        ),
                        _priceRow(
                          'Phí theo km (${estimate.distanceKm.toStringAsFixed(1)} km)',
                          CurrencyFormatter.formatVnd(estimate.distanceFare),
                        ),
                        _priceRow(
                          'Phụ phí giờ cao điểm & Geofence',
                          CurrencyFormatter.formatVnd(estimate.surchargeFee),
                        ),
                        _priceRow(
                          code.isEmpty
                              ? 'Giảm giá (Khuyến mãi)'
                              : 'Giảm giá (Mã khuyến mãi $code)',
                          '-${CurrencyFormatter.formatVnd(estimate.discountAmount)}',
                          valueColor: const Color(0xFF14B866),
                        ),
                        const Divider(height: 18),
                        _priceRow(
                          'Tổng cộng',
                          CurrencyFormatter.formatVnd(estimate.totalAmount),
                          isBold: true,
                          valueColor: const Color(0xFFFF5E83),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // UC11: Mã giảm giá / Khuyến mãi (Thẻ Coupon đục lỗ giống uc11_ma_giam_gia.jpg)
            const Text(
              'Mã giảm giá / Khuyến mãi',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _voucherCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nhập mã giảm giá',
                      prefixIcon: Icon(Icons.confirmation_number_outlined),
                    ),
                    onChanged: (_) => _rebuildCustomerUi(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5E83),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      _rebuildCustomerUi(() {});
                      if (code.isEmpty) return;
                      if (matchedVoucher == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.danger,
                            content: Text(
                              'Mã khuyến mãi "$code" không tồn tại trong hệ thống.',
                            ),
                          ),
                        );
                      } else if (matchedVoucher.status != 'Đang hoạt động') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.danger,
                            content: Text(
                              'Mã "$code" hiện đang tạm ngưng áp dụng.',
                            ),
                          ),
                        );
                      } else if ((preEst.totalAmount + codVal) <
                          matchedVoucher.minOrderValue) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.danger,
                            content: Text(
                              'Mã "$code" yêu cầu giá trị đơn + COD tối thiểu ${CurrencyFormatter.formatVnd(matchedVoucher.minOrderValue)}.',
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Đã áp dụng mã "$code" (-${CurrencyFormatter.formatVnd(discountVal)}) thành công!',
                            ),
                          ),
                        );
                      }
                    },
                    child: const Text('Áp dụng'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._store.vouchers.map((v) {
              final isSelected = _voucherCtrl.text.trim().toUpperCase() == v.code;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.zero),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFFF5E83)
                        : const Color(0xFF15131E),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 86,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFFF5E83)
                            : const Color(0xFF5B33E6),
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(0),
                        ),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.local_offer_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            v.discountLabel,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${v.code} • ${v.title}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                            Text(
                              'Đơn tối thiểu: ${CurrencyFormatter.formatVnd(v.minOrderValue)} • HSD: ${v.expiryDate}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF4A4754),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isSelected
                              ? const Color(0xFF14B866)
                              : const Color(0xFFFF5E83),
                          side: BorderSide(
                            color: isSelected
                                ? const Color(0xFF14B866)
                                : const Color(0xFFFF5E83),
                          ),
                        ),
                        onPressed: () {
                          _rebuildCustomerUi(() => _voucherCtrl.text = v.code);
                          if (v.status != 'Đang hoạt động') {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.danger,
                                content: Text(
                                  'Mã "${v.code}" hiện đang tạm ngưng áp dụng.',
                                ),
                              ),
                            );
                          } else if ((preEst.totalAmount + codVal) <
                              v.minOrderValue) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.danger,
                                content: Text(
                                  'Mã "${v.code}" yêu cầu giá trị đơn + COD tối thiểu ${CurrencyFormatter.formatVnd(v.minOrderValue)}.',
                                ),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Đã chọn áp dụng mã "${v.code}" (${v.discountLabel})!',
                                ),
                              ),
                            );
                          }
                        },
                        child: Text(
                          isSelected ? 'Đã chọn' : 'Áp dụng',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 10),
            // UC07: Thanh toán đơn hàng (Giống uc07_thanh_toan_1791014440615.jpg)
            const Text(
              'Thanh toán đơn hàng - Chọn phương thức:',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                'Tiền mặt (COD)',
                'Ví MoMo',
                'ZaloPay',
                'VNPay / VietQR',
              ].map((m) {
                final selected = _selectedPaymentMethod == m;
                return ChoiceChip(
                  label: Text(m),
                  selected: selected,
                  selectedColor: const Color(0xFF5B33E6),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF15131E),
                    fontWeight: FontWeight.w700,
                  ),
                  onSelected: (_) => _rebuildCustomerUi(() => _selectedPaymentMethod = m),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F1E8),
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: const Color(0xFF15131E)),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final codField = TextField(
                    controller: _codCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _rebuildCustomerUi(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Tiền thu hộ COD (đ)',
                    ),
                  );
                  if (constraints.maxWidth < 480) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.account_balance_wallet_rounded,
                              color: Color(0xFF5B33E6),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Phương thức đã chọn: $_selectedPaymentMethod',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF5B33E6),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        codField,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: Color(0xFF5B33E6),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Phương thức đã chọn: $_selectedPaymentMethod',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF5B33E6),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 170,
                        child: codField,
                      ),
                    ],
                  );
                },
              ),
            ),
            if (_selectedPaymentMethod != 'Tiền mặt (COD)') ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F1E8),
                  borderRadius: BorderRadius.all(Radius.zero),
                  border: Border.all(color: const Color(0xFF5B33E6)),
                ),
                child: Row(
                  children: [
                    QrMatrixPainterWidget(
                      payload: emvVietQr,
                      size: 72,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mã QR thanh toán $_selectedPaymentMethod',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            'Mã đơn: $nextOrderCode • Số tiền: ${CurrencyFormatter.formatVnd(estimate.totalAmount)}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Color(0xFF5B33E6),
                            ),
                          ),
                          const Text(
                            'Quét mã QR bằng ứng dụng ngân hàng hoặc ví điện tử để thanh toán',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF4A4754),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () {
                                _rebuildCustomerUi(
                                  () => _isPreOrderPaid = true,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Đã xác nhận thanh toán trước cho đơn $nextOrderCode (${CurrencyFormatter.formatVnd(estimate.totalAmount)}) qua $_selectedPaymentMethod!',
                                    ),
                                  ),
                                );
                              },
                              icon: Icon(
                                _isPreOrderPaid
                                    ? Icons.check_circle_rounded
                                    : Icons.verified_outlined,
                                size: 15,
                                color: _isPreOrderPaid
                                    ? const Color(0xFF14B866)
                                    : null,
                              ),
                              label: Text(
                                _isPreOrderPaid
                                    ? 'Đã xác nhận thanh toán QR'
                                    : 'Xác nhận đã chuyển khoản',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: _isPreOrderPaid
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: _isPreOrderPaid
                                      ? const Color(0xFF14B866)
                                      : null,
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
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5E83),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.zero),
                  ),
                ),
                onPressed: () {
                  if (!_validateOrderFormInputs()) {
                    _rebuildCustomerUi(() => _selectedScreenIndex = 2);
                    return;
                  }
                  final scheduleNote = _isScheduledDelivery
                      ? ' [Hẹn giờ: $_scheduledDeliverySlot]'
                      : '';
                  final descText = _pkgDescCtrl.text.trim().isEmpty
                      ? '$_pkgCategory$scheduleNote'
                      : '$_pkgCategory - ${_pkgDescCtrl.text.trim()}$scheduleNote';
                  final created = _store.createNewOrder(
                    pickupAddress: _pickupCtrl.text.trim(),
                    dropoffAddress: _dropoffCtrl.text.trim(),
                    recipientName: _recipientNameCtrl.text.trim(),
                    recipientPhone: _recipientPhoneCtrl.text.trim(),
                    packageDescription: descText,
                    weightKg: double.tryParse(_weightCtrl.text) ?? 1.5,
                    dimensionsCm: _dimCtrl.text,
                    serviceType: _selectedService,
                    codAmount: double.tryParse(_codCtrl.text) ?? 0,
                    paymentMethod: _selectedPaymentMethod,
                    voucherCode: _voucherCtrl.text,
                    customDistanceMeters: distMeters,
                    customDurationSeconds: durationSec,
                    isPrepaidConfirmed: _isPreOrderPaid,
                  );
                  if (_isPreOrderPaid &&
                      _selectedPaymentMethod != 'Tiền mặt (COD)') {
                    _store.processOrderPayment(
                      trackingCode: created.trackingCode,
                      gateway: _selectedPaymentMethod,
                      transactionId: 'TXN-${created.trackingCode}',
                    );
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã đặt đơn hàng ${created.trackingCode} thành công!',
                      ),
                    ),
                  );
                  _rebuildCustomerUi(() {
                    _isPreOrderPaid = false;
                    _dropoffCtrl.clear();
                    _recipientNameCtrl.clear();
                    _recipientPhoneCtrl.clear();
                    _pkgDescCtrl.clear();
                    _voucherCtrl.clear();
                    _codCtrl.text = '0';
                    _osrmDistMeters = null;
                    _osrmDurationSec = null;
                    _selectedScreenIndex = 4;
                  });
                },
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text(
                  'Đặt đơn ngay',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
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
                fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
                fontSize: isBold ? 15 : 13.5,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
              fontSize: isBold ? 17 : 13.5,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// UC06: Theo dõi đơn hàng GPS Thời gian thực (Khớp 100% uc06_theo_doi_gps_1791014402627.jpg)
  Widget _buildLiveGpsTrackingView() {
    final activeOrder = _store.activeCustomerOrderRecord;
    if (activeOrder == null) {
      return Card(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: AppColors.ink, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Theo dõi đơn hàng',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF5B33E6),
                          ),
                        ),
                        Text(
                          'Theo dõi Tài xế GPS 3D Thời gian thực',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF4A4754),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F1E8),
                      border: Border.all(color: const Color(0xFF15131E)),
                    ),
                    child: const Text(
                      'Chưa có chuyến giao',
                      style: TextStyle(
                        color: Color(0xFF4A4754),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Map3dPerspectiveWidget(
                mode: MapViewMode.customerPreview,
                is3dMode: _store.isMap3dEnabled,
                speedKmh: 0,
                onToggle3d: _store.toggleMap3d,
                progressFraction: 0.0,
                nextTurnInstruction:
                    'Hệ thống định vị GPS 3D sẵn sàng theo dõi lộ trình khi bạn tạo đơn',
                roadName: 'Chưa có vận đơn đang vận chuyển',
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F1E8),
                  border: Border.all(color: const Color(0xFF15131E)),
                ),
                child: Row(
                  children: [
                    const Animated3dIconBadge(
                      style: Icon3dStyle.gpsPinRadar,
                      size: 52,
                      showRadarPulse: true,
                      isSelected: true,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Hiện chưa có đơn hàng nào đang vận chuyển',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: Color(0xFF15131E),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Khi bạn đặt đơn hàng mới, lộ trình GPS 3D và thông tin tài xế nhận chuyến sẽ hiển thị trực tiếp tại đây.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4A4754),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.violet,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _rebuildCustomerUi(
                              () => _selectedScreenIndex = 2,
                            ),
                            icon: const Icon(Icons.add_box_rounded, size: 17),
                            label: const Text('Tạo đơn hàng mới'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final remMeters = _store.distanceFromDriverToOrderDropoffMeters(activeOrder);
    final etaMinutes = (remMeters / 500.0).ceil().clamp(1, 45);
    final deliveryOtp4 =
        SecurityAndBarcodeUtils.generateOrderDeliveryOtp4(activeOrder.trackingCode);
    final isSearching = activeOrder.status == OrderStatus.searching ||
        activeOrder.status == OrderStatus.draft;
    final isAccepted = activeOrder.status == OrderStatus.accepted ||
        activeOrder.status == OrderStatus.arrivingPickup;
    final isInTransit = activeOrder.status == OrderStatus.inTransit;
    final isDelivered = activeOrder.status == OrderStatus.delivered;
    final isCancelled = activeOrder.status == OrderStatus.cancelled;
    final isFailedOrReturning = activeOrder.status == OrderStatus.failed ||
        activeOrder.status == OrderStatus.returning;
    final assignedDriverRecord = activeOrder.assignedDriverName == null
        ? null
        : _store.drivers
            .where((d) => d.fullName == activeOrder.assignedDriverName)
            .firstOrNull;

    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Theo dõi đơn hàng',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF5B33E6),
                      ),
                    ),
                    Text(
                      'Theo dõi Tài xế GPS 3D Thời gian thực',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF4A4754),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F1E8),
                    borderRadius: BorderRadius.all(Radius.zero),
                    border: Border.all(color: const Color(0xFF93C5FD)),
                  ),
                  child: Text(
                    isDelivered
                        ? 'Đã giao thành công • Hoàn tất 100%'
                        : isCancelled
                            ? 'Đã hủy đơn • ${activeOrder.cancelReason ?? "Khách hủy"}'
                            : isFailedOrReturning
                                ? '${activeOrder.status.displayName} • ${activeOrder.cancelReason ?? "Đang xử lý sự cố"}'
                                : isSearching
                                    ? 'Trạng thái: ${activeOrder.status.displayName}'
                                    : 'Dự kiến: ~$etaMinutes phút nữa (${(remMeters / 1000).toStringAsFixed(2)} km)',
                    style: const TextStyle(
                      color: Color(0xFF5B33E6),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    border: Border.all(color: const Color(0xFF14B866)),
                  ),
                  child: Text(
                    'OTP nhận hàng: $deliveryOtp4',
                    style: const TextStyle(
                      color: Color(0xFF14B866),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            if (_store.customerOrders.length > 1) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _store.customerOrders.map((ordItem) {
                  final isCurrent = ordItem.trackingCode == activeOrder.trackingCode;
                  return ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${ordItem.trackingCode} (${ordItem.status.displayName})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isCurrent ? Colors.white : AppColors.ink,
                      ),
                    ),
                    selected: isCurrent,
                    selectedColor: const Color(0xFF5B33E6),
                    onSelected: (_) => _rebuildCustomerUi(() {
                      _store.selectCustomerOrder(ordItem.trackingCode);
                    }),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),
            Map3dPerspectiveWidget(
              mode: MapViewMode.customerLiveTracking,
              is3dMode: _store.isMap3dEnabled,
              speedKmh: _store.currentSpeedKmh,
              onToggle3d: _store.toggleMap3d,
              progressFraction: isDelivered
                  ? 1.0
                  : (isSearching || isCancelled || isFailedOrReturning
                        ? 0.0
                        : _store.routeProgressStep / 10.0),
              routePoints: activeOrder.id == _store.activeOrderRecord?.id &&
                      _store.activeRoutePolyline.length >= 2
                  ? _store.activeRoutePolyline
                  : SmartDispatchEngine.generateRoutePolyline(
                      activeOrder.pickupLocation,
                      activeOrder.dropoffLocation,
                      segments: 10,
                    ),
              pickupLabel: '[A] Lấy hàng',
              dropoffLabel: '[B] Giao hàng',
              nextTurnInstruction: isDelivered
                  ? 'Đơn ${activeOrder.trackingCode} đã giao hoàn tất tại điểm nhận'
                  : isCancelled
                      ? 'Đơn ${activeOrder.trackingCode} đã hủy (${activeOrder.cancelReason ?? "Khách hủy"})'
                      : isFailedOrReturning
                          ? 'Đơn ${activeOrder.trackingCode}: ${activeOrder.status.displayName} (${activeOrder.cancelReason ?? "Đang xử lý"})'
                          : isSearching
                              ? 'Hệ thống đang định tuyến và điều phối tài xế cho mã ${activeOrder.trackingCode}'
                              : 'Tài xế cách điểm giao ${(remMeters / 1000).toStringAsFixed(2)} km (ETA: $etaMinutes phút)',
              roadName:
                  '${activeOrder.pickupAddress} → ${activeOrder.dropoffAddress}',
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F1E8),
                borderRadius: BorderRadius.all(Radius.zero),
                border: Border.all(color: const Color(0xFF15131E)),
              ),
              child: Row(
                children: [
                  _buildUc06StepNode(
                    isCancelled
                        ? 'Đã hủy đơn'
                        : isFailedOrReturning
                            ? activeOrder.status.displayName
                            : 'Đã tạo đơn',
                    done: !isSearching && !isCancelled && !isFailedOrReturning,
                    active: isSearching || isCancelled || isFailedOrReturning,
                  ),
                  _buildUc06StepLine(
                    done: !isSearching && !isCancelled && !isFailedOrReturning,
                  ),
                  _buildUc06StepNode(
                    'Tài xế nhận',
                    done: isInTransit || isDelivered,
                    active: isAccepted,
                  ),
                  _buildUc06StepLine(done: isInTransit || isDelivered),
                  _buildUc06StepNode(
                    'Đang giao',
                    done: isDelivered,
                    active: isInTransit,
                  ),
                  _buildUc06StepLine(
                    done: isDelivered,
                  ),
                  _buildUc06StepNode(
                    'Hoàn thành',
                    done: isDelivered,
                    active: false,
                  ),
                ],
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
              child: Row(
                children: [
                  const Animated3dIconBadge(
                    style: Icon3dStyle.scooterExpress,
                    size: 52,
                    showRadarPulse: true,
                    isSelected: true,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activeOrder.assignedDriverName != null
                              ? '${activeOrder.assignedDriverName} • ★ ${(assignedDriverRecord?.rating ?? _store.activeDriverRecord?.rating ?? 4.9).toStringAsFixed(1)}'
                              : 'Đang tìm tài xế nhận chuyến...',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          activeOrder.assignedDriverName != null
                              ? '${assignedDriverRecord?.vehicleType ?? _store.activeDriverRecord?.vehicleType ?? "Xe máy"} • ${activeOrder.assignedDriverPlate ?? assignedDriverRecord?.licensePlate ?? _store.activeDriverRecord?.licensePlate ?? "59X1-123.45"} • Mã: ${activeOrder.trackingCode}'
                              : 'Mã vận đơn: ${activeOrder.trackingCode} • Dịch vụ: ${activeOrder.serviceType.displayName}',
                          style: const TextStyle(
                            color: Color(0xFF4A4754),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (activeOrder.assignedDriverName != null) ...[
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF5B33E6),
                      ),
                      onPressed: () {
                        final rawPhone = assignedDriverRecord?.phone ??
                            _store.activeDriverRecord?.phone ??
                            _store.activeDriverPhone;
                        final maskedPhone =
                            SecurityAndBarcodeUtils.maskPhoneNumber(
                          rawPhone,
                          shouldMask: isDelivered || isCancelled,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Đang kết nối cuộc gọi tới tài xế $maskedPhone...',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.phone,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF5B33E6),
                      ),
                      onPressed: () =>
                          _rebuildCustomerUi(() => _selectedScreenIndex = 5),
                      icon: const Icon(
                        Icons.chat_bubble_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (activeOrder.assignedDriverName != null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5B33E6),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () =>
                        _rebuildCustomerUi(() => _selectedScreenIndex = 5),
                    icon: const Icon(Icons.chat_bubble_outline, size: 17),
                    label: const Text('Nhắn tin tài xế'),
                  ),
                if (isDelivered && activeOrder.paymentStatus != 'RETURNED')
                  OutlinedButton.icon(
                    onPressed: () =>
                        _rebuildCustomerUi(() => _selectedScreenIndex = 8),
                    icon: const Icon(Icons.star_outline_rounded, size: 17),
                    label: const Text('Đánh giá 5 sao'),
                  ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _rebuildCustomerUi(() => _selectedScreenIndex = 9),
                  icon: const Icon(Icons.report_problem_outlined, size: 17),
                  label: const Text('Khiếu nại'),
                ),
                if (activeOrder.status.canTransitionTo(OrderStatus.cancelled))
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                    ),
                    onPressed: () =>
                        _rebuildCustomerUi(() => _selectedScreenIndex = 6),
                    icon: const Icon(Icons.cancel_outlined, size: 17),
                    label: const Text('Hủy đơn'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUc06StepNode(
    String label, {
    required bool done,
    required bool active,
  }) {
    final color = done
        ? const Color(0xFF14B866)
        : active
            ? const Color(0xFFFF5E83)
            : const Color(0xFF15131E);
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(
              done
                  ? Icons.check
                  : active
                      ? Icons.local_shipping_rounded
                      : Icons.circle,
              size: 14,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: (done || active) ? FontWeight.w800 : FontWeight.w500,
              color: active
                  ? const Color(0xFFFF5E83)
                  : done
                      ? const Color(0xFF15131E)
                      : const Color(0xFF4A4754),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUc06StepLine({required bool done}) {
    return Container(
      width: 24,
      height: 2.5,
      margin: const EdgeInsets.only(bottom: 16),
      color: done ? const Color(0xFF14B866) : const Color(0xFF15131E),
    );
  }
}
