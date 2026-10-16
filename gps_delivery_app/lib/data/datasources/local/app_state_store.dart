import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/env_config.dart';
import '../../../core/gps/gps_integrity_validator.dart';
import '../../../core/gps/kalman_gps_filter.dart';
import '../../../core/gps/smart_dispatch_engine.dart';
import '../../../core/utils/geo_math.dart';
import '../../../domain/entities/geo_point.dart';
import '../../../domain/entities/pricing_estimate.dart';
import '../../../domain/enums/order_status.dart';
import '../../../domain/enums/service_type.dart';
import '../remote/supabase_postgis_datasource.dart';


class SavedAddressRecord {
  final String id;
  final String label;
  final String fullAddress;
  final GeoPoint location;

  const SavedAddressRecord({
    required this.id,
    required this.label,
    required this.fullAddress,
    required this.location,
  });
}

class VoucherRecord {
  final String code;
  final String title;
  final String discountLabel;
  final double discountValue;
  final bool isPercentage;
  final double maxDiscount;
  final double minOrderValue;
  final String expiryDate;
  final String status;

  const VoucherRecord({
    required this.code,
    required this.title,
    required this.discountLabel,
    required this.discountValue,
    required this.isPercentage,
    required this.maxDiscount,
    required this.minOrderValue,
    required this.expiryDate,
    required this.status,
  });
}

class ChatMessageRecord {
  final String id;
  final String orderId;
  final String senderName;
  final bool isCustomer;
  final String text;
  final String timeLabel;

  const ChatMessageRecord({
    required this.id,
    required this.orderId,
    required this.senderName,
    required this.isCustomer,
    required this.text,
    required this.timeLabel,
  });
}

class NotificationRecord {
  final String id;
  final String category;
  final String title;
  final String timeAgo;
  final String targetGroup;
  final bool isRead;

  const NotificationRecord({
    required this.id,
    required this.category,
    required this.title,
    required this.timeAgo,
    this.targetGroup = 'Khách hàng',
    this.isRead = false,
  });
}

class DriverApplicantRecord {
  final String id;
  final String fullName;
  final String phone;
  final String citizenId;
  final String licensePlate;
  final String vehicleType;
  final String vehicleColor;
  String approvalStatus;
  final bool isOnline;
  final GeoPoint location;
  final double rating;
  final int totalTrips;

  DriverApplicantRecord({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.citizenId,
    required this.licensePlate,
    required this.vehicleType,
    required this.vehicleColor,
    required this.approvalStatus,
    this.isOnline = true,
    required this.location,
    this.rating = 4.8,
    this.totalTrips = 320,
  });
}

class ComplaintTicketRecord {
  final String ticketCode;
  final String orderId;
  final String customerName;
  final String driverName;
  final String issueType;
  final String description;
  String status;
  final List<String> replies;

  ComplaintTicketRecord({
    required this.ticketCode,
    required this.orderId,
    required this.customerName,
    required this.driverName,
    required this.issueType,
    required this.description,
    required this.status,
    required this.replies,
  });
}

class WithdrawalRequestRecord {
  final String id;
  final String ownerName;
  final String ownerRole;
  final double amount;
  final String bankName;
  final String accountMasked;
  final String requestDate;
  String status;

  WithdrawalRequestRecord({
    required this.id,
    required this.ownerName,
    required this.ownerRole,
    required this.amount,
    required this.bankName,
    required this.accountMasked,
    required this.requestDate,
    required this.status,
  });
}

class GeofenceZoneRecord {
  final String id;
  final String zoneName;
  final String zoneType;
  final double surchargeRate;
  bool isActive;
  final List<GeoPoint> boundary;

  GeofenceZoneRecord({
    required this.id,
    required this.zoneName,
    required this.zoneType,
    required this.surchargeRate,
    required this.isActive,
    required this.boundary,
  });
}

class RbacRoleRecord {
  final String roleName;
  final Map<String, bool> permissions;

  RbacRoleRecord({
    required this.roleName,
    required this.permissions,
  });
}

class PickupWarehouseRecord {
  final String id;
  final String name;
  final String address;
  final GeoPoint location;

  const PickupWarehouseRecord({
    required this.id,
    required this.name,
    required this.address,
    required this.location,
  });
}

