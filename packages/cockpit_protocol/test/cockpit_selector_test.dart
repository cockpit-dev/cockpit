import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('parses compact multi-condition selectors', () {
    expect(
      CockpitSelector.parse(
        'Dialog >> TextButton#save@save-key["Save"]'
        '[tip="Save changes"][route="/edit"][path="/dialog/save"]:nth(2)',
      ),
      const CockpitLocator(
        cockpitId: 'save',
        key: 'save-key',
        text: 'Save',
        tooltip: 'Save changes',
        type: 'TextButton',
        route: '/edit',
        path: '/dialog/save',
        index: 1,
        ancestor: CockpitLocator(type: 'Dialog'),
      ),
    );
  });

  test('plain targets stay exact and text modes are explicit', () {
    expect(CockpitSelector.parse('Save'), const CockpitLocator(text: 'Save'));
    expect(
      CockpitSelector.parse('[*="Save"]'),
      const CockpitLocator(
        text: 'Save',
        matchMode: CockpitTextMatchMode.contains,
      ),
    );
    expect(
      CockpitSelector.parse('[tip~="Svae"]'),
      const CockpitLocator(
        tooltip: 'Svae',
        matchMode: CockpitTextMatchMode.fuzzy,
      ),
    );
  });

  test(
    'distinguishes explicit selectors from free-text inspection queries',
    () {
      expect(CockpitSelector.isExplicit('Save changes'), isFalse);
      expect(CockpitSelector.isExplicit('Release notes [draft]'), isFalse);
      expect(CockpitSelector.isExplicit('@save-key'), isTrue);
      expect(CockpitSelector.isExplicit('#save'), isTrue);
      expect(CockpitSelector.isExplicit('FilledButton["Save"]'), isTrue);
      expect(CockpitSelector.isExplicit('Dialog >> Continue'), isTrue);
    },
  );

  test('formats canonical selectors which round trip', () {
    const locator = CockpitLocator(
      cockpitId: 'save',
      text: 'Save "now"',
      type: 'FilledButton',
      route: '/edit',
      ancestor: CockpitLocator(
        type: 'Dialog',
        ancestor: CockpitLocator(key: 'root-dialog'),
      ),
    );

    final selector = CockpitSelector.format(locator);

    expect(
      selector,
      '@root-dialog >> Dialog >> FilledButton#save["Save \\"now\\""]'
      '[route="/edit"]',
    );
    expect(CockpitSelector.parse(selector), locator);
  });

  test('preserves stable index on a plain text locator', () {
    const locator = CockpitLocator(text: 'Continue', index: 1);

    expect(CockpitSelector.format(locator), '["Continue"]:nth(2)');
    expect(CockpitSelector.parse(CockpitSelector.format(locator)), locator);
  });

  test('rejects ambiguous or malformed selectors', () {
    expect(
      () => CockpitSelector.parse('[*="Save"][tip~="Svae"]'),
      throwsFormatException,
    );
    expect(() => CockpitSelector.parse(':nth(0)'), throwsFormatException);
    expect(() => CockpitSelector.parse('Dialog >> '), throwsFormatException);
    expect(() => CockpitSelector.parse('[unknown="x"]'), throwsFormatException);
    expect(
      () => CockpitSelector.parse('[reg="internal"]'),
      throwsFormatException,
    );
    expect(() => CockpitSelector.parse('[/="Save.*"]'), throwsFormatException);
    expect(
      () => CockpitSelector.format(
        const CockpitLocator(registrationId: 'internal'),
      ),
      throwsFormatException,
    );
    expect(
      () => CockpitSelector.format(
        const CockpitLocator(
          text: 'Save.*',
          matchMode: CockpitTextMatchMode.regex,
        ),
      ),
      throwsFormatException,
    );
  });
}
