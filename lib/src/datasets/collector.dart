import 'dart:async';

import '../errors.dart';
import 'label_tracker.dart';
import 'recording.dart' show checkValue;
import 'types.dart';

/// Sends one append request: data per time-series plus labels.
typedef AppendFn =
    Future<void> Function(
      Map<String, List<(int, double)>> data, {
      List<DatasetLabel> labels,
      (String labeling, String label)? wholeDatasetLabel,
    });

/// Streams a dataset to edge-ml while it is being recorded. Create one with
/// [DatasetsApi.collector].
///
/// Values are buffered and uploaded in the background every
/// `uploadInterval`, or as soon as `maxBufferedValues` are buffered. Uploads
/// never overlap and keep their order. If a background upload fails, the
/// error is thrown by the next [add]/[addSample] call or by [complete].
///
/// Labels are uploaded by [complete], once their ranges are known.
class DatasetCollector with LabelTracker {
  /// Use [DatasetsApi.collector].
  DatasetCollector.internal({
    required this.datasetId,
    required this.timeSeries,
    required AppendFn append,
    required Duration uploadInterval,
    required int maxBufferedValues,
    (String, String)? wholeDatasetLabel,
  }) : _append = append,
       _maxBufferedValues = maxBufferedValues,
       _wholeDatasetLabel = wholeDatasetLabel {
    _timer = Timer.periodic(uploadInterval, (_) => _flushInBackground());
  }

  /// Server id of the dataset being recorded.
  final String datasetId;

  /// The time-series this dataset was created with.
  final List<String> timeSeries;

  final AppendFn _append;
  final int _maxBufferedValues;
  final (String, String)? _wholeDatasetLabel;
  late final Timer _timer;

  Map<String, List<(int, double)>> _buffer = {};
  int _buffered = 0;
  int? _lastTimestamp;
  Future<void> _uploads = Future.value();
  Object? _error;
  bool _completed = false;

  /// Whether [complete] has been called.
  bool get isCompleted => _completed;

  /// Adds one [value] of the time-series [series] at [timestamp] (unix ms,
  /// default: now).
  void add(String series, num value, {int? timestamp}) {
    _checkUsable();
    if (!timeSeries.contains(series)) {
      throw ArgumentError.value(series, 'series', 'is not one of ${timeSeries.join(', ')}');
    }
    checkValue(series, value);
    final t = timestamp ?? now();
    (_buffer[series] ??= []).add((t, value.toDouble()));
    _buffered++;
    if (_lastTimestamp == null || t > _lastTimestamp!) _lastTimestamp = t;
    if (_buffered >= _maxBufferedValues) _flushInBackground();
  }

  /// Adds one value per time-series, all at the same [timestamp] (unix ms,
  /// default: now).
  void addSample(Map<String, num> values, {int? timestamp}) {
    final t = timestamp ?? now();
    values.forEach((series, value) => add(series, value, timestamp: t));
  }

  /// Uploads everything buffered so far and waits for all uploads to finish.
  Future<void> flush() async {
    _checkUsable();
    _flushInBackground();
    await _uploads;
    _throwError();
  }

  /// Uploads the remaining values, closes open labels at the last recorded
  /// timestamp and uploads all labels. The collector cannot be used after.
  Future<void> complete() async {
    _checkUsable();
    _timer.cancel();
    _completed = true;
    _flushInBackground();
    await _uploads;
    _throwError();

    closeOpenLabels(_lastTimestamp ?? now());
    if (labels.isNotEmpty || _wholeDatasetLabel != null) {
      await _append(const {}, labels: labels, wholeDatasetLabel: _wholeDatasetLabel);
    }
  }

  /// Stops background uploads without uploading what is still buffered.
  void cancel() {
    _timer.cancel();
    _completed = true;
  }

  void _flushInBackground() {
    if (_buffered == 0) return;
    final batch = _buffer;
    _buffer = {};
    _buffered = 0;
    _uploads = _uploads.then((_) async {
      if (_error != null) return; // keep the first error, drop later batches
      try {
        await _append(batch);
      } catch (e) {
        _error = e;
      }
    });
  }

  void _checkUsable() {
    if (_completed) throw StateError('The dataset collector is already completed');
    _throwError();
  }

  void _throwError() {
    final e = _error;
    if (e == null) return;
    _timer.cancel();
    _completed = true;
    if (e is EdgeMLException) throw e;
    throw EdgeMLException('Upload failed: $e');
  }
}
