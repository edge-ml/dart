import 'dart:convert';

import '../errors.dart';
import '../units.dart';

/// One input of a model with several inputs (manifest schema 2).
class ModelInput {
  /// Creates a [ModelInput].
  const ModelInput({required this.name, required this.kind, required this.shape, this.rate});

  /// Parses an entry of the manifest's `inputs`.
  factory ModelInput.fromJson(Map<String, dynamic> json) => ModelInput(
        name: json['name'] as String,
        kind: json['kind'] as String,
        shape: [for (final d in json['shape'] as List) (d as num).toInt()],
        rate: ((json['sample_rate'] ?? json['sampling_rate']) as num?)?.toDouble(),
      );

  /// Tensor name, e.g. `raw_window` or `audio`.
  final String name;

  /// `sensors` (a window x channel grid) or `audio` (mono samples in [-1, 1]).
  final String kind;

  /// Tensor shape with the batch dimension, e.g. `[1, 50, 3]` or `[1, 16000]`.
  final List<int> shape;

  /// Sampling rate of the sensors or sample rate of the sound, in Hz.
  final double? rate;
}

/// The `manifest.json` that comes with an ExecuTorch model: what the model
/// expects as input and what its outputs mean.
///
/// Schema 1 describes one window of sensor samples. Schema 2 (models that take
/// sound) lists [inputs] and gives the window as a duration ([windowMs]).
class ModelManifest {
  /// Creates a [ModelManifest].
  const ModelManifest({
    required this.modelId,
    required this.modelName,
    required this.windowSize,
    required this.windowStride,
    required this.timeSeries,
    required this.labels,
    required this.outputType,
    this.inputUnits = const [],
    this.samplingRate,
    this.classificationFrequencyHz,
    this.executorchVersion,
    this.schemaVersion = 1,
    this.inputs = const [],
    this.windowMs,
    this.windowStrideMs,
  });

  /// Parses a manifest from its JSON text. Throws [EdgeMLException] if it is
  /// not an edge-ml ExecuTorch manifest this library understands.
  factory ModelManifest.parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw EdgeMLException('manifest.json is not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) throw const EdgeMLException('manifest.json is not a JSON object');
    return ModelManifest.fromJson(decoded);
  }

  /// Parses a decoded manifest.
  factory ModelManifest.fromJson(Map<String, dynamic> json) {
    // exports made before the format field existed are ExecuTorch manifests too
    final format = json['format'] ?? 'executorch';
    if (format != 'executorch') {
      throw EdgeMLException("This is a '$format' model; the Flutter library runs ExecuTorch models");
    }
    if (json['schema_version'] == 2) return ModelManifest._v2(json);
    if (json['schema_version'] != 1) {
      throw EdgeMLException('Unsupported manifest schema_version ${json['schema_version']}; update edge_ml_dart');
    }
    try {
      final window = json['window'] as Map<String, dynamic>;
      final input = json['input'] as Map<String, dynamic>;
      final output = json['output'] as Map<String, dynamic>;
      return ModelManifest(
        modelId: '${json['model_id']}',
        modelName: json['model_name'] as String? ?? '',
        windowSize: (window['size'] as num).toInt(),
        windowStride: (window['stride'] as num?)?.toInt() ?? (window['size'] as num).toInt(),
        timeSeries: (input['timeseries'] as List).cast<String>(),
        labels: (output['labels'] as List).cast<String>(),
        outputType: output['type'] as String? ?? 'logits',
        inputUnits: InputUnit.listFromManifestInput(input),
        samplingRate: (json['sampling_rate'] as num?)?.toDouble(),
        classificationFrequencyHz: (json['classification_frequency_hint_hz'] as num?)?.toDouble(),
        executorchVersion: (json['executorch'] as Map?)?['version'] as String?,
      );
    } on TypeError catch (e) {
      throw EdgeMLException('manifest.json is missing a field: $e');
    }
  }

  // schema 2: models with several inputs (sound and/or sensors)
  factory ModelManifest._v2(Map<String, dynamic> json) {
    try {
      final window = json['window'] as Map<String, dynamic>;
      final output = json['output'] as Map<String, dynamic>;
      final rawInputs = (json['inputs'] as List).cast<Map<String, dynamic>>();
      final inputs = [for (final i in rawInputs) ModelInput.fromJson(i)];
      final sensors = rawInputs.where((i) => i['kind'] == 'sensors').firstOrNull;
      final windowSize = sensors == null ? 0 : ((sensors['shape'] as List)[1] as num).toInt();
      return ModelManifest(
        schemaVersion: 2,
        modelId: '${json['model_id']}',
        modelName: json['model_name'] as String? ?? '',
        windowSize: windowSize,
        windowStride: windowSize,
        windowMs: (window['duration_ms'] as num).toDouble(),
        windowStrideMs: (window['stride_ms'] as num?)?.toDouble(),
        inputs: List.unmodifiable(inputs),
        timeSeries: sensors == null ? const [] : (sensors['timeseries'] as List).cast<String>(),
        labels: (output['labels'] as List).cast<String>(),
        outputType: output['type'] as String? ?? 'logits',
        inputUnits: sensors == null ? const [] : InputUnit.listFromManifestInput(sensors),
        samplingRate: (sensors?['sampling_rate'] as num?)?.toDouble(),
        classificationFrequencyHz: (json['classification_frequency_hint_hz'] as num?)?.toDouble(),
        executorchVersion: (json['executorch'] as Map?)?['version'] as String?,
      );
    } on TypeError catch (e) {
      throw EdgeMLException('manifest.json is missing a field: $e');
    }
  }

  /// 1: one window of sensor samples. 2: several inputs, e.g. sound ([inputs]).
  final int schemaVersion;

  /// The model's inputs in the order it takes them (schema 2; empty for 1).
  final List<ModelInput> inputs;

  /// Window duration in ms (schema 2).
  final double? windowMs;

  /// Time between two windows during training, in ms (schema 2).
  final double? windowStrideMs;

  /// The sound input, if the model takes sound.
  ModelInput? get audioInput => inputs.where((i) => i.kind == 'audio').firstOrNull;

  /// The sensor input of a schema 2 model, if it takes sensors.
  ModelInput? get sensorInput => inputs.where((i) => i.kind == 'sensors').firstOrNull;

  /// Server id of the model.
  final String modelId;

  /// Name of the model.
  final String modelName;

  /// Samples per window the model classifies (of the sensors; 0 for a model
  /// that only takes sound).
  final int windowSize;

  /// Samples between two windows during training (a hint for how often to
  /// classify).
  final int windowStride;

  /// The time-series (sensors) the model expects, in input order.
  final List<String> timeSeries;

  /// The unit the model expects for each of [timeSeries], in the same order.
  /// Every input is unknown for models trained before units existed.
  final List<InputUnit> inputUnits;

  /// Class label of each model output.
  final List<String> labels;

  /// `logits` (softmax gives probabilities) or `probabilities`.
  final String outputType;

  /// Sampling rate of the training data in Hz.
  final double? samplingRate;

  /// Suggested classification rate: sampling rate / window stride.
  final double? classificationFrequencyHz;

  /// ExecuTorch version the model was compiled with.
  final String? executorchVersion;
}
