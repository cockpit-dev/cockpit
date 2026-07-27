import 'cockpit_test_value.dart';

enum CockpitTestActionKind {
  tap,
  longPress,
  doubleTap,
  enterText,
  eraseText,
  copyText,
  pasteText,
  focusTextInput,
  setTextEditingValue,
  sendTextInputAction,
  sendKeyEvent,
  sendKeyDownEvent,
  sendKeyUpEvent,
  drag,
  fling,
  swipe,
  pinchZoom,
  rotate,
  panZoom,
  multiTouch,
  scrollUntilVisible,
  back,
  showOnScreen,
  increase,
  decrease,
  dismiss,
  dismissKeyboard,
  clearNetworkActivity,
  waitForNetworkIdle,
  waitForUiIdle,
  waitFor,
  assertVisible,
  assertText,
  assertScreenshot,
  travel,
  system,
  captureScreenshot,
  collectSnapshot,
}

enum CockpitTestActionField {
  activation('activation', CockpitTestValueType.string),
  durationMs('durationMs', CockpitTestValueType.integer),
  characters('characters', CockpitTestValueType.integer),
  intervalMs('intervalMs', CockpitTestValueType.integer),
  text('text', CockpitTestValueType.string),
  selectionStart('selectionStart', CockpitTestValueType.integer),
  selectionEnd('selectionEnd', CockpitTestValueType.integer),
  composingStart('composingStart', CockpitTestValueType.integer),
  composingEnd('composingEnd', CockpitTestValueType.integer),
  inputAction('inputAction', CockpitTestValueType.string),
  keyRequest('keyRequest', CockpitTestValueType.json),
  dx('dx', CockpitTestValueType.number),
  dy('dy', CockpitTestValueType.number),
  velocity('velocity', CockpitTestValueType.number),
  direction('direction', CockpitTestValueType.string),
  distance('distance', CockpitTestValueType.number),
  scale('scale', CockpitTestValueType.number),
  rotationRadians('rotationRadians', CockpitTestValueType.number),
  panDx('panDx', CockpitTestValueType.number),
  panDy('panDy', CockpitTestValueType.number),
  sequence('sequence', CockpitTestValueType.json),
  maxScrolls('maxScrolls', CockpitTestValueType.integer),
  revealAlignment('revealAlignment', CockpitTestValueType.string),
  quietMs('quietMs', CockpitTestValueType.integer),
  expected('expected', CockpitTestValueType.boolean),
  matchMode('matchMode', CockpitTestValueType.string),
  baseline('baseline', CockpitTestValueType.string),
  similarity('similarity', CockpitTestValueType.number),
  route('route', CockpitTestValueType.json),
  artifactName('artifactName', CockpitTestValueType.string),
  captureOptions('captureOptions', CockpitTestValueType.json),
  systemName('name', CockpitTestValueType.string),
  systemParameters('parameters', CockpitTestValueType.json),
  snapshotOptions('snapshotOptions', CockpitTestValueType.json);

  const CockpitTestActionField(this.wireName, this.valueType);

  final String wireName;
  final CockpitTestValueType valueType;
}

enum CockpitTestLocatorRequirement { forbidden, optional, required }

enum CockpitTestSettlement { none, uiIdle, polling }

final class CockpitTestActionSpec {
  const CockpitTestActionSpec({
    required this.locator,
    required this.allowedFields,
    this.requiredFields = const <CockpitTestActionField>{},
    this.secretFields = const <CockpitTestActionField>{},
    required this.settlement,
    this.conditionRequired = false,
  });

  final CockpitTestLocatorRequirement locator;
  final Set<CockpitTestActionField> allowedFields;
  final Set<CockpitTestActionField> requiredFields;
  final Set<CockpitTestActionField> secretFields;
  final CockpitTestSettlement settlement;
  final bool conditionRequired;
}

const _none = <CockpitTestActionField>{};

