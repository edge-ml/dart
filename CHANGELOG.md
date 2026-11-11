## 1.2.0

Audio and video recordings in datasets (needs an edge-ml server with media
support; everything else works with older servers as before).

- `datasets.uploadMediaFile` and `datasets.uploadMediaBytes` add an audio or
  video recording to a dataset, placed on its timeline by `start`. The server
  accepts MP4 (H.264/AAC) and WebM video, and MP3, WAV, OGG, FLAC and M4A
  audio.
- `Dataset.media` lists the recordings (`MediaSeries`: kind, name, start,
  duration, size, resolution, codecs); `Dataset.start`/`end` include them.
- `datasets.downloadMedia` fetches a recording.
- `datasets.create` makes a dataset without time-series, for datasets that
  only hold recordings.

## 1.1.0

Units (needs an edge-ml server with unit support; plain names keep working
with older servers).

- `datasets.collector` and `DatasetRecording` take `units` and `quantities`
  per time-series and send them when the dataset is created. Series without
  them are sent as plain names, as before.
- `TimeSeriesInfo.quantity` next to `unit`.
- `ModelInfo.inputUnits` and `ModelManifest.inputUnits`: the unit the model
  expects for each input, read from `input.units` (same format in ONNX and
  ExecuTorch manifests).
- `Predictor` converts declared sensor units to the expected units before
  predicting: `models.load(id, units: {...})`, `Predictor.fromBytes(...,
  units: ...)`, `setUnits`, `inputUnits`. A unit the model can't convert from
  throws `UnitException`. Models trained before units existed get values
  unchanged.
- `EdgeML.unitCatalog()` fetches the server's unit catalog (`/ml/units/`).
- Example app stores and declares its sensor units (m/s², rad/s).

## 1.0.1

- Fix: switching labels while recording (`startLabel` while another label of
  the same labeling is open) ended the previous label at the same millisecond
  the next one started. edge-ml treats that as an overlap and rejected every
  label after the first. The previous label now ends 1 ms earlier, and
  `stopLabel` + `startLabel` at the same time no longer touch either.
- `addLabel` rejects a range that overlaps another label of the same labeling
  right away, instead of failing later on upload.

## 1.0.0

A rewrite of the library around the edge-ml device API.

- `EdgeML` client with a configurable `backendUrl` for self-hosted edge-ml
- Datasets: list datasets and labelings; upload while recording
  (`datasets.collector`) or afterwards (`DatasetRecording` + `datasets.upload`),
  with whole-dataset or time-range labels; export edge-ml CSV
- Training: train from server-side presets (Small/Medium/Large CNN,
  Small/Large dense), follow progress, list models
- On-device inference with ExecuTorch on Android, iOS, macOS, Linux, Windows
  and web: `models.load` downloads and caches the model, `Predictor` buffers
  sensor values into windows and classifies them
- Typed errors (`EdgeMLException` and subclasses)

Breaking: `OnlineDatasetCollector` and `CsvDatasetCollector` are replaced by
`datasets.collector()` and `DatasetRecording`.

## 0.0.4

- Add write timeouts for CSV files

## 0.0.3

- Add support for writing Edge-ML compatible CSV files (https://github.com/edge-ml/edge-ml/wiki/#CSV-Header-Format)

## 0.0.2

- Publish workflow
- Link repository

## 0.0.1

- Initial version.
