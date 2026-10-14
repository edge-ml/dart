import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('parses an executorch manifest', () {
    final m = ModelManifest.parse(manifestJson(sensors: ['x', 'y', 'z'], size: 20, labels: ['walk', 'run']));
    expect(m.timeSeries, ['x', 'y', 'z']);
    expect(m.windowSize, 20);
    expect(m.windowStride, 10);
    expect(m.labels, ['walk', 'run']);
    expect(m.samplingRate, 50);
    expect(m.classificationFrequencyHz, 25);
    expect(m.executorchVersion, '1.0.0');
  });

  test('accepts manifests exported before the format field', () {
    expect(ModelManifest.parse(manifestJson(format: null)).labels, ['a', 'b']);
  });

  test('rejects other formats, schema versions and broken JSON', () {
    expect(() => ModelManifest.parse(manifestJson(format: 'onnx')), throwsA(isA<EdgeMLException>()));
    expect(() => ModelManifest.parse('{"schema_version": 2}'), throwsA(isA<EdgeMLException>()));
    expect(() => ModelManifest.parse('{"schema_version": 1}'), throwsA(isA<EdgeMLException>()));
    expect(() => ModelManifest.parse('nope'), throwsA(isA<EdgeMLException>()));
  });
}
