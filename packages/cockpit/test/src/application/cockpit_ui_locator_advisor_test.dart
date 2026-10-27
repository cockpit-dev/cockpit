import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/application/cockpit_ui_locator_advisor.dart';
import 'package:test/test.dart';

CockpitSnapshotTarget _target(
  String registrationId, {
  String? text,
  String? keyValue,
  String? typeName,
  bool visible = true,
  bool covered = false,
  List<CockpitCommandType> commands = const <CockpitCommandType>[],
  CockpitControlState? control,
  double dy = 0,
  double dx = 0,
}) {
  return CockpitSnapshotTarget(
    registrationId: registrationId,
    keyValue: keyValue,
    text: text,
    typeName: typeName,
    routeName: '/page',
    visible: visible,
    coveredByOverlay: covered,
    supportedCommands: commands,
    control: control,
    layout: CockpitSnapshotLayout(
      width: 80,
      height: 40,
      dx: dx,
      dy: dy,
      constraintsSummary: 'min:0.0x0.0 max:inf xinf',
    ),
  );
}

List<Map<String, Object?>> _rows(Map<String, Object?> index) =>
    (index['targets']! as List<Object?>).cast<Map<String, Object?>>().toList(
      growable: false,
    );

/// Text rows fold their text into `sel` and omit a duplicate `label`, so rows
/// are identified by whichever field carries the visible text.
List<String> _rowLabels(Map<String, Object?> index) => _rows(
  index,
).map((row) => (row['label'] ?? row['sel']).toString()).toList(growable: false);

void main() {
  test('surface index lists passive text alongside controls', () {
    final index = cockpitBuildUiTargetIndex(
      CockpitSnapshot(
        routeName: '/page',
        visibleTargets: <CockpitSnapshotTarget>[
          _target('native.title', text: 'Inbox', typeName: 'Text', dy: 8),
          _target(
            'native.open-button',
            text: 'Open',
            typeName: 'FilledButton',
            commands: const <CockpitCommandType>[CockpitCommandType.tap],
            dy: 64,
          ),
        ],
      ),
    );

    final rows = _rows(index);
    expect(rows, hasLength(2));
    expect(rows.first['sel'], 'Inbox');
    expect(rows.first.containsKey('can'), isFalse);
    expect(rows.last['label'], 'Open');
    expect(rows.last['can'], 'tap');
  });

  test('surface index orders visible, covered, then offscreen rows', () {
    final index = cockpitBuildUiTargetIndex(
      CockpitSnapshot(
        routeName: '/page',
        visibleTargets: <CockpitSnapshotTarget>[
          _target(
            'native.offscreen-action',
            text: 'Deep action',
            keyValue: 'offscreen-action',
            typeName: 'FilledButton',
            visible: false,
            commands: const <CockpitCommandType>[CockpitCommandType.tap],
            dy: 600,
          ),
          _target(
            'native.covered-action',
            text: 'Covered save',
            keyValue: 'covered-save',
            typeName: 'FilledButton',
            covered: true,
            commands: const <CockpitCommandType>[CockpitCommandType.tap],
            dy: 120,
          ),
          _target(
            'native.dialog-action',
            text: 'Confirm',
            keyValue: 'dialog-confirm',
            typeName: 'FilledButton',
            commands: const <CockpitCommandType>[CockpitCommandType.tap],
            dy: 200,
          ),
        ],
      ),
    );

    final rows = _rows(index);
    expect(
      _rowLabels(index),
      orderedEquals(<String>['Confirm', 'Covered save', 'Deep action']),
    );
    expect(rows[0]['state'], isNull);
    expect(rows[1]['state'], 'covered');
    expect(rows[2]['state'], 'offscreen');
    expect(index['offscreen'], 1);
    expect(index['covered'], 1);
  });

  test('live refs stay limited to currently visible controls', () {
    final index = cockpitBuildUiTargetIndex(
      CockpitSnapshot(
        routeName: '/page',
        visibleTargets: <CockpitSnapshotTarget>[
          _target(
            'native.visible-button',
            text: 'Open',
            keyValue: 'visible-open',
            typeName: 'FilledButton',
            commands: const <CockpitCommandType>[CockpitCommandType.tap],
            dy: 10,
          ),
          _target(
            'native.offscreen-button',
            text: 'Deep',
            keyValue: 'offscreen-open',
            typeName: 'FilledButton',
            visible: false,
            commands: const <CockpitCommandType>[CockpitCommandType.tap],
            dy: 900,
          ),
        ],
      ),
    );

    final rows = _rows(index);
    expect(rows.first['sel'].toString().startsWith(':'), isTrue);
    expect(rows.last['sel'].toString().startsWith(':'), isFalse);
  });

  test('text shadowed by an actionable control stays hidden', () {
    final index = cockpitBuildUiTargetIndex(
      CockpitSnapshot(
        routeName: '/page',
        visibleTargets: <CockpitSnapshotTarget>[
          _target(
            'native.open-button',
            text: 'Open',
            keyValue: 'open-button',
            typeName: 'FilledButton',
            commands: const <CockpitCommandType>[CockpitCommandType.tap],
            dy: 100,
          ),
          _target('native.open-text', text: 'Open', typeName: 'Text', dy: 100),
          _target('native.page-title', text: 'Board', typeName: 'Text', dy: 4),
        ],
      ),
    );

    final labels = _rowLabels(index)..sort();
    expect(labels, orderedEquals(<String>['Board', 'Open']));
  });
}
