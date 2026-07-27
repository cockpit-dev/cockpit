import 'package:cockpit/src/system_control/cockpit_native_ui_snapshot.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  final snapshot = CockpitNativeUiSnapshot.parse('''
<hierarchy>
  <node text="Form" class="android.view.View" bounds="[0,0][400,700]">
    <node text="Cancel" role="button" enabled="true" clickable="true" bounds="[10,200][90,250]" />
    <node text="Save" content-desc="Save task" resource-id="save-button" role="button" enabled="true" clickable="true" bounds="[120,200][220,250]" />
    <node text="Save task permanently" role="button" enabled="true" clickable="true" bounds="[230,200][390,250]" />
    <node text="Task 1" role="text" enabled="true" bounds="[10,300][100,350]" />
    <node text="Task 2" role="text" enabled="true" bounds="[110,300][200,350]" />
    <node text="Status" role="text" enabled="true" bounds="[10,400][220,450]" />
  </node>
</hierarchy>
''');

  test('resolves conjunctive signals, states, tree, and spatial relations', () {
    final result = snapshot.resolve(
      CockpitTestLocator(
        text: 'Save',
        label: 'Save task',
        testId: 'save-button',
        role: 'button',
        enabled: true,
        clickable: true,
        ancestor: CockpitTestLocator(text: 'Form'),
        above: CockpitTestLocator(text: 'Status'),
        rightOf: CockpitTestLocator(text: 'Cancel'),
      ),
    );

    expect(result.found, isTrue);
    expect(result.node?.textValues, contains('Save'));
  });

  test('resolves direct child and descendant constraints', () {
    final result = snapshot.resolve(
      CockpitTestLocator(
        text: 'Form',
        child: CockpitTestLocator(text: 'Save'),
        descendant: CockpitTestLocator(text: 'Status'),
      ),
    );

    expect(result.found, isTrue);
    expect(result.node?.textValues, contains('Form'));
  });

  test('missing state attributes never satisfy an authored state', () {
    final result = snapshot.resolve(
      CockpitTestLocator(text: 'Status', checked: false),
    );

    expect(result.found, isFalse);
  });

  test('uses explicit broad matching and prefers an exact candidate', () {
    expect(snapshot.resolve(CockpitTestLocator(text: 'Sav')).found, isFalse);

    final result = snapshot.resolve(
      CockpitTestLocator(
        text: 'Save',
        matchMode: CockpitTextMatchMode.contains,
      ),
    );

    expect(result.found, isTrue);
    expect(result.node?.textValues, contains('Save'));

    final fuzzy = snapshot.resolve(
      CockpitTestLocator(text: 'Svae', matchMode: CockpitTextMatchMode.fuzzy),
    );
    expect(fuzzy.node?.textValues, contains('Save'));
  });

  test('returns ambiguity for tied regex matches and supports list index', () {
    final regexLocator = CockpitTestLocator(
      text: r'^Task \d$',
      matchMode: CockpitTextMatchMode.regex,
    );
    expect(snapshot.resolve(regexLocator).ambiguous, isTrue);

    final indexed = snapshot.resolve(
      CockpitTestLocator(
        text: 'Task',
        matchMode: CockpitTextMatchMode.contains,
        index: 1,
      ),
    );
    expect(indexed.node?.textValues, contains('Task 2'));
  });

  test('collapses Android Flutter ancestor semantic duplicates', () {
    final flutterSnapshot = CockpitNativeUiSnapshot.parse('''
<hierarchy bounds="[0,0][400,800]">
  <node text="Save" class="android.view.View" enabled="true" clickable="true" bounds="[40,100][360,180]">
    <node text="Save" class="android.view.View" enabled="true" clickable="false" bounds="[40,100][360,180]" />
  </node>
</hierarchy>
''');
    final locator = CockpitTestLocator(text: 'Save');

    expect(flutterSnapshot.resolve(locator).ambiguous, isTrue);
    final result = flutterSnapshot.resolve(locator, flutterAware: true);

    expect(result.found, isTrue);
    expect(result.node?.state('clickable'), isTrue);
    expect(result.adapter, 'flutterAwareNative');
  });

  test('prefers an actionable iOS Flutter semantic ancestor', () {
    final flutterSnapshot = CockpitNativeUiSnapshot.parse('''
<App type="XCUIElementTypeApplication" x="0" y="0" width="390" height="844">
  <Button type="XCUIElementTypeButton" name="Continue" label="Continue" enabled="true" x="30" y="120" width="330" height="52">
    <StaticText type="XCUIElementTypeStaticText" name="Continue" label="Continue" enabled="true" x="30" y="120" width="330" height="52" />
  </Button>
</App>
''');

    final result = flutterSnapshot.resolve(
      CockpitTestLocator(text: 'Continue'),
      flutterAware: true,
    );

    expect(result.found, isTrue);
    expect(result.node?.types, contains('XCUIElementTypeButton'));
  });

  test('does not collapse distinct Flutter semantic siblings', () {
    final flutterSnapshot = CockpitNativeUiSnapshot.parse('''
<hierarchy bounds="[0,0][400,800]">
  <node text="Row" bounds="[20,100][380,160]" />
  <node text="Row" bounds="[20,100][380,160]" />
</hierarchy>
''');

    final result = flutterSnapshot.resolve(
      CockpitTestLocator(text: 'Row'),
      flutterAware: true,
    );

    expect(result.ambiguous, isTrue);
    expect(result.matchCount, 2);
  });
}
