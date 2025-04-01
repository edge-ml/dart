import 'package:flutter/material.dart';

import 'csv_collector_example.dart';
import 'online_collector_example.dart';

void main() {
  runApp(MouseDragTrackerApp());
}

class MouseDragTrackerApp extends StatelessWidget {
  const MouseDragTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mouse & Drag Tracker',
      home: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Text('Mouse & Drag Tracker'),
            bottom: TabBar(tabs: [Tab(text: 'Online'), Tab(text: 'CSV')]),
          ),
          body: TabBarView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: OnlineCollectorExample(),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: CsvCollectorExample(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
