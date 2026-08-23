# Cockpit Console

Cockpit Console is the desktop client for Cockpit Supervisor. It uses the same
public REST/SSE contracts and typed protocol as the CLI and MCP server; it does
not link Supervisor application services into the app process.

## Capabilities

- Dashboard health and recent activity across the connected Supervisor.
- Project root and workspace registration with explicit checkout identity.
- Application and device discovery, registration, launch, inspection, and
  live capability state.
- Concurrent development-session monitoring with project, entrypoint,
  platform, device, lifecycle, route, and bridge identity.
- On-demand session views for mounted UI, startup/runtime logs, bounded network
  activity and bodies, newest-first activity timeline, runtime errors, and
  diagnostics. Detail reads are lazy and retained activity is bounded so long
  sessions do not grow memory without limit.
- LON, JSON, and YAML case/suite authoring, validation, and execution.
- Durable run submission, resumable live events, cancellation, terminal state,
  and report-backed results.
- Advertised operation discovery with exact schema-aware LON, JSON, or YAML
  inputs.
- ACP assistant sessions with streaming conversation updates, tool calls,
  permissions, attachments, and session lifecycle controls.
- Responsive desktop navigation, light/dark themes, and English or Simplified
  Chinese UI.

## Platforms

- macOS
- Linux
- Windows

## Development

Cockpit Console requires Flutter 3.44.0 or newer. The published Cockpit
packages retain their independent Flutter 3.32.0 compatibility floor.

From the repository root:

```bash
flutter pub get
cockpit daemon start --yolo
cd packages/cockpit_console
flutter run -d macos
```

The Console intentionally does not start a stopped Supervisor behind the
user's back. Start it before opening the app; use a restricted policy instead
of `--yolo` when the environment requires one. The app discovers the loopback
endpoint and bearer token through Cockpit's normal lifecycle state. It never
copies that token into preferences or a keychain, and network bodies are read
only when the user requests them.

## Releases

Console releases are independent from the Dart and Flutter packages. Pushing a
tag matching `cockpit-console-v<pubspec-version>` runs the Console release
workflow and publishes desktop archives to that GitHub Release.

The workflow also supports manual dispatch for an existing Console tag. It
tests and analyzes the app before building macOS, Linux, and Windows artifacts.
