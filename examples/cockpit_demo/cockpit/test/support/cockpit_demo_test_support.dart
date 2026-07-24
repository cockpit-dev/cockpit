import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cockpit_demo/src/data/cockpit_demo_database.dart';
import 'package:cockpit_demo/src/cockpit_demo_app.dart';
import 'package:cockpit_demo/src/network/todo_sync_gateway.dart';
import 'package:cockpit_demo/src/ui/screens/todo_collection_screen.dart';
import 'package:cockpit_demo/src/ui/widgets/editorial_section.dart';
import 'package:path/path.dart' as p;

File resolveCockpitDemoFile(String relativePath) {
  var current = Directory.current.absolute;
  for (var depth = 0; depth < 6; depth += 1) {
    final direct = File(p.join(current.path, relativePath));
    if (direct.existsSync()) {
      return direct;
    }

    final nested = File(
      p.join(current.path, 'examples', 'cockpit_demo', relativePath),
    );
    if (nested.existsSync()) {
      return nested;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }

  throw StateError(
    'Unable to resolve cockpit_demo/$relativePath from ${Directory.current.path}.',
  );
}

bool _cockpitDemoTestRuntimeConfigured = false;

void _ensureCockpitDemoTestRuntimeConfigured() {
  if (_cockpitDemoTestRuntimeConfigured) {
    return;
  }
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  _cockpitDemoTestRuntimeConfigured = true;
}

void addCockpitDemoDatabaseTearDown(
  WidgetTester tester,
  CockpitDemoDatabase database,
) {
  _ensureCockpitDemoTestRuntimeConfigured();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await database.close();
  });
}

