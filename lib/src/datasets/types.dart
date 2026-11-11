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
    this.quantity,
    this.start,
    this.end,
    this.length,
    this.samplingRate,
  });

  /// Parses a time-series entry of a dataset document.
  factory TimeSeriesInfo.fromJson(Map<String, dynamic> json) {
    final rate = json['samplingRate'];
    final quantity = json['quantity'] as String?;
    return TimeSeriesInfo(
      id: '${json['_id']}',
      name: json['name'] as String,
      unit: json['unit'] as String? ?? '',
      quantity: quantity == null || quantity.isEmpty ? null : quantity,
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

  /// Physical quantity: a quantity id of the unit catalog (e.g.
  /// "acceleration", see [EdgeML.unitCatalog]), a custom label, or `null`
  /// when unknown (e.g. datasets recorded before units existed).
  final String? quantity;

  /// First timestamp (unix ms), `null` while the series is empty.
  final int? start;

  /// Last timestamp (unix ms), `null` while the series is empty.
  final int? end;

  /// Number of samples.
  final int? length;

  /// Mean sampling rate in Hz.
  final double? samplingRate;
}

/// Whether a recording is sound only or has a picture.
enum MediaKind {
  /// Sound only.
  audio,

  /// A picture, with or without sound.
  video,
}

/// An audio or video recording of a dataset.
///
/// It lies on the dataset's timeline: [start] is the moment it begins, so it
/// lines up with the time-series and the labels apply to it as well.
class MediaSeries {
  /// Creates a [MediaSeries].
  const MediaSeries({
    required this.id,
    required this.kind,
    required this.name,
    required this.start,
    required this.duration,
    required this.mimeType,
    required this.size,
    this.isProcessing = false,
    this.width,
    this.height,
    this.fps,
    this.sampleRate,
    this.channels,
    this.videoCodec,
    this.audioCodec,
  });

  /// Parses an entry of a dataset's `mediaSeries`.
  factory MediaSeries.fromJson(Map<String, dynamic> json) {
    final meta = (json['meta'] as Map?) ?? const {};
    return MediaSeries(
      id: '${json['_id']}',
      kind: json['kind'] == 'video' ? MediaKind.video : MediaKind.audio,
      name: json['name'] as String? ?? '',
      start: (json['start'] as num).toInt(),
      duration: Duration(milliseconds: (json['durationMs'] as num).toInt()),
      mimeType: json['mimeType'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      isProcessing: json['status'] == 'processing',
      width: (meta['width'] as num?)?.toInt(),
      height: (meta['height'] as num?)?.toInt(),
      fps: (meta['fps'] as num?)?.toDouble(),
      sampleRate: (meta['sampleRate'] as num?)?.toInt(),
      channels: (meta['channels'] as num?)?.toInt(),
      videoCodec: meta['videoCodec'] as String?,
      audioCodec: meta['audioCodec'] as String?,
    );
  }

  /// Server id of the recording.
  final String id;

  /// Audio or video.
  final MediaKind kind;

  /// Name, e.g. "front camera".
  final String name;

  /// The moment the recording begins on the dataset timeline, unix ms.
  final int start;

  /// Length of the recording.
  final Duration duration;

  /// The moment the recording ends on the dataset timeline, unix ms.
  int get end => start + duration.inMilliseconds;

  /// MIME type the server serves it with, e.g. "video/mp4".
  final String mimeType;

  /// Size of the file in bytes.
  final int size;

  /// `true` for a short while after the upload, while the server computes the
  /// waveform the web app shows. The recording can be played regardless.
  final bool isProcessing;

  /// Picture width in pixels (video only).
  final int? width;

  /// Picture height in pixels (video only).
  final int? height;

  /// Frames per second (video only).
  final double? fps;

  /// Sample rate of the sound in Hz, `null` for a silent video.
  final int? sampleRate;

  /// Number of sound channels, `null` for a silent video.
  final int? channels;

  /// Codec of the picture, e.g. "h264" (video only).
  final String? videoCodec;

  /// Codec of the sound, e.g. "aac"; `null` for a silent video.
  final String? audioCodec;

  @override
  String toString() => 'MediaSeries(${kind.name} $name, ${duration.inMilliseconds / 1000}s)';
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
    this.media = const [],
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
      // absent in datasets from before recordings existed
      media: [
        for (final m in (json['mediaSeries'] as List? ?? const []).cast<Map<String, dynamic>>())
          MediaSeries.fromJson(m),
      ],
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

  /// The audio and video recordings of the dataset.
  final List<MediaSeries> media;

  /// First timestamp over all time-series and recordings (unix ms), `null`
  /// if empty.
  int? get start {
    final starts = [...timeSeries.map((t) => t.start).whereType<int>(), ...media.map((m) => m.start)];
    return starts.isEmpty ? null : starts.reduce((a, b) => a < b ? a : b);
  }

  /// Last timestamp over all time-series and recordings (unix ms), `null` if
  /// empty.
  int? get end {
    final ends = [...timeSeries.map((t) => t.end).whereType<int>(), ...media.map((m) => m.end)];
    return ends.isEmpty ? null : ends.reduce((a, b) => a > b ? a : b);
  }

  @override
  String toString() =>
      'Dataset($name, ${timeSeries.map((t) => t.name).join(', ')}, ${labels.length} labels'
      '${media.isEmpty ? '' : ', ${media.length} recordings'})';
}

/// Empty series are stored with start = 2^63-1 / end = -1 on the server.
/// (Compared as a double: the int literal is not representable on the web.)
int? _validTime(Object? v) {
  if (v is! num || v < 0 || v >= 9e18) return null;
  return v.toInt();
}
