import 'dart:convert';

import '../errors.dart';

/// The `manifest.json` that comes with an ExecuTorch model: what the model
/// expects as input and what its outputs mean.
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
    this.samplingRate,
    this.classificationFrequencyHz,
    this.executorchVersion,
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
        samplingRate: (json['sampling_rate'] as num?)?.toDouble(),
        classificationFrequencyHz: (json['classification_frequency_hint_hz'] as num?)?.toDouble(),
        executorchVersion: (json['executorch'] as Map?)?['version'] as String?,
      );
    } on TypeError catch (e) {
      throw EdgeMLException('manifest.json is missing a field: $e');
    }
  }

  /// Server id of the model.
  final String modelId;

  /// Name of the model.
  final String modelName;

  /// Samples per window the model classifies.
  final int windowSize;

  /// Samples between two windows during training (a hint for how often to
  /// classify).
  final int windowStride;

  /// The time-series (sensors) the model expects, in input order.
  final List<String> timeSeries;

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
