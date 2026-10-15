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
