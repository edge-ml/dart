import 'dart:convert';
import 'dart:typed_data';

import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response jsonResponse(Object? json, [int status = 200]) =>
    http.Response(jsonEncode(json), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> jsonDecodeMap(String json) => jsonDecode(json) as Map<String, dynamic>;

/// A recorded request to the fake server.
class Call {
  Call(this.method, this.path, this.query, this.body);
  final String method;
  final String path;
  final Map<String, String> query;
  final Object? body;
}

/// An in-memory edge-ml server: handlers by "METHOD /path".
class FakeServer {
  final calls = <Call>[];
  final handlers = <String, http.Response Function(Call)>{};

  void on(String route, Object? json, {int status = 200}) => handlers[route] = (_) => jsonResponse(json, status);

  void onBytes(String route, List<int> bytes) => handlers[route] = (_) => http.Response.bytes(bytes, 200);

  List<Call> callsTo(String route) => calls.where((c) => '${c.method} ${c.path}' == route).toList();

  late final client = MockClient((req) async {
    final call = Call(
      req.method,
      req.url.path,
      req.url.queryParameters,
      req.body.isEmpty ? null : jsonDecode(req.body),
    );
    calls.add(call);
    final handler = handlers['${req.method} ${req.url.path}'];
    if (handler == null) return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
    return handler(call);
  });

  EdgeML edgeml({String key = 'KEY', InferenceRuntime? runtime}) => EdgeML(
    apiKey: key,
    backendUrl: 'https://edge.test',
    httpClient: client,
    runtime: runtime ?? FakeRuntime(),
    modelCache: MemoryModelCache(),
  );
}

/// Records the inputs it gets and returns fixed [output].
class FakeRuntime implements InferenceRuntime {
  FakeRuntime([this.output = const [0.25, 0.75]]);
  List<double> output;
  final inputs = <List<List<double>>>[];
  final loaded = <Uint8List>[];
  int disposed = 0;

  @override
  Future<LoadedModel> load(Uint8List program) async {
    loaded.add(program);
    return _FakeModel(this);
  }
}

class _FakeModel implements LoadedModel {
  _FakeModel(this.runtime);
  final FakeRuntime runtime;

  @override
  Future<Float32List> run(Float32List input, List<int> shape) async {
    final rows = shape[1], cols = shape[2];
    runtime.inputs.add([
      for (var r = 0; r < rows; r++) [for (var c = 0; c < cols; c++) input[r * cols + c]],
    ]);
    return Float32List.fromList(runtime.output);
  }

  @override
  Future<void> dispose() async => runtime.disposed++;
}

String manifestJson({
  List<String> sensors = const ['a', 'b'],
  int size = 4,
  List<String> labels = const ['a', 'b'],
  String type = 'probabilities',
  String? format = 'executorch',
}) => jsonEncode({
  'schema_version': 1,
  'format': ?format,
  'model_name': 'm',
  'model_id': 'id1',
  'executorch': {'version': '1.0.0', 'backend': 'xnnpack'},
  'sampling_rate': 50.0,
  'window': {'size': size, 'stride': size ~/ 2, 'unit': 'samples'},
  'input': {
    'name': 'raw_window',
    'shape': [1, size, sensors.length],
    'timeseries': sensors,
  },
  'output': {
    'type': type,
    'shape': [1, labels.length],
    'labels': labels,
  },
  'classification_frequency_hint_hz': 25.0,
});

Future<(Predictor, FakeRuntime)> stubPredictor(List<String> sensors, int size, {String type = 'probabilities'}) async {
  final runtime = FakeRuntime();
  final predictor = await Predictor.fromBytes(
    Uint8List(4),
    manifestJson(sensors: sensors, size: size, type: type),
    runtime: runtime,
  );
  return (predictor, runtime);
}
