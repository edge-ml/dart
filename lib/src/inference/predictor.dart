import 'dart:math' as math;
import 'dart:typed_data';

import '../errors.dart';
import '../units.dart';
import 'manifest.dart';
import 'audio_buffer.dart';
import 'runtime.dart';
import 'sample_buffer.dart';
import 'time_grid_buffer.dart';

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
///
/// Models trained on sound (manifest schema 2) also take the microphone with
/// [addAudio] or [addPcm16Bytes], at any sample rate: it is mixed to mono and
/// converted to the model's rate ([audioSampleRate]). Their windows have a
/// fixed duration ([windowMs]), and [predict] classifies the latest window of
/// sound and sensors, aligned in time.
///
/// ```dart
/// recorder.startStream(const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1))
///     .listen((bytes) => predictor.addPcm16Bytes(bytes, sampleRate: 16000));
/// Timer.periodic(const Duration(milliseconds: 500), (_) async {
///   if (predictor.isReady) print((await predictor.predict()).label);
/// });
/// ```
class Predictor {
  Predictor._(this.manifest, this.inputUnits, this._conversions, this._model)
    : _buffer = SampleBuffer(manifest.timeSeries, manifest.windowSize),
      _grid = manifest.schemaVersion >= 2
          ? TimeGridBuffer(manifest.timeSeries, manifest.windowSize, manifest.windowMs!)
          : null,
      _audio = manifest.audioInput == null
          ? null
          : AudioBuffer(manifest.audioInput!.rate!.round(), manifest.audioInput!.shape[1]);

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
  // schema 2: sensors on a time grid, and sound
  final TimeGridBuffer? _grid;
  final AudioBuffer? _audio;
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

  /// Whether the model takes sound (see [addAudio]).
  bool get takesSound => _audio != null;

  /// The sample rate the model takes sound at (Hz), or null.
  int? get audioSampleRate => _audio?.sampleRate;

  /// Window duration in ms (models that take sound; null for others).
  double? get windowMs => manifest.windowMs;

  /// Whether enough values are buffered for [predict].
  bool get isReady {
    if (_grid == null) return _buffer.isReady;
    try {
      _latestInputs();
      return true;
    } on PredictorNotReadyException {
      return false;
    }
  }

  /// Adds one [value] of [sensor] at [timestamp] (unix ms, default: now).
  void addDatapoint(String sensor, num value, {int? timestamp}) {
    _checkNotDisposed();
    final t = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    if (_grid != null) {
      _grid.addDatapoint(sensor, value, t);
    } else {
      _buffer.addDatapoint(sensor, value, t);
    }
  }

  /// Adds sound in [-1, 1] at [sampleRate] Hz (interleaved when [channels] >
  /// 1). [timestamp] is the unix ms of the last sample (default: now). Throws
  /// [StateError] for a model that does not take sound.
  void addAudio(List<double> samples, {required num sampleRate, int channels = 1, int? timestamp}) {
    _checkNotDisposed();
    final audio = _audio;
    if (audio == null) throw StateError('This model does not take sound');
    audio.add(samples, rate: sampleRate, channels: channels, time: timestamp ?? DateTime.now().millisecondsSinceEpoch);
  }

  /// Like [addAudio], for 16-bit PCM samples.
  void addPcm16(Int16List samples, {required num sampleRate, int channels = 1, int? timestamp}) {
    addAudio([for (final s in samples) s / 32768], sampleRate: sampleRate, channels: channels, timestamp: timestamp);
  }

  /// Like [addAudio], for 16-bit little-endian PCM bytes, e.g. from the
  /// `record` package's `startStream` with `AudioEncoder.pcm16bits`.
  void addPcm16Bytes(Uint8List bytes, {required num sampleRate, int channels = 1, int? timestamp}) {
    final view = ByteData.sublistView(bytes);
    final samples = Int16List(bytes.length ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = view.getInt16(i * 2, Endian.little);
    }
    addPcm16(samples, sampleRate: sampleRate, channels: channels, timestamp: timestamp);
  }

