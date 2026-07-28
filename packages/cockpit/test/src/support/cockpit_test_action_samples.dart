import 'package:cockpit_protocol/cockpit_protocol.dart';

CockpitTestAction sampleBoundAction(CockpitTestActionKind kind) =>
    CockpitTestAction.fromJson(_sampleActionJson(kind), path: r'$.action');

Map<String, Object?> _sampleActionJson(CockpitTestActionKind kind) {
  final locator = <String, Object?>{'testId': 'target'};
  final base = <String, Object?>{'type': kind.name};
  return <String, Object?>{
    ...base,
    ...switch (kind) {
      CockpitTestActionKind.tap => <String, Object?>{
        'locator': locator,
        'activation': 'semantic',
      },
      CockpitTestActionKind.longPress => <String, Object?>{
        'locator': locator,
        'durationMs': 500,
      },
      CockpitTestActionKind.doubleTap ||
      CockpitTestActionKind.focusTextInput ||
      CockpitTestActionKind.increase ||
      CockpitTestActionKind.decrease ||
      CockpitTestActionKind.dismiss => <String, Object?>{'locator': locator},
      CockpitTestActionKind.enterText => <String, Object?>{
        'locator': locator,
        'text': 'value',
      },
      CockpitTestActionKind.eraseText => <String, Object?>{
        'locator': locator,
        'characters': 4,
      },
      CockpitTestActionKind.copyText => <String, Object?>{'locator': locator},
      CockpitTestActionKind.pasteText => <String, Object?>{'locator': locator},
      CockpitTestActionKind.setTextEditingValue => <String, Object?>{
        'locator': locator,
        'text': 'edited',
        'selectionStart': 0,
        'selectionEnd': 6,
      },
      CockpitTestActionKind.sendTextInputAction => <String, Object?>{
        'inputAction': 'done',
      },
      CockpitTestActionKind.sendKeyEvent ||
      CockpitTestActionKind.sendKeyDownEvent ||
      CockpitTestActionKind.sendKeyUpEvent => <String, Object?>{
        'keyRequest': <String, Object?>{'logicalKey': 'Enter'},
      },
      CockpitTestActionKind.drag => <String, Object?>{
        'locator': locator,
        'dx': 0,
        'dy': 120,
        'durationMs': 300,
      },
      CockpitTestActionKind.fling => <String, Object?>{
        'locator': locator,
        'dx': 0,
        'dy': -200,
        'velocity': 1200,
      },
      CockpitTestActionKind.swipe => <String, Object?>{
        'locator': locator,
        'direction': 'up',
        'distance': 0.5,
        'durationMs': 250,
      },
      CockpitTestActionKind.pinchZoom => <String, Object?>{
        'locator': locator,
        'scale': 2,
      },
      CockpitTestActionKind.rotate => <String, Object?>{
        'locator': locator,
        'rotationRadians': 0.5,
      },
      CockpitTestActionKind.panZoom => <String, Object?>{
        'locator': locator,
        'panDx': 20,
        'panDy': -10,
        'scale': 1.2,
      },
      CockpitTestActionKind.multiTouch => <String, Object?>{
        'locator': locator,
        'sequence': <String, Object?>{
          'steps': <Object?>[
            <String, Object?>{
              'pointer': 0,
              'phase': 'down',
              'atMs': 0,
              'dx': 0,
              'dy': 0,
            },
            <String, Object?>{
              'pointer': 0,
              'phase': 'up',
              'atMs': 100,
              'dx': 10,
              'dy': 10,
            },
          ],
        },
      },
      CockpitTestActionKind.scrollUntilVisible => <String, Object?>{
        'locator': locator,
        'direction': 'down',
        'maxScrolls': 10,
        'durationMs': 200,
        'revealAlignment': 'nearest',
      },
      CockpitTestActionKind.back ||
      CockpitTestActionKind.dismissKeyboard ||
      CockpitTestActionKind.clearNetworkActivity => const <String, Object?>{},
      CockpitTestActionKind.showOnScreen => <String, Object?>{
        'locator': locator,
        'revealAlignment': 'center',
      },
      CockpitTestActionKind.waitForNetworkIdle ||
      CockpitTestActionKind.waitForUiIdle => <String, Object?>{'quietMs': 400},
      CockpitTestActionKind.waitFor => <String, Object?>{
        'condition': <String, Object?>{
          'type': 'visible',
          'locator': locator,
          'expected': true,
        },
      },
      CockpitTestActionKind.assertVisible => <String, Object?>{
        'locator': locator,
        'expected': true,
      },
      CockpitTestActionKind.assertText => <String, Object?>{
        'locator': locator,
        'text': 'Ready',
        'matchMode': 'exact',
      },
      CockpitTestActionKind.assertScreenshot => <String, Object?>{
        'locator': locator,
        'baseline': 'baselines/home.png',
        'pixelTolerance': 0.1,
        'maxDifferingPixelRatio': 0.01,
        'artifactName': 'home',
        'captureOptions': <String, Object?>{
          'profile': 'flutterPreferred',
          'allowFallback': false,
        },
      },
      CockpitTestActionKind.travel => <String, Object?>{
        'route': <Object?>[
          <String, Object?>{'latitude': 31.2304, 'longitude': 121.4737},
          <String, Object?>{'latitude': 31.231, 'longitude': 121.474},
        ],
        'intervalMs': 100,
      },
      CockpitTestActionKind.system => <String, Object?>{
        'name': 'activateWindow',
        'parameters': const <String, Object?>{},
      },
      CockpitTestActionKind.captureScreenshot => <String, Object?>{
        'artifactName': 'acceptanceScreenshot',
        'captureOptions': <String, Object?>{
          'reason': 'assertion_failure',
          'includeSnapshot': true,
          'attachToStep': false,
          'profile': 'diagnostic',
          'allowFallback': false,
          'snapshotOptions': <String, Object?>{'profile': 'live'},
        },
      },
      CockpitTestActionKind.collectSnapshot => <String, Object?>{
        'snapshotOptions': <String, Object?>{
          'profile': 'live',
          'maxTargets': 20,
        },
      },
    },
  };
}
