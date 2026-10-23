part of 'app_state_store.dart';

extension AppStateAuthAndGpsOps on AppStateStore {
  /// Đăng ký tài khoản mới hoặc cập nhật vào bảng `users` trong CSDL SQLite + PostGIS
  UserAccountRecord? registerUserAccountWithRole({
    required String phone,
    required String fullName,
    required String password,
    required SubsystemRole role,
    String? email,
    String? defaultAddress,
    bool activateSession = true,
  }) {
    final normPhone = _normalizePhone(phone);
    if (normPhone.length < 9 || fullName.trim().isEmpty) {
      return null;
    }
    final pwd = password.trim().isEmpty ? '12345678' : password.trim();
    final passwordHash =
        SecurityAndBarcodeUtils.hashPasswordWithSalt(pwd, normPhone);
    registeredUserPasswordHashes[normPhone] = passwordHash;

    final existing = findUserByPhone(normPhone);
    final UserAccountRecord record;
    if (existing != null) {
      existing.fullName = fullName.trim();
      existing.passwordHash = passwordHash;
      existing.role = role;
      if (email != null && email.trim().isNotEmpty) {
        existing.email = email.trim();
      }
      if (defaultAddress != null && defaultAddress.trim().isNotEmpty) {
        existing.defaultAddress = defaultAddress.trim();
      }
      record = existing;
    } else {
      record = UserAccountRecord(
        id: 'USR-0${users.length + 1}',
        phone: normPhone,
        email: (email != null && email.trim().isNotEmpty)
            ? email.trim()
            : '$normPhone@giaohanggps.vn',
        passwordHash: passwordHash,
        fullName: fullName.trim(),
        role: role,
        defaultAddress: defaultAddress?.trim().isNotEmpty == true
            ? defaultAddress!.trim()
            : '',
        defaultLocation: const GeoPoint(latitude: 10.7769, longitude: 106.6953),
        createdAt: DateTime.now().toIso8601String(),
      );
      users.add(record);
    }

    _sqliteDb.upsertRow('users', {
      'id': record.id,
      'phone': _normalizePhone(record.phone),
      'email': record.email,
      'password_hash': record.passwordHash,
      'full_name': record.fullName,
      'role': record.roleDbCode,
      'default_address': record.defaultAddress,
      'default_lat': record.defaultLocation.latitude,
      'default_lng': record.defaultLocation.longitude,
      'status': record.status,
      'created_at': record.createdAt,
    });

    if (role == SubsystemRole.driver &&
        drivers.where((d) => _normalizePhone(d.phone) == normPhone).isEmpty) {
      registerOrUpdateDriverKyc(
        fullName: record.fullName,
        phone: normPhone,
        citizenId: '07909500${users.length}88',
        vehicleType: 'Xe máy',
        licensePlate: '59-P1 ${100 + drivers.length}.89',
        activateDriverContext: activateSession,
      );
    }

    if (activateSession) {
      applyAuthenticatedUserSession(record);
    }
    _persistMutation('USER_REGISTER_SQL', {
      'table': 'users',
      'phone': normPhone,
      'role': record.roleDbCode,
    });
    _notifyStoreChanged();
    return record;
  }

  /// Áp dụng phiên đăng nhập thực tế từ bản ghi `users` trong CSDL
  void applyAuthenticatedUserSession(UserAccountRecord user) {
    activeAuthenticatedUser = user;
    customerFullName = user.fullName;
    customerPhone = user.phone;
    customerEmail = user.email;
    customerDefaultAddress = user.defaultAddress;
    isCustomerGoogleLinked = user.email.contains('@');

    switch (user.role) {
      case SubsystemRole.customer:
        break;
      case SubsystemRole.driver:
        activeDriverName = user.fullName;
        activeDriverPhone = user.phone;
        final matchedDrv = drivers
            .where((d) => _normalizePhone(d.phone) == _normalizePhone(user.phone))
            .firstOrNull;
        if (matchedDrv != null) {
          activeDriverId = matchedDrv.id;
          isDriverOnline = matchedDrv.isOnline;
          activeDriverLocation = matchedDrv.location;
        }
      case SubsystemRole.merchant:
        final matchedMer = merchantApplicants
            .where(
              (m) =>
                  _normalizePhone(m.ownerPhone) == _normalizePhone(user.phone),
            )
            .firstOrNull;
        if (matchedMer != null) {
          merchantStoreName = matchedMer.storeName;
          merchantBusinessType = matchedMer.businessType;
          merchantTaxCode = matchedMer.taxCode;
          merchantRepresentative = matchedMer.representativeName;
          merchantOpenHours = matchedMer.openHours;
          merchantBankName = matchedMer.bankName;
          merchantBankAccount = matchedMer.bankAccount;
        } else {
          merchantStoreName = user.fullName;
        }
      case SubsystemRole.admin:
        currentAdminRoleName = 'Super Admin';
    }
    _notifyStoreChanged();
  }

