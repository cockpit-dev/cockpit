# Interaction recorder host integration guide

The in-app interaction recorder is host-agnostic: the recording engine,
the panel widgets, and the floating window are three separate things, and
any floating-window system (UME, flutter_mana, DoKit, or an in-house
debug panel) can host the recorder through the same public surfaces. No
per-ecosystem adapter packages are shipped — this guide is the adapter.

Architecture context: [interaction-recorder.md](interaction-recorder.md).

## The four public surfaces

```dart
import 'package:flutter_cockpit/flutter_cockpit.dart';

// ① Engine enablement — config-driven, no UI. Required in every mode.
//    Wrap the app (or your dev shell) with FlutterCockpitApp and enable
//    the recorder block; pick a host mode (see table below).

// ② Controller — state + steps + commands. For fully custom UIs.
final controller = CockpitRecorderScope.of(context);
controller.start(); controller.pause(); controller.resume();
controller.stop(); controller.export(); controller.verifyReplay();

// ③ Composable widgets — embed wherever your host renders panels.
const CockpitRecorderPanel();      // full-screen panel content (header /
                                   // controls / timeline / bottom bar); pass
                                   // onClose to get the header close button
const CockpitRecorderEntryButton(); // compact 40×40 entry icon (presentational, onTap callback)
const CockpitRecorderIndicator();   // passive phase indicator (always IgnorePointer)

// ④ Exclusion marker — keep host chrome out of recordings and evidence.
CockpitRecorderExclude(child: myHostChrome);
```

## Choosing a host mode

`FlutterCockpitConfig.recorder` selects who owns the floating window:

| Mode | What mounts | Use when |
| --- | --- | --- |
| `floatingBall` (default) | The built-in draggable ball + panel sheet | No existing debug panel |
| `guest` | Nothing — scope + controller only | Your app already has a floating-window system |
| `headless` | Nothing at all | Remote-driven recording (`cockpit record`, Console, MCP) |

```dart
FlutterCockpitApp(
  config: const FlutterCockpitConfig.production().copyWith(
    recorder: FlutterCockpitRecorderConfig(enabled: true),
  ),
  child: app,
)
```

Recording is unavailable in release builds — enabling the recorder in a
release configuration fails fast at initialization.

## Three integration depths

### Depth 1 — embed the full panel

Drop `CockpitRecorderPanel` into your host's panel area:

```dart
// With UME (user-side code, ~10 lines; no adapter package needed):
class CockpitRecorderPluggable extends Pluggable {
  @override
  Widget buildWidget(BuildContext context) =>
      const CockpitRecorderPanel();

  @override
  Widget buildEntryPoint() => const CockpitRecorderEntryButton();

  @override
  void onTrigger() {}

  @override
  String get name => 'Cockpit';
}

// In main(): wrap the app with the recorder enabled in guest mode, then
// register the panel with your host (UME shown; registerPluggable is
// UME's own API).
runApp(
  FlutterCockpitApp(
    config: const FlutterCockpitConfig.production().copyWith(
      recorder: FlutterCockpitRecorderConfig(
        enabled: true,
        host: CockpitRecorderHostMode.guest,
      ),
    ),
    child: UMEWidget(child: app),
  ),
);
registerPluggable(CockpitRecorderPluggable());
```

Any framework with a "register a panel widget" concept — flutter_mana,
DoKit, an in-house dock — integrates identically.

### Depth 2 — mix and match

Hosts that only have an entry slot can show `CockpitRecorderEntryButton`
(or `CockpitRecorderIndicator` for passive status) and open the panel
themselves.

### Depth 3 — fully custom UI

Build your own controls on the controller alone: phase, step list, and
every command (`start`/`pause`/`resume`/`stop`, segments, annotate,
discard, export, verify replay). The panel widgets use exactly this API —
there is no second path.

## Keeping your chrome out of the recording

The capture layer resolves every pointer hit to registered semantic
targets. Host chrome fails that resolution by design, and three tiers
keep recordings and evidence screenshots clean:

1. **Marker (preferred).** Wrap your floating window's contents:
   `CockpitRecorderExclude(child: ...)`. Events whose hit path crosses
   the marker are dropped before they become steps. The built-in host
   does this for its own ball and panel.
2. **Registry.** For chrome you cannot wrap (a third-party ball you do
   not build), register its render subtree on the engine's exclusion
   registry.
3. **Semantic fallback.** Anything that still resolves to no target
   (typical for debug chrome, which carries no semantics) is recorded as
   an `unresolved` noise step — visible in the timeline, dropped from the
   exported case.

Evidence screenshots are taken from the capture boundary that excludes
the outer HUD layer entirely; registered/marked subtrees are excluded the
same way, so exported artifacts never contain recorder or host UI.

## Headless / remote control

With the recorder enabled, the remote session server exposes the full
lifecycle — `cockpit record start|pause|resume|stop|status|steps|export`
against a live dev session, the Console recorder screen, and the seven
`recorder_*` MCP tools. None of these surfaces requires any UI mounted in
the app.
