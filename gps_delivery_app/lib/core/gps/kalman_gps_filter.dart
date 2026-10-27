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
    if (!rawPoint.latitude.isFinite || !rawPoint.longitude.isFinite) {
      if (_variance >= 0.0 && _lat.isFinite && _lng.isFinite) {
        return GeoPoint(latitude: _lat, longitude: _lng);
      }
      throw ArgumentError.value(
        rawPoint,
        'rawPoint',
        'Invalid non-finite GeoPoint',
      );
    }

    final effectiveAccuracy = (!accuracyMeters.isFinite || accuracyMeters < 1.0)
        ? 1.0
        : accuracyMeters.clamp(1.0, 5000.0);

    if (_variance < 0.0 ||
        !_variance.isFinite ||
        !_lat.isFinite ||
        !_lng.isFinite) {
      _timestampMs = timestampMs;
      _lat = rawPoint.latitude;
      _lng = rawPoint.longitude;
      _variance = effectiveAccuracy * effectiveAccuracy;
      return rawPoint;
    }

    final timeDeltaMs = timestampMs - _timestampMs;
    if (timeDeltaMs > 60000) {
      _timestampMs = timestampMs;
      _lat = rawPoint.latitude;
      _lng = rawPoint.longitude;
      _variance = effectiveAccuracy * effectiveAccuracy;
      return rawPoint;
    }
    if (timeDeltaMs > 0) {
      _variance += (timeDeltaMs / 1000.0) *
          processNoiseMetersPerSec *
          processNoiseMetersPerSec;
      _timestampMs = timestampMs;
    } else if (timeDeltaMs < 0) {
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