  /// Đăng ký hoặc xác thực mật khẩu đã băm SHA-256 mở rộng kèm Salt
  bool authenticateOrRegisterAccount({
    required String phone,
    required String password,
    bool isRegister = false,
    String? fullName,
    SubsystemRole role = SubsystemRole.customer,
  }) {
    final normPhone = _normalizePhone(phone);
    if (normPhone.length < 9 || password.trim().length < 6) {
      return false;
    }
    final passwordHash =
        SecurityAndBarcodeUtils.hashPasswordWithSalt(password.trim(), normPhone);
    if (isRegister) {
      final created = registerUserAccountWithRole(
        phone: normPhone,
        fullName: (fullName != null && fullName.trim().isNotEmpty)
            ? fullName.trim()
            : customerFullName,
        password: password.trim(),
        role: role,
      );
      return created != null;
    }
    final existingUser = findUserByPhone(normPhone);
    if (existingUser != null && existingUser.status == 'LOCKED') {
      return false;
    }
    final existingHash =
        existingUser?.passwordHash ?? registeredUserPasswordHashes[normPhone];
    if (existingHash == null) {
      final created = registerUserAccountWithRole(
        phone: normPhone,
        fullName: fullName ?? 'Người dùng $normPhone',
        password: password.trim(),
        role: role,
      );
      return created != null;
    }
    final matched = existingHash == passwordHash;
    if (matched) {
      if (existingUser != null) {
        applyAuthenticatedUserSession(existingUser);
      } else {
        customerPhone = phone.trim();
        _notifyStoreChanged();
      }
    }
    return matched;
  }

  /// Xác thực đăng nhập bằng Số điện thoại hoặc Email kèm Mật khẩu đã đăng ký
  UserAccountRecord? authenticateWithPassword({
    required String phoneOrEmail,
    required String password,
  }) {
    final user = findUserByPhoneOrEmail(phoneOrEmail);
    if (user == null || user.status == 'LOCKED' || password.trim().isEmpty) {
      return null;
    }
    final normPhone = _normalizePhone(user.phone);
    final candidateHash = SecurityAndBarcodeUtils.hashPasswordWithSalt(
      password.trim(),
      normPhone,
    );
    if (user.passwordHash != candidateHash) {
      return null;
    }
    applyAuthenticatedUserSession(user);
    _persistMutation('PASSWORD_LOGIN_VERIFIED', {'phone': normPhone});
    return user;
  }

  String _resolveOtpKey(String phoneOrEmail) {
    final trimmed = phoneOrEmail.trim();
    if (trimmed.contains('@')) {
      final matched = findUserByPhoneOrEmail(trimmed);
      if (matched != null) {
        return _normalizePhone(matched.phone);
      }
      return trimmed.toLowerCase();
    }
    return _normalizePhone(trimmed);
  }

  String generateOtpForPhone(String phone, {bool notify = false}) {
    final normKey = _resolveOtpKey(phone);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final hashHex =
        SecurityAndBarcodeUtils.hashPasswordWithSalt('$nowMs', normKey)
            .replaceAll('BCRYPT-HASH-', '');
    final numericVal = int.parse(hashHex.substring(0, 8), radix: 16);
    final otp6 = (100000 + (numericVal % 900000)).toString();
    activeOtpCodesByPhone[normKey] = otp6;
    otpExpiryEpochMsByPhone[normKey] = nowMs + 120000;
    if (notify) {
      _notifyStoreChanged();
    }
    return otp6;
  }

  int getRemainingOtpSeconds(String phone) {
    final normKey = _resolveOtpKey(phone);
    final expiry = otpExpiryEpochMsByPhone[normKey];
    if (expiry == null) return 0;
    final remainMs = expiry - DateTime.now().millisecondsSinceEpoch;
    return remainMs > 0 ? (remainMs / 1000).ceil() : 0;
  }

  bool verifyOtpCode(String phone, String inputOtp) {
    final normKey = _resolveOtpKey(phone);
    final user = findUserByPhoneOrEmail(phone);
    if (user != null && user.status == 'LOCKED') {
      return false;
    }
    final expected = activeOtpCodesByPhone[normKey];
    final expiry = otpExpiryEpochMsByPhone[normKey];
    if (expected == null || expiry == null) return false;
    if (DateTime.now().millisecondsSinceEpoch > expiry) return false;
    final ok = expected == inputOtp.trim();
    if (ok) {
      activeOtpCodesByPhone.remove(normKey);
      otpExpiryEpochMsByPhone.remove(normKey);
      if (user != null) {
        applyAuthenticatedUserSession(user);
      }
      _persistMutation('OTP_VERIFIED', {'phone': normKey});
      _notifyStoreChanged();
    }
    return ok;
  }

