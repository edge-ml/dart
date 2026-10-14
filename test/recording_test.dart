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
      '20,3.0,4.0,x,x',
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

  test('rejects non-finite values', () {
    expect(() => DatasetRecording('r').add('a', double.nan), throwsArgumentError);
  });
}
