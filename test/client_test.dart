import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  EdgeML client(String url, http.Client c, {String key = 'k/1'}) =>
      EdgeML(apiKey: key, backendUrl: url, httpClient: c, modelCache: MemoryModelCache());

  test('defaults to the hosted edge-ml', () {
    expect(EdgeML(apiKey: 'k', modelCache: MemoryModelCache()).backendUrl, 'https://app.edge-ml.org');
  });

  test('self-hosted URLs, with a path prefix and trailing slash', () async {
    Uri? seen;
    final c = MockClient((req) async {
      seen = req.url;
      return http.Response('{"labelings": [], "datasets": []}', 200);
    });
    final e = client('https://lab.example.org/edge/ ', c);
    expect(e.backendUrl, 'https://lab.example.org/edge');
    await e.datasets.list();
    // the key is URL-encoded as one path segment
    expect(seen.toString(), 'https://lab.example.org/edge/ds/api/project/k%2F1');
  });

  test('rejects invalid URLs and empty keys', () {
    final c = MockClient((_) async => http.Response('', 200));
    expect(() => client('app.edge-ml.org', c), throwsArgumentError);
    expect(() => client('ftp://x.org', c), throwsArgumentError);
    expect(() => client('https://x.org', c, key: ' '), throwsArgumentError);
  });

  test('maps errors: 404, FastAPI validation lists, non-JSON, network', () async {
    Future<Object?> fail(http.Response res) async {
      try {
        await client('https://x.org', MockClient((_) async => res)).models.list();
      } catch (e) {
        return e;
      }
      return null;
    }

    expect(await fail(http.Response('{"detail": "Model not found"}', 404)), isA<NotFoundException>());
    final validation = await fail(
      http.Response('{"detail": [{"loc": ["body", "name"], "msg": "field required"}]}', 422),
    );
    expect((validation as EdgeMLException).message, 'body.name: field required');
    expect(validation.statusCode, 422);
    expect(
      ((await fail(http.Response('<html>', 502, reasonPhrase: 'Bad Gateway'))) as EdgeMLException).message,
      'Bad Gateway',
    );

    final offline = client('https://x.org', MockClient((_) async => throw http.ClientException('connection refused')));
    await expectLater(
      offline.models.list(),
      throwsA(isA<EdgeMLException>().having((e) => e.message, 'message', contains('Could not reach'))),
    );
  });
}
