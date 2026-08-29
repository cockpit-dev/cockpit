import 'package:cockpit_protocol/cockpit_protocol.dart';

enum CockpitIntentAction {
  tap,
  hover,
  wheel,
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
  longPress,
  doubleTap,
  drag,
  fling,
  swipe,
  pinchZoom,
  rotate,
  panZoom,
  multiTouch,
  scrollUntilVisible,
  clearNetworkActivity,
  waitForNetworkIdle,
  waitForUiIdle,
  back,
  showOnScreen,
  increase,
  decrease,
  dismiss,
  dismissKeyboard,
  captureScreenshot,
  collectSnapshot,
  waitFor,
  assertVisible,
  assertText,
  runShell;

  static CockpitIntentAction fromCommandType(CockpitCommandType commandType) {
    return switch (commandType) {
      CockpitCommandType.tap => CockpitIntentAction.tap,
      CockpitCommandType.hover => CockpitIntentAction.hover,
      CockpitCommandType.wheel => CockpitIntentAction.wheel,
      CockpitCommandType.enterText => CockpitIntentAction.enterText,
      CockpitCommandType.eraseText => CockpitIntentAction.eraseText,
      CockpitCommandType.copyText => CockpitIntentAction.copyText,
      CockpitCommandType.pasteText => CockpitIntentAction.pasteText,
      CockpitCommandType.focusTextInput => CockpitIntentAction.focusTextInput,
      CockpitCommandType.setTextEditingValue =>
        CockpitIntentAction.setTextEditingValue,
      CockpitCommandType.sendTextInputAction =>
        CockpitIntentAction.sendTextInputAction,
      CockpitCommandType.sendKeyEvent => CockpitIntentAction.sendKeyEvent,
      CockpitCommandType.sendKeyDownEvent =>
        CockpitIntentAction.sendKeyDownEvent,
      CockpitCommandType.sendKeyUpEvent => CockpitIntentAction.sendKeyUpEvent,
      CockpitCommandType.longPress => CockpitIntentAction.longPress,
      CockpitCommandType.doubleTap => CockpitIntentAction.doubleTap,
      CockpitCommandType.drag => CockpitIntentAction.drag,
      CockpitCommandType.fling => CockpitIntentAction.fling,
      CockpitCommandType.swipe => CockpitIntentAction.swipe,
      CockpitCommandType.pinchZoom => CockpitIntentAction.pinchZoom,
      CockpitCommandType.rotate => CockpitIntentAction.rotate,
      CockpitCommandType.panZoom => CockpitIntentAction.panZoom,
      CockpitCommandType.multiTouch => CockpitIntentAction.multiTouch,
      CockpitCommandType.scrollUntilVisible =>
        CockpitIntentAction.scrollUntilVisible,
      CockpitCommandType.clearNetworkActivity =>
        CockpitIntentAction.clearNetworkActivity,
      CockpitCommandType.waitForNetworkIdle =>
        CockpitIntentAction.waitForNetworkIdle,
      CockpitCommandType.waitForUiIdle => CockpitIntentAction.waitForUiIdle,
      CockpitCommandType.back => CockpitIntentAction.back,
      CockpitCommandType.showOnScreen => CockpitIntentAction.showOnScreen,
      CockpitCommandType.increase => CockpitIntentAction.increase,
      CockpitCommandType.decrease => CockpitIntentAction.decrease,
      CockpitCommandType.dismiss => CockpitIntentAction.dismiss,
      CockpitCommandType.dismissKeyboard => CockpitIntentAction.dismissKeyboard,
      CockpitCommandType.captureScreenshot =>
        CockpitIntentAction.captureScreenshot,
      CockpitCommandType.collectSnapshot => CockpitIntentAction.collectSnapshot,
      CockpitCommandType.waitFor => CockpitIntentAction.waitFor,
      CockpitCommandType.assertVisible => CockpitIntentAction.assertVisible,
      CockpitCommandType.assertText => CockpitIntentAction.assertText,
      CockpitCommandType.assertScreenshot ||
      CockpitCommandType.travel ||
      CockpitCommandType.system => throw UnsupportedError(
        '${commandType.name} is executed by the system test backend.',
      ),
    };
  }
}
