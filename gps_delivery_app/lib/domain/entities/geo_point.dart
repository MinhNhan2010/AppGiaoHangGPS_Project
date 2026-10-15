import 'package:equatable/equatable.dart';

class GeoPoint extends Equatable {
  final double latitude;
  final double longitude;

  const GeoPoint({
    required this.latitude,
    required this.longitude,
  });

  /// Converts to PostGIS EWKT format: SRID=4326;POINT(lng lat)
  String toPostgisEwkt() => 'SRID=4326;POINT($longitude $latitude)';

  Map<String, dynamic> toGeoJson() => {
        'type': 'Point',
        'coordinates': [longitude, latitude],
      };

  factory GeoPoint.fromGeoJson(Map<String, dynamic> json) {
    final coords = json['coordinates'] as List<dynamic>;
    return GeoPoint(
      longitude: (coords[0] as num).toDouble(),
      latitude: (coords[1] as num).toDouble(),
    );
  }

  @override
  List<Object?> get props => [latitude, longitude];
}
