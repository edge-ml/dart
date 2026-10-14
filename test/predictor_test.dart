import 'dart:math' as math;

import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('windowing (same cases as the JS library)', () {
    test('aligns sensors with different timestamps like training', () async {
      final (predictor, runtime) = await stubPredictor(['a', 'b'], 4);
      predictor.addDatapoint('a', 0, timestamp: 0);
      predictor.addDatapoint('b', 10, timestamp: 1);
      predictor.addDatapoint('a', 2, timestamp: 2);
      predictor.addDatapoint('b', 30, timestamp: 3);
      await predictor.predict();
      // rows t=0..3: a = 0, (1), 2, (2) ; b = (10), 10, (20), 30
      expect(runtime.inputs.single, [
        [0, 10],
        [1, 10],
        [2, 20],
        [2, 30],
      ]);
    });

    test('treats a reading of 0 as a value', () async {
      final (predictor, runtime) = await stubPredictor(['a'], 3);
      for (final (t, v) in [(0, 5), (1, 0), (2, 5)]) {
        predictor.addDatapoint('a', v, timestamp: t);
      }
      await predictor.predict();
      expect(runtime.inputs.single, [
        [5],
        [0],
        [5],
      ]);
    });

    test('needs data for every sensor', () async {
      final (predictor, _) = await stubPredictor(['a', 'b'], 2);
      predictor.addDatapoint('a', 1, timestamp: 0);
      predictor.addDatapoint('a', 1, timestamp: 1);
      expect(predictor.isReady, isFalse);
      expect(
        predictor.predict,
        throwsA(isA<PredictorNotReadyException>().having((e) => e.message, 'message', contains("sensor 'b'"))),
      );
    });

    test('is not ready until a full window is buffered', () async {
      final (predictor, _) = await stubPredictor(['a'], 3);
      predictor.addDatapoint('a', 1, timestamp: 0);
      predictor.addDatapoint('a', 1, timestamp: 1);
      expect(predictor.isReady, isFalse);
      expect(predictor.predict, throwsA(isA<PredictorNotReadyException>()));
      predictor.addDatapoint('a', 1, timestamp: 2);
      expect(predictor.isReady, isTrue);
    });

    test('keeps memory bounded and predicts on the newest samples', () async {
      final (predictor, runtime) = await stubPredictor(['a'], 5);
      for (var t = 0; t < 10000; t++) {
        predictor.addDatapoint('a', t, timestamp: t);
      }
      await predictor.predict();
      expect(runtime.inputs.single, [
        [9995],
        [9996],
        [9997],
        [9998],
        [9999],
      ]);
    });

    test('reset drops buffered values', () async {
      final (predictor, _) = await stubPredictor(['a'], 1);
      predictor.addDatapoint('a', 1, timestamp: 0);
      predictor.reset();
      expect(predictor.isReady, isFalse);
    });
  });

  group('outputs', () {
    test('returns probabilities as-is', () async {
      final (predictor, _) = await stubPredictor(['a'], 1);
      predictor.addDatapoint('a', 1, timestamp: 0);
      final p = await predictor.predict();
      expect(p.label, 'b');
      expect(p.index, 1);
      expect(p.probabilities, [0.25, 0.75]);
      expect(p.confidence, 0.75);
      expect(p.byLabel, {'a': 0.25, 'b': 0.75});
    });

    test('softmaxes logits', () async {
      final (predictor, _) = await stubPredictor(['a'], 1, type: 'logits');
      final p = await predictor.predictWindow([
        [1],
      ]);
      final e = math.exp(0.5);
      expect(p.probabilities[1], closeTo(e / (1 + e), 1e-6));
      expect(p.scores, [0.25, 0.75]);
      expect(p.probabilities.reduce((a, b) => a + b), closeTo(1, 1e-9));
    });

    test('rejects a model whose outputs do not match the labels', () async {
      final (predictor, runtime) = await stubPredictor(['a'], 1);
      runtime.output = [1, 2, 3];
      expect(
        () => predictor.predictWindow([
          [1],
        ]),
        throwsA(isA<EdgeMLException>()),
      );
    });
  });

  group('input handling', () {
    test('addSample ignores sensors the model does not use', () async {
      final (predictor, runtime) = await stubPredictor(['a', 'b'], 1);
      predictor.addSample({'a': 1, 'b': 2, 'gyroX': 3}, timestamp: 0);
      await predictor.predict();
      expect(runtime.inputs.single, [
        [1, 2],
      ]);
    });

    test('addValues takes values in input order', () async {
      final (predictor, runtime) = await stubPredictor(['a', 'b'], 1);
      predictor.addValues([3, 4], timestamp: 0);
      await predictor.predict();
      expect(runtime.inputs.single, [
        [3, 4],
      ]);
      expect(() => predictor.addValues([1]), throwsArgumentError);
    });

    test('rejects unknown sensors, NaN and wrong window shapes', () async {
      final (predictor, _) = await stubPredictor(['a', 'b'], 2);
      expect(() => predictor.addDatapoint('c', 1), throwsArgumentError);
      expect(() => predictor.addDatapoint('a', double.nan), throwsArgumentError);
      expect(
        () => predictor.predictWindow([
          [1, 2],
        ]),
        throwsArgumentError,
      );
    });

    test('cannot be used after dispose', () async {
      final (predictor, runtime) = await stubPredictor(['a'], 1);
      await predictor.dispose();
      await predictor.dispose();
      expect(runtime.disposed, 1);
      expect(() => predictor.addDatapoint('a', 1), throwsStateError);
    });
  });
}
