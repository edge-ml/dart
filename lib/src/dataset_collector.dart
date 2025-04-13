abstract class DatasetCollector {
  Future<void> addDataPoint({
    int? time,
    required String name,
    required num value,
  });

  /// Clean up and flush data
  Future<void> dispose();
}
