# edge_ml_dart

Flutter library for [edge-ml](https://edge-ml.org). It works with the hosted
edge-ml or a self-hosted instance, on Android, iOS, macOS, Linux, Windows and
the web.

- **Datasets**: upload sensor data, with or without labels (whole dataset or
  time ranges), while recording or afterwards, and list the project's datasets.
- **Training**: train a model on the edge-ml server from a preset (Small CNN,
  Large CNN, ...) and follow its progress.
- **On-device inference**: download the trained model in
  [ExecuTorch](https://pytorch.org/executorch/) format and run it on the
  device: feed sensor values, get predictions.

Everything is authenticated with the project's **Device API key** (edge-ml →
project settings → Device API). Uploading and training need the write key;
listing, downloading and running models also work with the read key.

## Installation

```yaml
dependencies:
  edge_ml_dart: ^1.0.0
```

Requirements: Flutter 3.38+, Android API 23+, iOS 13+, macOS 11+. On-device
inference uses [`executorch_flutter`](https://pub.dev/packages/executorch_flutter),
which downloads its prebuilt native library at build time (desktop builds need
`ninja` on the PATH).

**Web**: run once in your app and add the script to `web/index.html`:

```sh
dart run executorch_flutter:setup_web
```

```html
<head>
  <script src="js/executorch_wrapper.js"></script>
</head>
```

## Quick start

```dart
import 'package:edge_ml_dart/edge_ml_dart.dart';

final edgeml = EdgeML(apiKey: '<device api write key>');

// 1. record a labeled dataset
final collector = await edgeml.datasets.collector('walk-1', ['accX', 'accY', 'accZ']);
collector.startLabel('activity', 'walk');
collector.addSample({'accX': 0.1, 'accY': 9.8, 'accZ': 0.3}); // for every reading
collector.startLabel('activity', 'run'); // ends 'walk'
// ...
await collector.complete();

// 2. train a model from a preset
final model = await edgeml.models.train(
  name: 'activity-model',
  labeling: 'activity',
  preset: Presets.smallCnn,
  onProgress: (m) => print('${m.status.name} ${m.progress ?? ''}'),
);

// 3. run it on the device
final predictor = await edgeml.models.load(model.id);
sensorStream.listen((e) async {
  predictor.addSample({'accX': e.x, 'accY': e.y, 'accZ': e.z});
  if (predictor.isReady) {
    final p = await predictor.predict();
    print('${p.label} (${p.confidence})');
  }
});
```

The [example app](example/) does all of this with the phone's motion sensors.

## Self-hosted edge-ml

```dart
final edgeml = EdgeML(apiKey: key, backendUrl: 'https://edge-ml.my-lab.org');
```

`backendUrl` defaults to `https://app.edge-ml.org`. A path prefix
(`https://my-lab.org/edge-ml`) works too.

## Datasets

### List datasets

```dart
final datasets = await edgeml.datasets.list();
for (final ds in datasets) {
  print('${ds.name}: ${ds.timeSeries.map((t) => t.name)}');
  for (final label in ds.labels) {
    print('  ${label.labeling}/${label.label} ${label.start}-${label.end}');
  }
}
final ds = await edgeml.datasets.get('walk-1'); // by id or name
final labelings = await edgeml.datasets.labelings();
```

### Upload while recording

`collector()` creates the dataset and uploads values in the background (every
5 s, or every 5000 values) while you record. Timestamps are unix milliseconds
and default to now; pass `timestamp:` to use your sensor's clock.

```dart
final collector = await edgeml.datasets.collector(
  'session-3',
  ['accX', 'accY', 'accZ'],
  metadata: {'device': 'phone', 'person': 'p1'},
  wholeDatasetLabel: ('person', 'p1'), // optional: one label over the whole dataset
);

collector.add('accX', 0.12);                       // one value
collector.addSample({'accX': 0.1, 'accY': 9.8, 'accZ': 0.3}, timestamp: t); // one value per series

collector.startLabel('activity', 'walk');          // label from now on ...
collector.stopLabel('activity');                   // ... until now
collector.addLabel(DatasetLabel('activity', 'sit', start: t1, end: t2)); // or a known range

await collector.complete(); // uploads the rest and all labels
```

If a background upload fails, the next `add`/`addSample` call or `complete()`
throws the error.

### Record first, upload later

`DatasetRecording` keeps everything in memory, e.g. to record without a
connection. Upload it, or export it as an edge-ml CSV file that the edge-ml web
app imports.

```dart
final rec = DatasetRecording('offline-1', units: {'accX': 'm/s^2'});
rec.startLabel('activity', 'walk');
rec.addSample({'accX': 0.1, 'accY': 9.8});
rec.stopLabel('activity');

final datasetId = await edgeml.datasets.upload(rec);
final csv = rec.toCsv(); // time,sensor_accX[m/s^2],sensor_accY,label_activity_walk
```

## Training

Presets are defined by the edge-ml server, and every preset trains a model
that runs on the device:

| Preset | Model |
|---|---|
| `Presets.smallCnn` | 1D CNN, 1 block, 8 filters, on raw windows: smallest and fastest |
| `Presets.mediumCnn` (default) | 1D CNN, 2 blocks, 16 filters |
| `Presets.largeCnn` | 1D CNN, 3 blocks, 32 filters: most accurate |
| `Presets.smallDense` | dense network, 1 layer, on statistical features |
| `Presets.largeDense` | dense network, 3 layers, on statistical features |

```dart
final presets = await edgeml.models.presets(); // id, name, description

final model = await edgeml.models.train(
  name: 'gesture-model',
  labeling: 'gesture',                 // labeling name or id
  preset: Presets.largeCnn,
  datasets: ['g-1', 'g-2'],            // optional, default: every dataset with that labeling
  timeSeries: ['accX', 'accY', 'accZ'],// optional, default: series all datasets share
  disabledLabels: ['noise'],           // optional
  steps: {                             // optional overrides on top of the preset
    'windowing': StepOverride(parameters: {'window_size': 100, 'sliding_step': 50}),
    'classifier': StepOverride(parameters: {'epochs': 100}),
  },
  onProgress: (m) => print(m),
  onWarning: print,
);
print(model.metrics);
```

`train` waits until the model is trained; `startTraining` returns right away
and `watch(modelId)` streams the model's state. `list()` and `get(id)` return
the project's models; `ModelInfo.runsOnDevice` tells which ones you can load.

## Running models

```dart
final predictor = await edgeml.models.load(modelId);
print(predictor.timeSeries); // the sensors it expects, e.g. [accX, accY, accZ]
print(predictor.labels);     // what it predicts
print(predictor.windowSize); // samples per window

predictor.addSample({'accX': x, 'accY': y, 'accZ': z}); // unused sensors are ignored
predictor.addValues([x, y, z], timestamp: t);           // in timeSeries order

if (predictor.isReady) {
  final p = await predictor.predict(); // classifies the latest window
  print(p.label);       // 'walk'
  print(p.confidence);  // 0.93
  print(p.byLabel);     // {walk: 0.93, run: 0.05, sit: 0.02}
}

await predictor.dispose();
```

Feature extraction and normalization are part of the model. The predictor
only buffers values into windows, aligned the same way edge-ml aligns
datasets for training (sensors with different timestamps are interpolated).
`predictor.manifest.classificationFrequencyHz` suggests how often to call
`predict()`.

`load` downloads the model once and keeps it in the app's support directory,
so it also works offline later (on the web it is kept in memory). Use
`load(id, forceDownload: true)` or `edgeml.models.clearCache()` to refresh, and
`EdgeML(modelCache: MemoryModelCache())` to not store models on the device.

To ship a model inside your app instead, download the ExecuTorch export from
the edge-ml web app, add `model.pte` and `manifest.json` as assets and load
them with:

```dart
final predictor = await Predictor.fromBytes(pteBytes, manifestJson);
```

## Errors

All errors are `EdgeMLException`s with the server's explanation in `message`:
`AuthenticationException` (unknown key, or a read key used to write),
`NotFoundException`, `TrainingException` (training failed or timed out) and
`PredictorNotReadyException` (`predict()` before a full window).

## Migrating from 0.0.x

1.0 is a rewrite. `OnlineDatasetCollector` became `edgeml.datasets.collector()`
and the CSV writer became `DatasetRecording.toCsv()`. Training and on-device
inference are new.

## License

MIT
