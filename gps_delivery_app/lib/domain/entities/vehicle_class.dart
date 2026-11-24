/// Vehicle classes a customer can request and a driver partner can register.
///
/// Wire ids must stay in sync with the backend contract
/// (`delivery_cloud_quote`, driver presence, driver applications).
class VehicleClass {
  const VehicleClass({
    required this.id,
    required this.label,
    required this.shortLabel,
    required this.maxKg,
    required this.heavy,
    required this.description,
    required this.licenseClasses,
    this.baseFee = 0,
    this.perKmFee = 0,
  });

  final String id;
  final String label;
  final String shortLabel;
  final int maxKg;

  /// Heavy vehicles always use the `truck` (bulky cargo) service tier.
  final bool heavy;
  final String description;

  /// Driving licence classes accepted when a driver registers this vehicle.
  final List<String> licenseClasses;

  /// Vehicle surcharge on top of the service tier price (VND).
  final int baseFee;
  final int perKmFee;

  static const motorbike = VehicleClass(
    id: 'motorbike',
    label: 'Xe máy',
    shortLabel: 'Xe máy',
    maxKg: 30,
    heavy: false,
    description: 'Tài liệu, đồ ăn, kiện nhỏ',
    licenseClasses: ['A1', 'A', 'A2'],
  );
  static const evScooter = VehicleClass(
    id: 'ev_scooter',
    label: 'Xe máy điện',
    shortLabel: 'Xe điện',
    maxKg: 30,
    heavy: false,
    description: 'Không khí thải · ưu tiên tài xế xe điện',
    licenseClasses: ['A1', 'A', 'A2'],
  );
  static const tricycle = VehicleClass(
    id: 'tricycle',
    label: 'Xe ba gác',
    shortLabel: 'Ba gác',
    maxKg: 300,
    heavy: true,
    description: 'Hàng cồng kềnh, đồ gia dụng',
    licenseClasses: ['A1', 'A', 'B', 'B1', 'B2'],
  );
  static const van = VehicleClass(
    id: 'van',
    label: 'Xe van',
    shortLabel: 'Van',
    maxKg: 500,
    heavy: true,
    description: 'Thùng kín, chuyển nhà nhỏ',
    licenseClasses: ['B', 'B1', 'B2', 'C1'],
    baseFee: 60000,
    perKmFee: 3000,
  );
  static const truck = VehicleClass(
    id: 'truck',
    label: 'Xe tải 1,5 tấn',
    shortLabel: 'Tải 1,5T',
    maxKg: 1500,
    heavy: true,
    description: 'Hàng số lượng lớn, nội thất',
    licenseClasses: ['C1', 'C'],
    baseFee: 150000,
    perKmFee: 8000,
  );

  static const all = [motorbike, evScooter, tricycle, van, truck];

  static VehicleClass? tryById(Object? id) {
    for (final v in all) {
      if (v.id == id) return v;
    }
    return null;
  }

  static VehicleClass byId(Object? id) => tryById(id) ?? motorbike;

  /// Same fallback the backend applies for clients that omit `vehicle_type`.
  static VehicleClass resolve({
    Object? vehicleType,
    Object? serviceType,
    bool preferEv = false,
  }) {
    final explicit = tryById(vehicleType);
    if (explicit != null) return explicit;
    if (serviceType == 'truck') return van;
    return preferEv ? evScooter : motorbike;
  }

  /// Smallest vehicle that can carry [kg], preferring [current] when it fits.
  static VehicleClass suggestFor(double kg, {VehicleClass? current}) {
    if (current != null && kg <= current.maxKg) return current;
    for (final v in [motorbike, tricycle, van, truck]) {
      if (kg <= v.maxKg) return v;
    }
    return truck;
  }

  bool allowsService(String serviceType) =>
      heavy ? serviceType == 'truck' : serviceType != 'truck';

  bool acceptsLicense(String licenseClass) =>
      licenseClasses.contains(licenseClass.trim().toUpperCase());

  /// Whether a driver registered with this vehicle can serve an order that
  /// requested [orderVehicle] (capacity rule shared with dispatch).
  bool canServe(VehicleClass orderVehicle) => switch (orderVehicle.id) {
    'motorbike' => id == 'motorbike' || id == 'ev_scooter',
    'ev_scooter' => id == 'ev_scooter',
    'tricycle' => id == 'tricycle' || id == 'van' || id == 'truck',
    'van' => id == 'van' || id == 'truck',
    _ => id == 'truck',
  };

  /// Estimated vehicle surcharge, mirroring the server formula.
  int estimateFee(double km) {
    if (baseFee == 0 && perKmFee == 0) return 0;
    final extraKm = (km - 2).ceil();
    return baseFee + (extraKm > 0 ? extraKm : 0) * perKmFee;
  }
}
