import 'dart:math' as math;
import 'dart:typed_data';

import '../errors.dart';
import 'manifest.dart';
import 'runtime.dart';
import 'sample_buffer.dart';

/// The result of one classification.
class Prediction {
  /// Creates a [Prediction].
  const Prediction({
    required this.label,
    required this.index,
    required this.probabilities,
    required this.scores,
    required this.labels,
  });

  /// The predicted class label.
  final String label;

  /// Index of [label] in [labels].
  final int index;

  /// Probability per class, in [labels] order.
  final List<double> probabilities;

  /// Raw model outputs (logits) per class, in [labels] order.
  final List<double> scores;

  /// All class labels of the model.
  final List<String> labels;

  /// Probability of the predicted class.
  double get confidence => probabilities[index];

  /// Probability per class label.
  Map<String, double> get byLabel => {for (var i = 0; i < labels.length; i++) labels[i]: probabilities[i]};

  @override
  String toString() => 'Prediction($label, ${(confidence * 100).toStringAsFixed(1)}%)';
}

/// Runs a trained edge-ml model on the device. Get one with
/// [ModelsApi.load], or from files with [Predictor.fromBytes].
///
/// Feed it sensor values as they arrive with [addSample]/[addDatapoint] and
/// call [predict] to classify the latest window. Feature extraction and
/// normalization are part of the model; the predictor only buffers raw values
/// into windows, aligned the same way as for training.
///
/// ```dart
/// final predictor = await edgeml.models.load(modelId);
/// sensorStream.listen((e) async {
///   predictor.addSample({'accX': e.x, 'accY': e.y, 'accZ': e.z});
///   if (predictor.isReady) print((await predictor.predict()).label);
/// });
/// ```
class Predictor {
  Predictor._(this.manifest, this._model) : _buffer = SampleBuffer(manifest.timeSeries, manifest.windowSize);

  /// Loads a model from its `.pte` program and `manifest.json` text, e.g. an
  /// export downloaded from the edge-ml web app and bundled as app assets.
  static Future<Predictor> fromBytes(Uint8List pte, String manifestJson, {InferenceRuntime? runtime}) async {
    final manifest = ModelManifest.parse(manifestJson);
    final model = await (runtime ?? ExecuTorchRuntime()).load(pte);
    return Predictor._(manifest, model);
  }

  /// What the model expects and predicts.
  final ModelManifest manifest;

  final LoadedModel _model;
  final SampleBuffer _buffer;
  bool _disposed = false;

  /// The sensors the model expects, in input order.
  List<String> get timeSeries => manifest.timeSeries;

  /// The class labels the model predicts.
  List<String> get labels => manifest.labels;

  /// Samples per classified window.
  int get windowSize => manifest.windowSize;

  /// Whether enough values are buffered for [predict].
  bool get isReady => _buffer.isReady;

  /// Adds one [value] of [sensor] at [timestamp] (unix ms, default: now).
  void addDatapoint(String sensor, num value, {int? timestamp}) {
    _checkNotDisposed();
    _buffer.addDatapoint(sensor, value, timestamp ?? DateTime.now().millisecondsSinceEpoch);
  }

  /// Adds one value per sensor, all at the same [timestamp] (unix ms,
  /// default: now). Sensors the model does not use are ignored, so you can
  /// pass everything you record.
  void addSample(Map<String, num> values, {int? timestamp}) {
    _checkNotDisposed();
    final t = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    for (final sensor in timeSeries) {
      final value = values[sensor];
      if (value != null) _buffer.addDatapoint(sensor, value, t);
    }
  }

  /// Adds one value per sensor in [timeSeries] order.
  void addValues(List<num> values, {int? timestamp}) {
    if (values.length != timeSeries.length) {
      throw ArgumentError.value(values, 'values', 'needs ${timeSeries.length} values (${timeSeries.join(', ')})');
    }
    addSample({for (var i = 0; i < values.length; i++) timeSeries[i]: values[i]}, timestamp: timestamp);
  }

  /// Drops all buffered values.
  void reset() => _buffer.reset();

  /// Classifies the latest window of buffered values. Throws
  /// [PredictorNotReadyException] while fewer than [windowSize] samples are
  /// buffered.
  Future<Prediction> predict() {
    _checkNotDisposed();
    return predictWindow(_buffer.window());
  }

  /// Classifies one window: [windowSize] rows of one value per sensor, in
  /// [timeSeries] order.
  Future<Prediction> predictWindow(List<List<num>> window) async {
    _checkNotDisposed();
    final n = timeSeries.length;
    if (window.length != windowSize || window.any((row) => row.length != n)) {
      throw ArgumentError.value(window, 'window', 'must have $windowSize rows of $n values');
    }
    final input = Float32List(windowSize * n);
    for (var r = 0; r < windowSize; r++) {
      for (var c = 0; c < n; c++) {
        input[r * n + c] = window[r][c].toDouble();
      }
    }
    final output = await _model.run(input, [1, windowSize, n]);
    if (output.length != labels.length) {
      throw EdgeMLException('The model returned ${output.length} outputs for ${labels.length} labels');
    }
    final scores = [for (final v in output) v.toDouble()];
    final probabilities = manifest.outputType == 'logits' ? _softmax(scores) : scores;
    var best = 0;
    for (var i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > probabilities[best]) best = i;
    }
    return Prediction(label: labels[best], index: best, probabilities: probabilities, scores: scores, labels: labels);
  }

  /// Frees the model. The predictor cannot be used after.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _model.dispose();
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('The predictor is disposed');
  }

  static List<double> _softmax(List<double> xs) {
    final max = xs.reduce(math.max);
    final exps = [for (final x in xs) math.exp(x - max)];
    final sum = exps.reduce((a, b) => a + b);
    return [for (final e in exps) e / sum];
  }
}
