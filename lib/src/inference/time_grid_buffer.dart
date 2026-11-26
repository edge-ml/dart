import 'dart:math' as math;

import '../errors.dart';

/// Keep this many windows of sensor values.
const _storeFactor = 4;

/// Buffers sensor values for models with windows of a fixed duration (schema 2
/// manifests): every sensor keeps its own timestamps, and a window is the
/// sensors linearly interpolated onto an even grid, the way training builds it.
/// A port of the JavaScript library's TimeGridBuffer.
class TimeGridBuffer {
  /// Creates a buffer for [sensors] (in model input order) and windows of
  /// [samples] grid points over [windowMs].
  TimeGridBuffer(List<String> sensors, this.samples, this.windowMs) : sensors = List.unmodifiable(sensors) {
    reset();
  }

  /// Sensor names in model input order.
  final List<String> sensors;

  /// Grid points per window.
  final int samples;

  /// Window duration in ms.
  final double windowMs;

  late Map<String, (List<double>, List<double>)> _store;

  /// Drops all values.
  void reset() => _store = {for (final s in sensors) s: (<double>[], <double>[])};

  /// Adds one [value] of [sensor] at [time] (unix ms).
  void addDatapoint(String sensor, num value, num time) {
    if (value.isNaN) throw ArgumentError.value(value, 'value', 'is not a number');
    final series = _store[sensor];
    if (series == null) {
      throw ArgumentError.value(sensor, 'sensor', 'unknown; the model expects ${sensors.join(', ')}');
    }
    final (t, v) = series;
    final at = t.isEmpty || time >= t.last ? t.length : t.indexWhere((x) => x > time);
    t.insert(at, time.toDouble());
    v.insert(at, value.toDouble());
    final keepFrom = time - _storeFactor * windowMs;
    var drop = 0;
    while (drop < t.length - 2 && t[drop + 1] < keepFrom) {
      drop++;
    }
    if (drop > 0) {
      t.removeRange(0, drop);
      v.removeRange(0, drop);
    }
  }

  /// Unix ms up to which every sensor has values, or null.
  double? get endTime {
    if (sensors.isEmpty) return null;
    var end = double.infinity;
    for (final s in sensors) {
      final t = _store[s]!.$1;
      if (t.isEmpty) return null;
      end = math.min(end, t.last);
    }
    return end;
  }

  /// The window ending at [end] (default [endTime]): [samples] rows of one
  /// value per sensor.
  List<List<double>> window([double? end]) {
    final e = end ?? endTime;
    if (e == null) throw const PredictorNotReadyException('No sensor values yet');
    final start = e - windowMs;
    final step = windowMs / samples;
    final rows = [for (var k = 0; k < samples; k++) List<double>.filled(sensors.length, 0)];
    for (var c = 0; c < sensors.length; c++) {
      final (t, v) = _store[sensors[c]]!;
      // training only uses windows inside a sensor's data (1 ms tolerance)
      if (t.isEmpty || t.first > start + 1) {
        throw PredictorNotReadyException("Not enough values of '${sensors[c]}' (need ${windowMs.round()} ms)");
      }
      var j = 0;
      for (var k = 0; k < samples; k++) {
        final x = start + k * step;
        while (j < t.length - 2 && t[j + 1] <= x) {
          j++;
        }
        if (x <= t.first) {
          rows[k][c] = v.first;
        } else if (x >= t.last) {
          rows[k][c] = v.last;
        } else {
          final a = t[j + 1] == t[j] ? 0.0 : (x - t[j]) / (t[j + 1] - t[j]);
          rows[k][c] = v[j] * (1 - a) + v[j + 1] * a;
        }
      }
    }
    return rows;
  }
}
