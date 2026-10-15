import 'types.dart';

/// Tracks labels while recording: ranges added directly, and open labels
/// started with [startLabel] and closed with [stopLabel].
///
/// edge-ml rejects labels of one labeling that overlap, and ranges are
/// inclusive, so two labels that share even one millisecond overlap. The
/// tracker keeps labels of one labeling strictly apart: switching labels ends
/// the previous one 1 ms before the next starts.
mixin LabelTracker {
  final List<DatasetLabel> _labels = [];
  final Map<String, (String label, int start)> _open = {};

  /// Labels added so far, not including labels that are still open.
  List<DatasetLabel> get labels => List.unmodifiable(_labels);

  /// Current time used when no timestamp is given (unix ms).
  int now() => DateTime.now().millisecondsSinceEpoch;

  /// Adds a label over a finished time range (both ends inclusive). Throws
  /// [ArgumentError] if it ends before it starts or overlaps another label
  /// of the same labeling.
  void addLabel(DatasetLabel label) {
    if (label.end < label.start) {
      throw ArgumentError.value(label, 'label', 'ends before it starts');
    }
    for (final other in _labels) {
      if (other.labeling == label.labeling && other.start <= label.end && label.start <= other.end) {
        throw ArgumentError.value(label, 'label', 'overlaps $other; labels of one labeling must not overlap');
      }
    }
    _labels.add(label);
  }

  /// Starts labeling everything from [timestamp] (default: now) on as
  /// [label] of [labeling], until [stopLabel] is called or another label of
  /// the same labeling is started (which ends this one just before).
  void startLabel(String labeling, String label, {int? timestamp}) {
    final t = timestamp ?? now();
    stopLabel(labeling, timestamp: t - 1);
    final lastEnd = _lastEnd(labeling);
    _open[labeling] = (label, lastEnd != null && lastEnd >= t ? lastEnd + 1 : t);
  }

  /// Ends the open label of [labeling] at [timestamp] (default: now),
  /// inclusive. Does nothing if no label of that labeling is open.
  void stopLabel(String labeling, {int? timestamp}) {
    final open = _open.remove(labeling);
    if (open == null) return;
    final end = timestamp ?? now();
    _labels.add(DatasetLabel(labeling, open.$1, start: open.$2, end: end < open.$2 ? open.$2 : end));
  }

  /// The labeling names that currently have an open label.
  Iterable<String> get openLabelings => _open.keys;

  /// Closes every open label at [timestamp].
  void closeOpenLabels(int timestamp) {
    for (final labeling in _open.keys.toList()) {
      stopLabel(labeling, timestamp: timestamp);
    }
  }

  int? _lastEnd(String labeling) {
    int? last;
    for (final l in _labels) {
      if (l.labeling == labeling && (last == null || l.end > last)) last = l.end;
    }
    return last;
  }
}
