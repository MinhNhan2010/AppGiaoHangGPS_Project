import 'dart:convert';

import 'package:gps_delivery_app/core/config/env_config.dart';
import 'package:gps_delivery_app/core/utils/security_and_barcode_utils.dart';
import 'package:gps_delivery_app/data/datasources/local/app_state_store.dart';
import 'package:gps_delivery_app/data/datasources/local/sqlite_offline_queue_datasource.dart';
import 'package:gps_delivery_app/domain/entities/geo_point.dart';
import 'package:gps_delivery_app/domain/enums/order_status.dart';
import 'package:gps_delivery_app/domain/enums/service_type.dart';
import 'package:gps_delivery_app/domain/enums/user_role.dart';

extension AppStateTestFixtures on AppStateStore {
  void seedTestRecords() {
    customerFullName = 'Nguyễn Thu Hà';
    customerPhone = '0912345678';
    customerEmail = 'thu.ha@gmail.com';
    customerDefaultAddress =
        '72 Lê Thánh Tôn, Phường Bến Nghé, Quận 1, TP. HCM';
    customerGender = 'Nữ';
    activeDriverId = 'DV10928';
    activeDriverName = 'Nguyễn Văn Nam';
    activeDriverPhone = '0987654321';
    isDriverOnline = true;
    isPeakSurchargeActive = true;
    driverWalletBalance = 6190000;
    merchantStoreName = 'Cửa hàng Gốm Sứ Việt';
    merchantCodBalance = 2650000;
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
          defaultAddress: '72 Lê Thánh Tôn, Phường Bến Nghé, Quận 1, TP. HCM',
          defaultLocation: const GeoPoint(
            latitude: 10.7780,
            longitude: 106.7018,
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
          merchantId: 'MER-01',
          name: 'Kho chính',
          address: '123 Đường Lê Lợi, Phường Bến Nghé, Quận 1, TP. HCM',
          location: GeoPoint(latitude: 10.7769, longitude: 106.6953),
          contactPhone: '0909112233',
          openHours: '08:00 - 21:00',
          isPrimary: true,
        ),
        PickupWarehouseRecord(
          id: 'WH-02',
          merchantId: 'MER-01',
          name: 'Chi nhánh Q.3',
          address: '456 Đường Nguyễn Đình Chiểu, Phường 6, Quận 3, TP. HCM',
          location: GeoPoint(latitude: 10.7752, longitude: 106.6869),
          contactPhone: '0909445566',
          openHours: '08:30 - 20:30',
          isPrimary: false,
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
          code: 'FREESHIP20P',
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
          code: 'UUDAI30K',
          title: 'HỖ TRỢ PHÍ GIAO HÀNG 30.000Đ',
          discountLabel: '30.000đ',
          discountValue: 30000,
          isPercentage: false,
          maxDiscount: 30000,
          minOrderValue: 300000,
          expiryDate: '31/12/2026',
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
          expiryDate: '31/12/2026',
          status: 'Đang hoạt động',
        ),
      ]);

    final seedNow = DateTime.now();
    String fmtDate(DateTime dt) =>
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    final todayDateLabel = fmtDate(seedNow);
    final yesterdayDateLabel = fmtDate(
      seedNow.subtract(const Duration(days: 1)),
    );
    final twoDaysAgoLabel = fmtDate(seedNow.subtract(const Duration(days: 2)));
    final fourDaysAgoLabel = fmtDate(seedNow.subtract(const Duration(days: 4)));
    orders
      ..clear()
      ..addAll([
        ActiveOrderRecord(
          id: 'ORD-01',
          trackingCode: '#DH123456',
          customerName: 'Nguyễn Thu Hà',
          recipientName: 'Trần Minh Khoa',
          recipientPhone: '0903882145',
          pickupAddress: '72 Lê Thánh Tôn, Phường Bến Nghé, Quận 1, TP. HCM',
          dropoffAddress:
              '285 Cách Mạng Tháng Tám, Phường 12, Quận 10, TP. HCM',
          pickupLocation: const GeoPoint(
            latitude: 10.7780,
            longitude: 106.7018,
          ),
          dropoffLocation: const GeoPoint(
            latitude: 10.7772,
            longitude: 106.6815,
          ),
          serviceType: DeliveryServiceType.express30m,
          packageDescription: '2x Áo sơ mi công sở (Hộp quà niêm phong)',
          weightKg: 1.4,
          dimensionsCm: '30 x 20 x 10 cm',
          distanceMeters: 3600,
          durationSeconds: 780,
          deliveryFee: 36400,
          surchargeFee: 10000,
          discountAmount: 0,
          codAmount: 650000,
          totalAmount: 46400,
          paymentMethod: 'Tiền mặt (COD)',
          paymentStatus: 'UNPAID',
          status: OrderStatus.inTransit,
          assignedDriverName: 'Nguyễn Văn Nam',
          assignedDriverPlate: '59-P1 123.45',
          createdDateLabel: todayDateLabel,
        ),
        ActiveOrderRecord(
          id: 'ORD-02',
          trackingCode: '#DH789101',
          customerName: 'Nguyễn Thu Hà',
          recipientName: 'Lê Hoàng Bách',
          recipientPhone: '0908445123',
          pickupAddress: '72 Lê Thánh Tôn, Phường Bến Nghé, Quận 1, TP. HCM',
          dropoffAddress:
              '188 Phan Xích Long, Phường 2, Quận Phú Nhuận, TP. HCM',
          pickupLocation: const GeoPoint(
            latitude: 10.7780,
            longitude: 106.7018,
          ),
          dropoffLocation: const GeoPoint(
            latitude: 10.7992,
            longitude: 106.6805,
          ),
          serviceType: DeliveryServiceType.standard,
          packageDescription: 'Quà tặng gốm sứ đóng hộp xốp (2 kiện)',
          weightKg: 2.5,
          dimensionsCm: '35 x 25 x 15 cm',
          distanceMeters: 4400,
          durationSeconds: 1020,
          deliveryFee: 49000,
          surchargeFee: 5000,
          discountAmount: 0,
          codAmount: 750000,
          totalAmount: 54000,
          paymentMethod: 'Ví MoMo',
          paymentStatus: 'PAID',
          status: OrderStatus.delivered,
          assignedDriverName: 'Nguyễn Văn Nam',
          assignedDriverPlate: '59-P1 123.45',
          podImageNote:
              'Đã chụp ảnh kiện hàng kèm Watermark GPS (10.7992, 106.6805)',
          ratingStars: 5,
          ratingComment: 'Tài xế giao đúng hẹn, hàng nguyên vẹn!',
          createdDateLabel: yesterdayDateLabel,
        ),
        ActiveOrderRecord(
          id: 'ORD-03',
          trackingCode: '#DH556778',
          customerName: 'Nguyễn Thu Hà',
          recipientName: 'Ngô Thị Mai',
          recipientPhone: '0923560677',
          pickupAddress: '45 Hai Bà Trưng, Quận 3, TP. HCM',
          dropoffAddress: '77 Võ Văn Tần, Quận 3, TP. HCM',
          pickupLocation: const GeoPoint(
            latitude: 10.7821,
            longitude: 106.6951,
          ),
          dropoffLocation: const GeoPoint(
            latitude: 10.7761,
            longitude: 106.6894,
          ),
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
          createdDateLabel: todayDateLabel,
        ),
        ActiveOrderRecord(
          id: 'ORD-B2B-01',
          trackingCode: '#DH301201',
          customerName: 'Cửa hàng Gốm Sứ Việt',
          recipientName: 'Trần Hoàng Minh',
          recipientPhone: '0903445566',
          pickupAddress: '123 Đường Lê Lợi, Phường Bến Nghé, Quận 1, TP. HCM',
          dropoffAddress: '280 Điện Biên Phủ, Quận Bình Thạnh, TP. HCM',
          pickupLocation: const GeoPoint(
            latitude: 10.7769,
            longitude: 106.6953,
          ),
          dropoffLocation: const GeoPoint(
            latitude: 10.7985,
            longitude: 106.7152,
          ),
          serviceType: DeliveryServiceType.standard,
          packageDescription: 'Bộ ấm trà sứ Minh Long (Dễ vỡ)',
          weightKg: 3.2,
          dimensionsCm: '35 x 25 x 20 cm',
          distanceMeters: 6400,
          durationSeconds: 1320,
          deliveryFee: 57000,
          surchargeFee: 5000,
          discountAmount: 0,
          codAmount: 1850000,
          totalAmount: 62000,
          paymentMethod: 'Người gửi trả phí',
          paymentStatus: 'PAID',
          status: OrderStatus.delivered,
          assignedDriverName: 'Nguyễn Văn Nam',
          assignedDriverPlate: '59-P1 123.45',
          podImageNote:
              'Đã chụp ảnh kiện hàng kèm Watermark GPS (10.7985, 106.7152)',
          createdDateLabel: todayDateLabel,
        ),
        ActiveOrderRecord(
          id: 'ORD-B2B-02',
          trackingCode: '#DH301202',
          customerName: 'Cửa hàng Gốm Sứ Việt',
          recipientName: 'Võ Thị Ngọc Lan',
          recipientPhone: '0918776655',
          pickupAddress:
              '456 Đường Nguyễn Đình Chiểu, Phường 6, Quận 3, TP. HCM',
          dropoffAddress: '12 Nguyễn Huệ, Phường Bến Nghé, Quận 1, TP. HCM',
          pickupLocation: const GeoPoint(
            latitude: 10.7752,
            longitude: 106.6869,
          ),
          dropoffLocation: const GeoPoint(
            latitude: 10.7745,
            longitude: 106.7035,
          ),
          serviceType: DeliveryServiceType.express30m,
          packageDescription: 'Bình hoa gốm Bát Tràng (Dễ vỡ)',
          weightKg: 2.1,
          dimensionsCm: '25 x 25 x 35 cm',
          distanceMeters: 3800,
          durationSeconds: 840,
          deliveryFee: 37800,
          surchargeFee: 15000,
          discountAmount: 0,
          codAmount: 920000,
          totalAmount: 52800,
          paymentMethod: 'Người nhận trả phí',
          paymentStatus: 'UNPAID',
          status: OrderStatus.inTransit,
          assignedDriverName: 'Nguyễn Văn Nam',
          assignedDriverPlate: '59-P1 123.45',
          createdDateLabel: todayDateLabel,
        ),
        ActiveOrderRecord(
          id: 'ORD-B2B-03',
          trackingCode: '#DH301203',
          customerName: 'Cửa hàng Gốm Sứ Việt',
          recipientName: 'Đinh Quốc Khánh',
          recipientPhone: '0908334455',
          pickupAddress: '123 Đường Lê Lợi, Phường Bến Nghé, Quận 1, TP. HCM',
          dropoffAddress: '77 Võ Văn Tần, Phường 6, Quận 3, TP. HCM',
          pickupLocation: const GeoPoint(
            latitude: 10.7769,
            longitude: 106.6953,
          ),
          dropoffLocation: const GeoPoint(
            latitude: 10.7761,
            longitude: 106.6894,
          ),
          serviceType: DeliveryServiceType.standard,
          packageDescription: 'Bộ đĩa sứ xương bàn tiệc (6 món)',
          weightKg: 2.8,
          dimensionsCm: '32 x 32 x 18 cm',
          distanceMeters: 4200,
          durationSeconds: 960,
          deliveryFee: 48000,
          surchargeFee: 0,
          discountAmount: 0,
          codAmount: 1650000,
          totalAmount: 48000,
          paymentMethod: 'Người nhận trả phí',
          paymentStatus: 'PAID',
          status: OrderStatus.delivered,
          assignedDriverName: 'Phạm Quốc Bảo',
          assignedDriverPlate: '59-T1 889.90',
          podImageNote:
              'Đã chụp ảnh kiện hàng kèm Watermark GPS (10.7761, 106.6894)',
          createdDateLabel: twoDaysAgoLabel,
        ),
        ActiveOrderRecord(
          id: 'ORD-B2B-04',
          trackingCode: '#DH301204',
          customerName: 'Cửa hàng Gốm Sứ Việt',
          recipientName: 'Hoàng Thanh Tùng',
          recipientPhone: '0919223344',
          pickupAddress: '123 Đường Lê Lợi, Phường Bến Nghé, Quận 1, TP. HCM',
          dropoffAddress:
              '188 Phan Xích Long, Phường 2, Quận Phú Nhuận, TP. HCM',
          pickupLocation: const GeoPoint(
            latitude: 10.7769,
            longitude: 106.6953,
          ),
          dropoffLocation: const GeoPoint(
            latitude: 10.7992,
            longitude: 106.6805,
          ),
          serviceType: DeliveryServiceType.standard,
          packageDescription: 'Đôi lục bình gốm men rạn (Dễ vỡ)',
          weightKg: 5.5,
          dimensionsCm: '45 x 30 x 30 cm',
          distanceMeters: 7800,
          durationSeconds: 1560,
          deliveryFee: 68500,
          surchargeFee: 8000,
          discountAmount: 0,
          codAmount: 2300000,
          totalAmount: 76500,
          paymentMethod: 'Người gửi trả phí',
          paymentStatus: 'PAID',
          status: OrderStatus.delivered,
          assignedDriverName: 'Phạm Quốc Bảo',
          assignedDriverPlate: '59-T1 889.90',
          podImageNote:
              'Đã chụp ảnh kiện hàng kèm Watermark GPS (10.7992, 106.6805)',
          createdDateLabel: fourDaysAgoLabel,
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
          text: 'Anh Nam ơi, đơn #DH123456 giao qua 285 Cách Mạng Tháng Tám tầm mấy phút tới ạ?',
          timeLabel: '10:32',
        ),
        ChatMessageRecord(
          id: 'MSG-02',
          orderId: '#DH123456',
          senderName: 'Nguyễn Văn Nam',
          isCustomer: false,
          text: 'Dạ anh nhận hàng ở 72 Lê Thánh Tôn rồi nhé, đang đi qua Quận 3 tầm 8 phút nữa tới nơi ạ.',
          timeLabel: '10:33',
        ),
        ChatMessageRecord(
          id: 'MSG-03',
          orderId: '#DH123456',
          senderName: 'Nguyễn Thu Hà',
          isCustomer: true,
          text:
              'Dạ vâng, tới sảnh anh gọi người nhận số 0903882145 giúp em nhé!',
          timeLabel: '10:34',
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
          citizenId: '079095012345',
          licensePlate: '59-P1 123.45',
          vehicleType: 'Xe máy',
          vehicleColor: 'Đỏ',
          approvalStatus: 'Đã duyệt',
          isOnline: true,
          location: const GeoPoint(latitude: 10.7776, longitude: 106.6916),
          rating: 4.9,
          totalTrips: 320,
          rejectedCount: 6,
          walletBalance: 6190000,
          bankName: 'Vietcombank',
          bankAccount: '007100****889',
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
          isOnline: false,
          location: const GeoPoint(latitude: 10.7812, longitude: 106.7015),
          rating: 4.8,
          totalTrips: 215,
          rejectedCount: 8,
          walletBalance: 3450000,
          bankName: 'BIDV',
          bankAccount: '314100****221',
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
          rejectedCount: 5,
          walletBalance: 2180000,
          bankName: 'Techcombank',
          bankAccount: '190366****445',
        ),
        DriverApplicantRecord(
          id: 'DV10931',
          fullName: 'Phạm Quốc Bảo',
          phone: '0939887766',
          citizenId: '079094011223',
          licensePlate: '59-T1 889.90',
          vehicleType: 'Xe máy',
          vehicleColor: 'Đen nhám',
          approvalStatus: 'Đã duyệt',
          isOnline: true,
          location: const GeoPoint(latitude: 10.7765, longitude: 106.6995),
          rating: 4.9,
          totalTrips: 280,
          rejectedCount: 4,
          walletBalance: 4250000,
          bankName: 'ACB',
          bankAccount: '881200****556',
        ),
      ]);

    merchantApplicants
      ..clear()
      ..addAll([
        MerchantApplicantRecord(
          id: 'MER-01',
          ownerPhone: '0909112233',
          storeName: 'Cửa hàng Gốm Sứ Việt',
          businessType: 'Gốm sứ & Nội thất',
          taxCode: '0101234567-001',
          representativeName: 'Nguyễn Văn A',
          openHours: '08:00 - 21:00',
          bankName: 'Ngân hàng VPBank (VPB)',
          bankAccount: '123456789',
          approvalStatus: 'Đã duyệt',
          codBalance: 2650000,
        ),
        MerchantApplicantRecord(
          id: 'MER-02',
          ownerPhone: '0977889900',
          storeName: 'Thời trang Thiết kế Lụa Việt',
          businessType: 'Thời trang & Phụ kiện',
          taxCode: '0316549871',
          representativeName: 'Phạm Hoàng Yến',
          openHours: '08:30 - 22:00',
          bankName: 'Ngân hàng Techcombank (TCB)',
          bankAccount: '190388991122',
          approvalStatus: 'Chờ duyệt',
          codBalance: 0,
        ),
      ]);

    complaints
      ..clear()
      ..addAll([
        ComplaintTicketRecord(
          ticketCode: 'KN-001',
          orderId: '#DH789101',
          customerName: 'Nguyễn Thu Hà',
          driverName: 'Nguyễn Văn Nam',
          issueType: 'Giao hàng chậm',
          description: 'Đơn #DH789101 giao qua Phan Xích Long trễ 25 phút vào khung giờ cao điểm chiều.',
          status: 'Mới',
          replies: [
            'Nguyễn Thu Hà (17:45): Đơn hàng hôm qua giao tới Phú Nhuận trễ hơn dự kiến khoảng 25 phút.',
            'Admin (17:55): Chào bạn, bộ phận vận hành đã tiếp nhận và đang đối chiếu nhật ký lộ trình của tài xế.',
          ],
        ),
        ComplaintTicketRecord(
          ticketCode: 'KN-002',
          orderId: '#DH301201',
          customerName: 'Cửa hàng Gốm Sứ Việt',
          driverName: 'Nguyễn Văn Nam',
          issueType: 'Shop KN: Hàng hư hỏng',
          description:
              'Móp nhẹ góc hộp carton bên ngoài khi vận chuyển kiện #DH301201.',
          status: 'Đang xử lý',
          replies: [
            'Cửa hàng Gốm Sứ Việt (09:15): Kiện hàng gốm sứ bị móp nhẹ ở góc hộp.',
          ],
        ),
        ComplaintTicketRecord(
          ticketCode: 'KN-003',
          orderId: '#DH301203',
          customerName: 'Đinh Quốc Khánh',
          driverName: 'Phạm Quốc Bảo',
          issueType: 'Thiếu hàng',
          description: 'Người nhận phản ánh nhận trước 1 thùng, cần kiểm tra kiện phụ đi kèm.',
          status: 'Đã giải quyết',
          replies: [
            'Admin: Đã đối chiếu biên bản bàn giao và hoàn tất giao bổ sung kiện phụ trong ngày.',
          ],
        ),
      ]);

    withdrawalRequests
      ..clear()
      ..addAll([
        WithdrawalRequestRecord(
          id: 'WD-01',
          ownerId: 'DV10928',
          ownerName: 'Nguyễn Văn Nam',
          ownerRole: 'Tài xế',
          amount: 5000000,
          bankName: 'Vietcombank',
          accountMasked: '007100****889',
          requestDate: todayDateLabel,
          status: 'Chờ duyệt',
        ),
        WithdrawalRequestRecord(
          id: 'WD-02',
          ownerId: 'DV10929',
          ownerName: 'Trần Văn Hùng',
          ownerRole: 'Tài xế',
          amount: 3000000,
          bankName: 'BIDV',
          accountMasked: '314100****221',
          requestDate: todayDateLabel,
          status: 'Chờ duyệt',
        ),
        WithdrawalRequestRecord(
          id: 'WD-03',
          ownerId: 'MER-01',
          ownerName: 'Cửa hàng Gốm Sứ Việt',
          ownerRole: 'Cửa hàng (COD)',
          amount: 1150000,
          bankName: 'Ngân hàng VPBank (VPB)',
          accountMasked: '123456****789',
          requestDate: '$todayDateLabel 10:30',
          status: 'Chờ duyệt',
        ),
        WithdrawalRequestRecord(
          id: 'WD-04',
          ownerId: 'MER-01',
          ownerName: 'Cửa hàng Gốm Sứ Việt',
          ownerRole: 'Cửa hàng (COD)',
          amount: 1850000,
          bankName: 'Ngân hàng VPBank (VPB)',
          accountMasked: '123456****789',
          requestDate: '$fourDaysAgoLabel 14:15',
          status: 'Đã duyệt',
        ),
      ]);

    codReconciliations
      ..clear()
      ..addAll([
        CodReconciliationRecord(
          id: 'REC-MER-01',
          merchantId: 'MER-01',
          periodLabel:
              'Kỳ ${seedNow.month.toString().padLeft(2, '0')}/${seedNow.year}',
          totalCodCollected: 5800000,
          totalServiceFee: 150000,
          returnCancelFee: 0,
          netPayoutAmount: 5650000,
          status: 'RECONCILED',
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

  Future<void> persistTestRecords() async {
    final nowIso = DateTime.now().toIso8601String();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    for (final u in users) {
      await SqliteOfflineQueueDatasource.instance.upsertRow('users', {
        'id': u.id,
        'phone': EnvConfig.formatVietnamPhoneNational(u.phone),
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
      await SqliteOfflineQueueDatasource.instance.upsertRow('user_addresses', {
        'id': a.id,
        'user_phone': EnvConfig.formatVietnamPhoneNational(customerPhone),
        'label': a.label,
        'full_address': a.fullAddress,
        'latitude': a.location.latitude,
        'longitude': a.location.longitude,
        'created_at': nowIso,
      });
    }

    for (final d in drivers) {
      await SqliteOfflineQueueDatasource.instance.upsertRow('drivers', {
        'id': d.id,
        'phone': EnvConfig.formatVietnamPhoneNational(d.phone),
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
        'rejected_count': d.rejectedCount,
        'wallet_balance': d.walletBalance,
        'bank_name': d.bankName,
        'bank_account': d.bankAccount,
        'attached_kyc_docs_json': jsonEncode(d.attachedKycDocs),
        'created_at': nowIso,
      });
    }

    for (final m in merchantApplicants) {
      await SqliteOfflineQueueDatasource.instance.upsertRow('merchants', {
        'id': m.id,
        'owner_phone': EnvConfig.formatVietnamPhoneNational(m.ownerPhone),
        'store_name': m.storeName,
        'business_type': m.businessType,
        'tax_code': m.taxCode,
        'representative_name': m.representativeName,
        'open_hours': m.openHours,
        'bank_name': m.bankName,
        'bank_account': m.bankAccount,
        'cod_balance': m.codBalance,
        'approval_status': m.approvalStatus,
        'webhook_url': m.webhookUrl,
        'attached_kyc_docs_json': jsonEncode(m.attachedKycDocs),
        'created_at': nowIso,
      });
    }

    for (final w in merchantWarehouses) {
      await SqliteOfflineQueueDatasource.instance.upsertRow(
        'merchant_pickup_points',
        {
          'id': w.id,
          'merchant_id': w.merchantId,
          'warehouse_name': w.name,
          'full_address': w.address,
          'latitude': w.location.latitude,
          'longitude': w.location.longitude,
          'contact_phone': w.contactPhone,
          'open_hours': w.openHours,
          'is_primary': w.isPrimary ? 1 : 0,
          'webhook_url': w.webhookUrl,
          'created_at': nowIso,
        },
      );
      await SqliteOfflineQueueDatasource.instance.upsertEntityRecord(
        tableName: 'warehouse_meta',
        recordId: w.id,
        payload: {
          'isPrimary': w.isPrimary,
          'webhookUrl': w.webhookUrl,
          'contactPhone': w.contactPhone,
          'openHours': w.openHours,
        },
      );
    }

    for (final d in drivers) {
      await SqliteOfflineQueueDatasource.instance.upsertEntityRecord(
        tableName: 'driver_meta',
        recordId: d.id,
        payload: {
          'rejectedCount': d.rejectedCount,
          'bankName': d.bankName,
          'bankAccount': d.bankAccount,
          'attachedKycDocs': d.attachedKycDocs,
        },
      );
    }

    for (final m in merchantApplicants) {
      await SqliteOfflineQueueDatasource.instance.upsertEntityRecord(
        tableName: 'merchant_meta',
        recordId: m.id,
        payload: {
          'webhookUrl': m.webhookUrl,
          'attachedKycDocs': m.attachedKycDocs,
        },
      );
    }

    for (final rec in codReconciliations) {
      await SqliteOfflineQueueDatasource.instance.upsertRow(
        'cod_reconciliations',
        {
          'id': rec.id,
          'merchant_id': rec.merchantId,
          'period_label': rec.periodLabel,
          'total_cod_collected': rec.totalCodCollected,
          'total_service_fee': rec.totalServiceFee,
          'return_cancel_fee': rec.returnCancelFee,
          'net_payout_amount': rec.netPayoutAmount,
          'status': rec.status,
        },
      );
      await SqliteOfflineQueueDatasource.instance.upsertEntityRecord(
        tableName: 'cod_reconciliation_meta',
        recordId: rec.id,
        payload: {'returnCancelFee': rec.returnCancelFee},
      );
    }

    await SqliteOfflineQueueDatasource.instance.upsertRow('pricing_configs', {
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
      await SqliteOfflineQueueDatasource.instance.upsertRow('vouchers', {
        'code': v.code,
        'title': v.title,
        'discount_label': v.discountLabel,
        'discount_value': v.discountValue,
        'is_percentage': v.isPercentage ? 1 : 0,
        'max_discount': v.maxDiscount,
        'min_order_value': v.minOrderValue,
        'expiry_date': v.expiryDate,
        'status': v.status,
        'usage_limit': v.usageLimit,
        'used_count': v.usedCount,
      });
      await SqliteOfflineQueueDatasource.instance.upsertEntityRecord(
        tableName: 'voucher_meta',
        recordId: v.code,
        payload: {'usageLimit': v.usageLimit, 'usedCount': v.usedCount},
      );
    }

    for (var i = 0; i < orders.length; i++) {
      await SqliteOfflineQueueDatasource.instance.upsertRow(
        'orders',
        orders[i].toSqlRow(nowMs - i * 60000),
      );
    }

    for (final z in geofenceZones) {
      await SqliteOfflineQueueDatasource.instance.upsertRow('geofence_zones', {
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
      await SqliteOfflineQueueDatasource.instance.upsertRow(
        'admin_roles_permissions',
        {
          'id': 'RBAC-0${i + 1}',
          'role_name': r.roleName,
          'permissions_json': jsonEncode(r.permissions),
          'updated_at': nowIso,
        },
      );
    }

    for (var i = 0; i < withdrawalRequests.length; i++) {
      final w = withdrawalRequests[i];
      await SqliteOfflineQueueDatasource.instance.upsertRow(
        'wallets_and_transactions',
        {
          'id': w.id,
          'owner_id': w.ownerId,
          'owner_name': w.ownerName,
          'owner_role': w.ownerRole,
          'amount': w.amount,
          'bank_name': w.bankName,
          'account_masked': w.accountMasked,
          'request_date': w.requestDate,
          'status': w.status,
          'created_at_ms': nowMs - i * 60000,
        },
      );
      if (w.ownerId.isNotEmpty) {
        await SqliteOfflineQueueDatasource.instance.upsertEntityRecord(
          tableName: 'withdrawal_meta',
          recordId: w.id,
          payload: {'ownerId': w.ownerId},
        );
      }
    }

    for (var i = 0; i < complaints.length; i++) {
      final c = complaints[i];
      await SqliteOfflineQueueDatasource.instance.upsertRow(
        'incidents_and_complaints',
        {
          'ticket_code': c.ticketCode,
          'order_id': c.orderId,
          'customer_name': c.customerName,
          'driver_name': c.driverName,
          'issue_type': c.issueType,
          'description': c.description,
          'status': c.status,
          'replies_json': jsonEncode(c.replies),
          'evidence_files_json': jsonEncode(c.evidenceFiles),
          'created_at_ms': nowMs - i * 60000,
        },
      );
      if (c.evidenceFiles.isNotEmpty) {
        await SqliteOfflineQueueDatasource.instance.upsertEntityRecord(
          tableName: 'complaint_meta',
          recordId: c.ticketCode,
          payload: {'evidenceFiles': c.evidenceFiles},
        );
      }
    }

    for (var i = 0; i < chatMessages.length; i++) {
      final m = chatMessages[i];
      await SqliteOfflineQueueDatasource.instance.upsertRow(
        'chat_messages_and_notifications',
        {
          'id': m.id,
          'record_type': 'CHAT',
          'order_id': m.orderId,
          'recipient_key': null,
          'sender_name': m.senderName,
          'is_customer': m.isCustomer ? 1 : 0,
          'category': 'CHAT_MESSAGE',
          'title': m.senderName,
          'content': m.text,
          'target_group': 'INDIVIDUAL',
          'time_label': m.timeLabel,
          'is_read': 1,
          'created_at_ms': nowMs - (chatMessages.length - i) * 1000,
        },
      );
    }

    for (var i = 0; i < notifications.length; i++) {
      final n = notifications[i];
      await SqliteOfflineQueueDatasource.instance.upsertRow(
        'chat_messages_and_notifications',
        {
          'id': n.id,
          'record_type': 'NOTIFICATION',
          'order_id': n.recipientKey,
          'recipient_key': n.recipientKey,
          'sender_name': 'Hệ thống',
          'is_customer': 0,
          'category': n.category,
          'title': n.title,
          'content': n.title,
          'target_group': n.targetGroup,
          'time_label': n.timeAgo,
          'is_read': n.isRead ? 1 : 0,
          'created_at_ms': nowMs - i * 60000,
        },
      );
    }
  }
}