class ActiveOrderRecord {
  final String id;
  final String trackingCode;
  final String customerName;
  final String recipientName;
  final String recipientPhone;
  final String pickupAddress;
  final String dropoffAddress;
  final GeoPoint pickupLocation;
  final GeoPoint dropoffLocation;
  final DeliveryServiceType serviceType;
  final String packageDescription;
  final double weightKg;
  final String dimensionsCm;
  int distanceMeters;
  int durationSeconds;
  final double deliveryFee;
  final double surchargeFee;
  final double discountAmount;
  final double codAmount;
  final double totalAmount;
  String paymentMethod;
  String paymentStatus;
  OrderStatus status;
  String? assignedDriverName;
  String? assignedDriverPlate;
  String? podImageNote;
  String? cancelReason;
  int? ratingStars;
  String? ratingComment;
  final String createdDateLabel;

  ActiveOrderRecord({
    required this.id,
    required this.trackingCode,
    required this.customerName,
    required this.recipientName,
    required this.recipientPhone,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.serviceType,
    required this.packageDescription,
    required this.weightKg,
    required this.dimensionsCm,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.deliveryFee,
    required this.surchargeFee,
    required this.discountAmount,
    required this.codAmount,
    required this.totalAmount,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.status,
    this.assignedDriverName,
    this.assignedDriverPlate,
    this.podImageNote,
    this.cancelReason,
    this.ratingStars,
    this.ratingComment,
    required this.createdDateLabel,
  });
}

class AppStateStore extends ChangeNotifier {
  static final AppStateStore instance = AppStateStore._internal();

  final KalmanGpsFilter _kalmanFilter = KalmanGpsFilter();
  bool isOfflineMode = false;
  int offlineQueueCount = 0;
  bool isDriverOnline = true;
  bool isMap3dEnabled = true;
  double currentCameraPitch = 55.0;
  int batteryPercent = 85;
  double currentSpeedKmh = 35.0;

  // Live GPS Tracking & Route Progression (UC07, UC16, UC18, UC25)
  GeoPoint activeDriverLocation =
      const GeoPoint(latitude: 21.0068, longitude: 105.8421);
  double activeDriverBearing = 215.0;
  int routeProgressStep = 4;
  String currentAdminRoleName = 'Super Admin';
  String lastSyncStatusMessage =
      'Đã đồng bộ 16/16 bảng với PostgreSQL 16 + PostGIS';

  // Customer Profile (UC41 - Hình 8.13)
  String customerFullName = 'Nguyễn Thu Hà';
  String customerPhone = '+84 912 345 678';
  String customerEmail = 'thu.ha@gmail.com';
  String customerDefaultAddress = '123 Đường Lê Lợi, Quận 1, TP. HCM';

  // Pricing Formula Config (UC26 - Hình 8.28)
  double baseFareConfig = 25000;
  double pricePerKmConfig = 5000;
  double peakHourSurchargeConfig = 10000;
  double badWeatherSurchargeConfig = 15000;
  bool isPeakSurchargeActive = true;
  bool isWeatherSurchargeActive = true;

  // Merchant Store Info (UC30, UC31 - Hình 8.36, 8.37)
  String merchantStoreName = 'Cửa hàng Gốm Sứ Việt';
  String merchantBusinessType = 'Gốm sứ & Nội thất';
  String merchantTaxCode = '0316892451';
  String merchantRepresentative = 'Nguyễn Văn A';
  String merchantOpenHours = '8:00 AM - 9:00 PM (Thứ 2 - Chủ Nhật)';
  String merchantBankName = 'Ngân hàng VPBank (VPB)';
  String merchantBankAccount = '123456****789';
  double merchantCodBalance = 5250000;
  double driverWalletBalance = 6190000;

