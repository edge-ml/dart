import 'types.dart';

/// Tracks labels while recording: ranges added directly, and open labels
/// started with [startLabel] and closed with [stopLabel]. Only one label per
/// labeling can be open, since labels of one labeling must not overlap.
mixin LabelTracker {
  final List<DatasetLabel> _labels = [];
  final Map<String, (String label, int start)> _open = {};

  /// Labels added so far, not including labels that are still open.
  List<DatasetLabel> get labels => List.unmodifiable(_labels);

  /// Current time used when no timestamp is given (unix ms).
  int now() => DateTime.now().millisecondsSinceEpoch;

  /// Adds a label over a finished time range.
  void addLabel(DatasetLabel label) {
    if (label.end < label.start) {
      throw ArgumentError.value(label, 'label', 'ends before it starts');
    }
    _labels.add(label);
  }

  /// Starts labeling everything from [timestamp] (default: now) on as
  /// [label] of [labeling], until [stopLabel] is called or another label of
  /// the same labeling is started.
  void startLabel(String labeling, String label, {int? timestamp}) {
    final t = timestamp ?? now();
    stopLabel(labeling, timestamp: t);
    _open[labeling] = (label, t);
  }

  /// Ends the open label of [labeling] at [timestamp] (default: now). Does
  /// nothing if no label of that labeling is open.
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
}
