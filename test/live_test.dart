// End-to-end test against a real edge-ml server, skipped unless configured:
//
//   EDGEML_URL=https://beta.edge-ml.org EDGEML_KEY=<device api write key> flutter test test/live_test.dart
//
// Uploads two labeled datasets (one recorded in m/s^2, one in g), trains the
// small_cnn preset on them, then downloads the model and runs it with the real
// ExecuTorch runtime, feeding values in g. A second test adds a recording
// (a generated WAV file) to a dataset; it needs a server with media support.
@TestOn('vm')
@Tags(['live'])
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final url = Platform.environment['EDGEML_URL'];
  final key = Platform.environment['EDGEML_KEY'];
  final skip = url == null || key == null ? 'set EDGEML_URL and EDGEML_KEY' : false;
  final run = DateTime.now().millisecondsSinceEpoch;
  final labeling = 'dart-live-$run';

  const g = 9.80665;
  const axes = ['x', 'y', 'z'];

  /// 50 Hz: 'wave' is a sine per axis, 'still' is small noise; in m/s^2, or
  /// in g if [inG].
  DatasetRecording record(String name, int start, {bool inG = false}) {
    final rng = Random(start);
    final rec = DatasetRecording(
      name,
      metadata: {'source': 'edge_ml_dart live test'},
      units: {for (final a in axes) a: inG ? 'g' : 'm/s^2'},
      quantities: {for (final a in axes) a: 'acceleration'},
    );
    for (final (i, label) in [(0, 'wave'), (1, 'still')]) {
      final t0 = start + i * 20000;
      // back-to-back labels, the way an app switches them while recording
      rec.startLabel(labeling, label, timestamp: t0);
      for (var s = 0; s < 1000; s++) {
        final t = t0 + s * 20;
        rec.addSample({
          for (final (j, axis) in axes.indexed)
            axis: (label == 'wave' ? 5 * sin(s / 5 + j) : rng.nextDouble() * 0.5) / (inG ? g : 1),
        }, timestamp: t);
      }
    }
    return rec;
  }

  /// A mono 16-bit WAV file with a 440 Hz tone.
  Uint8List wav(Duration length, {int sampleRate = 8000}) {
    final samples = sampleRate * length.inMilliseconds ~/ 1000;
    final data = ByteData(44 + samples * 2);
    void tag(int offset, String s) {
      for (final (i, c) in s.codeUnits.indexed) {
        data.setUint8(offset + i, c);
      }
    }

    tag(0, 'RIFF');
    data.setUint32(4, 36 + samples * 2, Endian.little);
    tag(8, 'WAVEfmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little); // PCM
    data.setUint16(22, 1, Endian.little); // mono
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    data.setUint32(40, samples * 2, Endian.little);
    for (var i = 0; i < samples; i++) {
      data.setInt16(44 + i * 2, (12000 * sin(2 * pi * 440 * i / sampleRate)).round(), Endian.little);
    }
    return data.buffer.asUint8List();
  }

  test(
    'audio recordings: upload, list, download',
    () async {
      final edgeml = EdgeML(apiKey: key!, backendUrl: url!, modelCache: MemoryModelCache());
      addTearDown(edgeml.close);
      final start = run - 60000;
      final sound = wav(const Duration(seconds: 3));

      // next to sensor data, from memory
      final rec = DatasetRecording('dart-live-$run-media', metadata: {'source': 'edge_ml_dart live test'});
      for (var s = 0; s < 100; s++) {
        rec.addSample({'x': sin(s / 5)}, timestamp: start + s * 20);
      }
      final withData = await edgeml.datasets.upload(rec);
      final fromBytes = await edgeml.datasets.uploadMediaBytes(
        withData,
        sound,
        fileName: 'tone.wav',
        name: 'microphone',
        start: start + 1000,
        kind: MediaKind.audio,
      );
      expect(fromBytes.kind, MediaKind.audio);
      expect(fromBytes.name, 'microphone');
      expect(fromBytes.start, start + 1000);
      expect(fromBytes.duration.inMilliseconds, closeTo(3000, 50));
      expect(fromBytes.mimeType, 'audio/wav');
      expect((fromBytes.sampleRate, fromBytes.channels), (8000, 1));

      // in a dataset of its own, from a file; the server picks name and start
      final dir = Directory.systemTemp.createTempSync('edgeml_live');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/interview.wav')..writeAsBytesSync(sound);
      final mediaOnly = await edgeml.datasets.create('dart-live-$run-media-only');
      final fromFile = await edgeml.datasets.uploadMediaFile(mediaOnly, file.path);
      expect(fromFile.name, 'interview');

      final listed = await edgeml.datasets.get(withData);
      expect(listed.media.map((m) => m.id), [fromBytes.id]);
      expect(listed.start, start);
      expect(listed.end, start + 1000 + fromBytes.duration.inMilliseconds);
      final only = await edgeml.datasets.get(mediaOnly);
      expect(only.timeSeries, isEmpty);
      expect(only.media.single.id, fromFile.id);
      expect(only.start, fromFile.start);

      expect(await edgeml.datasets.downloadMedia(withData, fromBytes.id), sound);

      // the server looks at the content, not at the file name
      await expectLater(
        edgeml.datasets.uploadMediaBytes(withData, Uint8List.fromList('not a recording'.codeUnits), fileName: 'x.wav'),
        throwsA(isA<EdgeMLException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
      await expectLater(
        edgeml.datasets.uploadMediaBytes(withData, sound, kind: MediaKind.video),
        throwsA(isA<EdgeMLException>().having((e) => e.message, 'message', contains('audio, not video'))),
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'upload, list, train, load and predict',
    () async {
      // starting training checks the real data first, which can take over a minute
      final edgeml = EdgeML(
        apiKey: key!,
        backendUrl: url!,
        modelCache: MemoryModelCache(),
        timeout: const Duration(minutes: 3),
      );
      final names = ['dart-live-$run-a', 'dart-live-$run-b'];
      await edgeml.datasets.upload(record(names[0], run));
      await edgeml.datasets.upload(record(names[1], run + 100000, inG: true));

      final ds = await edgeml.datasets.get(names[0]);
      expect(ds.timeSeries.map((t) => t.name), ['x', 'y', 'z']);
      expect(ds.timeSeries.map((t) => (t.quantity, t.unit)).toSet(), {('acceleration', 'm/s^2')});
      final inG = await edgeml.datasets.get(names[1]);
      expect(inG.timeSeries.map((t) => (t.quantity, t.unit)).toSet(), {('acceleration', 'g')});
      expect((await edgeml.unitCatalog()).quantity('acceleration')!.defaultUnit, 'm/s^2');
      expect(ds.labels.map((l) => l.label), ['wave', 'still']);
      expect(ds.labels[1].start, ds.labels[0].end + 1); // adjacent, not overlapping

      expect((await edgeml.models.presets()).map((p) => p.id), contains(Presets.smallCnn));
      final model = await edgeml.models.train(
        name: 'dart-live-$run',
        labeling: labeling,
        preset: Presets.smallCnn,
        datasets: names,
        steps: {
          'classifier': const StepOverride(parameters: {'epochs': 5}),
        },
        timeout: const Duration(minutes: 10),
      );
      expect(model.runsOnDevice, isTrue);
      expect(model.preset, Presets.smallCnn);
      // trained on both datasets, converted to the default unit
      expect(model.inputUnits.map((u) => (u.name, u.quantity, u.unit)), [
        for (final a in axes) (a, 'acceleration', 'm/s^2'),
      ]);

      final predictor = await edgeml.models.load(model.id, units: {for (final a in axes) a: 'g'});
      expect(predictor.timeSeries, ['x', 'y', 'z']);
      expect(predictor.inputUnits.map((u) => u.unit), ['m/s^2', 'm/s^2', 'm/s^2']);
      final window = [
        for (var s = 0; s < predictor.windowSize; s++) [for (var j = 0; j < 3; j++) 5 * sin(s / 5 + j)],
      ];
      for (final (s, row) in window.indexed) {
        predictor.addValues([for (final v in row) v / g], timestamp: s * 20);
      }
      final p = await predictor.predict();
      expect(p.labels.toSet(), {'wave', 'still'});
      expect(p.probabilities.reduce((a, b) => a + b), closeTo(1, 1e-5));

      // values in g, declared as g, give the same result as m/s^2 as they are
      predictor.setUnits({});
      final direct = await predictor.predictWindow(window);
      for (var j = 0; j < p.scores.length; j++) {
        expect(p.scores[j], closeTo(direct.scores[j], 1e-3));
      }
      expect(() => predictor.setUnits({'x': 'degC'}), throwsA(isA<UnitException>()));
      await predictor.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
