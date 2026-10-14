import 'dart:typed_data';

import 'package:executorch_flutter/executorch_flutter.dart';

import '../errors.dart';

/// Runs compiled models. The default is [ExecuTorchRuntime]; implement this
/// to use another runtime, or a fake one in tests.
abstract interface class InferenceRuntime {
  /// Loads a compiled model program.
  Future<LoadedModel> load(Uint8List program);
}

/// A model loaded by an [InferenceRuntime].
abstract interface class LoadedModel {
  /// Runs the model on one float32 [input] tensor of [shape] and returns its
  /// first output, flattened.
  Future<Float32List> run(Float32List input, List<int> shape);

  /// Frees the model's native memory.
  Future<void> dispose();
}

/// Runs ExecuTorch `.pte` programs with `executorch_flutter` (XNNPACK on
/// Android, iOS, macOS, Linux and Windows; WebAssembly on the web).
class ExecuTorchRuntime implements InferenceRuntime {
  /// Creates the runtime. [debugLogging] turns on the native library's
  /// verbose logs, which are off by default.
  ExecuTorchRuntime({this.debugLogging = false});

  /// Whether the native library logs every call (to stderr / logcat).
  final bool debugLogging;

  @override
  Future<LoadedModel> load(Uint8List program) async {
    // set on first use, not in the constructor, so creating a client never
    // loads the native library
    setNativeDebugLogging(debugLogging);
    try {
      return _ExecuTorchModel(await ExecuTorchModel.loadFromBytes(program));
    } on ExecuTorchException catch (e) {
      throw EdgeMLException('Could not load the model: ${e.message}');
    }
  }
}

class _ExecuTorchModel implements LoadedModel {
  _ExecuTorchModel(this._model);

  final ExecuTorchModel _model;

  @override
  Future<Float32List> run(Float32List input, List<int> shape) async {
    final List<TensorData> outputs;
    try {
      outputs = await _model.forward([
        TensorData(
          shape: shape,
          dataType: TensorType.float32,
          data: input.buffer.asUint8List(input.offsetInBytes, input.lengthInBytes),
        ),
      ]);
    } on ExecuTorchException catch (e) {
      throw EdgeMLException('Inference failed: ${e.message}');
    }
    final out = outputs.first;
    if (out.dataType != TensorType.float32) {
      throw EdgeMLException('Expected a float32 output, got ${out.dataType}');
    }
    // copy into a fresh (aligned) buffer: the output may be an unaligned view
    // on memory the runtime reuses
    final bytes = Uint8List.fromList(out.data);
    return bytes.buffer.asFloat32List(0, bytes.length ~/ 4);
  }

  @override
  Future<void> dispose() => _model.dispose();
}
