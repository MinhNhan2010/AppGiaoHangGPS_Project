part of 'app_state_store.dart';

extension AppStateSeedAndHydration on AppStateStore {
  void _initializeDefaultRoles() {
    rbacRoles
      ..clear()
      ..addAll([
        RbacRoleRecord(
          roleName: 'Super Admin',
          permissions: {
            'User: Khóa/Mở': true,
            'Đơn: Xem': true,
            'Đơn: Tạo': true,
            'Đơn: Sửa': true,
            'Đơn: Xóa': true,
            'Tài xế: Xem': true,
            'Tài xế: Phê duyệt': true,
            'Tài xế: Chỉnh sửa': true,
            'Tài xế: Đình chỉ': true,
            'Khiếu nại: Xử lý': true,
            'Tài chính: Báo cáo': true,
            'Tài chính: Giao dịch': true,
            'Tài chính: Thanh toán': true,
            'Hệ thống: Cài đặt': true,
            'Hệ thống: Bảo mật': true,
            'Hệ thống: Nhật ký': true,
          },
        ),
        RbacRoleRecord(
          roleName: 'Điều phối viên',
          permissions: {
            'User: Khóa/Mở': false,
            'Đơn: Xem': true,
            'Đơn: Tạo': true,
            'Đơn: Sửa': true,
            'Đơn: Xóa': true,
            'Tài xế: Xem': true,
            'Tài xế: Phê duyệt': true,
            'Tài xế: Chỉnh sửa': true,
            'Tài xế: Đình chỉ': false,
            'Khiếu nại: Xử lý': true,
            'Tài chính: Báo cáo': false,
            'Tài chính: Giao dịch': false,
            'Tài chính: Thanh toán': false,
            'Hệ thống: Cài đặt': false,
            'Hệ thống: Bảo mật': false,
            'Hệ thống: Nhật ký': false,
          },
        ),
        RbacRoleRecord(
          roleName: 'Kế toán',
          permissions: {
            'User: Khóa/Mở': false,
            'Đơn: Xem': false,
            'Đơn: Tạo': false,
            'Đơn: Sửa': false,
            'Đơn: Xóa': false,
            'Tài xế: Xem': false,
            'Tài xế: Phê duyệt': false,
            'Tài xế: Chỉnh sửa': false,
            'Tài xế: Đình chỉ': false,
            'Khiếu nại: Xử lý': false,
            'Tài chính: Báo cáo': true,
            'Tài chính: Giao dịch': true,
            'Tài chính: Thanh toán': true,
            'Hệ thống: Cài đặt': false,
            'Hệ thống: Bảo mật': false,
            'Hệ thống: Nhật ký': false,
          },
        ),
        RbacRoleRecord(
          roleName: 'Hỗ trợ CSKH',
          permissions: {
            'User: Khóa/Mở': false,
            'Đơn: Xem': true,
            'Đơn: Tạo': true,
            'Đơn: Sửa': false,
            'Đơn: Xóa': false,
            'Tài xế: Xem': true,
            'Tài xế: Phê duyệt': false,
            'Tài xế: Chỉnh sửa': false,
            'Tài xế: Đình chỉ': false,
            'Khiếu nại: Xử lý': true,
            'Tài chính: Báo cáo': true,
            'Tài chính: Giao dịch': false,
            'Tài chính: Thanh toán': false,
            'Hệ thống: Cài đặt': false,
            'Hệ thống: Bảo mật': false,
            'Hệ thống: Nhật ký': false,
          },
        ),
      ]);
  }

  /// Khởi tạo và nạp toàn bộ 16 bảng quan hệ từ CSDL SQLite thực tế (`gps_delivery_production.db`)
  Future<void> initializeDatabase() {
    if (_initializingDbFuture != null) return _initializingDbFuture!;
    final future = _runInitializeDatabase();
    _initializingDbFuture = future.whenComplete(() {
      _initializingDbFuture = null;
    });
    return _initializingDbFuture!;
  }

