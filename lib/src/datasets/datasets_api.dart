import 'dart:math';

import '../errors.dart';
import '../http/api_client.dart';
import 'collector.dart';
import 'recording.dart';
import 'types.dart';

/// Dataset functions of an [EdgeML] client: `edgeml.datasets`.
class DatasetsApi {
  /// Use `EdgeML(...).datasets`.
  DatasetsApi.internal(this._api);

  final ApiClient _api;

  /// Values per upload request when uploading a whole recording.
  static const uploadChunkSize = 20000;

  /// All datasets of the project, with their time-series and labels (but not
  /// their values). Works with the read or the write key.
  Future<List<Dataset>> list() async {
    final project = await _project();
    final labelings = _labelings(project);
    return [
      for (final ds in (project['datasets'] as List? ?? const []).cast<Map<String, dynamic>>())
        Dataset.fromJson(ds, labelings),
    ];
  }

  /// One dataset by [id] or by [name]. Throws [NotFoundException] if there is
  /// none, and [EdgeMLException] if a name is used by several datasets.
  Future<Dataset> get(String idOrName) async {
    final all = await list();
    final byId = all.where((d) => d.id == idOrName);
    if (byId.isNotEmpty) return byId.first;
    final byName = all.where((d) => d.name == idOrName).toList();
    if (byName.isEmpty) throw NotFoundException("Dataset '$idOrName' does not exist in this project");
    if (byName.length > 1) {
      throw EdgeMLException("Several datasets are named '$idOrName'; use the id instead");
    }
    return byName.single;
  }

  /// The labelings (label groups) of the project and their labels.
  Future<List<Labeling>> labelings() async => _labelings(await _project());

  /// Uploads a whole [recording] with its labels and returns the new
  /// dataset's id. Needs the write key.
  Future<String> upload(DatasetRecording recording, {(String labeling, String label)? wholeDatasetLabel}) async {
    final data = recording.timeSeries;
    if (data.isEmpty) throw ArgumentError.value(recording, 'recording', 'has no values');
    final labels = recording.finishedLabels();
    final id = await _init(recording.name, data.keys.toList(), recording.metadata);

    var chunk = <String, List<(int, double)>>{};
    var size = 0;
    for (final MapEntry(key: series, value: values) in data.entries) {
      var i = 0;
      while (i < values.length) {
        final take = min(uploadChunkSize - size, values.length - i);
        (chunk[series] ??= []).addAll(values.sublist(i, i + take));
        i += take;
        size += take;
        if (size == uploadChunkSize) {
          await _append(id, chunk);
          chunk = {};
          size = 0;
        }
      }
    }
    await _append(id, chunk, labels: labels, wholeDatasetLabel: wholeDatasetLabel);
    return id;
  }

  /// Creates the dataset [name] with the given [timeSeries] and returns a
  /// [DatasetCollector] that uploads values while you record. Call
  /// [DatasetCollector.complete] when done. Needs the write key.
  ///
  /// [wholeDatasetLabel] labels the entire dataset, e.g. `('activity', 'walk')`.
  /// Use [DatasetCollector.startLabel]/[DatasetCollector.stopLabel] to label
  /// parts of it.
  Future<DatasetCollector> collector(
    String name,
    List<String> timeSeries, {
    Map<String, String> metadata = const {},
    (String labeling, String label)? wholeDatasetLabel,
    Duration uploadInterval = const Duration(seconds: 5),
    int maxBufferedValues = 5000,
  }) async {
    if (timeSeries.isEmpty) throw ArgumentError.value(timeSeries, 'timeSeries', 'must not be empty');
    final id = await _init(name, timeSeries, metadata);
    return DatasetCollector.internal(
      datasetId: id,
      timeSeries: List.unmodifiable(timeSeries),
      append: (data, {labels = const [], wholeDatasetLabel}) =>
          _append(id, data, labels: labels, wholeDatasetLabel: wholeDatasetLabel),
      uploadInterval: uploadInterval,
      maxBufferedValues: maxBufferedValues,
      wholeDatasetLabel: wholeDatasetLabel,
    );
  }

  Future<String> _init(String name, List<String> timeSeries, Map<String, String> metadata) async {
    if (name.isEmpty) throw ArgumentError.value(name, 'name', 'must not be empty');
    final res = await _api.postJson('/ds/api/dataset/init/${_api.key}', {
      'name': name,
      'timeSeries': timeSeries,
      'metaData': metadata,
    });
    final id = res is Map ? res['id'] : null;
    if (id == null) throw const EdgeMLException('The server did not return a dataset id');
    return '$id';
  }

  Future<void> _append(
    String id,
    Map<String, List<(int, double)>> data, {
    List<DatasetLabel> labels = const [],
    (String, String)? wholeDatasetLabel,
  }) async {
    if (data.isEmpty && labels.isEmpty && wholeDatasetLabel == null) return;
    await _api.postJson('/ds/api/dataset/append/${_api.key}/$id', {
      'data': [
        for (final MapEntry(key: name, value: values) in data.entries)
          {
            'name': name,
            'data': [
              for (final (t, v) in values) [t, v],
            ],
          },
      ],
      'labels': [for (final l in labels) l.toJson()],
      if (wholeDatasetLabel != null)
        'labeling': {'labelingName': wholeDatasetLabel.$1, 'labelName': wholeDatasetLabel.$2},
    });
  }

  Future<Map<String, dynamic>> _project() async =>
      (await _api.getJson('/ds/api/project/${_api.key}') as Map).cast<String, dynamic>();

  static List<Labeling> _labelings(Map<String, dynamic> project) => [
    for (final l in (project['labelings'] as List? ?? const []).cast<Map<String, dynamic>>()) Labeling.fromJson(l),
  ];
}
