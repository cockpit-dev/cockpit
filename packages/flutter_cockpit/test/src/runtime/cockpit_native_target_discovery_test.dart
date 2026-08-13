// ignore_for_file: deprecated_member_use

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'discovers public Cupertino controls without internal target noise',
    (tester) async {
      var checked = false;
      var toggled = false;
      var selectedRadio = 0;
      var selectedSegment = 0;
      var selectedSlidingSegment = 0;
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        CockpitSurface(
          routeName: '/cupertino',
          child: CupertinoApp(
            home: CupertinoPageScaffold(
              child: StatefulBuilder(
                builder: (context, setState) => ListView(
                  children: <Widget>[
                    CupertinoButton(
                      key: const ValueKey<String>('continue'),
                      onPressed: () {},
                      child: const Text('Continue'),
                    ),
                    CupertinoListTile(
                      key: const ValueKey<String>('settings'),
                      title: const Text('Settings'),
                      onTap: () {},
                    ),
                    CupertinoCheckbox(
                      key: const ValueKey<String>('checked'),
                      value: checked,
                      onChanged: (value) =>
                          setState(() => checked = value ?? false),
                    ),
                    CupertinoSwitch(
                      key: const ValueKey<String>('enabled'),
                      value: toggled,
                      onChanged: (value) => setState(() => toggled = value),
                    ),
                    CupertinoRadio<int>(
                      key: const ValueKey<String>('radio-editor'),
                      value: 1,
                      groupValue: selectedRadio,
                      onChanged: (value) =>
                          setState(() => selectedRadio = value ?? 0),
                    ),
                    CupertinoTextField(
                      key: const ValueKey<String>('message'),
                      controller: controller,
                      placeholder: 'Message',
                    ),
                    CupertinoSlider(
                      key: const ValueKey<String>('volume'),
                      value: 0.25,
                      onChanged: (_) {},
                    ),
                    CupertinoSegmentedControl<int>(
                      key: const ValueKey<String>('display-mode'),
                      children: const <int, Widget>{
                        0: Text('One'),
                        1: Text('Two'),
                      },
                      groupValue: selectedSegment,
                      onValueChanged: (value) =>
                          setState(() => selectedSegment = value),
                    ),
                    CupertinoSlidingSegmentedControl<int>(
                      key: const ValueKey<String>('layout-mode'),
                      children: const <int, Widget>{
                        0: Text('Grid'),
                        1: Text('List'),
                      },
                      groupValue: selectedSlidingSegment,
                      onValueChanged: (value) =>
                          setState(() => selectedSlidingSegment = value ?? 0),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );
      CockpitTarget targetForKey(String key) {
        final resolution = state.registry.resolve(CockpitLocator(key: key));
        expect(resolution.isSuccess, isTrue, reason: resolution.error?.message);
        return resolution.target!;
      }

      expect(targetForKey('continue').typeName, 'CupertinoButton');
      expect(targetForKey('settings').typeName, 'CupertinoListTile');
      expect(targetForKey('checked').typeName, 'CupertinoCheckbox');
      expect(targetForKey('enabled').typeName, 'CupertinoSwitch');
      expect(targetForKey('radio-editor').typeName, 'CupertinoRadio');
      final input = targetForKey('message');
      expect(input.typeName, 'CupertinoTextField');
      expect(input.supportedCommands, contains(CockpitCommandType.enterText));
      expect(targetForKey('volume').typeName, 'CupertinoSlider');
      expect(
        targetForKey('volume').supportedCommands,
        containsAll(<CockpitCommandType>[
          CockpitCommandType.increase,
          CockpitCommandType.decrease,
        ]),
      );

      input.onEnterText?.call('Hello');
      targetForKey('checked').onTap?.call();
      targetForKey('enabled').onTap?.call();
      targetForKey('radio-editor').onTap?.call();
      state.registry
          .resolve(const CockpitLocator(text: 'Two'))
          .target!
          .onTap
          ?.call();
      state.registry
          .resolve(const CockpitLocator(text: 'List'))
          .target!
          .onTap
          ?.call();
      await tester.pumpAndSettle();

      expect(controller.text, 'Hello');
      expect(checked, isTrue);
      expect(toggled, isTrue);
      expect(selectedRadio, 1);
      expect(selectedSegment, 1);
      expect(selectedSlidingSegment, 1);
      expect(
        state.registry.visibleTargets
            .where((target) => target.typeName == 'CupertinoSegment')
            .map((target) => target.text),
        containsAllInOrder(<String>['One', 'Two', 'Grid', 'List']),
      );
      expect(
        state.registry.visibleTargets,
        isNot(
          contains(
            predicate<CockpitTarget>((target) {
              final key = target.keyValue;
              return key != null && key.startsWith("[<'");
            }),
          ),
        ),
      );
    },
  );

  testWidgets('discovers enterText support for a keyed TextField', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    final target = await _resolveKeyedInputTarget(
      tester,
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: TextField(
              key: const ValueKey<String>('task-input'),
              controller: controller,
              decoration: const InputDecoration(labelText: 'Task title'),
            ),
          ),
        ),
      ),
    );

    expect(target.supportedCommands, contains(CockpitCommandType.tap));
    expect(target.supportedCommands, contains(CockpitCommandType.enterText));
    expect(
      target.supportedCommands,
      containsAll(<CockpitCommandType>[
        CockpitCommandType.focusTextInput,
        CockpitCommandType.setTextEditingValue,
        CockpitCommandType.sendTextInputAction,
      ]),
    );

    target.onTap?.call();
    await tester.pump();
    target.onEnterText?.call('Gesture backlog');
    await tester.pump();

    expect(controller.text, 'Gesture backlog');
  });

  testWidgets('discovers enterText support for a keyed TextFormField', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    final target = await _resolveKeyedInputTarget(
      tester,
      MaterialApp(
        home: Scaffold(
          body: Form(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: TextFormField(
                key: const ValueKey<String>('task-input'),
                controller: controller,
                decoration: const InputDecoration(labelText: 'Task title'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(target.supportedCommands, contains(CockpitCommandType.tap));
    expect(target.supportedCommands, contains(CockpitCommandType.enterText));
    expect(
      target.supportedCommands,
      containsAll(<CockpitCommandType>[
        CockpitCommandType.focusTextInput,
        CockpitCommandType.setTextEditingValue,
        CockpitCommandType.sendTextInputAction,
      ]),
    );

    target.onTap?.call();
    await tester.pump();
    target.onEnterText?.call('Production handoff');
    await tester.pump();

    expect(controller.text, 'Production handoff');
  });

  testWidgets('resolves unlabeled text input targets by field label text', (
    tester,
  ) async {
    final titleController = TextEditingController();
    final notesController = TextEditingController();
    addTearDown(titleController.dispose);
    addTearDown(notesController.dispose);

    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/editor',
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Task title'),
                ),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final resolution = surfaceState.registry.resolve(
      const CockpitLocator(text: 'Task title', type: 'TextField'),
    );

    expect(resolution.isSuccess, isTrue);
    final target = resolution.target;
    expect(target, isNotNull);
    target!.onEnterText?.call('AI planned title');
    await tester.pump();

    expect(titleController.text, 'AI planned title');
    expect(notesController.text, isEmpty);
  });

  testWidgets(
    'prefers the field label over a prefilled input value for text targeting',
    (tester) async {
      final controller = TextEditingController(
        text: 'Existing follow-up title',
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        CockpitSurface(
          routeName: '/detail',
          child: MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Follow-up title',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );
      final resolution = surfaceState.registry.resolve(
        const CockpitLocator(text: 'Follow-up title', type: 'TextField'),
      );

      expect(resolution.isSuccess, isTrue);
      final target = resolution.target;
      expect(target, isNotNull);
      target!.onEnterText?.call('Next follow-up title');
      await tester.pump();

      expect(controller.text, 'Next follow-up title');
    },
  );

  testWidgets('discovers interactive targets by their own key', (tester) async {
    var selected = false;

    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/editor',
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChoiceChip(
                key: const ValueKey<String>('task-priority-urgent'),
                selected: selected,
                label: const Text('URGENT'),
                onSelected: (_) {
                  selected = true;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final resolution = surfaceState.registry.resolve(
      const CockpitLocator(key: 'task-priority-urgent'),
    );

    expect(resolution.isSuccess, isTrue);
    final target = resolution.target;
    expect(target, isNotNull);
    expect(target!.supportedCommands, contains(CockpitCommandType.tap));

    target.onTap?.call();
    await tester.pump();

    expect(selected, isTrue);
  });

  testWidgets(
    'resolves TextButton.icon with the public TextButton type signal',
    (tester) async {
      var openedEditor = false;

      await tester.pumpWidget(
        CockpitSurface(
          routeName: '/inbox',
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: <Widget>[
                  TextButton.icon(
                    key: const ValueKey<String>('open-task-editor-action'),
                    onPressed: () {
                      openedEditor = true;
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('New task'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );
      final resolution = surfaceState.registry.resolve(
        const CockpitLocator(
          key: 'open-task-editor-action',
          text: 'New task',
          type: 'TextButton',
          route: '/inbox',
          ancestor: CockpitLocator(route: '/inbox'),
        ),
      );

      expect(resolution.isSuccess, isTrue, reason: resolution.error?.message);
      final target = resolution.target;
      expect(target, isNotNull);
      expect(target!.supportedCommands, contains(CockpitCommandType.tap));

      target.onTap?.call();
      await tester.pump();

      expect(openedEditor, isTrue);
    },
  );

  testWidgets('does not expose private-use icon glyphs as locator text', (
    tester,
  ) async {
    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/commands',
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: IconButton(
                onPressed: () {},
                tooltip: 'Available commands',
                icon: const Icon(Icons.add),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final target = surfaceState.registry.visibleTargets.singleWhere(
      (target) =>
          target.typeName == 'IconButton' &&
          target.tooltip == 'Available commands',
    );

    expect(target.text, isNull);
    expect(target.textParts, isEmpty);
    expect(target.supportedCommands, contains(CockpitCommandType.tap));
  });

  testWidgets('generates compact stable registration ids for native targets', (
    tester,
  ) async {
    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/inbox',
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey<String>('fab-add-task'),
                onPressed: () {},
                child: const Text('New task'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final target = surfaceState.registry.visibleTargets.singleWhere(
      (target) => target.keyValue == 'fab-add-task',
    );

    expect(target.registrationId, startsWith('native.inbox.elevatedbutton.'));
    expect(target.registrationId, isNot(contains('root.')));
    expect(target.registrationId.length, lessThanOrEqualTo(72));
  });

  testWidgets('does not leak ancestor keys onto actionable descendants', (
    tester,
  ) async {
    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/editor',
        child: MaterialApp(
          home: Scaffold(
            body: Container(
              key: const ValueKey<String>('task-row-shell'),
              padding: const EdgeInsets.all(16),
              child: InkWell(onTap: () {}, child: const Text('Open task')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final keyedTargets = surfaceState.registry.visibleTargets
        .where((target) => target.keyValue == 'task-row-shell')
        .toList(growable: false);

    expect(keyedTargets, hasLength(1));
    expect(keyedTargets.single.supportedCommands, isEmpty);
    expect(
      surfaceState.registry
          .resolve(const CockpitLocator(key: 'task-row-shell'))
          .isSuccess,
      isTrue,
    );
  });

  testWidgets('does not duplicate ancestor keys across passive descendants', (
    tester,
  ) async {
    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/inbox',
        child: MaterialApp(
          home: Scaffold(
            floatingActionButton: FloatingActionButton.extended(
              key: const ValueKey<String>('fab-add-task'),
              onPressed: () {},
              label: const Text('New task'),
            ),
            body: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final keyedTargets = surfaceState.registry.visibleTargets
        .where((target) => target.keyValue == 'fab-add-task')
        .toList(growable: false);

    expect(keyedTargets, hasLength(1));
    expect(
      keyedTargets.single.supportedCommands,
      contains(CockpitCommandType.tap),
    );
  });

  testWidgets(
    'hasDiscoverableTarget uses the same visibility rules as discovery',
    (tester) async {
      await tester.pumpWidget(
        CockpitSurface(
          routeName: '/inbox',
          child: MaterialApp(
            home: Scaffold(
              floatingActionButton: FloatingActionButton.extended(
                key: const ValueKey<String>('fab-add-task'),
                onPressed: () {},
                label: const Text('New task'),
              ),
              body: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pump();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );

      expect(surfaceState.registry.visibleTargets, isNotEmpty);
      expect(surfaceState.registry.hasRouteReadyVisibleTargets, isTrue);
    },
  );

  testWidgets(
    'hasDiscoverableTarget excludes inactive route fallback targets',
    (tester) async {
      await tester.pumpWidget(
        CockpitSurface(
          routeName: '/editor',
          child: MaterialApp(
            initialRoute: '/inbox',
            routes: <String, WidgetBuilder>{
              '/inbox': (context) => Scaffold(
                floatingActionButton: FloatingActionButton.extended(
                  key: const ValueKey<String>('fab-add-task'),
                  onPressed: () {},
                  label: const Text('New task'),
                ),
                body: const SizedBox.expand(),
              ),
              '/editor': (context) => const Scaffold(body: Text('Editor')),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );
      surfaceState.registry.routeName = '/editor';

      expect(surfaceState.registry.visibleTargets, isNotEmpty);
      expect(surfaceState.registry.routeReadyVisibleTargets, isEmpty);
      expect(surfaceState.registry.hasRouteReadyVisibleTargets, isFalse);
    },
  );

  testWidgets('inherits semantic labels onto actionable descendants', (
    tester,
  ) async {
    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/inbox',
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: Semantics(
                label: 'Open task Semantic alpha',
                button: true,
                child: InkWell(
                  key: const ValueKey<String>('task-open-alpha'),
                  onTap: () {},
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Semantic alpha'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final semanticTargets = surfaceState.registry.visibleTargets
        .where(
          (target) =>
              target.semanticId == 'Open task Semantic alpha' &&
              target.supportedCommands.contains(CockpitCommandType.tap),
        )
        .toList(growable: false);

    expect(semanticTargets, isNotEmpty);
  });

  testWidgets('explicit semantic children do not inherit container identity', (
    tester,
  ) async {
    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/inbox',
        child: Semantics(
          label: 'Launch configuration',
          tooltip: 'Launch configuration details',
          container: true,
          explicitChildNodes: true,
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            home: Scaffold(
              body: TextField(
                key: const ValueKey<String>('task-title-field'),
                decoration: const InputDecoration(labelText: 'Task title'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final field = surfaceState.registry.visibleTargets.singleWhere(
      (target) => target.keyValue == 'task-title-field',
    );

    expect(field.text, 'Task title');
    expect(field.semanticId, isNull);
    expect(field.cockpitId, 'task-title-field');
    expect(field.tooltip, isNull);
  });

  testWidgets('resolves an actionable composite control by exact child text', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/commands',
        child: MaterialApp(
          home: Scaffold(
            body: InkWell(
              onTap: () => tapped = true,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('/inspect'),
                  Text('Inspect the current project'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final resolution = surfaceState.registry.resolve(
      const CockpitLocator(text: '/inspect'),
      requiredCommand: CockpitCommandType.tap,
    );

    expect(resolution.isSuccess, isTrue);
    expect(resolution.target?.typeName, 'InkWell');
    expect(resolution.target?.textParts, contains('/inspect'));
    resolution.target?.onTap?.call();
    expect(tapped, isTrue);

    final snapshotTarget = surfaceState.snapshot().visibleTargets.firstWhere(
      (target) => target.typeName == 'InkWell',
    );
    expect(snapshotTarget.textParts, contains('/inspect'));
  });

  testWidgets('discovers long press and double tap handlers for native rows', (
    tester,
  ) async {
    var longPressed = false;
    var doubleTapped = false;

    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/inbox',
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: InkWell(
                key: const ValueKey<String>('task-open-alpha'),
                onTap: () {},
                onLongPress: () {
                  longPressed = true;
                },
                onDoubleTap: () {
                  doubleTapped = true;
                },
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Gesture alpha'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final resolution = surfaceState.registry.resolve(
      const CockpitLocator(key: 'task-open-alpha'),
    );

    expect(resolution.isSuccess, isTrue);
    final target = resolution.target!;
    expect(target.supportedCommands, contains(CockpitCommandType.longPress));
    expect(target.supportedCommands, contains(CockpitCommandType.doubleTap));

    target.onLongPress?.call();
    target.onDoubleTap?.call();

    expect(longPressed, isTrue);
    expect(doubleTapped, isTrue);
  });

  testWidgets(
    'deduplicates passive text across semantics wrappers and text widgets',
    (tester) async {
      await tester.pumpWidget(
        CockpitSurface(
          routeName: '/settings',
          child: MaterialApp(
            home: Scaffold(
              body: const Center(child: Text('Acceptance bundles')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );
      final matches = surfaceState.registry.visibleTargets
          .where((target) => target.text == 'Acceptance bundles')
          .toList(growable: false);

      expect(matches, hasLength(1));
    },
  );

  testWidgets(
    'deduplicates inherited passive semantics across visual descendants',
    (tester) async {
      await tester.pumpWidget(
        CockpitSurface(
          routeName: '/recording',
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: Semantics(
                  label: 'Live audio waveform, recording in progress',
                  container: true,
                  child: ExcludeSemantics(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 80),
                      child: SizedBox(
                        key: const ValueKey<String>('waveform-frame'),
                        width: 240,
                        height: 64,
                        child: CustomPaint(painter: _TestWaveformPainter()),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );
      final matches = surfaceState.registry.visibleTargets
          .where(
            (target) =>
                target.semanticId ==
                'Live audio waveform, recording in progress',
          )
          .toList(growable: false);

      expect(matches, hasLength(1));
    },
  );

  testWidgets(
    'does not assign merged descendant semantics text to passive keyed containers',
    (tester) async {
      await tester.pumpWidget(
        CockpitSurface(
          routeName: '/settings',
          child: MaterialApp(
            home: Scaffold(
              body: Semantics(
                container: true,
                child: Container(
                  key: const ValueKey<String>('delivery-card'),
                  padding: const EdgeInsets.all(16),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Storage and delivery'),
                      SizedBox(height: 12),
                      Text('Acceptance bundles'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );
      final deliveryTarget = surfaceState.registry.visibleTargets.singleWhere(
        (target) => target.keyValue == 'delivery-card',
      );

      expect(
        deliveryTarget.text,
        isNot(contains('Acceptance bundles')),
        reason:
            'The container should keep its own key signal without taking descendant text.',
      );
      expect(
        surfaceState.registry.visibleTargets.any(
          (target) => target.text == 'Acceptance bundles',
        ),
        isTrue,
      );
    },
  );

  testWidgets('preserves a passive Text key while deduplicating RichText', (
    tester,
  ) async {
    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/command-lab',
        child: const MaterialApp(
          home: Scaffold(
            body: Text('gesture:idle', key: Key('lab-gesture-status')),
          ),
        ),
      ),
    );
    await tester.pump();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final resolution = surfaceState.registry.resolve(
      const CockpitLocator(key: 'lab-gesture-status'),
    );

    expect(resolution.isSuccess, isTrue);
    expect(resolution.target?.text, 'gesture:idle');
    expect(resolution.target?.typeName, 'Text');
  });

  testWidgets(
    'tristate checkbox direct handler follows the false, true, null cycle',
    (tester) async {
      bool? value = false;

      await tester.pumpWidget(
        CockpitSurface(
          routeName: '/settings',
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (context, setState) => Checkbox(
                    key: const ValueKey<String>('task-flag'),
                    tristate: true,
                    value: value,
                    onChanged: (next) => setState(() => value = next),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );
      Future<void> tapCheckbox() async {
        final resolution = surfaceState.registry.resolve(
          const CockpitLocator(key: 'task-flag'),
        );
        expect(resolution.isSuccess, isTrue, reason: resolution.error?.message);
        resolution.target!.onTap!();
        await tester.pump();
      }

      await tapCheckbox();
      expect(value, isTrue);
      await tapCheckbox();
      expect(value, isNull);
      await tapCheckbox();
      expect(value, isFalse);
    },
  );

  testWidgets('non-tristate checkbox direct handler keeps the boolean toggle', (
    tester,
  ) async {
    var value = false;

    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/settings',
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) => Checkbox(
                  key: const ValueKey<String>('task-done'),
                  value: value,
                  onChanged: (next) => setState(() => value = next ?? false),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    Future<void> tapCheckbox() async {
      final resolution = surfaceState.registry.resolve(
        const CockpitLocator(key: 'task-done'),
      );
      expect(resolution.isSuccess, isTrue, reason: resolution.error?.message);
      resolution.target!.onTap!();
      await tester.pump();
    }

    await tapCheckbox();
    expect(value, isTrue);
    await tapCheckbox();
    expect(value, isFalse);
  });

  testWidgets(
    'does not resolve text targets that only barely overlap the viewport',
    (tester) async {
      await tester.pumpWidget(
        CockpitSurface(
          routeName: '/settings',
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 220,
                child: ListView(
                  children: const <Widget>[
                    SizedBox(height: 210),
                    Text('Acceptance bundles'),
                    SizedBox(height: 400),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );

      expect(
        surfaceState.registry
            .resolve(const CockpitLocator(text: 'Acceptance bundles'))
            .isSuccess,
        isFalse,
      );
    },
  );
}

class _TestWaveformPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.blue;
    for (var index = 0; index < 16; index += 1) {
      final x = index * size.width / 16;
      canvas.drawRect(Rect.fromLTWH(x, 24, 4, 16), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<CockpitTarget> _resolveKeyedInputTarget(
  WidgetTester tester,
  Widget child,
) async {
  await tester.pumpWidget(CockpitSurface(routeName: '/editor', child: child));
  await tester.pump();

  final surfaceState = tester.state<CockpitSurfaceState>(
    find.byType(CockpitSurface),
  );
  final resolution = surfaceState.registry.resolve(
    const CockpitLocator(key: 'task-input'),
  );
  final testIdResolution = surfaceState.registry.resolve(
    const CockpitLocator(cockpitId: 'task-input'),
  );

  expect(resolution.isSuccess, isTrue);
  expect(testIdResolution.isSuccess, isTrue);
  final target = resolution.target;
  expect(target, isNotNull);
  expect(testIdResolution.target?.registrationId, target?.registrationId);
  return target!;
}
