part of 'app_state_store.dart';

extension AppStateSeedAndHydration on AppStateStore {
  void _populateInitialRelationalRecordsInMemory() {
    users
      ..clear()
      ..addAll([
        UserAccountRecord(
          id: 'USR-01',
          phone: '0912345678',
          email: 'thu.ha@gmail.com',
          passwordHash: SecurityAndBarcodeUtils.hashPasswordWithSalt(
            '12345678',
            '0912345678',
          ),
          fullName: 'Nguyễn Thu Hà',
          role: SubsystemRole.customer,
          defaultAddress: '123 Đường Lê Lợi, Quận 1, TP. HCM',
          defaultLocation: const GeoPoint(
            latitude: 10.7745,
            longitude: 106.7035,
          ),
          createdAt: '2026-10-01',
        ),
        UserAccountRecord(
          id: 'USR-02',
          phone: '0987654321',
          email: 'nam.driver@giaohanggps.vn',
          passwordHash: SecurityAndBarcodeUtils.hashPasswordWithSalt(
            '12345678',
            '0987654321',
          ),
          fullName: 'Nguyễn Văn Nam',
          role: SubsystemRole.driver,
          defaultAddress: 'Quận 1, TP. HCM',
          defaultLocation: const GeoPoint(
            latitude: 10.7769,
            longitude: 106.6953,
          ),
          createdAt: '2026-10-01',
        ),
        UserAccountRecord(
          id: 'USR-03',
          phone: '0909112233',
          email: 'contact@gomsuviet.vn',
          passwordHash: SecurityAndBarcodeUtils.hashPasswordWithSalt(
            '12345678',
            '0909112233',
          ),
          fullName: 'Cửa hàng Gốm Sứ Việt',
          role: SubsystemRole.merchant,
          defaultAddress: '123 Đường Lê Lợi, Phường Bến Nghé, Quận 1, TP. HCM',
          defaultLocation: const GeoPoint(
            latitude: 10.7769,
            longitude: 106.6953,
          ),
          createdAt: '2026-10-01',
        ),
        UserAccountRecord(
          id: 'USR-04',
          phone: '0900999999',
          email: 'admin@gomau.vn',
          passwordHash: SecurityAndBarcodeUtils.hashPasswordWithSalt(
            '12345678',
            '0900999999',
          ),
          fullName: 'Quản trị viên Hệ thống',
          role: SubsystemRole.admin,
          defaultAddress: 'Trung tâm Điều hành GO-MAU',
          defaultLocation: const GeoPoint(
            latitude: 10.7769,
            longitude: 106.7009,
          ),
          createdAt: '2026-10-01',
        ),
      ]);

    savedAddresses
      ..clear()
      ..addAll(const [
        SavedAddressRecord(
          id: 'ADDR-01',
          label: 'Nhà',
          fullAddress: '12 Nguyễn Huệ, P. Bến Nghé, Q.1, TP. HCM',
          location: GeoPoint(latitude: 10.7745, longitude: 106.7035),
        ),
        SavedAddressRecord(
          id: 'ADDR-02',
          label: 'Cơ quan',
          fullAddress:
              'Bitexco Financial Tower, 45 Lê Lợi, P. Bến Nghé, Q.1, TP. HCM',
          location: GeoPoint(latitude: 10.7716, longitude: 106.7044),
        ),
        SavedAddressRecord(
          id: 'ADDR-03',
          label: 'Khác',
          fullAddress: '18A/24 Nguyễn Thị Minh Khai, P. Đa Kao, Q.1, TP. HCM',
          location: GeoPoint(latitude: 10.7882, longitude: 106.7012),
        ),
      ]);

    merchantWarehouses
      ..clear()
      ..addAll(const [
        PickupWarehouseRecord(
          id: 'WH-01',
          name: 'Kho chính',
          address: '123 Đường Lê Lợi, Phường Bến Nghé, Quận 1, TP. HCM',
          location: GeoPoint(latitude: 10.7769, longitude: 106.6953),
        ),
        PickupWarehouseRecord(
          id: 'WH-02',
          name: 'Chi nhánh Q.3',
          address: '456 Đường Nguyễn Đình Chiểu, Phường 6, Quận 3, TP. HCM',
          location: GeoPoint(latitude: 10.7752, longitude: 106.6869),
        ),
      ]);

    vouchers
      ..clear()
      ..addAll([
        VoucherRecord(
          code: 'PROMO20K',
          title: 'GIẢM 20.000Đ PHÍ VẬN CHUYỂN',
          discountLabel: '20.000đ',
          discountValue: 20000,
          isPercentage: false,
          maxDiscount: 20000,
          minOrderValue: 50000,
          expiryDate: '31/12/2026',
          status: 'Đang hoạt động',
        ),
        VoucherRecord(
          code: 'GHN-SUMMER24',
          title: 'GIẢM 20% ĐƠN ĐẦU TIÊN',
          discountLabel: '20%',
          discountValue: 20,
          isPercentage: true,
          maxDiscount: 50000,
          minOrderValue: 500000,
          expiryDate: '31/12/2026',
          status: 'Đang hoạt động',
        ),
        VoucherRecord(
          code: 'GHN-OFF50K',
          title: 'MIỄN PHÍ GIAO HÀNG TỐI ĐA 30K',
          discountLabel: '30.000đ',
          discountValue: 30000,
          isPercentage: false,
          maxDiscount: 30000,
          minOrderValue: 300000,
          expiryDate: '15/11/2026',
          status: 'Đang hoạt động',
        ),
        VoucherRecord(
          code: 'GHN-BACKTOSCHOOL',
          title: 'GIẢM 10% PHÍ GIAO HÀNG',
          discountLabel: '10%',
          discountValue: 10,
          isPercentage: true,
          maxDiscount: 25000,
          minOrderValue: 200000,
          expiryDate: '30/11/2026',
          status: 'Đang hoạt động',
        ),
      ]);

    orders
      ..clear()
      ..addAll([
        ActiveOrderRecord(
          id: 'ORD-01',
          trackingCode: '#DH123456',
          customerName: 'Nguyễn Thu Hà',
          recipientName: 'Nguyễn Thị Minh An',
          recipientPhone: '0912345678',
          pickupAddress: '145 Phố Huế, Hai Bà Trưng, Hà Nội',
          dropoffAddress:
              'Số 15, Ngõ 100, Đường Lê Trọng Tấn, Quận Thanh Xuân, Hà Nội',
          pickupLocation:
              const GeoPoint(latitude: 21.0145, longitude: 105.8512),
          dropoffLocation:
              const GeoPoint(latitude: 20.9951, longitude: 105.8286),
          serviceType: DeliveryServiceType.express30m,
          packageDescription: '2x Áo thun Polo (Size M, Xanh)',
          weightKg: 1.8,
          dimensionsCm: '30 x 20 x 10 cm',
          distanceMeters: 14500,
          durationSeconds: 2700,
          deliveryFee: 138250,
          surchargeFee: 20000,
          discountAmount: 20000,
          codAmount: 1500000,
          totalAmount: 138250,
          paymentMethod: 'Tiền mặt (COD)',
          paymentStatus: 'UNPAID',
          status: OrderStatus.inTransit,
          assignedDriverName: 'Nguyễn Văn Nam',
          assignedDriverPlate: '29-P1 123.45',
          createdDateLabel: '26/10/2023',
        ),
        ActiveOrderRecord(
          id: 'ORD-02',
          trackingCode: '#DH789101',
          customerName: 'Trần Văn An',
          recipientName: 'Lê Văn B',
          recipientPhone: '0987654321',
          pickupAddress: '123 Đường Lê Lợi, Phường Bến Nghé, Quận 1, TP. HCM',
          dropoffAddress: '456 Đường Nguyễn Huệ, Quận Phú Nhuận, TP. HCM',
          pickupLocation:
              const GeoPoint(latitude: 10.7731, longitude: 106.6983),
          dropoffLocation:
              const GeoPoint(latitude: 10.7992, longitude: 106.6805),
          serviceType: DeliveryServiceType.standard,
          packageDescription: 'Gốm sứ cao cấp (3 kiện)',
          weightKg: 2.5,
          dimensionsCm: '35 x 25 x 15 cm',
          distanceMeters: 12000,
          durationSeconds: 2100,
          deliveryFee: 85000,
          surchargeFee: 10000,
          discountAmount: 0,
          codAmount: 750000,
          totalAmount: 95000,
          paymentMethod: 'Ví MoMo',
          paymentStatus: 'PAID',
          status: OrderStatus.delivered,
          assignedDriverName: 'Nguyễn Văn Nam',
          assignedDriverPlate: '29-P1 123.45',
          podImageNote:
              'Đã chụp ảnh kiện hàng kèm Watermark GPS (10.7992, 106.6805)',
          ratingStars: 5,
          ratingComment: 'Tài xế thân thiện, giao hàng siêu tốc đúng giờ!',
          createdDateLabel: '25/10/2023',
        ),
        ActiveOrderRecord(
          id: 'ORD-03',
          trackingCode: '#DH556778',
          customerName: 'Phạm Văn C',
          recipientName: 'Ngô Thị Mai',
          recipientPhone: '0923560677',
          pickupAddress: '45 Hai Bà Trưng, Quận 3, TP. HCM',
          dropoffAddress: '77 Võ Văn Tần, Quận 3, TP. HCM',
          pickupLocation:
              const GeoPoint(latitude: 10.7821, longitude: 106.6951),
          dropoffLocation:
              const GeoPoint(latitude: 10.7761, longitude: 106.6894),
          serviceType: DeliveryServiceType.saving,
          packageDescription: 'Tài liệu doanh nghiệp',
          weightKg: 0.8,
          dimensionsCm: '25 x 18 x 5 cm',
          distanceMeters: 3500,
          durationSeconds: 900,
          deliveryFee: 45000,
          surchargeFee: 0,
          discountAmount: 0,
          codAmount: 210000,
          totalAmount: 45000,
          paymentMethod: 'Tiền mặt (COD)',
          paymentStatus: 'UNPAID',
          status: OrderStatus.searching,
          createdDateLabel: '26/10/2023',
        ),
      ]);

    chatMessages
      ..clear()
      ..addAll(const [
        ChatMessageRecord(
          id: 'MSG-01',
          orderId: '#DH123456',
          senderName: 'Nguyễn Thu Hà',
          isCustomer: true,
          text: 'Anh đến chưa ạ? Mình đang đợi ở sảnh.',
          timeLabel: '10:32',
        ),
        ChatMessageRecord(
          id: 'MSG-02',
          orderId: '#DH123456',
          senderName: 'Nguyễn Văn Nam',
          isCustomer: false,
          text:
              'Dạ, chào bạn. Anh đang đi đến điểm đón rồi nhé. Còn 5 phút nữa nhé.',
          timeLabel: '10:32',
        ),
        ChatMessageRecord(
          id: 'MSG-03',
          orderId: '#DH123456',
          senderName: 'Nguyễn Thu Hà',
          isCustomer: true,
          text: 'Vâng ạ, mình đợi. Xe anh màu gì thế ạ?',
          timeLabel: '10:33',
        ),
      ]);

    notifications
      ..clear()
      ..addAll([
        NotificationRecord(
          id: 'NOTI-01',
          category: 'Đơn hàng',
          title: 'Đơn hàng #DH789101 đã giao thành công',
          timeAgo: '5 phút trước',
        ),
        NotificationRecord(
          id: 'NOTI-02',
          category: 'Đơn hàng',
          title: 'Tài xế Nguyễn Văn Nam đang vận chuyển đơn #DH123456',
          timeAgo: '1 giờ trước',
        ),
        NotificationRecord(
          id: 'NOTI-03',
          category: 'Khuyến mãi',
          title: 'Mã PROMO20K giảm 20.000đ phí giao hàng hôm nay',
          timeAgo: '3 giờ trước',
        ),
      ]);

    drivers
      ..clear()
      ..addAll([
        DriverApplicantRecord(
          id: 'DV10928',
          fullName: 'Nguyễn Văn Nam',
          phone: '0987654321',
          citizenId: '001095012345',
          licensePlate: '29A-123.45',
          vehicleType: 'Xe máy',
          vehicleColor: 'Đỏ',
          approvalStatus: 'Đã duyệt',
          isOnline: true,
          location: const GeoPoint(latitude: 10.7769, longitude: 106.6953),
          rating: 4.9,
          totalTrips: 320,
        ),
        DriverApplicantRecord(
          id: 'DV10929',
          fullName: 'Trần Văn Hùng',
          phone: '0938112233',
          citizenId: '079092054321',
          licensePlate: '59-P2 678.90',
          vehicleType: 'Xe máy',
          vehicleColor: 'Xanh đen',
          approvalStatus: 'Chờ duyệt',
          isOnline: true,
          location: const GeoPoint(latitude: 10.7812, longitude: 106.7015),
          rating: 4.8,
          totalTrips: 215,
        ),
        DriverApplicantRecord(
          id: 'DV10930',
          fullName: 'Lê Thị Mai',
          phone: '0945667788',
          citizenId: '079196098765',
          licensePlate: '59-X1 456.78',
          vehicleType: 'Xe tải 500kg',
          vehicleColor: 'Trắng',
          approvalStatus: 'Chờ duyệt',
          isOnline: false,
          location: const GeoPoint(latitude: 10.7689, longitude: 106.6910),
          rating: 4.7,
          totalTrips: 140,
        ),
      ]);

    merchantApplicants
      ..clear()
      ..addAll([
        MerchantApplicantRecord(
          id: 'MER-01',
          ownerPhone: '0909112233',
          storeName: 'Cửa hàng Gốm Sứ Việt',
          businessType: 'Hộ kinh doanh cá thể',
          taxCode: '0101234567-001',
          representativeName: 'Nguyễn Văn A',
          openHours: '08:00 - 21:00',
          bankName: 'VPBank',
          bankAccount: '123456789',
          approvalStatus: 'Đã duyệt',
        ),
        MerchantApplicantRecord(
          id: 'MER-02',
          ownerPhone: '0977889900',
          storeName: 'Thời trang Thiết kế Lụa Việt',
          businessType: 'Công ty TNHH',
          taxCode: '0316549871',
          representativeName: 'Phạm Hoàng Yến',
          openHours: '08:30 - 22:00',
          bankName: 'Techcombank',
          bankAccount: '190388991122',
          approvalStatus: 'Chờ duyệt',
        ),
      ]);

    complaints
      ..clear()
      ..addAll([
        ComplaintTicketRecord(
          ticketCode: 'KN-001',
          orderId: '#DH123456',
          customerName: 'Nguyễn Thu Hà',
          driverName: 'Nguyễn Văn Nam',
          issueType: 'Giao hàng chậm',
          description:
              'Giao hàng trễ hơn 2 tiếng so với dự kiến. Khách hàng đã phải chờ đợi quá lâu.',
          status: 'Mới',
          replies: [
            'Nguyễn Thu Hà (10:30): Hôm nay tôi đã nhận hàng quá muộn, trễ 2 tiếng so với hẹn.',
            'Admin (10:45): Chào bạn, chúng tôi đã ghi nhận khiếu nại và đang kiểm tra lộ trình GPS của tài xế.',
          ],
        ),
        ComplaintTicketRecord(
          ticketCode: 'KN-002',
          orderId: '#DH789101',
          customerName: 'Trần Văn An',
          driverName: 'Nguyễn Văn Nam',
          issueType: 'Hàng hư hỏng',
          description: 'Móp góc hộp carton bên ngoài khi vận chuyển.',
          status: 'Đang xử lý',
          replies: [
            'Trần Văn An (09:15): Kiện hàng gốm sứ bị móp nhẹ ở góc hộp.',
          ],
        ),
        ComplaintTicketRecord(
          ticketCode: 'KN-003',
          orderId: '#DH556778',
          customerName: 'Phạm Văn C',
          driverName: 'Trần Văn Hùng',
          issueType: 'Thiếu hàng',
          description: 'Shop gửi 3 kiện nhưng người nhận mới nhận 2 kiện.',
          status: 'Đã giải quyết',
          replies: [
            'Admin: Đã đối chiếu phiếu giao hàng và hoàn tất giao bổ sung kiện thứ 3.',
          ],
        ),
      ]);

    withdrawalRequests
      ..clear()
      ..addAll([
        WithdrawalRequestRecord(
          id: 'WD-01',
          ownerName: 'Nguyễn Văn Nam',
          ownerRole: 'Tài xế',
          amount: 5000000,
          bankName: 'Vietcombank',
          accountMasked: '007100****889',
          requestDate: '24/10/2023',
          status: 'Chờ duyệt',
        ),
        WithdrawalRequestRecord(
          id: 'WD-02',
          ownerName: 'Trần Văn Hùng',
          ownerRole: 'Tài xế',
          amount: 3000000,
          bankName: 'BIDV',
          accountMasked: '314100****221',
          requestDate: '24/10/2023',
          status: 'Chờ duyệt',
        ),
        WithdrawalRequestRecord(
          id: 'WD-03',
          ownerName: 'Cửa hàng Gốm Sứ Việt',
          ownerRole: 'Cửa hàng (COD)',
          amount: 2100000,
          bankName: 'VPBank - 789',
          accountMasked: '123456****789',
          requestDate: '15/10/2023 10:30',
          status: 'Chờ duyệt',
        ),
        WithdrawalRequestRecord(
          id: 'WD-04',
          ownerName: 'Cửa hàng Gốm Sứ Việt',
          ownerRole: 'Cửa hàng (COD)',
          amount: 1850000,
          bankName: 'VPBank - 789',
          accountMasked: '123456****789',
          requestDate: '12/10/2023 14:15',
          status: 'Đã duyệt',
        ),
      ]);

    geofenceZones
      ..clear()
      ..addAll([
        GeofenceZoneRecord(
          id: 'GEO-01',
          zoneName: 'Vùng trung tâm (Quận 1 & Quận 3)',
          zoneType: 'CENTER_ZONE',
          surchargeRate: 0,
          isActive: true,
          boundary: const [
            GeoPoint(latitude: 10.765, longitude: 106.685),
            GeoPoint(latitude: 10.765, longitude: 106.710),
            GeoPoint(latitude: 10.790, longitude: 106.710),
            GeoPoint(latitude: 10.790, longitude: 106.685),
          ],
        ),
        GeofenceZoneRecord(
          id: 'GEO-02',
          zoneName: 'Vùng phụ phí cao (Giờ cao điểm / Khu ngập)',
          zoneType: 'SURCHARGE_ZONE',
          surchargeRate: 25000,
          isActive: true,
          boundary: const [
            GeoPoint(latitude: 10.740, longitude: 106.660),
            GeoPoint(latitude: 10.740, longitude: 106.685),
            GeoPoint(latitude: 10.765, longitude: 106.685),
            GeoPoint(latitude: 10.765, longitude: 106.660),
          ],
        ),
        GeofenceZoneRecord(
          id: 'GEO-03',
          zoneName: 'Vùng hạn chế (Cấm tải giờ cao điểm)',
          zoneType: 'RESTRICTED_ZONE',
          surchargeRate: 0,
          isActive: true,
          boundary: const [
            GeoPoint(latitude: 10.730, longitude: 106.710),
            GeoPoint(latitude: 10.730, longitude: 106.740),
            GeoPoint(latitude: 10.755, longitude: 106.740),
            GeoPoint(latitude: 10.755, longitude: 106.710),
          ],
        ),
      ]);

    rbacRoles
      ..clear()
      ..addAll([
        RbacRoleRecord(
          roleName: 'Super Admin',
          permissions: {
            'Đơn: Xem': true,
            'Đơn: Tạo': true,
            'Đơn: Sửa': true,
            'Đơn: Xóa': true,
            'Tài xế: Xem': true,
            'Tài xế: Phê duyệt': true,
            'Tài xế: Chỉnh sửa': true,
            'Tài xế: Đình chỉ': true,
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
            'Đơn: Xem': true,
            'Đơn: Tạo': true,
            'Đơn: Sửa': true,
            'Đơn: Xóa': true,
            'Tài xế: Xem': true,
            'Tài xế: Phê duyệt': true,
            'Tài xế: Chỉnh sửa': true,
            'Tài xế: Đình chỉ': false,
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
            'Đơn: Xem': false,
            'Đơn: Tạo': false,
            'Đơn: Sửa': false,
            'Đơn: Xóa': false,
            'Tài xế: Xem': false,
            'Tài xế: Phê duyệt': false,
            'Tài xế: Chỉnh sửa': false,
            'Tài xế: Đình chỉ': false,
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
            'Đơn: Xem': true,
            'Đơn: Tạo': true,
            'Đơn: Sửa': false,
            'Đơn: Xóa': false,
            'Tài xế: Xem': true,
            'Tài xế: Phê duyệt': false,
            'Tài xế: Chỉnh sửa': false,
            'Tài xế: Đình chỉ': false,
            'Tài chính: Báo cáo': true,
            'Tài chính: Giao dịch': false,
            'Tài chính: Thanh toán': false,
            'Hệ thống: Cài đặt': true,
            'Hệ thống: Bảo mật': false,
            'Hệ thống: Nhật ký': false,
          },
        ),
      ]);
  }