  /// Adds one value per sensor, all at the same [timestamp] (unix ms,
  /// default: now). Sensors the model does not use are ignored, so you can
  /// pass everything you record.
  void addSample(Map<String, num> values, {int? timestamp}) {
    _checkNotDisposed();
    final t = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    for (final sensor in timeSeries) {
      final value = values[sensor];
      if (value == null) continue;
      if (_grid != null) {
        _grid.addDatapoint(sensor, value, t);
      } else {
        _buffer.addDatapoint(sensor, value, t);
      }
    }
  }

  /// Adds one value per sensor in [timeSeries] order.
  void addValues(List<num> values, {int? timestamp}) {
    if (values.length != timeSeries.length) {
      throw ArgumentError.value(values, 'values', 'needs ${timeSeries.length} values (${timeSeries.join(', ')})');
    }
    addSample({for (var i = 0; i < values.length; i++) timeSeries[i]: values[i]}, timestamp: timestamp);
  }

  /// Drops all buffered values (and sound).
  void reset() {
    _buffer.reset();
    _grid?.reset();
    _audio?.reset();
  }

  /// Classifies the latest window of buffered values. Throws
  /// [PredictorNotReadyException] while fewer than [windowSize] samples are
  /// buffered.
  Future<Prediction> predict() {
    _checkNotDisposed();
    if (_grid != null) {
      final (sensors, audio) = _latestInputs();
      return predictInputs(sensors: sensors, audio: audio);
    }
    return predictWindow(_buffer.window());
  }

  // the latest window of every input, ending at the same time
  (List<List<double>>?, Float32List?) _latestInputs() {
    final ends = <double?>[if (timeSeries.isNotEmpty) _grid!.endTime, if (_audio != null) _audio.endTime];
    if (ends.contains(null)) {
      throw PredictorNotReadyException(
        _audio != null && _audio.endTime == null ? 'No sound yet' : 'No sensor values yet',
      );
    }
    final end = ends.cast<double>().reduce(math.min);
    return (timeSeries.isNotEmpty ? _grid!.window(end) : null, _audio?.window(end));
  }

  /// Classifies one window of a model that takes sound: [sensors] as
  /// [windowSize] rows in [timeSeries] order (declared units), and [audio] as
  /// one window of mono samples at [audioSampleRate] in [-1, 1].
  Future<Prediction> predictInputs({List<List<num>>? sensors, List<double>? audio}) async {
    _checkNotDisposed();
    if (manifest.schemaVersion < 2) throw StateError('This model takes one sensor window; use predictWindow');
    final model = _model;
    if (model is! MultiInputModel) {
      throw const EdgeMLException('This runtime cannot run models with several inputs (implement MultiInputModel)');
    }
    final tensors = <InputTensor>[];
    for (final input in manifest.inputs) {
      if (input.kind == 'sensors') {
        tensors.add((data: _sensorTensor(sensors), shape: [1, windowSize, timeSeries.length]));
      } else {
        final n = input.shape[1];
        if (audio == null || audio.length != n) throw ArgumentError.value(audio?.length, 'audio', 'must have $n samples');
        tensors.add((data: Float32List.fromList(audio), shape: [1, n]));
      }
    }
    return _toPrediction(await model.runAll(tensors));
  }

  Float32List _sensorTensor(List<List<num>>? window) {
    final n = timeSeries.length;
    if (window == null || window.length != windowSize || window.any((row) => row.length != n)) {
      throw ArgumentError.value(window, 'window', 'must have $windowSize rows of $n values');
    }
    final input = Float32List(windowSize * n);
    for (var r = 0; r < windowSize; r++) {
      for (var c = 0; c < n; c++) {
        final conversion = _conversions[c];
        input[r * n + c] = conversion == null ? window[r][c].toDouble() : conversion.apply(window[r][c]);
      }
    }
    return input;
  }

  /// Classifies one window: [windowSize] rows of one value per sensor, in
  /// [timeSeries] order and in the declared units (see [setUnits]).
  Future<Prediction> predictWindow(List<List<num>> window) async {
    _checkNotDisposed();
    if (manifest.schemaVersion >= 2) {
      if (takesSound) throw StateError('This model also takes sound; use predictInputs');
      return predictInputs(sensors: window);
    }
    final output = await _model.run(_sensorTensor(window), [1, windowSize, timeSeries.length]);
    return _toPrediction(output);
  }

  Prediction _toPrediction(Float32List output) {
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
