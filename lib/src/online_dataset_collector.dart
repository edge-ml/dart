import 'dart:convert';
import 'package:http/http.dart' as http;

import 'dataset_collector.dart';

class _Urls {
  static const String initDatasetIncrement = "/ds/api/dataset/init/";
  static const String addDatasetIncrement = "/ds/api/dataset/append/";
}

class OnlineDatasetCollector extends DatasetCollector {
  final String url;
  final String key;
  final String name;
  final bool useDeviceTime;
  final List<String> timeSeries;
  final Map<String, dynamic> metaData;
  final String? datasetLabel;
  final int uploadIntervalMs;

  List<_TimeSeriesData> _dataStore = [];
  int _lastChecked = DateTime.now().millisecondsSinceEpoch;
  late String datasetKey;

  static Future<OnlineDatasetCollector> create({
    required String url,
    required String key,
    required String name,
    required bool useDeviceTime,
    required List<String> timeSeries,
    required Map<String, dynamic> metaData,
    String? datasetLabel,
    int uploadIntervalMs = 5000,
  }) async {
    final instance = OnlineDatasetCollector._(
      url: url,
      key: key,
      name: name,
      useDeviceTime: useDeviceTime,
      timeSeries: timeSeries,
      metaData: metaData,
      datasetLabel: datasetLabel,
      uploadIntervalMs: uploadIntervalMs,
    );
    await instance._initialize();
    return instance;
  }

  OnlineDatasetCollector._({
    required this.url,
    required this.key,
    required this.name,
    required this.useDeviceTime,
    required this.timeSeries,
    required this.metaData,
    this.datasetLabel,
    required this.uploadIntervalMs,
  });

  Future<void> _initialize() async {
    // Get labeling (e.g. "MyLabel_XYZ" -> labelingName=MyLabel, labelName=XYZ)
    Map<String, String>? labeling;
    if (datasetLabel != null && datasetLabel!.contains("_")) {
      final parts = datasetLabel!.split("_");
      if (parts.length >= 2) {
        labeling = {"labelingName": parts[0], "labelName": parts[1]};
      }
    }

    final initBody = {
      "name": name,
      "metaData": metaData,
      "timeSeries": timeSeries,
    };
    if (labeling != null) {
      initBody["labeling"] = labeling;
    }

    final initResponse = await http.post(
      Uri.parse('$url${_Urls.initDatasetIncrement}$key'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(initBody),
    );

    if (initResponse.statusCode != 200) {
      throw Exception(
        "Could not generate datasetCollector. Server returned ${initResponse.statusCode}.",
      );
    }

    final data = jsonDecode(initResponse.body);
    if (data["id"] == null) {
      throw Exception(
        "Could not generate datasetCollector (invalid response).",
      );
    }
    this.datasetKey = data["id"];
  }

  Future<void> addDataPoint({
    int? time,
    required String name,
    required num value,
  }) async {
    if (name.isEmpty) {
      throw ArgumentError("Sensor name cannot be empty.");
    }

    if (!timeSeries.contains(name)) {
      throw ArgumentError("Invalid time-series name: $name");
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final actualTime = useDeviceTime ? nowMs : (time ?? 0);
    if (!useDeviceTime && time == null) {
      throw ArgumentError("Timestamp must be provided if useDeviceTime=false.");
    }

    // Round like in the JS implementation
    final roundedValue = (value * 100).round() / 100;

    final index = _dataStore.indexWhere((ts) => ts.name == name);
    if (index == -1) {
      final newTsData = _TimeSeriesData(
        name: name,
        data: [
          [actualTime, roundedValue],
        ],
      );
      _dataStore.add(newTsData);
    } else {
      final tsData = _dataStore[index];
      tsData.data.add([actualTime, roundedValue]);
      _dataStore[index] = tsData;
    }

    // Trigger upload
    final currentMs = DateTime.now().millisecondsSinceEpoch;
    if (currentMs - _lastChecked > uploadIntervalMs) {
      _upload();
      _lastChecked = currentMs;
      _dataStore.clear();
    }
  }

  Future<void> _upload({Map<String, String>? labeling}) async {
    final currentDataList = _dataStore;

    final List<Map<String, dynamic>> jsonDataList =
        currentDataList.map((ts) => ts.toJson()).toList();

    final uploadBody = {
      "data": jsonDataList,
      if (labeling != null) "labeling": labeling,
    };

    final response = await http.post(
      Uri.parse('$url${_Urls.addDatasetIncrement}$key/$datasetKey'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(uploadBody),
    );

    if (response.statusCode != 200) {
      throw Exception("Upload failed with status code ${response.statusCode}.");
    }
  }

  @override
  Future<void> dispose() async {
    await _upload();
  }
}

class _TimeSeriesData {
  final String name;

  final List<List<num>> data;

  _TimeSeriesData({required this.name, required this.data});

  Map<String, dynamic> toJson() {
    return {"name": name, "data": data};
  }
}