  final List<SavedAddressRecord> savedAddresses = [
    const SavedAddressRecord(
      id: 'ADDR-01',
      label: 'Nhà',
      fullAddress: '12 Nguyễn Huệ, P. Bến Nghé, Q.1, TP. HCM',
      location: GeoPoint(latitude: 10.7745, longitude: 106.7035),
    ),
    const SavedAddressRecord(
      id: 'ADDR-02',
      label: 'Cơ quan',
      fullAddress: 'Bitexco Financial Tower, 45 Lê Lợi, P. Bến Nghé, Q.1, TP. HCM',
      location: GeoPoint(latitude: 10.7716, longitude: 106.7044),
    ),
    const SavedAddressRecord(
      id: 'ADDR-03',
      label: 'Khác',
      fullAddress: '18A/24 Nguyễn Thị Minh Khai, P. Đa Kao, Q.1, TP. HCM',
      location: GeoPoint(latitude: 10.7882, longitude: 106.7012),
    ),
  ];

  final List<PickupWarehouseRecord> merchantWarehouses = [
    const PickupWarehouseRecord(
      id: 'WH-01',
      name: 'Kho chính',
      address: '123 Đường Lê Lợi, Phường Bến Nghé, Quận 1, TP. HCM',
      location: GeoPoint(latitude: 10.7769, longitude: 106.6953),
    ),
    const PickupWarehouseRecord(
      id: 'WH-02',
      name: 'Chi nhánh Q.3',
      address: '456 Đường Nguyễn Đình Chiểu, Phường 6, Quận 3, TP. HCM',
      location: GeoPoint(latitude: 10.7752, longitude: 106.6869),
    ),
  ];

