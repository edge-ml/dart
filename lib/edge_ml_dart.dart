/// Flutter library for [edge-ml](https://edge-ml.org): upload labeled sensor
/// datasets, train models on the edge-ml server from presets, and run them on
/// the device with ExecuTorch.
///
/// Start with [EdgeML].
library;

export 'src/client.dart' show EdgeML;
export 'src/datasets/collector.dart' show DatasetCollector;
export 'src/datasets/datasets_api.dart' show DatasetsApi;
export 'src/datasets/recording.dart' show DatasetRecording;
export 'src/datasets/types.dart' show Dataset, DatasetLabel, LabelClass, Labeling, TimeSeriesInfo;
export 'src/errors.dart';
export 'src/inference/manifest.dart' show ModelManifest;
export 'src/inference/model_cache.dart' show MemoryModelCache, ModelCache, ModelFiles;
export 'src/inference/predictor.dart' show Prediction, Predictor;
export 'src/inference/runtime.dart' show ExecuTorchRuntime, InferenceRuntime, LoadedModel;
export 'src/models/models_api.dart' show ModelsApi;
export 'src/models/types.dart' show ModelInfo, Preset, Presets, StepOverride, TrainStatus, TrainingStarted;
