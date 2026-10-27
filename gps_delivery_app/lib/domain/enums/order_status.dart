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
    final trimmed = code.trim();
    final upper = trimmed.toUpperCase();
    final lower = trimmed.toLowerCase();
    return OrderStatus.values.firstWhere(
      (e) => e.dbCode == upper || e.name.toLowerCase() == lower,
      orElse: () => OrderStatus.draft,
    );
  }

  /// Thực thi quy tắc chuyển trạng thái hữu hạn FSM của đơn hàng
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
