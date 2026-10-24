part of 'app_state_store.dart';

extension AppStateOrderAndAdminOps on AppStateStore {
  bool hasAdminPermission(String permKey) {
    final role =
        rbacRoles.where((r) => r.roleName == currentAdminRoleName).firstOrNull;
    if (role == null) return true;
    return role.permissions[permKey] ?? false;
  }

  void setAdminActiveRole(String roleName) {
    currentAdminRoleName = roleName;
    _notifyStoreChanged();
  }

  void addCustomGeofenceZone({
    required String zoneName,
    required String zoneType,
    required double surchargeRate,
    required List<GeoPoint> vertices,
  }) {
    if (vertices.length < 3) return;
    final newZone = GeofenceZoneRecord(
      id: 'GEO-0${geofenceZones.length + 1}',
      zoneName: zoneName,
      zoneType: zoneType,
      surchargeRate: surchargeRate,
      isActive: true,
      boundary: List<GeoPoint>.from(vertices),
    );
    geofenceZones.add(newZone);
    _sqliteDb.upsertRow('geofence_zones', {
      'id': newZone.id,
      'zone_name': newZone.zoneName,
      'zone_type': newZone.zoneType,
      'surcharge_rate': newZone.surchargeRate,
      'is_active': 1,
      'boundary_json': jsonEncode(
        newZone.boundary
            .map((pt) => {'lat': pt.latitude, 'lng': pt.longitude})
            .toList(),
      ),
    });
    _persistMutation('ADD_GEOFENCE_ZONE', {'zoneName': zoneName});
    _notifyStoreChanged();
  }

  void addCustomerAddress(String label, String address) {
    final resolved = SmartDispatchEngine.resolveAddressToCoordinate(
      address,
      fallback: const GeoPoint(latitude: 10.7785, longitude: 106.6980),
    );
    final normUserPhone = _normalizePhone(customerPhone);
    final newAddr = SavedAddressRecord(
      id: 'ADDR-0${savedAddresses.length + 1}',
      userPhone: normUserPhone,
      label: label,
      fullAddress: address,
      location: resolved,
    );
    savedAddresses.add(newAddr);
    _sqliteDb.upsertRow('user_addresses', {
      'id': newAddr.id,
      'user_phone': _normalizePhone(customerPhone),
      'label': newAddr.label,
      'full_address': newAddr.fullAddress,
      'latitude': newAddr.location.latitude,
      'longitude': newAddr.location.longitude,
      'created_at': DateTime.now().toIso8601String(),
    });
    _persistMutation('ADD_ADDRESS', {'label': label, 'address': address});
    _notifyStoreChanged();
  }

  void removeCustomerAddress(String id) {
    savedAddresses.removeWhere((a) => a.id == id);
    _sqliteDb.deleteRows('user_addresses', where: 'id = ?', whereArgs: [id]);
    _persistMutation('REMOVE_ADDRESS', {'id': id});
    _notifyStoreChanged();
  }

  ActiveOrderRecord createNewOrder({
    required String pickupAddress,
    required String dropoffAddress,
    required String recipientName,
    required String recipientPhone,
    required String packageDescription,
    required double weightKg,
    required String dimensionsCm,
    required DeliveryServiceType serviceType,
    required double codAmount,
    required String paymentMethod,
    String? voucherCode,
    int? customDistanceMeters,
    int? customDurationSeconds,
    bool? isPrepaidConfirmed,
  }) {
    final pickupPt = SmartDispatchEngine.resolveAddressToCoordinate(
      pickupAddress,
      fallback: const GeoPoint(latitude: 10.7769, longitude: 106.6953),
    );
    final dropoffPt = SmartDispatchEngine.resolveAddressToCoordinate(
      dropoffAddress,
      fallback: const GeoPoint(latitude: 10.7550, longitude: 106.6750),
    );

    final rawAirMeters = GeoMath.distanceMeters(pickupPt, dropoffPt);
    final isDefaultRoute = pickupAddress.contains('Phố Huế') &&
        dropoffAddress.contains('Lê Trọng Tấn');
    final distMeters = customDistanceMeters ??
        (isDefaultRoute
            ? 14500
            : (rawAirMeters * 1.28).round().clamp(1500, 45000));
    final durationSec = customDurationSeconds ??
        (isDefaultRoute
            ? 2700
            : ((distMeters / 1000.0) * 180).round());

    double geofenceFee = 0;
    for (final z in geofenceZones) {
      if (z.isActive &&
          z.surchargeRate > 0 &&
          GeoMath.isPointInPolygon(dropoffPt, z.boundary)) {
        geofenceFee += z.surchargeRate;
      }
    }
    if (isWeatherSurchargeActive) {
      geofenceFee += badWeatherSurchargeConfig;
    }
    if (weightKg > 5.0) {
      geofenceFee += ((weightKg - 5.0) * 3000).roundToDouble();
    }
    if (packageDescription.toLowerCase().contains('dễ vỡ')) {
      geofenceFee += 5000;
    }
    if (packageDescription.toLowerCase().contains('giữ lạnh')) {
      geofenceFee += 10000;
    }

    final baseScale = (baseFareConfig / 25000.0).clamp(0.4, 5.0);
    final kmScale = (pricePerKmConfig / 5000.0).clamp(0.4, 5.0);

    final preDiscountEst = PricingEstimate.calculate(
      serviceType: serviceType,
      distanceMeters: distMeters,
      durationSeconds: durationSec,
      isPeakHour: isPeakSurchargeActive,
      geofenceSurcharge: geofenceFee,
      voucherDiscount: 0,
      baseFareScale: baseScale,
      pricePerKmScale: kmScale,
    );

    double discount = 0;
    if (voucherCode != null && voucherCode.trim().isNotEmpty) {
      final matched = vouchers
          .where((v) => v.code.toUpperCase() == voucherCode.trim().toUpperCase())
          .firstOrNull;
      if (matched != null &&
          matched.status == 'Đang hoạt động' &&
          (preDiscountEst.totalAmount + codAmount) >= matched.minOrderValue) {
        if (matched.isPercentage) {
          final rawPct =
              preDiscountEst.totalAmount * (matched.discountValue / 100.0);
          discount = rawPct.clamp(0.0, matched.maxDiscount);
        } else {
          discount = matched.discountValue;
        }
      }
    }

    final est = PricingEstimate.calculate(
      serviceType: serviceType,
      distanceMeters: distMeters,
      durationSeconds: durationSec,
      isPeakHour: isPeakSurchargeActive,
      geofenceSurcharge: geofenceFee,
      voucherDiscount: discount,
      baseFareScale: baseScale,
      pricePerKmScale: kmScale,
    );

    final record = ActiveOrderRecord(
      id: 'ORD-${DateTime.now().millisecondsSinceEpoch}-${orders.length + 1}',
      trackingCode: '#DH${100000 + orders.length * 1423}',
      customerName: customerFullName,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      pickupAddress: pickupAddress,
      dropoffAddress: dropoffAddress,
      pickupLocation: pickupPt,
      dropoffLocation: dropoffPt,
      serviceType: serviceType,
      packageDescription: packageDescription,
      weightKg: weightKg,
      dimensionsCm: dimensionsCm,
      distanceMeters: distMeters,
      durationSeconds: durationSec,
      deliveryFee: est.baseFare + est.distanceFare,
      surchargeFee: est.surchargeFee,
      discountAmount: est.discountAmount,
      codAmount: codAmount,
      totalAmount: est.totalAmount,
      paymentMethod: paymentMethod,
      paymentStatus: (paymentMethod == 'Tiền mặt (COD)' ||
              paymentMethod == 'Người nhận trả phí' ||
              paymentMethod == 'Người gửi trả phí' ||
              isPrepaidConfirmed == false)
          ? 'UNPAID'
          : 'PAID',
      status: OrderStatus.searching,
      createdDateLabel: 'Hôm nay',
    );
    orders.insert(0, record);
    selectedCustomerOrderCode = record.trackingCode;
    _sqliteDb.upsertRow('orders', record.toSqlRow());
    activeRoutePolyline = SmartDispatchEngine.generateRoutePolyline(
      pickupPt,
      dropoffPt,
      segments: 10,
    );
    _pushRealtimeNotification(
      category: 'Đơn hàng',
      title:
          'Đơn hàng ${record.trackingCode} đã được khởi tạo (${est.totalAmount.toStringAsFixed(0)}đ). Hệ thống đang tìm tài xế.',
      targetGroup: 'Khách hàng',
    );
    if (isOfflineMode) offlineQueueCount++;
    _persistMutation('CREATE_ORDER', {'trackingCode': record.trackingCode});
    _notifyStoreChanged();
    return record;
  }

