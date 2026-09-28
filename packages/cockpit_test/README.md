# cockpit_test

[English](README.md) · [简体中文](README.zh-CN.md)

Platform-neutral, in-process test scenarios shared by Cockpit runners. Author a
scenario once against `CockpitTester`, then execute the same Dart closure in a
Flutter integration test, a bridge-connected release/profile app, or a native
black-box target.

`cockpit_test` depends only on `cockpit_protocol`. It owns the shared authoring,
preflight, locale, runner, and result contracts; concrete testers and platform
lifecycle remain in dependent packages.

## Author a scenario

A scenario is an id and a body. Nothing else is required:

```dart
import 'package:cockpit_test/cockpit_test.dart';

final smoke = CockpitTestScenario(
  id: 'save-settings',
  body: (tester) async {
    await tester.tap('Settings');
    await tester.type('Alice', into: 'Name');
    await tester.tap('Save');
    await tester.expectText('#status', 'Saved');
  },
);
```

The body only uses selectors, protocol values, plain Dart, and the active
locale — never `WidgetTester`, `BuildContext`, or a native SDK — so the same
closure runs on every surface.

## Assert, wait, and read back

Target-side assertions and waits cover the common UI checks, and every method
below means the same protocol operation on all three surfaces:

```dart
// Text matching: exact by default, plus contains / fuzzy / regex.
await tester.expectText('#status', 'Saved');
await tester.expectText('#title', 'Settings', match: CockpitTextMatchMode.contains);

// Presence and, just as importantly, absence — the shared way to assert that
// something disappeared.
await tester.waitFor('#drawer');
await tester.waitFor('#spinner', absent: true);

// Read the real UI state back instead of only asserting, then compare it in
// plain Dart. These host-side helpers throw structured assertion failures the
// runner reports as failed tests, not internal errors.
final snapshot = await tester.collectSnapshot();
cockpitExpectEquals(snapshot.visibleTargets.length, 2);
cockpitExpectTrue(snapshot.routeName == 'settings');
cockpitExpectContains(await readLabels(snapshot), 'Saved');
```

The full helper set is `cockpitExpectEquals` (deep equality over numbers,
strings, booleans, lists, sets, and maps), `cockpitExpectTrue`,
`cockpitExpectNotNull`, and `cockpitExpectContains` (string, iterable, or map
key membership).

## Run it on Flutter

`flutter_cockpit_test` reuses Flutter's official `integration_test` runner and
mount/teardown lifecycle:

```dart
cockpitScenarioWidgets(
  'saves settings',
  app: buildDevelopmentApp,
  scenario: smoke,
);
```

Use `cockpitTestWidgets` instead when a test intentionally needs Flutter-only
APIs in addition to the shared `CockpitTester` surface.

## Cross a locale matrix once

Wrap scenarios in a suite — bare scenarios are enough, each becomes a case
named after its scenario id:

```dart
final suite = CockpitTestSuiteProgram(
  id: 'settings-smoke',
  locales: [
    CockpitLocaleProfile('en-US'),
    CockpitLocaleProfile('zh-Hant-TW'),
  ],
  scenarios: [smoke],
);
```

Pass `cases: [CockpitTestCaseProgram(id: ..., scenario: ...)]` only when a
scenario needs a case-specific id or metadata. Run the matrix with any concrete
tester; the locale is also optional for single runs and defaults to `en-US`:

```dart
import 'package:cockpit/cockpit.dart';

final result = await const CockpitProgrammaticTestRunner().runSuite(
  suite,
  createTester: (locale) async => RemoteCockpitTester(
    client: client,
    workspaceRoot: workspaceRoot,
    initialLocale: locale,
  ),
);
```

Every attempt is `passed`, `failed`, or `blocked` and carries a structured
`CockpitTestError`. An empty suite cannot be constructed, and an empty attempt
collection never reports success.

## Selectors across surfaces

`#cockpitId` and `@key` selectors resolve inside Flutter apps (in-app and
bridge surfaces). Black-box targets only see the accessibility tree, so
scenarios that must run there should stick to the shared locator kinds: text
(`'Save'` or `["text*="Save"]`), tooltip, widget type, and path. Use
`CockpitSelector.format` to see how a locator encodes.

## Capability preflight (advanced)

