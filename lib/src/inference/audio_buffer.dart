import 'dart:math' as math;
import 'dart:typed_data';

import '../errors.dart';
import 'resampler.dart';

/// Keep this many windows of sound.
const _storeFactor = 4;

/// Buffers microphone sound for a model: converts it to mono at the model's
/// [sampleRate] and keeps the latest samples with the time of the last one.
/// A port of the JavaScript library's AudioBuffer.
class AudioBuffer {
  /// Creates a buffer for windows of [windowSamples] samples at [sampleRate].
  AudioBuffer(this.sampleRate, this.windowSamples) : _capacity = _storeFactor * windowSamples {
    reset();
  }

  /// The rate the model takes sound at, in Hz.
  final int sampleRate;

  /// Samples per window.
  final int windowSamples;

  final int _capacity;
  late Float32List _data;
  int _count = 0;
  int _head = 0;
  Resampler? _resampler;

  /// Unix ms of the last stored sample, or null before any sound.
  double? endTime;

  /// Drops all sound.
  void reset() {
    _data = Float32List(_capacity);
    _count = 0;
    _head = 0;
    endTime = null;
    _resampler = null;
  }

  /// Adds [samples] in [-1, 1] at [rate] Hz (interleaved when [channels] > 1);
  /// [time] is the unix ms of the last sample.
  void add(List<double> samples, {required num rate, int channels = 1, required num time}) {
    if (rate <= 0) throw ArgumentError.value(rate, 'sampleRate', 'must be positive');
    if (_resampler == null || _resampler!.inRate != rate) _resampler = Resampler(rate, sampleRate);
    final out = _resampler!.process(downmix(samples, channels));
    for (final x in out) {
      _data[_head] = x;
      _head = (_head + 1) % _capacity;
    }
    _count = math.min(_capacity, _count + out.length);
    endTime = time - _resampler!.latencyMs;
  }

  /// The [windowSamples] samples ending at [end] (unix ms; default: the last
  /// sample).
  Float32List window([double? end]) {
    final last = endTime;
    if (last == null) throw const PredictorNotReadyException('No sound yet');
    final back = math.max(0, ((last - (end ?? last)) * sampleRate / 1000).round());
    final needed = windowSamples + back;
    if (_count < needed) {
      throw PredictorNotReadyException('Not enough sound (${math.max(0, _count - back)}/$windowSamples samples)');
    }
    final out = Float32List(windowSamples);
    final start = _head - needed;
    for (var i = 0; i < windowSamples; i++) {
      out[i] = _data[(start + i) % _capacity];
    }
    return out;
  }
}
