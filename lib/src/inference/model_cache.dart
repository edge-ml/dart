import 'dart:typed_data';

import 'model_cache_io.dart' if (dart.library.js_interop) 'model_cache_web.dart' as platform;

/// A downloaded model: the ExecuTorch program and its manifest.
class ModelFiles {
  /// Creates [ModelFiles].
  const ModelFiles(this.pte, this.manifestJson);

  /// The compiled `.pte` program.
  final Uint8List pte;

  /// The `manifest.json` text.
  final String manifestJson;
}

/// Stores downloaded models so [ModelsApi.load] works offline after the first
/// download.
abstract interface class ModelCache {
  /// The default cache: files under the app support directory on native
  /// platforms, memory on the web.
  factory ModelCache.platformDefault() => platform.createDefaultCache();

  /// The cached files for [key], or null.
  Future<ModelFiles?> read(String key);

  /// Stores [files] under [key].
  Future<void> write(String key, ModelFiles files);

  /// Removes [key], or everything if [key] is null.
  Future<void> clear([String? key]);
}

/// Keeps models in memory for the lifetime of the app.
class MemoryModelCache implements ModelCache {
  final _files = <String, ModelFiles>{};

  @override
  Future<ModelFiles?> read(String key) async => _files[key];

  @override
  Future<void> write(String key, ModelFiles files) async => _files[key] = files;

  @override
  Future<void> clear([String? key]) async => key == null ? _files.clear() : _files.remove(key);
}
