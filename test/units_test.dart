import 'dart:convert';

import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'unit_fixtures.dart';

const g = 9.80665;

/// x in m/s^2 (acceleration), y in degC (temperature), z in a custom unit "ue".
final inputUnits = jsonDecode(inputUnitsJson) as List;
final catalog = UnitCatalog.fromJson(jsonDecode(unitCatalogJson) as Map<String, dynamic>);

Future<(Predictor, FakeRuntime)> unitPredictor({Map<String, String> units = const {}, UnitCatalog? catalog}) =>
    stubPredictor(['x', 'y', 'z'], 2, inputUnits: inputUnits, units: units, catalog: catalog);

Matcher closeToRows(List<List<num>> rows) => pairwiseCompare<List<num>, List<double>>(rows, (expected, actual) {
  for (var i = 0; i < expected.length; i++) {
    if ((expected[i] - actual[i]).abs() > 1e-3) return false;
  }
  return true;
}, 'rows close to');

void main() {
  group('expected units from the manifest', () {
    test('ExecuTorch manifests', () async {
      final (predictor, _) = await unitPredictor();
      expect(
        [for (final u in predictor.inputUnits) (u.name, u.quantity, u.unit)],
        [('x', 'acceleration', 'm/s^2'), ('y', 'temperature', 'degC'), ('z', 'strain', 'ue')],
      );
      expect(predictor.inputUnits[0].conversions['g']!.scale, g);
      expect(predictor.manifest.inputUnits, predictor.inputUnits);
    });

    test('ONNX manifests have the same input.units', () {
      final onnxInput = {
        'name': 'raw_window',
        'shape': [1, 20, 3],
        'dtype': 'float32',
        'layout': 'window x channel',
        'timeseries': ['x', 'y', 'z'],
        'units': inputUnits,
      };
      final units = InputUnit.listFromManifestInput(onnxInput);
      expect(units.map((u) => u.unit), ['m/s^2', 'degC', 'ue']);
      expect(units[1].conversions['degF']!.apply(212), closeTo(100, 1e-9));
      expect(units[2].conversions, isEmpty);
    });

    test('models without units: every input unknown', () async {
      final (predictor, _) = await stubPredictor(['x', 'y'], 2);
      expect(predictor.inputUnits.map((u) => u.isKnown), [false, false]);
      expect(predictor.inputUnits.map((u) => u.name), ['x', 'y']);
    });
  });

  group('conversion', () {
    test('converts declared units to the expected units', () async {
      final (predictor, runtime) = await unitPredictor(units: {'x': 'g', 'y': 'degF', 'z': 'ue'});
      await predictor.predictWindow([
        [1, 212, 5],
        [-0.5, 32, 6],
      ]);
      expect(
        runtime.inputs.single,
        closeToRows([
          [g, 100, 5],
          [-g / 2, 0, 6],
        ]),
      );
    });

    test('converts buffered values too', () async {
      final (predictor, runtime) = await unitPredictor(units: {'x': 'mg', 'y': 'K'});
      predictor.addSample({'x': 1000, 'y': 273.15, 'z': 1}, timestamp: 0);
      predictor.addSample({'x': 0, 'y': 300, 'z': 2}, timestamp: 1);
      await predictor.predict();
      expect(
        runtime.inputs.single,
        closeToRows([
          [g, 0, 1],
          [0, 26.85, 2],
        ]),
      );
    });

    test('undeclared sensors and the expected unit pass through', () async {
      final (predictor, runtime) = await unitPredictor(units: {'x': 'm/s^2'});
      await predictor.predictWindow([
        [1, 2, 3],
        [4, 5, 6],
      ]);
      expect(runtime.inputs.single, [
        [1, 2, 3],
        [4, 5, 6],
      ]);
    });

    test('units of sensors the model does not use are ignored', () async {
      final (predictor, _) = await unitPredictor(units: {'gyroX': 'rad/s', 'x': 'g'});
      expect(predictor.inputUnits, hasLength(3));
    });

    test('setUnits replaces earlier declarations', () async {
      final (predictor, runtime) = await unitPredictor(units: {'x': 'g'});
      predictor.setUnits({'y': 'degF'});
      await predictor.predictWindow([
        [1, 32, 0],
        [1, 32, 0],
      ]);
      expect(runtime.inputs.single.first, [1, 0, 0]);
    });

    test('labels and aliases with the catalog', () async {
      expect(() => unitPredictor(units: {'y': '°F'}), throwsA(isA<UnitException>()));
      final (predictor, runtime) = await unitPredictor(units: {'x': 'm/s²', 'y': '°F'}, catalog: catalog);
      await predictor.predictWindow([
        [1, 212, 0],
        [1, 212, 0],
      ]);
      expect(runtime.inputs.single.first[0], 1);
      expect(runtime.inputs.single.first[1], closeTo(100, 1e-3));
    });
  });

  group('units the model cannot convert from', () {
    test('throw a UnitException listing the accepted units', () async {
      expect(
        () => unitPredictor(units: {'x': 'furlong'}),
        throwsA(
          isA<UnitException>().having(
            (e) => e.message,
            'message',
            "'x' is declared in 'furlong', but the model expects m/s^2 (acceleration) and cannot convert from "
                "'furlong'. Accepted units: m/s^2, g, mg, cm/s^2.",
          ),
        ),
      );
      expect(() => unitPredictor(units: {'x': 'degC'}), throwsA(isA<UnitException>()));
    });

    test('custom quantities only accept their own unit', () async {
      expect(
        () => unitPredictor(units: {'z': 'mm/m'}),
        throwsA(isA<UnitException>().having((e) => e.message, 'message', contains('Deliver it in ue'))),
      );
    });

    test('setUnits throws and keeps working afterwards', () async {
      final (predictor, _) = await unitPredictor();
      expect(() => predictor.setUnits({'y': 'rad'}), throwsA(isA<UnitException>()));
      expect(UnitException('x'), isA<EdgeMLException>());
    });
  });

  group('backwards compatibility', () {
    test('models without units ignore declared units', () async {
      final (predictor, runtime) = await stubPredictor(['x', 'y'], 1, units: {'x': 'g', 'y': 'degF'});
      await predictor.predictWindow([
        [1, 2],
      ]);
      expect(runtime.inputs.single, [
        [1, 2],
      ]);
    });

    test('inputs of unknown unit in a new manifest pass through', () async {
      final (predictor, runtime) = await stubPredictor(
        ['x'],
        1,
        inputUnits: [
          {'name': 'x', 'quantity': null, 'unit': '', 'conversions': <String, Object>{}},
        ],
        units: {'x': 'g'},
      );
      await predictor.predictWindow([
        [3],
      ]);
      expect(runtime.inputs.single, [
        [3],
      ]);
    });
  });

  group('server', () {
    late FakeServer server;
    late EdgeML edgeml;

    setUp(() {
      server = FakeServer();
      edgeml = server.edgeml();
    });

    test('collector sends units and keeps plain names plain', () async {
      server.on('POST /ds/api/dataset/init/KEY', {'id': 'D1'});
      server.on('POST /ds/api/dataset/append/KEY/D1', null);
      final collector = await edgeml.datasets.collector(
        'rec',
        ['plain', 'accX', 'temp', 'strain'],
        units: {'accX': 'g', 'temp': 'degF', 'strain': 'ue'},
        quantities: {'accX': 'acceleration', 'temp': 'temperature'},
      );
      expect((server.callsTo('POST /ds/api/dataset/init/KEY').single.body as Map)['timeSeries'], [
        'plain',
        {'name': 'accX', 'unit': 'g', 'quantity': 'acceleration'},
        {'name': 'temp', 'unit': 'degF', 'quantity': 'temperature'},
        {'name': 'strain', 'unit': 'ue', 'quantity': null},
      ]);
      collector.cancel();
    });

    test('collector without units sends names only', () async {
      server.on('POST /ds/api/dataset/init/KEY', {'id': 'D1'});
      final collector = await edgeml.datasets.collector('rec', ['a', 'b']);
      expect((server.calls.single.body as Map)['timeSeries'], ['a', 'b']);
      collector.cancel();
    });

    test('collector rejects units of unknown series', () async {
      expect(() => edgeml.datasets.collector('rec', ['a'], units: {'b': 'g'}), throwsA(isA<ArgumentError>()));
      expect(server.calls, isEmpty);
    });

    test('upload sends the units of recorded series', () async {
      server.on('POST /ds/api/dataset/init/KEY', {'id': 'D1'});
      server.on('POST /ds/api/dataset/append/KEY/D1', null);
      final rec = DatasetRecording(
        'r',
        units: {'accX': 'm/s^2', 'gyroX': 'rad/s'},
        quantities: {'accX': 'acceleration', 'gyroX': 'angular_velocity'},
      )..add('accX', 1, timestamp: 1);
      rec.add('other', 2, timestamp: 1);
      await edgeml.datasets.upload(rec);
      expect((server.callsTo('POST /ds/api/dataset/init/KEY').single.body as Map)['timeSeries'], [
        {'name': 'accX', 'unit': 'm/s^2', 'quantity': 'acceleration'},
        'other',
      ]);
    });

    test('datasets expose quantity next to unit', () async {
      server.on('GET /ds/api/project/KEY', {
        'labelings': <Object>[],
        'datasets': [
          {
            '_id': 'D1',
            'name': 'd',
            'timeSeries': [
              {'_id': 'T1', 'name': 'accX', 'unit': 'g', 'quantity': 'acceleration'},
              {'_id': 'T2', 'name': 'old', 'unit': 'raw'},
              {'_id': 'T3', 'name': 'blank', 'unit': '', 'quantity': ''},
            ],
          },
        ],
      });
      final [ds] = await edgeml.datasets.list();
      expect([for (final t in ds.timeSeries) (t.unit, t.quantity)], [('g', 'acceleration'), ('raw', null), ('', null)]);
    });

    test('model info exposes the expected unit per input', () async {
      server.on('GET /ml/device/KEY/models/M1', {
        'id': 'M1',
        'name': 'm',
        'trainStatus': 'done',
        'timeSeries': ['x', 'y', 'z'],
        'inputUnits': inputUnits,
      });
      server.on('GET /ml/device/KEY/models/M2', {
        'id': 'M2',
        'name': 'old',
        'trainStatus': 'done',
        'timeSeries': ['x'],
      });
      final info = await edgeml.models.get('M1');
      expect(info.inputUnits.map((u) => u.unit), ['m/s^2', 'degC', 'ue']);
      expect(info.inputUnits[0].quantity, 'acceleration');
      final old = await edgeml.models.get('M2');
      expect(old.inputUnits.single.isKnown, isFalse);
    });

    test('models.load converts with the declared units', () async {
      server.on('GET /ml/device/KEY/models/M1/executorch/manifest.json', {
        ...jsonDecodeMap(manifestJson(sensors: ['x', 'y', 'z'], size: 1, units: inputUnits)),
      });
      server.onBytes('GET /ml/device/KEY/models/M1/executorch/model.pte', [1, 2, 3]);
      final runtime = FakeRuntime();
      final client = server.edgeml(runtime: runtime);
      final predictor = await client.models.load('M1', units: {'x': 'g'});
      await predictor.predictWindow([
        [2, 0, 0],
      ]);
      expect(runtime.inputs.single.single.first, closeTo(2 * g, 1e-4));
      expect(() => client.models.load('M1', units: {'x': 'K'}), throwsA(isA<UnitException>()));
    });

    test('unitCatalog fetches the catalog without the key', () async {
      server.on('GET /ml/units/', jsonDecode(unitCatalogJson));
      final catalog = await edgeml.unitCatalog();
      final acc = catalog.quantity('acceleration')!;
      expect(acc.defaultUnit, 'm/s^2');
      expect(acc.unit('m/s²')!.id, 'm/s^2');
      expect(catalog.quantity('temperature')!.unit('°F')!.id, 'degF');
      expect(catalog.quantity('nope'), isNull);
    });
  });
}
