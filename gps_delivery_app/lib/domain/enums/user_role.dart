enum SubsystemRole {
  customer('CUSTOMER', 'Phân hệ Khách hàng', 'Đặt đơn giao hàng, định vị GPS 3D, thanh toán & đánh giá dịch vụ'),
  driver('DRIVER', 'Phân hệ Tài xế', 'Nhận cuốc xe thông minh, dẫn đường 3D, xác nhận POD & ví thu nhập'),
  merchant('MERCHANT', 'Phân hệ Cửa hàng / Người gửi', 'Tạo đơn lẻ/hàng loạt CSV, in vận đơn A6, đối soát & rút tiền COD'),
  admin('ADMIN', 'Phân hệ Quản trị viên', 'Giám sát đội xe GPS, cấu hình giá cước, vùng Geofence & phân quyền');

  final String code;
  final String title;
  final String coverageSummary;

  const SubsystemRole(this.code, this.title, this.coverageSummary);
}
