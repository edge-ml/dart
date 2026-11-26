import 'dart:math' as math;
import 'dart:typed_data';

/// Share of the output Nyquist band kept when converting down.
const _passband = 0.92;

/// Streaming sample-rate conversion for microphone audio.
///
/// Windowed-sinc interpolation (Blackman window). When converting down (e.g.
/// 48 kHz to 16 kHz) the kernel is widened and its cutoff lowered below the
/// new Nyquist frequency, so sounds above it are filtered out instead of
/// folding back as aliases. Chunks can be of any size; the output does not
/// depend on how the input was split.
///
/// A port of the JavaScript library's `Resampler`, so both produce the same
/// samples.
class Resampler {
  /// Converts from [inRate] to [outRate] (Hz). More [zeroCrossings] make the
  /// filter sharper and slower.
  Resampler(this.inRate, this.outRate, {int zeroCrossings = 16})
    : step = inRate / outRate,
      cutoff = outRate < inRate ? outRate / inRate * _passband : 1.0 {
    if (inRate <= 0 || outRate <= 0) throw ArgumentError('Sample rates must be positive');
    half = (zeroCrossings / cutoff).ceil();
    reset();
  }

  /// Sample rate of the input, in Hz.
  final num inRate;

  /// Sample rate of the output, in Hz.
  final num outRate;

  /// Input samples per output sample.
  final double step;

  /// Cutoff as a fraction of the input Nyquist frequency.
  final double cutoff;

  /// Kernel half-width in input samples.
  late final int half;

  late Float32List _history;
  // position of the next output sample, in input samples from _history[0]
  double _pos = 0;

  /// Forgets the past input (e.g. after a gap in the recording).
  void reset() {
    _history = Float32List(0);
    _pos = 0;
  }

  /// How far the output lags the input, in ms: an output sample needs the
  /// input up to half a kernel after it.
  double get latencyMs => inRate == outRate ? 0 : half / inRate * 1000;

  /// Converts the next [input] samples and returns the output samples they
  /// complete.
  Float32List process(List<double> input) {
    if (inRate == outRate) return Float32List.fromList(input);
    final x = Float32List(_history.length + input.length)
      ..setAll(0, _history)
      ..setAll(_history.length, input);
    final out = <double>[];
    while (_pos + half < x.length) {
      final center = _pos;
      final first = (center - half).ceil();
      final last = (center + half).floor();
      var acc = 0.0;
      for (var i = math.max(0, first); i <= last; i++) {
        final t = i - center;
        final w = 0.42 + 0.5 * math.cos(math.pi * t / half) + 0.08 * math.cos(2 * math.pi * t / half);
        acc += x[i] * cutoff * _sinc(cutoff * t) * w;
      }
      out.add(acc);
      _pos += step;
    }
    // keep what the next output samples still need
    final keep = math.max(0, (_pos - half).floor() - 1);
    _history = Float32List.fromList(x.sublist(keep));
    _pos -= keep;
    return Float32List.fromList(out);
  }

  static double _sinc(double x) => x == 0 ? 1 : math.sin(math.pi * x) / (math.pi * x);
}

/// Mixes interleaved multi-channel [samples] down to mono.
Float32List downmix(List<double> samples, int channels) {
  if (channels == 1) return Float32List.fromList(samples);
  final frames = samples.length ~/ channels;
  final out = Float32List(frames);
  for (var f = 0; f < frames; f++) {
    var sum = 0.0;
    for (var c = 0; c < channels; c++) {
      sum += samples[f * channels + c];
    }
    out[f] = sum / channels;
  }
  return out;
}
