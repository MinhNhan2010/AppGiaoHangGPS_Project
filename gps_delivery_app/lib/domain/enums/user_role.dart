enum SubsystemRole {
  customer('CUSTOMER', 'Phân hệ Khách hàng', '14 Use Case (UC01–UC12, UC41–UC42)'),
  driver('DRIVER', 'Phân hệ Tài xế', '9 Use Case (UC13–UC21)'),
  merchant('MERCHANT', 'Phân hệ Cửa hàng / Người gửi', '11 Use Case (UC30–UC40)'),
  admin('ADMIN', 'Phân hệ Quản trị viên', '12 Use Case (UC22–UC29, UC43–UC46)');

  final String code;
  final String title;
  final String coverageSummary;

  const SubsystemRole(this.code, this.title, this.coverageSummary);
}
