import 'package:http/http.dart' as http;

import 'datasets/datasets_api.dart';
import 'http/api_client.dart';
import 'inference/model_cache.dart';
import 'inference/runtime.dart';
import 'models/models_api.dart';

/// Client for one edge-ml project, authenticated with the project's device
/// API key (edge-ml web app → project settings → Device API).
///
/// Uploading datasets and training need the **write** key; listing, and
/// downloading and running models also work with the **read** key.
///
/// ```dart
/// final edgeml = EdgeML(apiKey: '<device api key>');
/// // self-hosted:
/// final edgeml = EdgeML(apiKey: key, backendUrl: 'https://edge-ml.my-lab.org');
/// ```
class EdgeML {
  /// Creates a client for the project of [apiKey].
  ///
  /// - [backendUrl]: the edge-ml server, default [defaultBackendUrl]. Set it
  ///   to use a self-hosted edge-ml.
  /// - [httpClient]: a custom `http` client (proxies, certificates, tests).
  /// - [timeout]: per request.
  /// - [runtime]: runs models, default [ExecuTorchRuntime].
  /// - [modelCache]: where downloaded models are kept, default files in the
  ///   app support directory (memory on the web). Pass [MemoryModelCache] to
  ///   not store models on the device.
  EdgeML({
    required String apiKey,
    String backendUrl = defaultBackendUrl,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 60),
    InferenceRuntime? runtime,
    ModelCache? modelCache,
  }) : _api = ApiClient(backendUrl: backendUrl, apiKey: apiKey, httpClient: httpClient, timeout: timeout) {
    if (apiKey.trim().isEmpty) throw ArgumentError.value(apiKey, 'apiKey', 'must not be empty');
    datasets = DatasetsApi.internal(_api);
    models = ModelsApi.internal(_api, runtime ?? ExecuTorchRuntime(), modelCache ?? ModelCache.platformDefault());
  }

  /// The hosted edge-ml instance.
  static const defaultBackendUrl = 'https://app.edge-ml.org';

  final ApiClient _api;

  /// Upload and list datasets.
  late final DatasetsApi datasets;

  /// Train, list, download and run models.
  late final ModelsApi models;

  /// The edge-ml server this client talks to.
  String get backendUrl => _api.backendUrl;

  /// Closes the HTTP client (unless you passed your own).
  void close() => _api.close();
}
