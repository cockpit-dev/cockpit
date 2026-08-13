# Platform Environments And Recovery

Use this reference when discovery, launch, native control, capture, recording,
or a platform tool is unavailable. Repair the host first; do not turn a missing
capability into a passing fallback for a release gate.

## Contents

- [Diagnose from the outside in](#diagnose-from-the-outside-in)
- [Android](#android)
- [iOS and iPadOS](#ios-and-ipados)
- [macOS](#macos)
- [Linux](#linux)
- [Windows](#windows)
- [Web](#web)
- [Parallel projects and devices](#parallel-projects-and-devices)
- [Common failure mapping](#common-failure-mapping)

## Diagnose From The Outside In

Run the cheapest checks in this order:

```bash
cockpit daemon status
cockpit daemon doctor
cockpit target discover
cockpit op list --workspace-id <workspaceId>
cockpit target inspect --target-id <targetId> --profile inspect
```

An executable on `PATH` proves only that a probe can start. For release work,
run the cheapest real operation required by the suite: read one native UI tree,
resolve one stable locator, capture one screenshot, and start/stop recording when
recording is required. Keep the capability unavailable when that probe fails;
the exact environment failure belongs in the run and report.

If a tool is found but exits before printing its version because a dynamic
library, runtime, or plugin cannot load, repair or reinstall that toolchain.
Changing `PATH` cannot fix a broken executable. Run its version command again
before repeating Cockpit discovery.

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
flutter doctor -v
dart pub global activate cockpit any
cockpit help
```

For local development and test targets, start authorization at daemon creation:

```bash
cockpit daemon restart --yolo
cockpit daemon status
```

Confirm `auth: yolo`. Do not use YOLO for production/unknown
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

When Flutter or Gradle reports a missing SDK component, install the exact
reported platform/build-tools pair and accept licenses before retrying:

```bash
sdkmanager --licenses
sdkmanager "platform-tools" "emulator" "platforms;android-<api>" "build-tools;<version>"
```

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
xcodebuild -checkFirstLaunchStatus
xcrun simctl list devices available
xcrun simctl list runtimes available
```

Repair Xcode selection and first-launch setup when needed:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

Flutter plugins may arrive through Swift Package Manager or CocoaPods. Do not
force a migration: inspect the app's `pubspec.yaml`, Xcode project, and
`flutter config --list` first. Flutter 3.44 and newer enable SwiftPM by default;
a project or global `enable-swift-package-manager: false` selects CocoaPods,
and an enabled project may still fall back to CocoaPods for another plugin that
does not support SwiftPM.

Only require `pod --version` when the resolved build actually uses CocoaPods;
then repair the CocoaPods/Ruby installation reported by `flutter doctor -v`.
For SwiftPM, require the generated `FlutterGeneratedPluginSwiftPackage` and its
Flutter framework preparation pre-action to exist, then prove the selected path
with one real build. WDA-only black-box control of an already installed app
requires neither package manager.

Boot a Simulator explicitly and wait for readiness:

```bash
xcrun simctl boot <simulatorUdid>
xcrun simctl bootstatus <simulatorUdid> -b
```

If the requested runtime is absent, install it in Xcode Settings > Platforms or
with the Xcode-supported platform download command, then rerun `simctl list
runtimes available`. Do not silently switch the suite to a different device,
runtime, viewport, or visual profile.

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

Flutter launch `dartDefines` and `dartDefineFromFiles` are compiled into the
application on every supported platform. Launch `environment` values belong to
the Flutter build/host process. Desktop apps can inherit them at runtime;
Android/iOS application processes do not inherit arbitrary host variables, so
use Dart defines or the application's own configuration channel for values the
mobile app itself must read. Installed black-box targets accept neither form.

## macOS

Native tree/input may require Accessibility; screenshots and recording may
require Screen Recording; scripted cross-application behavior may require
Automation. Grant only the permissions advertised by the chosen operation in
System Settings > Privacy & Security. Grant them to the terminal, CI runner, or
executable that actually hosts Cockpit, then restart that host and the daemon.

macOS has no supported CLI that silently grants these privacy permissions.
`tccutil reset` only removes a decision; it does not approve access. When
Cockpit is launched by an IDE or desktop agent, grant that application rather
than an unrelated shell. Prove the repaired permission with a real capture or
Accessibility action before rerunning a suite.

Keep a logged-in foreground desktop session. Headless SSH sessions cannot
provide reliable WindowServer UI automation. Re-inspect the target after every
permission change; do not infer success from the Settings toggle alone.

## Linux

Native desktop control needs an active display. X11 supports common Cockpit
tooling directly; native Wayland security may restrict global tree/input and
capture, so use an advertised portal/driver or an isolated X11/Xvfb CI session.
AT-SPI tree inspection additionally requires the desktop accessibility bus;
Cockpit probes it at runtime and reports the tree capability blocked when the
bus or target application is not reachable.

Typical Debian/Ubuntu dependencies include `xvfb`, `x11-utils`, `xdotool`,
`ffmpeg`, GTK development/runtime libraries, `clang`, `cmake`, `ninja-build`,
and `pkg-config`. Verify `DISPLAY`, `xdotool`, and `ffmpeg` before discovery.
For a persistent Cockpit daemon, start one Xvfb server before the daemon and
export the same `DISPLAY` to the daemon, workspace worker, browser, app, and
test process. Wrapping only the final suite command in `xvfb-run` leaves the
already-running daemon without a display.

```bash
Xvfb :99 -screen 0 1280x720x24 -nolisten tcp &
export DISPLAY=:99
until xdpyinfo >/dev/null 2>&1; do sleep 1; done
cockpit daemon start --yolo
```

Give each parallel CI job a different display number and stop only the Xvfb
process started by that job.

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

Flutter Web development keeps using the in-app Flutter Element/RenderObject
bridge. Generic Chromium pages need an automation-owned browser and an explicit
`--cdp-url`. An HTTP(S) endpoint is accepted only when it exposes one page;
otherwise pass the selected page's `ws://.../devtools/page/...` URL. Cockpit
never scans a default debugging port or attaches to another browser profile.
Safari, Firefox, and unreachable endpoints remain blocked.

```bash
cockpit target register \
  --workspace-id <workspaceId> \
  --platform web \
  --device-id chrome \
  --target-kind browserPage \
  --cdp-url ws://127.0.0.1:<port>/devtools/page/<pageId> \
  --environment test \
  --mode automation \
  --idempotency-key web-target-001
```

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