  Future<void> _runInitializeDatabase() async {
    try {
      await removeLegacyDemoRecords();
      if (await _sqliteDb.countRows('admin_roles_permissions') == 0) {
        for (final role in rbacRoles) {
          await _sqliteDb.upsertRow('admin_roles_permissions', {
            'id': role.roleName,
            'role_name': role.roleName,
            'permissions_json': jsonEncode(role.permissions),
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      }
      await _loadAllTablesFromSqlite();
      await _sqliteDb.clearStaleSnapshotEntries();
      if (!isOfflineMode) {
        await drainOfflineSyncQueue();
      }
      offlineQueueCount = await _sqliteDb.getPendingQueueCount();
      isDatabaseReady = true;
      lastSyncStatusMessage =
          'Đã tải dữ liệu trên thiết bị';
      _notifyStoreChanged();
    } catch (_) {
      // Giữ trạng thái trong bộ nhớ nếu môi trường test không cho phép mở tệp
    }
  }

  Future<void> reloadFromSqlite() async {
    await _loadAllTablesFromSqlite();
    offlineQueueCount = await _sqliteDb.getPendingQueueCount();
    _notifyStoreChanged();
  }

  Future<void> _loadAllTablesFromSqlite() async {
    userPreferencesByPhone.clear();
    registeredUserPasswordHashes.clear();
    final entityRows = await _sqliteDb.queryRows('local_relational_entities');
    final driverMeta = <String, Map<String, dynamic>>{};
    final merchantMeta = <String, Map<String, dynamic>>{};
    final warehouseMeta = <String, Map<String, dynamic>>{};
    final withdrawalMeta = <String, Map<String, dynamic>>{};
    final voucherMeta = <String, Map<String, dynamic>>{};
    final codRecMeta = <String, Map<String, dynamic>>{};
    final complaintMeta = <String, Map<String, dynamic>>{};
    for (final er in entityRows) {
      try {
        final tName = er['table_name'].toString();
        final rId = er['record_id'].toString();
        final decoded =
            jsonDecode(er['payload_json'].toString()) as Map<String, dynamic>;
        switch (tName) {
          case 'driver_meta':
            driverMeta[rId] = decoded;
          case 'merchant_meta':
            merchantMeta[rId] = decoded;
          case 'warehouse_meta':
            warehouseMeta[rId] = decoded;
          case 'withdrawal_meta':
            withdrawalMeta[rId] = decoded;
          case 'voucher_meta':
            voucherMeta[rId] = decoded;
          case 'cod_reconciliation_meta':
            codRecMeta[rId] = decoded;
          case 'complaint_meta':
            complaintMeta[rId] = decoded;
          case 'user_preferences':
            userPreferencesByPhone[rId] = decoded;
        }
      } catch (_) {}
    }

    final userRows = await _sqliteDb.queryRows('users');
    users.clear();
    if (userRows.isNotEmpty) {
      users
        ..clear()
        ..addAll(
          userRows.map(
            (r) => UserAccountRecord(
              id: r['id'].toString(),
              phone: r['phone'].toString(),
              email: (r['email'] ?? '').toString(),
              passwordHash: r['password_hash'].toString(),
              fullName: r['full_name'].toString(),
              role: UserAccountRecord.parseRoleCode(
                (r['role'] ?? 'CUSTOMER').toString(),
              ),
              defaultAddress: (r['default_address'] ?? '').toString(),
              defaultLocation: GeoPoint(
                latitude: (r['default_lat'] as num?)?.toDouble() ?? 10.7769,
                longitude: (r['default_lng'] as num?)?.toDouble() ?? 106.6953,
              ),
              status: (r['status'] ?? 'ACTIVE').toString(),
              createdAt: (r['created_at'] ?? '').toString(),
            ),
          ),
        );
      for (final u in users) {
        registeredUserPasswordHashes[_normalizePhone(u.phone)] = u.passwordHash;
      }
    }

    final addrRows = await _sqliteDb.queryRows('user_addresses');
    savedAddresses.clear();
    if (addrRows.isNotEmpty) {
      savedAddresses
        ..clear()
        ..addAll(
          addrRows.map(
            (r) => SavedAddressRecord(
              id: r['id'].toString(),
              userPhone: (r['user_phone'] ?? '').toString(),
              label: r['label'].toString(),
              fullAddress: r['full_address'].toString(),
              location: GeoPoint(
                latitude: (r['latitude'] as num).toDouble(),
                longitude: (r['longitude'] as num).toDouble(),
              ),
            ),
          ),
        );
    }

    final drvRows = await _sqliteDb.queryRows('drivers');
    drivers.clear();
    isDriverOnline = false;
    driverWalletBalance = 0;
    activeDriverId = activeDriverName = activeDriverPhone = '';
    if (drvRows.isNotEmpty) {
      drivers
        ..clear()
        ..addAll(
          drvRows.map((r) {
            final idStr = r['id'].toString();
            final rawStatus = (r['approval_status'] ?? 'Chờ duyệt').toString();
            final normStatus =
                (rawStatus == 'SUSPENDED' || rawStatus == 'Đình chỉ')
                    ? 'Đình chỉ'
                    : (rawStatus == 'REJECTED' || rawStatus == 'Từ chối')
                        ? 'Từ chối'
                        : (rawStatus == 'APPROVED' ||
                                rawStatus == 'Đã duyệt')
                            ? 'Đã duyệt'
                            : 'Chờ duyệt';
            final rawOnline = (r['is_online'] as num?)?.toInt() == 1;
            final meta = driverMeta[idStr];
            List<String>? parsedDocs;
            final colDocsJson = r['attached_kyc_docs_json']?.toString();
            if (colDocsJson != null && colDocsJson.trim().startsWith('[')) {
              try {
                parsedDocs = (jsonDecode(colDocsJson) as List<dynamic>)
                    .map((e) => e.toString())
                    .toList();
              } catch (_) {}
            } else if (meta?['attachedKycDocs'] is List) {
              parsedDocs = (meta!['attachedKycDocs'] as List)
                  .map((e) => e.toString())
                  .toList();
            }
            final walletVal = (r['wallet_balance'] as num?)?.toDouble() ??
                0.0;
            final colBank = r['bank_name']?.toString();
            final colAcct = r['bank_account']?.toString();
            final colRej = (r['rejected_count'] as num?)?.toInt();
            return DriverApplicantRecord(
              id: idStr,
              fullName: r['full_name'].toString(),
              phone: r['phone'].toString(),
              citizenId: r['citizen_id'].toString(),
              licensePlate: r['license_plate'].toString(),
              vehicleType: r['vehicle_type'].toString(),
              vehicleColor: r['vehicle_color'].toString(),
              approvalStatus: normStatus,
              isOnline: normStatus == 'Đã duyệt' &&
                  walletVal >= 200000 &&
                  rawOnline,
              location: GeoPoint(
                latitude: (r['latitude'] as num).toDouble(),
                longitude: (r['longitude'] as num).toDouble(),
              ),
              rating: (r['rating'] as num?)?.toDouble() ?? 0.0,
              totalTrips: (r['total_trips'] as num?)?.toInt() ?? 0,
              rejectedCount: (colRej != null && colRej > 0)
                  ? colRej
                  : ((meta?['rejectedCount'] as num?)?.toInt() ??
                      colRej ??
                      0),
              walletBalance: walletVal,
              bankName: colBank ?? meta?['bankName']?.toString() ?? '',
              bankAccount: colAcct ?? meta?['bankAccount']?.toString() ?? '',
              attachedKycDocs: parsedDocs,
            );
          }),
        );
      final defaultDrv = drivers.first;
      isDriverOnline = defaultDrv.isOnline;
      activeDriverId = defaultDrv.id;
      activeDriverName = defaultDrv.fullName;
      activeDriverPhone = defaultDrv.phone;
      driverWalletBalance = defaultDrv.walletBalance;
    }

    verifiedDriverLocations.clear();
    for (final fix in await _sqliteDb.getEntityRecords('verified_driver_locations')) {
      final id = fix['id']?.toString();
      final lat = fix['latitude'];
      final lon = fix['longitude'];
      if (id != null && lat is num && lon is num &&
          drivers.any((driver) => driver.id == id)) {
        verifiedDriverLocations[id] = GeoPoint(
          latitude: lat.toDouble(), longitude: lon.toDouble());
      }
    }

    final merRows = await _sqliteDb.queryRows('merchants');
    merchantApplicants.clear();
    merchantStoreName = merchantBusinessType = merchantTaxCode = '';
    merchantRepresentative = merchantOpenHours = '';
    merchantBankName = merchantBankAccount = '';
    merchantCodBalance = 0;
    if (merRows.isNotEmpty) {
      merchantApplicants
        ..clear()
        ..addAll(
          merRows.map((r) {
            final merId = r['id'].toString();
            final rawStatus = (r['approval_status'] ?? 'Chờ duyệt').toString();
            final normStatus =
                (rawStatus == 'SUSPENDED' || rawStatus == 'Đình chỉ')
                    ? 'Đình chỉ'
                    : (rawStatus == 'APPROVED' || rawStatus == 'Đã duyệt')
                        ? 'Đã duyệt'
                        : (rawStatus == 'REJECTED' || rawStatus == 'Từ chối')
                            ? 'Từ chối'
                            : 'Chờ duyệt';
            final meta = merchantMeta[merId];
            List<String>? parsedDocs;
            final colDocsJson = r['attached_kyc_docs_json']?.toString();
            if (colDocsJson != null && colDocsJson.trim().startsWith('[')) {
              try {
                parsedDocs = (jsonDecode(colDocsJson) as List<dynamic>)
                    .map((e) => e.toString())
                    .toList();
              } catch (_) {}
            } else if (meta?['attachedKycDocs'] is List) {
              parsedDocs = (meta!['attachedKycDocs'] as List)
                  .map((e) => e.toString())
                  .toList();
            }
            final colWebhook = r['webhook_url']?.toString() ?? '';
            return MerchantApplicantRecord(
              id: merId,
              ownerPhone: (r['owner_phone'] ?? '').toString(),
              storeName: r['store_name'].toString(),
              businessType: r['business_type'].toString(),
              taxCode: r['tax_code'].toString(),
              representativeName: r['representative_name'].toString(),
              openHours: r['open_hours'].toString(),
              bankName: r['bank_name'].toString(),
              bankAccount: r['bank_account'].toString(),
              approvalStatus: normStatus,
              codBalance: (r['cod_balance'] as num?)?.toDouble() ??
                  0.0,
              webhookUrl: colWebhook.isNotEmpty
                  ? colWebhook
                  : (meta?['webhookUrl']?.toString() ?? ''),
              attachedKycDocs: parsedDocs,
            );
          }),
        );
      final m = merchantApplicants.first;
      merchantStoreName = m.storeName;
      merchantBusinessType = m.businessType;
      merchantTaxCode = m.taxCode;
      merchantRepresentative = m.representativeName;
      merchantOpenHours = m.openHours;
      merchantBankName = m.bankName;
      merchantBankAccount = m.bankAccount;
      merchantCodBalance = m.codBalance;
    }

    final whRows = await _sqliteDb.queryRows('merchant_pickup_points');
    merchantWarehouses.clear();
    if (whRows.isNotEmpty) {
      merchantWarehouses
        ..clear()
        ..addAll(
          whRows.map((r) {
            final whId = r['id'].toString();
            final meta = warehouseMeta[whId];
            final colPhone = r['contact_phone']?.toString() ?? '';
            final colHours = r['open_hours']?.toString() ?? '';
            final colPrimary = (r['is_primary'] as num?)?.toInt();
            final colWebhook = r['webhook_url']?.toString() ?? '';
            final resolvedPrimary = colPrimary != null
                ? colPrimary == 1
                : (meta != null && meta.containsKey('isPrimary')
                    ? meta['isPrimary'] == true
                    : false);
            return PickupWarehouseRecord(
              id: whId,
              merchantId: (r['merchant_id'] ?? '').toString(),
              name: r['warehouse_name'].toString(),
              address: r['full_address'].toString(),
              location: GeoPoint(
                latitude: (r['latitude'] as num).toDouble(),
                longitude: (r['longitude'] as num).toDouble(),
              ),
              contactName: meta?['contactName']?.toString() ?? '',
              contactPhone: colPhone.isNotEmpty
                  ? colPhone
                  : (meta?['contactPhone']?.toString() ??
                      ''),
              openHours: colHours.isNotEmpty
                  ? colHours
                  : (meta?['openHours']?.toString() ??
                      (whId == 'WH-02' ? '08:30 - 20:30' : '08:00 - 21:00')),
              isPrimary: resolvedPrimary,
              webhookUrl: colWebhook.isNotEmpty
                  ? colWebhook
                  : (meta?['webhookUrl']?.toString() ?? ''),
            );
          }),
        );
    }

    final codRecRows = await _sqliteDb.queryRows('cod_reconciliations');
    codReconciliations.clear();
    if (codRecRows.isNotEmpty) {
      codReconciliations
        ..clear()
        ..addAll(
          codRecRows.map((r) {
            final recId = r['id'].toString();
            final meta = codRecMeta[recId];
            final colReturnFee = (r['return_cancel_fee'] as num?)?.toDouble();
            return CodReconciliationRecord(
              id: recId,
              merchantId: r['merchant_id'].toString(),
              periodLabel: r['period_label'].toString(),
              totalCodCollected: (r['total_cod_collected'] as num).toDouble(),
              totalServiceFee: (r['total_service_fee'] as num).toDouble(),
              returnCancelFee: colReturnFee ??
                  (meta?['returnCancelFee'] as num?)?.toDouble() ??
                  0.0,
              netPayoutAmount: (r['net_payout_amount'] as num).toDouble(),
              status: r['status'].toString(),
            );
          }),
        );
    } else if (codReconciliations.isNotEmpty) {
      for (final rec in codReconciliations) {
        await _sqliteDb.upsertRow('cod_reconciliations', {
          'id': rec.id,
          'merchant_id': rec.merchantId,
          'period_label': rec.periodLabel,
          'total_cod_collected': rec.totalCodCollected,
          'total_service_fee': rec.totalServiceFee,
          'return_cancel_fee': rec.returnCancelFee,
          'net_payout_amount': rec.netPayoutAmount,
          'status': rec.status,
        });
      }
    }

    final prcRows = await _sqliteDb.queryRows('pricing_configs');
    if (prcRows.isNotEmpty) {
      final p = prcRows.first;
      if (p['service_type'] == 'STANDARD') {
        await _sqliteDb.updateRows(
          'pricing_configs',
          {
            'service_type': 'STANDARD_V2',
            'is_weather_enabled': 0,
          },
          where: 'id = ?',
          whereArgs: [p['id']],
        );
        isWeatherSurchargeActive = false;
      } else {
        isWeatherSurchargeActive =
            (p['is_weather_enabled'] as num?)?.toInt() == 1;
      }
      baseFareConfig = (p['base_fare'] as num).toDouble();
      pricePerKmConfig = (p['price_per_km'] as num).toDouble();
      peakHourSurchargeConfig = (p['peak_hour_surcharge'] as num).toDouble();
      badWeatherSurchargeConfig =
          (p['bad_weather_surcharge'] as num).toDouble();
      isPeakSurchargeActive = (p['is_peak_enabled'] as num?)?.toInt() == 1;
    }

    final vRows = await _sqliteDb.queryRows('vouchers');
    vouchers.clear();
    if (vRows.isNotEmpty) {
      vouchers
        ..clear()
        ..addAll(
          vRows.map((r) {
            final vCode = r['code'].toString();
            final meta = voucherMeta[vCode];
            final colLimit = (r['usage_limit'] as num?)?.toInt();
            final colUsed = (r['used_count'] as num?)?.toInt();
            return VoucherRecord(
              code: vCode,
              title: r['title'].toString(),
              discountLabel: r['discount_label'].toString(),
              discountValue: (r['discount_value'] as num).toDouble(),
              isPercentage: (r['is_percentage'] as num).toInt() == 1,
              maxDiscount: (r['max_discount'] as num).toDouble(),
              minOrderValue: (r['min_order_value'] as num).toDouble(),
              expiryDate: r['expiry_date'].toString(),
              status: r['status'].toString(),
              usageLimit: colLimit ??
                  (meta?['usageLimit'] as num?)?.toInt() ??
                  1000,
              usedCount:
                  colUsed ?? (meta?['usedCount'] as num?)?.toInt() ?? 0,
            );
          }),
        );
    }

    final ordRows = await _sqliteDb.queryRows(
      'orders',
      orderBy: 'created_at_ms DESC',
    );
    orders
      ..clear()
      ..addAll(ordRows.map(ActiveOrderRecord.fromSqlRow));

    final geoRows = await _sqliteDb.queryRows('geofence_zones');
    geofenceZones.clear();
    if (geoRows.isNotEmpty) {
      geofenceZones
        ..clear()
        ..addAll(
          geoRows.map((r) {
            final rawPts =
                jsonDecode(r['boundary_json'].toString()) as List<dynamic>;
            return GeofenceZoneRecord(
              id: r['id'].toString(),
              zoneName: r['zone_name'].toString(),
              zoneType: r['zone_type'].toString(),
              surchargeRate: (r['surcharge_rate'] as num).toDouble(),
              isActive: (r['is_active'] as num).toInt() == 1,
              boundary: rawPts
                  .map(
                    (pt) => GeoPoint(
                      latitude:
                          ((pt as Map<String, dynamic>)['lat'] as num)
                              .toDouble(),
                      longitude: (pt['lng'] as num).toDouble(),
                    ),
                  )
                  .toList(),
            );
          }),
        );
    }

    final defaultRbacMap = <String, Map<String, bool>>{
      for (final r in rbacRoles) r.roleName: Map<String, bool>.from(r.permissions),
    };
    final rbacRows = await _sqliteDb.queryRows('admin_roles_permissions');
    if (rbacRows.isNotEmpty) {
      final migratedRoles = <RbacRoleRecord>[];
      for (final r in rbacRows) {
        final roleName = r['role_name'].toString();
        final decoded =
            jsonDecode(r['permissions_json'].toString()) as Map<String, dynamic>;
        final hadComplaintPerm = decoded.containsKey('Khiếu nại: Xử lý');
        final hadUserPerm = decoded.containsKey('User: Khóa/Mở');
        final defaults = defaultRbacMap[roleName] ?? const <String, bool>{};
        final merged = <String, bool>{
          ...defaults,
          for (final e in decoded.entries) e.key: e.value == true,
        };
        if (!hadComplaintPerm && roleName == 'Hỗ trợ CSKH') {
          merged['Khiếu nại: Xử lý'] = true;
          merged['Hệ thống: Cài đặt'] = false;
        }
        if (!hadComplaintPerm || !hadUserPerm) {
          await _sqliteDb.updateRows(
            'admin_roles_permissions',
            {
              'permissions_json': jsonEncode(merged),
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'role_name = ?',
            whereArgs: [roleName],
          );
        }
        migratedRoles.add(
          RbacRoleRecord(roleName: roleName, permissions: merged),
        );
      }
      rbacRoles
        ..clear()
        ..addAll(migratedRoles);
    }

    final wdRows = await _sqliteDb.queryRows(
      'wallets_and_transactions',
      orderBy: 'created_at_ms DESC',
    );
    withdrawalRequests.clear();
    if (wdRows.isNotEmpty) {
      withdrawalRequests
        ..clear()
        ..addAll(
          wdRows.map((r) {
            final wdId = r['id'].toString();
            final colOwnerId = r['owner_id']?.toString() ?? '';
            final metaOwnerId = colOwnerId.isNotEmpty
                ? colOwnerId
                : (withdrawalMeta[wdId]?['ownerId']?.toString() ?? '');
            return WithdrawalRequestRecord(
              id: wdId,
              ownerId: metaOwnerId,
              ownerName: r['owner_name'].toString(),
              ownerRole: r['owner_role'].toString(),
              amount: (r['amount'] as num).toDouble(),
              bankName: r['bank_name'].toString(),
              accountMasked: r['account_masked'].toString(),
              requestDate: r['request_date'].toString(),
              status: r['status'].toString(),
            );
          }),
        );
    }

    final compRows = await _sqliteDb.queryRows(
      'incidents_and_complaints',
      orderBy: 'created_at_ms DESC',
    );
    complaints.clear();
    if (compRows.isNotEmpty) {
      complaints
        ..clear()
        ..addAll(
          compRows.map((r) {
            final tCode = r['ticket_code'].toString();
            final repliesList =
                (jsonDecode(r['replies_json'].toString()) as List<dynamic>)
                    .map((e) => e.toString())
                    .toList();
            List<String> evList = const [];
            final colEvJson = r['evidence_files_json']?.toString();
            if (colEvJson != null && colEvJson.trim().startsWith('[')) {
              try {
                evList = (jsonDecode(colEvJson) as List<dynamic>)
                    .map((e) => e.toString())
                    .toList();
              } catch (_) {}
            } else {
              final rawEv = complaintMeta[tCode]?['evidenceFiles'];
              if (rawEv is List) {
                evList = rawEv.map((e) => e.toString()).toList();
              }
            }
            return ComplaintTicketRecord(
              ticketCode: tCode,
              orderId: r['order_id'].toString(),
              customerName: r['customer_name'].toString(),
              driverName: r['driver_name'].toString(),
              issueType: r['issue_type'].toString(),
              description: r['description'].toString(),
              status: r['status'].toString(),
              replies: repliesList,
              evidenceFiles: evList,
            );
          }),
        );
    }

    final chatNotiRows = await _sqliteDb.queryRows(
      'chat_messages_and_notifications',
      orderBy: 'created_at_ms ASC',
    );
    chatMessages.clear();
    notifications.clear();
    if (chatNotiRows.isNotEmpty) {
      final loadedChats = <ChatMessageRecord>[];
      final loadedNotis = <NotificationRecord>[];
      for (final r in chatNotiRows) {
        if (r['record_type'] == 'CHAT') {
          loadedChats.add(
            ChatMessageRecord(
              id: r['id'].toString(),
              orderId: (r['order_id'] ?? '').toString(),
              senderName: (r['sender_name'] ?? '').toString(),
              isCustomer: (r['is_customer'] as num?)?.toInt() == 1,
              text: r['content'].toString(),
              timeLabel: r['time_label'].toString(),
            ),
          );
        } else {
          final colRk = r['recipient_key']?.toString();
          loadedNotis.insert(
            0,
            NotificationRecord(
              id: r['id'].toString(),
              category: (r['category'] ?? 'Hệ thống').toString(),
              title: (r['title'] ?? r['content']).toString(),
              timeAgo: r['time_label'].toString(),
              targetGroup: (r['target_group'] ?? 'Khách hàng').toString(),
              recipientKey: (colRk != null && colRk.isNotEmpty)
                  ? colRk
                  : r['order_id']?.toString(),
              isRead: (r['is_read'] as num?)?.toInt() == 1,
            ),
          );
        }
      }
      if (loadedChats.isNotEmpty) {
        chatMessages
          ..clear()
          ..addAll(loadedChats);
      }
      if (loadedNotis.isNotEmpty) {
        notifications
          ..clear()
          ..addAll(loadedNotis);
      }
    }

    final seenRecMerchants = <String>{};
    final duplicateRecIds = <String>[];
    for (final rec in codReconciliations) {
      if (!seenRecMerchants.add(rec.merchantId)) {
        duplicateRecIds.add(rec.id);
      }
    }
    if (duplicateRecIds.isNotEmpty) {
      codReconciliations.removeWhere((r) => duplicateRecIds.contains(r.id));
      for (final dupId in duplicateRecIds) {
        await _sqliteDb.deleteRows(
          'cod_reconciliations',
          where: 'id = ?',
          whereArgs: [dupId],
        );
      }
    }

    final compRegex = RegExp(r'Đã cộng (\d+)đ tiền bồi thường');
    for (final mer in merchantApplicants) {
      _syncMerchantCodReconciliation(mer);
      final rec = codReconciliations
          .where((r) => r.merchantId == mer.id)
          .firstOrNull;
      if (rec == null) continue;
      final merStoreLower = mer.storeName.trim().toLowerCase();
      final merWithdrawals = withdrawalRequests
          .where(
            (w) =>
                w.ownerRole.contains('Cửa hàng') &&
                w.status != 'Từ chối' &&
                ((w.ownerId.isNotEmpty && w.ownerId == mer.id) ||
                    (w.ownerId.isEmpty &&
                        w.ownerName.trim().toLowerCase() == merStoreLower)),
          )
          .fold<double>(0.0, (s, w) => s + w.amount);
      final merOrderCodes = orders
          .where((o) => o.customerName.trim().toLowerCase() == merStoreLower)
          .map((o) => o.trackingCode)
          .toSet();
      double shopCompensations = 0.0;
      for (final c in complaints) {
        if (merOrderCodes.contains(c.orderId) ||
            c.customerName.trim().toLowerCase() == merStoreLower) {
          for (final rep in c.replies) {
            final match = compRegex.firstMatch(rep);
            if (match != null) {
              shopCompensations += double.tryParse(match.group(1)!) ?? 0.0;
            }
          }
        }
      }
      final expectedBalance =
          (rec.netPayoutAmount + shopCompensations - merWithdrawals)
              .clamp(0.0, double.infinity);
      if ((mer.codBalance - expectedBalance).abs() > 0.5) {
        mer.codBalance = expectedBalance;
        await _sqliteDb.updateRows(
          'merchants',
          {'cod_balance': mer.codBalance},
          where: 'id = ?',
          whereArgs: [mer.id],
        );
      }
    }
    if (merchantApplicants.isNotEmpty) {
      merchantCodBalance =
          (activeMerchantRecord ?? merchantApplicants.first).codBalance;
    }

    final persistedLogs = await _sqliteDb.getEntityRecords('system_audit_logs');
    if (persistedLogs.isNotEmpty) {
      systemAuditLogs
        ..clear()
        ..addAll(persistedLogs.take(80));
    } else if (systemAuditLogs.isEmpty) {
      systemAuditLogs.add({
        'action': 'SYSTEM_DATABASE_READY',
        'actor': 'SQLite Engine',
        'role': 'SYSTEM',
        'summary':
            '{"users":${users.length},"orders":${orders.length},"drivers":${drivers.length}}',
        'timestamp': DateTime.now().toIso8601String(),
      });
    }

    await loadAuthProviderConfigsFromDatabase();
    final activeSessionUser = activeAuthenticatedUser;
    if (activeSessionUser != null) {
      final refreshed = users
              .where((u) => u.id == activeSessionUser.id && u.phone == activeSessionUser.phone)
              .firstOrNull ??
          findUserByPhone(activeSessionUser.phone);
      if (refreshed != null) {
        applyAuthenticatedUserSession(refreshed);
      } else {
        clearAuthenticatedSession();
        customerFullName = customerPhone = customerEmail = customerDefaultAddress = '';
      }
    }
  }
}
