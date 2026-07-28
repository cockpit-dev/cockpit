# Platform Environments And Recovery

Use this reference when discovery, launch, native control, capture, recording,
or a platform tool is unavailable. Repair the host first; do not turn a missing
capability into a passing fallback for a release gate.

## Diagnose From The Outside In

Run the cheapest checks in this order:

```bash
cockpit daemon status
cockpit daemon doctor
cockpit target discover
cockpit operation list --workspace-id <workspaceId>
cockpit target inspect --target-id <targetId> --profile inspect
```

Read `available`, `limitations`, driver/adapter identity, quality flags, and the
exact failure reason. Then verify the named platform tool directly. After a
repair, restart the daemon if its process environment or macOS permissions
changed, rediscover the device, and inspect the target again. A stale target
record is not capability proof.

Cockpit requires Dart 3.8 or newer. Install the Flutter SDK when Flutter build,
launch, reload, or semantic bridge capabilities are needed. Ensure the global
package executable directory is on `PATH`:

```bash
dart --version
flutter --version
dart pub global activate cockpit ^2.0.0
cockpit --version
```

For local development and test targets, start authorization at daemon creation:

```bash
cockpit daemon restart --yolo
cockpit daemon status
```

Confirm `authorizationMode: yolo`. Do not use YOLO for production/unknown
targets, shared devices, or real external side effects.

## Android

Required host components are a compatible JDK, Android SDK command-line tools,
platform-tools, an installed platform image, and either a booted emulator or an
authorized physical device. Cockpit owns its packaged Android automation
driver; users do not build a driver from the Cockpit source repository.

```bash
java -version
adb version
adb devices -l
sdkmanager --list
emulator -list-avds
```

Set `ANDROID_HOME` or `ANDROID_SDK_ROOT`, and add
`$ANDROID_HOME/platform-tools`, `$ANDROID_HOME/cmdline-tools/latest/bin`, and
`$ANDROID_HOME/emulator` to `PATH`. Install missing components and accept SDK
licenses with the SDK manager. Match the platform and build-tools versions to
the application build; JDK 17 is the reliable baseline for current Android
Gradle builds.

An emulator must finish booting before discovery:

```bash
adb wait-for-device
adb shell getprop sys.boot_completed
```

On Linux CI, enable KVM access or use another supported hypervisor. On a
physical device, enable Developer options and USB debugging, unlock the device,
accept the host RSA prompt, and require `adb devices -l` to show `device`, not
`unauthorized` or `offline`. Restart ADB after PATH, USB, or authorization
repairs:

```bash
adb kill-server
adb start-server
```

Grant runtime permissions needed by the tested scenario or model the permission
dialog as a native step. Disable system animations only for deterministic CI,
not to hide an animation behavior the case intends to verify. Black-box Android
control is non-invasive and requires the installed application ID, not source
changes or a Flutter bridge.

## iOS And iPadOS

iOS automation requires macOS, a selected complete Xcode installation,
accepted first-launch components, an available Simulator runtime or trusted
physical device, and a reachable WebDriverAgent (WDA) endpoint for native
locator/input/assertion work.

```bash
xcode-select -p
xcodebuild -version
xcrun simctl list devices available
xcrun simctl list runtimes available
```

Repair Xcode selection and first-launch setup when needed:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

Boot a Simulator explicitly and wait for readiness:

```bash
xcrun simctl boot <simulatorUdid>
xcrun simctl bootstatus <simulatorUdid> -b
```

Use a maintained WDA distribution such as Appium's
`appium-webdriveragent`. For a Simulator, run its XCTest runner without code
signing and keep the process alive for the whole Cockpit target lifetime:

```bash
xcodebuild \
  -project <WDA_ROOT>/WebDriverAgent.xcodeproj \
  -scheme WebDriverAgentRunner \
  -destination 'platform=iOS Simulator,id=<simulatorUdid>' \
  -derivedDataPath <isolatedDerivedData> \
  CODE_SIGNING_ALLOWED=NO test
curl --fail http://127.0.0.1:8100/status
```

Register each iOS target with the reachable endpoint:

```bash
cockpit target register \
  --workspace-id <workspaceId> \
  --platform ios \
  --device-id <deviceId> \
  --target-kind nativeApp \
  --environment test \
  --app-id <bundleId> \
  --wda-url http://127.0.0.1:<port> \
  --idempotency-key <uniqueKey>
```

