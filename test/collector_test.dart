import 'dart:async';

import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fakes.dart';

void main() {
  late FakeServer server;
  late EdgeML edgeml;

  setUp(() {
    server = FakeServer();
    edgeml = server.edgeml();
    server.on('POST /ds/api/dataset/init/KEY', {'id': 'D'});
    server.on('POST /ds/api/dataset/append/KEY/D', null);
  });

  List<Map> appends() => server.callsTo('POST /ds/api/dataset/append/KEY/D').map((c) => c.body as Map).toList();

  test('uploads when the buffer is full and on complete, in order', () async {
    final c = await edgeml.datasets.collector(
      'rec',
      ['a', 'b'],
      maxBufferedValues: 4,
      uploadInterval: const Duration(hours: 1),
    );
    for (var t = 0; t < 10; t++) {
      c.add(t.isEven ? 'a' : 'b', t, timestamp: t);
    }
    await c.complete();
    final sent = [
      for (final a in appends())
        for (final ts in a['data'] as List)
          for (final p in ts['data'] as List) p[0],
    ];
    expect(sent..sort(), List.generate(10, (t) => t));
    expect(appends().length, 3); // 4 + 4 + 2
    expect(c.isCompleted, isTrue);
    expect(() => c.add('a', 1), throwsStateError);
  });

  test('uploads on the interval', () async {
    final c = await edgeml.datasets.collector('rec', ['a'], uploadInterval: const Duration(milliseconds: 20));
    c.add('a', 1, timestamp: 1);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(appends().length, 1);
    c.cancel();
  });

  test('labels are sent with complete; open labels close at the last timestamp', () async {
    final c = await edgeml.datasets.collector('rec', ['a'], wholeDatasetLabel: ('person', 'p1'));
    c.startLabel('activity', 'walk', timestamp: 0);
    c.add('a', 1, timestamp: 0);
    c.startLabel('activity', 'run', timestamp: 5); // closes walk
    c.add('a', 1, timestamp: 9);
    c.startLabel('posture', 'standing', timestamp: 2);
    c.stopLabel('posture', timestamp: 4);
    await c.complete();
    final last = appends().last;
    expect(last['data'], isEmpty);
    expect(last['labels'], [
      {'labelingName': 'activity', 'labelName': 'walk', 'start': 0, 'end': 5},
      {'labelingName': 'posture', 'labelName': 'standing', 'start': 2, 'end': 4},
      {'labelingName': 'activity', 'labelName': 'run', 'start': 5, 'end': 9},
    ]);
    expect(last['labeling'], {'labelingName': 'person', 'labelName': 'p1'});
  });

  test('a failed background upload is thrown by the next add', () async {
    server.on('POST /ds/api/dataset/append/KEY/D', {'detail': 'Unknown time-series'}, status: 400);
    final c = await edgeml.datasets.collector('rec', ['a'], maxBufferedValues: 1);
    c.add('a', 1);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(() => c.add('a', 2), throwsA(isA<EdgeMLException>().having((e) => e.statusCode, 'status', 400)));
    expect(c.isCompleted, isTrue);
  });

  test('uploads never overlap', () async {
    var inFlight = 0, maxInFlight = 0;
    final gate = Completer<void>();
    final slow = FakeServer()
      ..on('POST /ds/api/dataset/init/KEY', {'id': 'D'})
      ..on('POST /ds/api/dataset/append/KEY/D', null);
    // wrap the mock client to count concurrent appends
    final client = _CountingClient(
      slow.client,
      onStart: () {
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
      },
      onEnd: () => inFlight--,
      gate: gate.future,
    );
    final e = EdgeML(
      apiKey: 'KEY',
      backendUrl: 'https://edge.test',
      httpClient: client,
      runtime: FakeRuntime(),
      modelCache: MemoryModelCache(),
    );
    final c = await e.datasets.collector('rec', ['a'], maxBufferedValues: 1);
    for (var i = 0; i < 5; i++) {
      c.add('a', i, timestamp: i);
    }
    gate.complete();
    await c.complete();
    expect(maxInFlight, 1);
  });

  test('rejects unknown series and non-finite values', () async {
    final c = await edgeml.datasets.collector('rec', ['a']);
    expect(() => c.add('b', 1), throwsArgumentError);
    expect(() => c.add('a', double.infinity), throwsArgumentError);
    c.cancel();
  });
}

class _CountingClient extends http.BaseClient {
  _CountingClient(this.inner, {required this.onStart, required this.onEnd, required this.gate});
  final http.Client inner;
  final void Function() onStart, onEnd;
  final Future<void> gate;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!request.url.path.contains('/append/')) return inner.send(request);
    onStart();
    await gate;
    try {
      return await inner.send(request);
    } finally {
      onEnd();
    }
  }
}
