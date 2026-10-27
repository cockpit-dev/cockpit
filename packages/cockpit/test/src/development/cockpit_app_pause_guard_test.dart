import 'dart:async';

import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/development/cockpit_app_pause_guard.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

/// The guard turns VM service isolate state into a fast `appPaused` failure:
/// while the app's root isolate is paused its in-process control plane never
/// answers, so interactive operations must not enter the hung dial.
void main() {
  final vmServiceUri = Uri.parse('http://127.0.0.1:8123/auth=token');

  test(
    'rejects when the root isolate is paused while workers keep running',
    () async {
      // Mirrors a live drift-backed Flutter app: `main` is paused at a
      // debugger while the database worker isolate stays runnable.
      final guard = CockpitVmAppPauseGuard(
        connect: (_) async => _fakeService(<_IsolateSpec>[
          const _IsolateSpec(
            id: 'isolates/1',
            name: 'main',
            pause: EventKind.kPauseInterrupted,
          ),
          const _IsolateSpec(
            id: 'isolates/2',
            name: 'Drift isolate worker for app.sqlite',
            pause: EventKind.kResume,
          ),
        ]),
      );

      await expectLater(
        guard.ensureRunning(vmServiceUri: vmServiceUri),
        throwsA(
          isA<CockpitApplicationServiceException>()
              .having((error) => error.code, 'code', 'appPaused')
              .having(
                (error) => error.message,
                'message',
                allOf(contains('PauseInterrupted'), contains('dev restart')),
              )
              .having(
                (error) => error.details['pauseKind'],
                'pauseKind',
                'PauseInterrupted',
              ),
        ),
      );
    },
  );

  test('passes when a background worker is paused but the root runs', () async {
    final guard = CockpitVmAppPauseGuard(
      connect: (_) async => _fakeService(<_IsolateSpec>[
        const _IsolateSpec(
          id: 'isolates/1',
          name: 'main',
          pause: EventKind.kResume,
        ),
        const _IsolateSpec(
          id: 'isolates/2',
          name: 'Drift isolate worker for app.sqlite',
          pause: EventKind.kPauseBreakpoint,
        ),
      ]),
    );

    await expectLater(
      guard.ensureRunning(vmServiceUri: vmServiceUri),
      completes,
    );
  });

  test('rejects when every isolate is paused', () async {
    // Infrastructure isolates never host the control plane.
    final guard = CockpitVmAppPauseGuard(
      connect: (_) async => _fakeService(<_IsolateSpec>[
        const _IsolateSpec(
          id: 'isolates/1',
          name: 'main',
          pause: EventKind.kPauseBreakpoint,
        ),
        const _IsolateSpec(
          id: 'isolates/2',
          name: 'Drift isolate worker for app.sqlite',
          pause: EventKind.kPauseInterrupted,
        ),
        const _IsolateSpec(id: 'vm-service', name: 'vm-service', pause: null),
      ]),
    );

    await expectLater(
      guard.ensureRunning(vmServiceUri: vmServiceUri),
      throwsA(
        isA<CockpitApplicationServiceException>().having(
          (error) => error.details['pauseKind'],
          'pauseKind',
          'PauseBreakpoint',
        ),
      ),
    );
  });

  test('passes on launch-time and transient service pause kinds', () async {
    for (final kind in const <String>[
      EventKind.kNone,
      EventKind.kResume,
      EventKind.kPauseStart,
      EventKind.kPausePostRequest,
    ]) {
      final guard = CockpitVmAppPauseGuard(
        connect: (_) async => _fakeService(<_IsolateSpec>[
          _IsolateSpec(id: 'isolates/1', name: 'main', pause: kind),
        ]),
      );
      await expectLater(
        guard.ensureRunning(vmServiceUri: vmServiceUri),
        completes,
        reason: kind,
      );
    }
  });

  test(
    'falls back to the first user isolate when none is named main',
    () async {
      final guard = CockpitVmAppPauseGuard(
        connect: (_) async => _fakeService(<_IsolateSpec>[
          const _IsolateSpec(
            id: 'isolates/1',
            name: 'entrypoint.dart\$main',
            pause: EventKind.kPauseInterrupted,
          ),
          const _IsolateSpec(
            id: 'isolates/2',
            name: 'worker',
            pause: EventKind.kResume,
          ),
        ]),
      );

      await expectLater(
        guard.ensureRunning(vmServiceUri: vmServiceUri),
        throwsA(
          isA<CockpitApplicationServiceException>().having(
            (error) => error.code,
            'code',
            'appPaused',
          ),
        ),
      );
    },
  );

  test('passes when the isolate list carries no user isolates', () async {
    final guard = CockpitVmAppPauseGuard(
      connect: (_) async => _fakeService(const <_IsolateSpec>[]),
    );

    await expectLater(
      guard.ensureRunning(vmServiceUri: vmServiceUri),
      completes,
    );
  });

  test('fails open when the VM service cannot be probed', () async {
    final guard = CockpitVmAppPauseGuard(
      connect: (_) => throw StateError('vm service unreachable'),
    );

    await expectLater(
      guard.ensureRunning(vmServiceUri: vmServiceUri),
      completes,
    );
  });

  test('fails open when the probe exceeds its budget', () async {
    final guard = CockpitVmAppPauseGuard(
      connect: (_) => Completer<VmService>().future,
      probeTimeout: const Duration(milliseconds: 5),
    );

    await expectLater(
      guard.ensureRunning(vmServiceUri: vmServiceUri),
      completes,
    );
  });

  test('disposes the probe connection', () async {
    final service = _fakeService(<_IsolateSpec>[
      const _IsolateSpec(
        id: 'isolates/1',
        name: 'main',
        pause: EventKind.kPauseInterrupted,
      ),
    ]);
    final guard = CockpitVmAppPauseGuard(connect: (_) async => service);

    await expectLater(
      guard.ensureRunning(vmServiceUri: vmServiceUri),
      throwsA(isA<CockpitApplicationServiceException>()),
    );
    expect(service.disposeCount, 1);
  });
}

final class _IsolateSpec {
  const _IsolateSpec({
    required this.id,
    required this.name,
    required this.pause,
  });

  final String id;
  final String name;
  final String? pause;
}

/// Answers `getVM`/`getIsolate` from a fixed isolate table. A `null` pause
/// marks an isolate that carries no pause event at all.
_FakeVmService _fakeService(List<_IsolateSpec> specs) {
  return _FakeVmService(
    vm: VM(
      isolates: <IsolateRef>[
        for (final spec in specs) IsolateRef(id: spec.id, name: spec.name),
      ],
    ),
    isolates: <String, Isolate>{
      for (final spec in specs)
        spec.id: Isolate(
          id: spec.id,
          name: spec.name,
          pauseEvent: spec.pause == null ? null : Event(kind: spec.pause),
        ),
    },
  );
}

final class _FakeVmService extends VmService {
  _FakeVmService({required this.vm, required this.isolates})
    // A never-completing input stream keeps the base constructor's onDone
    // hook (which disposes the service) from firing during the test.
    : super(StreamController<void>().stream, (_) {});

  final VM vm;
  final Map<String, Isolate> isolates;
  int disposeCount = 0;

  @override
  Future<VM> getVM() async => vm;

  @override
  Future<Isolate> getIsolate(String isolateId) async => isolates[isolateId]!;

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}
