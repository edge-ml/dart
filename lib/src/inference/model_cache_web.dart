import 'model_cache.dart';

/// No file system on the web: keep models in memory.
ModelCache createDefaultCache() => MemoryModelCache();
