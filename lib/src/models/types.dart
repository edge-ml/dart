/// Ids of the training presets the edge-ml server offers (see
/// [ModelsApi.presets] for the current list and descriptions). Every preset
/// trains a model that runs on the device.
abstract final class Presets {
  /// 1 convolution block, 8 filters. Fastest and smallest.
  static const smallCnn = 'small_cnn';

  /// 2 convolution blocks, 16 filters. A good default.
  static const mediumCnn = 'medium_cnn';

  /// 3 convolution blocks, 32 filters. Most accurate, largest.
  static const largeCnn = 'large_cnn';

  /// 1 hidden layer on simple statistical features.
  static const smallDense = 'small_dense';

  /// 3 hidden layers on simple statistical features.
  static const largeDense = 'large_dense';
}

/// A training preset offered by the server.
class Preset {
  /// Creates a [Preset].
  const Preset({required this.id, required this.name, required this.description, this.pipeline = const {}});

  /// Parses a preset from the server.
  factory Preset.fromJson(Map<String, dynamic> json) => Preset(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    pipeline: (json['pipeline'] as Map? ?? const {}).cast<String, dynamic>(),
  );

  /// Id to pass to [ModelsApi.train], e.g. `small_cnn`.
  final String id;

  /// Display name, e.g. "Small CNN".
  final String name;

  /// What the preset trains.
  final String description;

  /// The pipeline steps the preset selects (for display).
  final Map<String, dynamic> pipeline;

  @override
  String toString() => 'Preset($id)';
}

/// One step override for [ModelsApi.train]: pick a different [option] for a
/// pipeline step and/or change its [parameters]. Step keys are `windowing`,
/// `featureExtraction`, `normalizer`, `classifier` and `evaluation`.
class StepOverride {
  /// Creates a [StepOverride]; leave [option] out to keep the preset's option.
  const StepOverride({this.option, this.parameters = const {}});

  /// Option name as listed by the server, e.g. "PyTorch 1D Convolutional Neural Network".
  final String? option;

  /// Parameter values by name, e.g. `{'window_size': 100}`.
  final Map<String, Object> parameters;

  /// The JSON the device API expects.
  Map<String, Object> toJson() => {'name': ?option, 'parameters': parameters};
}

/// Training state of a model.
enum TrainStatus {
  /// Queued, not started yet.
  waiting,

  /// Training is running.
  training,

  /// Finished; the model can be downloaded.
  done,

  /// Training failed; see [ModelInfo.error].
  error;

  static TrainStatus _parse(Object? v) =>
      TrainStatus.values.firstWhere((s) => s.name == v, orElse: () => TrainStatus.waiting);
}

/// A model of the project and its training state.
class ModelInfo {
  /// Creates a [ModelInfo].
  const ModelInfo({
    required this.id,
    required this.name,
    required this.status,
    this.stage,
    this.progress,
    this.error,
    this.formats = const [],
    this.preset,
    this.labels = const [],
    this.timeSeries = const [],
    this.samplingRate,
    this.metrics,
  });

  /// Parses a model summary from the server.
  factory ModelInfo.fromJson(Map<String, dynamic> json) => ModelInfo(
    id: json['id'] as String,
    name: json['name'] as String,
    status: TrainStatus._parse(json['trainStatus']),
    stage: json['stage'] as String?,
    progress: (json['progress'] as num?)?.toInt(),
    error: json['error'] as String?,
    formats: (json['formats'] as List? ?? const []).cast<String>(),
    preset: json['preset'] as String?,
    labels: (json['labels'] as List? ?? const []).cast<String>(),
    timeSeries: (json['timeSeries'] as List? ?? const []).cast<String>(),
    samplingRate: (json['samplingRate'] as num?)?.toDouble(),
    metrics: (json['metrics'] as Map?)?.cast<String, dynamic>(),
  );

  /// Server id of the model.
  final String id;

  /// Name of the model.
  final String name;

  /// Training state.
  final TrainStatus status;

  /// Coarse training stage while training, e.g. "Training classifier".
  final String? stage;

  /// Training progress in percent, for classifiers that report it.
  final int? progress;

  /// Why training failed, if [status] is [TrainStatus.error].
  final String? error;

  /// Export formats the model supports, e.g. `EXECUTORCH`, `ONNX`, `C`.
  final List<String> formats;

  /// The preset the model was trained from, if any.
  final String? preset;

  /// The class labels the model predicts.
  final List<String> labels;

  /// The time-series (sensors) the model expects, in input order.
  final List<String> timeSeries;

  /// Sampling rate of the training data in Hz.
  final double? samplingRate;

  /// Evaluation metrics (accuracy, f1, confusion matrix, ...), once trained.
  final Map<String, dynamic>? metrics;

  /// Whether training finished successfully.
  bool get isTrained => status == TrainStatus.done;

  /// Whether the model can be loaded with [ModelsApi.load].
  bool get runsOnDevice => isTrained && formats.contains('EXECUTORCH');

  @override
  String toString() => 'ModelInfo($name, ${status.name}${progress != null ? ' $progress%' : ''})';
}

/// Result of [ModelsApi.startTraining].
class TrainingStarted {
  /// Creates a [TrainingStarted].
  const TrainingStarted(this.modelId, this.warnings);

  /// Id of the model being trained.
  final String modelId;

  /// Non-fatal warnings from the server, e.g. about few training windows.
  final List<String> warnings;
}
