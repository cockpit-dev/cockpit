import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';

void main() {
  test('debugger models keep source and value data compact', () {
    final frame = CockpitVmFrame(
      index: 0,
      name: 'Checkout.submit',
      location: const CockpitVmLocation(
        uri: 'package:shop/checkout.dart',
        line: 42,
        column: 7,
      ),
      variables: const <CockpitVmVariable>[
        CockpitVmVariable(
          name: 'count',
          value: CockpitVmValue(id: 'objects/1', kind: 'Int', value: '3'),
        ),
      ],
    );
    final json = frame.toJson();

    expect(json, <String, Object?>{
      'i': 0,
      'name': 'Checkout.submit',
      'loc': <String, Object?>{
        'u': 'package:shop/checkout.dart',
        'l': 42,
        'c': 7,
      },
      'vars': <Object?>[
        <String, Object?>{
          'name': 'count',
          'value': <String, Object?>{
            'id': 'objects/1',
            'kind': 'Int',
            'value': '3',
          },
        },
      ],
    });
  });

  test('evaluation output only includes a value or an error', () {
    final success = const CockpitVmEvaluation(
      value: CockpitVmValue(kind: 'String', value: 'ready'),
    ).toJson();
    final failure = const CockpitVmEvaluation(error: 'compile error').toJson();

    expect(success, <String, Object?>{
      'value': <String, Object?>{'kind': 'String', 'value': 'ready'},
    });
    expect(failure, <String, Object?>{'error': 'compile error'});
    expect(success, isNot(contains('ok')));
  });

  test('step values match the VM protocol', () {
    expect(CockpitVmStep.into.wireValue, 'Into');
    expect(CockpitVmStep.over.wireValue, 'Over');
    expect(CockpitVmStep.out.wireValue, 'Out');
    expect(CockpitVmStep.overAsyncSuspension.wireValue, 'OverAsyncSuspension');
  });

  test('debugger validates unsafe arguments before attaching', () async {
    expect(
      () => CockpitVmDebugger(timeout: Duration.zero),
      throwsArgumentError,
    );
    await expectLater(
      CockpitVmDebugger().resume(frameIndex: 0),
      throwsArgumentError,
    );
    await expectLater(
      CockpitVmDebugger().addBreakpoint('package:app/main.dart', 0),
      throwsArgumentError,
    );
  });
}