  final List<VoucherRecord> vouchers = [
    const VoucherRecord(
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
    const VoucherRecord(
      code: 'GHN-SUMMER24',
      title: 'GIẢM 20% ĐƠN ĐẦU TIÊN',
      discountLabel: '20%',
      discountValue: 20,
      isPercentage: true,
      maxDiscount: 50000,
      minOrderValue: 500000,
      expiryDate: '30/09/2026',
      status: 'Đang hoạt động',
    ),
    const VoucherRecord(
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
    const VoucherRecord(
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
  ];

  final List<ActiveOrderRecord> orders = [
    ActiveOrderRecord(
      id: 'ORD-01',
      trackingCode: '#DH123456',
      customerName: 'Nguyễn Thu Hà',
      recipientName: 'Nguyễn Thị Minh An',
      recipientPhone: '0912345678',
      pickupAddress: '145 Phố Huế, Hai Bà Trưng, Hà Nội',
      dropoffAddress: 'Số 15, Ngõ 100, Đường Lê Trọng Tấn, Quận Thanh Xuân, Hà Nội',
      pickupLocation: const GeoPoint(latitude: 21.0145, longitude: 105.8512),
      dropoffLocation: const GeoPoint(latitude: 20.9951, longitude: 105.8286),
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
      pickupLocation: const GeoPoint(latitude: 10.7731, longitude: 106.6983),
      dropoffLocation: const GeoPoint(latitude: 10.7992, longitude: 106.6805),
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
      podImageNote: 'Đã chụp ảnh kiện hàng kèm Watermark GPS (10.7992, 106.6805)',
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
      pickupLocation: const GeoPoint(latitude: 10.7821, longitude: 106.6951),
      dropoffLocation: const GeoPoint(latitude: 10.7761, longitude: 106.6894),
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
  ];

  final List<ChatMessageRecord> chatMessages = [
    const ChatMessageRecord(
      id: 'MSG-01',
      orderId: '#DH123456',
      senderName: 'Nguyễn Thu Hà',
      isCustomer: true,
      text: 'Anh đến chưa ạ? Mình đang đợi ở sảnh.',
      timeLabel: '10:32',
    ),
    const ChatMessageRecord(
      id: 'MSG-02',
      orderId: '#DH123456',
      senderName: 'Nguyễn Văn Nam',
      isCustomer: false,
      text: 'Dạ, chào bạn. Anh đang đi đến điểm đón rồi nhé. Còn 5 phút nữa nhé.',
      timeLabel: '10:32',
    ),
    const ChatMessageRecord(
      id: 'MSG-03',
      orderId: '#DH123456',
      senderName: 'Nguyễn Thu Hà',
      isCustomer: true,
      text: 'Vâng ạ, mình đợi. Xe anh màu gì thế ạ?',
      timeLabel: '10:33',
    ),
  ];

  final List<NotificationRecord> notifications = [
    const NotificationRecord(
      id: 'NOTI-01',
      category: 'Đơn hàng',
      title: 'Đơn hàng #GH8921 đã giao thành công',
      timeAgo: '5 phút trước',
    ),
    const NotificationRecord(
      id: 'NOTI-02',
      category: 'Đơn hàng',
      title: 'Tài xế Nguyễn Văn Nam đang đến điểm lấy hàng',
      timeAgo: '1 giờ trước',
    ),
    const NotificationRecord(
      id: 'NOTI-03',
      category: 'Khuyến mãi',
      title: 'Khuyến mãi giảm 30% phí giao hàng hôm nay',
      timeAgo: '3 giờ trước',
    ),
  ];

  final List<DriverApplicantRecord> drivers = [
    DriverApplicantRecord(
      id: 'DV10928',
      fullName: 'Nguyễn Văn Nam',
      phone: '0987 654 321',
      citizenId: '001095012345',
      licensePlate: '29A-123.45',
      vehicleType: 'Xe máy',
      vehicleColor: 'Đỏ',
      approvalStatus: 'Chờ duyệt',
      isOnline: true,
      location: const GeoPoint(latitude: 10.7769, longitude: 106.6953),
      rating: 4.9,
      totalTrips: 320,
    ),
    DriverApplicantRecord(
      id: 'DV10929',
      fullName: 'Trần Văn Hùng',
      phone: '0912 345 678',
      citizenId: '079092054321',
      licensePlate: '59-P2 678.90',
      vehicleType: 'Xe máy',
      vehicleColor: 'Xanh đen',
      approvalStatus: 'Đã duyệt',
      isOnline: true,
      location: const GeoPoint(latitude: 10.7812, longitude: 106.7015),
      rating: 4.8,
      totalTrips: 215,
    ),
    DriverApplicantRecord(
      id: 'DV10930',
      fullName: 'Lê Thị Mai',
      phone: '0909 112 233',
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
  ];

  final List<ComplaintTicketRecord> complaints = [
    ComplaintTicketRecord(
      ticketCode: 'KN-001',
      orderId: '#DH123456',
      customerName: 'Nguyễn Văn A',
      driverName: 'Trần Văn B',
      issueType: 'Giao hàng chậm',
      description: 'Giao hàng trễ hơn 2 tiếng so với dự kiến. Khách hàng đã phải chờ đợi quá lâu.',
      status: 'Mới',
      replies: [
        'Nguyễn Văn A (10:30): Hôm nay tôi đã nhận hàng quá muộn, trễ 2 tiếng so với hẹn.',
        'Admin (10:45): Chào bạn, chúng tôi đã ghi nhận khiếu nại và đang kiểm tra lộ trình GPS của tài xế.',
      ],
    ),
    ComplaintTicketRecord(
      ticketCode: 'KN-002',
      orderId: '#DH789101',
      customerName: 'Trần Thị B',
      driverName: 'Nguyễn Văn Nam',
      issueType: 'Hàng hư hỏng',
      description: 'Móp góc hộp carton bên ngoài khi vận chuyển.',
      status: 'Đang xử lý',
      replies: [
        'Trần Thị B (09:15): Kiện hàng gốm sứ bị móp nhẹ ở góc hộp.',
      ],
    ),
    ComplaintTicketRecord(
      ticketCode: 'KN-003',
      orderId: '#DH556778',
      customerName: 'Lê Văn C',
      driverName: 'Phạm Văn Đức',
      issueType: 'Thiếu hàng',
      description: 'Shop gửi 3 kiện nhưng người nhận mới nhận 2 kiện.',
      status: 'Đã giải quyết',
      replies: [
        'Admin: Đã đối chiếu phiếu giao hàng và hoàn tất giao bổ sung kiện thứ 3.',
      ],
    ),
  ];

  final List<WithdrawalRequestRecord> withdrawalRequests = [
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
      ownerName: 'Cửa hàng Hoa Lan',
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
  ];

  final List<GeofenceZoneRecord> geofenceZones = [
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
  ];

  final List<RbacRoleRecord> rbacRoles = [
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
  ];

  AppStateStore._internal();

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
    notifyListeners();
  }

  void toggleMap3d() {
    isMap3dEnabled = !isMap3dEnabled;
    currentCameraPitch = isMap3dEnabled ? 55.0 : 0.0;
    notifyListeners();
  }

  /// Bước di chuyển GPS thực tế của tài xế dọc theo lộ trình qua bộ lọc Kalman 2D (UC07, UC16, UC18)
  void stepDriverAlongRoute({bool snapToDropoff = false}) {
    final ord = orders.first;
    final polyline = SmartDispatchEngine.generateRoutePolyline(
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
    activeDriverBearing = GeoMath.bearingDegrees(previous, activeDriverLocation);
    if (isOfflineMode) offlineQueueCount++;
    notifyListeners();
  }

  /// Khoảng cách Haversine thực tế từ vị trí Tài xế hiện tại tới điểm giao hàng (RULE-ORD-03)
  double distanceFromDriverToDropoffMeters() {
    final ord = orders.first;
    return GeoMath.distanceMeters(activeDriverLocation, ord.dropoffLocation);
  }

  /// Đọc tọa độ từ Chip GPS Phần cứng thiết bị thật qua Geolocator + Kiểm định chống Fake GPS + Lọc Kalman 2D
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
      notifyListeners();
      return lastSyncStatusMessage;
    } catch (e) {
      return 'Không thể đọc cảm biến GPS phần cứng ($e). Đang dùng tọa độ Kalman hiện tại.';
    }
  }

  /// Đồng bộ lộ trình đường phố thực tế từ máy chủ OSRM (`router.project-osrm.org`)
  Future<String> syncLiveOsrmRouteForActiveOrder() async {
    final ord = orders.first;
    final res = await SmartDispatchEngine.fetchLiveOsrmRoute(
      ord.pickupLocation,
      ord.dropoffLocation,
    );
    ord.distanceMeters = res.distanceMeters;
    ord.durationSeconds = res.durationSeconds;
    final km = (res.distanceMeters / 1000.0).toStringAsFixed(1);
    final mins = (res.durationSeconds / 60).round().clamp(5, 240);
    lastSyncStatusMessage = res.isLiveOsrm
        ? 'OSRM Thực tế: $km km ($mins phút) - ${res.polylinePoints.length} điểm tọa độ'
        : 'Nội suy Haversine Offline: $km km ($mins phút)';
    notifyListeners();
    return lastSyncStatusMessage;
  }

  /// Cấu hình nóng kết nối Cloud Supabase PostgreSQL/PostGIS và đồng bộ thử nghiệm 16 bảng
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
      } catch (_) {
        // Đã khởi tạo trước đó trong phiên chạy
      }
      final remoteDs = SupabasePostgisDatasource();
      final rows = await remoteDs.fetchTableRecords('orders', limit: 10);
      isOfflineMode = false;
      offlineQueueCount = 0;
      lastSyncStatusMessage =
          'Đã kết nối Cloud Supabase PostGIS thành công (${rows.length} bản ghi orders trên mây)';
      notifyListeners();
      return lastSyncStatusMessage;
    } catch (e) {
      lastSyncStatusMessage =
          'Đã lưu cấu hình Supabase. Máy chủ trả về: $e (Đang duy trì đồng bộ SQLite dự phòng)';
      notifyListeners();
      return lastSyncStatusMessage;
    }
  }