  void updateCustomerProfile({
    required String fullName,
    required String phone,
    required String email,
    required String defaultAddress,
  }) {
    final oldNameLower = customerFullName.trim().toLowerCase();
    final oldPhoneNorm = _normalizePhone(customerPhone);

    if (fullName.trim().isNotEmpty) {
      customerFullName = fullName.trim();
    }
    if (phone.trim().isNotEmpty) {
      customerPhone = phone.trim();
    }
    customerEmail = email.trim();
    customerDefaultAddress = defaultAddress.trim();

    final normPhone = _normalizePhone(customerPhone);
    if (customerFullName.trim().toLowerCase() != oldNameLower) {
      for (final ord in orders) {
        if (ord.customerName.trim().toLowerCase() == oldNameLower) {
          ord.customerName = customerFullName;
          _sqliteDb.updateRows(
            'orders',
            {'customer_name': customerFullName},
            where: 'tracking_code = ?',
            whereArgs: [ord.trackingCode],
          );
        }
      }
    }
    if (normPhone.isNotEmpty && normPhone != oldPhoneNorm) {
      for (var i = 0; i < savedAddresses.length; i++) {
        final addr = savedAddresses[i];
        if (_normalizePhone(addr.userPhone) == oldPhoneNorm) {
          final updatedAddr = SavedAddressRecord(
            id: addr.id,
            userPhone: normPhone,
            label: addr.label,
            fullAddress: addr.fullAddress,
            location: addr.location,
          );
          savedAddresses[i] = updatedAddr;
          _sqliteDb.updateRows(
            'user_addresses',
            {'user_phone': normPhone},
            where: 'id = ?',
            whereArgs: [addr.id],
          );
        }
      }
    }

    final u = activeAuthenticatedUser ??
        findUserByPhone(normPhone) ??
        findUserByPhone(oldPhoneNorm) ??
        findUserByPhoneOrEmail(customerEmail) ??
        users.where((x) => x.role == SubsystemRole.customer).firstOrNull;
    if (u != null) {
      u.fullName = customerFullName;
      if (normPhone.isNotEmpty) {
        u.phone = normPhone;
      }
      u.email = customerEmail;
      u.defaultAddress = customerDefaultAddress;
      _sqliteDb.upsertRow('users', {
        'id': u.id,
        'phone': u.phone,
        'email': u.email,
        'password_hash': u.passwordHash,
        'full_name': u.fullName,
        'role': u.roleDbCode,
        'default_address': u.defaultAddress,
        'default_lat': u.defaultLocation.latitude,
        'default_lng': u.defaultLocation.longitude,
        'status': u.status,
        'created_at': u.createdAt,
      });
    }
    _persistMutation('UPDATE_CUSTOMER_PROFILE', {'phone': normPhone});
    _notifyStoreChanged();
  }

  void registerOrUpdateDriverKyc({
    required String fullName,
    required String phone,
    required String citizenId,
    required String vehicleType,
    required String licensePlate,
    String vehicleColor = 'Xanh đen',
    bool activateDriverContext = true,
  }) {
    final normPhone = _normalizePhone(phone);
    final existing =
        drivers.where((d) => _normalizePhone(d.phone) == normPhone).firstOrNull;
    final DriverApplicantRecord record;
    if (existing != null) {
      existing.fullName = fullName.trim();
      existing.phone = normPhone;
      existing.citizenId = citizenId.trim();
      existing.vehicleType = vehicleType.trim();
      existing.licensePlate = licensePlate.trim();
      existing.approvalStatus = 'Chờ duyệt';
      record = existing;
    } else {
      record = DriverApplicantRecord(
        id: 'DV109${drivers.length + 28}',
        fullName: fullName.trim(),
        phone: normPhone,
        citizenId: citizenId.trim(),
        licensePlate: licensePlate.trim(),
        vehicleType: vehicleType.trim(),
        vehicleColor: vehicleColor,
        approvalStatus: 'Chờ duyệt',
        isOnline: true,
        location: const GeoPoint(latitude: 10.7769, longitude: 106.6953),
        rating: 5.0,
        totalTrips: 0,
      );
      drivers.insert(0, record);
    }

    if (activateDriverContext) {
      activeDriverId = record.id;
      activeDriverName = record.fullName;
      activeDriverPhone = record.phone;
    }

    _sqliteDb.upsertRow('drivers', {
      'id': record.id,
      'phone': _normalizePhone(record.phone),
      'full_name': record.fullName,
      'citizen_id': record.citizenId,
      'license_plate': record.licensePlate,
      'vehicle_type': record.vehicleType,
      'vehicle_color': record.vehicleColor,
      'approval_status': record.approvalStatus,
      'is_online': record.isOnline ? 1 : 0,
      'latitude': record.location.latitude,
      'longitude': record.location.longitude,
      'rating': record.rating,
      'total_trips': record.totalTrips,
      'wallet_balance': driverWalletBalance,
      'created_at': DateTime.now().toIso8601String(),
    });
    _persistMutation('REGISTER_DRIVER_KYC', {'driverId': record.id});
    _notifyStoreChanged();
  }

