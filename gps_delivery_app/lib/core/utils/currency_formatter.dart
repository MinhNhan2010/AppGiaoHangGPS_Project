import 'package:intl/intl.dart';

class CurrencyFormatter {
  const CurrencyFormatter._();

  static final NumberFormat _vndFormat = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: '₫',
    decimalDigits: 0,
  );

  static String formatVnd(num amount) {
    final safeAmount = (amount is double && !amount.isFinite) ? 0 : amount;
    return _vndFormat.format(safeAmount);
  }

  static String formatDistanceKm(int distanceMeters) {
    final safeMeters = distanceMeters < 0 ? 0 : distanceMeters;
    final km = safeMeters / 1000.0;
    return '${km.toStringAsFixed(1)} km';
  }

  static String formatDurationMinutes(int durationSeconds) {
    final safeSeconds = durationSeconds < 0 ? 0 : durationSeconds;
    final minutes = (safeSeconds / 60).ceil();
    if (minutes < 60) return '$minutes phút';
    final hours = minutes ~/ 60;
    final rem = minutes % 60;
    return rem == 0 ? '$hours giờ' : '$hours giờ $rem phút';
  }
}