const Map<CockpitTestActionKind, CockpitTestActionSpec>
cockpitTestActionSpecs = <CockpitTestActionKind, CockpitTestActionSpec>{
  CockpitTestActionKind.tap: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.required,
    allowedFields: <CockpitTestActionField>{CockpitTestActionField.activation},
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.longPress: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.required,
    allowedFields: <CockpitTestActionField>{CockpitTestActionField.durationMs},
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.doubleTap: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.required,
    allowedFields: _none,
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.enterText: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.optional,
    allowedFields: <CockpitTestActionField>{CockpitTestActionField.text},
    requiredFields: <CockpitTestActionField>{CockpitTestActionField.text},
    secretFields: <CockpitTestActionField>{CockpitTestActionField.text},
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.eraseText: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.optional,
    allowedFields: <CockpitTestActionField>{CockpitTestActionField.characters},
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.copyText: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.required,
    allowedFields: _none,
    settlement: CockpitTestSettlement.none,
  ),
  CockpitTestActionKind.pasteText: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.optional,
    allowedFields: _none,
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.focusTextInput: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.required,
    allowedFields: _none,
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.setTextEditingValue: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.optional,
    allowedFields: <CockpitTestActionField>{
      CockpitTestActionField.text,
      CockpitTestActionField.selectionStart,
      CockpitTestActionField.selectionEnd,
      CockpitTestActionField.composingStart,
      CockpitTestActionField.composingEnd,
    },
    secretFields: <CockpitTestActionField>{CockpitTestActionField.text},
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.sendTextInputAction: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.forbidden,
    allowedFields: <CockpitTestActionField>{CockpitTestActionField.inputAction},
    requiredFields: <CockpitTestActionField>{
      CockpitTestActionField.inputAction,
    },
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.sendKeyEvent: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.forbidden,
    allowedFields: <CockpitTestActionField>{CockpitTestActionField.keyRequest},
    requiredFields: <CockpitTestActionField>{CockpitTestActionField.keyRequest},
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.sendKeyDownEvent: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.forbidden,
    allowedFields: <CockpitTestActionField>{CockpitTestActionField.keyRequest},
    requiredFields: <CockpitTestActionField>{CockpitTestActionField.keyRequest},
    settlement: CockpitTestSettlement.none,
  ),
  CockpitTestActionKind.sendKeyUpEvent: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.forbidden,
    allowedFields: <CockpitTestActionField>{CockpitTestActionField.keyRequest},
    requiredFields: <CockpitTestActionField>{CockpitTestActionField.keyRequest},
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.drag: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.optional,
    allowedFields: <CockpitTestActionField>{
      CockpitTestActionField.dx,
      CockpitTestActionField.dy,
      CockpitTestActionField.durationMs,
    },
    requiredFields: <CockpitTestActionField>{
      CockpitTestActionField.dx,
      CockpitTestActionField.dy,
    },
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.fling: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.optional,
    allowedFields: <CockpitTestActionField>{
      CockpitTestActionField.dx,
      CockpitTestActionField.dy,
      CockpitTestActionField.velocity,
    },
    requiredFields: <CockpitTestActionField>{
      CockpitTestActionField.dx,
      CockpitTestActionField.dy,
      CockpitTestActionField.velocity,
    },
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.swipe: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.optional,
    allowedFields: <CockpitTestActionField>{
      CockpitTestActionField.direction,
      CockpitTestActionField.distance,
      CockpitTestActionField.durationMs,
    },
    requiredFields: <CockpitTestActionField>{
      CockpitTestActionField.direction,
      CockpitTestActionField.distance,
    },
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.pinchZoom: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.optional,
    allowedFields: <CockpitTestActionField>{CockpitTestActionField.scale},
    requiredFields: <CockpitTestActionField>{CockpitTestActionField.scale},
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.rotate: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.optional,
    allowedFields: <CockpitTestActionField>{
      CockpitTestActionField.rotationRadians,
    },
    requiredFields: <CockpitTestActionField>{
      CockpitTestActionField.rotationRadians,
    },
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.panZoom: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.optional,
    allowedFields: <CockpitTestActionField>{
      CockpitTestActionField.panDx,
      CockpitTestActionField.panDy,
      CockpitTestActionField.scale,
      CockpitTestActionField.rotationRadians,
    },
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.multiTouch: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.optional,
    allowedFields: <CockpitTestActionField>{CockpitTestActionField.sequence},
    requiredFields: <CockpitTestActionField>{CockpitTestActionField.sequence},
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.scrollUntilVisible: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.required,
    allowedFields: <CockpitTestActionField>{
      CockpitTestActionField.direction,
      CockpitTestActionField.maxScrolls,
      CockpitTestActionField.durationMs,
      CockpitTestActionField.revealAlignment,
    },
    requiredFields: <CockpitTestActionField>{CockpitTestActionField.direction},
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.back: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.forbidden,
    allowedFields: _none,
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.showOnScreen: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.required,
    allowedFields: <CockpitTestActionField>{
      CockpitTestActionField.revealAlignment,
    },
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.increase: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.required,
    allowedFields: _none,
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.decrease: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.required,
    allowedFields: _none,
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.dismiss: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.required,
    allowedFields: _none,
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.dismissKeyboard: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.forbidden,
    allowedFields: _none,
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.clearNetworkActivity: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.forbidden,
    allowedFields: _none,
    settlement: CockpitTestSettlement.none,
  ),
  CockpitTestActionKind.waitForNetworkIdle: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.forbidden,
    allowedFields: <CockpitTestActionField>{CockpitTestActionField.quietMs},
    settlement: CockpitTestSettlement.polling,
  ),
  CockpitTestActionKind.waitForUiIdle: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.forbidden,
    allowedFields: <CockpitTestActionField>{CockpitTestActionField.quietMs},
    settlement: CockpitTestSettlement.polling,
  ),
  CockpitTestActionKind.waitFor: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.forbidden,
    allowedFields: _none,
    settlement: CockpitTestSettlement.polling,
    conditionRequired: true,
  ),
  CockpitTestActionKind.assertVisible: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.required,
    allowedFields: <CockpitTestActionField>{CockpitTestActionField.expected},
    settlement: CockpitTestSettlement.none,
  ),
  CockpitTestActionKind.assertText: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.optional,
    allowedFields: <CockpitTestActionField>{
      CockpitTestActionField.text,
      CockpitTestActionField.matchMode,
    },
    requiredFields: <CockpitTestActionField>{CockpitTestActionField.text},
    settlement: CockpitTestSettlement.none,
  ),
  CockpitTestActionKind.assertScreenshot: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.forbidden,
    allowedFields: <CockpitTestActionField>{
      CockpitTestActionField.baseline,
      CockpitTestActionField.similarity,
      CockpitTestActionField.artifactName,
    },
    requiredFields: <CockpitTestActionField>{CockpitTestActionField.baseline},
    settlement: CockpitTestSettlement.none,
  ),
  CockpitTestActionKind.travel: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.forbidden,
    allowedFields: <CockpitTestActionField>{
      CockpitTestActionField.route,
      CockpitTestActionField.intervalMs,
    },
    requiredFields: <CockpitTestActionField>{CockpitTestActionField.route},
    settlement: CockpitTestSettlement.none,
  ),
  CockpitTestActionKind.system: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.forbidden,
    allowedFields: <CockpitTestActionField>{
      CockpitTestActionField.systemName,
      CockpitTestActionField.systemParameters,
    },
    requiredFields: <CockpitTestActionField>{CockpitTestActionField.systemName},
    settlement: CockpitTestSettlement.uiIdle,
  ),
  CockpitTestActionKind.captureScreenshot: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.forbidden,
    allowedFields: <CockpitTestActionField>{
      CockpitTestActionField.artifactName,
      CockpitTestActionField.captureOptions,
    },
    requiredFields: <CockpitTestActionField>{
      CockpitTestActionField.artifactName,
    },
    settlement: CockpitTestSettlement.none,
  ),
  CockpitTestActionKind.collectSnapshot: CockpitTestActionSpec(
    locator: CockpitTestLocatorRequirement.forbidden,
    allowedFields: <CockpitTestActionField>{
      CockpitTestActionField.snapshotOptions,
    },
    settlement: CockpitTestSettlement.none,
  ),
};

CockpitTestActionField? cockpitTestActionFieldFromWireName(String name) {
  for (final field in CockpitTestActionField.values) {
    if (field.wireName == name) {
      return field;
    }
  }
  return null;
}