Future<void> pumpTodoApp(
  WidgetTester tester, {
  required CockpitSessionController controller,
  required CockpitDemoDatabase database,
  FlutterCockpitConfiguration? configuration,
  TodoSyncGatewayClient? syncGateway,
}) async {
  _ensureCockpitDemoTestRuntimeConfigured();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  final effectiveConfiguration =
      (configuration ??
              const FlutterCockpitConfiguration(initialRouteName: '/inbox'))
          .copyWith(sessionController: controller);
  await tester.pumpWidget(
    buildCockpitDemoApp(
      configuration: effectiveConfiguration,
      database: database,
      syncGateway: syncGateway,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pumpAndSettle();
}

Widget buildCockpitDemoApp({
  FlutterCockpitConfiguration? configuration,
  CockpitDemoDatabase? database,
  TodoSyncGatewayClient? syncGateway,
}) {
  final effectiveConfiguration =
      configuration ??
      const FlutterCockpitConfiguration(initialRouteName: '/inbox');
  final initialRouteName = effectiveConfiguration.initialRouteName == '/'
      ? '/inbox'
      : effectiveConfiguration.initialRouteName;
  final runtimeConfiguration = effectiveConfiguration.copyWith(
    initialRouteName: initialRouteName,
  );
  addTearDown(FlutterCockpit.dispose);
  return FlutterCockpitApp(
    config: FlutterCockpitConfig.fromRuntimeConfiguration(runtimeConfiguration),
    child: CockpitDemoApp(
      initialRouteName: initialRouteName,
      navigatorObservers: <NavigatorObserver>[
        FlutterCockpit.createNavigatorObserver(),
      ],
      database: database,
      syncGateway: syncGateway,
    ),
  );
}

HttpClient createRealHttpClient() =>
    _RealHttpOverrides().createHttpClient(null);

CockpitHttpNetworkObserver createObservedRealNetworkObserver({
  int maxRetainedEntries = 80,
}) {
  final observer = CockpitHttpNetworkObserver(
    maxRetainedEntries: maxRetainedEntries,
  );
  observer.attachParentOverrides(_RealHttpOverrides());
  return observer;
}

Future<void> createTaskThroughUi(
  WidgetTester tester, {
  required String title,
  String notes = '',
  String? priorityLabel,
  String? dueLabel,
}) async {
  await tester.tap(find.text('New task'));
  await tester.pumpAndSettle();
  await tester.enterText(textFieldByLabel('Task title'), title);
  if (notes.isNotEmpty) {
    await tester.enterText(textFieldByLabel('Notes'), notes);
  }
  if (priorityLabel != null) {
    final priorityFinder = find.widgetWithText(
      ChoiceChip,
      priorityLabel.toUpperCase(),
    );
    await _scrollUntilVisible(tester, priorityFinder);
    await tester.tap(priorityFinder);
    await tester.pumpAndSettle();
  }
  if (dueLabel != null) {
    final dueFinder = find.widgetWithText(ChoiceChip, dueLabel);
    await _scrollUntilVisible(tester, dueFinder);
    await tester.tap(dueFinder);
    await tester.pumpAndSettle();
  }
  final saveFinder = find.text('Save task');
  await _scrollUntilVisible(tester, saveFinder);
  await tester.tap(saveFinder);
  await tester.pumpAndSettle();
  await settleAfterTaskSave(tester);
}

Future<void> settleAfterTaskSave(WidgetTester tester) async {
  for (var attempt = 0; attempt < 12; attempt += 1) {
    final routeSettled =
        FlutterCockpit.binding.currentRouteName.value != '/editor';
    final spinnerSettled = find
        .byType(CircularProgressIndicator)
        .evaluate()
        .isEmpty;
    final collectionFinder = find.byType(TodoCollectionScreen);
    final collectionSettled =
        collectionFinder.evaluate().isEmpty ||
        !tester
            .state<State<TodoCollectionScreen>>(collectionFinder)
            .widget
            .service
            .listState
            .isLoading;
    if (routeSettled && spinnerSettled && collectionSettled) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  await tester
      .scrollUntilVisible(
        finder,
        180,
        scrollable: find.byType(Scrollable).first,
      )
      .timeout(const Duration(seconds: 10));
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

Future<void> settleSingleTapGesture(WidgetTester tester) async {
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 32));
  await tester.pumpAndSettle();
}

Future<void> scrollTodoCollectionUntilVisible(
  WidgetTester tester,
  Finder finder, {
  double delta = 220,
}) async {
  final collection = find.byType(TodoCollectionScreen);
  final scrollable = collection.evaluate().isNotEmpty
      ? find.descendant(of: collection, matching: find.byType(Scrollable)).first
      : find.byType(Scrollable).first;
  await tester
      .scrollUntilVisible(finder, delta, scrollable: scrollable)
      .timeout(const Duration(seconds: 10));
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

Finder textFieldByLabel(String label) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        (widget.decoration?.labelText == label ||
            widget.decoration?.hintText == label),
    description: 'TextField($label)',
  );
}

Finder taskRowByTitle(String title, {bool selectionMode = false}) {
  return find.ancestor(of: find.text(title), matching: find.byType(InkWell));
}

Finder taskToggleByTitle(String title, {bool completed = false}) {
  return find.bySemanticsLabel(
    '${completed ? 'Reopen' : 'Complete'} task $title',
  );
}

Finder manualQueueReorderHandle(String title) {
  final manualQueueTitle = find.text(title).last;
  final cardFinder = find.ancestor(
    of: manualQueueTitle,
    matching: find.byType(EditorialSection),
  );
  return find.descendant(
    of: cardFinder.first,
    matching: find.byIcon(Icons.drag_indicator_rounded),
  );
}

Finder navigationButton(String label) {
  return find.ancestor(
    of: find.text(label).last,
    matching: find.byType(TextButton),
  );
}

Finder planningSurfaceCanvas() {
  return find.byWidgetPredicate(
    (widget) => widget is GestureDetector && widget.onScaleUpdate != null,
    description: 'Planning surface canvas',
  );
}

void recordCapture({
  required CockpitSessionController controller,
  required String actionType,
  required CockpitCaptureResult capture,
  required Map<String, List<int>> artifactPayloads,
}) {
  artifactPayloads[capture.screenshot.artifact.relativePath] =
      capture.screenshot.bytes;
  controller.recordStep(
    actionType: actionType,
    actionArgs: const <String, Object?>{'target': 'root'},
    observation: CockpitObservation(
      routeName: capture.screenshot.snapshot?.routeName,
      interactiveElements:
          capture.screenshot.snapshot?.visibleTargets
              .map((target) => target.displayLabel)
              .whereType<String>()
              .toList(growable: false) ??
          const <String>[],
      phase: CockpitObservationPhase.afterAction,
    ),
    artifactRefs: <CockpitArtifactRef>[capture.screenshot.artifact],
    captureRefs: <CockpitArtifactRef>[capture.screenshot.artifact],
    commandType: CockpitCommandType.captureScreenshot,
    status: CockpitCommandStatus.succeeded,
    requestedCaptureProfile: capture.requestedProfile,
    resolvedCaptureKind: capture.resolvedCaptureKind,
    usedCaptureFallback: capture.usedFallback,
    degradationReason: capture.degradationReason,
  );
}

Future<Map<String, Object?>> readJson(Uri uri) async {
  return HttpOverrides.runZoned(() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final payload = jsonDecode(await utf8.decoder.bind(response).join());
      return Map<String, Object?>.from(payload as Map<Object?, Object?>);
    } finally {
      client.close(force: true);
    }
  }, createHttpClient: _RealHttpOverrides().createHttpClient);
}

