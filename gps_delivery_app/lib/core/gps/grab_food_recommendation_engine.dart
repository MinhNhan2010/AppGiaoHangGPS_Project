import '../../data/models/app_state_records.dart';
import '../../domain/entities/geo_point.dart';
import '../../domain/entities/pricing_estimate.dart';
import '../../domain/enums/service_type.dart';
import '../utils/geo_math.dart';

enum MealTimeSlot {
  auto('auto', 'Tự động theo giờ', 'Đề xuất thông minh theo khung giờ hiện tại'),
  breakfast('breakfast', 'Bữa sáng', '05:00 - 10:59 • Phở, bánh mì, cà phê'),
  lunch('lunch', 'Cơm trưa', '11:00 - 13:59 • Cơm tấm, bún chả, healthy bowl'),
  afternoonTea(
    'afternoonTea',
    'Trà chiều',
    '14:00 - 16:59 • Trà sữa, cà phê, ăn vặt',
  ),
  dinner('dinner', 'Ăn tối', '17:00 - 21:59 • Món nóng, lẩu, cơm gia đình'),
  lateNight('lateNight', 'Đêm khuya', '22:00 - 04:59 • Cháo sườn, phở đêm');

  final String dbCode;
  final String displayName;
  final String subtitle;

  const MealTimeSlot(this.dbCode, this.displayName, this.subtitle);

  static MealTimeSlot resolveForHour(int hour) {
    final safeHour = hour % 24;
    if (safeHour >= 5 && safeHour <= 10) return MealTimeSlot.breakfast;
    if (safeHour >= 11 && safeHour <= 13) return MealTimeSlot.lunch;
    if (safeHour >= 14 && safeHour <= 16) return MealTimeSlot.afternoonTea;
    if (safeHour >= 17 && safeHour <= 21) return MealTimeSlot.dinner;
    return MealTimeSlot.lateNight;
  }

  MealTimeSlot effectiveSlotForNow([DateTime? now]) {
    if (this != MealTimeSlot.auto) return this;
    return resolveForHour((now ?? DateTime.now()).hour);
  }
}

enum GrabFoodQuickFilter {
  all('Tất cả'),
  nearMe('Gần tôi (< 3km)'),
  riceNoodlePho('Cơm • Bún • Phở'),
  coffeeMilkTea('Cà phê & Trà sữa'),
  snacksBanhMi('Ăn vặt & Bánh mì'),
  healthy('Healthy • Ít calo'),
  ecoGreen('Quán Xanh'),
  promo('Đang có Ưu đãi');

  final String label;
  const GrabFoodQuickFilter(this.label);
}

class GrabFoodCartEntry {
  final FoodMenuItemRecord item;
  final int quantity;

  const GrabFoodCartEntry({required this.item, required this.quantity});

  double get lineTotalVnd => item.priceVnd * quantity;

  GrabFoodCartEntry copyWith({FoodMenuItemRecord? item, int? quantity}) {
    return GrabFoodCartEntry(
      item: item ?? this.item,
      quantity: quantity ?? this.quantity,
    );
  }
}

class GrabFoodVenueRecommendation {
  final String venueKey;
  final String merchantId;
  final String storeName;
  final String storeAddress;
  final GeoPoint storeLocation;
  final bool isPartnerMerchant;
  final double rating;
  final int roadDistanceMeters;
  final double roadDistanceKm;
  final int prepMinutes;
  final int estimatedTotalEtaMinutes;
  final double estimatedDeliveryFeeVnd;
  final bool hasEcoPackaging;
  final bool hasPromo;
  final bool servesCurrentMealSlot;
  final bool isFavoriteVenue;
  final double recommendationScore;
  final List<FoodMenuItemRecord> matchedItems;
  final List<FoodMenuItemRecord> allAvailableItems;

  const GrabFoodVenueRecommendation({
    required this.venueKey,
    required this.merchantId,
    required this.storeName,
    required this.storeAddress,
    required this.storeLocation,
    required this.isPartnerMerchant,
    required this.rating,
    required this.roadDistanceMeters,
    required this.roadDistanceKm,
    required this.prepMinutes,
    required this.estimatedTotalEtaMinutes,
    required this.estimatedDeliveryFeeVnd,
    required this.hasEcoPackaging,
    required this.hasPromo,
    required this.servesCurrentMealSlot,
    required this.isFavoriteVenue,
    required this.recommendationScore,
    required this.matchedItems,
    required this.allAvailableItems,
  });
}

