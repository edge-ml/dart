// Runs a model exported by the edge-ml server through the real ExecuTorch
// runtime and compares it with PyTorch. Needs the native library, so it runs
// on desktop hosts (Linux/macOS/Windows), not in the browser.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const dir = 'test/fixtures/torch_cnn';
  final expected = jsonDecode(File('$dir/expected.json').readAsStringSync()) as Map<String, dynamic>;
  final windows = (expected['windows'] as List).cast<List>();
  final logits = (expected['logits'] as List).cast<List>();

  late Predictor predictor;

  setUpAll(() async {
    predictor = await Predictor.fromBytes(
      File('$dir/model.pte').readAsBytesSync(),
      File('$dir/manifest.json').readAsStringSync(),
    );
  });

  tearDownAll(() => predictor.dispose());

  test('matches PyTorch on the server export', () async {
    expect(predictor.timeSeries, ['x', 'y', 'z']);
    for (var i = 0; i < windows.length; i++) {
      final window = [for (final row in windows[i]) (row as List).cast<num>()];
      final p = await predictor.predictWindow(window);
      for (var j = 0; j < p.scores.length; j++) {
        expect(p.scores[j], closeTo((logits[i][j] as num).toDouble(), 1e-4));
      }
    }
  });

  test('buffered values give the same result as the window', () async {
    final window = [for (final row in windows[1]) (row as List).cast<num>()];
    predictor.reset();
    for (var r = 0; r < window.length; r++) {
      predictor.addValues(window[r], timestamp: r * 40);
    }
    final buffered = await predictor.predict();
    final direct = await predictor.predictWindow(window);
    expect(buffered.scores, direct.scores);
  });
}