Declaring typed requirements is optional. When present, the runner checks them
against the target before the body runs and reports every gap at once:

```dart
CockpitTestRequirements(
  commands: const {
    CockpitCommandType.tap,
    CockpitCommandType.enterText,
  },
  locators: const {CockpitLocatorKind.text},
)
```

Requirements use protocol enums, so the tester method `type()` correctly
preflights `CockpitCommandType.enterText`; string aliases cannot drift from
the wire contract. Even without declared requirements, a target that answers
"unsupported capability" mid-run blocks the attempt exactly like a preflight
mismatch — declared requirements simply move that verdict earlier and list
everything missing in one shot. Preflight matters most for black-box targets
and apps with optional integrations (network observer, semantic commands);
default-mounted Flutter apps support the shared surface in full.

## Locale behavior

`CockpitLocaleProfile` validates and canonicalizes language, script, and region
subtags at runtime. For example, `ZH-hant-tw` becomes `zh-Hant-TW`. Metadata and
translation maps are copied into immutable values.

`CockpitLocalizedText` resolves lazily against the current locale using:

1. exact tag, such as `zh-Hant-TW`;
2. language and script, such as `zh-Hant`;
3. language, such as `zh`.

A missing translation raises `CockpitTestLocalizationException`; it never
silently selects an unrelated language.

## Localized message formatting

Pass `params` to format a value as an ICU MessageFormat message. Plural
categories follow the same CLDR rules the app itself uses (`intl` is the rule
engine), so formatted expectations line up with what the app renders:

```dart
CockpitLocalizedText(
  'cart.items',
  values: const {
    'en': '{count, plural, =0 {Empty cart} =1 {One item} other {# items}}',
    'zh': '{count, plural, other {# 件商品}}',
  },
  params: const {'count': 3},
)
```

Without `params`, a value resolves verbatim — literal braces stay literal, so
plain expected text keeps working. The parser covers placeholders, `plural`
with exact `=N` cases taking precedence over CLDR categories, `select` and
gender-style keyword constructs, nested messages, `#` bound to the innermost
plural, and ICU apostrophe quoting (`'{'` escapes a brace, `''` is a literal
apostrophe). Malformed messages throw with the offset instead of rendering
garbage, and `selectordinal` is rejected explicitly because `intl` ships no
ordinal rules.

### Catalogs

Author expectations from the app's real translation files instead of inline
maps. `CockpitArbCatalog` reads ARB — the format of Flutter's official
`gen_l10n` — including `@key` placeholder metadata; `CockpitJsonCatalog` reads
the nested JSON used by `slang` and `easy_localization`:

```dart
import 'package:cockpit_test/catalog_io.dart';

final arb = loadCockpitArbCatalog({
  'en': '../app/lib/l10n/app_en.arb',
  'zh': '../app/lib/l10n/app_zh.arb',
});
await tester.expectText(
  '#cart-caption',
  arb.text('cart.items', params: {'count': 3}),
);

final json = loadCockpitJsonCatalog({
  'en': 'assets/strings_en.json',
  'zh': 'assets/strings_zh.json',
});
```

Both catalogs validate eagerly at construction: malformed ICU messages,
placeholders the ARB metadata does not declare, duplicate keys, and non-string
leaves fail with the full problem list. `validateMatrix(locales)` reports
coverage gaps using the same exact → language-script → language fallback the
runtime resolves with, so a missing `zh-Hant` entry covered by `zh` is not a
false alarm. The loaders are VM-only (host-side scenario code); web hosts
decode assets themselves and use `CockpitArbCatalog.fromArb` /
`CockpitJsonCatalog.fromJson` directly.

## In-process boundary

A scenario body is a Dart closure. `toManifestJson()` is only a diagnostic
projection of IDs, requirements, locale matrix, and metadata; it cannot contain
or reconstruct executable code. Use the declarative `cockpit.test/v2` document
model for persisted, queued, or language-neutral test execution.

A runnable tour lives in
[`example/settings_smoke.dart`](example/settings_smoke.dart).

## Learn more

- [Cross-runner programmatic tests](../../docs/cross-runner-programmatic-testing.md)
- [`cockpit_protocol` contracts](../cockpit_protocol/README.md)
- [`cockpit` concrete testers](../cockpit/README.md)
