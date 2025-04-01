import 'dart:async';

import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:flutter/material.dart';

import 'mouse_tracker.dart';

const String edgeMlUrl = String.fromEnvironment(
  'EDGE_ML_URL',
  defaultValue: 'https://app.edge-ml.org',
);
const String edgeMlApiKey = String.fromEnvironment(
  'EDGE_ML_API_KEY',
  defaultValue: '',
);

class OnlineCollectorExample extends StatefulWidget {
  const OnlineCollectorExample({super.key});

  @override
  State<OnlineCollectorExample> createState() => _OnlineCollectorExampleState();
}

class _OnlineCollectorExampleState extends State<OnlineCollectorExample> {
  OnlineDatasetCollector? _onlineDatasetCollector;

  final TextEditingController _urlController = TextEditingController(
    text: edgeMlUrl,
  );
  final TextEditingController _apiKeyController = TextEditingController(
    text: edgeMlApiKey,
  );
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
    _onlineDatasetCollector?.addDataPoint(name: "mouseX", value: _cursorX);
    _onlineDatasetCollector?.addDataPoint(name: "mouseY", value: _cursorY);
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

      String url = _urlController.text;
      String apiKey = _apiKeyController.text;
      String datasetName = _datasetNameController.text;
      int frequency = _frequency.toInt();

      try {
        _onlineDatasetCollector = await OnlineDatasetCollector.create(
          url: url,
          key: apiKey,
          name: datasetName,
          useDeviceTime: true,
          timeSeries: ["mouseX", "mouseY"],
          metaData: {"app": "example"},
          datasetLabel: "mouse",
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
          controller: _urlController,
          decoration: InputDecoration(
            labelText: 'URL',
            border: OutlineInputBorder(),
          ),
          enabled: !_tracking && !_starting,
        ),
        SizedBox(height: 16.0),
        TextField(
          controller: _apiKeyController,
          decoration: InputDecoration(
            labelText: 'API Key',
            border: OutlineInputBorder(),
          ),
          enabled: !_tracking && !_starting,
        ),
        SizedBox(height: 16.0),
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
