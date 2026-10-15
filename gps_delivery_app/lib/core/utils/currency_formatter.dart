import 'package:intl/intl.dart';

class CurrencyFormatter {
  const CurrencyFormatter._();

  static final NumberFormat _vndFormat = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: '₫',
    decimalDigits: 0,
  );

  static String formatVnd(num amount) => _vndFormat.format(amount);

  static String formatDistanceKm(int distanceMeters) {
    final km = distanceMeters / 1000.0;
    return '${km.toStringAsFixed(1)} km';
  }

  static String formatDurationMinutes(int durationSeconds) {
    final minutes = (durationSeconds / 60).ceil();
    if (minutes < 60) return '$minutes phút';
    final hours = minutes ~/ 60;
    final rem = minutes % 60;
    return rem == 0 ? '$hours giờ' : '$hours giờ $rem phút';
  }
}
