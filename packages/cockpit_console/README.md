# Cockpit Console

Cockpit Console is the desktop client for Cockpit Supervisor. It provides live
views for workspaces, targets, test documents, runs, operations, and ACP agent
sessions while using the same public Supervisor contracts as the CLI.

## Platforms

- macOS
- Linux
- Windows

## Development

From the repository root:

```bash
flutter pub get
cd packages/cockpit_console
flutter run -d macos
```

Start Cockpit Supervisor before opening the Console. The app discovers the
local Supervisor through Cockpit's normal discovery state; it does not store or
request service credentials.

## Releases

Console releases are independent from the Dart and Flutter packages. Pushing a
tag matching `cockpit-console-v<pubspec-version>` runs the Console release
workflow and publishes desktop archives to that GitHub Release.

The workflow also supports manual dispatch for an existing Console tag. It
tests and analyzes the app before building macOS, Linux, and Windows artifacts.
