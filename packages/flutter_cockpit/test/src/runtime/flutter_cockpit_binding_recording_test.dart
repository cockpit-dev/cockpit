import 'dart:async';

import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('concurrent recording stops share one native operation', () async {
    final recorder = _FakeNativeRecording()..completeStartsImmediately = true;
    final binding = FlutterCockpitBinding(
      FlutterCockpitConfiguration(nativeRecording: recorder),
    );
    addTearDown(binding.dispose);
    await binding.startRecording(_request);

    final first = binding.stopRecording();
    final second = binding.stopRecording();

    expect(identical(first, second), isTrue);
    expect(recorder.stopCalls, 1);
    recorder.completeStop(_completedResult);

    expect(await first, same(_completedResult));
    expect(await second, same(_completedResult));
    expect(binding.activeRecordingSession, isNull);
    expect(recorder.stopCalls, 1);
  });

  test('failed native stop ends the session without a second stop', () async {
    final recorder = _FakeNativeRecording()..completeStartsImmediately = true;
    final binding = FlutterCockpitBinding(
      FlutterCockpitConfiguration(nativeRecording: recorder),
    );
    addTearDown(binding.dispose);
    await binding.startRecording(_request);

    final failure = StateError('native stop failed');
    final first = binding.stopRecording();
    final second = binding.stopRecording();
    recorder.failStop(failure);

    expect(identical(first, second), isTrue);
    await expectLater(first, throwsA(same(failure)));
    await expectLater(second, throwsA(same(failure)));
    expect(binding.activeRecordingSession, isNull);
    expect(recorder.stopCalls, 1);

    final inactive = await binding.stopRecording();
    expect(inactive.state, CockpitRecordingState.failed);
    expect(inactive.failureReason, 'recordingNotActive');
    expect(recorder.stopCalls, 1);
  });

  test(
    'synchronous native stop failure is shared and dispatched once',
    () async {
      final failure = StateError('synchronous native stop failed');
      final recorder = _FakeNativeRecording()
        ..completeStartsImmediately = true
        ..synchronousStopFailure = failure;
      final binding = FlutterCockpitBinding(
        FlutterCockpitConfiguration(nativeRecording: recorder),
      );
      addTearDown(binding.dispose);
      await binding.startRecording(_request);

      final first = binding.stopRecording();
      final second = binding.stopRecording();

      expect(identical(first, second), isTrue);
      await expectLater(first, throwsA(same(failure)));
      await expectLater(second, throwsA(same(failure)));
      expect(binding.activeRecordingSession, isNull);
      expect(recorder.stopCalls, 1);
    },
  );

  test('recording conflict messages describe the active lifecycle', () async {
    final recorder = _FakeNativeRecording();
    final binding = FlutterCockpitBinding(
      FlutterCockpitConfiguration(nativeRecording: recorder),
    );
    addTearDown(binding.dispose);

    final starting = binding.startRecording(_request);
    await expectLater(
      binding.startRecording(_request),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'A screen recording is already starting.',
        ),
      ),
    );
    recorder.completeStart();
    await starting;

    await expectLater(
      binding.startRecording(_request),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'A screen recording is already active.',
        ),
      ),
    );
  });

  test('active recording prevents native recorder replacement', () async {
    final recorder = _FakeNativeRecording()..completeStartsImmediately = true;
    final replacement = _FakeNativeRecording();
    final binding = FlutterCockpitBinding(
      FlutterCockpitConfiguration(nativeRecording: recorder),
    );
    addTearDown(binding.dispose);
    await binding.startRecording(_request);

    expect(
      () => binding.updateConfiguration(
        FlutterCockpitConfiguration(nativeRecording: replacement),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Native recording cannot be reconfigured while recording is active.',
        ),
      ),
    );
    expect(binding.nativeRecording, same(recorder));
    expect(recorder.stopCalls, 0);
  });
}

const _request = CockpitRecordingRequest(
  purpose: CockpitRecordingPurpose.acceptance,
  name: 'recording-test',
);

final _completedResult = CockpitRecordingResult(
  state: CockpitRecordingState.completed,
  purpose: CockpitRecordingPurpose.acceptance,
  recordingKind: CockpitRecordingKind.nativeScreen,
  durationMs: 10,
  bytes: const <int>[1],
);

final class _FakeNativeRecording extends CockpitNativeRecording {
  bool completeStartsImmediately = false;
  Object? synchronousStopFailure;
  Completer<CockpitRecordingSession>? _start;
  Completer<CockpitRecordingResult>? _stop;
  int stopCalls = 0;

  @override
  Future<CockpitRecordingSession> startRecording({
    required CockpitRecordingRequest request,
  }) {
    final session = CockpitRecordingSession(
      request: request,
      state: CockpitRecordingState.recording,
    );
    if (completeStartsImmediately) return Future.value(session);
    _start = Completer<CockpitRecordingSession>();
    return _start!.future;
  }

  void completeStart() {
    final start = _start!;
    start.complete(
      const CockpitRecordingSession(
        request: _request,
        state: CockpitRecordingState.recording,
      ),
    );
    _start = null;
  }

  @override
  Future<CockpitRecordingResult> stopRecording({
    required CockpitRecordingSession session,
  }) {
    stopCalls += 1;
    final failure = synchronousStopFailure;
    if (failure != null) throw failure;
    _stop = Completer<CockpitRecordingResult>();
    return _stop!.future;
  }

  void completeStop(CockpitRecordingResult result) {
    final stop = _stop!;
    stop.complete(result);
    _stop = null;
  }

  void failStop(Object error) {
    final stop = _stop!;
    stop.completeError(error);
    _stop = null;
  }
}