class GrabFoodReorderSuggestion {
  final String storeName;
  final String storeAddress;
  final GeoPoint storeLocation;
  final String dishSummary;
  final double lastFoodSubtotalVnd;
  final int orderCount;
  final List<FoodMenuItemRecord> matchedCatalogItems;

  const GrabFoodReorderSuggestion({
    required this.storeName,
    required this.storeAddress,
    required this.storeLocation,
    required this.dishSummary,
    required this.lastFoodSubtotalVnd,
    required this.orderCount,
    required this.matchedCatalogItems,
  });
}

/// Động cơ Gợi ý Ăn uống Thông minh lấy cảm hứng từ GrabFood
/// Kết hợp Khoảng cách GPS thực tế + Khung giờ bữa ăn + Đánh giá sao + Thực đơn Đối tác B2B
class GrabFoodRecommendationEngine {
  const GrabFoodRecommendationEngine._();

  static const List<String> supportedCategories = <String>[
    'Cơm • Bún • Phở',
    'Cà phê & Trà sữa',
    'Ăn vặt & Bánh mì',
    'Healthy • Ít calo',
  ];

  /// Danh mục ẩm thực tuyển chọn tại Việt Nam (luôn sẵn sàng kể cả khi DB mới cài đặt sạch)
  static final List<FoodMenuItemRecord> curatedMenuCatalog =
      List<FoodMenuItemRecord>.unmodifiable([
        FoodMenuItemRecord(
          id: 'GF-CUR-01',
          merchantId: 'CURATED-PHO-HOA',
          storeName: 'Phở Hòa Pasteur',
          storeAddress: '260C Pasteur, Phường Võ Thị Sáu, Quận 3, TP. HCM',
          storeLocation: const GeoPoint(latitude: 10.7868, longitude: 106.6881),
          name: 'Phở Tái Nạm Gầu Đặc Biệt',
          description: 'Nước dùng ninh xương bò 12 giờ, bánh phở tươi truyền thống',
          category: 'Cơm • Bún • Phở',
          priceVnd: 68000,
          prepMinutes: 12,
          mealSlots: const ['breakfast', 'lunch', 'dinner', 'lateNight'],
          isEcoPackaging: true,
          isColdItem: false,
          hasPromoBadge: true,
          rating: 4.9,
          soldCount: 1420,
          isPartnerMerchant: false,
        ),
        FoodMenuItemRecord(
          id: 'GF-CUR-02',
          merchantId: 'CURATED-PHO-HOA',
          storeName: 'Phở Hòa Pasteur',
          storeAddress: '260C Pasteur, Phường Võ Thị Sáu, Quận 3, TP. HCM',
          storeLocation: const GeoPoint(latitude: 10.7868, longitude: 106.6881),
          name: 'Quẩy Giòn & Trà Đá Thảo Mộc',
          description: 'Combo quẩy nóng giòn kèm ly trà sâm dứa mát lạnh',
          category: 'Cơm • Bún • Phở',
          priceVnd: 15000,
          prepMinutes: 5,
          mealSlots: const ['breakfast', 'lunch', 'dinner', 'lateNight'],
          isEcoPackaging: true,
          isColdItem: true,
          hasPromoBadge: false,
          rating: 4.8,
          soldCount: 890,
          isPartnerMerchant: false,
        ),
        FoodMenuItemRecord(
          id: 'GF-CUR-03',
          merchantId: 'CURATED-COM-TAM-PLT',
          storeName: 'Cơm Tấm Phúc Lộc Thọ',
          storeAddress:
              '236 Nguyễn Thị Minh Khai, Phường Võ Thị Sáu, Quận 3, TP. HCM',
          storeLocation: const GeoPoint(latitude: 10.7778, longitude: 106.6898),
          name: 'Cơm Tấm Sườn Bì Chả Trứng Ốp La',
          description: 'Sườn nướng than hoa mật ong kèm bì thính, chả hấp trứng',
          category: 'Cơm • Bún • Phở',
          priceVnd: 59000,
          prepMinutes: 12,
          mealSlots: const ['lunch', 'dinner', 'lateNight'],
          isEcoPackaging: true,
          isColdItem: false,
          hasPromoBadge: true,
          rating: 4.8,
          soldCount: 2150,
          isPartnerMerchant: false,
        ),
        FoodMenuItemRecord(
          id: 'GF-CUR-04',
          merchantId: 'CURATED-COM-TAM-PLT',
          storeName: 'Cơm Tấm Phúc Lộc Thọ',
          storeAddress:
              '236 Nguyễn Thị Minh Khai, Phường Võ Thị Sáu, Quận 3, TP. HCM',
          storeLocation: const GeoPoint(latitude: 10.7778, longitude: 106.6898),
          name: 'Canh Khổ Qua Nhồi Thịt Nóng',
          description: 'Khổ qua tươi hầm thịt bằm mộc nhĩ thanh mát',
          category: 'Cơm • Bún • Phở',
          priceVnd: 22000,
          prepMinutes: 8,
          mealSlots: const ['lunch', 'dinner', 'lateNight'],
          isEcoPackaging: true,
          isColdItem: false,
          hasPromoBadge: false,
          rating: 4.8,
          soldCount: 930,
          isPartnerMerchant: false,
        ),
        FoodMenuItemRecord(
          id: 'GF-CUR-05',
          merchantId: 'CURATED-BANH-MI-HH',
          storeName: 'Bánh Mì Huỳnh Hoa',
          storeAddress: '26 Lê Thị Riêng, Phường Bến Thành, Quận 1, TP. HCM',
          storeLocation: const GeoPoint(latitude: 10.7712, longitude: 106.6913),
          name: 'Bánh Mì Đặc Biệt Full Chả Pate Bơ',
          description: 'Ổ bánh mì giòn rụm kèm 5 lớp thịt nguội, chả lụa, pate tươi',
          category: 'Ăn vặt & Bánh mì',
          priceVnd: 68000,
          prepMinutes: 8,
          mealSlots: const ['breakfast', 'afternoonTea', 'dinner', 'lateNight'],
          isEcoPackaging: true,
          isColdItem: false,
          hasPromoBadge: false,
          rating: 4.9,
          soldCount: 3180,
          isPartnerMerchant: false,
        ),
        FoodMenuItemRecord(
          id: 'GF-CUR-06',
          merchantId: 'CURATED-BANH-MI-HH',
          storeName: 'Bánh Mì Huỳnh Hoa',
          storeAddress: '26 Lê Thị Riêng, Phường Bến Thành, Quận 1, TP. HCM',
          storeLocation: const GeoPoint(latitude: 10.7712, longitude: 106.6913),
          name: 'Sữa Đậu Nành Lạnh Nguyên Chất',
          description: 'Đậu nành nấu mới mỗi ngày, ướp lạnh giữ nguyên vị béo thơm',
          category: 'Ăn vặt & Bánh mì',
          priceVnd: 18000,
          prepMinutes: 5,
          mealSlots: const ['breakfast', 'afternoonTea', 'dinner', 'lateNight'],
          isEcoPackaging: true,
          isColdItem: true,
          hasPromoBadge: true,
          rating: 4.8,
          soldCount: 1120,
          isPartnerMerchant: false,
        ),
        FoodMenuItemRecord(
          id: 'GF-CUR-07',
          merchantId: 'CURATED-PHE-LA-HTM',
          storeName: 'Phê La - Hồ Tùng Mậu',
          storeAddress: '115 Hồ Tùng Mậu, Phường Bến Nghé, Quận 1, TP. HCM',
          storeLocation: const GeoPoint(latitude: 10.7730, longitude: 106.7032),
          name: 'Ô Long Sữa Phê La Trân Châu Ô Long',
          description: 'Trà Ô Long đặc sản Đà Lạt pha thủ công kèm trân châu dẻo',
          category: 'Cà phê & Trà sữa',
          priceVnd: 55000,
          prepMinutes: 8,
          mealSlots: const ['breakfast', 'lunch', 'afternoonTea', 'dinner'],
          isEcoPackaging: true,
          isColdItem: true,
          hasPromoBadge: true,
          rating: 4.9,
          soldCount: 2890,
          isPartnerMerchant: false,
        ),
        FoodMenuItemRecord(
          id: 'GF-CUR-08',
          merchantId: 'CURATED-PHE-LA-HTM',
          storeName: 'Phê La - Hồ Tùng Mậu',
          storeAddress: '115 Hồ Tùng Mậu, Phường Bến Nghé, Quận 1, TP. HCM',
          storeLocation: const GeoPoint(latitude: 10.7730, longitude: 106.7032),
          name: 'Cà Phê Phin Sữa Đá Đà Lạt',
          description: 'Hạt Robusta rang mộc đậm vị hậu ngọt, đóng ly chống tràn',
          category: 'Cà phê & Trà sữa',
          priceVnd: 45000,
          prepMinutes: 7,
          mealSlots: const ['breakfast', 'lunch', 'afternoonTea'],
          isEcoPackaging: true,
          isColdItem: true,
          hasPromoBadge: false,
          rating: 4.9,
          soldCount: 1740,
          isPartnerMerchant: false,
        ),
        FoodMenuItemRecord(
          id: 'GF-CUR-09',
          merchantId: 'CURATED-POKE-SAIGON',
          storeName: 'Poke Saigon - Lý Tự Trọng',
          storeAddress: '42 Lý Tự Trọng, Phường Bến Nghé, Quận 1, TP. HCM',
          storeLocation: const GeoPoint(latitude: 10.7782, longitude: 106.7014),
          name: 'Poke Cá Hồi Bơ Gạo Lứt Ít Calo (420 kcal)',
          description: 'Cá hồi Na Uy tươi, bơ sáp, đậu nành Nhật, sốt mè rang',
          category: 'Healthy • Ít calo',
          priceVnd: 95000,
          prepMinutes: 10,
          mealSlots: const ['breakfast', 'lunch', 'dinner'],
          isEcoPackaging: true,
          isColdItem: true,
          hasPromoBadge: true,
          rating: 4.8,
          soldCount: 980,
          isPartnerMerchant: false,
        ),
        FoodMenuItemRecord(
          id: 'GF-CUR-10',
          merchantId: 'CURATED-POKE-SAIGON',
          storeName: 'Poke Saigon - Lý Tự Trọng',
          storeAddress: '42 Lý Tự Trọng, Phường Bến Nghé, Quận 1, TP. HCM',
          storeLocation: const GeoPoint(latitude: 10.7782, longitude: 106.7014),
          name: 'Nước Ép Cần Tây Táo Xanh Detox Lạnh',
          description: 'Ép lạnh nguyên chất không đường, giữ trọn vitamin',
          category: 'Healthy • Ít calo',
          priceVnd: 48000,
          prepMinutes: 6,
          mealSlots: const ['breakfast', 'lunch', 'afternoonTea', 'dinner'],
          isEcoPackaging: true,
          isColdItem: true,
          hasPromoBadge: false,
          rating: 4.8,
          soldCount: 640,
          isPartnerMerchant: false,
        ),
        FoodMenuItemRecord(
          id: 'GF-CUR-11',
          merchantId: 'CURATED-CHAO-DEM-Q1',
          storeName: 'Cháo Sườn & Dimsum Đêm Chợ Cũ',
          storeAddress: '84 Tôn Thất Đạm, Phường Bến Nghé, Quận 1, TP. HCM',
          storeLocation: const GeoPoint(latitude: 10.7718, longitude: 106.7038),
          name: 'Cháo Sườn Sụn Trứng Bắc Thảo Nóng',
          description: 'Cháo bột gạo xay mịn nấu sườn sụn non và trứng bắc thảo',
          category: 'Ăn vặt & Bánh mì',
          priceVnd: 49000,
          prepMinutes: 10,
          mealSlots: const ['afternoonTea', 'dinner', 'lateNight'],
          isEcoPackaging: false,
          isColdItem: false,
          hasPromoBadge: true,
          rating: 4.7,
          soldCount: 1260,
          isPartnerMerchant: false,
        ),
        FoodMenuItemRecord(
          id: 'GF-CUR-12',
          merchantId: 'CURATED-CHAO-DEM-Q1',
          storeName: 'Cháo Sườn & Dimsum Đêm Chợ Cũ',
          storeAddress: '84 Tôn Thất Đạm, Phường Bến Nghé, Quận 1, TP. HCM',
          storeLocation: const GeoPoint(latitude: 10.7718, longitude: 106.7038),
          name: 'Há Cảo Tôm Tươi Hấp Xửng (4 viên)',
          description: 'Vỏ mỏng trong suốt nhân tôm sú tươi hấp nóng',
          category: 'Ăn vặt & Bánh mì',
          priceVnd: 42000,
          prepMinutes: 12,
          mealSlots: const ['afternoonTea', 'dinner', 'lateNight'],
          isEcoPackaging: true,
          isColdItem: false,
          hasPromoBadge: false,
          rating: 4.7,
          soldCount: 810,
          isPartnerMerchant: false,
        ),
        FoodMenuItemRecord(
          id: 'GF-CUR-13',
          merchantId: 'CURATED-BUN-CHA-HL',
          storeName: 'Bún Chả Hương Liên',
          storeAddress: '24 Lê Văn Hưu, Quận Hai Bà Trưng, Hà Nội',
          storeLocation: const GeoPoint(latitude: 21.0181, longitude: 105.8535),
          name: 'Combo Bún Chả Hà Nội & Nem Hải Sản',
          description: 'Chả viên, chả miếng nướng than hoa kèm 1 nem cua bể giòn',
          category: 'Cơm • Bún • Phở',
          priceVnd: 65000,
          prepMinutes: 14,
          mealSlots: const ['lunch', 'dinner'],
          isEcoPackaging: true,
          isColdItem: false,
          hasPromoBadge: true,
          rating: 4.9,
          soldCount: 1950,
          isPartnerMerchant: false,
        ),
        FoodMenuItemRecord(
          id: 'GF-CUR-14',
          merchantId: 'CURATED-BUN-CHA-HL',
          storeName: 'Bún Chả Hương Liên',
          storeAddress: '24 Lê Văn Hưu, Quận Hai Bà Trưng, Hà Nội',
          storeLocation: const GeoPoint(latitude: 21.0181, longitude: 105.8535),
          name: 'Trà Quất Mật Ong Đá Mát Lạnh',
          description: 'Trà xanh nhài pha quất tươi và mật ong rừng giải nhiệt',
          category: 'Cơm • Bún • Phở',
          priceVnd: 20000,
          prepMinutes: 5,
          mealSlots: const ['lunch', 'afternoonTea', 'dinner'],
          isEcoPackaging: false,
          isColdItem: true,
          hasPromoBadge: false,
          rating: 4.8,
          soldCount: 740,
          isPartnerMerchant: false,
        ),
        FoodMenuItemRecord(
          id: 'GF-CUR-15',
          merchantId: 'CURATED-CAFE-GIANG',
          storeName: 'Cà Phê Giảng Phố Cổ',
          storeAddress: '39 Nguyễn Hữu Huân, Quận Hoàn Kiếm, Hà Nội',
          storeLocation: const GeoPoint(latitude: 21.0338, longitude: 105.8546),
          name: 'Cà Phê Trứng Truyền Thống Phố Cổ',
          description: 'Lớp kem trứng đánh bông mịn béo thơm trên nền cà phê nóng',
          category: 'Cà phê & Trà sữa',
          priceVnd: 39000,
          prepMinutes: 8,
          mealSlots: const ['breakfast', 'afternoonTea', 'lateNight'],
          isEcoPackaging: true,
          isColdItem: false,
          hasPromoBadge: false,
          rating: 4.9,
          soldCount: 2340,
          isPartnerMerchant: false,
        ),
        FoodMenuItemRecord(
          id: 'GF-CUR-16',
          merchantId: 'CURATED-CAFE-GIANG',
          storeName: 'Cà Phê Giảng Phố Cổ',
          storeAddress: '39 Nguyễn Hữu Huân, Quận Hoàn Kiếm, Hà Nội',
          storeLocation: const GeoPoint(latitude: 21.0338, longitude: 105.8546),
          name: 'Cacao Đá Kem Trứng Béo Ngậy',
          description: 'Cacao nguyên chất kết hợp kem trứng mát lạnh',
          category: 'Cà phê & Trà sữa',
          priceVnd: 42000,
          prepMinutes: 8,
          mealSlots: const ['breakfast', 'afternoonTea', 'dinner', 'lateNight'],
          isEcoPackaging: false,
          isColdItem: true,
          hasPromoBadge: true,
          rating: 4.8,
          soldCount: 1190,
          isPartnerMerchant: false,
        ),
      ]);

