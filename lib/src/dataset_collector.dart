abstract class DatasetCollector {
  Future<void> addDataPoint({int? time, required String name, required num value});
}
