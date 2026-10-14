/// A label over a time range of a dataset: `labeling` is the group (e.g.
/// "activity"), `label` the class within it (e.g. "walk"). Times are unix
/// milliseconds, both inclusive.
class DatasetLabel {
  /// Creates a label from [start] to [end] (unix ms).
  const DatasetLabel(this.labeling, this.label, {required this.start, required this.end});

  /// The labeling (label group) name, e.g. "activity".
  final String labeling;

  /// The label (class) name, e.g. "walk".
  final String label;

  /// Start of the labeled range, unix ms.
  final int start;

  /// End of the labeled range (inclusive), unix ms.
  final int end;

  /// The JSON the device API expects.
  Map<String, Object> toJson() => {'labelingName': labeling, 'labelName': label, 'start': start, 'end': end};

  @override
  String toString() => 'DatasetLabel($labeling/$label, $start..$end)';

  @override
  bool operator ==(Object other) =>
      other is DatasetLabel &&
      other.labeling == labeling &&
      other.label == label &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(labeling, label, start, end);
}

/// A labeling (label group) of the project and its labels.
class Labeling {
  /// Creates a [Labeling].
  const Labeling({required this.id, required this.name, required this.labels});

  /// Parses a labeling document from the server.
  factory Labeling.fromJson(Map<String, dynamic> json) => Labeling(
    id: '${json['_id']}',
    name: json['name'] as String,
    labels: [
      for (final l in (json['labels'] as List? ?? const []).cast<Map<String, dynamic>>())
        LabelClass(id: '${l['_id']}', name: l['name'] as String, color: l['color'] as String?),
    ],
  );

  /// Server id of the labeling.
  final String id;

  /// Name, e.g. "activity".
  final String name;

  /// The labels (classes) of this labeling.
  final List<LabelClass> labels;

  @override
  String toString() => 'Labeling($name: ${labels.map((l) => l.name).join(', ')})';
}

/// One label (class) of a [Labeling].
class LabelClass {
  /// Creates a [LabelClass].
  const LabelClass({required this.id, required this.name, this.color});

  /// Server id of the label.
  final String id;

  /// Name, e.g. "walk".
  final String name;

  /// Display color in the edge-ml frontend, e.g. "#ff0000".
  final String? color;
}

/// A time-series (sensor channel) of a dataset.
class TimeSeriesInfo {
  /// Creates a [TimeSeriesInfo].
  const TimeSeriesInfo({
    required this.id,
    required this.name,
    this.unit = '',
    this.start,
    this.end,
    this.length,
    this.samplingRate,
  });

  /// Parses a time-series entry of a dataset document.
  factory TimeSeriesInfo.fromJson(Map<String, dynamic> json) {
    final rate = json['samplingRate'];
    return TimeSeriesInfo(
      id: '${json['_id']}',
      name: json['name'] as String,
      unit: json['unit'] as String? ?? '',
      start: _validTime(json['start']),
      end: _validTime(json['end']),
      length: (json['length'] as num?)?.toInt(),
      samplingRate: rate is Map ? (rate['mean'] as num?)?.toDouble() : (rate as num?)?.toDouble(),
    );
  }

  /// Server id of the time-series.
  final String id;

  /// Name, e.g. "accX".
  final String name;

  /// Unit, e.g. "m/s^2" (empty if unknown).
  final String unit;

  /// First timestamp (unix ms), `null` while the series is empty.
  final int? start;

  /// Last timestamp (unix ms), `null` while the series is empty.
  final int? end;

  /// Number of samples.
  final int? length;

  /// Mean sampling rate in Hz.
  final double? samplingRate;
}

/// A dataset of the project, without its sample values.
class Dataset {
  /// Creates a [Dataset].
  const Dataset({
    required this.id,
    required this.name,
    required this.timeSeries,
    required this.labels,
    this.metadata = const {},
  });

  /// Parses a dataset document, resolving label ids to names with the
  /// project's [labelings].
  factory Dataset.fromJson(Map<String, dynamic> json, List<Labeling> labelings) {
    final byId = {for (final l in labelings) l.id: l};
    final labels = <DatasetLabel>[];
    for (final group in (json['labelings'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      final labeling = byId['${group['labelingId']}'];
      if (labeling == null) continue;
      final classes = {for (final c in labeling.labels) c.id: c.name};
      for (final l in (group['labels'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        final name = classes['${l['type']}'];
        if (name == null) continue;
        labels.add(
          DatasetLabel(labeling.name, name, start: (l['start'] as num).toInt(), end: (l['end'] as num).toInt()),
        );
      }
    }
    labels.sort((a, b) => a.start.compareTo(b.start));
    return Dataset(
      id: '${json['_id']}',
      name: json['name'] as String,
      metadata: {for (final e in ((json['metaData'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
      timeSeries: [
        for (final ts in (json['timeSeries'] as List? ?? const []).cast<Map<String, dynamic>>())
          TimeSeriesInfo.fromJson(ts),
      ],
      labels: labels,
    );
  }

  /// Server id of the dataset.
  final String id;

  /// Name of the dataset.
  final String name;

  /// Metadata key/value pairs.
  final Map<String, String> metadata;

  /// The time-series of the dataset.
  final List<TimeSeriesInfo> timeSeries;

  /// All labels of the dataset, sorted by start time.
  final List<DatasetLabel> labels;

  /// First timestamp over all time-series (unix ms), `null` if empty.
  int? get start {
    final starts = timeSeries.map((t) => t.start).whereType<int>();
    return starts.isEmpty ? null : starts.reduce((a, b) => a < b ? a : b);
  }

  /// Last timestamp over all time-series (unix ms), `null` if empty.
  int? get end {
    final ends = timeSeries.map((t) => t.end).whereType<int>();
    return ends.isEmpty ? null : ends.reduce((a, b) => a > b ? a : b);
  }

  @override
  String toString() => 'Dataset($name, ${timeSeries.map((t) => t.name).join(', ')}, ${labels.length} labels)';
}

/// Empty series are stored with start = 2^63-1 / end = -1 on the server.
/// (Compared as a double: the int literal is not representable on the web.)
int? _validTime(Object? v) {
  if (v is! num || v < 0 || v >= 9e18) return null;
  return v.toInt();
}
