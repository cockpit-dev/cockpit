import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/application/cockpit_interactive_result_profile.dart';
import 'package:test/test.dart';

void main() {
  group('CockpitInteractiveResultProfile', () {
    test('uses minimal defaults', () {
      const profile = CockpitInteractiveResultProfile.minimal();

      expect(profile.name, CockpitInteractiveResultProfileName.minimal);
      expect(profile.ui, CockpitInteractiveUiLevel.none);
      expect(profile.diagnostics, CockpitInteractiveDiagnosticsLevel.none);
      expect(profile.artifacts, CockpitInteractiveArtifactLevel.none);
      expect(profile.includeDelta, isFalse);
      expect(profile.includeRuntimeSteps, isFalse);
      expect(profile.emitSnapshotRef, isFalse);
      expect(
        profile.resolveSnapshotOptions().profile,
        CockpitSnapshotProfile.live,
      );
    });

    test(
      'centralizes profile layer decisions for all interactive services',
      () {
        const minimal = CockpitInteractiveResultProfile.minimal();
        const locate = CockpitInteractiveResultProfile.locate();
        const standard = CockpitInteractiveResultProfile.standard();
        const inspect = CockpitInteractiveResultProfile.inspect();
        const evidence = CockpitInteractiveResultProfile.evidence();

        expect(minimal.requiresStatusSnapshotRead, isFalse);
        expect(minimal.requiresPostActionSnapshotRead(), isFalse);
        expect(minimal.emitsUiSummary, isFalse);
        expect(minimal.emitsInlineSnapshot, isFalse);
        expect(minimal.emitsDiagnostics, isFalse);
        expect(minimal.emitsSnapshotRef, isFalse);
        expect(minimal.emitsRuntimeSteps, isFalse);

        expect(locate.requiresStatusSnapshotRead, isTrue);
        expect(locate.emitsInlineSnapshot, isTrue);
        expect(locate.emitsDiagnostics, isFalse);
        expect(locate.emitsSnapshotRef, isFalse);
        final locateOptions = locate.resolveSnapshotOptions();
        expect(locateOptions.profile, CockpitSnapshotProfile.baseline);
        expect(locateOptions.includeNetworkActivity, isFalse);
        expect(locateOptions.includeRuntimeActivity, isFalse);

        expect(standard.requiresStatusSnapshotRead, isTrue);
        expect(standard.requiresPostActionSnapshotRead(), isTrue);
        expect(standard.emitsUiSummary, isTrue);
        expect(standard.emitsInlineSnapshot, isFalse);
        expect(standard.emitsDiagnostics, isFalse);
        expect(standard.emitsSnapshotRef, isTrue);

        expect(inspect.requiresStatusSnapshotRead, isTrue);
        expect(inspect.requiresPostActionSnapshotRead(), isTrue);
        expect(inspect.emitsUiSummary, isTrue);
        expect(inspect.emitsDiagnostics, isTrue);
        expect(inspect.emitsRuntimeSteps, isTrue);

        expect(evidence.requiresStatusSnapshotRead, isTrue);
        expect(evidence.requiresPostActionSnapshotRead(), isTrue);
        expect(evidence.emitsUiSummary, isFalse);
        expect(evidence.emitsInlineSnapshot, isTrue);
        expect(evidence.emitsDiagnostics, isTrue);

        expect(
          minimal.requiresPostActionSnapshotRead(compareAgainstSnapshot: true),
          isTrue,
        );
      },
    );

    test('uses inspect defaults', () {
      const profile = CockpitInteractiveResultProfile.inspect();

      expect(profile.name, CockpitInteractiveResultProfileName.inspect);
      expect(profile.ui, CockpitInteractiveUiLevel.summary);
      expect(
        profile.diagnostics,
        CockpitInteractiveDiagnosticsLevel.failuresOnly,
      );
      expect(profile.artifacts, CockpitInteractiveArtifactLevel.metadata);
      expect(profile.includeDelta, isTrue);
      expect(profile.includeRuntimeSteps, isTrue);
      expect(profile.emitSnapshotRef, isTrue);

      final snapshotOptions = profile.resolveSnapshotOptions();
      expect(snapshotOptions.profile, CockpitSnapshotProfile.investigate);
      expect(snapshotOptions.includeNetworkActivity, isTrue);
      expect(snapshotOptions.networkQuery.onlyFailures, isTrue);
      expect(snapshotOptions.includeRuntimeActivity, isTrue);
      expect(snapshotOptions.runtimeQuery.onlyErrors, isTrue);
    });

    test('can require artifact metadata without widening other layers', () {
      const standard = CockpitInteractiveResultProfile.standard();
      final profile = standard.copyWith(
        artifacts: CockpitInteractiveArtifactLevel.metadata,
      );

      expect(profile.name, standard.name);
      expect(profile.ui, standard.ui);
      expect(profile.diagnostics, standard.diagnostics);
      expect(profile.artifacts, CockpitInteractiveArtifactLevel.metadata);
      expect(profile.includeDelta, standard.includeDelta);
      expect(profile.includeRuntimeSteps, standard.includeRuntimeSteps);
      expect(profile.emitSnapshotRef, standard.emitSnapshotRef);
      expect(profile.snapshotProfile, standard.snapshotProfile);
    });

    test('allows layer overrides on a preset', () {
      final profile =
          CockpitInteractiveResultProfile.fromJson(const <String, Object?>{
            'profile': 'standard',
            'ui': 'snapshot',
            'diagnostics': 'full',
            'artifacts': 'metadata',
            'includeDelta': true,
            'includeRuntimeSteps': true,
            'emitSnapshotRef': false,
            'snapshotProfile': 'forensic',
          });

      expect(profile.name, CockpitInteractiveResultProfileName.standard);
      expect(profile.ui, CockpitInteractiveUiLevel.snapshot);
      expect(profile.diagnostics, CockpitInteractiveDiagnosticsLevel.full);
      expect(profile.artifacts, CockpitInteractiveArtifactLevel.metadata);
      expect(profile.includeDelta, isTrue);
      expect(profile.includeRuntimeSteps, isTrue);
      expect(profile.emitSnapshotRef, isFalse);
      expect(
        profile.resolveSnapshotOptions().profile,
        CockpitSnapshotProfile.forensic,
      );
    });

    test('preserves an explicitly richer snapshot options override', () {
      const profile = CockpitInteractiveResultProfile.minimal();
      final options = profile.resolveSnapshotOptions(
        const CockpitSnapshotOptions.forensic(),
      );

      expect(options.profile, CockpitSnapshotProfile.forensic);
      expect(options.includeRuntimeActivity, isTrue);
      expect(options.includeNetworkActivity, isTrue);
    });

    test('rejects an unknown preset', () {
      expect(
        () => CockpitInteractiveResultProfile.fromJson(const <String, Object?>{
          'profile': 'mystery',
        }),
        throwsA(
          isA<CockpitApplicationServiceException>().having(
            (error) => error.code,
            'code',
            'invalidInteractiveResultProfile',
          ),
        ),
      );
    });

    test('rejects an unknown layer value', () {
      expect(
        () => CockpitInteractiveResultProfile.fromJson(const <String, Object?>{
          'ui': 'verbose',
        }),
        throwsA(
          isA<CockpitApplicationServiceException>().having(
            (error) => error.code,
            'code',
            'invalidInteractiveResultProfile',
          ),
        ),
      );
    });
  });
}
