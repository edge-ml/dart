import 'dart:math' as math;
import 'dart:typed_data';

import '../errors.dart';
import '../units.dart';
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
/// Declare the unit each sensor delivers with `units` (or [setUnits]) and the
/// values are converted to the units the model expects ([inputUnits]) before
/// predicting.
///
/// ```dart
/// final predictor = await edgeml.models.load(modelId, units: {'accX': 'm/s^2', 'accY': 'm/s^2', 'accZ': 'm/s^2'});
/// sensorStream.listen((e) async {
///   predictor.addSample({'accX': e.x, 'accY': e.y, 'accZ': e.z});
///   if (predictor.isReady) print((await predictor.predict()).label);
/// });
/// ```
class Predictor {
  Predictor._(this.manifest, this.inputUnits, this._conversions, this._model)
    : _buffer = SampleBuffer(manifest.timeSeries, manifest.windowSize);

  /// Loads a model from its `.pte` program and `manifest.json` text, e.g. an
  /// export downloaded from the edge-ml web app and bundled as app assets.
  ///
  /// [units] declares the unit each sensor delivers (see [setUnits]); with a
  /// [catalog], unit labels and aliases such as `°F` are accepted too.
  static Future<Predictor> fromBytes(
    Uint8List pte,
    String manifestJson, {
    InferenceRuntime? runtime,
    Map<String, String> units = const {},
    UnitCatalog? catalog,
  }) async {
    final manifest = ModelManifest.parse(manifestJson);
    final inputUnits = List<InputUnit>.unmodifiable(
      manifest.inputUnits.length == manifest.timeSeries.length
          ? manifest.inputUnits
          : [for (final n in manifest.timeSeries) InputUnit.unknown(n)],
    );
    // check the units before loading the model, so a mistake fails fast
    final conversions = resolveUnitConversions(inputUnits, units, catalog: catalog);
    final model = await (runtime ?? ExecuTorchRuntime()).load(pte);
    return Predictor._(manifest, inputUnits, conversions, model);
  }

  /// What the model expects and predicts.
  final ModelManifest manifest;

  final LoadedModel _model;
  final SampleBuffer _buffer;
  List<UnitConversion?> _conversions;
  bool _disposed = false;

  /// The unit the model expects for each of [timeSeries], with the
  /// conversions from other units of the same quantity. Inputs of models
  /// trained before units existed are unknown ([InputUnit.isKnown] false).
  final List<InputUnit> inputUnits;

  /// Declares the unit each sensor delivers, by time-series name, e.g.
  /// `{'accX': 'g', 'temp': 'degF'}`, replacing earlier declarations. Values
  /// are then converted to the units the model expects before predicting.
  ///
  /// Sensors left out, sensors the model does not use, and inputs of unknown
  /// unit pass through unchanged. Throws [UnitException] if the model cannot
  /// convert from a declared unit. Units are matched by catalog id
  /// (`m/s^2`, `degF`); with a [catalog] ([EdgeML.unitCatalog]), labels and
  /// aliases like `m/s²` or `°F` are accepted too.
  void setUnits(Map<String, String> units, {UnitCatalog? catalog}) {
    _conversions = resolveUnitConversions(inputUnits, units, catalog: catalog);
  }

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
  /// [timeSeries] order and in the declared units (see [setUnits]).
  Future<Prediction> predictWindow(List<List<num>> window) async {
    _checkNotDisposed();
    final n = timeSeries.length;
    if (window.length != windowSize || window.any((row) => row.length != n)) {
      throw ArgumentError.value(window, 'window', 'must have $windowSize rows of $n values');
    }
    final input = Float32List(windowSize * n);
    for (var r = 0; r < windowSize; r++) {
      for (var c = 0; c < n; c++) {
        final conversion = _conversions[c];
        input[r * n + c] = conversion == null ? window[r][c].toDouble() : conversion.apply(window[r][c]);
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