  /// Kiểm tra quyền thực thi RBAC của vai trò Admin đang đăng nhập (UC46)
  bool hasAdminPermission(String permKey) {
    final role =
        rbacRoles.where((r) => r.roleName == currentAdminRoleName).firstOrNull;
    if (role == null) return true;
    return role.permissions[permKey] ?? false;
  }

  void setAdminActiveRole(String roleName) {
    currentAdminRoleName = roleName;
    notifyListeners();
  }

  void addCustomGeofenceZone({
    required String zoneName,
    required String zoneType,
    required double surchargeRate,
    required List<GeoPoint> vertices,
  }) {
    if (vertices.length < 3) return;
    geofenceZones.add(
      GeofenceZoneRecord(
        id: 'GEO-0${geofenceZones.length + 1}',
        zoneName: zoneName,
        zoneType: zoneType,
        surchargeRate: surchargeRate,
        isActive: true,
        boundary: List<GeoPoint>.from(vertices),
      ),
    );
    notifyListeners();
  }

  void addCustomerAddress(String label, String address) {
    final resolved = SmartDispatchEngine.resolveAddressToCoordinate(
      address,
      fallback: const GeoPoint(latitude: 10.7785, longitude: 106.6980),
    );
    savedAddresses.add(
      SavedAddressRecord(
        id: 'ADDR-0${savedAddresses.length + 1}',
        label: label,
        fullAddress: address,
        location: resolved,
      ),
    );
    notifyListeners();
  }

