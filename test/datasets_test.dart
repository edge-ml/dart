import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const project = {
  'labelings': [
    {
      '_id': 'L1',
      'name': 'activity',
      'labels': [
        {'_id': 'walk', 'name': 'walk', 'color': '#ff0000'},
        {'_id': 'run', 'name': 'run', 'color': '#00ff00'},
      ],
    },
  ],
  'datasets': [
    {
      '_id': 'D1',
      'name': 'walk-1',
      'metaData': {'device': 'phone'},
      'timeSeries': [
        {
          '_id': 'T1',
          'name': 'accX',
          'unit': 'g',
          'start': 1000,
          'end': 5000,
          'length': 5,
          'samplingRate': {'mean': 1.0, 'var': 0.0},
        },
        {'_id': 'T2', 'name': 'accY', 'start': 9223372036854775807, 'end': -1},
      ],
      'labelings': [
        {
          'labelingId': 'L1',
          'labels': [
            {'_id': 'x2', 'start': 3000, 'end': 5000, 'type': 'run'},
            {'_id': 'x1', 'start': 1000, 'end': 2999, 'type': 'walk'},
          ],
        },
      ],
    },
  ],
};

void main() {
  late FakeServer server;
  late EdgeML edgeml;

  setUp(() {
    server = FakeServer();
    edgeml = server.edgeml();
  });

  test('list resolves labels to names and parses time-series', () async {
    server.on('GET /ds/api/project/KEY', project);
    final [ds] = await edgeml.datasets.list();
    expect(ds.name, 'walk-1');
    expect(ds.metadata, {'device': 'phone'});
    expect(ds.labels, [
      const DatasetLabel('activity', 'walk', start: 1000, end: 2999),
      const DatasetLabel('activity', 'run', start: 3000, end: 5000),
    ]);
    final [accX, accY] = ds.timeSeries;
    expect((accX.unit, accX.samplingRate, accX.length), ('g', 1.0, 5));
    expect((accY.start, accY.end), (null, null)); // empty series sentinel values
    expect((ds.start, ds.end), (1000, 5000));
  });

  test('get finds a dataset by id or name', () async {
    server.on('GET /ds/api/project/KEY', project);
    expect((await edgeml.datasets.get('D1')).name, 'walk-1');
    expect((await edgeml.datasets.get('walk-1')).id, 'D1');
    await expectLater(edgeml.datasets.get('nope'), throwsA(isA<NotFoundException>()));
  });

  test('labelings', () async {
    server.on('GET /ds/api/project/KEY', project);
    final [labeling] = await edgeml.datasets.labelings();
    expect(labeling.name, 'activity');
    expect(labeling.labels.map((l) => l.name), ['walk', 'run']);
  });

  test('upload sends the data and labels, chunked', () async {
    server.on('POST /ds/api/dataset/init/KEY', {'id': 'NEW'});
    server.on('POST /ds/api/dataset/append/KEY/NEW', null);
    final rec = DatasetRecording('walk-2', metadata: {'k': 'v'});
    for (var t = 0; t < DatasetsApi.uploadChunkSize + 10; t++) {
      rec.addSample({'accX': t, 'accY': -t}, timestamp: t);
    }
    rec.addLabel(const DatasetLabel('activity', 'walk', start: 0, end: 99));
    rec.startLabel('activity', 'run', timestamp: 100);

    expect(await edgeml.datasets.upload(rec, wholeDatasetLabel: ('place', 'home')), 'NEW');

    final init = server.callsTo('POST /ds/api/dataset/init/KEY').single.body as Map;
    expect(init, {
      'name': 'walk-2',
      'timeSeries': ['accX', 'accY'],
      'metaData': {'k': 'v'},
    });
    final appends = server.callsTo('POST /ds/api/dataset/append/KEY/NEW').map((c) => c.body as Map).toList();
    final sent = <String, int>{};
    for (final a in appends) {
      for (final ts in a['data'] as List) {
        sent.update(
          ts['name'] as String,
          (n) => n + (ts['data'] as List).length,
          ifAbsent: () => (ts['data'] as List).length,
        );
      }
      final size = (a['data'] as List).fold<int>(0, (n, ts) => n + (ts['data'] as List).length);
      expect(size, lessThanOrEqualTo(DatasetsApi.uploadChunkSize));
    }
    expect(sent, {'accX': DatasetsApi.uploadChunkSize + 10, 'accY': DatasetsApi.uploadChunkSize + 10});
    // labels only with the last request; the open label closes at the last timestamp
    expect(appends.take(appends.length - 1).every((a) => (a['labels'] as List).isEmpty), isTrue);
    expect(appends.last['labels'], [
      {'labelingName': 'activity', 'labelName': 'walk', 'start': 0, 'end': 99},
      {'labelingName': 'activity', 'labelName': 'run', 'start': 100, 'end': DatasetsApi.uploadChunkSize + 9},
    ]);
    expect(appends.last['labeling'], {'labelingName': 'place', 'labelName': 'home'});
    expect((appends.first['data'] as List).first['data'].first, [0, 0.0]);
  });

  test('server errors become typed exceptions with the server message', () async {
    server.on('POST /ds/api/dataset/init/KEY', {'detail': 'Used Api Key does not grant write access'}, status: 401);
    final rec = DatasetRecording('x')..add('a', 1);
    await expectLater(
      edgeml.datasets.upload(rec),
      throwsA(isA<AuthenticationException>().having((e) => e.message, 'message', contains('write access'))),
    );
  });

  test('upload rejects an empty recording', () async {
    await expectLater(edgeml.datasets.upload(DatasetRecording('x')), throwsArgumentError);
  });
}