  static String foldVietnamese(String input) {
    const groups = <String, String>{
      'a': 'àáạảãâầấậẩẫăằắặẳẵ',
      'e': 'èéẹẻẽêềếệểễ',
      'i': 'ìíịỉĩ',
      'o': 'òóọỏõôồốộổỗơờớợởỡ',
      'u': 'ùúụủũưừứựửữ',
      'y': 'ỳýỵỷỹ',
      'd': 'đ',
    };
    var out = input.trim().toLowerCase();
    groups.forEach((ascii, chars) {
      for (var i = 0; i < chars.length; i++) {
        out = out.replaceAll(chars[i], ascii);
      }
    });
    return out;
  }

  static String? extractGrabFoodStoreNameFromDescription(
    String packageDescription,
  ) {
    final match = RegExp(
      r'\[GrabFood\s*•\s*([^\]]+)\]',
      caseSensitive: false,
    ).firstMatch(packageDescription);
    final raw = match?.group(1)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  static List<GrabFoodReorderSuggestion> extractReorderFavorites({
    required List<ActiveOrderRecord> customerOrders,
    required List<FoodMenuItemRecord> partnerMenuItems,
    int maxItems = 4,
  }) {
    final allCatalog = <FoodMenuItemRecord>[
      ...partnerMenuItems.where((m) => m.isAvailable),
      ...curatedMenuCatalog.where((m) => m.isAvailable),
    ];
    final grouped = <String, _ReorderAccumulator>{};
    for (final ord in customerOrders) {
      final desc = ord.packageDescription.trim();
      final taggedStore = extractGrabFoodStoreNameFromDescription(desc);
      FoodMenuItemRecord? addrMatch;
      if (taggedStore == null) {
        final foldedPickup = foldVietnamese(ord.pickupAddress);
        addrMatch = allCatalog.where((item) {
          return foldVietnamese(item.storeAddress) == foldedPickup ||
              foldedPickup.contains(foldVietnamese(item.storeName));
        }).firstOrNull;
      }
      final isFoodOrder =
          taggedStore != null ||
          desc.toLowerCase().contains('grabfood') ||
          desc.toLowerCase().contains('thực phẩm') ||
          addrMatch != null;
      if (!isFoodOrder) continue;

      final storeName = taggedStore ?? addrMatch?.storeName ?? ord.pickupAddress;
      final key = foldVietnamese(storeName);
      if (key.isEmpty) continue;

      final cleanSummary = desc
          .replaceFirst(RegExp(r'^\[GrabFood\s*•\s*[^\]]+\]\s*'), '')
          .replaceFirst(RegExp(r'\s*\[GIỮ LẠNH[^\]]*\]', caseSensitive: false), '')
          .trim();

      final existing = grouped[key];
      if (existing == null) {
        final storeItems = allCatalog
            .where((m) => foldVietnamese(m.storeName) == key)
            .toList();
        final matchedDishes = storeItems.where((m) {
          return foldVietnamese(desc).contains(foldVietnamese(m.name));
        }).toList();
        grouped[key] = _ReorderAccumulator(
          storeName: storeName,
          storeAddress: ord.pickupAddress,
          storeLocation: ord.pickupLocation,
          dishSummary: cleanSummary.isNotEmpty ? cleanSummary : desc,
          lastFoodSubtotalVnd: ord.codAmount > 0 ? ord.codAmount : ord.totalAmount,
          orderCount: 1,
          matchedCatalogItems: matchedDishes.isNotEmpty
              ? matchedDishes
              : storeItems.take(1).toList(),
        );
      } else {
        existing.orderCount += 1;
      }
    }

    final list = grouped.values
        .map(
          (acc) => GrabFoodReorderSuggestion(
            storeName: acc.storeName,
            storeAddress: acc.storeAddress,
            storeLocation: acc.storeLocation,
            dishSummary: acc.dishSummary,
            lastFoodSubtotalVnd: acc.lastFoodSubtotalVnd,
            orderCount: acc.orderCount,
            matchedCatalogItems: acc.matchedCatalogItems,
          ),
        )
        .toList()
      ..sort((a, b) => b.orderCount.compareTo(a.orderCount));
    return list.take(maxItems).toList();
  }

  static bool _matchesQuickFilter(
    FoodMenuItemRecord item,
    GrabFoodQuickFilter filter,
  ) {
    switch (filter) {
      case GrabFoodQuickFilter.all:
      case GrabFoodQuickFilter.nearMe:
        return true;
      case GrabFoodQuickFilter.riceNoodlePho:
        return item.category == 'Cơm • Bún • Phở';
      case GrabFoodQuickFilter.coffeeMilkTea:
        return item.category == 'Cà phê & Trà sữa';
      case GrabFoodQuickFilter.snacksBanhMi:
        return item.category == 'Ăn vặt & Bánh mì';
      case GrabFoodQuickFilter.healthy:
        return item.category == 'Healthy • Ít calo';
      case GrabFoodQuickFilter.ecoGreen:
        return item.isEcoPackaging;
      case GrabFoodQuickFilter.promo:
        return item.hasPromoBadge;
    }
  }

  static List<GrabFoodVenueRecommendation> rankRecommendedVenues({
    required GeoPoint customerLocation,
    required List<FoodMenuItemRecord> partnerMenuItems,
    List<ActiveOrderRecord> customerOrders = const <ActiveOrderRecord>[],
    MealTimeSlot selectedSlot = MealTimeSlot.auto,
    GrabFoodQuickFilter quickFilter = GrabFoodQuickFilter.all,
    String searchQuery = '',
    DeliveryServiceType serviceType = DeliveryServiceType.express30m,
    double baseFareScale = 1.0,
    double pricePerKmScale = 1.0,
    bool isPeakHour = false,
    DateTime? referenceTime,
  }) {
    final activeAvailableItems = <FoodMenuItemRecord>[
      ...partnerMenuItems.where((m) => m.isAvailable),
      ...curatedMenuCatalog.where((m) => m.isAvailable),
    ];
    final groupedByVenue = <String, List<FoodMenuItemRecord>>{};
    for (final item in activeAvailableItems) {
      final key = item.merchantId.trim().isNotEmpty
          ? item.merchantId.trim()
          : foldVietnamese(item.storeName);
      (groupedByVenue[key] ??= <FoodMenuItemRecord>[]).add(item);
    }

    final effectiveSlot = selectedSlot.effectiveSlotForNow(referenceTime);
    final strictMealSlot = selectedSlot != MealTimeSlot.auto;
    final foldedQuery = foldVietnamese(searchQuery);
    final queryTokens = foldedQuery
        .split(RegExp(r'[\s,]+'))
        .where((t) => t.isNotEmpty)
        .toList();

    final favoriteVenueKeys = extractReorderFavorites(
      customerOrders: customerOrders,
      partnerMenuItems: partnerMenuItems,
      maxItems: 20,
    ).map((fav) => foldVietnamese(fav.storeName)).toSet();

    final results = <GrabFoodVenueRecommendation>[];

    for (final entry in groupedByVenue.entries) {
      final venueItems = entry.value;
      if (venueItems.isEmpty) continue;
      final head = venueItems.first;
      final rawAirMeters = GeoMath.distanceMeters(
        customerLocation,
        head.storeLocation,
      );
      final roadMeters = (rawAirMeters * 1.28).round().clamp(400, 180000);
      final roadKm = roadMeters / 1000.0;

      if (quickFilter == GrabFoodQuickFilter.nearMe && roadKm > 3.0) {
        continue;
      }

      final storeHaystack = foldVietnamese(
        '${head.storeName} ${head.storeAddress}',
      );
      final storeMatchesQuery =
          queryTokens.isEmpty || queryTokens.every(storeHaystack.contains);

      final matched = venueItems.where((item) {
        if (strictMealSlot && !item.mealSlots.contains(effectiveSlot.dbCode)) {
          return false;
        }
        if (!_matchesQuickFilter(item, quickFilter)) {
          return false;
        }
        if (queryTokens.isEmpty || storeMatchesQuery) {
          return true;
        }
        final itemHaystack = foldVietnamese(
          '${item.name} ${item.description} ${item.category} ${item.storeName}',
        );
        return queryTokens.every(itemHaystack.contains);
      }).toList();

      if (matched.isEmpty) continue;

      matched.sort((a, b) {
        final aSlot = a.mealSlots.contains(effectiveSlot.dbCode) ? 1 : 0;
        final bSlot = b.mealSlots.contains(effectiveSlot.dbCode) ? 1 : 0;
        if (aSlot != bSlot) return bSlot.compareTo(aSlot);
        return b.soldCount.compareTo(a.soldCount);
      });

      final avgRating =
          venueItems.fold<double>(0.0, (s, e) => s + e.rating) /
          venueItems.length;
      final minPrep = matched
          .map((e) => e.prepMinutes)
          .reduce((a, b) => a < b ? a : b);
      final travelMinutes = (roadKm * 3.2).round().clamp(4, 120);
      final totalEta = minPrep + travelMinutes;

      final estPricing = PricingEstimate.calculate(
        serviceType: serviceType,
        distanceMeters: roadMeters,
        durationSeconds: travelMinutes * 60,
        isPeakHour: isPeakHour,
        baseFareScale: baseFareScale,
        pricePerKmScale: pricePerKmScale,
      );

      final isPartner = venueItems.any((e) => e.isPartnerMerchant);
      final hasEco = matched.any((e) => e.isEcoPackaging);
      final hasPromo = matched.any((e) => e.hasPromoBadge);
      final servesCurrentSlot = matched.any(
        (e) => e.mealSlots.contains(effectiveSlot.dbCode),
      );
      final isFavorite = favoriteVenueKeys.contains(
        foldVietnamese(head.storeName),
      );

      final proximityScore = (48.0 - (roadKm * 4.2)).clamp(-45.0, 48.0);
      final ratingScore = avgRating * 8.0;
      final etaScore = (24.0 - (totalEta * 0.45)).clamp(0.0, 24.0);
      final slotBoost = servesCurrentSlot ? 22.0 : 0.0;
      final partnerBoost = isPartner ? 14.0 : 0.0;
      final favoriteBoost = isFavorite ? 12.0 : 0.0;
      final badgeBoost = (hasPromo ? 4.0 : 0.0) + (hasEco ? 3.0 : 0.0);

      final totalScore =
          proximityScore +
          ratingScore +
          etaScore +
          slotBoost +
          partnerBoost +
          favoriteBoost +
          badgeBoost;

      results.add(
        GrabFoodVenueRecommendation(
          venueKey: entry.key,
          merchantId: head.merchantId,
          storeName: head.storeName,
          storeAddress: head.storeAddress,
          storeLocation: head.storeLocation,
          isPartnerMerchant: isPartner,
          rating: avgRating,
          roadDistanceMeters: roadMeters,
          roadDistanceKm: roadKm,
          prepMinutes: minPrep,
          estimatedTotalEtaMinutes: totalEta,
          estimatedDeliveryFeeVnd: estPricing.totalAmount,
          hasEcoPackaging: hasEco,
          hasPromo: hasPromo,
          servesCurrentMealSlot: servesCurrentSlot,
          isFavoriteVenue: isFavorite,
          recommendationScore: totalScore,
          matchedItems: matched,
          allAvailableItems: venueItems,
        ),
      );
    }

    results.sort((a, b) {
      final scoreCmp = b.recommendationScore.compareTo(a.recommendationScore);
      if (scoreCmp != 0) return scoreCmp;
      return a.roadDistanceMeters.compareTo(b.roadDistanceMeters);
    });
    return results;
  }
}

class _ReorderAccumulator {
  final String storeName;
  final String storeAddress;
  final GeoPoint storeLocation;
  final String dishSummary;
  final double lastFoodSubtotalVnd;
  int orderCount;
  final List<FoodMenuItemRecord> matchedCatalogItems;

  _ReorderAccumulator({
    required this.storeName,
    required this.storeAddress,
    required this.storeLocation,
    required this.dishSummary,
    required this.lastFoodSubtotalVnd,
    required this.orderCount,
    required this.matchedCatalogItems,
  });
}
