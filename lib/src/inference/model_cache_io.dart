import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'model_cache.dart';

ModelCache createDefaultCache() => FileModelCache();

/// Stores each model as `model.pte` + `manifest.json` in its own directory
/// under the app support directory (or [root]).
class FileModelCache implements ModelCache {
  /// Creates a cache in [root], default: `<app support dir>/edge_ml/models`.
  FileModelCache({Directory? root}) : _root = root;

  Directory? _root;

  Future<Directory> _dir() async =>
      _root ??= Directory('${(await getApplicationSupportDirectory()).path}/edge_ml/models');

  Future<Directory> _modelDir(String key) async =>
      Directory('${(await _dir()).path}/${key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}');

  @override
  Future<ModelFiles?> read(String key) async {
    final dir = await _modelDir(key);
    final pte = File('${dir.path}/model.pte');
    final manifest = File('${dir.path}/manifest.json');
    if (!await pte.exists() || !await manifest.exists()) return null;
    return ModelFiles(await pte.readAsBytes(), await manifest.readAsString());
  }

  @override
  Future<void> write(String key, ModelFiles files) async {
    final dir = await _modelDir(key);
    await dir.create(recursive: true);
    // manifest last: read() treats a model without manifest as not cached,
    // so an interrupted write is never read back half-written
    final manifest = File('${dir.path}/manifest.json');
    if (await manifest.exists()) await manifest.delete();
    await File('${dir.path}/model.pte').writeAsBytes(files.pte, flush: true);
    await manifest.writeAsString(files.manifestJson, flush: true);
  }

  @override
  Future<void> clear([String? key]) async {
    final dir = key == null ? await _dir() : await _modelDir(key);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