  void removeCustomerAddress(String id) {
    savedAddresses.removeWhere((a) => a.id == id);
    notifyListeners();
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
    final distMeters = isDefaultRoute
        ? 14500
        : (rawAirMeters * 1.28).round().clamp(1500, 45000);
    final durationSec = isDefaultRoute
        ? 2700
        : ((distMeters / 1000.0) * 180).round();

    double geofenceFee = 0;
    for (final z in geofenceZones) {
      if (z.isActive &&
          z.surchargeRate > 0 &&
          GeoMath.isPointInPolygon(dropoffPt, z.boundary)) {
        geofenceFee += z.surchargeRate;
      }
    }

    final preDiscountEst = PricingEstimate.calculate(
      serviceType: serviceType,
      distanceMeters: distMeters,
      durationSeconds: durationSec,
      isPeakHour: isPeakSurchargeActive,
      geofenceSurcharge: geofenceFee,
      voucherDiscount: 0,
    );

    double discount = 0;
    if (voucherCode != null && voucherCode.trim().isNotEmpty) {
      final matched = vouchers
          .where((v) => v.code.toUpperCase() == voucherCode.trim().toUpperCase())
          .firstOrNull;
      if (matched != null) {
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
    );

    final record = ActiveOrderRecord(
      id: 'ORD-0${orders.length + 1}',
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
      paymentStatus: paymentMethod == 'Tiền mặt (COD)' ? 'UNPAID' : 'PAID',
      status: OrderStatus.searching,
      createdDateLabel: 'Hôm nay',
    );
    orders.insert(0, record);
    if (isOfflineMode) offlineQueueCount++;
    notifyListeners();
    return record;
  }

  void driverAcceptOrder(String trackingCode, {String? customDriverName, String? customPlate}) {
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord == null) return;
    if (!ord.status.canTransitionTo(OrderStatus.accepted)) return;
    ord.status = OrderStatus.accepted;
    ord.assignedDriverName = customDriverName ?? 'Nguyễn Văn Nam';
    ord.assignedDriverPlate = customPlate ?? '29-P1 123.45';
    notifyListeners();
  }

