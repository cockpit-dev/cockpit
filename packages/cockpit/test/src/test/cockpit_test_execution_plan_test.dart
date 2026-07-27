import 'package:cockpit/cockpit.dart';
import 'package:cockpit/src/test/cockpit_test_execution_plan.dart';
import 'package:cockpit/src/test/cockpit_test_variable_binder.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  const compiler = CockpitTestDocumentCompiler();

  test('binding preserves types, interpolation, and explicit JSON null', () {
    final compiled = compiler.compile(_bindingCase()).requireCase();
    final plan = CockpitTestVariableBinder().bind(
      compiled,
      inputs: const <String, Object?>{'username': 'operator'},
    );

    final action =
        (plan.steps.single.operation as CockpitTestActionPlanOperation).action;
    expect(action.value<String>(CockpitTestActionField.text), 'hello operator');
    expect(plan.caseId, 'bindingCase');
    expect(plan.secretBindings.isEmpty, isTrue);
  });

  test('missing, unknown, and ill-typed runtime inputs fail binding', () {
    final compiled = compiler
        .compile(_bindingCase(requiredInput: true))
        .requireCase();
    final binder = CockpitTestVariableBinder();

    expect(
      () => binder.bind(compiled),
      throwsA(isA<CockpitTestBindingException>()),
    );
    expect(
      () => binder.bind(compiled, inputs: const <String, Object?>{'extra': 1}),
      throwsA(isA<CockpitTestBindingException>()),
    );
    expect(
      () =>
          binder.bind(compiled, inputs: const <String, Object?>{'username': 7}),
      throwsA(isA<CockpitTestBindingException>()),
    );
  });

  test('secret plans contain only opaque dispatch tokens and references', () {
    final compiled = compiler.compile(_secretCase()).requireCase();
    final plan = CockpitTestVariableBinder().bind(compiled);
    final action =
        (plan.steps.single.operation as CockpitTestActionPlanOperation).action;
    final token = action.values[CockpitTestActionField.text];

    expect(token, isA<CockpitTestSecretToken>());
    expect(token.toString(), '<secret-token>');
    expect(token.toString(), isNot(contains('PASSWORD')));
    expect(plan.secretBindings.isEmpty, isFalse);
  });

  test('binding rejects secret references outside credential text fields', () {
    final result = compiler.compile('''
schemaVersion: cockpit.test/v2
kind: case
id: invalidSecret
target: {platform: android, targetKind: flutterApp, plane: semantic}
variables:
  password: {source: secret, type: string, reference: env:PASSWORD}
steps:
  - stepId: tapSecret
    action:
      type: tap
      locator: {text: {\$var: password}}
''');

    expect(result.isSuccess, isFalse);
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.code),
      contains('secretUsageInvalid'),
    );
  });
}

String _bindingCase({bool requiredInput = false}) =>
    '''
schemaVersion: cockpit.test/v2
kind: case
id: bindingCase
target: {platform: android, targetKind: flutterApp, plane: semantic}
variables:
  username:
    source: input
    type: string
    required: $requiredInput
    ${requiredInput ? '' : 'default: guest'}
  nullablePayload: {source: input, type: json, required: false, default: null}
steps:
  - stepId: greet
    action:
      type: enterText
      text: hello \${username}
''';

String _secretCase() => '''
schemaVersion: cockpit.test/v2
kind: case
id: secretCase
target: {platform: android, targetKind: flutterApp, plane: semantic}
variables:
  password: {source: secret, type: string, reference: env:PASSWORD}
steps:
  - stepId: enterPassword
    action:
      type: enterText
      text: {\$var: password}
''';
