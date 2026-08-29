// ignore_for_file: deprecated_member_use

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'exposes control state without advertising disabled or read-only actions',
    (tester) async {
      final draft = TextEditingController(text: 'Draft');
      final secret = TextEditingController(text: 'secret-value');
      addTearDown(draft.dispose);
      addTearDown(secret.dispose);

      await tester.pumpWidget(
        CockpitSurface(
          routeName: '/states',
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: <Widget>[
                  const FilledButton(
                    key: ValueKey<String>('disabled-save'),
                    onPressed: null,
                    child: Text('Save'),
                  ),
                  const Checkbox(
                    key: ValueKey<String>('disabled-check'),
                    value: false,
                    onChanged: null,
                  ),
                  const Radio<int>(
                    key: ValueKey<String>('disabled-radio'),
                    value: 1,
                    groupValue: 0,
                    onChanged: null,
                  ),
                  const RadioListTile<int>(
                    key: ValueKey<String>('disabled-radio-tile'),
                    value: 1,
                    groupValue: 0,
                    onChanged: null,
                    title: Text('Disabled radio tile'),
                  ),
                  const CupertinoRadio<int>(
                    key: ValueKey<String>('disabled-cupertino-radio'),
                    value: 1,
                    groupValue: 0,
                    onChanged: null,
                  ),
                  Switch(
                    key: const ValueKey<String>('active-switch'),
                    value: true,
                    onChanged: (_) {},
                  ),
                  TextField(
                    key: const ValueKey<String>('read-only-input'),
                    controller: draft,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Draft'),
                  ),
                  TextField(
                    key: const ValueKey<String>('secret-input'),
                    controller: secret,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Secret'),
                  ),
                  SegmentedButton<String>(
                    segments: const <ButtonSegment<String>>[
                      ButtonSegment<String>(value: 'grid', label: Text('Grid')),
                      ButtonSegment<String>(value: 'list', label: Text('List')),
                    ],
                    selected: const <String>{'grid'},
                    onSelectionChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final registry = tester
          .state<CockpitSurfaceState>(find.byType(CockpitSurface))
          .registry;
      CockpitTarget byKey(String key) =>
          registry.resolve(CockpitLocator(key: key)).target!;

      final disabledButton = byKey('disabled-save');
      expect(disabledButton.control?.enabled, isFalse);
      expect(
        disabledButton.supportedCommands,
        isNot(contains(CockpitCommandType.tap)),
      );

      final disabledCheck = byKey('disabled-check');
      expect(disabledCheck.control?.enabled, isFalse);
      expect(disabledCheck.control?.checked, CockpitCheckState.off);

      for (final key in const <String>[
        'disabled-radio',
        'disabled-radio-tile',
        'disabled-cupertino-radio',
      ]) {
        final radio = byKey(key);
        expect(radio.control?.enabled, isFalse, reason: key);
        expect(radio.control?.checked, CockpitCheckState.off, reason: key);
        expect(
          radio.supportedCommands,
          isNot(contains(CockpitCommandType.tap)),
          reason: key,
        );
      }

      final activeSwitch = byKey('active-switch');
      expect(activeSwitch.control?.enabled, isTrue);
      expect(activeSwitch.control?.checked, CockpitCheckState.on);
      expect(activeSwitch.supportedCommands, contains(CockpitCommandType.tap));

      final readOnly = byKey('read-only-input');
      expect(readOnly.control?.readOnly, isTrue);
      expect(readOnly.control?.value, 'Draft');
      expect(
        readOnly.supportedCommands,
        isNot(
          containsAll(<CockpitCommandType>[
            CockpitCommandType.tap,
            CockpitCommandType.longPress,
            CockpitCommandType.enterText,
          ]),
        ),
      );

      final obscured = byKey('secret-input');
      expect(obscured.control?.obscured, isTrue);
      expect(obscured.control?.value, isNull);

      final grid = registry.resolve(const CockpitLocator(text: 'Grid')).target!;
      final list = registry.resolve(const CockpitLocator(text: 'List')).target!;
      expect(grid.control?.selected, isTrue);
      expect(list.control?.selected, isFalse);
    },
  );

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

  testWidgets('discovers controls without keys or developer-authored semantics', (
    tester,
  ) async {
    var tapped = false;
    var longPressed = false;
    var doubleTapped = false;
    var sliderValue = 0.5;
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/invoice',
        child: MaterialApp(
          home: Scaffold(
            body: ExcludeSemantics(
              child: StatefulBuilder(
                builder: (context, setState) => Column(
                  children: <Widget>[
                    Material(
                      child: InkResponse(
                        onTap: () => tapped = true,
                        onLongPress: () => longPressed = true,
                        onDoubleTap: () => doubleTapped = true,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Open invoice'),
                        ),
                      ),
                    ),
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'Invoice title',
                      ),
                    ),
                    Slider(
                      value: sliderValue,
                      divisions: 10,
                      onChanged: (value) => setState(() => sliderValue = value),
                    ),
                    PopupMenuButton<String>(
                      itemBuilder: (context) => const <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          value: 'archive',
                          child: Text('Archive'),
                        ),
                      ],
                      child: const Text('More actions'),
                    ),
                  ],
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
    final targets = surfaceState.registry.visibleTargets;
    final action = targets.singleWhere(
      (target) =>
          target.typeName == 'InkResponse' && target.text == 'Open invoice',
    );
    expect(action.keyValue, isNull);
    expect(action.semanticId, isNull);
    expect(
      action.supportedCommands,
      containsAll(<CockpitCommandType>[
        CockpitCommandType.tap,
        CockpitCommandType.longPress,
        CockpitCommandType.doubleTap,
      ]),
    );
    action.onTap?.call();
    action.onLongPress?.call();
    action.onDoubleTap?.call();
    expect(tapped, isTrue);
    expect(longPressed, isTrue);
    expect(doubleTapped, isTrue);

    final input = targets.singleWhere(
      (target) =>
          target.typeName == 'TextField' && target.text == 'Invoice title',
    );
    expect(input.keyValue, isNull);
    expect(input.semanticId, isNull);
    expect(input.supportedCommands, contains(CockpitCommandType.enterText));
    input.onEnterText?.call('August invoice');
    await tester.pump();
    expect(controller.text, 'August invoice');

    final sliderMatches = targets
        .where((target) => target.typeName?.contains('Slider') == true)
        .toList(growable: false);
    expect(
      sliderMatches,
      hasLength(1),
      reason: targets
          .map(
            (target) =>
                '${target.typeName}:${target.text}:${target.supportedCommands}',
          )
          .join('\n'),
    );
    var slider = sliderMatches.single;
    expect(slider.keyValue, isNull);
    expect(slider.semanticId, isNull);
    expect(
      slider.supportedCommands,
      containsAll(<CockpitCommandType>[
        CockpitCommandType.increase,
        CockpitCommandType.decrease,
      ]),
    );
    slider.onSemanticIncrease?.call();
    await tester.pump();
    expect(sliderValue, closeTo(0.6, 0.0001));
    slider = surfaceState.registry.visibleTargets.singleWhere(
      (target) => target.typeName == 'Slider',
    );
    slider.onSemanticDecrease?.call();
    await tester.pump();
    expect(sliderValue, closeTo(0.5, 0.0001));

    final popup = surfaceState.registry.visibleTargets.singleWhere(
      (target) =>
          target.typeName?.startsWith('PopupMenuButton') == true &&
          target.text == 'More actions',
    );
    expect(popup.keyValue, isNull);
    expect(popup.semanticId, isNull);
    expect(popup.supportedCommands, contains(CockpitCommandType.tap));
  });

  testWidgets(
    'discovers wheel owners without keys or semantics and keeps passive text compact',
    (tester) async {
      await tester.pumpWidget(
        CockpitSurface(
          routeName: '/wheel',
          child: MaterialApp(
            home: Scaffold(
              body: ExcludeSemantics(
                child: Column(
                  children: <Widget>[
                    SizedBox(
                      height: 220,
                      child: ListView.builder(
                        itemCount: 20,
                        itemBuilder: (context, index) =>
                            SizedBox(height: 40, child: Text('Row $index')),
                      ),
                    ),
                    SizedBox(
                      height: 80,
                      child: Listener(
                        onPointerSignal: (_) {},
                        child: const Text('Custom wheel surface'),
                      ),
                    ),
                    SizedBox(
                      height: 80,
                      child: InteractiveViewer(
                        trackpadScrollCausesScale: true,
                        child: const Text('Trackpad canvas'),
                      ),
                    ),
                    const Text('Passive text'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final targets = tester
          .state<CockpitSurfaceState>(find.byType(CockpitSurface))
          .registry
          .visibleTargets;
      final wheelTargets = targets
          .where(
            (target) =>
                target.supportedCommands.contains(CockpitCommandType.wheel),
          )
          .toList(growable: false);

      expect(wheelTargets, isEmpty);

      final passive = targets.singleWhere(
        (target) => target.text == 'Passive text',
      );
      expect(
        passive.supportedCommands,
        isNot(contains(CockpitCommandType.wheel)),
      );

      final state = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );
      final customWheel = state.probeVisibleLocator(
        const CockpitLocator(
          text: 'Custom wheel surface',
          ancestor: CockpitLocator(type: 'Listener'),
        ),
        requiredCommand: CockpitCommandType.wheel,
      );
      expect(customWheel.isSuccess, isTrue);
      expect(
        customWheel.target?.supportedCommands,
        contains(CockpitCommandType.wheel),
      );

      final scrollWheel = state.probeVisibleLocator(
        const CockpitLocator(
          text: 'Row 0',
          ancestor: CockpitLocator(type: 'Scrollable'),
        ),
        requiredCommand: CockpitCommandType.wheel,
      );
      expect(scrollWheel.isSuccess, isTrue);
      expect(
        scrollWheel.target?.supportedCommands,
        contains(CockpitCommandType.wheel),
      );

      final trackpadWheel = state.probeVisibleLocator(
        const CockpitLocator(
          text: 'Trackpad canvas',
          ancestor: CockpitLocator(type: 'InteractiveViewer'),
        ),
        requiredCommand: CockpitCommandType.wheel,
      );
      expect(trackpadWheel.isSuccess, isTrue);
      expect(
        trackpadWheel.target?.supportedCommands,
        contains(CockpitCommandType.wheel),
      );
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

  testWidgets('keeps a nested public control independently actionable', (
    tester,
  ) async {
    var cardTapped = false;
    var iconTapped = false;
    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/inbox',
        child: MaterialApp(
          home: Scaffold(
            body: GestureDetector(
              key: const ValueKey<String>('task-card'),
              onTap: () => cardTapped = true,
              child: Row(
                children: <Widget>[
                  const Expanded(child: Text('Task alpha')),
                  IconButton(
                    key: const ValueKey<String>('task-menu'),
                    tooltip: 'Task menu',
                    onPressed: () => iconTapped = true,
                    icon: const Icon(Icons.more_horiz),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final registry = tester
        .state<CockpitSurfaceState>(find.byType(CockpitSurface))
        .registry;
    final card = registry.resolve(const CockpitLocator(key: 'task-card'));
    final menu = registry.resolve(const CockpitLocator(key: 'task-menu'));

    expect(card.isSuccess, isTrue, reason: card.error?.message);
    expect(menu.isSuccess, isTrue, reason: menu.error?.message);
    card.target?.onTap?.call();
    menu.target?.onTap?.call();
    expect(cardTapped, isTrue);
    expect(iconTapped, isTrue);
  });

  testWidgets('keeps stable keyed scopes within bounded target ancestors', (
    tester,
  ) async {
    Widget section(String key) => Container(
      key: ValueKey<String>(key),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  tooltip: 'Expand output',
                  onPressed: () {},
                  icon: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/logs',
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[section('startup-logs'), section('app-logs')],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final registry = tester
        .state<CockpitSurfaceState>(find.byType(CockpitSurface))
        .registry;
    final targets = registry.visibleTargets
        .where(
          (target) =>
              target.typeName == 'IconButton' &&
              target.tooltip == 'Expand output',
        )
        .toList(growable: false);

    expect(targets, hasLength(2));
    for (final target in targets) {
      expect(
        target.locatorAncestors.take(8).map((ancestor) => ancestor.keyValue),
        contains(anyOf('startup-logs', 'app-logs')),
      );
    }
    expect(
      registry
          .resolve(
            const CockpitLocator(
              tooltip: 'Expand output',
              ancestor: CockpitLocator(key: 'startup-logs'),
            ),
            requiredCommand: CockpitCommandType.tap,
          )
          .isSuccess,
      isTrue,
    );
  });

  testWidgets('collapses a framework control wrapper into its live child', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/settings',
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(leading: BackButton(onPressed: () => tapped = true)),
          ),
        ),
      ),
    );
    await tester.pump();

    final registry = tester
        .state<CockpitSurfaceState>(find.byType(CockpitSurface))
        .registry;
    final backTargets = registry.visibleTargets
        .where((target) => target.tooltip == 'Back')
        .toList(growable: false);

    expect(backTargets, hasLength(1));
    expect(
      backTargets.single.supportedCommands,
      contains(CockpitCommandType.tap),
    );
    backTargets.single.onTap?.call();
    expect(tapped, isTrue);
  });

  testWidgets('collapses a semantic wrapper into its standard control', (
    tester,
  ) async {
    var value = 0.5;
    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/level',
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Semantics(
                key: const ValueKey<String>('level-semantics'),
                label: 'Level',
                value: '${(value * 100).round()}',
                increasedValue:
                    '${((value + 0.1).clamp(0.0, 1.0) * 100).round()}',
                decreasedValue:
                    '${((value - 0.1).clamp(0.0, 1.0) * 100).round()}',
                onIncrease: () => setState(() => value += 0.1),
                onDecrease: () => setState(() => value -= 0.1),
                child: Slider(
                  key: const ValueKey<String>('level-slider'),
                  value: value,
                  divisions: 10,
                  onChanged: (next) => setState(() => value = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final registry = tester
        .state<CockpitSurfaceState>(find.byType(CockpitSurface))
        .registry;
    final levelTargets = registry.visibleTargets
        .where(
          (target) =>
              target.semanticId == 'Level' || target.cockpitId == 'Level',
        )
        .toList(growable: false);

    expect(levelTargets, hasLength(1));
    expect(levelTargets.single.typeName, 'Slider');
    expect(levelTargets.single.keyValue, 'level-slider');
    expect(
      levelTargets.single.supportedCommands,
      containsAll(<CockpitCommandType>[
        CockpitCommandType.increase,
        CockpitCommandType.decrease,
      ]),
    );
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

  testWidgets(
    'keeps direct control text when merged semantics contains nearby content',
    (tester) async {
      var outage = false;
      await tester.pumpWidget(
        CockpitSurface(
          routeName: '/settings',
          child: MaterialApp(
            home: Scaffold(
              body: MergeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    StatefulBuilder(
                      builder: (context, setState) => InkWell(
                        onTap: () => setState(() => outage = !outage),
                        child: Row(
                          children: <Widget>[
                            const Expanded(
                              child: Text('Simulate relay outage'),
                            ),
                            IgnorePointer(
                              child: Switch(
                                value: outage,
                                onChanged: (value) =>
                                    setState(() => outage = value),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Text('Recovery workflow'),
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
      final registry = surfaceState.registry;
      final toggleTargets = registry.visibleTargets
          .where(
            (target) =>
                target.text == 'Simulate relay outage' &&
                target.supportedCommands.contains(CockpitCommandType.tap),
          )
          .toList(growable: false);

      expect(toggleTargets, hasLength(1));
      expect(toggleTargets.single.typeName, 'InkWell');
      expect(toggleTargets.single.control?.checked, CockpitCheckState.off);
      expect(
        registry.visibleTargets.where((target) => target.typeName == 'Switch'),
        isEmpty,
      );
      final recoveryResolution = surfaceState.probeVisibleLocator(
        const CockpitLocator(text: 'Recovery workflow'),
        requiredCommand: CockpitCommandType.tap,
      );
      expect(recoveryResolution.isSuccess, isTrue);
      expect(
        recoveryResolution.target?.supportedCommands,
        isNot(contains(CockpitCommandType.tap)),
      );

      toggleTargets.single.onTap?.call();
      await tester.pump();
      final updatedToggle = surfaceState.registry.visibleTargets.singleWhere(
        (target) =>
            target.text == 'Simulate relay outage' &&
            target.supportedCommands.contains(CockpitCommandType.tap),
      );
      expect(updatedToggle.control?.checked, CockpitCheckState.on);
    },
  );

  testWidgets('pointer blockers remove descendant mutation capabilities', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/blocked',
        child: MaterialApp(
          home: Scaffold(
            body: AbsorbPointer(
              child: Column(
                children: <Widget>[
                  FilledButton(
                    key: const ValueKey<String>('blocked-button'),
                    onPressed: () {},
                    child: const Text('Blocked action'),
                  ),
                  TextField(
                    key: const ValueKey<String>('blocked-input'),
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Blocked input',
                    ),
                  ),
                  Slider(
                    key: const ValueKey<String>('blocked-slider'),
                    value: 0.5,
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final targets = tester
        .state<CockpitSurfaceState>(find.byType(CockpitSurface))
        .registry
        .visibleTargets;
    final button = targets.singleWhere(
      (target) => target.keyValue == 'blocked-button',
    );
    final input = targets.singleWhere(
      (target) => target.keyValue == 'blocked-input',
    );
    final slider = targets.singleWhere(
      (target) => target.keyValue == 'blocked-slider',
    );

    expect(button.supportedCommands, isEmpty);
    expect(input.supportedCommands, isEmpty);
    expect(slider.supportedCommands, isEmpty);
  });

  testWidgets('does not guess state from multiple blocked controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/blocked',
        child: MaterialApp(
          home: Scaffold(
            body: InkWell(
              key: const ValueKey<String>('multi-control-row'),
              onTap: () {},
              child: IgnorePointer(
                child: Row(
                  children: <Widget>[
                    Switch(value: false, onChanged: (_) {}),
                    Checkbox(value: true, onChanged: (_) {}),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = tester
        .state<CockpitSurfaceState>(find.byType(CockpitSurface))
        .registry
        .visibleTargets
        .singleWhere((target) => target.keyValue == 'multi-control-row');

    expect(row.supportedCommands, contains(CockpitCommandType.tap));
    expect(row.control?.checked, isNull);
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