  void registerOrUpdateMerchantKyc({
    required String ownerPhone,
    required String storeName,
    required String businessType,
    required String taxCode,
    required String representativeName,
    required String bankName,
    required String bankAccount,
    String openHours = '08:00 - 21:00',
  }) {
    final normPhone = _normalizePhone(ownerPhone);
    final existing = merchantApplicants
        .where((m) => _normalizePhone(m.ownerPhone) == normPhone)
        .firstOrNull;
    final MerchantApplicantRecord record;
    if (existing != null) {
      existing.storeName = storeName.trim();
      existing.businessType = businessType.trim();
      existing.taxCode = taxCode.trim();
      existing.representativeName = representativeName.trim();
      existing.openHours = openHours.trim();
      existing.bankName = bankName.trim();
      existing.bankAccount = bankAccount.trim();
      existing.approvalStatus = 'Chờ duyệt';
      record = existing;
    } else {
      record = MerchantApplicantRecord(
        id: 'MER-0${merchantApplicants.length + 1}',
        ownerPhone: normPhone,
        storeName: storeName.trim(),
        businessType: businessType.trim(),
        taxCode: taxCode.trim(),
        representativeName: representativeName.trim(),
        openHours: openHours.trim(),
        bankName: bankName.trim(),
        bankAccount: bankAccount.trim(),
        approvalStatus: 'Chờ duyệt',
      );
      merchantApplicants.insert(0, record);
    }

    _sqliteDb.upsertRow('merchants', {
      'id': record.id,
      'owner_phone': normPhone,
      'store_name': record.storeName,
      'business_type': record.businessType,
      'tax_code': record.taxCode,
      'representative_name': record.representativeName,
      'open_hours': record.openHours,
      'bank_name': record.bankName,
      'bank_account': record.bankAccount,
      'cod_balance': merchantCodBalance,
      'approval_status': record.approvalStatus,
      'created_at': DateTime.now().toIso8601String(),
    });
    _persistMutation('REGISTER_MERCHANT_KYC', {'merchantId': record.id});
    _notifyStoreChanged();
  }

  void setDriverOnlineStatus(bool online) {
    isDriverOnline = online;
    final drv = drivers.where((d) => d.id == activeDriverId).firstOrNull ??
        drivers.firstOrNull;
    if (drv != null) {
      drv.isOnline = online;
      _sqliteDb.updateRows(
        'drivers',
        {'is_online': online ? 1 : 0},
        where: 'id = ?',
        whereArgs: [drv.id],
      );
    }
    _persistMutation('SET_DRIVER_ONLINE', {'isOnline': online});
    _notifyStoreChanged();
  }

