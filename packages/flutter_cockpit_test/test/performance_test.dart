import 'package:flutter/material.dart';
import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  cockpitTestWidgets(
    'profiles an action without requiring VM timeline',
    app: () => const MaterialApp(home: _ProfilePage()),
    body: (cockpit) async {
      final report = await cockpit.profile(
        () => cockpit.tap('#increment'),
        name: 'increment',
        timeline: false,
      );

      expect(report.stepId, 'increment');
      expect(report.timelineSource, isNull);
      expect(
        report.summary.frameCount,
        report.frames.length + report.droppedFrames,
      );
      expect(cockpit.report['performance'], isA<List<Object?>>());
    },
  );
}

final class _ProfilePage extends StatefulWidget {
  const _ProfilePage();

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

final class _ProfilePageState extends State<_ProfilePage> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          Text('Count $_count'),
          ElevatedButton(
            key: const ValueKey<String>('increment'),
            onPressed: () => setState(() => _count += 1),
            child: const Text('Increment'),
          ),
        ],
      ),
    );
  }
}
