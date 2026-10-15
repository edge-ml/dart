import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toCsv writes the edge-ml CSV format', () {
    final rec = DatasetRecording('r', units: {'accX': 'g'});
    rec.startLabel('activity', 'walk', timestamp: 0);
    rec.addSample({'accX': 1, 'accY': 2}, timestamp: 0);
    rec.add('accX', 1.5, timestamp: 10); // accY has no value at t=10
    rec.startLabel('activity', 'run', timestamp: 20);
    rec.addSample({'accX': 3, 'accY': 4}, timestamp: 20);
    expect(rec.toCsv().trim().split('\n'), [
      'time,sensor_accX[g],sensor_accY,label_activity_walk,label_activity_run',
      '0,1.0,2.0,x,',
      '10,1.5,,x,',
      '20,3.0,4.0,,x',
    ]);
    expect(rec.length, 5);
  });

  test('labels: stopLabel, ranges, validation', () {
    final rec = DatasetRecording('r');
    rec.stopLabel('nothing open'); // no-op
    rec.startLabel('a', 'x', timestamp: 10);
    rec.stopLabel('a', timestamp: 5); // never ends before it starts
    expect(rec.labels, [const DatasetLabel('a', 'x', start: 10, end: 10)]);
    expect(() => rec.addLabel(const DatasetLabel('a', 'y', start: 5, end: 1)), throwsArgumentError);
  });

  test('labels of one labeling never overlap or touch (the server rejects that)', () {
    final rec = DatasetRecording('r');
    rec.startLabel('activity', 'walk', timestamp: 0);
    rec.startLabel('activity', 'run', timestamp: 10); // switch: walk ends 1 ms before
    rec.stopLabel('activity', timestamp: 20);
    rec.startLabel('activity', 'sit', timestamp: 20); // stop + start at the same time
    rec.startLabel('activity', 'walk', timestamp: 21); // switch within 1 ms of the start
    rec.startLabel('activity', 'run', timestamp: 21); // switch in the same ms
    rec.stopLabel('activity', timestamp: 30);
    rec.startLabel('posture', 'standing', timestamp: 5); // other labelings are independent
    rec.stopLabel('posture', timestamp: 15);

    final activity = rec.labels.where((l) => l.labeling == 'activity').toList()..sort((a, b) => a.start - b.start);
    expect(activity.map((l) => l.label), ['walk', 'run', 'sit', 'walk', 'run']);
    for (var i = 1; i < activity.length; i++) {
      expect(activity[i].start, greaterThan(activity[i - 1].end), reason: '${activity[i - 1]} / ${activity[i]}');
    }
    for (final l in activity) {
      expect(l.end, greaterThanOrEqualTo(l.start));
    }
    expect(activity.first, const DatasetLabel('activity', 'walk', start: 0, end: 9));
    expect(rec.labels.where((l) => l.labeling == 'posture').single.start, 5);
  });

  test('addLabel rejects overlapping ranges of the same labeling right away', () {
    final rec = DatasetRecording('r')..addLabel(const DatasetLabel('a', 'x', start: 0, end: 10));
    expect(() => rec.addLabel(const DatasetLabel('a', 'y', start: 10, end: 20)), throwsArgumentError);
    rec.addLabel(const DatasetLabel('a', 'y', start: 11, end: 20));
    rec.addLabel(const DatasetLabel('b', 'z', start: 0, end: 20)); // other labeling: fine
    expect(rec.labels.length, 3);
  });

  test('rejects non-finite values', () {
    expect(() => DatasetRecording('r').add('a', double.nan), throwsArgumentError);
  });
}