  void updateMerchantProfile({
    required String storeName,
    required String taxCode,
    required String businessType,
    required String representativeName,
    required String phone,
    required String bankName,
    required String bankAccount,
    String? warehouseAddress,
    int warehouseIndex = 0,
  }) {
    merchantStoreName = storeName.trim();
    merchantTaxCode = taxCode.trim();
    merchantBusinessType = businessType.trim();
    merchantRepresentative = representativeName.trim();
    merchantBankName = bankName.trim();
    merchantBankAccount = bankAccount.trim();

    final targetMer = activeMerchantRecord ?? merchantApplicants.firstOrNull;
    final targetMerId = targetMer?.id ?? 'MER-01';
    if (targetMer != null) {
      targetMer.storeName = merchantStoreName;
      targetMer.taxCode = merchantTaxCode;
      targetMer.businessType = merchantBusinessType;
      targetMer.representativeName = merchantRepresentative;
      if (phone.trim().isNotEmpty) {
        targetMer.ownerPhone = _normalizePhone(phone);
      }
      targetMer.bankName = merchantBankName;
      targetMer.bankAccount = merchantBankAccount;
    }

    if (warehouseAddress != null &&
        warehouseAddress.trim().isNotEmpty &&
        merchantWarehouses.isNotEmpty) {
      final safeIdx = warehouseIndex.clamp(0, merchantWarehouses.length - 1);
      final currentWh = merchantWarehouses[safeIdx];
      final resolvedPt = SmartDispatchEngine.resolveAddressToCoordinate(
        warehouseAddress.trim(),
        fallback: currentWh.location,
      );
      final updatedWh = PickupWarehouseRecord(
        id: currentWh.id,
        name: currentWh.name,
        address: warehouseAddress.trim(),
        location: resolvedPt,
      );
      merchantWarehouses[safeIdx] = updatedWh;
      _sqliteDb.upsertRow('merchant_pickup_points', {
        'id': updatedWh.id,
        'merchant_id': targetMerId,
        'warehouse_name': updatedWh.name,
        'full_address': updatedWh.address,
        'latitude': updatedWh.location.latitude,
        'longitude': updatedWh.location.longitude,
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    _sqliteDb.upsertRow('merchants', {
      'id': targetMerId,
      'owner_phone': _normalizePhone(phone),
      'store_name': merchantStoreName,
      'business_type': merchantBusinessType,
      'tax_code': merchantTaxCode,
      'representative_name': merchantRepresentative,
      'open_hours': merchantOpenHours,
      'bank_name': merchantBankName,
      'bank_account': merchantBankAccount,
      'cod_balance': merchantCodBalance,
      'approval_status': targetMer?.approvalStatus ?? 'Đã duyệt',
      'created_at': DateTime.now().toIso8601String(),
    });
    _persistMutation('UPDATE_MERCHANT_PROFILE', {'storeName': merchantStoreName});
    _notifyStoreChanged();
  }

  void savePricingConfiguration({
    required double baseFare,
    required double pricePerKm,
    required bool isPeakEnabled,
    required bool isWeatherEnabled,
  }) {
    baseFareConfig = baseFare;
    pricePerKmConfig = pricePerKm;
    isPeakSurchargeActive = isPeakEnabled;
    isWeatherSurchargeActive = isWeatherEnabled;

    _sqliteDb.upsertRow('pricing_configs', {
      'id': 'PRC-01',
      'service_type': 'STANDARD',
      'base_fare': baseFareConfig,
      'price_per_km': pricePerKmConfig,
      'peak_hour_surcharge': peakHourSurchargeConfig,
      'bad_weather_surcharge': badWeatherSurchargeConfig,
      'is_peak_enabled': isPeakSurchargeActive ? 1 : 0,
      'is_weather_enabled': isWeatherSurchargeActive ? 1 : 0,
      'updated_at': DateTime.now().toIso8601String(),
    });
    _persistMutation('SAVE_PRICING_CONFIG', {
      'baseFare': baseFareConfig,
      'pricePerKm': pricePerKmConfig,
    });
    _notifyStoreChanged();
  }

  bool processOrderPayment({
    required String trackingCode,
    required String gateway,
    required String transactionId,
  }) {
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord == null) return false;
    final signature =
        SecurityAndBarcodeUtils.generatePaymentIdempotencySignature(
      orderId: trackingCode,
      amount: ord.totalAmount,
      gateway: gateway,
      transactionId: transactionId,
    );
    if (processedPaymentSignatures.contains(signature)) {
      return false;
    }
    processedPaymentSignatures.add(signature);
    ord.paymentMethod = gateway;
    ord.paymentStatus = 'PAID';
    _sqliteDb.updateRows(
      'orders',
      {
        'payment_method': gateway,
        'payment_status': 'PAID',
      },
      where: 'tracking_code = ?',
      whereArgs: [trackingCode],
    );
    _persistMutation('ORDER_PAYMENT_PAID', {
      'trackingCode': trackingCode,
      'gateway': gateway,
      'signature': signature,
    });
    _notifyStoreChanged();
    return true;
  }

  CsvBatchParseResult parseAndCreateBulkOrdersFromCsv(
    String csvContentOrFilePath, {
    bool commitOrders = false,
  }) {
    String rawContent = csvContentOrFilePath.trim();
    try {
      if (rawContent.toLowerCase().endsWith('.csv')) {
        final f = File(rawContent);
        if (f.existsSync()) {
          rawContent = f.readAsStringSync();
        }
      }
    } catch (_) {}

    final lines = rawContent
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final parsedRows = <CsvBatchRowResult>[];
    final createdCodes = <String>[];
    int validCount = 0;
    int invalidCount = 0;
    final phoneRegex = RegExp(r'^(\+84|0)[0-9]{8,10}$');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (i == 0 &&
          (line.toLowerCase().contains('recipient') ||
              line.toLowerCase().contains('nguoi_nhan') ||
              line.toLowerCase().contains('ten_nguoi_nhan'))) {
        continue;
      }
      final cols = line.split(',').map((c) => c.trim()).toList();
      final name = cols.isNotEmpty ? cols[0] : '';
      final phone = cols.length > 1 ? cols[1].replaceAll(' ', '') : '';
      final address = cols.length > 2 ? cols[2] : '';

      final isFourColCodFormat = cols.length == 4 &&
          double.tryParse(
                cols[3].replaceAll('.', '').replaceAll('đ', '').trim(),
              ) !=
              null;

      final desc = isFourColCodFormat
          ? 'Kiện hàng thương mại điện tử'
          : (cols.length > 3 && cols[3].isNotEmpty
              ? cols[3]
              : 'Kiện hàng thương mại điện tử');
      final weight = isFourColCodFormat
          ? 1.5
          : (cols.length > 4 ? (double.tryParse(cols[4]) ?? 1.5) : 1.5);
      final cod = isFourColCodFormat
          ? (double.tryParse(
                  cols[3].replaceAll('.', '').replaceAll('đ', '').trim(),
                ) ??
              0.0)
          : (cols.length > 5
              ? (double.tryParse(
                      cols[5].replaceAll('.', '').replaceAll('đ', '').trim(),
                    ) ??
                  0.0)
              : 0.0);
      final svcStr = !isFourColCodFormat && cols.length > 6
          ? cols[6].toUpperCase()
          : 'STANDARD';
      final svc = svcStr.contains('EXPRESS')
          ? DeliveryServiceType.express30m
          : svcStr.contains('ECONOMY') || svcStr.contains('SAVING')
              ? DeliveryServiceType.saving
              : DeliveryServiceType.standard;

      final errors = <String>[];
      if (name.isEmpty) errors.add('Thiếu tên người nhận');
      if (!phoneRegex.hasMatch(phone)) errors.add('SĐT không hợp lệ');
      if (address.length < 5) errors.add('Thiếu địa chỉ giao');
      if (weight <= 0 || weight > 500) errors.add('Khối lượng không hợp lệ');
      if (cod < 0) errors.add('Tiền COD âm');

      final isValid = errors.isEmpty;
      if (isValid) {
        validCount++;
        if (commitOrders) {
          final created = createNewOrder(
            pickupAddress: merchantWarehouses.first.address,
            dropoffAddress: address,
            recipientName: name,
            recipientPhone: phone,
            packageDescription: desc,
            weightKg: weight,
            dimensionsCm: '30 x 20 x 15 cm',
            serviceType: svc,
            codAmount: cod,
            paymentMethod: cod > 0 ? 'Tiền mặt (COD)' : 'Đã thanh toán trước',
          );
          createdCodes.add(created.trackingCode);
        }
      } else {
        invalidCount++;
      }

      parsedRows.add(
        CsvBatchRowResult(
          rowNumber: parsedRows.length + 1,
          recipientName: name.isEmpty ? '(Trống)' : name,
          recipientPhone: phone.isEmpty ? '(Trống)' : phone,
          dropoffAddress: address.isEmpty ? '(Trống)' : address,
          packageDescription: desc,
          weightKg: weight,
          codAmount: cod,
          serviceType: svc,
          isValid: isValid,
          statusNote: isValid ? 'Hợp lệ' : errors.join(', '),
        ),
      );
    }

    return CsvBatchParseResult(
      rows: parsedRows,
      validCount: validCount,
      invalidCount: invalidCount,
      createdTrackingCodes: createdCodes,
    );
  }

  void toggleOfflineSimulation(bool offline) {
    final wasOffline = isOfflineMode;
    isOfflineMode = offline;
    if (offline) {
      offlineQueueCount += 3;
      lastSyncStatusMessage =
          'Đang lưu tạm $offlineQueueCount bản ghi vào SQLite local_sync_queue';
    } else {
      final drained = offlineQueueCount;
      offlineQueueCount = 0;
      if (wasOffline && drained > 0) {
        lastSyncStatusMessage =
            'Đã đồng bộ $drained gói tin SQLite lên PostGIS (Exponential Backoff: 1000ms)';
      }
    }
    _persistMutation('TOGGLE_OFFLINE', {'isOffline': offline});
    _notifyStoreChanged();
  }

  void toggleMap3d() {
    isMap3dEnabled = !isMap3dEnabled;
    currentCameraPitch = isMap3dEnabled ? 55.0 : 0.0;
    _notifyStoreChanged();
  }

  void stepDriverAlongRoute({bool snapToDropoff = false}) {
    final ord = activeOrderRecord ?? orders.first;
    final polyline = activeRoutePolyline.length >= 2
        ? activeRoutePolyline
        : SmartDispatchEngine.generateRoutePolyline(
            ord.pickupLocation,
            ord.dropoffLocation,
            segments: 10,
          );
    if (snapToDropoff) {
      routeProgressStep = polyline.length - 1;
    } else {
      routeProgressStep = (routeProgressStep + 1) % polyline.length;
    }
    final rawTarget = polyline[routeProgressStep];
    final previous = activeDriverLocation;
    activeDriverLocation = _kalmanFilter.filter(
      rawPoint: rawTarget,
      accuracyMeters: 4.5,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (snapToDropoff) {
      activeDriverLocation = ord.dropoffLocation;
    }
    activeDriverBearing =
        GeoMath.bearingDegrees(previous, activeDriverLocation);
    _sqliteDb.upsertRow('order_tracking_logs', {
      'order_id': ord.id,
      'driver_id': activeDriverId,
      'latitude': activeDriverLocation.latitude,
      'longitude': activeDriverLocation.longitude,
      'speed': currentSpeedKmh,
      'bearing': activeDriverBearing,
      'is_mock_location': 0,
      'recorded_at': DateTime.now().toIso8601String(),
    });
    if (isOfflineMode) offlineQueueCount++;
    _notifyStoreChanged();
  }

  double distanceFromDriverToDropoffMeters() {
    final ord = activeOrderRecord ?? orders.first;
    return GeoMath.distanceMeters(activeDriverLocation, ord.dropoffLocation);
  }

  Future<String> acquireRealHardwareGps() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return 'Dịch vụ định vị GPS trên thiết bị đang tắt. Đang giữ tọa độ Kalman nội bộ.';
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return 'Chưa cấp quyền truy cập GPS phần cứng. Đang dùng bộ phát Kalman nội bộ.';
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      final rawFix = GeoPoint(latitude: pos.latitude, longitude: pos.longitude);
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      GpsIntegrityValidator.validateSample(
        currentPoint: rawFix,
        currentTimestampMs: nowMs,
        isMockFlaggedByOs: pos.isMocked,
        reportedSpeedKmh: pos.speed > 0 ? pos.speed * 3.6 : 0.0,
      );

      final previous = activeDriverLocation;
      activeDriverLocation = _kalmanFilter.filter(
        rawPoint: rawFix,
        accuracyMeters: pos.accuracy > 0 ? pos.accuracy : 5.0,
        timestampMs: nowMs,
      );
      if (pos.speed > 0) {
        currentSpeedKmh = (pos.speed * 3.6).clamp(5.0, 90.0);
      }
      activeDriverBearing =
          GeoMath.bearingDegrees(previous, activeDriverLocation);
      lastSyncStatusMessage =
          'Chip GPS Thiết bị: (${activeDriverLocation.latitude.toStringAsFixed(5)}, ${activeDriverLocation.longitude.toStringAsFixed(5)}) ±${pos.accuracy.toStringAsFixed(1)}m';
      await _sqliteDb.upsertRow('order_tracking_logs', {
        'order_id': (activeOrderRecord ?? orders.first).id,
        'driver_id': activeDriverId,
        'latitude': activeDriverLocation.latitude,
        'longitude': activeDriverLocation.longitude,
        'speed': currentSpeedKmh,
        'bearing': activeDriverBearing,
        'is_mock_location': pos.isMocked ? 1 : 0,
        'recorded_at': DateTime.now().toIso8601String(),
      });
      _persistMutation('HARDWARE_GPS_FIX', {
        'lat': activeDriverLocation.latitude,
        'lng': activeDriverLocation.longitude,
      });
      _notifyStoreChanged();
      return lastSyncStatusMessage;
    } catch (e) {
      return 'Không thể đọc cảm biến GPS phần cứng ($e). Đang dùng tọa độ Kalman hiện tại.';
    }
  }

