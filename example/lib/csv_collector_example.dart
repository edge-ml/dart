import 'dart:async';

import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';

import 'mouse_tracker.dart';

class CsvCollectorExample extends StatefulWidget {
  const CsvCollectorExample({super.key});

  @override
  State<CsvCollectorExample> createState() => _CsvCollectorExampleState();
}

class _CsvCollectorExampleState extends State<CsvCollectorExample> {
  CsvDatasetCollector? _csvDatasetCollector;

  final TextEditingController _datasetNameController = TextEditingController(
    text: "Mouse Movement",
  );

  bool _tracking = false;
  bool _starting = false;
  Timer? _timer;

  double _frequency = 50;

  double _cursorX = 0;
  double _cursorY = 0;

  void _onTimerTick(Timer timer) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    _csvDatasetCollector?.addDataPoint(
      name: "mouseX",
      value: _cursorX,
      time: nowMs,
    );
    _csvDatasetCollector?.addDataPoint(
      name: "mouseY",
      value: _cursorY,
      time: nowMs,
    );
  }

  void _startTimer(int frequency) {
    _timer = Timer.periodic(Duration(milliseconds: frequency), _onTimerTick);
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _toggleTracking() async {
    if (!_tracking) {
      setState(() {
        _starting = true;
      });

      String datasetName = _datasetNameController.text;
      int frequency = _frequency.toInt();

      try {
        _csvDatasetCollector = await CsvDatasetCollector.create(
          name: datasetName,
          useDeviceTime: false,
          timeSeries: ["mouseX", "mouseY"],
          metaData: {"app": "example"},
          datasetLabel: "mouse",
        );
        print(
          "Initialized CSV collector with output file: \"${_csvDatasetCollector!.filePath}\"",
        );
      } catch (e) {
        print('Failed to create OnlineDatasetCollector: $e');
        setState(() {
          _starting = false;
        });
        return;
      }

      setState(() {
        _starting = false;
        _tracking = true;
      });
      print('Started tracking');
      _startTimer(frequency);
    } else {
      _stopTimer();
      setState(() {
        _tracking = false;
      });
      print('Stopped tracking');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _datasetNameController,
          decoration: InputDecoration(
            labelText: 'Dataset Name',
            border: OutlineInputBorder(),
          ),
          enabled: !_tracking && !_starting,
        ),
        SizedBox(height: 16.0),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Measure Frequency: ${_frequency.toInt()} ms'),
            Slider(
              value: _frequency,
              min: 1,
              max: 1000,
              divisions: 999,
              label: _frequency.toInt().toString(),
              onChanged:
                  _tracking && !_starting
                      ? null
                      : (value) {
                        setState(() {
                          _frequency = value;
                        });
                      },
            ),
          ],
        ),
        SizedBox(height: 16.0),
        ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => CsvFileListPage()),
            );
          },
          child: Text('Show CSV Files'),
        ),
        SizedBox(height: 22.0),
        ElevatedButton(
          onPressed: _starting ? null : _toggleTracking,
          child: Text(
            _tracking
                ? 'Stop'
                : _starting
                ? 'Starting...'
                : 'Start',
          ),
        ),
        SizedBox(height: 16.0),
        Expanded(
          child: CursorTracker(
            onCursorUpdate: (double a, double b) {
              _cursorX = a;
              _cursorY = b;
            },
          ),
        ),
      ],
    );
  }
}

class CsvFileListPage extends StatelessWidget {
  const CsvFileListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('CSV Files'),
        leading: BackButton(),
      ),
      body: FutureBuilder<List<String>>(
        future: CsvDatasetCollector.listCsvFiles(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text('No CSV files found.'));
          } else {
            final files = snapshot.data!;
            return ListView.builder(
              itemCount: files.length,
              itemBuilder: (context, index) {
                final filePath = files[index];
                final fileName = filePath.split('/').last;
                return ListTile(
                  title: Text(fileName),
                  onTap: () async {
                    await OpenFile.open(filePath);
                  },
                );
              },
            );
          }
        },
      ),
    );
  }
}
