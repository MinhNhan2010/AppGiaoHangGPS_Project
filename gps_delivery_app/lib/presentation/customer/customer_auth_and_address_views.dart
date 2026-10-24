part of 'customer_subsystem_views.dart';

extension _CustomerAuthAndAddressViews on _CustomerSubsystemEntryState {
  /// Quản lý sổ địa chỉ nhận hàng
  Widget _buildSavedAddressesView() {
    final mySavedAddresses = _store.customerSavedAddresses;
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFF5B33E6),
            child: const Row(
              children: [
                Icon(
                  Icons.bookmarks_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Quản lý sổ địa chỉ thường dùng',
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
                // Bản đồ Google Maps ghim vị trí địa chỉ đã lưu
                Builder(
                  builder: (context) {
                    final safeAddrIdx = mySavedAddresses.isEmpty
                        ? 0
                        : _selectedSavedAddressIndex.clamp(
                            0,
                            mySavedAddresses.length - 1,
                          );
                    final focusedSaved = mySavedAddresses.isNotEmpty
                        ? mySavedAddresses[safeAddrIdx]
                        : null;
                    final pinPos = focusedSaved != null
                        ? focusedSaved.location
                        : (_store.activeAuthenticatedUser?.defaultLocation ??
                            _store.activeDriverLocation);
                    final pinAddress = focusedSaved != null
                        ? focusedSaved.fullAddress
                        : (_store.customerDefaultAddress.isNotEmpty
                            ? _store.customerDefaultAddress
                            : 'Chưa thiết lập địa chỉ mặc định');
                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF15131E)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Map3dPerspectiveWidget(
                        height: 175,
                        mode: MapViewMode.customerPreview,
                        is3dMode: _store.isMap3dEnabled,
                        speedKmh: 0,
                        onToggle3d: _store.toggleMap3d,
                        routePoints: [
                          pinPos,
                          GeoPoint(
                            latitude: pinPos.latitude + 0.0032,
                            longitude: pinPos.longitude + 0.0040,
                          ),
                        ],
                        pickupLabel: focusedSaved != null
                            ? '📍 ${focusedSaved.label}'
                            : '📍 Vị trí lưu',
                        dropoffLabel: 'Khu vực lân cận',
                        nextTurnInstruction: focusedSaved != null &&
                                focusedSaved.fullAddress ==
                                    _store.customerDefaultAddress
                            ? 'Địa chỉ mặc định của bạn'
                            : 'Đang xem trước địa chỉ đã lưu',
                        roadName: pinAddress,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5E83),
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.zero),
                      ),
                    ),
                    onPressed: () async {
                      final gpsMsg = await _store.acquireRealHardwareGps();
                      if (!mounted) return;
                      final pos = _store.activeDriverLocation;
                      final candidates = SmartDispatchEngine.searchAddressSuggestions('');
                      GeocodedPlaceSuggestion? nearestPlace;
                      double minDist = double.infinity;
                      for (final c in candidates) {
                        final d = GeoMath.distanceMeters(pos, c.location);
                        if (d < minDist) {
                          minDist = d;
                          nearestPlace = c;
                        }
                      }
                      final resolvedText = (nearestPlace != null && minDist <= 2500)
                          ? '${nearestPlace.fullAddress} (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})'
                          : 'Vị trí GPS thực tế (${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)})';
                      _rebuildCustomerUi(() {
                        _pickupCtrl.text = resolvedText;
                        _newAddressCtrl.text = resolvedText;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '$gpsMsg • Đã gán địa chỉ: ${_pickupCtrl.text}',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.my_location_rounded, size: 18),
                    label: const Text(
                      'Dùng vị trí hiện tại (GPS)',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Sổ địa chỉ đã lưu',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: Color(0xFF15131E),
                  ),
                ),
                const SizedBox(height: 8),
                if (mySavedAddresses.isEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F1E8),
                      border: Border.all(color: const Color(0xFF15131E)),
                    ),
                    child: const Text(
                      'Bạn chưa lưu địa chỉ nào. Hãy nhập địa chỉ thường dùng bên dưới và nhấn "Thêm địa chỉ".',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF4A4754),
                      ),
                    ),
                  )
                else
                  ...mySavedAddresses.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final addr = entry.value;
                    final isDefault =
                        addr.fullAddress == _store.customerDefaultAddress;
                    final isFocused = idx ==
                        _selectedSavedAddressIndex.clamp(
                          0,
                          mySavedAddresses.length - 1,
                        );
                    return InkWell(
                      onTap: () => _rebuildCustomerUi(
                        () => _selectedSavedAddressIndex = idx,
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isFocused
                              ? const Color(0xFFF5F1E8)
                              : Colors.white,
                          borderRadius: BorderRadius.all(Radius.zero),
                          border: Border.all(
                            color: isFocused
                                ? const Color(0xFF5B33E6)
                                : const Color(0xFF15131E),
                            width: isFocused ? 1.5 : 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE9E9E4),
                                    borderRadius: BorderRadius.all(Radius.zero),
                                  ),
                                  child: Icon(
                                    addr.label.contains('Nhà')
                                        ? Icons.home_rounded
                                        : addr.label.contains('Cơ quan') ||
                                                addr.label.contains('Công ty')
                                            ? Icons.business_rounded
                                            : Icons.location_on_rounded,
                                    color: const Color(0xFF5B33E6),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            addr.label,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13.5,
                                            ),
                                          ),
                                          if (isDefault)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              color: const Color(0xFF5B33E6),
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
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        addr.fullAddress,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF4A4754),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Color(0xFFDC2626),
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      _store.removeCustomerAddress(addr.id),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                  ),
                                  onPressed: () {
                                    _pickupCtrl.text = addr.fullAddress;
                                    _rebuildCustomerUi(
                                      () => _selectedScreenIndex = 2,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.trip_origin_rounded,
                                    size: 14,
                                  ),
                                  label: const Text(
                                    'Chọn lấy',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                FilledButton.tonalIcon(
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                  ),
                                  onPressed: () {
                                    _dropoffCtrl.text = addr.fullAddress;
                                    _rebuildCustomerUi(
                                      () => _selectedScreenIndex = 2,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.location_on_outlined,
                                    size: 14,
                                  ),
                                  label: const Text(
                                    'Chọn giao',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                if (!isDefault)
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                    ),
                                    onPressed: () {
                                      _store.setDefaultCustomerAddress(
                                        addr.fullAddress,
                                      );
                                      _rebuildCustomerUi(() {
                                        _selectedSavedAddressIndex = idx;
                                        _profileAddressCtrl.text =
                                            addr.fullAddress;
                                      });
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Đã đặt "${addr.label}" làm địa chỉ mặc định!',
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.star_outline_rounded,
                                      size: 14,
                                      color: Color(0xFF5B33E6),
                                    ),
                                    label: const Text(
                                      'Đặt mặc định',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: ['Nhà riêng', 'Công ty', 'Khác'].map((tag) {
                    return ChoiceChip(
                      label: Text(tag),
                      selected: _selectedAddressTag == tag,
                      onSelected: (_) =>
                          _rebuildCustomerUi(() => _selectedAddressTag = tag),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newAddressCtrl,
                        onChanged: (_) => _rebuildCustomerUi(() {}),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Nhập địa chỉ mới để lưu vào sổ...',
                          prefixIcon: const Icon(Icons.place_outlined),
                          suffixIcon: IconButton(
                            tooltip: 'Tra cứu địa chỉ thực tế từ OpenStreetMap',
                            onPressed: () async {
                              final q = _newAddressCtrl.text.trim();
                              if (q.isEmpty) return;
                              final results = await SmartDispatchEngine
                                  .fetchLiveNominatimSuggestions(q);
                              if (!mounted) return;
                              _rebuildCustomerUi(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Đã tìm thấy ${results.length} địa chỉ thực tế cho "$q"',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.travel_explore_rounded,
                              color: Color(0xFF5B33E6),
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5E83),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.zero),
                        ),
                      ),
                      onPressed: () {
                        if (_newAddressCtrl.text.trim().isEmpty) return;
                        _store.addCustomerAddress(
                          _selectedAddressTag,
                          _newAddressCtrl.text.trim(),
                        );
                        _newAddressCtrl.clear();
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text(
                        'Thêm địa chỉ',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                if (_newAddressCtrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: SmartDispatchEngine.searchAddressSuggestions(
                      _newAddressCtrl.text,
                    ).take(3).map((place) {
                      return ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(
                          Icons.location_searching_rounded,
                          size: 13,
                          color: Color(0xFF5B33E6),
                        ),
                        label: Text(
                          place.title,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: () => _rebuildCustomerUi(
                          () => _newAddressCtrl.text = place.fullAddress,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _applyVoucherAndProceed(BuildContext context, String code) {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) return;
    final matched =
        _store.vouchers.where((v) => v.code == cleanCode).firstOrNull;
    if (matched == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(
            'Mã khuyến mãi "$cleanCode" không tồn tại trong hệ thống.',
          ),
        ),
      );
      return;
    }
    if (matched.status != 'Đang hoạt động') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Mã "$cleanCode" hiện đang tạm ngưng áp dụng.'),
        ),
      );
      return;
    }
    final hasCompleteOrderForm = _pickupCtrl.text.trim().isNotEmpty &&
        _dropoffCtrl.text.trim().isNotEmpty &&
        _recipientNameCtrl.text.trim().isNotEmpty &&
        _recipientPhoneCtrl.text.trim().isNotEmpty;
    _rebuildCustomerUi(() {
      _voucherCtrl.text = cleanCode;
      _selectedScreenIndex = hasCompleteOrderForm ? 3 : 2;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          hasCompleteOrderForm
              ? 'Đã chọn mã khuyến mãi $cleanCode (Đơn tối thiểu ${CurrencyFormatter.formatVnd(matched.minOrderValue)})!'
              : 'Đã chọn mã $cleanCode. Vui lòng nhập địa chỉ lấy/giao và người nhận để tính cước!',
        ),
      ),
    );
  }

  /// UC11: Mã giảm giá / Khuyến mãi (Khớp 100% anh_sua_lai/uc11_khuyen_mai.jpg)
  Widget _buildDedicatedVoucherUc11View() {
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: AppColors.ink, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFF5B33E6),
            child: const Row(
              children: [
                Icon(
                  Icons.local_offer_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Kho mã ưu đãi & Khuyến mãi',
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
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _voucherCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Nhập mã giảm giá',
                          prefixIcon: Icon(Icons.confirmation_number_outlined),
                        ),
                        onChanged: (_) => _rebuildCustomerUi(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5E83),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.zero),
                          ),
                        ),
                        onPressed: () =>
                            _applyVoucherAndProceed(context, _voucherCtrl.text),
                        child: const Text(
                          'Áp dụng',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Voucher khả dụng',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFF15131E),
                  ),
                ),
                const SizedBox(height: 10),
                ..._store.vouchers.map((v) {
                  final isSelected =
                      _voucherCtrl.text.trim().toUpperCase() == v.code;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.all(Radius.zero),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFFF5E83)
                            : const Color(0xFF15131E),
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 96,
                          padding: const EdgeInsets.symmetric(
                            vertical: 18,
                            horizontal: 8,
                          ),
                          decoration: const BoxDecoration(
                            color: Color(0xFF5B33E6),
                            borderRadius: BorderRadius.horizontal(
                              left: Radius.circular(0),
                            ),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.local_offer_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                v.discountLabel,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  v.title.toUpperCase(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: Color(0xFF15131E),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Mã: ${v.code} • Đơn tối thiểu: ${CurrencyFormatter.formatVnd(v.minOrderValue)}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF4A4754),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'HSD: ${v.expiryDate}',
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
                          padding: const EdgeInsets.only(right: 12),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF5E83),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(Radius.zero),
                              ),
                            ),
                            onPressed: () =>
                                _applyVoucherAndProceed(context, v.code),
                            child: const Text(
                              'Dùng ngay',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
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
}
