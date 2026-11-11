import 'dart:io';
import 'dart:typed_data';

import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const video = {
  '_id': 'M1',
  'kind': 'video',
  'name': 'front camera',
  'start': 2000,
  'end': 42000,
  'durationMs': 40000,
  'mimeType': 'video/mp4',
  'size': 4120902,
  'status': 'processing',
  'hasPeaks': false,
  'meta': {
    'container': 'mp4',
    'videoCodec': 'h264',
    'audioCodec': 'aac',
    'width': 640,
    'height': 360,
    'fps': 25.0,
    'sampleRate': 44100,
    'channels': 1,
  },
};

const audio = {
  '_id': 'M2',
  'kind': 'audio',
  'name': 'voice',
  'start': 500,
  'end': 3500,
  'durationMs': 3000,
  'mimeType': 'audio/mpeg',
  'size': 200637,
  'status': 'ready',
  'hasPeaks': true,
  'meta': {'container': 'mp3', 'videoCodec': null, 'audioCodec': 'mp3', 'sampleRate': 44100, 'channels': 1},
};

void main() {
  late FakeServer server;
  late EdgeML edgeml;

  setUp(() {
    server = FakeServer();
    edgeml = server.edgeml();
  });

  test('datasets list their recordings', () async {
    server.on('GET /ds/api/project/KEY', {
      'labelings': [],
      'datasets': [
        {
          '_id': 'D1',
          'name': 'walk-1',
          'timeSeries': [
            {'_id': 'T1', 'name': 'accX', 'start': 1000, 'end': 5000},
          ],
          'mediaSeries': [video, audio],
        },
        // from before recordings existed
        {'_id': 'D0', 'name': 'old', 'timeSeries': []},
      ],
    });
    final [ds, old] = await edgeml.datasets.list();
    expect(old.media, isEmpty);
    expect(old.start, isNull);

    final [cam, mic] = ds.media;
    expect(cam.kind, MediaKind.video);
    expect(cam.name, 'front camera');
    expect(cam.start, 2000);
    expect(cam.duration, const Duration(seconds: 40));
    expect(cam.end, 42000);
    expect(cam.mimeType, 'video/mp4');
    expect(cam.size, 4120902);
    expect(cam.isProcessing, isTrue);
    expect((cam.width, cam.height, cam.fps), (640, 360, 25.0));
    expect((cam.videoCodec, cam.audioCodec, cam.sampleRate, cam.channels), ('h264', 'aac', 44100, 1));

    expect(mic.kind, MediaKind.audio);
    expect(mic.isProcessing, isFalse);
    expect((mic.width, mic.videoCodec), (null, null));

    // the dataset spans its sensor data and its recordings
    expect((ds.start, ds.end), (500, 42000));
    expect('$ds', contains('2 recordings'));
  });

  test('uploadMediaBytes sends the file and its details as a form', () async {
    server.on('POST /ds/api/dataset/media/KEY/D1', audio, status: 201);
    final media = await edgeml.datasets.uploadMediaBytes(
      'D1',
      Uint8List.fromList('sound'.codeUnits),
      fileName: 'voice.mp3',
      start: 500,
      name: 'voice',
      kind: MediaKind.audio,
    );
    expect(media.id, 'M2');
    expect(media.duration, const Duration(seconds: 3));

    final body = server.calls.single.body as String;
    expect(body, contains('name="file"; filename="voice.mp3"'));
    expect(body, contains('sound'));
    expect(body, matches(RegExp(r'name="start"\s+500')));
    expect(body, matches(RegExp(r'name="name"\s+voice')));
    expect(body, matches(RegExp(r'name="kind"\s+audio')));
  });

  test('details that are not given are left to the server', () async {
    server.on('POST /ds/api/dataset/media/KEY/D1', audio, status: 201);
    await edgeml.datasets.uploadMediaBytes('D1', Uint8List.fromList([1, 2, 3]));
    final body = server.calls.single.body as String;
    expect(body, contains('filename="recording"'));
    expect(body, isNot(contains('name="start"')));
    expect(body, isNot(contains('name="kind"')));
  });

  test('uploadMediaFile reads the file at a path', () async {
    final dir = Directory.systemTemp.createTempSync('edgeml');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/walk.mp4')..writeAsStringSync('frames');
    server.on('POST /ds/api/dataset/media/KEY/D1', video, status: 201);
    final media = await edgeml.datasets.uploadMediaFile('D1', file.path, start: 2000);
    expect(media.kind, MediaKind.video);
    final body = server.calls.single.body as String;
    expect(body, contains('filename="walk.mp4"'));
    expect(body, contains('frames'));
  });

  test('a refused file reports the reason of the server', () async {
    server.on('POST /ds/api/dataset/media/KEY/D1', {
      'detail': 'This video format (avi/mpeg4) cannot be played in the browser.',
    }, status: 400);
    await expectLater(
      edgeml.datasets.uploadMediaBytes('D1', Uint8List.fromList([1])),
      throwsA(
        isA<EdgeMLException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', contains('cannot be played')),
      ),
    );
    server.on('POST /ds/api/dataset/media/KEY/NOPE', {'detail': 'Dataset not found'}, status: 404);
    await expectLater(
      edgeml.datasets.uploadMediaBytes('NOPE', Uint8List.fromList([1])),
      throwsA(isA<NotFoundException>()),
    );
  });

  test('bad arguments are rejected before anything is sent', () async {
    await expectLater(edgeml.datasets.uploadMediaBytes('', Uint8List.fromList([1])), throwsArgumentError);
    await expectLater(edgeml.datasets.uploadMediaBytes('D1', Uint8List(0)), throwsArgumentError);
    expect(server.calls, isEmpty);
  });

  test('create makes a dataset without time-series', () async {
    server.on('POST /ds/api/dataset/init/KEY', {'id': 'D9'});
    expect(await edgeml.datasets.create('interview', metadata: {'room': 'lab'}), 'D9');
    expect(server.calls.single.body, {
      'name': 'interview',
      'timeSeries': <Object>[],
      'metaData': {'room': 'lab'},
    });
  });

  test('downloadMedia returns the file', () async {
    server.onBytes('GET /ds/api/dataset/media/KEY/D1/M2', 'sound'.codeUnits);
    expect(await edgeml.datasets.downloadMedia('D1', 'M2'), 'sound'.codeUnits);
  });
}
