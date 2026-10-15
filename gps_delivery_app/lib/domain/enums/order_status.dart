enum OrderStatus {
  draft('DRAFT', 'Bản nháp'),
  searching('SEARCHING', 'Tìm tài xế'),
  accepted('ACCEPTED', 'Tài xế đã nhận'),
  arrivingPickup('ARRIVING_PICKUP', 'Đang đến lấy hàng'),
  inTransit('IN_TRANSIT', 'Đang giao hàng'),
  delivered('DELIVERED', 'Giao thành công'),
  cancelled('CANCELLED', 'Đã hủy đơn'),
  failed('FAILED', 'Giao thất bại'),
  returning('RETURNING', 'Chuyển hoàn');

  final String dbCode;
  final String displayName;

  const OrderStatus(this.dbCode, this.displayName);

  static OrderStatus fromDbCode(String code) {
    return OrderStatus.values.firstWhere(
      (e) => e.dbCode == code,
      orElse: () => OrderStatus.draft,
    );
  }

  /// Enforces Finite State Machine transition rules (Chapter 10.3 - Table 22)
  bool canTransitionTo(OrderStatus next) {
    return switch (this) {
      OrderStatus.draft =>
        next == OrderStatus.searching || next == OrderStatus.cancelled,
      OrderStatus.searching =>
        next == OrderStatus.accepted || next == OrderStatus.cancelled,
      OrderStatus.accepted =>
        next == OrderStatus.arrivingPickup || next == OrderStatus.cancelled,
      OrderStatus.arrivingPickup =>
        next == OrderStatus.inTransit || next == OrderStatus.cancelled,
      OrderStatus.inTransit =>
        next == OrderStatus.delivered || next == OrderStatus.failed,
      OrderStatus.failed =>
        next == OrderStatus.inTransit || next == OrderStatus.returning,
      OrderStatus.returning => next == OrderStatus.delivered,
      OrderStatus.delivered || OrderStatus.cancelled => false,
    };
  }
}