  Future<String> syncLiveOsrmRouteForActiveOrder() async {
    final ord = activeOrderRecord ?? orders.first;
    final res = await SmartDispatchEngine.fetchLiveOsrmRoute(
      ord.pickupLocation,
      ord.dropoffLocation,
    );
    ord.distanceMeters = res.distanceMeters;
    ord.durationSeconds = res.durationSeconds;
    if (res.polylinePoints.length >= 2) {
      activeRoutePolyline = res.polylinePoints;
      routeProgressStep = 0;
    }
    await _sqliteDb.updateRows(
      'orders',
      {
        'distance_meters': ord.distanceMeters,
        'duration_seconds': ord.durationSeconds,
      },
      where: 'id = ?',
      whereArgs: [ord.id],
    );
    final km = (res.distanceMeters / 1000.0).toStringAsFixed(1);
    final mins = (res.durationSeconds / 60).round().clamp(5, 240);
    lastSyncStatusMessage = res.isLiveOsrm
        ? 'OSRM Thực tế: $km km ($mins phút) - ${res.polylinePoints.length} điểm tọa độ'
        : 'Nội suy Haversine Offline: $km km ($mins phút)';
    _persistMutation('OSRM_ROUTE_SYNC', {
      'trackingCode': ord.trackingCode,
      'distanceMeters': ord.distanceMeters,
      'points': activeRoutePolyline.length,
    });
    _notifyStoreChanged();
    return lastSyncStatusMessage;
  }

