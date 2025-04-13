import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:semaphore_plus/semaphore_plus.dart';

import 'dataset_collector.dart';

class CsvDatasetCollector extends DatasetCollector {
  final String name;
  late final String filePath;
  final bool useDeviceTime;
  final List<String> timeSeries;
  final Map<String, dynamic> metaData;
  final bool allowUnsupportedString;

  // The file that we'll be writing data into
  late File _outputFile;

  final Map<int, Map<String, String>> _rows = {};

  final _rowsModSemaphore = LocalSemaphore(1);

  CsvDatasetCollector._({
    required this.name,
    required this.useDeviceTime,
    required this.timeSeries,
    required this.metaData,
    this.allowUnsupportedString = false,
  });

  /// Factory constructor to create and initialize the CSV collector
  static Future<CsvDatasetCollector> create({
    required String name,
    String? filePath,
    required bool useDeviceTime,
    required List<String> timeSeries,
    required Map<String, dynamic> metaData,
    bool allowUnsupportedString = false,
    String? datasetLabel,
  }) async {
    final instance = CsvDatasetCollector._(
      name: name,
      useDeviceTime: useDeviceTime,
      timeSeries: timeSeries,
      metaData: metaData,
      allowUnsupportedString: allowUnsupportedString,
    );
    await instance._initialize(filePath);
    return instance;
  }

  /// Prepares our CSV file for writing:
  ///  - If [filePath] was given, we use that directly.
  ///  - Otherwise, we find an app-specific documents directory,
  ///    create a subdirectory, and generate a timestamp-based filename.
  Future<void> _initialize(String? filePath) async {
    if (filePath != null && filePath.trim().isNotEmpty) {
      this.filePath = filePath;
      _outputFile = File(filePath);
    } else {
      // Acquire application-specific directory
      final dir = await getApplicationDocumentsDirectory();

      // Create a "csv_datasets" subdirectory (you can customize this name)
      final csvDir = Directory('${dir.path}/csv_datasets');
      if (!(await csvDir.exists())) {
        await csvDir.create(recursive: true);
      }

      // Format: YYYY-MM-DD_HH_mm_ss__datasetName.csv
      final now = DateTime.now();
      final nowString =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}__${now.hour.toString().padLeft(2, '0')}_${now.minute.toString().padLeft(2, '0')}_${now.second.toString().padLeft(2, '0')}';

      // Replace spaces in dataset name with underscore
      final sanitizedName = name.replaceAll(RegExp(r'\s+'), '_');
      final fileName = '${nowString}__${sanitizedName}.csv';

      this.filePath = '${csvDir.path}/$fileName';

      _outputFile = File(this.filePath);
    }

    final headerRow = ['time']..addAll(timeSeries.map((s) => 'sensor_$s'));
    final csvHeader = const ListToCsvConverter().convert([headerRow]);

    await _outputFile.writeAsString('$csvHeader\n');
  }

  Future<void> _writeCsv() async {
    List<List<String>> allRows = [];

    try {
      await _rowsModSemaphore.acquire();

      // Rebuild entire CSV content with header and sorted rows
      final headerRow = ['time']..addAll(timeSeries.map((s) => 'sensor_$s'));

      allRows.add(headerRow);
      final sortedTimestamps = _rows.keys.toList()..sort();
      for (final timestamp in sortedTimestamps) {
        final rowMap = _rows[timestamp]!;
        final row = [rowMap['time'] ?? ''] +
            timeSeries.map((sensor) => rowMap[sensor] ?? '').toList();
        allRows.add(row);
      }
    } catch (_) {
      // Nothing
    } finally {
      _rowsModSemaphore.release();
    }

    if (allRows.isNotEmpty) {
      final csvContent = const ListToCsvConverter().convert(allRows);
      await _outputFile.writeAsString('$csvContent\n');
    }
  }

  Future<void> _setField(int? time, String name, String value) async {
    if (name.isEmpty) {
      throw ArgumentError('Sensor name cannot be empty.');
    }
    if (!timeSeries.contains(name)) {
      throw ArgumentError(
        'Sensor name "$name" is not part of the current data set.',
      );
    }

    if (!useDeviceTime && time == null) {
      throw ArgumentError("Timestamp must be provided if useDeviceTime=false.");
    }

    final int actualTime =
        useDeviceTime ? DateTime.now().millisecondsSinceEpoch : time!;

    try {
      await _rowsModSemaphore.acquire();

      // Update sensor data in the _rows map
      if (!_rows.containsKey(actualTime)) {
        _rows[actualTime] = {
          'time': actualTime.toString(),
          for (var sensor in timeSeries) sensor: '',
        };
      }
      _rows[actualTime]![name] = value;
    } catch (_) {
      // Nothing
    } finally {
      _rowsModSemaphore.release();
    }
  }

  /// Appends a new data point to the CSV.
  /// Each line includes [timestamp, name, value].
  /// If [useDeviceTime] is true, we capture the current device time;
  /// otherwise, we require an explicit [time] argument.
  @override
  Future<void> addDataPoint({
    int? time,
    required String name,
    required num value,
  }) async {
    // Round similarly to your JS logic (two decimals)
    final roundedValue = (value * 100).round() / 100;

    await _setField(time, name, roundedValue.toString());

    await _writeCsv();
  }

  /// Appends a string new data point to the CSV.
  /// Each line includes [timestamp, name, value].
  /// If [useDeviceTime] is true, we capture the current device time;
  /// otherwise, we require an explicit [time] argument.
  /// [allowUnsupportedString] needs to be set to true to use this method.
  /// This method creates CSV files not supported by Edge-ML.
  Future<void> addStringDataPoint({
    int? time,
    required String name,
    required String value,
  }) async {
    if (!allowUnsupportedString) {
      throw ArgumentError('allowUnsupportedString needs to be set to true');
    }

    await _setField(time, name, value);

    await _writeCsv();
  }

  static Future<List<String>> listCsvFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final csvDir = Directory('${dir.path}/csv_datasets');
    if (!(await csvDir.exists())) {
      return [];
    }
    final files = await csvDir
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files.map((f) => f.path).toList();
  }
}