`FLUTTER_COCKPIT_IOS_WDA_URL` is a process-level default when explicit target
registration is unavailable; prefer `--wda-url` because it remains
target-scoped. WDA readiness means `/status` succeeds and `target inspect`
advertises native UI-tree and locator actions. A screenshot-only fallback does
not prove native iOS E2E completeness.

For a physical device, enable Developer Mode, unlock and trust both computer
and development certificate, confirm it with `xcrun devicectl list devices`,
and sign WDA with a valid development team/profile. Keep its device connection
or port forwarding alive and register that reachable URL. Signing, trust, and
Developer Mode failures must remain explicit environment failures.

Flutter apps use the same native WDA plane for system dialogs, WebViews, native
screens, and mixed-stack transitions. The optional development shell adds
Flutter semantics and runtime diagnostics; it is not required for installed
black-box control and never belongs in the production app.

## macOS

Native tree/input may require Accessibility; screenshots and recording may
require Screen Recording; scripted cross-application behavior may require
Automation. Grant only the permissions advertised by the chosen operation in
System Settings > Privacy & Security. Grant them to the terminal, CI runner, or
executable that actually hosts Cockpit, then restart that host and the daemon.

Keep a logged-in foreground desktop session. Headless SSH sessions cannot
provide reliable WindowServer UI automation. Re-inspect the target after every
permission change; do not infer success from the Settings toggle alone.

## Linux

Native desktop control needs an active display. X11 supports common Cockpit
tooling directly; native Wayland security may restrict global tree/input and
capture, so use an advertised portal/driver or an isolated X11/Xvfb CI session.

Typical Debian/Ubuntu dependencies include `xvfb`, `x11-utils`, `xdotool`,
`ffmpeg`, GTK development/runtime libraries, `clang`, `cmake`, `ninja-build`,
and `pkg-config`. Verify `DISPLAY`, `xdotool`, and `ffmpeg` before discovery.
Launch the entire test command inside one `xvfb-run` process so display state
is not split across shells.

## Windows

Run Cockpit in an unlocked interactive desktop session. Windows UI Automation,
window activation, input, screenshots, and `ffmpeg` `gdigrab` recording cannot
be proven from a non-interactive service session. Install the Flutter Windows
toolchain when building Flutter desktop apps and ensure `ffmpeg.exe` is on
`PATH` when recording is required.

Long paths and inherited ACLs can break builds before automation starts. Use a
short workspace/output root and ensure the current user owns it. Keep each job
in its own directory rather than sharing build or report output.

## Web

Install a supported browser and confirm Flutter/device discovery sees it.
Headless CI needs the browser executable and its required system libraries;
headed interaction needs a display server. Treat browser-driver, origin,
certificate, popup, download, and sandbox restrictions as environment facts.
Do not substitute coordinate clicks when the requested browser/semantic
capability is unavailable unless the target explicitly advertises that plane.

## Parallel Projects And Devices

Register every checkout as a separate workspace. Give every job unique output,
temporary, build, and derived-data directories. The Supervisor isolates workers
by workspace, but physical devices, emulators, display servers, and ports remain
finite leased resources.

Use one WDA endpoint/port per iOS target, one emulator/Simulator identity per
concurrent mobile job, and never share a run ID or idempotency key across
logical actions. Do not stop a daemon, device, display, or WDA process owned by
another workspace. After a timeout, inspect the run and lease state before
retrying; a long operation in one workspace must not become a global blocker.

## Common Failure Mapping

| Symptom | Repair |
| --- | --- |
| Daemon unavailable or stale | `daemon doctor`, inspect bounded logs, restart with the intended authorization mode |
| No device discovered | verify the native device tool first, boot/unlock/authorize, then rediscover |
| Target exists but action is absent | inspect capability limitations; install/authorize the named driver or choose an advertised plane |
| Android `unauthorized`/`offline` | unlock, accept RSA, repair USB, restart ADB |
| iOS tree/locator unavailable | start WDA, verify `/status`, assign the endpoint to the target, re-register/re-inspect |
| macOS permission denied | grant the hosting process, restart it and Cockpit, then re-inspect |
| Capture works but locator does not | treat locator coverage as unavailable; capture is evidence, not control proof |
| Recording unavailable | verify platform recorder and interactive session; require it only when the case/release policy does |
| Operation timed out | inspect current state before retry; change only that operation/step timeout when measured cost justifies it |