  Future<String> configureAndSyncSupabaseCloud({
    required String url,
    required String anonKey,
  }) async {
    EnvConfig.configureSupabaseRuntime(url: url, anonKey: anonKey);
    if (!EnvConfig.isSupabaseConfigured) {
      return 'Vui lòng nhập SUPABASE_URL hợp lệ và SUPABASE_ANON_KEY không rỗng.';
    }
    try {
      try {
        await Supabase.initialize(
          url: EnvConfig.supabaseUrl,
          publishableKey: EnvConfig.supabaseAnonKey,
        );
      } catch (_) {}
      final remoteDs = SupabasePostgisDatasource();
      final rows = await remoteDs.fetchTableRecords('orders', limit: 20);
      isOfflineMode = false;
      offlineQueueCount = 0;
      lastSyncStatusMessage =
          'Đã kết nối Cloud Supabase PostGIS thành công (${rows.length} bản ghi orders trên mây)';
      _notifyStoreChanged();
      return lastSyncStatusMessage;
    } catch (e) {
      lastSyncStatusMessage =
          'Đã lưu cấu hình Supabase. Máy chủ trả về: $e (Đang duy trì CSDL SQLite cục bộ)';
      _notifyStoreChanged();
      return lastSyncStatusMessage;
    }
  }

