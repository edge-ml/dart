import 'dart:convert';

import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:edge_ml_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object> dataset(String id, String name, List<(String, int, int)> labels) => {
  '_id': id,
  'name': name,
  'timeSeries': [
    {'_id': '$id-x', 'name': 'accX'},
    {'_id': '$id-y', 'name': 'accY'},
  ],
  'labelings': [
    {
      'labelingId': 'L1',
      'labels': [
        for (final (type, start, end) in labels) {'_id': '$id-$type', 'type': type, 'start': start, 'end': end},
      ],
    },
  ],
};

void main() {
  late List<Map<String, dynamic>> trainRequests;

  EdgeML client() {
    trainRequests = [];
    final mock = MockClient((req) async {
      final path = req.url.path;
      Object? body;
      if (path.endsWith('/ds/api/project/KEY')) {
        body = {
          'labelings': [
            {
              '_id': 'L1',
              'name': 'activity',
              'labels': [
                {'_id': 'walk', 'name': 'walk'},
                {'_id': 'run', 'name': 'run'},
                {'_id': 'sit', 'name': 'sit'},
              ],
            },
            {'_id': 'L2', 'name': 'unused', 'labels': []},
          ],
          'datasets': [
            dataset('D1', 'walk-1', [('walk', 0, 9), ('run', 10, 19), ('sit', 20, 29)]),
            dataset('D2', 'walk-2', [('walk', 0, 9)]),
          ],
        };
      } else if (path.endsWith('/presets')) {
        body = [
          {'id': 'small_cnn', 'name': 'Small CNN', 'description': 'smallest and fastest'},
          {'id': 'medium_cnn', 'name': 'Medium CNN', 'description': 'a good default'},
        ];
      } else if (path.endsWith('/train')) {
        trainRequests.add(jsonDecode(req.body) as Map<String, dynamic>);
        body = {'id': 'M1', 'warnings': []};
      } else if (path.endsWith('/models/M1')) {
        body = {
          'id': 'M1',
          'name': 'my-model',
          'trainStatus': 'done',
          'labels': ['walk', 'run', 'sit'],
        };
      }
      return http.Response(jsonEncode(body), body == null ? 404 : 200);
    });
    return EdgeML(apiKey: 'KEY', backendUrl: 'https://edge.test', httpClient: mock, modelCache: MemoryModelCache());
  }

  testWidgets('shows the labels and datasets that will be trained, and trains on the ticked ones', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TrainPage(edgeml: client())),
      ),
    );
    await tester.pumpAndSettle();

    // labeling with its labels; the unused labeling is not offered
    expect(find.text('activity'), findsOneWidget);
    for (final label in ['walk', 'run', 'sit']) {
      expect(find.widgetWithText(Chip, label), findsOneWidget);
    }
    expect(find.text('unused'), findsNothing);

    // both datasets, all ticked, with their labels
    expect(find.text('Datasets (2 of 2)'), findsOneWidget);
    expect(find.text('walk-1'), findsOneWidget);
    expect(find.text('walk, run, sit · 2 sensors'), findsOneWidget);
    expect(find.text('a good default'), findsOneWidget); // preset description

    // untick walk-2 and train
    await tester.tap(find.text('walk-2'));
    await tester.pumpAndSettle();
    expect(find.text('Datasets (1 of 2)'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Train'));
    await tester.pumpAndSettle();

    expect(trainRequests.single['datasets'], ['D1']);
    expect(trainRequests.single['labeling'], 'activity');
    expect(trainRequests.single['preset'], 'medium_cnn');
    expect(find.textContaining('Done: my-model predicts walk, run, sit'), findsOneWidget);
  });
}
