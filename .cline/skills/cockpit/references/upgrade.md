# Cockpit upgrades

An upgrade has two independent layers. Update the host tooling first, then
update the Cockpit packages used by the Flutter project. Keeping only one layer
current creates a mixed CLI/bridge surface that can look healthy while actions,
native evidence, or integration tests use older contracts.

## Host tooling

Run the side-effect-free check when deciding whether an upgrade is needed:

```bash
cockpit update --check
```

Apply the host upgrade only after the check identifies a newer release:

```bash
cockpit update
cockpit skill
```

Give the `cockpit skill` prompt to the active AI host. `cockpit update` replaces
the CLI and Supervisor in place, preserves authorization, sessions, and durable
state, and reconciles a running engine. It does not change any Flutter project
dependency. Never remove Cockpit home data, Pub caches, sessions, executables,
or ports manually.

## Flutter project packages

Update the development shell and all Cockpit packages to the same release line:

- `cockpit_protocol` — shared DTO and operation contracts;
- `flutter_cockpit` — the in-app bridge and native plugin;
- `flutter_cockpit_test` — the Dart integration-test facade;
- `cockpit` — the shell CLI/worker dependency when the project has a
  `cockpit/` development package.

Keep these dependencies out of the production application package whenever the
project uses a separate development shell. Update the shell or test package
`pubspec.yaml` constraints, then resolve from the workspace root:

```bash
flutter pub get
```

For a package that is not in a Pub workspace, run `flutter pub get` from that
package's own root. Let Pub regenerate platform lockfiles; do not hand-edit
`Podfile.lock`, `Package.resolved`, or generated plugin registrants.

After dependency resolution, verify that every Cockpit package in the project
uses the same release line and that no stale package constraint remains:

```bash
rg -n 'cockpit(_protocol)?|flutter_cockpit(_test)?' --glob 'pubspec.yaml'
flutter pub outdated
```

Do not use a broad major-version upgrade command for the whole application just
to update Cockpit. It can change unrelated dependencies and make a failure hard
to attribute. Upgrade only the Cockpit constraints, then review the lockfile
diff for unexpected package churn.

## Reconnect and verify

The existing development handle remains the selector after an upgrade. Do not
start a second app to refresh an old bridge. From the intended project:

```bash
cockpit dev status
cockpit dev diagnose
cockpit dev reload
cockpit dev inspect
```

If the bridge cannot reconnect after the package update, use the same session's
`cockpit dev recover` once, then read status again. Only an explicitly stopped
or crashed owned app should be relaunched with `cockpit dev start`.

Run the smallest proof for the changed layer: the project's Flutter tests for
`flutter_cockpit_test`, a focused `dev` interaction for the bridge, and a case or
suite validation for black-box coverage. Re-run native capture or host actions
when the update changes platform plugin code. A successful process exit is not
enough; require the expected UI/state postcondition and current evidence.

## CI and release checks

CI should resolve the same package set on the supported minimum Flutter version,
run the bridge and integration-test suites, exercise CocoaPods and SwiftPM on
Darwin, and perform Pub dry-runs for every publishable package. Publish only
after those gates pass. Keep README instructions version-independent; changelog
and package metadata are the release source of truth.