  void driverAdvanceOrderStatus(String trackingCode, {String? podNote}) {
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord == null) return;
    switch (ord.status) {
      case OrderStatus.searching:
      case OrderStatus.draft:
        ord.status = OrderStatus.accepted;
        ord.assignedDriverName = 'Nguyễn Văn Nam';
        ord.assignedDriverPlate = '29-P1 123.45';
      case OrderStatus.accepted:
        ord.status = OrderStatus.arrivingPickup;
      case OrderStatus.arrivingPickup:
        ord.status = OrderStatus.inTransit;
      case OrderStatus.inTransit:
        ord.status = OrderStatus.delivered;
        ord.paymentStatus = 'PAID';
        ord.podImageNote =
            podNote ?? 'Đã chụp ảnh kiện hàng kèm Watermark GPS & OTP 4 số';
        // RULE-FIN-01: Tài xế hưởng 80% tổng cước vận chuyển (khấu trừ 20% phí nền tảng)
        final driverNetEarning =
            ((ord.deliveryFee + ord.surchargeFee) * 0.80).roundToDouble();
        driverWalletBalance += driverNetEarning;
        merchantCodBalance += ord.codAmount;
      default:
        break;
    }
    if (isOfflineMode) offlineQueueCount++;
    notifyListeners();
  }

  bool cancelOrder(String trackingCode, String reason) {
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord == null) return false;
    // RULE-ORD-02 & Bảng 22: Chỉ cho phép hủy khi trạng thái đơn hợp lệ trong FSM
    if (!ord.status.canTransitionTo(OrderStatus.cancelled)) {
      return false;
    }
    ord.status = OrderStatus.cancelled;
    ord.cancelReason = reason;
    notifyListeners();
    return true;
  }

  void submitDriverRating(String trackingCode, int stars, String comment) {
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord != null) {
      ord.ratingStars = stars;
      ord.ratingComment = comment;
    }
    notifyListeners();
  }

  void sendChatMessage(String orderId, String text, {required bool isCustomer}) {
    if (text.trim().isEmpty) return;
    chatMessages.add(
      ChatMessageRecord(
        id: 'MSG-0${chatMessages.length + 1}',
        orderId: orderId,
        senderName: isCustomer ? customerFullName : 'Nguyễn Văn Nam',
        isCustomer: isCustomer,
        text: text.trim(),
        timeLabel: 'Vừa xong',
      ),
    );
    notifyListeners();
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
      // RULE-FIN-02: Bắt buộc duy trì số dư ký quỹ tối thiểu 200.000 VNĐ trong ví Tài xế
      if (driverWalletBalance - amount < 200000) return false;
      driverWalletBalance -= amount;
    } else {
      if (merchantCodBalance < amount) return false;
      merchantCodBalance -= amount;
    }
    withdrawalRequests.insert(
      0,
      WithdrawalRequestRecord(
        id: 'WD-0${withdrawalRequests.length + 1}',
        ownerName: ownerName,
        ownerRole: ownerRole,
        amount: amount,
        bankName: bankName,
        accountMasked: accountMasked,
        requestDate: 'Vừa xong',
        status: 'Chờ duyệt',
      ),
    );
    notifyListeners();
    return true;
  }

  void updateWithdrawalStatus(String id, String status) {
    final req = withdrawalRequests.where((w) => w.id == id).firstOrNull;
    if (req != null) {
      final previousStatus = req.status;
      req.status = status;
      // Hoàn trả lại số dư vào ví nếu lệnh rút tiền bị Từ chối từ trạng thái Chờ duyệt
      if (previousStatus == 'Chờ duyệt' && status == 'Từ chối') {
        if (req.ownerRole == 'Tài xế') {
          driverWalletBalance += req.amount;
        } else {
          merchantCodBalance += req.amount;
        }
      }
      notifyListeners();
    }
  }

  void updateDriverApproval(String id, String status) {
    final drv = drivers.where((d) => d.id == id).firstOrNull;
    if (drv != null) {
      drv.approvalStatus = status;
      notifyListeners();
    }
  }

  void addIncidentOrComplaint({
    required String orderId,
    required String reporterName,
    required String issueType,
    required String description,
  }) {
    complaints.insert(
      0,
      ComplaintTicketRecord(
        ticketCode: 'KN-00${complaints.length + 1}',
        orderId: orderId,
        customerName: reporterName,
        driverName: 'Nguyễn Văn Nam',
        issueType: issueType,
        description: description,
        status: 'Mới',
        replies: ['$reporterName: $description'],
      ),
    );
    notifyListeners();
  }

  void replyComplaint(String ticketCode, String replyText, String nextStatus) {
    final item =
        complaints.where((c) => c.ticketCode == ticketCode).firstOrNull;
    if (item != null) {
      item.status = nextStatus;
      if (replyText.trim().isNotEmpty) {
        item.replies.add('Admin: ${replyText.trim()}');
      }
      notifyListeners();
    }
  }

  void broadcastSystemNotification({
    required String title,
    required String targetGroup,
  }) {
    notifications.insert(
      0,
      NotificationRecord(
        id: 'NOTI-0${notifications.length + 1}',
        category: 'Hệ thống',
        title: title,
        targetGroup: targetGroup,
        timeAgo: 'Vừa xong',
      ),
    );
    notifyListeners();
  }

  void toggleRbacPermission(String roleName, String permKey, bool value) {
    final role = rbacRoles.where((r) => r.roleName == roleName).firstOrNull;
    if (role != null) {
      role.permissions[permKey] = value;
      notifyListeners();
    }
  }

  void toggleGeofenceZone(String id, bool active) {
    final z = geofenceZones.where((g) => g.id == id).firstOrNull;
    if (z != null) {
      z.isActive = active;
      notifyListeners();
    }
  }
}
