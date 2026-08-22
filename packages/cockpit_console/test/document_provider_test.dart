import 'package:cockpit_console/src/providers/data_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DocumentEditorState', () {
    test('tracks content and path changes independently', () {
      const saved = DocumentEditorState(
        content: 'kind: case',
        relativePath: 'cases/login.yaml',
        persistedContent: 'kind: case',
        persistedRelativePath: 'cases/login.yaml',
      );

      expect(saved.dirty, isFalse);
      expect(saved.copyWith(content: 'kind: suite').dirty, isTrue);
      expect(saved.copyWith(relativePath: 'cases/renamed.yaml').dirty, isTrue);
    });

    test('accepts a successful save as the new clean baseline', () {
      const edited = DocumentEditorState(
        content: 'kind: suite',
        relativePath: 'suites/smoke.yaml',
      );
      final saved = edited.copyWith(
        persistedContent: edited.content,
        persistedRelativePath: edited.relativePath,
      );

      expect(edited.dirty, isTrue);
      expect(saved.dirty, isFalse);
    });
  });

  group('DocumentValidation.fromResult', () {
    test('separates immutable error and warning diagnostics', () {
      final validation = DocumentValidation.fromResult(<String, Object?>{
        'valid': false,
        'diagnostics': <Object?>[
          <String, Object?>{'severity': 'error', 'message': 'bad case'},
          <String, Object?>{'severity': 'warning', 'message': 'slow step'},
        ],
      });

      expect(validation.valid, isFalse);
      expect(validation.errors, <String>['bad case']);
      expect(validation.warnings, <String>['slow step']);
      expect(validation.missingErrorDiagnostic, isFalse);
      expect(() => validation.errors.add('later'), throwsUnsupportedError);
    });

    test('does not present a silent invalid result', () {
      final validation = DocumentValidation.fromResult(<String, Object?>{
        'valid': false,
        'diagnostics': const <Object?>[],
      });

      expect(validation.errors, isEmpty);
      expect(validation.missingErrorDiagnostic, isTrue);
    });
  });
}