  /// Đăng nhập hoặc tự động khởi tạo tài khoản trong bảng `users` SQLite từ phiên Google OAuth 2.0
  UserAccountRecord? signInOrRegisterOAuthUser({
    required String email,
    required String fullName,
    String? phone,
    SubsystemRole role = SubsystemRole.customer,
  }) {
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = fullName.trim().isNotEmpty
        ? fullName.trim()
        : cleanEmail.split('@').first;
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      return null;
    }

    final existingByEmail = findUserByPhoneOrEmail(cleanEmail);
    if (existingByEmail != null) {
      if (existingByEmail.status == 'LOCKED') {
        return existingByEmail;
      }
      if (existingByEmail.id != 'USR-01' &&
          existingByEmail.defaultAddress == '123 Đường Lê Lợi, Quận 1, TP. HCM') {
        existingByEmail.defaultAddress = '';
        _sqliteDb.updateRows(
          'users',
          {'default_address': ''},
          where: 'id = ?',
          whereArgs: [existingByEmail.id],
        );
      }
      applyAuthenticatedUserSession(existingByEmail);
      _persistMutation('OAUTH_GOOGLE_SIGN_IN', {
        'email': cleanEmail,
        'userId': existingByEmail.id,
      });
      return existingByEmail;
    }

    final rawPhoneDigits =
        (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final resolvedPhone = rawPhoneDigits.length >= 9
        ? rawPhoneDigits
        : '09${10000000 + (cleanEmail.hashCode.abs() % 89999999)}';

    final safeRole = role == SubsystemRole.admin
        ? SubsystemRole.customer
        : role;

    return registerUserAccountWithRole(
      phone: resolvedPhone,
      email: cleanEmail,
      fullName: cleanName,
      password: 'OAUTH-GOOGLE-${cleanEmail.hashCode.abs()}',
      role: safeRole,
    );
  }

  Future<void> saveAuthProviderConfigsToDatabase({
    required String smtpHost,
    required int smtpPort,
    required String smtpSenderEmail,
    required String smtpAppPassword,
    required String smsWebhookUrl,
    required String googleClientId,
    required String googleClientSecret,
  }) async {
    EnvConfig.configureAuthProvidersRuntime(
      smtpHost: smtpHost,
      smtpPort: smtpPort,
      smtpSenderEmail: smtpSenderEmail,
      smtpAppPassword: smtpAppPassword,
      smsWebhookUrl: smsWebhookUrl,
      googleClientId: googleClientId,
      googleClientSecret: googleClientSecret,
    );
    await _sqliteDb.upsertEntityRecord(
      tableName: 'auth_provider_configs',
      recordId: 'DEFAULT',
      payload: {
        'smtpHost': EnvConfig.smtpHost,
        'smtpPort': EnvConfig.smtpPort,
        'smtpSenderEmail': EnvConfig.smtpSenderEmail,
        'smtpAppPassword': EnvConfig.smtpAppPassword,
        'smsWebhookUrl': EnvConfig.smsWebhookUrl,
        'googleClientId': EnvConfig.googleClientId,
        'googleClientSecret': EnvConfig.googleClientSecret,
      },
    );
    _notifyStoreChanged();
  }

  Future<void> loadAuthProviderConfigsFromDatabase() async {
    try {
      final rows = await _sqliteDb.getEntityRecords('auth_provider_configs');
      if (rows.isEmpty) return;
      final cfg = rows.first;
      EnvConfig.configureAuthProvidersRuntime(
        smtpHost: cfg['smtpHost']?.toString(),
        smtpPort: int.tryParse(cfg['smtpPort']?.toString() ?? '465'),
        smtpSenderEmail: cfg['smtpSenderEmail']?.toString(),
        smtpAppPassword: cfg['smtpAppPassword']?.toString(),
        smsWebhookUrl: cfg['smsWebhookUrl']?.toString(),
        googleClientId: cfg['googleClientId']?.toString(),
        googleClientSecret: cfg['googleClientSecret']?.toString(),
      );
    } catch (_) {}
  }
}
