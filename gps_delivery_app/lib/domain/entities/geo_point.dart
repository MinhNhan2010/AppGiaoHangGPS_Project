import 'dart:typed_data';
import 'package:equatable/equatable.dart';

class GeoPoint extends Equatable {
  final double latitude;
  final double longitude;

  const GeoPoint({
    required this.latitude,
    required this.longitude,
  });

  /// Chuyển đổi sang định dạng PostGIS EWKT: SRID=4326;POINT(lng lat)
  String toPostgisEwkt() => 'SRID=4326;POINT($longitude $latitude)';

  Map<String, dynamic> toGeoJson() => {
        'type': 'Point',
        'coordinates': [longitude, latitude],
      };

  static bool _isValidWgs84(double lat, double lng) =>
      lat.isFinite && lng.isFinite && lat.abs() <= 90.0 && lng.abs() <= 180.0;

  factory GeoPoint.fromGeoJson(Map<String, dynamic> json) {
    final coords = json['coordinates'];
    if (coords is List && coords.length >= 2) {
      final rawLng = coords[0];
      final rawLat = coords[1];
      final lng = rawLng is num
          ? rawLng.toDouble()
          : double.tryParse('$rawLng');
      final lat = rawLat is num
          ? rawLat.toDouble()
          : double.tryParse('$rawLat');
      if (lat != null && lng != null && _isValidWgs84(lat, lng)) {
        return GeoPoint(longitude: lng, latitude: lat);
      }
      throw FormatException('Tọa độ GeoJSON không hợp lệ: $json');
    }
    final rawLat = json['latitude'] ?? json['lat'];
    final rawLng = json['longitude'] ?? json['lng'] ?? json['lon'];
    final lat = rawLat is num
        ? rawLat.toDouble()
        : (rawLat != null ? double.tryParse('$rawLat') : null);
    final lng = rawLng is num
        ? rawLng.toDouble()
        : (rawLng != null ? double.tryParse('$rawLng') : null);
    if (lat != null && lng != null && _isValidWgs84(lat, lng)) {
      return GeoPoint(latitude: lat, longitude: lng);
    }
    throw FormatException('Không thể giải mã tọa độ GeoJSON: $json');
  }

  static GeoPoint? tryParsePostgis(Object? raw) {
    if (raw == null) return null;
    if (raw is GeoPoint) {
      return _isValidWgs84(raw.latitude, raw.longitude) ? raw : null;
    }
    if (raw is Map<String, dynamic>) {
      try {
        return GeoPoint.fromGeoJson(raw);
      } catch (_) {
        return null;
      }
    }
    if (raw is Map) {
      try {
        return GeoPoint.fromGeoJson(Map<String, dynamic>.from(raw));
      } catch (_) {
        return null;
      }
    }
    if (raw is String) {
      final trimmed = raw.trim();
      final pointMatch = RegExp(
        r'POINT(?:\s*[ZM]{1,2})?\s*\(\s*([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)\s+([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (pointMatch != null) {
        final lng = double.tryParse(pointMatch.group(1)!);
        final lat = double.tryParse(pointMatch.group(2)!);
        if (lat != null && lng != null && _isValidWgs84(lat, lng)) {
          return GeoPoint(latitude: lat, longitude: lng);
        }
      }
      final hexClean = trimmed.startsWith('0x') || trimmed.startsWith('0X')
          ? trimmed.substring(2)
          : (trimmed.startsWith(r'\x') ? trimmed.substring(2) : trimmed);
      if (hexClean.length >= 42 &&
          hexClean.length.isEven &&
          RegExp(r'^[0-9a-fA-F]+$').hasMatch(hexClean)) {
        final byteCount = hexClean.length ~/ 2;
        final bytes = Uint8List(byteCount);
        for (var i = 0; i < byteCount; i++) {
          bytes[i] = int.parse(hexClean.substring(i * 2, i * 2 + 2), radix: 16);
        }
        final bd = ByteData.sublistView(bytes);
        final endian = bytes[0] == 1 ? Endian.little : Endian.big;
        final geomType = bd.getUint32(1, endian);
        final baseType = geomType & 0xFF;
        final hasSrid = (geomType & 0x20000000) != 0;
        final coordOffset = hasSrid ? 9 : 5;
        if (baseType == 1 && byteCount >= coordOffset + 16) {
          final lng = bd.getFloat64(coordOffset, endian);
          final lat = bd.getFloat64(coordOffset + 8, endian);
          if (_isValidWgs84(lat, lng)) {
            return GeoPoint(latitude: lat, longitude: lng);
          }
        }
      }
    }
    return null;
  }

  @override
  List<Object?> get props => [latitude, longitude];
}