  /// Khởi tạo và nạp toàn bộ 16 bảng quan hệ từ CSDL SQLite thực tế (`gps_delivery_production.db`)
  Future<void> initializeDatabase() async {
    try {
      final userCount = await _sqliteDb.countRows('users');
      if (userCount == 0) {
        await _seedInitialDatabaseTables();
      }
      await _loadAllTablesFromSqlite();
      offlineQueueCount = await _sqliteDb.getPendingQueueCount();
      isDatabaseReady = true;
      lastSyncStatusMessage =
          'CSDL SQLite (${_sqliteDb.databaseFilePath}) • ${orders.length} đơn, ${users.length} người dùng, ${drivers.length} tài xế';
      _notifyStoreChanged();
    } catch (_) {
      // Giữ trạng thái trong bộ nhớ nếu môi trường test không cho phép mở tệp
    }
  }

  Future<void> _seedInitialDatabaseTables() async {
    final nowIso = DateTime.now().toIso8601String();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    for (final u in users) {
      await _sqliteDb.upsertRow('users', {
        'id': u.id,
        'phone': _normalizePhone(u.phone),
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

    for (final a in savedAddresses) {
      await _sqliteDb.upsertRow('user_addresses', {
        'id': a.id,
        'user_phone': _normalizePhone(customerPhone),
        'label': a.label,
        'full_address': a.fullAddress,
        'latitude': a.location.latitude,
        'longitude': a.location.longitude,
        'created_at': nowIso,
      });
    }

    for (final d in drivers) {
      await _sqliteDb.upsertRow('drivers', {
        'id': d.id,
        'phone': _normalizePhone(d.phone),
        'full_name': d.fullName,
        'citizen_id': d.citizenId,
        'license_plate': d.licensePlate,
        'vehicle_type': d.vehicleType,
        'vehicle_color': d.vehicleColor,
        'approval_status': d.approvalStatus,
        'is_online': d.isOnline ? 1 : 0,
        'latitude': d.location.latitude,
        'longitude': d.location.longitude,
        'rating': d.rating,
        'total_trips': d.totalTrips,
        'wallet_balance': driverWalletBalance,
        'created_at': nowIso,
      });
    }

    for (final m in merchantApplicants) {
      await _sqliteDb.upsertRow('merchants', {
        'id': m.id,
        'owner_phone': _normalizePhone(m.ownerPhone),
        'store_name': m.storeName,
        'business_type': m.businessType,
        'tax_code': m.taxCode,
        'representative_name': m.representativeName,
        'open_hours': m.openHours,
        'bank_name': m.bankName,
        'bank_account': m.bankAccount,
        'cod_balance': merchantCodBalance,
        'approval_status': m.approvalStatus,
        'created_at': nowIso,
      });
    }

    for (final w in merchantWarehouses) {
      await _sqliteDb.upsertRow('merchant_pickup_points', {
        'id': w.id,
        'merchant_id': 'MER-01',
        'warehouse_name': w.name,
        'full_address': w.address,
        'latitude': w.location.latitude,
        'longitude': w.location.longitude,
        'created_at': nowIso,
      });
    }

    await _sqliteDb.upsertRow('pricing_configs', {
      'id': 'PRC-01',
      'service_type': 'STANDARD_V2',
      'base_fare': baseFareConfig,
      'price_per_km': pricePerKmConfig,
      'peak_hour_surcharge': peakHourSurchargeConfig,
      'bad_weather_surcharge': badWeatherSurchargeConfig,
      'is_peak_enabled': isPeakSurchargeActive ? 1 : 0,
      'is_weather_enabled': isWeatherSurchargeActive ? 1 : 0,
      'updated_at': nowIso,
    });

    for (final v in vouchers) {
      await _sqliteDb.upsertRow('vouchers', {
        'code': v.code,
        'title': v.title,
        'discount_label': v.discountLabel,
        'discount_value': v.discountValue,
        'is_percentage': v.isPercentage ? 1 : 0,
        'max_discount': v.maxDiscount,
        'min_order_value': v.minOrderValue,
        'expiry_date': v.expiryDate,
        'status': v.status,
      });
    }

    for (var i = 0; i < orders.length; i++) {
      await _sqliteDb.upsertRow(
        'orders',
        orders[i].toSqlRow(nowMs - i * 60000),
      );
    }

    for (final z in geofenceZones) {
      await _sqliteDb.upsertRow('geofence_zones', {
        'id': z.id,
        'zone_name': z.zoneName,
        'zone_type': z.zoneType,
        'surcharge_rate': z.surchargeRate,
        'is_active': z.isActive ? 1 : 0,
        'boundary_json': jsonEncode(
          z.boundary
              .map((pt) => {'lat': pt.latitude, 'lng': pt.longitude})
              .toList(),
        ),
      });
    }

    for (var i = 0; i < rbacRoles.length; i++) {
      final r = rbacRoles[i];
      await _sqliteDb.upsertRow('admin_roles_permissions', {
        'id': 'RBAC-0${i + 1}',
        'role_name': r.roleName,
        'permissions_json': jsonEncode(r.permissions),
        'updated_at': nowIso,
      });
    }

    for (var i = 0; i < withdrawalRequests.length; i++) {
      final w = withdrawalRequests[i];
      await _sqliteDb.upsertRow('wallets_and_transactions', {
        'id': w.id,
        'owner_name': w.ownerName,
        'owner_role': w.ownerRole,
        'amount': w.amount,
        'bank_name': w.bankName,
        'account_masked': w.accountMasked,
        'request_date': w.requestDate,
        'status': w.status,
        'created_at_ms': nowMs - i * 60000,
      });
    }

    for (var i = 0; i < complaints.length; i++) {
      final c = complaints[i];
      await _sqliteDb.upsertRow('incidents_and_complaints', {
        'ticket_code': c.ticketCode,
        'order_id': c.orderId,
        'customer_name': c.customerName,
        'driver_name': c.driverName,
        'issue_type': c.issueType,
        'description': c.description,
        'status': c.status,
        'replies_json': jsonEncode(c.replies),
        'created_at_ms': nowMs - i * 60000,
      });
    }

    for (var i = 0; i < chatMessages.length; i++) {
      final m = chatMessages[i];
      await _sqliteDb.upsertRow('chat_messages_and_notifications', {
        'id': m.id,
        'record_type': 'CHAT',
        'order_id': m.orderId,
        'sender_name': m.senderName,
        'is_customer': m.isCustomer ? 1 : 0,
        'category': 'CHAT_MESSAGE',
        'title': m.senderName,
        'content': m.text,
        'target_group': 'INDIVIDUAL',
        'time_label': m.timeLabel,
        'is_read': 1,
        'created_at_ms': nowMs - (chatMessages.length - i) * 1000,
      });
    }

    for (var i = 0; i < notifications.length; i++) {
      final n = notifications[i];
      await _sqliteDb.upsertRow('chat_messages_and_notifications', {
        'id': n.id,
        'record_type': 'NOTIFICATION',
        'order_id': null,
        'sender_name': 'Hệ thống',
        'is_customer': 0,
        'category': n.category,
        'title': n.title,
        'content': n.title,
        'target_group': n.targetGroup,
        'time_label': n.timeAgo,
        'is_read': n.isRead ? 1 : 0,
        'created_at_ms': nowMs - i * 60000,
      });
    }
  }

  Future<void> _loadAllTablesFromSqlite() async {
    final userRows = await _sqliteDb.queryRows('users');
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
    if (addrRows.isNotEmpty) {
      savedAddresses
        ..clear()
        ..addAll(
          addrRows.map(
            (r) => SavedAddressRecord(
              id: r['id'].toString(),
              userPhone: (r['user_phone'] ?? '0912345678').toString(),
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
    if (drvRows.isNotEmpty) {
      drivers
        ..clear()
        ..addAll(
          drvRows.map(
            (r) => DriverApplicantRecord(
              id: r['id'].toString(),
              fullName: r['full_name'].toString(),
              phone: r['phone'].toString(),
              citizenId: r['citizen_id'].toString(),
              licensePlate: r['license_plate'].toString(),
              vehicleType: r['vehicle_type'].toString(),
              vehicleColor: r['vehicle_color'].toString(),
              approvalStatus: r['approval_status'].toString(),
              isOnline: (r['is_online'] as num?)?.toInt() == 1,
              location: GeoPoint(
                latitude: (r['latitude'] as num).toDouble(),
                longitude: (r['longitude'] as num).toDouble(),
              ),
              rating: (r['rating'] as num?)?.toDouble() ?? 4.9,
              totalTrips: (r['total_trips'] as num?)?.toInt() ?? 0,
            ),
          ),
        );
      final firstDrvWallet =
          (drvRows.first['wallet_balance'] as num?)?.toDouble();
      if (firstDrvWallet != null && firstDrvWallet > 0) {
        driverWalletBalance = firstDrvWallet;
      }
      isDriverOnline = drivers.first.isOnline;
      activeDriverId = drivers.first.id;
      activeDriverName = drivers.first.fullName;
      activeDriverPhone = drivers.first.phone;
    }

    final merRows = await _sqliteDb.queryRows('merchants');
    if (merRows.isNotEmpty) {
      merchantApplicants
        ..clear()
        ..addAll(
          merRows.map((r) {
            final rawStatus = (r['approval_status'] ?? 'Chờ duyệt').toString();
            final normStatus =
                (rawStatus == 'APPROVED' || rawStatus == 'Đã duyệt')
                    ? 'Đã duyệt'
                    : (rawStatus == 'REJECTED' || rawStatus == 'Từ chối')
                        ? 'Từ chối'
                        : 'Chờ duyệt';
            return MerchantApplicantRecord(
              id: r['id'].toString(),
              ownerPhone: (r['owner_phone'] ?? '').toString(),
              storeName: r['store_name'].toString(),
              businessType: r['business_type'].toString(),
              taxCode: r['tax_code'].toString(),
              representativeName: r['representative_name'].toString(),
              openHours: r['open_hours'].toString(),
              bankName: r['bank_name'].toString(),
              bankAccount: r['bank_account'].toString(),
              approvalStatus: normStatus,
            );
          }),
        );
      final m = merRows.first;
      merchantStoreName = m['store_name'].toString();
      merchantBusinessType = m['business_type'].toString();
      merchantTaxCode = m['tax_code'].toString();
      merchantRepresentative = m['representative_name'].toString();
      merchantOpenHours = m['open_hours'].toString();
      merchantBankName = m['bank_name'].toString();
      merchantBankAccount = m['bank_account'].toString();
      merchantCodBalance =
          (m['cod_balance'] as num?)?.toDouble() ?? merchantCodBalance;
    }

    final whRows = await _sqliteDb.queryRows('merchant_pickup_points');
    if (whRows.isNotEmpty) {
      merchantWarehouses
        ..clear()
        ..addAll(
          whRows.map(
            (r) => PickupWarehouseRecord(
              id: r['id'].toString(),
              name: r['warehouse_name'].toString(),
              address: r['full_address'].toString(),
              location: GeoPoint(
                latitude: (r['latitude'] as num).toDouble(),
                longitude: (r['longitude'] as num).toDouble(),
              ),
            ),
          ),
        );
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
    if (vRows.isNotEmpty) {
      vouchers
        ..clear()
        ..addAll(
          vRows.map(
            (r) => VoucherRecord(
              code: r['code'].toString(),
              title: r['title'].toString(),
              discountLabel: r['discount_label'].toString(),
              discountValue: (r['discount_value'] as num).toDouble(),
              isPercentage: (r['is_percentage'] as num).toInt() == 1,
              maxDiscount: (r['max_discount'] as num).toDouble(),
              minOrderValue: (r['min_order_value'] as num).toDouble(),
              expiryDate: r['expiry_date'].toString(),
              status: r['status'].toString(),
            ),
          ),
        );
    }

    final ordRows = await _sqliteDb.queryRows(
      'orders',
      orderBy: 'created_at_ms DESC',
    );
    if (ordRows.isNotEmpty) {
      final loadedOrders = ordRows.map(ActiveOrderRecord.fromSqlRow).toList();
      final staleDemoOrders = loadedOrders.where(
        (o) =>
            o.id != 'ORD-01' &&
            o.recipientName == 'Nguyễn Thị Minh An' &&
            o.dropoffAddress.contains('Lê Trọng Tấn'),
      );
      for (final stale in staleDemoOrders) {
        await _sqliteDb.deleteRows(
          'orders',
          where: 'id = ?',
          whereArgs: [stale.id],
        );
      }
      loadedOrders.removeWhere(
        (o) =>
            o.id != 'ORD-01' &&
            o.recipientName == 'Nguyễn Thị Minh An' &&
            o.dropoffAddress.contains('Lê Trọng Tấn'),
      );
      orders
        ..clear()
        ..addAll(loadedOrders);
    }

    final geoRows = await _sqliteDb.queryRows('geofence_zones');
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

    final rbacRows = await _sqliteDb.queryRows('admin_roles_permissions');
    if (rbacRows.isNotEmpty) {
      rbacRoles
        ..clear()
        ..addAll(
          rbacRows.map((r) {
            final decoded = jsonDecode(r['permissions_json'].toString())
                as Map<String, dynamic>;
            return RbacRoleRecord(
              roleName: r['role_name'].toString(),
              permissions: decoded.map((k, v) => MapEntry(k, v == true)),
            );
          }),
        );
    }

    final wdRows = await _sqliteDb.queryRows(
      'wallets_and_transactions',
      orderBy: 'created_at_ms DESC',
    );
    if (wdRows.isNotEmpty) {
      withdrawalRequests
        ..clear()
        ..addAll(
          wdRows.map(
            (r) => WithdrawalRequestRecord(
              id: r['id'].toString(),
              ownerName: r['owner_name'].toString(),
              ownerRole: r['owner_role'].toString(),
              amount: (r['amount'] as num).toDouble(),
              bankName: r['bank_name'].toString(),
              accountMasked: r['account_masked'].toString(),
              requestDate: r['request_date'].toString(),
              status: r['status'].toString(),
            ),
          ),
        );
    }

    final compRows = await _sqliteDb.queryRows(
      'incidents_and_complaints',
      orderBy: 'created_at_ms DESC',
    );
    if (compRows.isNotEmpty) {
      complaints
        ..clear()
        ..addAll(
          compRows.map((r) {
            final repliesList =
                (jsonDecode(r['replies_json'].toString()) as List<dynamic>)
                    .map((e) => e.toString())
                    .toList();
            return ComplaintTicketRecord(
              ticketCode: r['ticket_code'].toString(),
              orderId: r['order_id'].toString(),
              customerName: r['customer_name'].toString(),
              driverName: r['driver_name'].toString(),
              issueType: r['issue_type'].toString(),
              description: r['description'].toString(),
              status: r['status'].toString(),
              replies: repliesList,
            );
          }),
        );
    }

    final chatNotiRows = await _sqliteDb.queryRows(
      'chat_messages_and_notifications',
      orderBy: 'created_at_ms ASC',
    );
    if (chatNotiRows.isNotEmpty) {
      final loadedChats = <ChatMessageRecord>[];
      final loadedNotis = <NotificationRecord>[];
      for (final r in chatNotiRows) {
        if (r['record_type'] == 'CHAT') {
          loadedChats.add(
            ChatMessageRecord(
              id: r['id'].toString(),
              orderId: (r['order_id'] ?? '#DH123456').toString(),
              senderName: (r['sender_name'] ?? '').toString(),
              isCustomer: (r['is_customer'] as num?)?.toInt() == 1,
              text: r['content'].toString(),
              timeLabel: r['time_label'].toString(),
            ),
          );
        } else {
          loadedNotis.insert(
            0,
            NotificationRecord(
              id: r['id'].toString(),
              category: (r['category'] ?? 'Hệ thống').toString(),
              title: (r['title'] ?? r['content']).toString(),
              timeAgo: r['time_label'].toString(),
              targetGroup: (r['target_group'] ?? 'Khách hàng').toString(),
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
    await loadAuthProviderConfigsFromDatabase();
  }
}
