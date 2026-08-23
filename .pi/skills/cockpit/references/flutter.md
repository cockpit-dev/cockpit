# Flutter Development Shell

Use this reference when adding or repairing the development-only Flutter
bridge. Once the shell exists, use the short `cockpit dev` workflow from
`SKILL.md`.

## Contents

- [Keep production untouched](#keep-production-untouched)
- [Add the dependency](#add-the-dependency)
- [Create the entrypoint](#create-the-entrypoint)
- [Start and control](#start-and-control)
- [Platform behavior](#platform-behavior)
- [Router integration](#router-integration)
- [Debugging](#debugging)

## Keep Production Untouched

Keep Cockpit imports and wiring under `cockpit/`. Do not import
`flutter_cockpit` from production `lib/` code and do not replace the production
entrypoint.

```text
cockpit/
  main.dart
  cockpit_bootstrap.dart
lib/
  ... unchanged production code ...
```

The shell imports the application's existing public root widget or bootstrap.

## Add The Dependency

Add the bridge as a development dependency:

```yaml
dev_dependencies:
  flutter_cockpit: any
```

Resolve packages with `flutter pub get`. The standalone `cockpit` CLI does not
belong in the application dependencies.

## Create The Entrypoint

`cockpit/main.dart`:

```dart
import 'package:flutter/widgets.dart';

import 'cockpit_bootstrap.dart';

void main() {
  runApp(buildCockpitDevelopmentApp());
}
```

`cockpit/cockpit_bootstrap.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';

import 'package:your_app/app.dart';

Widget buildCockpitDevelopmentApp() {
  const diagnostics = bool.fromEnvironment(
    'FLUTTER_COCKPIT_ENABLE_DEBUG_DIAGNOSTICS',
  );
  return FlutterCockpitApp(
    config: FlutterCockpitConfig.production(
      remoteSession: CockpitRemoteSessionConfiguration.resolveFromEnvironment(
        fallback: const CockpitRemoteSessionConfiguration(
          enabled: true,
          host: '127.0.0.1',
          port: 47331,
        ),
      ),
      diagnostics: CockpitDiagnosticsConfig(
        enableRebuildTracking: diagnostics,
      ),
    ),
    child: YourExistingApp(
      navigatorObservers: <NavigatorObserver>[
        FlutterCockpit.createNavigatorObserver(),
      ],
    ),
  );
}
```

Replace only the application import, root widget, and observer parameter with
the application's real public API. Create one Cockpit observer per Navigator.

## Start And Control

Run from anywhere inside the checkout:

```bash
cockpit dev start
```

For a monorepo or non-default entrypoint, pass the workspace-relative path:

```bash
cockpit dev start apps/mobile/cockpit/main.dart --platform macos
```

Pass only real application launch choices:

```bash
cockpit dev start \
  --flavor staging \
  --dart-define API_URL=https://example.test \
  --dart-define-from-file config/development.json \
  --env LOG_LEVEL=debug
```

Cockpit indexes the entrypoint, selects/registers the Flutter target, launches
the process, authenticates the bridge, and binds one numeric handle. Do not
manually register workspace, target, app, port, or runtime session IDs.

Use task commands after launch:

```bash
cockpit dev inspect
cockpit dev tap "Save"
cockpit dev type "Ada" --into "Name"
cockpit dev wait
cockpit dev viewport 800x600
cockpit dev screenshot
cockpit dev reload
cockpit dev diagnose
```

Target conditions are conjunctive. Keep the common command short, then add
only the condition needed to resolve ambiguity:

```bash
cockpit dev tap '#save-button'
cockpit dev tap 'Dialog >> TextButton["Save"]'
cockpit dev type "Ada" --into '@profile-name'
```

Execute a routine exact-text action without inspecting first. If it is
ambiguous, run `cockpit dev inspect "Save"` once. It searches mounted Flutter
Element targets without requiring Semantics labels and returns `sel` (the shortest
stable selector) and `can` (known actions). Copy `sel` exactly; do not use
registration IDs.

With no query, `cockpit dev inspect` returns the current mounted control surface
in visual order. Its compact `:REF` selectors are live handles for the current UI;
copy one directly into the command named by `can`, then re-inspect after navigation,
overlay, filtering, reorder, keyboard, or another control-surface change. Targeted
inspection returns stable selectors suitable for durable reuse.

Selectors are conjunctive: `#id`, `@key`, `Type["text"]`, named filters such as
`[tip="Save"][route="/edit"]`, and ancestor chains such as
`Dialog >> TextButton["Continue"]`. `[*="text"]` and `[~="text"]` opt into
contains and fuzzy matching. `:nth(2)` is 1-based and only for stable ordered
items. Equal candidates remain ambiguous.

When source is available and a custom control is unlabeled, ambiguous, or absent
from compact inspect, use `rg` to find its visible text, route, public Widget type,
tooltip, or callback, then read only the containing build method and callback.
Execute the real structure directly: `CompanyButton >> Text["Save"]`, or
`Toolbar >> [type="CompanyIconButton"]` for a control with no text, key, or
Semantics. Explicit action locators traverse the mounted Element tree independently
of compact inspect. Cockpit requires one visible match and uses the known action owner
or a real hit-tested `tap`, `hold`, or `double`; equal matches remain ambiguous.
Add only a source-proven ancestor or condition, never an invented key, semantic label,
or coordinate. The live postcondition proves the action.

Use the tree only when target inspection is insufficient:

```bash
cockpit dev tree
cockpit dev tree --view more
cockpit dev tree --view full
```

The default returns a compact actionable selector index. `more` writes the mounted
public Widget structure to a verified artifact path. `full` writes every mounted
Element, including offstage/private nodes. Structural tree stdout contains only the
path.
Semantics is supplementary; direct Widget text remains discoverable even below
`ExcludeSemantics`.

The bridge exposes Element/RenderObject targets, optional Semantics, route and focus state, framework
and isolate errors, app logs, HTTP activity, rebuild signals, screenshots,
recording, idle state, and typed command results. Cockpit reads these through
the same handle.

## Platform Behavior

- macOS, Windows, and Linux resize the owning Flutter window content area and
  wait for settled Flutter metrics.
- Web reports the managed browser viewport alternative.
- Android and iOS report `fixedMobileViewport` with advertised device and
  orientation options.
- Android/iOS `--env` configures the Flutter build process. Use Dart defines or
  an application-owned configuration channel for mobile runtime values.
- Screenshots use ADB/simctl/WDA first on Android/iOS so system dialogs are
  visible, with Flutter view fallback. Desktop and web use Flutter view first.
- System dialogs, permissions, platform views, and native shell screens use an
  advertised native/system control plane; return to Flutter state for the
  postcondition.

## Router Integration

If the shell creates the Navigator, supply the observer as above. If the
existing application owns `MaterialApp`, `GoRouter`, or another Router and does
not accept observers, bind route state from the development-only adapter:

```dart
FlutterCockpit.bindRouteInformationProvider(router.routeInformationProvider);
```

When no public provider exists, update route state from a development-only
listener:

```dart
FlutterCockpit.setCurrentRouteName(currentRouteName);
```

Do not create a second production navigation model for automation.

## Debugging

Use the smallest read that answers the next question:

```bash
cockpit dev status
cockpit dev inspect "Expected text"
cockpit dev diagnose --view more
```

Use `cockpit explain <operation>` only when a task command is
missing. Exact live schemas are authoritative. A generic schema is not a basis
for guessing fields.

When the bridge or port changes, keep using the same handle; Cockpit proves
process and checkout ownership before reconnecting. Unexpected process exits
may relaunch once from stored non-secret launch configuration. Reads do not
launch a stopped app. Finish visible verification with a current screenshot and
zero new disqualifying runtime errors.
