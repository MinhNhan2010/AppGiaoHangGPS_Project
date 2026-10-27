import 'dart:math' as math;
import '../../domain/entities/geo_point.dart';

class GeoMath {
  const GeoMath._();

  static const double _earthRadiusMeters = 6371000.0;

  static double distanceMeters(GeoPoint a, GeoPoint b) {
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);

    final sinDLat = math.sin(dLat / 2);
    final sinDLon = math.sin(dLon / 2);
    final h = (sinDLat * sinDLat +
            math.cos(lat1) * math.cos(lat2) * sinDLon * sinDLon)
        .clamp(0.0, 1.0);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1.0 - h));
    return _earthRadiusMeters * c;
  }

  static double bearingDegrees(GeoPoint from, GeoPoint to) {
    if (from.latitude == to.latitude && from.longitude == to.longitude) {
      return 0.0;
    }
    final lat1 = _degToRad(from.latitude);
    final lat2 = _degToRad(to.latitude);
    final dLon = _degToRad(to.longitude - from.longitude);

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = _radToDeg(math.atan2(y, x));
    return (brng + 360.0) % 360.0;
  }

  /// Thuật toán Ray-Casting kiểm tra điểm nằm trong đa giác
  static bool isPointInPolygon(GeoPoint point, List<GeoPoint> polygon) {
    if (polygon.length < 3 ||
        !point.latitude.isFinite ||
        !point.longitude.isFinite) {
      return false;
    }
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;
      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;
      if (!xi.isFinite || !yi.isFinite || !xj.isFinite || !yj.isFinite) {
        continue;
      }

      final intersect = ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude <
              (xj - xi) *
                      (point.latitude - yi) /
                      ((yj - yi) == 0 ? 1e-12 : (yj - yi)) +
                  xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
  static double _radToDeg(double rad) => rad * (180.0 / math.pi);
}
