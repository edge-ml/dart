// End-to-end test against a real edge-ml server, skipped unless configured:
//
//   EDGEML_URL=https://beta.edge-ml.org EDGEML_KEY=<device api write key> flutter test test/live_test.dart
//
// Uploads two labeled datasets (one recorded in m/s^2, one in g), trains the
// small_cnn preset on them, then downloads the model and runs it with the real
// ExecuTorch runtime, feeding values in g.
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