Future<Map<String, Object?>> postJson(
  Uri uri,
  Map<String, Object?> payload,
) async {
  return HttpOverrides.runZoned(() async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      return Map<String, Object?>.from(
        jsonDecode(body) as Map<Object?, Object?>,
      );
    } finally {
      client.close(force: true);
    }
  }, createHttpClient: _RealHttpOverrides().createHttpClient);
}

Future<void> deleteDirectory(Directory directory) async {
  if (directory.existsSync()) {
    await directory.delete(recursive: true);
  }
}

CockpitSessionController buildTestController({
  required String sessionId,
  required String taskId,
  required String platform,
  DateTime Function()? now,
}) {
  return CockpitSessionController(
    sessionId: sessionId,
    taskId: taskId,
    platform: platform,
    now: now,
  );
}

final List<int> validMp4Bytes = base64Decode(
  'AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAAIZnJlZQAAAuVtZGF0AAACrgYF//+q3EXpvebZSLeWLNgg2SPu73gyNjQgLSBjb3JlIDE2NSByMzIyMiBiMzU2MDVhIC0gSC4yNjQvTVBFRy00IEFWQyBjb2RlYyAtIENvcHlsZWZ0IDIwMDMtMjAyNSAtIGh0dHA6Ly93d3cudmlkZW9sYW4ub3JnL3gyNjQuaHRtbCAtIG9wdGlvbnM6IGNhYmFjPTEgcmVmPTMgZGVibG9jaz0xOjA6MCBhbmFseXNlPTB4MzoweDExMyBtZT1oZXggc3VibWU9NyBwc3k9MSBwc3lfcmQ9MS4wMDowLjAwIG1peGVkX3JlZj0xIG1lX3JhbmdlPTE2IGNocm9tYV9tZT0xIHRyZWxsaXM9MSA4eDhkY3Q9MSBjcW09MCBkZWFkem9uZT0yMSwxMSBmYXN0X3Bza2lwPTEgY2hyb21hX3FwX29mZnNldD0tMiB0aHJlYWRzPTEgbG9va2FoZWFkX3RocmVhZHM9MSBzbGljZWRfdGhyZWFkcz0wIG5yPTAgZGVjaW1hdGU9MSBpbnRlcmxhY2VkPTAgYmx1cmF5X2NvbXBhdD0wIGNvbnN0cmFpbmVkX2ludHJhPTAgYmZyYW1lcz0zIGJfcHlyYW1pZD0yIGJfYWRhcHQ9MSBiX2JpYXM9MCBkaXJlY3Q9MSB3ZWlnaHRiPTEgb3Blbl9nb3A9MCB3ZWlnaHRwPTIga2V5aW50PTI1MCBrZXlpbnRfbWluPTI1IHNjZW5lY3V0PTQwIGludHJhX3JlZnJlc2g9MCByY19sb29rYWhlYWQ9NDAgcmM9Y3JmIG1idHJlZT0xIGNyZj0yMy4wIHFjb21wPTAuNjAgcXBtaW49MCBxcG1heD02OSBxcHN0ZXA9NCBpcF9yYXRpbz0xLjQwIGFxPTE6MS4wMACAAAAAD2WIhAAz//727L4FNhTIwQAAAAhBmiJsQr/+wAAAAAgBnkF5Cv/EgQAAA1xtb292AAAAbG12aGQAAAAAAAAAAAAAAAAAAAPoAAAAeAABAAABAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAACh3RyYWsAAABcdGtoZAAAAAMAAAAAAAAAAAAAAAEAAAAAAAAAeAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAEAAAABAAAAAAACRlZHRzAAAAHGVsc3QAAAAAAAAAAQAAAHgAAAQAAAEAAAAAAf9tZGlhAAAAIG1kaGQAAAAAAAAAAAAAAAAAADIAAAAIAFXEAAAAAAAtaGRscgAAAAAAAAAAdmlkZQAAAAAAAAAAAAAAAFZpZGVvSGFuZGxlcgAAAAGqbWluZgAAABR2bWhkAAAAAQAAAAAAAAAAAAAAJGRpbmYAAAAcZHJlZgAAAAAAAAABAAAADHVybCAAAAABAAABanN0YmwAAAC+c3RzZAAAAAAAAAABAAAArmF2YzEAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAEAAQAEgAAABIAAAAAAAAAAEVTGF2YzYyLjExLjEwMCBsaWJ4MjY0AAAAAAAAAAAAAAAY//8AAAA0YXZjQwFkAAr/4QAXZ2QACqzZXsBEAAADAAQAAAMAyDxIllgBAAZo6+PLIsD9+PgAAAAAEHBhc3AAAAABAAAAAQAAABRidHJ0AAAAAAAAvuIAAAAAAAAAGHN0dHMAAAAAAAAAAQAAAAMAAAIAAAAAFHN0c3MAAAAAAAAAAQAAAAEAAAAoY3R0cwAAAAAAAAADAAAAAQAABAAAAAABAAAGAAAAAAEAAAIAAAAAHHN0c2MAAAAAAAAAAQAAAAEAAAADAAAAAQAAACBzdHN6AAAAAAAAAAAAAAADAAACxQAAAAwAAAAMAAAAFHN0Y28AAAAAAAAAAQAAADAAAABhdWR0YQAAAFltZXRhAAAAAAAAACFoZGxyAAAAAAAAAABtZGlyYXBwbAAAAAAAAAAAAAAAACxpbHN0AAAAJKl0b28AAAAcZGF0YQAAAAEAAAAATGF2ZjYyLjMuMTAw',
);

final class FakeCockpitNativeRecording extends CockpitNativeRecording {
  FakeCockpitNativeRecording({required this.sourceFilePath});

  final String sourceFilePath;

  @override
  Future<CockpitRecordingCapabilities> queryCapabilities() async {
    return CockpitRecordingCapabilities(
      supportsNativeRecording: true,
      preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
    );
  }

  @override
  Future<CockpitRecordingSession> startRecording({
    required CockpitRecordingRequest request,
  }) async {
    return CockpitRecordingSession(
      request: request,
      state: CockpitRecordingState.recording,
    );
  }

  @override
  Future<CockpitRecordingResult> stopRecording({
    required CockpitRecordingSession session,
  }) async {
    return CockpitRecordingResult(
      state: CockpitRecordingState.completed,
      purpose: session.request.purpose,
      recordingKind: CockpitRecordingKind.nativeScreen,
      artifact: CockpitArtifactRef(
        role: 'recording',
        relativePath: cockpitRecordingRelativePathFor(session.request),
      ),
      durationMs: 2600,
      sourceFilePath: sourceFilePath,
    );
  }
}

final class _RealHttpOverrides extends HttpOverrides {}
