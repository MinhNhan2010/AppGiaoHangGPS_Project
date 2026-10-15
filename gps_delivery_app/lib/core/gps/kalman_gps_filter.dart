import '../../domain/entities/geo_point.dart';

class KalmanGpsFilter {
  final double processNoiseMetersPerSec;
  double _variance = -1.0;
  double _lat = 0.0;
  double _lng = 0.0;
  int _timestampMs = 0;

  KalmanGpsFilter({this.processNoiseMetersPerSec = 3.0});

  GeoPoint filter({
    required GeoPoint rawPoint,
    required double accuracyMeters,
    required int timestampMs,
  }) {
    final effectiveAccuracy = accuracyMeters < 1.0 ? 1.0 : accuracyMeters;

    if (_variance < 0.0) {
      _timestampMs = timestampMs;
      _lat = rawPoint.latitude;
      _lng = rawPoint.longitude;
      _variance = effectiveAccuracy * effectiveAccuracy;
      return rawPoint;
    }

    final timeDeltaMs = timestampMs - _timestampMs;
    if (timeDeltaMs > 0) {
      _variance += (timeDeltaMs / 1000.0) *
          processNoiseMetersPerSec *
          processNoiseMetersPerSec;
      _timestampMs = timestampMs;
    }

    final kalmanGain =
        _variance / (_variance + effectiveAccuracy * effectiveAccuracy);
    _lat += kalmanGain * (rawPoint.latitude - _lat);
    _lng += kalmanGain * (rawPoint.longitude - _lng);
    _variance = (1.0 - kalmanGain) * _variance;

    return GeoPoint(latitude: _lat, longitude: _lng);
  }

  void reset() {
    _variance = -1.0;
  }
}