  void _pushRealtimeNotification({
    required String category,
    required String title,
    String targetGroup = 'Khách hàng',
  }) {
    final noti = NotificationRecord(
      id: 'NOTI-${DateTime.now().millisecondsSinceEpoch}-${notifications.length + 1}',
      category: category,
      title: title,
      targetGroup: targetGroup,
      timeAgo: 'Vừa xong',
    );
    notifications.insert(0, noti);
    _sqliteDb.upsertRow('chat_messages_and_notifications', {
      'id': noti.id,
      'record_type': 'NOTIFICATION',
      'order_id': null,
      'sender_name': 'Hệ thống',
      'is_customer': 0,
      'category': noti.category,
      'title': noti.title,
      'content': noti.title,
      'target_group': noti.targetGroup,
      'time_label': noti.timeAgo,
      'is_read': 0,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _recordOrderStatusHistory(
    String orderId,
    OrderStatus status,
    String note,
  ) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _sqliteDb.upsertRow('local_relational_entities', {
      'table_name': 'order_status_histories',
      'record_id': 'HIST-$orderId-${status.name}-$nowMs',
      'payload_json': jsonEncode({
        'order_id': orderId,
        'status': status.name,
        'note': note,
        'updated_at': DateTime.now().toIso8601String(),
      }),
      'updated_at_ms': nowMs,
    });
  }

  void driverAcceptOrder(
    String trackingCode, {
    String? customDriverName,
    String? customPlate,
  }) {
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord == null) return;
    if (!ord.status.canTransitionTo(OrderStatus.accepted)) return;
    if (!isDriverOnline) return;
    final activeDrv =
        drivers.where((d) => d.id == activeDriverId).firstOrNull ??
            drivers.firstOrNull;
    if (activeDrv != null && activeDrv.approvalStatus != 'Đã duyệt') return;
    ord.status = OrderStatus.accepted;
    ord.assignedDriverName =
        customDriverName ?? activeDrv?.fullName ?? activeDriverName;
    ord.assignedDriverPlate =
        customPlate ?? activeDrv?.licensePlate ?? '59-P1 123.45';
    selectedDriverOrderCode = trackingCode;
    activeRoutePolyline = SmartDispatchEngine.generateRoutePolyline(
      ord.pickupLocation,
      ord.dropoffLocation,
      segments: 10,
    );
    activeDriverLocation = ord.pickupLocation;
    routeProgressStep = 0;
    _sqliteDb.updateRows(
      'orders',
      {
        'status': ord.status.name,
        'assigned_driver_name': ord.assignedDriverName,
        'assigned_driver_plate': ord.assignedDriverPlate,
      },
      where: 'tracking_code = ?',
      whereArgs: [trackingCode],
    );
    _recordOrderStatusHistory(
      ord.id,
      ord.status,
      'Tài xế ${ord.assignedDriverName} (${ord.assignedDriverPlate}) đã nhận đơn',
    );
    _pushRealtimeNotification(
      category: 'Đơn hàng',
      title:
          'Tài xế ${ord.assignedDriverName} (${ord.assignedDriverPlate}) đã nhận đơn ${ord.trackingCode}.',
      targetGroup: 'Khách hàng',
    );
    _persistMutation('DRIVER_ACCEPT_ORDER', {'trackingCode': trackingCode});
    _notifyStoreChanged();
  }

  bool adminAssignOrReassignDriver({
    required String trackingCode,
    required DriverApplicantRecord driver,
  }) {
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord == null) return false;
    if (ord.status == OrderStatus.delivered ||
        ord.status == OrderStatus.cancelled) {
      return false;
    }
    if (driver.approvalStatus != 'Đã duyệt' || !driver.isOnline) return false;
    if (ord.status == OrderStatus.searching ||
        ord.status == OrderStatus.draft ||
        ord.status == OrderStatus.failed) {
      ord.status = OrderStatus.accepted;
      ord.cancelReason = null;
    }
    ord.assignedDriverName = driver.fullName;
    ord.assignedDriverPlate = driver.licensePlate;
    selectedDriverOrderCode = trackingCode;
    activeRoutePolyline = SmartDispatchEngine.generateRoutePolyline(
      ord.pickupLocation,
      ord.dropoffLocation,
      segments: 10,
    );
    activeDriverLocation = ord.pickupLocation;
    routeProgressStep = 0;
    _sqliteDb.updateRows(
      'orders',
      {
        'status': ord.status.name,
        'assigned_driver_name': ord.assignedDriverName,
        'assigned_driver_plate': ord.assignedDriverPlate,
        'cancel_reason': ord.cancelReason,
      },
      where: 'tracking_code = ?',
      whereArgs: [trackingCode],
    );
    _recordOrderStatusHistory(
      ord.id,
      ord.status,
      'Quản trị viên gán/điều phối lại cho tài xế ${driver.fullName} (${driver.licensePlate})',
    );
    _persistMutation('ADMIN_ASSIGN_DRIVER', {
      'trackingCode': trackingCode,
      'driverId': driver.id,
      'driverName': driver.fullName,
    });
    _notifyStoreChanged();
    return true;
  }

