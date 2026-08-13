import 'package:cockpit/src/system_control/cockpit_native_ui_snapshot.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  final snapshot = CockpitNativeUiSnapshot.parse('''
<hierarchy>
  <node text="Form" class="android.view.View" bounds="[0,0][400,700]">
    <node text="Cancel" role="button" enabled="true" clickable="true" bounds="[10,200][90,250]" />
    <node text="Save" content-desc="Save task" resource-id="save-button" role="button" enabled="true" clickable="true" bounds="[120,200][220,250]" />
    <node text="Save task" role="button" enabled="true" clickable="true" bounds="[230,140][390,190]" />
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

  test('resolves normalized Chromium DOM nodes with the same locator', () {
    final dom = CockpitNativeUiSnapshot.parse('''
{"tree":{"role":"html","type":"html","frame":{"x":0,"y":0,"width":800,"height":600},"visible":true,"enabled":true,"children":[{"role":"main","type":"main","name":"Message form","frame":{"x":20,"y":20,"width":400,"height":100},"visible":true,"enabled":true,"children":[{"role":"button","type":"button","text":"Send","id":"send","testid":"send-button","frame":{"x":200,"y":40,"width":80,"height":40},"visible":true,"enabled":true,"clickable":true,"children":[]}] }]}}
''');

    final result = dom.resolve(
      CockpitTestLocator(
        text: 'Send',
        nativeId: 'send',
        testId: 'send-button',
        role: 'button',
        enabled: true,
        clickable: true,
        ancestor: CockpitTestLocator(label: 'Message form'),
      ),
    );

    expect(result.found, isTrue);
    expect(result.centerX, 240);
    expect(result.centerY, 60);
  });

  test('normalizes native role separators for cross-platform locators', () {
    final linux = CockpitNativeUiSnapshot.parse('''
{"tree":{"role":"check box","frame":{"x":0,"y":0,"width":120,"height":40},"visible":true,"enabled":true,"children":[]}}
''');

    expect(linux.resolve(CockpitTestLocator(role: 'checkbox')).found, isTrue);
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

  test('preserves Android secure nodes as password state', () {
    final secureSnapshot = CockpitNativeUiSnapshot.parse('''
<hierarchy>
  <node text="Password" secure="true" bounds="[0,0][200,60]" />
</hierarchy>
''');

    final result = secureSnapshot.resolve(CockpitTestLocator(text: 'Password'));

    expect(result.node?.state('password'), isTrue);
  });

  test('resolves Android hintText through text and label locators', () {
    final snapshot = CockpitNativeUiSnapshot.parse(
      '''<?xml version="1.0"?><hierarchy><node class="android.widget.EditText" hintText="Task title" visible-to-user="true" bounds="[10,20][210,80]" /></hierarchy>''',
    );

    expect(
      snapshot.resolve(CockpitTestLocator(text: 'Task title')).found,
      isTrue,
    );
    expect(
      snapshot.resolve(CockpitTestLocator(label: 'Task title')).found,
      isTrue,
    );
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

    final fuzzyPhrase = snapshot.resolve(
      CockpitTestLocator(
        text: 'Svae task',
        matchMode: CockpitTextMatchMode.fuzzy,
      ),
    );
    expect(fuzzyPhrase.node?.textValues, contains('Save task'));
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

  test('parses macOS accessibility JSON trees', () {
    final macos = CockpitNativeUiSnapshot.parse('''
{"platform":"macos","windows":[{"nativePath":"w0","role":"AXWindow","title":"Cockpit","frame":{"x":20,"y":40,"width":800,"height":600},"children":[{"nativePath":"w0/c0","role":"AXButton","title":"New task","description":"Create task","frame":{"x":650,"y":70,"width":110,"height":44}}]}]}
''');

    final result = macos.resolve(CockpitTestLocator(label: 'New task'));

    expect(result.found, isTrue);
    expect(result.centerX, 705);
    expect(result.node?.roles, contains('AXButton'));
    expect(result.node?.attributes['nativepath'], 'w0/c0');
  });

  test('parses Windows UI Automation JSON trees', () {
    final windows = CockpitNativeUiSnapshot.parse('''
{"platform":"windows","tree":{"controlType":"Window","name":"Cockpit","frame":{"x":0,"y":0,"width":1024,"height":768},"children":[{"controlType":"Button","name":"Save","automationId":"save-button","className":"FlutterView","frame":{"x":700,"y":680,"width":180,"height":48}}]}}
''');

    final result = windows.resolve(
      CockpitTestLocator(text: 'Save', testId: 'save-button', role: 'Button'),
    );

    expect(result.found, isTrue);
    expect(result.node?.nativeIds, contains('save-button'));
    expect(result.node?.types, contains('Button'));
  });
}
