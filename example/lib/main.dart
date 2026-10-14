import 'dart:async';

import 'package:edge_ml_dart/edge_ml_dart.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// edge-ml example: record the phone's motion sensors with labels, train a
/// model from a preset and classify live sensor data on the device.
void main() => runApp(const ExampleApp());

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  EdgeML? _edgeml;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final key = prefs.getString('apiKey');
      final url = prefs.getString('backendUrl') ?? EdgeML.defaultBackendUrl;
      setState(() {
        _edgeml = key == null ? null : EdgeML(apiKey: key, backendUrl: url);
        _loading = false;
      });
    });
  }

  Future<void> _connect(String url, String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backendUrl', url);
    await prefs.setString('apiKey', key);
    _edgeml?.close();
    setState(() => _edgeml = EdgeML(apiKey: key, backendUrl: url));
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'edge-ml example',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: _loading
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : _edgeml == null
        ? SettingsPage(onSave: _connect)
        : HomePage(edgeml: _edgeml!, onSettings: () => setState(() => _edgeml = null)),
  );
}

/// Backend URL (hosted or self-hosted) and the project's device API key.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.onSave});

  final Future<void> Function(String url, String key) onSave;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _url = TextEditingController(text: EdgeML.defaultBackendUrl);
  final _key = TextEditingController();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Connect to edge-ml')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _url,
          decoration: const InputDecoration(
            labelText: 'Backend URL',
            helperText: 'Change it for a self-hosted edge-ml',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _key,
          decoration: const InputDecoration(
            labelText: 'Device API write key',
            helperText: 'edge-ml → project settings → Device API',
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: () => widget.onSave(_url.text, _key.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.edgeml, required this.onSettings});

  final EdgeML edgeml;
  final VoidCallback onSettings;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DatasetsPage(edgeml: widget.edgeml),
      RecordPage(edgeml: widget.edgeml),
      TrainPage(edgeml: widget.edgeml),
      PredictPage(edgeml: widget.edgeml),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('edge-ml'),
        actions: [IconButton(icon: const Icon(Icons.settings), onPressed: widget.onSettings)],
      ),
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dataset), label: 'Datasets'),
          NavigationDestination(icon: Icon(Icons.fiber_manual_record), label: 'Record'),
          NavigationDestination(icon: Icon(Icons.model_training), label: 'Train'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Predict'),
        ],
      ),
    );
  }
}

void _showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is EdgeMLException ? e.message : '$e')));
}

const sensors = ['accX', 'accY', 'accZ', 'gyroX', 'gyroY', 'gyroZ'];

/// Accelerometer events joined with the latest gyroscope values, ~50 Hz.
Stream<Map<String, double>> motionSamples() {
  const period = SensorInterval.gameInterval;
  final gyro = <String, double>{};
  final controller = StreamController<Map<String, double>>();
  final subs = <StreamSubscription<Object>>[];
  controller.onListen = () {
    subs.add(
      gyroscopeEventStream(samplingPeriod: period).listen((e) {
        gyro.addAll({'gyroX': e.x, 'gyroY': e.y, 'gyroZ': e.z});
      }, onError: controller.addError),
    );
    subs.add(
      accelerometerEventStream(samplingPeriod: period).listen((e) {
        if (gyro.isEmpty) return;
        controller.add({'accX': e.x, 'accY': e.y, 'accZ': e.z, ...gyro});
      }, onError: controller.addError),
    );
  };
  controller.onCancel = () => Future.wait(subs.map((s) => s.cancel()));
  return controller.stream;
}

class DatasetsPage extends StatefulWidget {
  const DatasetsPage({super.key, required this.edgeml});

  final EdgeML edgeml;

  @override
  State<DatasetsPage> createState() => _DatasetsPageState();
}

class _DatasetsPageState extends State<DatasetsPage> {
  late Future<List<Dataset>> _datasets = widget.edgeml.datasets.list();

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async => setState(() => _datasets = widget.edgeml.datasets.list()),
    child: FutureBuilder(
      future: _datasets,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final datasets = snapshot.data!;
        if (datasets.isEmpty) return const Center(child: Text('No datasets yet. Record one!'));
        return ListView(
          children: [
            for (final ds in datasets)
              ListTile(
                title: Text(ds.name),
                subtitle: Text(
                  '${ds.timeSeries.map((t) => t.name).join(', ')}\n'
                  'labels: ${ds.labels.map((l) => l.label).toSet().join(', ')}',
                ),
                isThreeLine: true,
              ),
          ],
        );
      },
    ),
  );
}

/// Records the motion sensors into a new dataset; tap a label while recording
/// to label from that moment on.
class RecordPage extends StatefulWidget {
  const RecordPage({super.key, required this.edgeml});

  final EdgeML edgeml;

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  final _name = TextEditingController(text: 'recording');
  final _labeling = TextEditingController(text: 'activity');
  final _labels = TextEditingController(text: 'walk, run, sit');
  DatasetCollector? _collector;
  StreamSubscription<Map<String, double>>? _sub;
  String? _activeLabel;
  int _samples = 0;

  List<String> get _labelNames => [
    for (final l in _labels.text.split(','))
      if (l.trim().isNotEmpty) l.trim(),
  ];

