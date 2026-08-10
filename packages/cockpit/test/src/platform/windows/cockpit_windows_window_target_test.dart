import 'package:cockpit/src/platform/windows/cockpit_windows_window_target.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes Windows executable names for exact process matching', () {
    expect(cockpitNormalizeWindowsProcessName('cockpit_demo'), 'cockpit_demo');
    expect(
      cockpitNormalizeWindowsProcessName('Cockpit_Demo.EXE'),
      'cockpit_demo',
    );
    expect(
      cockpitNormalizeWindowsProcessName(r'C:\apps\cockpit_demo.exe'),
      'cockpit_demo',
    );
    expect(
      cockpitNormalizeWindowsProcessName('C:/apps/cockpit_demo.exe'),
      'cockpit_demo',
    );
    expect(
      cockpitNormalizeWindowsProcessName(r'C:\apps\cockpit.demo.exe'),
      'cockpit.demo',
    );
    expect(cockpitNormalizeWindowsProcessName('cockpit.demo'), 'cockpit.demo');
  });

  test('normalizes surrounding whitespace without fuzzy matching', () {
    expect(
      cockpitNormalizeWindowsProcessName('  cockpit-demo.exe  '),
      'cockpit-demo',
    );
    expect(cockpitNormalizeWindowsProcessName(''), isEmpty);
  });

  test('rejects ambiguous app-only window selection', () {
    expect(
      () => cockpitSelectWindowsWindowTarget(
        const <CockpitWindowsWindowTarget>[_smallWindow, _otherProcessWindow],
        appId: 'cockpit_demo',
        processId: null,
      ),
      throwsA(
        isA<CockpitWindowsWindowException>().having(
          (error) => error.code,
          'code',
          'windowsWindowAmbiguous',
        ),
      ),
    );
  });

  test('selects the largest main window for an exact process', () {
    final selected = cockpitSelectWindowsWindowTarget(
      const <CockpitWindowsWindowTarget>[_smallWindow, _largeWindow],
      appId: 'cockpit_demo',
      processId: 4101,
    );

    expect(selected.handle, 42);
  });
}

const _smallWindow = CockpitWindowsWindowTarget(
  processId: 4101,
  title: 'Small',
  handle: 41,
  left: 0,
  top: 0,
  width: 320,
  height: 240,
);

const _largeWindow = CockpitWindowsWindowTarget(
  processId: 4101,
  title: 'Large',
  handle: 42,
  left: 0,
  top: 0,
  width: 1280,
  height: 720,
);

const _otherProcessWindow = CockpitWindowsWindowTarget(
  processId: 4102,
  title: 'Other',
  handle: 43,
  left: 0,
  top: 0,
  width: 800,
  height: 600,
);
