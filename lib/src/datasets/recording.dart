import 'label_tracker.dart';
import 'types.dart';

/// A dataset recorded in memory: sensor values and labels, uploaded later with
/// [DatasetsApi.upload] or exported as an edge-ml CSV file with [toCsv] (which
/// the edge-ml web app imports).
///
/// Use it to record without a network connection. To stream a long recording
/// to the server while recording, use [DatasetsApi.collector] instead.
///
/// ```dart
/// final rec = DatasetRecording('walk-1');
/// rec.startLabel('activity', 'walk');
/// rec.addSample({'accX': 0.1, 'accY': 9.8});
/// rec.stopLabel('activity');
/// await edgeml.datasets.upload(rec);
/// ```
class DatasetRecording with LabelTracker {
  /// Creates an empty recording named [name].
  DatasetRecording(this.name, {Map<String, String> metadata = const {}, Map<String, String> units = const {}})
    : metadata = Map.of(metadata),
      units = Map.of(units);

  /// Name of the dataset.
  final String name;

  /// Metadata key/value pairs stored with the dataset.
  final Map<String, String> metadata;

  /// Optional unit per time-series name, e.g. `{'accX': 'm/s^2'}` (CSV only).
  final Map<String, String> units;

  final Map<String, List<(int, double)>> _series = {};

  /// The recorded values per time-series as (unix ms, value) pairs, in the
  /// order they were added.
  Map<String, List<(int, double)>> get timeSeries => {
    for (final e in _series.entries) e.key: List.unmodifiable(e.value),
  };

  /// Total number of recorded values over all time-series.
  int get length => _series.values.fold(0, (n, s) => n + s.length);

  /// Adds one [value] of the time-series [series] at [timestamp] (unix ms,
  /// default: now).
  void add(String series, num value, {int? timestamp}) {
    checkValue(series, value);
    (_series[series] ??= []).add((timestamp ?? now(), value.toDouble()));
  }

  /// Adds one value per time-series, all at the same [timestamp] (unix ms,
  /// default: now).
  void addSample(Map<String, num> values, {int? timestamp}) {
    final t = timestamp ?? now();
    values.forEach((series, value) => add(series, value, timestamp: t));
  }

  /// The labels, with labels that are still open closed at the last recorded
  /// timestamp.
  List<DatasetLabel> finishedLabels() {
    final last = _lastTimestamp;
    if (last != null) closeOpenLabels(last);
    return labels;
  }

  int? get _lastTimestamp {
    int? last;
    for (final s in _series.values) {
      for (final (t, _) in s) {
        if (last == null || t > last) last = t;
      }
    }
    return last;
  }

  /// The recording in edge-ml's CSV format: a `time` column (unix ms), one
  /// `sensor_<name>[<unit>]` column per time-series and one
  /// `label_<labeling>_<label>` column per label, marked with `x` where the
  /// label applies. Open labels are closed at the last timestamp.
  String toCsv() {
    final labels = finishedLabels();
    final names = _series.keys.toList();
    final rows = <int, List<double?>>{};
    for (var i = 0; i < names.length; i++) {
      for (final (t, v) in _series[names[i]]!) {
        (rows[t] ??= List.filled(names.length, null))[i] = v;
      }
    }
    final times = rows.keys.toList()..sort();
    final labelColumns = <(String, String)>{for (final l in labels) (l.labeling, l.label)}.toList();

    final out = StringBuffer();
    out.writeln(
      [
        'time',
        for (final n in names) units[n] == null || units[n]!.isEmpty ? 'sensor_$n' : 'sensor_$n[${units[n]}]',
        for (final (labeling, label) in labelColumns) 'label_${labeling}_$label',
      ].join(','),
    );
    for (final t in times) {
      out.writeln(
        [
          t,
          for (final v in rows[t]!) v ?? '',
          for (final (labeling, label) in labelColumns)
            labels.any((l) => l.labeling == labeling && l.label == label && l.start <= t && t <= l.end) ? 'x' : '',
        ].join(','),
      );
    }
    return out.toString();
  }
}

/// Shared validation for recorded values.
void checkValue(String series, num value) {
  if (series.isEmpty) throw ArgumentError.value(series, 'series', 'must not be empty');
  if (value.isNaN || value.isInfinite) {
    throw ArgumentError.value(value, 'value', 'must be a finite number ($series)');
  }
}
