import 'dart:convert';

import '../errors.dart';
import '../http/api_client.dart';
import '../inference/model_cache.dart';
import '../inference/predictor.dart';
import '../inference/runtime.dart';
import 'types.dart';

/// Model functions of an [EdgeML] client: `edgeml.models`.
class ModelsApi {
  /// Use `EdgeML(...).models`.
  ModelsApi.internal(this._api, this._runtime, this._cache);

  final ApiClient _api;
  final InferenceRuntime _runtime;
  final ModelCache _cache;

  String get _base => '/ml/device/${_api.key}';

  /// The training presets the server offers.
  Future<List<Preset>> presets() async => [
    for (final p in (await _api.getJson('$_base/presets') as List).cast<Map<String, dynamic>>()) Preset.fromJson(p),
  ];

  /// All models of the project.
  Future<List<ModelInfo>> list() async => [
    for (final m in (await _api.getJson('$_base/models') as List).cast<Map<String, dynamic>>()) ModelInfo.fromJson(m),
  ];

  /// One model and its training state.
  Future<ModelInfo> get(String modelId) async =>
      ModelInfo.fromJson((await _api.getJson('$_base/models/${Uri.encodeComponent(modelId)}') as Map).cast());

  /// Starts training on the server and returns immediately. Use [watch] or
  /// [waitForModel] to follow it, or [train] to do both. Needs the write key.
  ///
  /// - [labeling]: name or id of the labeling to learn.
  /// - [preset]: a [Presets] id. Every preset trains a model that runs on the
  ///   device. Pass `null` for the server's default pipeline, which does not.
  /// - [datasets]: names or ids; default: every dataset with that labeling.
  /// - [timeSeries]: sensor names; default: those all datasets share.
  /// - [disabledLabels]: labels (names or ids) to leave out.
  /// - [steps]: per-step overrides on top of the preset, see [StepOverride].
  Future<TrainingStarted> startTraining({
    required String name,
    required String labeling,
    String? preset = Presets.mediumCnn,
    List<String>? datasets,
    List<String>? timeSeries,
    List<String> disabledLabels = const [],
    bool useZeroClass = false,
    Map<String, StepOverride> steps = const {},
  }) async {
    final res =
        (await _api.postJson('$_base/train', {
              'name': name,
              'labeling': labeling,
              'preset': ?preset,
              'datasets': ?datasets,
              'timeSeries': ?timeSeries,
              'disabledLabels': disabledLabels,
              'useZeroClass': useZeroClass,
              'pipeline': {for (final e in steps.entries) e.key: e.value.toJson()},
            })
            as Map);
    return TrainingStarted('${res['id']}', (res['warnings'] as List? ?? const []).cast<String>());
  }

  /// Emits the model's state every [interval] until training is done or
  /// failed (the last event), then closes.
  Stream<ModelInfo> watch(String modelId, {Duration interval = const Duration(seconds: 2)}) async* {
    while (true) {
      final model = await get(modelId);
      yield model;
      if (model.status == TrainStatus.done || model.status == TrainStatus.error) return;
      await Future<void>.delayed(interval);
    }
  }

  /// Waits until training of [modelId] is done. Throws [TrainingException]
  /// if it fails or takes longer than [timeout].
  Future<ModelInfo> waitForModel(
    String modelId, {
    void Function(ModelInfo model)? onProgress,
    Duration interval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final model = await get(modelId);
      onProgress?.call(model);
      if (model.status == TrainStatus.done) return model;
      if (model.status == TrainStatus.error) {
        throw TrainingException('Training failed: ${model.error ?? 'unknown error'}', modelId: modelId);
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TrainingException('Training did not finish within ${timeout.inMinutes} minutes', modelId: modelId);
      }
      await Future<void>.delayed(interval);
    }
  }

  /// Trains a model and waits until it is done; see [startTraining] for the
  /// parameters. [onWarning] receives the server's non-fatal warnings;
  /// [onProgress] the model's state every [interval] while it trains.
  Future<ModelInfo> train({
    required String name,
    required String labeling,
    String? preset = Presets.mediumCnn,
    List<String>? datasets,
    List<String>? timeSeries,
    List<String> disabledLabels = const [],
    bool useZeroClass = false,
    Map<String, StepOverride> steps = const {},
    void Function(ModelInfo model)? onProgress,
    void Function(String warning)? onWarning,
    Duration interval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 30),
  }) async {
    final started = await startTraining(
      name: name,
      labeling: labeling,
      preset: preset,
      datasets: datasets,
      timeSeries: timeSeries,
      disabledLabels: disabledLabels,
      useZeroClass: useZeroClass,
      steps: steps,
    );
    started.warnings.forEach(onWarning ?? (_) {});
    return waitForModel(started.modelId, onProgress: onProgress, interval: interval, timeout: timeout);
  }

  /// Downloads a trained model in ExecuTorch format: the `.pte` program and
  /// its `manifest.json`.
  Future<ModelFiles> download(String modelId) async {
    final base = '$_base/models/${Uri.encodeComponent(modelId)}/executorch';
    // manifest first: it fails fast (and explains why) for models that
    // cannot run on the device, before downloading the program
    final manifest = await _api.getJson('$base/manifest.json');
    final pte = await _api.getBytes('$base/model.pte');
    return ModelFiles(pte, jsonEncode(manifest));
  }

  /// Loads a trained model for on-device inference: downloads it on first
  /// use and caches it on the device (in memory on the web), so later loads
  /// work offline. [forceDownload] skips the cache.
  Future<Predictor> load(String modelId, {bool forceDownload = false}) async {
    final cacheKey = '${Uri.parse(_api.backendUrl).host}_$modelId';
    var files = forceDownload ? null : await _cache.read(cacheKey);
    if (files == null) {
      files = await download(modelId);
      await _cache.write(cacheKey, files);
    }
    return Predictor.fromBytes(files.pte, files.manifestJson, runtime: _runtime);
  }

  /// Removes downloaded models from the device cache: one, or all if
  /// [modelId] is null.
  Future<void> clearCache([String? modelId]) =>
      _cache.clear(modelId == null ? null : '${Uri.parse(_api.backendUrl).host}_$modelId');
}
