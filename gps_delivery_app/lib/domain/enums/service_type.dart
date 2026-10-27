enum DeliveryServiceType {
  express30m(
    dbCode: 'EXPRESS_30M',
    displayName: 'Giao nhanh (Express)',
    subtitle: 'Giao hàng siêu tốc trong nội thành.',
    etaLabel: '1-2 giờ',
    defaultBaseFare: 15000,
    defaultPricePerKm: 8500,
    defaultPeakSurcharge: 20000,
  ),
  standard(
    dbCode: 'STANDARD',
    displayName: 'Giao tiêu chuẩn',
    subtitle: 'Phù hợp cho các đơn hàng thông thường.',
    etaLabel: '1-3 ngày',
    defaultBaseFare: 25000,
    defaultPricePerKm: 5000,
    defaultPeakSurcharge: 10000,
  ),
  saving(
    dbCode: 'SAVING',
    displayName: 'Giao tiết kiệm',
    subtitle: 'Cước phí tối ưu cho người kinh doanh.',
    etaLabel: '3-5 ngày',
    defaultBaseFare: 12000,
    defaultPricePerKm: 4000,
    defaultPeakSurcharge: 0,
  ),
  truck(
    dbCode: 'TRUCK',
    displayName: 'Giao hàng lớn',
    subtitle: 'Vận chuyển hàng hóa cồng kềnh.',
    etaLabel: '2-4 ngày',
    defaultBaseFare: 80000,
    defaultPricePerKm: 15000,
    defaultPeakSurcharge: 30000,
  );

  final String dbCode;
  final String displayName;
  final String subtitle;
  final String etaLabel;
  final double defaultBaseFare;
  final double defaultPricePerKm;
  final double defaultPeakSurcharge;

  const DeliveryServiceType({
    required this.dbCode,
    required this.displayName,
    required this.subtitle,
    required this.etaLabel,
    required this.defaultBaseFare,
    required this.defaultPricePerKm,
    required this.defaultPeakSurcharge,
  });

  static DeliveryServiceType fromDbCode(String code) {
    final trimmed = code.trim();
    final upper = trimmed.toUpperCase();
    final lower = trimmed.toLowerCase();
    if (upper == 'EXPRESS') return DeliveryServiceType.express30m;
    if (upper == 'ECONOMY') return DeliveryServiceType.saving;
    return DeliveryServiceType.values.firstWhere(
      (e) => e.dbCode == upper || e.name.toLowerCase() == lower,
      orElse: () => DeliveryServiceType.express30m,
    );
  }
}
