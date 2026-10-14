import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../errors.dart';

/// Thin JSON/bytes client for the edge-ml device API. The API key is part of
/// the URL path, as the server expects.
class ApiClient {
  ApiClient({required String backendUrl, required this.apiKey, http.Client? httpClient, required this.timeout})
    : backendUrl = normalizeBackendUrl(backendUrl),
      _client = httpClient ?? http.Client(),
      _ownsClient = httpClient == null;

  final String backendUrl;
  final String apiKey;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  /// The API key, URL-encoded for use as a path segment.
  String get key => Uri.encodeComponent(apiKey);

  static String normalizeBackendUrl(String url) {
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      throw ArgumentError.value(url, 'backendUrl', 'must be an http(s) URL such as https://app.edge-ml.org');
    }
    return trimmed;
  }

  Uri uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse(backendUrl + path);
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Future<dynamic> getJson(String path, {Map<String, String>? query}) async =>
      _decode(await _send(() => _client.get(uri(path, query))));

  Future<dynamic> postJson(String path, Object? body) async => _decode(
    await _send(
      () => _client.post(uri(path), headers: const {'Content-Type': 'application/json'}, body: jsonEncode(body)),
    ),
  );

  Future<Uint8List> getBytes(String path) async => (await _send(() => _client.get(uri(path)))).bodyBytes;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request().timeout(timeout);
    } on TimeoutException {
      throw EdgeMLException('No answer from $backendUrl within ${timeout.inSeconds}s');
    } on http.ClientException catch (e) {
      throw EdgeMLException('Could not reach $backendUrl: ${e.message}');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res;

    final detail = _errorDetail(res);
    switch (res.statusCode) {
      case 401:
        throw AuthenticationException(detail);
      case 404:
        throw NotFoundException(detail);
      default:
        throw EdgeMLException(detail, statusCode: res.statusCode);
    }
  }

  static String _errorDetail(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map) {
        final detail = body['detail'] ?? body['error'] ?? body['message'];
        // FastAPI validation errors: [{loc: [...], msg: "..."}]
        if (detail is List) {
          return detail.map((e) => e is Map ? '${(e['loc'] as List?)?.join('.') ?? ''}: ${e['msg']}' : '$e').join('; ');
        }
        if (detail != null) return '$detail';
      }
    } on FormatException {
      // not JSON
    }
    return res.reasonPhrase ?? 'HTTP ${res.statusCode}';
  }

  static dynamic _decode(http.Response res) => res.body.isEmpty ? null : jsonDecode(res.body);
}
