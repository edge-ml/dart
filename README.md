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
  edge_ml_dart: ^1.2.0
```

Requirements: Flutter 3.38+, Android API 23+, iOS 13+, macOS 11+. On-device
inference uses [`executorch_flutter`](https://pub.dev/packages/executorch_flutter),
which downloads its prebuilt native library at build time (desktop builds need
`ninja` on the PATH).

**Android**: release builds need the internet permission in
`android/app/src/main/AndroidManifest.xml` (Flutter only adds it to debug
builds):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

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
final collector = await edgeml.datasets.collector(
  'walk-1',
  ['accX', 'accY', 'accZ'],
  units: {'accX': 'm/s^2', 'accY': 'm/s^2', 'accZ': 'm/s^2'}, // optional, see Units
  quantities: {'accX': 'acceleration', 'accY': 'acceleration', 'accZ': 'acceleration'},
);
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
final predictor = await edgeml.models.load(model.id, units: {'accX': 'm/s^2', 'accY': 'm/s^2', 'accZ': 'm/s^2'});
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
  print('${ds.name}: ${ds.timeSeries.map((t) => '${t.name} [${t.unit}, ${t.quantity}]')}');
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
  units: {'accX': 'g', 'accY': 'g', 'accZ': 'g'},              // optional
  quantities: {'accX': 'acceleration', 'accY': 'acceleration', 'accZ': 'acceleration'},
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
final rec = DatasetRecording(
  'offline-1',
  units: {'accX': 'm/s^2'},
  quantities: {'accX': 'acceleration'}, // sent by upload(); the CSV only has the unit
);
rec.startLabel('activity', 'walk');
rec.addSample({'accX': 0.1, 'accY': 9.8});
rec.stopLabel('activity');

final datasetId = await edgeml.datasets.upload(rec);
final csv = rec.toCsv(); // time,sensor_accX[m/s^2],sensor_accY,label_activity_walk
```

### Audio and video

A dataset can hold audio and video recordings next to its time-series, to
view and label them in the edge-ml web app. They are not used for training.
The library uploads files; recording them (camera, microphone) is up to your
app, with whatever plugin it uses.

```dart
// add a recording to a dataset, e.g. the one a collector just filled
final media = await edgeml.datasets.uploadMediaFile(
  collector.datasetId,
  '/path/to/walk-1.mp4',
  start: recordingStartedAt.millisecondsSinceEpoch, // lines it up with the sensor data
  name: 'front camera',                             // optional: defaults to the file name
);
print('${media.kind.name} ${media.duration} ${media.width}x${media.height}');

// from memory (also works on the web)
await edgeml.datasets.uploadMediaBytes(datasetId, bytes, fileName: 'voice.m4a');

// a dataset that only holds recordings
final id = await edgeml.datasets.create('interview-1');
await edgeml.datasets.uploadMediaFile(id, path);

// recordings are listed with the dataset and can be downloaded
final ds = await edgeml.datasets.get(id);
final bytes = await edgeml.datasets.downloadMedia(ds.id, ds.media.first.id);
```

`start` is the unix ms at which the recording begins. Without it the server
uses the start of the dataset. The server keeps the file as it is and accepts
what browsers can play: MP4 (H.264 with AAC) and WebM video; MP3, WAV, OGG,
FLAC and M4A audio, up to 2 GB. Anything else throws an `EdgeMLException`
(status 400) that says why. Phone cameras record MP4/H.264 by default; on
iOS, pick "Most Compatible" rather than HEVC.

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

### Sensor units

Every model knows the unit it expects for each input. Declare the unit your
sensors deliver, and the predictor converts the values before predicting:

```dart
final predictor = await edgeml.models.load(modelId, units: {'accX': 'g', 'temp': 'degF'});
predictor.addSample({'accX': 0.02, 'temp': 71.6}); // in g and °F

for (final u in predictor.inputUnits) {
  print('${u.name}: ${u.unit} (${u.quantity})'); // accX: m/s^2 (acceleration)
}
predictor.setUnits({'accX': 'm/s^2'}); // change the declaration later
```

- Sensors you don't declare pass through unchanged, and so do all inputs of
  models trained before units existed (or on data of unknown unit).
- If the model can't convert from a declared unit (e.g. `degC` for an
  acceleration), `load`/`setUnits` throw a `UnitException` listing the units
  it accepts, instead of predicting on wrong values.
- Units are matched by catalog id (`m/s^2`, `rad/s`, `degF`, ...). Pass
  `catalog: await edgeml.unitCatalog()` to also accept labels and aliases such
  as `m/s²` or `°F`.
- `ModelInfo.inputUnits` (from `models.get`/`list`) shows the same before
  downloading a model.

## Units

edge-ml stores a quantity and a unit for each time-series. The quantity is an
id of the server's unit catalog (e.g. `acceleration`, `angular_velocity`,
`temperature`) or a name of your own, the unit one of its units (e.g. `g`,
`rad/s`, `degF`). Training converts series of catalog quantities to the
quantity's default unit (e.g. m/s² for acceleration), so datasets recorded in
different units can be trained on together. Series without a quantity are
trained on as they are.

```dart
final catalog = await edgeml.unitCatalog(); // works without a valid key
for (final q in catalog.quantities) {
  print('${q.id}: models expect ${q.defaultUnit}, units ${q.units.map((u) => u.id)}');
}
```

## Errors

All errors are `EdgeMLException`s with the server's explanation in `message`:
`AuthenticationException` (unknown key, or a read key used to write),
`NotFoundException`, `TrainingException` (training failed or timed out),
`PredictorNotReadyException` (`predict()` before a full window) and
`UnitException` (a declared sensor unit the model can't convert from).

## Migrating from 0.0.x

1.0 is a rewrite. `OnlineDatasetCollector` became `edgeml.datasets.collector()`
and the CSV writer became `DatasetRecording.toCsv()`. Training and on-device
inference are new.

## License

MIT
