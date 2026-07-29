<p align="center">
  <img src="../../assets/brand/cockpit-mark.svg" width="128" alt="Cockpit logo">
</p>

# cockpit_demo

`cockpit_demo` is the repository's production Flutter acceptance target. The
application package remains free of Cockpit dependencies; the sibling
`cockpit/` directory is a non-published development shell that owns the
`flutter_cockpit` bridge, Cockpit CLI, E2E documents, and acceptance runner.

The same `cockpit.test/v2` suite runs locally and in CI on Android, iOS, macOS,
Linux, web, and Windows. It validates real navigation and form behavior,
streams durable run events, downloads digest-checked evidence, and emits JSON,
JUnit, HTML, and AI-oriented reports.

## Bootstrap

Use Flutter 3.32.0 or newer:

```bash
flutter pub get
cd examples/cockpit_demo/cockpit
flutter pub get
```

Platform prerequisites are the normal Flutter toolchains: a booted Android
emulator, Xcode and an iOS simulator, Chrome for web, or the corresponding
desktop toolchain. The runner discovers live devices and does not infer a
device when more than one matching target is available.

## Run The Regression Suite

Use an isolated Cockpit home so parallel projects do not share credentials,
daemon state, workers, or target ownership:

```bash
export COCKPIT_HOME="$PWD/.dart_tool/cockpit-home"
dart run cockpit daemon policy apply --file e2e/authorization.ci.json
dart run tool/verify.dart --platform macos --stop-daemon
```

Pass `--device-id` when discovery finds multiple devices:

```bash
dart run tool/verify.dart \
  --platform ios \
  --device-id <simulator-udid> \
  --output-root /tmp/cockpit-demo-acceptance \
  --stop-daemon
```

The default output root is `.dart_tool/cockpit_acceptance`. Every invocation
creates its own directory, so concurrent runs do not overwrite each other.
Each result contains:

- `events.jsonl`: ordered Supervisor events suitable for replay and diagnosis;
- `run.json` and `report.json`: terminal run state and suite aggregate;
- `artifacts.json`: artifact metadata returned by the public API;
- `artifacts/`: streamed files verified against declared size and SHA-256;
- `summary.json`: machine-readable acceptance and cleanup result.

The process exits successfully only when the suite passes, all artifacts are
verified, the launched app is stopped, and requested daemon cleanup succeeds.

## Documents

- Cases: `cockpit/e2e/cases/`
- Suite: `cockpit/e2e/suites/regression.suite.yaml`
- CI authorization: `cockpit/e2e/authorization.ci.json`
- Runner: `cockpit/tool/verify.dart`

Validate edited documents before running them:

```bash
dart run cockpit case validate \
  --file e2e/cases/task_editor_validation.case.yaml \
  --format yaml
dart run cockpit suite validate \
  --file e2e/suites/regression.suite.yaml \
  --format yaml
```

## CI

The repository workflow [`.github/workflows/example-e2e.yml`](../../.github/workflows/example-e2e.yml)
runs this exact acceptance entrypoint on all six supported platforms and
uploads only the acceptance output. `COCKPIT_HOME` is deliberately excluded so
Supervisor credentials are never published as CI artifacts.
