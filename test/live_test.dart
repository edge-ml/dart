// End-to-end test against a real edge-ml server, skipped unless configured:
//
//   EDGEML_URL=https://beta.edge-ml.org EDGEML_KEY=<device api write key> flutter test test/live_test.dart
//
// Uploads two labeled datasets, trains the small_cnn preset on them, then
// downloads the model and runs it with the real ExecuTorch runtime.
@TestOn('vm')
@Tags(['live'])
library;

import 'dart:io';
import 'dart:math';

import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final url = Platform.environment['EDGEML_URL'];
  final key = Platform.environment['EDGEML_KEY'];
  final skip = url == null || key == null ? 'set EDGEML_URL and EDGEML_KEY' : false;
  final run = DateTime.now().millisecondsSinceEpoch;
  final labeling = 'dart-live-$run';

  /// 50 Hz: 'wave' is a sine per axis, 'still' is small noise.
  DatasetRecording record(String name, int start) {
    final rng = Random(start);
    final rec = DatasetRecording(name, metadata: {'source': 'edge_ml_dart live test'});
    for (final (i, label) in [(0, 'wave'), (1, 'still')]) {
      final t0 = start + i * 20000;
      rec.addLabel(DatasetLabel(labeling, label, start: t0, end: t0 + 19980));
      for (var s = 0; s < 1000; s++) {
        final t = t0 + s * 20;
        rec.addSample({
          for (final (j, axis) in ['x', 'y', 'z'].indexed)
            axis: label == 'wave' ? sin(s / 5 + j) : rng.nextDouble() * 0.1,
        }, timestamp: t);
      }
    }
    return rec;
  }

  test(
    'upload, list, train, load and predict',
    () async {
      final edgeml = EdgeML(apiKey: key!, backendUrl: url!, modelCache: MemoryModelCache());
      final names = ['dart-live-$run-a', 'dart-live-$run-b'];
      await edgeml.datasets.upload(record(names[0], run));
      await edgeml.datasets.upload(record(names[1], run + 100000));

      final ds = await edgeml.datasets.get(names[0]);
      expect(ds.timeSeries.map((t) => t.name), ['x', 'y', 'z']);
      expect(ds.labels.map((l) => l.label), ['wave', 'still']);

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

      final predictor = await edgeml.models.load(model.id);
      expect(predictor.timeSeries, ['x', 'y', 'z']);
      for (var s = 0; s < predictor.windowSize; s++) {
        predictor.addSample({'x': sin(s / 5), 'y': sin(s / 5 + 1), 'z': sin(s / 5 + 2)}, timestamp: s * 20);
      }
      final p = await predictor.predict();
      expect(p.labels.toSet(), {'wave', 'still'});
      expect(p.probabilities.reduce((a, b) => a + b), closeTo(1, 1e-5));
      await predictor.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
