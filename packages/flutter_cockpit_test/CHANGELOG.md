# Changelog

## 4.0.47

- Synchronized the integration-test facade with the Flutter gesture runtime
  fixes in the current Cockpit release.

## 4.0.46

- Synchronized the integration-test facade with the Flutter-first gesture,
  animation, native-action, and live-watch capabilities.

## 4.0.45

- Synchronized the integration-test facade with the current Cockpit release.
- Completed the Flutter gesture facade with real hover, wheel, coordinate
  input, and device/button-aware pointer actions; animation watch remains
  bounded to compact deltas.

## 4.0.44

- Synchronized the integration-test facade with the current Cockpit release.

## 4.0.43

- Use the native timeout default for explicit host/system actions in the
  integration-test facade.
- Added the `flutter_cockpit_test` integration-test facade.
- Reused Cockpit's in-app Element selectors, hit-tested commands, reveal, waits,
  assertions, snapshots, and evidence paths.
- Added explicit native capture, recording, viewport, and host-action helpers.
- Added common long-press, double-tap, increment/decrement, reveal, wait, and
  live-capability helpers; acceptance screenshots now follow Cockpit's platform
  routing policy by default.
- Added bounded defaults and per-call timeout overrides to the integration-test
  facade, including native capture, recording, viewport, and host actions.
- Applied the default timeout to direct `execute` calls and cancel pending
  native recording startup after a timeout.