  Future<void> _start() async {
    try {
      final collector = await widget.edgeml.datasets.collector(_name.text, sensors);
      setState(() {
        _collector = collector;
        _samples = 0;
      });
      _sub = motionSamples().listen((sample) {
        try {
          collector.addSample(sample);
          setState(() => _samples++);
        } catch (e) {
          if (mounted) _showError(context, e);
          _stop();
        }
      });
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  Future<void> _stop() async {
    final collector = _collector;
    await _sub?.cancel();
    setState(() {
      _collector = null;
      _activeLabel = null;
    });
    if (collector == null || collector.isCompleted) return;
    try {
      await collector.complete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dataset uploaded')));
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  void _label(String? label) {
    final collector = _collector!;
    if (label == null) {
      collector.stopLabel(_labeling.text);
    } else {
      collector.startLabel(_labeling.text, label);
    }
    setState(() => _activeLabel = label);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _collector?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recording = _collector != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _name,
          enabled: !recording,
          decoration: const InputDecoration(labelText: 'Dataset name'),
        ),
        TextField(
          controller: _labeling,
          enabled: !recording,
          decoration: const InputDecoration(labelText: 'Labeling'),
        ),
        TextField(
          controller: _labels,
          enabled: !recording,
          decoration: const InputDecoration(labelText: 'Labels (comma separated)'),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record),
          label: Text(recording ? 'Stop and upload ($_samples samples)' : 'Start recording'),
          onPressed: recording ? _stop : _start,
        ),
        if (recording) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('no label'),
                selected: _activeLabel == null,
                onSelected: (_) => _label(null),
              ),
              for (final l in _labelNames)
                ChoiceChip(label: Text(l), selected: _activeLabel == l, onSelected: (_) => _label(l)),
            ],
          ),
        ],
      ],
    );
  }
}

/// Trains a model from a preset and shows its progress.
class TrainPage extends StatefulWidget {
  const TrainPage({super.key, required this.edgeml});

  final EdgeML edgeml;

  @override
  State<TrainPage> createState() => _TrainPageState();
}

class _TrainPageState extends State<TrainPage> {
  final _name = TextEditingController(text: 'my-model');
  late final Future<(List<Labeling>, List<Preset>)> _options = (
    widget.edgeml.datasets.labelings(),
    widget.edgeml.models.presets(),
  ).wait;
  String? _labeling;
  String _preset = Presets.mediumCnn;
  String? _status;
  bool _training = false;

  Future<void> _train() async {
    setState(() {
      _training = true;
      _status = 'Starting…';
    });
    try {
      final model = await widget.edgeml.models.train(
        name: _name.text,
        labeling: _labeling!,
        preset: _preset,
        onProgress: (m) => setState(() => _status = '${m.status.name} ${m.stage ?? ''} ${m.progress ?? ''}'),
        onWarning: (w) => _showError(context, w),
      );
      setState(() => _status = 'Done: ${model.name} predicts ${model.labels.join(', ')}');
    } catch (e) {
      setState(() => _status = null);
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _training = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _options,
    builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final (labelings, presets) = snapshot.data!;
      if (labelings.isEmpty) return const Center(child: Text('Record a labeled dataset first.'));
      _labeling ??= labelings.first.name;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Model name'),
          ),
          DropdownButtonFormField(
            initialValue: _labeling,
            decoration: const InputDecoration(labelText: 'Labeling'),
            items: [for (final l in labelings) DropdownMenuItem(value: l.name, child: Text(l.name))],
            onChanged: (v) => setState(() => _labeling = v),
          ),
          DropdownButtonFormField(
            initialValue: _preset,
            decoration: const InputDecoration(labelText: 'Preset'),
            items: [for (final p in presets) DropdownMenuItem(value: p.id, child: Text(p.name))],
            onChanged: (v) => setState(() => _preset = v!),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _training ? null : _train, child: const Text('Train')),
          if (_status != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_status!)),
        ],
      );
    },
  );
}

/// Runs a trained model on live sensor data.
class PredictPage extends StatefulWidget {
  const PredictPage({super.key, required this.edgeml});

  final EdgeML edgeml;

  @override
  State<PredictPage> createState() => _PredictPageState();
}

class _PredictPageState extends State<PredictPage> {
  late final Future<List<ModelInfo>> _models = widget.edgeml.models.list();
  Predictor? _predictor;
  StreamSubscription<Map<String, double>>? _sub;
  Timer? _timer;
  Prediction? _prediction;
  bool _loading = false;

  Future<void> _run(ModelInfo model) async {
    await _stop();
    setState(() => _loading = true);
    try {
      final predictor = await widget.edgeml.models.load(model.id);
      _sub = motionSamples().listen(predictor.addSample);
      // classify as often as the training windows overlapped
      final hz = predictor.manifest.classificationFrequencyHz ?? 2;
      _timer = Timer.periodic(Duration(milliseconds: (1000 / hz).round().clamp(100, 5000)), (_) async {
        if (!predictor.isReady) return;
        final p = await predictor.predict();
        if (mounted) setState(() => _prediction = p);
      });
      setState(() => _predictor = predictor);
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _stop() async {
    _timer?.cancel();
    await _sub?.cancel();
    await _predictor?.dispose();
    _predictor = null;
    _prediction = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _models,
    builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final models = snapshot.data!.where((m) => m.runsOnDevice).toList();
      if (models.isEmpty) return const Center(child: Text('Train a model first.'));
      final p = _prediction;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final m in models)
            ListTile(
              title: Text(m.name),
              subtitle: Text(m.labels.join(', ')),
              selected: _predictor?.manifest.modelId == m.id,
              onTap: _loading ? null : () => _run(m),
            ),
          if (_loading) const LinearProgressIndicator(),
          if (_predictor != null && p == null) const Text('Collecting the first window…'),
          if (p != null) ...[
            const SizedBox(height: 16),
            Text(p.label, style: Theme.of(context).textTheme.displaySmall),
            for (final MapEntry(key: label, value: prob) in p.byLabel.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 80, child: Text(label)),
                    Expanded(child: LinearProgressIndicator(value: prob)),
                  ],
                ),
              ),
          ],
        ],
      );
    },
  );
}
