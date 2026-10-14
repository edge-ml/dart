import 'dart:typed_data';

import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Map<String, Object?> model(
  String status, {
  List<String> formats = const ['EXECUTORCH'],
  String? error,
  int? progress,
}) => {
  'id': 'M1',
  'name': 'm',
  'trainStatus': status,
  'stage': 'Training',
  'progress': progress,
  'error': error,
  'formats': formats,
  'preset': 'small_cnn',
  'labels': ['walk', 'run'],
  'timeSeries': ['a', 'b'],
  'samplingRate': 50.0,
  'metrics': null,
};

void main() {
  late FakeServer server;
  late EdgeML edgeml;
  late FakeRuntime runtime;

  setUp(() {
    server = FakeServer();
    runtime = FakeRuntime();
    edgeml = server.edgeml(runtime: runtime);
  });

  test('presets', () async {
    server.on('GET /ml/device/KEY/presets', [
      {'id': 'small_cnn', 'name': 'Small CNN', 'description': 'd', 'pipeline': {}},
    ]);
    final [p] = await edgeml.models.presets();
    expect((p.id, p.name), (Presets.smallCnn, 'Small CNN'));
  });

  test('startTraining sends the compact request with the default preset', () async {
    server.on('POST /ml/device/KEY/train', {
      'id': 'M1',
      'warnings': ['few windows'],
    });
    final started = await edgeml.models.startTraining(
      name: 'm',
      labeling: 'activity',
      datasets: ['walk-1'],
      steps: {
        'windowing': const StepOverride(parameters: {'window_size': 100}),
      },
    );
    expect(started.modelId, 'M1');
    expect(started.warnings, ['few windows']);
    expect(server.calls.single.body, {
      'name': 'm',
      'labeling': 'activity',
      'preset': 'medium_cnn',
      'datasets': ['walk-1'],
      'disabledLabels': [],
      'useZeroClass': false,
      'pipeline': {
        'windowing': {
          'parameters': {'window_size': 100},
        },
      },
    });
  });

  test('train waits for the model and reports progress and warnings', () async {
    server.on('POST /ml/device/KEY/train', {
      'id': 'M1',
      'warnings': ['w'],
    });
    final states = [model('waiting'), model('training', progress: 50), model('done')];
    server.handlers['GET /ml/device/KEY/models/M1'] = (_) => jsonResponse(states.removeAt(0));
    final progress = <TrainStatus>[];
    final warnings = <String>[];
    final m = await edgeml.models.train(
      name: 'm',
      labeling: 'activity',
      preset: Presets.smallCnn,
      onProgress: (m) => progress.add(m.status),
      onWarning: warnings.add,
      interval: Duration.zero,
    );
    expect(m.runsOnDevice, isTrue);
    expect(progress, [TrainStatus.waiting, TrainStatus.training, TrainStatus.done]);
    expect(warnings, ['w']);
  });

  test('train throws TrainingException when training fails or times out', () async {
    server.on('POST /ml/device/KEY/train', {'id': 'M1', 'warnings': []});
    server.on('GET /ml/device/KEY/models/M1', model('error', error: 'boom'));
    await expectLater(
      edgeml.models.train(name: 'm', labeling: 'a', interval: Duration.zero),
      throwsA(isA<TrainingException>().having((e) => e.message, 'message', contains('boom'))),
    );
    server.on('GET /ml/device/KEY/models/M1', model('training'));
    await expectLater(
      edgeml.models.waitForModel('M1', interval: Duration.zero, timeout: Duration.zero),
      throwsA(isA<TrainingException>()),
    );
  });

  test('watch emits until done', () async {
    final states = [model('training'), model('done')];
    server.handlers['GET /ml/device/KEY/models/M1'] = (_) => jsonResponse(states.removeAt(0));
    final seen = await edgeml.models.watch('M1', interval: Duration.zero).map((m) => m.status).toList();
    expect(seen, [TrainStatus.training, TrainStatus.done]);
  });

  test('load downloads once, then uses the cache', () async {
    server.on('GET /ml/device/KEY/models/M1/executorch/manifest.json', jsonDecodeMap(manifestJson()));
    server.onBytes('GET /ml/device/KEY/models/M1/executorch/model.pte', [1, 2, 3]);
    final p1 = await edgeml.models.load('M1');
    final p2 = await edgeml.models.load('M1');
    expect(p1.labels, ['a', 'b']);
    expect(p2.windowSize, 4);
    expect(server.callsTo('GET /ml/device/KEY/models/M1/executorch/model.pte').length, 1);
    expect(runtime.loaded.map((b) => b.toList()), [
      [1, 2, 3],
      [1, 2, 3],
    ]);
    await edgeml.models.load('M1', forceDownload: true);
    expect(server.callsTo('GET /ml/device/KEY/models/M1/executorch/model.pte').length, 2);
    await edgeml.models.clearCache('M1');
    await edgeml.models.load('M1');
    expect(server.callsTo('GET /ml/device/KEY/models/M1/executorch/model.pte').length, 3);
  });

  test('load explains why a model cannot run on the device', () async {
    server.on('GET /ml/device/KEY/models/M1/executorch/manifest.json', {
      'detail': 'This model cannot be exported to ExecuTorch. Train it with one of the presets.',
    }, status: 400);
    await expectLater(
      edgeml.models.load('M1'),
      throwsA(isA<EdgeMLException>().having((e) => e.message, 'message', contains('presets'))),
    );
  });

  test('Predictor.fromBytes works without a server', () async {
    final p = await Predictor.fromBytes(Uint8List(1), manifestJson(sensors: ['x']), runtime: runtime);
    expect(p.timeSeries, ['x']);
  });
}
