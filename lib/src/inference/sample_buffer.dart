import '../errors.dart';

/// Keep up to this many windows of values per sensor.
const _storeFactor = 4;

/// Buffers sensor values and produces the latest window, aligned the way
/// edge-ml aligns datasets for training: rows are the union of all timestamps
/// (outer join), gaps are filled by linear interpolation over the rows, and
/// leading/trailing gaps take the nearest known value.
///
/// A port of the JavaScript library's SampleBuffer, so both produce the same
/// windows.
class SampleBuffer {
  /// Creates a buffer for [sensors] (in model input order) and windows of
  /// [windowSize] samples.
  SampleBuffer(List<String> sensors, this.windowSize)
    : sensors = List.unmodifiable(sensors),
      _index = {for (var i = 0; i < sensors.length; i++) sensors[i]: i} {
    reset();
  }

  /// Sensor names in model input order.
  final List<String> sensors;

  /// Samples per window.
  final int windowSize;

  final Map<String, int> _index;
  late List<List<(int, double)>> _store;

  /// Drops all buffered values.
  void reset() => _store = [for (final _ in sensors) <(int, double)>[]];

  /// Adds one [value] of [sensor] at [timestamp] (unix ms).
  void addDatapoint(String sensor, num value, int timestamp) {
    final i = _index[sensor];
    if (i == null) {
      throw ArgumentError.value(sensor, 'sensor', 'is not an input of this model (${sensors.join(', ')})');
    }
    if (value.isNaN || value.isInfinite) throw ArgumentError.value(value, 'value', 'must be a finite number');
    final series = _store[i]..add((timestamp, value.toDouble()));
    if (series.length > 2 * _storeFactor * windowSize) {
      _store[i] = series.sublist(series.length - _storeFactor * windowSize);
    }
  }

  /// Whether a full window can be built.
  bool get isReady {
    if (_store.any((s) => s.isEmpty)) return false;
    final times = <int>{};
    for (final s in _store) {
      for (final (t, _) in s) {
        times.add(t);
        if (times.length >= windowSize) return true;
      }
    }
    return false;
  }

  /// The latest [windowSize] rows of values, one value per sensor in
  /// [sensors] order. Throws [PredictorNotReadyException] until enough
  /// values are buffered.
  List<List<double>> window() {
    for (var i = 0; i < sensors.length; i++) {
      if (_store[i].isEmpty) throw PredictorNotReadyException("No data for sensor '${sensors[i]}' yet");
    }

    final rows = <int, List<double?>>{};
    for (var col = 0; col < sensors.length; col++) {
      for (final (t, v) in _store[col]) {
        (rows[t] ??= List<double?>.filled(sensors.length, null))[col] = v;
      }
    }
    final times = rows.keys.toList()..sort();
    if (times.length < windowSize) {
      throw PredictorNotReadyException('Not enough samples yet (${times.length}/$windowSize)');
    }
    final merged = [for (final t in times) rows[t]!];

    for (var col = 0; col < sensors.length; col++) {
      final column = [for (final row in merged) row[col]];
      interpolateLinear(column);
      for (var r = 0; r < merged.length; r++) {
        merged[r][col] = column[r];
      }
    }
    return [
      for (final row in merged.sublist(merged.length - windowSize)) [for (final v in row) v!],
    ];
  }
}

/// Fills the nulls of [values] in place: linearly between known values, with
/// the first known value before it and the last known value after it.
void interpolateLinear(List<double?> values) {
  double? left;
  var nulls = 0;
  for (var i = 0; i < values.length; i++) {
    final v = values[i];
    if (v == null) {
      nulls++;
      continue;
    }
    for (var j = 0; j < nulls; j++) {
      values[i - (nulls - j)] = left == null ? v : left + (v - left) * (j + 1) / (nulls + 1);
    }
    nulls = 0;
    left = v;
  }
  for (var j = 0; j < nulls; j++) {
    values[values.length - (nulls - j)] = left;
  }
}
