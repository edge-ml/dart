// Runs on a real device, emulator, simulator or browser:
//
//   flutter test integration_test/device_test.dart -d <device>
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/device_test.dart -d web-server   # Chrome
//
// Checks that the example app starts, that a model exported by the edge-ml
// server runs on this platform's ExecuTorch runtime with the same results as
// PyTorch on the server, and that declared sensor units are converted to the
// units the model expects before it runs.
import 'dart:convert';

import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:edge_ml_example/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const fixture = 'integration_test/fixtures/torch_cnn';
const g = 9.80665;

/// `input.units` as the edge-ml server writes them for a model trained on x in
/// m/s^2 (acceleration), y in degC (temperature) and z of unknown unit.
const inputUnits = [
  {
    'name': 'x',
    'quantity': 'acceleration',
    'unit': 'm/s^2',
    'conversions': {
      'm/s^2': {'scale': 1.0, 'offset': 0.0},
      'g': {'scale': g, 'offset': 0.0},
      'mg': {'scale': g / 1000, 'offset': 0.0},
      'cm/s^2': {'scale': 0.01, 'offset': 0.0},
    },
  },
  {
    'name': 'y',
    'quantity': 'temperature',
    'unit': 'degC',
    'conversions': {
      'degC': {'scale': 1.0, 'offset': 0.0},
      'K': {'scale': 1.0, 'offset': -273.15},
      'degF': {'scale': 5 / 9, 'offset': -160 / 9},
    },
  },
  {'name': 'z', 'quantity': null, 'unit': '', 'conversions': <String, Object>{}},
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the example app starts on the connect screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();
    expect(find.text('Connect to edge-ml'), findsOneWidget);
    expect(find.text(EdgeML.defaultBackendUrl), findsOneWidget);
  });

  group('on-device ExecuTorch runtime', () {
    late Predictor predictor;
    late List<List<List<num>>> windows;
    late List<List<num>> logits;

    setUpAll(() async {
      final expected = jsonDecode(await rootBundle.loadString('$fixture/expected.json')) as Map<String, dynamic>;
      windows = [
        for (final w in expected['windows'] as List) [for (final row in w as List) (row as List).cast<num>()],
      ];
      logits = [for (final l in expected['logits'] as List) (l as List).cast<num>()];
      final pte = (await rootBundle.load('$fixture/model.pte')).buffer.asUint8List();
      predictor = await Predictor.fromBytes(pte, await rootBundle.loadString('$fixture/manifest.json'));
    });

    tearDownAll(() => predictor.dispose());

    testWidgets('matches PyTorch on the server export', (tester) async {
      expect(predictor.timeSeries, ['x', 'y', 'z']);
      for (var i = 0; i < windows.length; i++) {
        final p = await predictor.predictWindow(windows[i]);
        for (var j = 0; j < p.scores.length; j++) {
          expect(p.scores[j], closeTo(logits[i][j].toDouble(), 1e-4), reason: 'window $i, output $j');
        }
        expect(p.probabilities.reduce((a, b) => a + b), closeTo(1, 1e-5));
      }
    });

    testWidgets('buffered samples give the same prediction as the window', (tester) async {
      predictor.reset();
      final window = windows[1];
      for (var r = 0; r < window.length; r++) {
        predictor.addValues(window[r], timestamp: r * 40);
      }
      expect(predictor.isReady, isTrue);
      final buffered = await predictor.predict();
      final direct = await predictor.predictWindow(window);
      expect(buffered.scores, direct.scores);
      expect(buffered.label, direct.label);
    });
  });

  group('sensor units on the device', () {
    late Predictor predictor;
    late List<List<List<num>>> windows;
    late List<List<num>> logits;

    setUpAll(() async {
      final expected = jsonDecode(await rootBundle.loadString('$fixture/expected.json')) as Map<String, dynamic>;
      windows = [
        for (final w in expected['windows'] as List) [for (final row in w as List) (row as List).cast<num>()],
      ];
      logits = [for (final l in expected['logits'] as List) (l as List).cast<num>()];
      final manifest = jsonDecode(await rootBundle.loadString('$fixture/manifest.json')) as Map<String, dynamic>;
      (manifest['input'] as Map<String, dynamic>)['units'] = inputUnits;
      final pte = (await rootBundle.load('$fixture/model.pte')).buffer.asUint8List();
      predictor = await Predictor.fromBytes(pte, jsonEncode(manifest), units: {'x': 'g', 'y': 'degF', 'z': 'g'});
    });

    tearDownAll(() => predictor.dispose());

    testWidgets('values in g and degF give the same results as in m/s^2 and degC', (tester) async {
      expect(predictor.inputUnits.map((u) => u.unit), ['m/s^2', 'degC', '']);
      for (var i = 0; i < windows.length; i++) {
        // the same window as delivered by a sensor in g and °F; z is unknown
        // to the model, so it goes in unchanged
        final delivered = [
          for (final [x, y, z] in windows[i]) [x / g, y * 9 / 5 + 32, z],
        ];
        final p = await predictor.predictWindow(delivered);
        for (var j = 0; j < p.scores.length; j++) {
          expect(p.scores[j], closeTo(logits[i][j].toDouble(), 1e-3), reason: 'window $i, output $j');
        }
      }
    });

    testWidgets('a unit the model cannot convert from is an error', (tester) async {
      expect(() => predictor.setUnits({'x': 'degC'}), throwsA(isA<UnitException>()));
    });
  });
}
