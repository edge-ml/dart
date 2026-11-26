// Models that take sound (manifest schema 2): manifest, buffers, resampler,
// and the real ExecuTorch runtime on models exported by the edge-ml server
// with Python reference scores (test/fixtures/README.md).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:edge_ml_dart/src/inference/resampler.dart' show downmix;
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Float32List floats(String b64) {
  final bytes = base64Decode(b64);
  return Float32List.view(Uint8List.fromList(bytes).buffer);
}

Map<String, dynamic> reference(String name) =>
    jsonDecode(File('test/fixtures/$name/reference.json').readAsStringSync()) as Map<String, dynamic>;

const t0 = 1800000000000;

void main() {
  group('manifest schema 2', () {
    test('lists the inputs and the window duration', () {
      final m = ModelManifest.parse(File('test/fixtures/audio_mixed/manifest.json').readAsStringSync());
      expect(m.schemaVersion, 2);
      expect([for (final i in m.inputs) i.name], ['raw_window', 'audio']);
      expect(m.timeSeries, ['acc_x', 'acc_y']);
      expect(m.windowSize, 25);
      expect(m.windowMs, 500);
      expect(m.samplingRate, 50);
      expect(m.audioInput!.rate, 8000);
      expect(m.audioInput!.shape, [1, 4000]);
      expect(m.labels, ['still', 'shaking']);
      final only = ModelManifest.parse(File('test/fixtures/audio_only/manifest.json').readAsStringSync());
      expect(only.timeSeries, isEmpty);
      expect(only.windowSize, 0);
      expect(only.sensorInput, isNull);
    });
  });

  for (final name in ['audio_mixed', 'audio_only']) {
    group('Predictor with sound ($name)', () {
      final mixed = name == 'audio_mixed';
      final ref = reference(name);
      final sensors = mixed ? (ref['sensors'] as List).cast<List>() : const <List>[];
      final audio = [for (final a in ref['audio'] as List) floats(a as String)];
      final python = (ref['python_scores'] as List).cast<List>();
      final pythonPredictions = (ref['python_predictions'] as List).cast<int>();
      final windowMs = (ref['window_ms'] as num).toDouble();
      final sensorSamples = ref['sensor_samples'] as int;
      late Predictor predictor;

      List<List<num>>? rows(int k) => mixed ? [for (final r in sensors[k]) (r as List).cast<num>()] : null;

      // feeds window k as a device would: sensors on their own timestamps, then sound
      void feed(int k, int end, Float32List sound, int rate, {int chunk = 1000}) {
        if (mixed) {
          final r = rows(k)!;
          final step = windowMs / sensorSamples;
          final names = predictor.timeSeries;
          Map<String, num> sample(List<num> row) => {for (var c = 0; c < names.length; c++) names[c]: row[c]};
          predictor.addSample(sample(r.first), timestamp: (end - windowMs - step).round());
          for (var i = 0; i < r.length; i++) {
            predictor.addSample(sample(r[i]), timestamp: (end - windowMs + i * step).round());
          }
          predictor.addSample(sample(r.last), timestamp: end);
        }
        for (var i = 0; i < sound.length; i += chunk) {
          final part = sound.sublist(i, math.min(sound.length, i + chunk));
          final time = end - (sound.length - (i + part.length)) * 1000 ~/ rate;
          predictor.addAudio(part, sampleRate: rate, timestamp: time);
        }
      }

      setUpAll(() async {
        predictor = await Predictor.fromBytes(
          File('test/fixtures/$name/model.pte').readAsBytesSync(),
          File('test/fixtures/$name/manifest.json').readAsStringSync(),
        );
      });
      tearDownAll(() => predictor.dispose());
      setUp(() => predictor.reset());

      test('reads its inputs', () {
        expect(predictor.takesSound, isTrue);
        expect(predictor.audioSampleRate, 8000);
        expect(predictor.windowMs, 500);
        expect(predictor.timeSeries, mixed ? ['acc_x', 'acc_y'] : isEmpty);
      });

      test('matches the Python pipeline through ExecuTorch', () async {
        for (var k = 0; k < audio.length; k++) {
          final p = await predictor.predictInputs(sensors: rows(k), audio: audio[k]);
          for (var j = 0; j < p.scores.length; j++) {
            expect(p.scores[j], closeTo((python[k][j] as num).toDouble(), 1e-3));
          }
          expect(p.index, pythonPredictions[k]);
        }
      });

      test('buffers sensors and sound into the same window', () async {
        expect(predictor.isReady, isFalse);
        feed(1, t0 + 5000, audio[1], 8000);
        expect(predictor.isReady, isTrue);
        final buffered = await predictor.predict();
        final direct = await predictor.predictInputs(sensors: rows(1), audio: audio[1]);
        for (var j = 0; j < buffered.scores.length; j++) {
          expect(buffered.scores[j], closeTo(direct.scores[j], 1e-4));
        }
      });

      test('predicts the same from 48 kHz microphone input', () async {
        final streams = (ref['streams'] as List).cast<Map<String, dynamic>>();
        // only windows with sound before them: the resampler lags ~2 ms
        final withLead = [
          for (var k = 0; k < streams.length; k++)
            if ((streams[k]['lead_ms'] as num) > 0) k,
        ];
        expect(withLead.length, greaterThanOrEqualTo(3));
        for (final k in withLead) {
          predictor.reset();
          feed(k, t0 + 10000 * (k + 1), floats(streams[k]['audio_48k'] as String), 48000, chunk: 4096);
          final p = await predictor.predict();
          expect(p.index, pythonPredictions[k]);
          for (var j = 0; j < p.scores.length; j++) {
            expect((p.scores[j] - (python[k][j] as num)).abs(), lessThan(0.5));
          }
        }
      });

      test('takes 16-bit PCM bytes, as the record package delivers them', () async {
        final pcm = ByteData(audio[2].length * 2);
        for (var i = 0; i < audio[2].length; i++) {
          pcm.setInt16(i * 2, (audio[2][i] * 32768).round().clamp(-32768, 32767), Endian.little);
        }
        if (mixed) feed(2, t0 + 500, Float32List(0), 8000);
        predictor.addPcm16Bytes(pcm.buffer.asUint8List(), sampleRate: 8000, timestamp: t0 + 500);
        expect((await predictor.predict()).index, pythonPredictions[2]);
      });

      test('waits for enough sound', () async {
        feed(0, t0, audio[0].sublist(0, 1000), 8000);
        expect(predictor.isReady, isFalse);
        // like the sensor path, predict() throws right away when not ready
        expect(() => predictor.predict(), throwsA(isA<PredictorNotReadyException>()));
      });
    });
  }

  group('schema checks', () {
    test('sound models need a runtime with several inputs', () async {
      final p = await Predictor.fromBytes(
        Uint8List(0),
        File('test/fixtures/audio_only/manifest.json').readAsStringSync(),
        runtime: FakeRuntime(),
      );
      await expectLater(
        p.predictInputs(audio: Float32List(4000)),
        throwsA(isA<EdgeMLException>().having((e) => e.message, 'message', contains('MultiInputModel'))),
      );
      expect(() => p.predictWindow([]), throwsStateError);
    });

    test('sensor models refuse sound', () async {
      final p = await Predictor.fromBytes(
        File('test/fixtures/torch_cnn/model.pte').readAsBytesSync(),
        File('test/fixtures/torch_cnn/manifest.json').readAsStringSync(),
      );
      expect(p.takesSound, isFalse);
      expect(() => p.addAudio([0, 0], sampleRate: 16000), throwsStateError);
      await p.dispose();
    });
  });

  group('Resampler', () {
    Float32List tone(double freq, int rate, double seconds) => Float32List.fromList([
      for (var i = 0; i < (rate * seconds).round(); i++) math.sin(2 * math.pi * freq * i / rate),
    ]);
    double rms(List<double> xs) => math.sqrt(xs.fold(0.0, (a, x) => a + x * x) / xs.length);

    test('produces the same samples as the JavaScript library', () {
      final v = jsonDecode(File('test/fixtures/resampler_vector.json').readAsStringSync()) as Map<String, dynamic>;
      final input = floats(v['input'] as String);
      final expected = floats(v['output'] as String);
      final r = Resampler(v['inRate'] as int, v['outRate'] as int);
      final out = <double>[];
      for (var i = 0, n = 1; i < input.length; i += n, n = n * 7 % 997 + 1) {
        out.addAll(r.process(input.sublist(i, math.min(input.length, i + n))));
      }
      expect(out.length, expected.length);
      for (var i = 0; i < out.length; i++) {
        expect(out[i], closeTo(expected[i], 1e-5));
      }
    });

    test('keeps a tone in the passband and filters out what would alias', () {
      final kept = Resampler(48000, 16000).process(tone(1000, 48000, 1));
      expect(rms(kept.sublist(500, 15000)), closeTo(math.sqrt1_2, 0.01));
      final ideal = tone(1000, 16000, 1);
      for (var i = 500; i < 15000; i++) {
        expect(kept[i], closeTo(ideal[i], 0.01));
      }
      final aliased = Resampler(48000, 16000).process(tone(10000, 48000, 1));
      expect(rms(aliased.sublist(500, 15000)), lessThan(0.01));
    });

    test('mixes channels down', () {
      expect(downmix([1, 0, 0.5, 0.5, -1, 1], 2), [0.5, 0.5, 0]);
    });
  });
}