  void driverAdvanceOrderStatus(String trackingCode, {String? podNote}) {
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord == null) return;
    final activeDrv =
        drivers.where((d) => d.id == activeDriverId).firstOrNull ??
            drivers.firstOrNull;
    switch (ord.status) {
      case OrderStatus.searching:
      case OrderStatus.draft:
        ord.status = OrderStatus.accepted;
        ord.assignedDriverName = activeDrv?.fullName ?? activeDriverName;
        ord.assignedDriverPlate = activeDrv?.licensePlate ?? '59-P1 123.45';
      case OrderStatus.accepted:
        ord.status = OrderStatus.arrivingPickup;
      case OrderStatus.arrivingPickup:
        ord.status = OrderStatus.inTransit;
      case OrderStatus.inTransit:
        ord.status = OrderStatus.delivered;
        ord.paymentStatus = 'PAID';
        ord.podImageNote =
            podNote ?? 'Đã chụp ảnh kiện hàng kèm Watermark GPS & OTP 4 số';
        final driverNetEarning =
            ((ord.deliveryFee + ord.surchargeFee) * 0.80).roundToDouble();
        driverWalletBalance += driverNetEarning;
        if (ord.codAmount > 0) {
          final codHandlingFee = ord.codAmount > 2000000
              ? (ord.codAmount * 0.005).roundToDouble()
              : 0.0;
          final isShipPrepaidOrRecipientPaid =
              ord.paymentMethod == 'Người nhận trả phí' ||
                  ord.paymentMethod.contains('MoMo') ||
                  ord.paymentMethod.contains('VNPay') ||
                  ord.paymentMethod.contains('ZaloPay');
          final shipDeduct =
              isShipPrepaidOrRecipientPaid ? 0.0 : ord.totalAmount;
          final netMerchantCod =
              (ord.codAmount - shipDeduct - codHandlingFee)
                  .clamp(0.0, double.infinity);
          merchantCodBalance += netMerchantCod;
        }
        if (activeDrv != null) {
          activeDrv.totalTrips += 1;
        }
        _sqliteDb.updateRows(
          'drivers',
          {
            'wallet_balance': driverWalletBalance,
            if (activeDrv != null) 'total_trips': activeDrv.totalTrips,
          },
          where: 'id = ?',
          whereArgs: [activeDrv?.id ?? activeDriverId],
        );
        final targetMerId =
            (activeMerchantRecord ?? merchantApplicants.firstOrNull)?.id ??
                'MER-01';
        _sqliteDb.updateRows(
          'merchants',
          {'cod_balance': merchantCodBalance},
          where: 'id = ?',
          whereArgs: [targetMerId],
        );
      case OrderStatus.failed:
        ord.status = OrderStatus.inTransit;
        ord.cancelReason = null;
      case OrderStatus.returning:
        ord.status = OrderStatus.delivered;
        ord.paymentStatus = 'RETURNED';
        ord.podImageNote =
            podNote ?? 'Đã hoàn trả kiện hàng về kho Cửa hàng thành công';
      default:
        break;
    }
    _sqliteDb.updateRows(
      'orders',
      {
        'status': ord.status.name,
        'payment_status': ord.paymentStatus,
        'assigned_driver_name': ord.assignedDriverName,
        'assigned_driver_plate': ord.assignedDriverPlate,
        'pod_image_note': ord.podImageNote,
      },
      where: 'tracking_code = ?',
      whereArgs: [trackingCode],
    );
    _recordOrderStatusHistory(
      ord.id,
      ord.status,
      ord.podImageNote ?? 'Cập nhật trạng thái vận đơn sang ${ord.status.displayName}',
    );
    _pushRealtimeNotification(
      category: 'Đơn hàng',
      title:
          'Đơn hàng ${ord.trackingCode}: Trạng thái chuyển sang "${ord.status.displayName}".',
      targetGroup: 'Khách hàng',
    );
    if (isOfflineMode) offlineQueueCount++;
    _persistMutation('ADVANCE_ORDER_STATUS', {
      'trackingCode': trackingCode,
      'status': ord.status.name,
    });
    _notifyStoreChanged();
  }

  bool cancelOrder(String trackingCode, String reason) {
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord == null) return false;
    if (!ord.status.canTransitionTo(OrderStatus.cancelled)) {
      return false;
    }
    ord.status = OrderStatus.cancelled;
    ord.cancelReason = reason;
    _sqliteDb.updateRows(
      'orders',
      {
        'status': ord.status.name,
        'cancel_reason': reason,
      },
      where: 'tracking_code = ?',
      whereArgs: [trackingCode],
    );
    _persistMutation('CANCEL_ORDER', {
      'trackingCode': trackingCode,
      'reason': reason,
    });
    _notifyStoreChanged();
    return true;
  }

  void submitDriverRating(
    String trackingCode,
    int stars,
    String comment, {
    double tipVnd = 0,
  }) {
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord != null &&
        ord.status == OrderStatus.delivered &&
        ord.paymentStatus != 'RETURNED') {
      final wasAlreadyRated = ord.ratingStars != null;
      ord.ratingStars = stars;
      ord.ratingComment = comment;
      if (!wasAlreadyRated && tipVnd > 0) {
        driverWalletBalance += tipVnd;
      }
      final targetDrv = (ord.assignedDriverName != null
              ? drivers
                  .where((d) => d.fullName == ord.assignedDriverName)
                  .firstOrNull
              : null) ??
          drivers.where((d) => d.id == activeDriverId).firstOrNull ??
          drivers.firstOrNull;
      final ratedList = orders.where((o) => o.ratingStars != null).toList();
      if (targetDrv != null && ratedList.isNotEmpty) {
        final driverRatedList = ratedList
            .where((o) => o.assignedDriverName == targetDrv.fullName)
            .toList();
        final relevantOrders =
            driverRatedList.isNotEmpty ? driverRatedList : ratedList;
        final avg =
            relevantOrders.fold<int>(0, (s, o) => s + o.ratingStars!) /
                relevantOrders.length;
        targetDrv.rating = double.parse(avg.toStringAsFixed(1));
      }
      _sqliteDb.updateRows(
        'drivers',
        {
          'wallet_balance': driverWalletBalance,
          if (targetDrv != null) 'rating': targetDrv.rating,
        },
        where: 'id = ?',
        whereArgs: [targetDrv?.id ?? activeDriverId],
      );
      _sqliteDb.updateRows(
        'orders',
        {
          'rating_stars': stars,
          'rating_comment': comment,
        },
        where: 'tracking_code = ?',
        whereArgs: [trackingCode],
      );
      _sqliteDb.upsertRow('order_ratings', {
        'id': 'RAT-${ord.id}',
        'order_tracking_code': trackingCode,
        'customer_name': ord.customerName,
        'driver_name': ord.assignedDriverName ?? activeDriverName,
        'stars': stars,
        'comment': comment,
        'created_at': DateTime.now().toIso8601String(),
      });
      _persistMutation('SUBMIT_RATING', {
        'trackingCode': trackingCode,
        'stars': stars,
        'tipVnd': wasAlreadyRated ? 0 : tipVnd,
      });
    }
    _notifyStoreChanged();
  }

  void sendChatMessage(String orderId, String text, {required bool isCustomer}) {
    if (text.trim().isEmpty) return;
    final msg = ChatMessageRecord(
      id: 'MSG-${DateTime.now().millisecondsSinceEpoch}-${chatMessages.length + 1}',
      orderId: orderId,
      senderName: isCustomer ? customerFullName : activeDriverName,
      isCustomer: isCustomer,
      text: text.trim(),
      timeLabel: 'Vừa xong',
    );
    chatMessages.add(msg);
    _sqliteDb.upsertRow('chat_messages_and_notifications', {
      'id': msg.id,
      'record_type': 'CHAT',
      'order_id': msg.orderId,
      'sender_name': msg.senderName,
      'is_customer': msg.isCustomer ? 1 : 0,
      'category': 'CHAT_MESSAGE',
      'title': msg.senderName,
      'content': msg.text,
      'target_group': 'INDIVIDUAL',
      'time_label': msg.timeLabel,
      'is_read': 1,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
    _persistMutation('SEND_CHAT', {'orderId': orderId, 'text': text.trim()});
    _notifyStoreChanged();
  }

  bool requestWithdrawal({
    required String ownerName,
    required String ownerRole,
    required double amount,
    required String bankName,
    required String accountMasked,
  }) {
    if (amount <= 0) return false;
    if (ownerRole == 'Tài xế') {
      if (driverWalletBalance - amount < 200000) return false;
      driverWalletBalance -= amount;
      _sqliteDb.updateRows(
        'drivers',
        {'wallet_balance': driverWalletBalance},
        where: 'id = ?',
        whereArgs: [activeDriverId],
      );
    } else {
      if (merchantCodBalance < amount) return false;
      merchantCodBalance -= amount;
      final targetMerId =
          (activeMerchantRecord ?? merchantApplicants.firstOrNull)?.id ??
              'MER-01';
      _sqliteDb.updateRows(
        'merchants',
        {'cod_balance': merchantCodBalance},
        where: 'id = ?',
        whereArgs: [targetMerId],
      );
    }
    final req = WithdrawalRequestRecord(
      id: 'WD-${DateTime.now().millisecondsSinceEpoch}-${withdrawalRequests.length + 1}',
      ownerName: ownerName,
      ownerRole: ownerRole,
      amount: amount,
      bankName: bankName,
      accountMasked: accountMasked,
      requestDate: 'Vừa xong',
      status: 'Chờ duyệt',
    );
    withdrawalRequests.insert(0, req);
    _sqliteDb.upsertRow('wallets_and_transactions', {
      'id': req.id,
      'owner_name': req.ownerName,
      'owner_role': req.ownerRole,
      'amount': req.amount,
      'bank_name': req.bankName,
      'account_masked': req.accountMasked,
      'request_date': req.requestDate,
      'status': req.status,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
    _persistMutation('REQUEST_WITHDRAWAL', {
      'ownerRole': ownerRole,
      'amount': amount,
    });
    _notifyStoreChanged();
    return true;
  }

  void updateWithdrawalStatus(String id, String status) {
    final req = withdrawalRequests.where((w) => w.id == id).firstOrNull;
    if (req != null && req.status == 'Chờ duyệt') {
      final previousStatus = req.status;
      req.status = status;
      if (previousStatus == 'Chờ duyệt' && status == 'Từ chối') {
        if (req.ownerRole == 'Tài xế') {
          driverWalletBalance += req.amount;
          _sqliteDb.updateRows(
            'drivers',
            {'wallet_balance': driverWalletBalance},
            where: 'id = ?',
            whereArgs: [activeDriverId],
          );
        } else {
          merchantCodBalance += req.amount;
          final targetMerId =
              (activeMerchantRecord ?? merchantApplicants.firstOrNull)?.id ??
                  'MER-01';
          _sqliteDb.updateRows(
            'merchants',
            {'cod_balance': merchantCodBalance},
            where: 'id = ?',
            whereArgs: [targetMerId],
          );
        }
      }
      _sqliteDb.updateRows(
        'wallets_and_transactions',
        {'status': status},
        where: 'id = ?',
        whereArgs: [id],
      );
      _pushRealtimeNotification(
        category: 'Hệ thống',
        title:
            'Lệnh rút tiền ${req.id} (${req.amount.toStringAsFixed(0)}đ • ${req.bankName}) đã chuyển sang trạng thái: $status.',
        targetGroup: req.ownerRole == 'Tài xế' ? 'Tài xế' : 'Cửa hàng B2B',
      );
      _persistMutation('UPDATE_WITHDRAWAL', {'id': id, 'status': status});
      _notifyStoreChanged();
    }
  }

  void updateDriverApproval(String id, String status) {
    final drv = drivers.where((d) => d.id == id).firstOrNull;
    if (drv != null) {
      drv.approvalStatus = status;
      drv.isOnline = status == 'Đã duyệt';
      if (drv.id == activeDriverId) {
        isDriverOnline = drv.isOnline;
      }
      _sqliteDb.updateRows(
        'drivers',
        {
          'approval_status': status,
          'is_online': drv.isOnline ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      final user = findUserByPhone(drv.phone);
      if (user != null && user.role != SubsystemRole.admin) {
        if (status == 'Đã duyệt') {
          user.role = SubsystemRole.driver;
        } else if (status == 'Từ chối' && user.role == SubsystemRole.driver) {
          user.role = SubsystemRole.customer;
        }
        _sqliteDb.updateRows(
          'users',
          {'role': user.roleDbCode},
          where: 'id = ?',
          whereArgs: [user.id],
        );
      }
      _pushRealtimeNotification(
        category: 'Hệ thống',
        title:
            'Hồ sơ Tài xế ${drv.fullName} (${drv.id} • ${drv.licensePlate}) đã chuyển sang trạng thái: $status.',
        targetGroup: 'Tài xế',
      );
      _persistMutation('UPDATE_DRIVER_APPROVAL', {'id': id, 'status': status});
      _notifyStoreChanged();
    }
  }

  void updateMerchantApproval(String id, String status) {
    final mer = merchantApplicants.where((m) => m.id == id).firstOrNull;
    if (mer != null) {
      mer.approvalStatus = status;
      _sqliteDb.updateRows(
        'merchants',
        {'approval_status': status},
        where: 'id = ?',
        whereArgs: [id],
      );
      final user = findUserByPhone(mer.ownerPhone);
      if (user != null && user.role != SubsystemRole.admin) {
        if (status == 'Đã duyệt') {
          user.role = SubsystemRole.merchant;
          merchantStoreName = mer.storeName;
          merchantBusinessType = mer.businessType;
          merchantTaxCode = mer.taxCode;
          merchantRepresentative = mer.representativeName;
          merchantOpenHours = mer.openHours;
          merchantBankName = mer.bankName;
          merchantBankAccount = mer.bankAccount;
        } else if (status == 'Từ chối' && user.role == SubsystemRole.merchant) {
          user.role = SubsystemRole.customer;
        }
        _sqliteDb.updateRows(
          'users',
          {'role': user.roleDbCode},
          where: 'id = ?',
          whereArgs: [user.id],
        );
      }
      _pushRealtimeNotification(
        category: 'Hệ thống',
        title:
            'Hồ sơ Cửa hàng B2B ${mer.storeName} (${mer.id}) đã chuyển sang trạng thái: $status.',
        targetGroup: 'Cửa hàng B2B',
      );
      _persistMutation('UPDATE_MERCHANT_APPROVAL', {
        'id': id,
        'status': status,
      });
      _notifyStoreChanged();
    }
  }

  void addIncidentOrComplaint({
    required String orderId,
    required String reporterName,
    required String issueType,
    required String description,
  }) {
    final item = ComplaintTicketRecord(
      ticketCode: 'KN-00${complaints.length + 1}',
      orderId: orderId,
      customerName: reporterName,
      driverName: activeDriverName,
      issueType: issueType,
      description: description,
      status: 'Mới',
      replies: ['$reporterName: $description'],
    );
    complaints.insert(0, item);
    _sqliteDb.upsertRow('incidents_and_complaints', {
      'ticket_code': item.ticketCode,
      'order_id': item.orderId,
      'customer_name': item.customerName,
      'driver_name': item.driverName,
      'issue_type': item.issueType,
      'description': item.description,
      'status': item.status,
      'replies_json': jsonEncode(item.replies),
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
    if (reporterName.startsWith('Tài xế') &&
        (issueType == 'Hàng bị hỏng' ||
            issueType == 'Khách không nhận hàng' ||
            issueType == 'Tai nạn / Xe hỏng')) {
      final ord = orders.where((o) => o.trackingCode == orderId).firstOrNull;
      if (ord != null && ord.status.canTransitionTo(OrderStatus.failed)) {
        ord.status = OrderStatus.failed;
        ord.cancelReason = '$issueType: $description';
        _sqliteDb.updateRows(
          'orders',
          {
            'status': ord.status.name,
            'cancel_reason': ord.cancelReason,
          },
          where: 'tracking_code = ?',
          whereArgs: [orderId],
        );
      }
    }
    _persistMutation('ADD_COMPLAINT', {'orderId': orderId});
    _notifyStoreChanged();
  }

  void replyComplaint(String ticketCode, String replyText, String nextStatus) {
    final item =
        complaints.where((c) => c.ticketCode == ticketCode).firstOrNull;
    if (item != null) {
      final wasResolved = item.status == 'Đã giải quyết';
      item.status = nextStatus;
      if (replyText.trim().isNotEmpty) {
        item.replies.add('Admin: ${replyText.trim()}');
      }
      if (!wasResolved && nextStatus == 'Đã giải quyết') {
        final lowerIssue = item.issueType.toLowerCase();
        final isCompensableIssue = lowerIssue.contains('hỏng') ||
            lowerIssue.contains('mất') ||
            lowerIssue.contains('thiếu') ||
            lowerIssue.contains('cod') ||
            lowerIssue.contains('sai phí') ||
            lowerIssue.contains('sai cước');
        if (isCompensableIssue) {
          final relatedOrder =
              orders.where((o) => o.trackingCode == item.orderId).firstOrNull;
          final compensation =
              relatedOrder != null && relatedOrder.codAmount > 0
                  ? (relatedOrder.codAmount * 0.20).clamp(50000.0, 500000.0)
                  : 100000.0;
          merchantCodBalance += compensation;
          final targetMerId =
              (activeMerchantRecord ?? merchantApplicants.firstOrNull)?.id ??
                  'MER-01';
          _sqliteDb.updateRows(
            'merchants',
            {'cod_balance': merchantCodBalance},
            where: 'id = ?',
            whereArgs: [targetMerId],
          );
          item.replies.add(
            'Hệ thống: Đã cộng ${compensation.toStringAsFixed(0)}đ tiền bồi thường vào ví đối soát.',
          );
        } else {
          item.replies.add(
            'Hệ thống: Đã xác nhận xử lý và đóng hồ sơ sự cố/khiếu nại.',
          );
        }
      }
      _sqliteDb.updateRows(
        'incidents_and_complaints',
        {
          'status': item.status,
          'replies_json': jsonEncode(item.replies),
        },
        where: 'ticket_code = ?',
        whereArgs: [ticketCode],
      );
      _persistMutation('REPLY_COMPLAINT', {'ticketCode': ticketCode});
      _pushRealtimeNotification(
        category: 'Hệ thống',
        title:
            'Khiếu nại ${item.ticketCode} (Đơn ${item.orderId}) đã chuyển sang trạng thái: ${item.status}.',
        targetGroup: 'Tất cả người dùng',
      );
      _notifyStoreChanged();
    }
  }

  void broadcastSystemNotification({
    required String title,
    required String targetGroup,
  }) {
    if (title.trim().isEmpty) return;
    final noti = NotificationRecord(
      id: 'NOTI-${DateTime.now().millisecondsSinceEpoch}-${notifications.length + 1}',
      category: 'Hệ thống',
      title: title.trim(),
      targetGroup: targetGroup,
      timeAgo: 'Vừa xong',
    );
    notifications.insert(0, noti);
    _sqliteDb.upsertRow('chat_messages_and_notifications', {
      'id': noti.id,
      'record_type': 'NOTIFICATION',
      'order_id': null,
      'sender_name': 'Hệ thống',
      'is_customer': 0,
      'category': noti.category,
      'title': noti.title,
      'content': noti.title,
      'target_group': noti.targetGroup,
      'time_label': noti.timeAgo,
      'is_read': 0,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
    _persistMutation('BROADCAST_NOTIFICATION', {'title': title});
    _notifyStoreChanged();
  }

  void toggleRbacPermission(String roleName, String permKey, bool value) {
    final role = rbacRoles.where((r) => r.roleName == roleName).firstOrNull;
    if (role != null) {
      role.permissions[permKey] = value;
      _sqliteDb.updateRows(
        'admin_roles_permissions',
        {
          'permissions_json': jsonEncode(role.permissions),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'role_name = ?',
        whereArgs: [roleName],
      );
      _persistMutation('TOGGLE_RBAC', {'roleName': roleName, 'permKey': permKey});
      _notifyStoreChanged();
    }
  }

  void toggleGeofenceZone(String id, bool active) {
    final z = geofenceZones.where((g) => g.id == id).firstOrNull;
    if (z != null) {
      z.isActive = active;
      _sqliteDb.updateRows(
        'geofence_zones',
        {'is_active': active ? 1 : 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      _persistMutation('TOGGLE_GEOFENCE', {'id': id, 'active': active});
      _notifyStoreChanged();
    }
  }

  void toggleCustomerSocialLink({
    required String provider,
    required bool linked,
  }) {
    if (provider.toUpperCase() == 'GOOGLE') {
      isCustomerGoogleLinked = linked;
    } else {
      isCustomerTwoFactorEnabled = linked;
    }
    _persistMutation('TOGGLE_SOCIAL_LINK', {
      'provider': provider,
      'linked': linked,
    });
    _notifyStoreChanged();
  }

  void markAllNotificationsAsRead() {
    for (final n in notifications) {
      n.isRead = true;
    }
    _sqliteDb.updateRows(
      'chat_messages_and_notifications',
      {'is_read': 1},
      where: 'record_type = ?',
      whereArgs: ['NOTIFICATION'],
    );
    _persistMutation('MARK_ALL_NOTIFICATIONS_READ', {
      'count': notifications.length,
    });
    _notifyStoreChanged();
  }

  void markNotificationAsRead(String id) {
    final target = notifications.where((n) => n.id == id).firstOrNull;
    if (target == null || target.isRead) return;
    target.isRead = true;
    _sqliteDb.updateRows(
      'chat_messages_and_notifications',
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    _persistMutation('MARK_NOTIFICATION_READ', {'id': id});
    _notifyStoreChanged();
  }

  PickupWarehouseRecord addMerchantWarehouse({
    required String name,
    required String address,
  }) {
    final pt = SmartDispatchEngine.resolveAddressToCoordinate(
      address,
      fallback: const GeoPoint(latitude: 10.7765, longitude: 106.6920),
    );
    final wh = PickupWarehouseRecord(
      id: 'WH-0${merchantWarehouses.length + 1}',
      name: name.trim(),
      address: address.trim(),
      location: pt,
    );
    merchantWarehouses.add(wh);
    final targetMerId =
        (activeMerchantRecord ?? merchantApplicants.firstOrNull)?.id ??
            'MER-01';
    _sqliteDb.upsertRow('merchant_pickup_points', {
      'id': wh.id,
      'merchant_id': targetMerId,
      'warehouse_name': wh.name,
      'full_address': wh.address,
      'latitude': wh.location.latitude,
      'longitude': wh.location.longitude,
      'created_at': DateTime.now().toIso8601String(),
    });
    _persistMutation('ADD_MERCHANT_WAREHOUSE', {
      'id': wh.id,
      'name': wh.name,
      'address': wh.address,
    });
    _notifyStoreChanged();
    return wh;
  }

  bool deleteMerchantWarehouse(String warehouseId) {
    if (merchantWarehouses.length <= 1) return false;
    final existed = merchantWarehouses.any((w) => w.id == warehouseId);
    if (!existed) return false;
    merchantWarehouses.removeWhere((w) => w.id == warehouseId);
    _sqliteDb.deleteRows(
      'merchant_pickup_points',
      where: 'id = ?',
      whereArgs: [warehouseId],
    );
    _persistMutation('DELETE_MERCHANT_WAREHOUSE', {'id': warehouseId});
    _notifyStoreChanged();
    return true;
  }

  void setDefaultCustomerAddress(String addressText) {
    final cleanAddr = addressText.trim();
    if (cleanAddr.isEmpty) return;
    customerDefaultAddress = cleanAddr;
    final resolvedLoc = SmartDispatchEngine.resolveAddressToCoordinate(
      cleanAddr,
      fallback: activeDriverLocation,
    );
    final activeUser = activeAuthenticatedUser;
    if (activeUser != null) {
      activeUser.defaultAddress = cleanAddr;
      activeUser.defaultLocation = resolvedLoc;
      _sqliteDb.updateRows(
        'users',
        {
          'default_address': cleanAddr,
          'default_lat': resolvedLoc.latitude,
          'default_lng': resolvedLoc.longitude,
        },
        where: 'id = ?',
        whereArgs: [activeUser.id],
      );
    }
    _persistMutation('SET_DEFAULT_CUSTOMER_ADDRESS', {'address': cleanAddr});
    _notifyStoreChanged();
  }

  bool updateExistingOrderDetails({
    required String trackingCode,
    required String recipientName,
    required String recipientPhone,
    required String dropoffAddress,
    required double codAmount,
  }) {
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord == null) return false;
    if (ord.status == OrderStatus.delivered ||
        ord.status == OrderStatus.cancelled) {
      return false;
    }
    ord.recipientName = recipientName.trim();
    ord.recipientPhone = recipientPhone.trim();
    ord.dropoffAddress = dropoffAddress.trim();
    ord.dropoffLocation = SmartDispatchEngine.resolveAddressToCoordinate(
      dropoffAddress.trim(),
      fallback: ord.dropoffLocation,
    );
    final newAirMeters =
        GeoMath.distanceMeters(ord.pickupLocation, ord.dropoffLocation);
    ord.distanceMeters = (newAirMeters * 1.28).round().clamp(1200, 45000);
    ord.durationSeconds = ((ord.distanceMeters / 1000.0) * 180).round();
    ord.codAmount = codAmount;

    double geofenceFee = 0;
    for (final z in geofenceZones) {
      if (z.isActive &&
          z.surchargeRate > 0 &&
          GeoMath.isPointInPolygon(ord.dropoffLocation, z.boundary)) {
        geofenceFee += z.surchargeRate;
      }
    }
    if (isWeatherSurchargeActive) {
      geofenceFee += badWeatherSurchargeConfig;
    }
    if (ord.weightKg > 5.0) {
      geofenceFee += ((ord.weightKg - 5.0) * 3000).roundToDouble();
    }
    if (ord.packageDescription.toLowerCase().contains('dễ vỡ')) {
      geofenceFee += 5000;
    }
    if (ord.packageDescription.toLowerCase().contains('giữ lạnh')) {
      geofenceFee += 10000;
    }
    final baseScale = (baseFareConfig / 25000.0).clamp(0.4, 5.0);
    final kmScale = (pricePerKmConfig / 5000.0).clamp(0.4, 5.0);
    final newEst = PricingEstimate.calculate(
      serviceType: ord.serviceType,
      distanceMeters: ord.distanceMeters,
      durationSeconds: ord.durationSeconds,
      isPeakHour: isPeakSurchargeActive,
      geofenceSurcharge: geofenceFee,
      voucherDiscount: ord.discountAmount,
      baseFareScale: baseScale,
      pricePerKmScale: kmScale,
    );
    ord.deliveryFee = newEst.baseFare + newEst.distanceFare;
    ord.surchargeFee = newEst.surchargeFee;
    ord.totalAmount = newEst.totalAmount;

    _sqliteDb.updateRows(
      'orders',
      {
        'recipient_name': ord.recipientName,
        'recipient_phone': ord.recipientPhone,
        'dropoff_address': ord.dropoffAddress,
        'dropoff_lat': ord.dropoffLocation.latitude,
        'dropoff_lng': ord.dropoffLocation.longitude,
        'distance_meters': ord.distanceMeters,
        'duration_seconds': ord.durationSeconds,
        'delivery_fee': ord.deliveryFee,
        'surcharge_fee': ord.surchargeFee,
        'cod_amount': ord.codAmount,
        'total_amount': ord.totalAmount,
      },
      where: 'tracking_code = ?',
      whereArgs: [trackingCode],
    );
    _persistMutation('UPDATE_ORDER_DETAILS', {
      'trackingCode': trackingCode,
      'recipientName': ord.recipientName,
      'codAmount': ord.codAmount,
    });
    _notifyStoreChanged();
    return true;
  }

  VoucherRecord createNewVoucher({
    required String code,
    required String title,
    required double discountValue,
    required bool isPercentage,
    required double minOrderValue,
    String expiryDate = '31/12/2026',
  }) {
    final cleanCode = code.trim().toUpperCase();
    final label = isPercentage
        ? 'Giảm ${discountValue.toStringAsFixed(0)}%'
        : 'Giảm ${(discountValue / 1000).toStringAsFixed(0)}k';
    final record = VoucherRecord(
      code: cleanCode,
      title: title.trim(),
      discountLabel: label,
      discountValue: discountValue,
      isPercentage: isPercentage,
      maxDiscount: isPercentage ? 30000 : discountValue,
      minOrderValue: minOrderValue,
      expiryDate: expiryDate,
      status: 'Đang hoạt động',
    );
    vouchers.removeWhere((v) => v.code == cleanCode);
    vouchers.insert(0, record);
    _sqliteDb.upsertRow('vouchers', {
      'code': record.code,
      'title': record.title,
      'discount_label': record.discountLabel,
      'discount_value': record.discountValue,
      'is_percentage': record.isPercentage ? 1 : 0,
      'max_discount': record.maxDiscount,
      'min_order_value': record.minOrderValue,
      'expiry_date': record.expiryDate,
      'status': record.status,
    });
    _persistMutation('CREATE_VOUCHER', {'code': record.code});
    _pushRealtimeNotification(
      category: 'Khuyến mãi',
      title:
          'Mã ưu đãi mới ${record.code} (${record.discountLabel}): ${record.title} • HSD: ${record.expiryDate}.',
      targetGroup: 'Tất cả người dùng',
    );
    _notifyStoreChanged();
    return record;
  }

  bool requeueOrReturnOrder(String trackingCode, {required bool isReturn}) {
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord == null) return false;
    if (ord.status == OrderStatus.delivered ||
        ord.status == OrderStatus.cancelled) {
      return false;
    }
    if (isReturn) {
      if (ord.status == OrderStatus.returning) return false;
      ord.status = OrderStatus.returning;
      ord.cancelReason = 'Hoàn hàng về điểm lấy theo yêu cầu Cửa hàng';
    } else {
      ord.status = ord.assignedDriverName != null
          ? OrderStatus.inTransit
          : OrderStatus.searching;
      ord.cancelReason = null;
    }
    _sqliteDb.updateRows(
      'orders',
      {
        'status': ord.status.name,
        'cancel_reason': ord.cancelReason,
      },
      where: 'tracking_code = ?',
      whereArgs: [trackingCode],
    );
    _persistMutation(
      isReturn ? 'RETURN_ORDER_TO_WAREHOUSE' : 'REQUEUE_ORDER_DELIVERY',
      {'trackingCode': trackingCode, 'status': ord.status.name},
    );
    _notifyStoreChanged();
    return true;
  }

  bool toggleUserAccountStatus(String userId) {
    if (!hasAdminPermission('User: Khóa/Mở')) return false;
    final u = users.where((x) => x.id == userId).firstOrNull;
    if (u == null) return false;
    if (u.id == activeAuthenticatedUser?.id ||
        u.role == SubsystemRole.admin) {
      return false;
    }
    u.status = u.status == 'ACTIVE' ? 'LOCKED' : 'ACTIVE';
    _sqliteDb.updateRows(
      'users',
      {'status': u.status},
      where: 'id = ?',
      whereArgs: [u.id],
    );
    _persistMutation('TOGGLE_USER_STATUS', {'id': u.id, 'status': u.status});
    _notifyStoreChanged();
    return true;
  }

  void toggleVoucherStatus(String code) {
    final v = vouchers.where((x) => x.code == code).firstOrNull;
    if (v == null) return;
    v.status = v.status == 'Đang hoạt động' ? 'Tạm dừng' : 'Đang hoạt động';
    _sqliteDb.updateRows(
      'vouchers',
      {'status': v.status},
      where: 'code = ?',
      whereArgs: [v.code],
    );
    _persistMutation('TOGGLE_VOUCHER_STATUS', {
      'code': v.code,
      'status': v.status,
    });
    _notifyStoreChanged();
  }

  String exportReportFileToDisk({
    required String fileName,
    required String content,
  }) {
    final sep = Platform.pathSeparator;
    String targetPath;
    try {
      final exportDir =
          Directory('${Directory.current.path}${sep}database${sep}exports');
      if (!exportDir.existsSync()) {
        exportDir.createSync(recursive: true);
      }
      targetPath = '${exportDir.path}$sep$fileName';
      File(targetPath).writeAsStringSync(content, flush: true);
    } catch (_) {
      targetPath = '${Directory.systemTemp.path}$sep$fileName';
      try {
        File(targetPath).writeAsStringSync(content, flush: true);
      } catch (_) {}
    }
    _persistMutation('EXPORT_REPORT_FILE', {
      'fileName': fileName,
      'path': targetPath,
    });
    return targetPath;
  }
}
