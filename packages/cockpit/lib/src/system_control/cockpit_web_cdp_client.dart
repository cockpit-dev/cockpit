import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'cockpit_system_control_profile.dart';

const String cockpitWebCdpCommandExecutable = '__cockpit_web_cdp__';

typedef CockpitWebCdpProbe =
    Future<CockpitWebCdpProbeResult> Function({
      required String cdpUrl,
      required Duration timeout,
    });

typedef CockpitWebCdpActionRunner =
    Future<CockpitWebCdpActionResult> Function({
      required String webSocketUrl,
      required CockpitSystemControlAction action,
      required Map<String, Object?> parameters,
      required Duration timeout,
    });

final class CockpitWebCdpProbeResult {
  const CockpitWebCdpProbeResult({
    required this.available,
    this.webSocketUrl,
    this.pageId,
    this.pageUrl,
    this.failureReason,
  });

  const CockpitWebCdpProbeResult.blocked(String failureReason)
    : this(available: false, failureReason: failureReason);

  final bool available;
  final String? webSocketUrl;
  final String? pageId;
  final String? pageUrl;
  final String? failureReason;
}

final class CockpitWebCdpActionResult {
  const CockpitWebCdpActionResult({this.stdout, this.changed});

  final String? stdout;
  final bool? changed;
}

final class CockpitWebCdpException implements Exception {
  const CockpitWebCdpException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

Future<CockpitWebCdpProbeResult> cockpitProbeWebCdp({
  required String cdpUrl,
  required Duration timeout,
}) async {
  final endpoint = Uri.tryParse(cdpUrl.trim());
  if (endpoint == null || !endpoint.hasScheme) {
    return const CockpitWebCdpProbeResult.blocked('cdpUrlInvalid');
  }
  try {
    final resolved = await _resolveWebSocketEndpoint(
      endpoint: endpoint,
      timeout: timeout,
    );
    final connection = await WipConnection.connect(
      resolved.webSocketUrl,
    ).timeout(timeout);
    try {
      await connection.runtime
          .evaluate('document.readyState', returnByValue: true)
          .timeout(timeout);
    } finally {
      await connection.close();
    }
    return CockpitWebCdpProbeResult(
      available: true,
      webSocketUrl: resolved.webSocketUrl,
      pageId: resolved.pageId,
      pageUrl: resolved.pageUrl,
    );
  } on TimeoutException {
    return const CockpitWebCdpProbeResult.blocked('cdpProbeTimedOut');
  } on CockpitWebCdpException catch (error) {
    return CockpitWebCdpProbeResult.blocked(error.code);
  } on Object {
    return const CockpitWebCdpProbeResult.blocked('cdpEndpointUnreachable');
  }
}

Future<CockpitWebCdpActionResult> cockpitRunWebCdpAction({
  required String webSocketUrl,
  required CockpitSystemControlAction action,
  required Map<String, Object?> parameters,
  required Duration timeout,
}) async {
  final connection = await WipConnection.connect(webSocketUrl).timeout(timeout);
  try {
    return await _CockpitWebCdpSession(
      connection,
    ).run(action, parameters).timeout(timeout);
  } on CockpitWebCdpException {
    rethrow;
  } on WipError catch (error) {
    throw CockpitWebCdpException(
      'cdpCommandFailed',
      error.message ?? 'Chromium rejected the CDP command.',
    );
  } finally {
    await connection.close();
  }
}

Future<_CockpitWebCdpEndpoint> _resolveWebSocketEndpoint({
  required Uri endpoint,
  required Duration timeout,
}) async {
  if (endpoint.scheme == 'ws' || endpoint.scheme == 'wss') {
    return _CockpitWebCdpEndpoint(webSocketUrl: endpoint.toString());
  }
  if (endpoint.scheme != 'http' && endpoint.scheme != 'https') {
    throw const CockpitWebCdpException(
      'cdpUrlInvalid',
      'CDP endpoint must use http, https, ws, or wss.',
    );
  }
  final client = HttpClient();
  try {
    final listUri = endpoint.resolve('/json/list');
    final request = await client.getUrl(listUri).timeout(timeout);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw CockpitWebCdpException(
        'cdpEndpointRejected',
        'CDP target list returned HTTP ${response.statusCode}.',
      );
    }
    final decoded = jsonDecode(
      await utf8.decodeStream(response).timeout(timeout),
    );
    if (decoded is! List<Object?>) {
      throw const CockpitWebCdpException(
        'cdpTargetListInvalid',
        'CDP target list is not an array.',
      );
    }
    final targets = decoded
        .whereType<Map<Object?, Object?>>()
        .map((value) => Map<String, Object?>.from(value))
        .where((value) => value['type'] == 'page')
        .toList(growable: false);
    if (targets.isEmpty) {
      throw const CockpitWebCdpException(
        'cdpPageNotFound',
        'The registered Chromium page was not found at the CDP endpoint.',
      );
    }
    if (targets.length != 1) {
      throw const CockpitWebCdpException(
        'cdpPageAmbiguous',
        'The CDP endpoint contains multiple pages; register the exact page WebSocket URL.',
      );
    }
    final match = targets.single;
    final webSocketUrl = match['webSocketDebuggerUrl'];
    if (webSocketUrl is! String || webSocketUrl.trim().isEmpty) {
      throw const CockpitWebCdpException(
        'cdpWebSocketMissing',
        'The selected Chromium page does not expose a debugger WebSocket.',
      );
    }
    return _CockpitWebCdpEndpoint(
      webSocketUrl: webSocketUrl.trim(),
      pageId: match['id'] as String?,
      pageUrl: match['url'] as String?,
    );
  } finally {
    client.close(force: true);
  }
}

final class _CockpitWebCdpEndpoint {
  const _CockpitWebCdpEndpoint({
    required this.webSocketUrl,
    this.pageId,
    this.pageUrl,
  });

  final String webSocketUrl;
  final String? pageId;
  final String? pageUrl;
}

final class _CockpitWebCdpSession {
  const _CockpitWebCdpSession(this.connection);

  final WipConnection connection;

  Future<CockpitWebCdpActionResult> run(
    CockpitSystemControlAction action,
    Map<String, Object?> parameters,
  ) => switch (action) {
    CockpitSystemControlAction.readUiTree => _readUiTree(parameters),
    CockpitSystemControlAction.tap => _tap(parameters),
    CockpitSystemControlAction.longPress => _longPress(parameters),
    CockpitSystemControlAction.drag => _drag(parameters),
    CockpitSystemControlAction.typeText => _typeText(parameters),
    CockpitSystemControlAction.pressKey => _pressKey(parameters),
    CockpitSystemControlAction.pressBack => _pressBack(),
    CockpitSystemControlAction.activateWindow => _activateWindow(),
    CockpitSystemControlAction.terminateApp => _terminatePage(),
    CockpitSystemControlAction.dismissSystemDialog => _dismissDialog(),
    CockpitSystemControlAction.dismissKeyboard => _dismissKeyboard(),
    CockpitSystemControlAction.openUrl => _openUrl(parameters),
    CockpitSystemControlAction.readWindows => _readWindows(),
    CockpitSystemControlAction.readSystemState => _readSystemState(),
    _ => throw CockpitWebCdpException(
      'unsupportedWebCdpAction',
      '${action.name} is not implemented by the Chromium DOM driver.',
    ),
  };

  Future<CockpitWebCdpActionResult> _readUiTree(
    Map<String, Object?> parameters,
  ) async {
    final maxDepth = _integer(parameters, 'maxDepth', fallback: 16);
    final maxNodes = _integer(parameters, 'maxNodes', fallback: 2000);
    if (maxDepth < 1 || maxDepth > 64 || maxNodes < 1 || maxNodes > 10000) {
      throw const CockpitWebCdpException(
        'invalidWebDomTreeLimits',
        'Web DOM tree limits are outside the supported range.',
      );
    }
    final value = await _evaluate('''
(() => {
  const maxDepth = $maxDepth;
  const maxNodes = $maxNodes;
  let count = 0;
  let truncated = false;
  const compact = value => {
    if (value == null) return null;
    const text = String(value).replace(/\\s+/g, ' ').trim();
    return text ? text.slice(0, 512) : null;
  };
  const directText = element => compact(Array.from(element.childNodes)
    .filter(node => node.nodeType === 3)
    .map(node => node.textContent || '')
    .join(' '));
  const labelledText = element => {
    const ids = (element.getAttribute('aria-labelledby') || '')
      .split(/\\s+/).filter(Boolean);
    if (!ids.length) return null;
    return compact(ids.map(id => element.ownerDocument?.getElementById(id)?.textContent || '')
      .join(' '));
  };
  const roleOf = element => {
    const explicit = compact(element.getAttribute('role'));
    if (explicit) return explicit;
    const tag = element.tagName.toLowerCase();
    if (tag === 'button') return 'button';
    if (tag === 'a' && element.hasAttribute('href')) return 'link';
    if (tag === 'textarea') return 'textbox';
    if (tag === 'select') return 'combobox';
    if (tag === 'option') return 'option';
    if (tag === 'img') return 'img';
    if (tag === 'summary') return 'button';
    if (tag === 'input') {
      const type = (element.getAttribute('type') || 'text').toLowerCase();
      if (type === 'checkbox') return 'checkbox';
      if (type === 'radio') return 'radio';
      if (type === 'range') return 'slider';
      if (type === 'button' || type === 'submit' || type === 'reset') return 'button';
      return 'textbox';
    }
    return tag;
  };
  const childrenOf = (element, offsetX, offsetY, scaleX, scaleY) => {
    const children = Array.from(element.children || []).map(child =>
      ({element: child, offsetX, offsetY, scaleX, scaleY}));
    if (element.shadowRoot) {
      children.push(...Array.from(element.shadowRoot.children).map(child =>
        ({element: child, offsetX, offsetY, scaleX, scaleY})));
    }
    if (element.tagName === 'IFRAME') {
      try {
        const root = element.contentDocument?.documentElement;
        if (root) {
          const rect = element.getBoundingClientRect();
          const iframeScaleX = element.offsetWidth > 0 ? rect.width / element.offsetWidth : 1;
          const iframeScaleY = element.offsetHeight > 0 ? rect.height / element.offsetHeight : 1;
          const childScaleX = scaleX * iframeScaleX;
          const childScaleY = scaleY * iframeScaleY;
          children.push({
            element: root,
            offsetX: offsetX + rect.left * scaleX + element.clientLeft * childScaleX,
            offsetY: offsetY + rect.top * scaleY + element.clientTop * childScaleY,
            scaleX: childScaleX,
            scaleY: childScaleY,
          });
        }
      } catch (_) {}
    }
    return children;
  };
  const visit = (element, depth, forceRoot = false,
                 offsetX = 0, offsetY = 0, scaleX = 1, scaleY = 1) => {
    if (!element || element.nodeType !== 1 || typeof element.tagName !== 'string' ||
        count >= maxNodes || depth > maxDepth) {
      if (count >= maxNodes || depth > maxDepth) truncated = true;
      return null;
    }
    const tag = element.tagName.toLowerCase();
    if (['script', 'style', 'template', 'meta', 'link', 'noscript'].includes(tag)) return null;
    const style = (element.ownerDocument?.defaultView || window).getComputedStyle(element);
    if (style.display === 'none' || style.visibility === 'hidden' ||
        element.hidden || element.getAttribute('aria-hidden') === 'true') return null;
    count += 1;
    const childNodes = [];
    for (const child of childrenOf(element, offsetX, offsetY, scaleX, scaleY)) {
      const node = visit(child.element, depth + 1, false,
        child.offsetX, child.offsetY, child.scaleX, child.scaleY);
      if (node) childNodes.push(node);
      if (count >= maxNodes) break;
    }
    const localRect = forceRoot
      ? {left: 0, top: 0, width: window.innerWidth, height: window.innerHeight,
         right: window.innerWidth, bottom: window.innerHeight}
      : element.getBoundingClientRect();
    const rect = forceRoot ? localRect : {
      left: offsetX + localRect.left * scaleX,
      top: offsetY + localRect.top * scaleY,
      width: localRect.width * scaleX,
      height: localRect.height * scaleY,
      right: offsetX + localRect.right * scaleX,
      bottom: offsetY + localRect.bottom * scaleY,
    };
    const intersects = rect.width > 0 && rect.height > 0 && rect.right > 0 &&
      rect.bottom > 0 && rect.left < window.innerWidth && rect.top < window.innerHeight;
    if (!forceRoot && !intersects && childNodes.length === 0) return null;
    const inputType = tag === 'input'
      ? (element.getAttribute('type') || 'text').toLowerCase()
      : null;
    const password = inputType === 'password';
    const editable = !element.disabled &&
      (element.isContentEditable || tag === 'textarea' ||
       (tag === 'input' && !['button','submit','reset','checkbox','radio','range','file','hidden'].includes(inputType)));
    const clickable = !element.disabled &&
      (['button','summary','option'].includes(tag) ||
       (tag === 'a' && element.hasAttribute('href')) ||
       (tag === 'input' && !['text','email','password','search','tel','url','number','date','time','datetime-local','month','week','color','file','hidden'].includes(inputType)) ||
       element.hasAttribute('onclick') || element.getAttribute('role') === 'button');
    const focusable = !element.disabled &&
      (element.tabIndex >= 0 || editable || clickable || ['select','a'].includes(tag));
    const scrollable = (/(auto|scroll)/.test(style.overflowY) && element.scrollHeight > element.clientHeight) ||
      (/(auto|scroll)/.test(style.overflowX) && element.scrollWidth > element.clientWidth);
    const name = compact(element.getAttribute('aria-label')) || labelledText(element) ||
      compact(element.getAttribute('alt')) || compact(element.getAttribute('title')) ||
      compact(element.getAttribute('placeholder'));
    const text = password ? null :
      (tag === 'input' || tag === 'textarea' || tag === 'select'
        ? compact(element.value)
        : directText(element));
    const node = {
      role: roleOf(element),
      type: tag,
      frame: {x: rect.left, y: rect.top, width: rect.width, height: rect.height},
      visible: forceRoot || intersects,
      enabled: !element.disabled && !element.hasAttribute('inert'),
      focusable,
      focused: element.ownerDocument?.activeElement === element,
      clickable,
      editable,
      scrollable,
      password,
      children: childNodes,
    };
    if (name) node.name = name;
    if (text) node.text = text;
    const id = compact(element.id) || compact(element.getAttribute('data-cockpit-id'));
    if (id) node.id = id;
    const testid = compact(element.getAttribute('data-testid')) ||
      compact(element.getAttribute('data-test')) || compact(element.getAttribute('data-cy'));
    if (testid) node.testid = testid;
    const className = compact(typeof element.className === 'string' ? element.className : null);
    if (className) node.className = className;
    for (const state of ['checked', 'selected', 'expanded', 'pressed']) {
      const aria = element.getAttribute('aria-' + state);
      if (aria === 'true' || aria === 'false') node[state] = aria === 'true';
    }
    if ('checked' in element) node.checked = Boolean(element.checked);
    if ('selected' in element) node.selected = Boolean(element.selected);
    return node;
  };
  const tree = visit(document.documentElement, 0, true);
  return {tree, nodeCount: count, truncated, url: location.href};
})()
''');
    if (value is! Map<Object?, Object?> || value['tree'] == null) {
      throw const CockpitWebCdpException(
        'webDomTreeInvalid',
        'Chromium returned an invalid DOM tree.',
      );
    }
    return CockpitWebCdpActionResult(stdout: jsonEncode(value));
  }

  Future<CockpitWebCdpActionResult> _tap(
    Map<String, Object?> parameters,
  ) async {
    final x = _number(parameters, 'x');
    final y = _number(parameters, 'y');
    await _mouse('mouseMoved', x: x, y: y);
    await _mouse('mousePressed', x: x, y: y, button: 'left', buttons: 1);
    await _mouse('mouseReleased', x: x, y: y, button: 'left');
    return const CockpitWebCdpActionResult(changed: true);
  }

  Future<CockpitWebCdpActionResult> _longPress(
    Map<String, Object?> parameters,
  ) async {
    final x = _number(parameters, 'x');
    final y = _number(parameters, 'y');
    final duration = _integer(parameters, 'durationMs', fallback: 800);
    await _mouse('mouseMoved', x: x, y: y);
    await _mouse('mousePressed', x: x, y: y, button: 'left', buttons: 1);
    await Future<void>.delayed(Duration(milliseconds: duration));
    await _mouse('mouseReleased', x: x, y: y, button: 'left');
    return const CockpitWebCdpActionResult(changed: true);
  }

  Future<CockpitWebCdpActionResult> _drag(
    Map<String, Object?> parameters,
  ) async {
    final startX = _number(parameters, 'startX');
    final startY = _number(parameters, 'startY');
    final endX = _number(parameters, 'endX');
    final endY = _number(parameters, 'endY');
    final duration = _integer(parameters, 'durationMs', fallback: 300);
    if (parameters['gesture'] == 'scroll') {
      await connection
          .sendCommand('Input.dispatchMouseEvent', <String, dynamic>{
            'type': 'mouseWheel',
            'x': startX,
            'y': startY,
            'deltaX': startX - endX,
            'deltaY': startY - endY,
          });
      return const CockpitWebCdpActionResult(changed: true);
    }
    const steps = 8;
    await _mouse('mouseMoved', x: startX, y: startY);
    await _mouse(
      'mousePressed',
      x: startX,
      y: startY,
      button: 'left',
      buttons: 1,
    );
    for (var step = 1; step <= steps; step += 1) {
      final progress = step / steps;
      await _mouse(
        'mouseMoved',
        x: startX + (endX - startX) * progress,
        y: startY + (endY - startY) * progress,
        button: 'left',
        buttons: 1,
      );
      if (duration > 0) {
        await Future<void>.delayed(
          Duration(milliseconds: (duration / steps).round()),
        );
      }
    }
    await _mouse('mouseReleased', x: endX, y: endY, button: 'left');
    return const CockpitWebCdpActionResult(changed: true);
  }

  Future<CockpitWebCdpActionResult> _typeText(
    Map<String, Object?> parameters,
  ) async {
    final text = parameters['text'];
    if (text is! String) {
      throw const CockpitWebCdpException(
        'invalidWebText',
        'Web text input requires a string.',
      );
    }
    await connection.sendCommand('Input.insertText', <String, dynamic>{
      'text': text,
    });
    return const CockpitWebCdpActionResult(changed: true);
  }

  Future<CockpitWebCdpActionResult> _pressKey(
    Map<String, Object?> parameters,
  ) async {
    final key = parameters['key'];
    if (key is! String || key.trim().isEmpty) {
      throw const CockpitWebCdpException(
        'invalidWebKey',
        'Web key input requires a key name.',
      );
    }
    final repeat = _integer(parameters, 'repeat', fallback: 1);
    final descriptor = _keyDescriptor(key.trim());
    for (var index = 0; index < repeat; index += 1) {
      await connection.sendCommand('Input.dispatchKeyEvent', <String, dynamic>{
        'type': 'rawKeyDown',
        ...descriptor,
      });
      if (descriptor['text'] case final String text when text.isNotEmpty) {
        await connection.sendCommand(
          'Input.dispatchKeyEvent',
          <String, dynamic>{'type': 'char', ...descriptor},
        );
      }
      await connection.sendCommand('Input.dispatchKeyEvent', <String, dynamic>{
        'type': 'keyUp',
        ...descriptor,
      });
    }
    return const CockpitWebCdpActionResult(changed: true);
  }

  Future<CockpitWebCdpActionResult> _pressBack() async {
    final response = await connection.sendCommand('Page.getNavigationHistory');
    final result = response.result ?? const <String, dynamic>{};
    final currentIndex = result['currentIndex'];
    final entries = result['entries'];
    if (currentIndex is! int ||
        entries is! List<Object?> ||
        currentIndex <= 0) {
      return const CockpitWebCdpActionResult(changed: false);
    }
    final previous = entries[currentIndex - 1];
    if (previous is! Map<Object?, Object?> || previous['id'] is! int) {
      throw const CockpitWebCdpException(
        'webNavigationHistoryInvalid',
        'Chromium returned invalid page navigation history.',
      );
    }
    await connection.sendCommand(
      'Page.navigateToHistoryEntry',
      <String, dynamic>{'entryId': previous['id']},
    );
    return const CockpitWebCdpActionResult(changed: true);
  }

  Future<CockpitWebCdpActionResult> _activateWindow() async {
    await connection.sendCommand('Page.bringToFront');
    return const CockpitWebCdpActionResult(changed: true);
  }

  Future<CockpitWebCdpActionResult> _terminatePage() async {
    await connection.sendCommand('Page.close');
    return const CockpitWebCdpActionResult(changed: true);
  }

  Future<CockpitWebCdpActionResult> _dismissDialog() async {
    try {
      await connection.sendCommand(
        'Page.handleJavaScriptDialog',
        <String, dynamic>{'accept': false},
      );
      return const CockpitWebCdpActionResult(changed: true);
    } on WipError catch (error) {
      if ((error.message ?? '').toLowerCase().contains('no dialog')) {
        return const CockpitWebCdpActionResult(changed: false);
      }
      rethrow;
    }
  }

  Future<CockpitWebCdpActionResult> _dismissKeyboard() async {
    final value = await _evaluate('''
(() => {
  const active = document.activeElement;
  if (!active || active === document.body || active === document.documentElement) return false;
  if (typeof active.blur === 'function') active.blur();
  return true;
})()
''');
    return CockpitWebCdpActionResult(changed: value == true);
  }

  Future<CockpitWebCdpActionResult> _openUrl(
    Map<String, Object?> parameters,
  ) async {
    final url = parameters['url'];
    if (url is! String || Uri.tryParse(url)?.hasScheme != true) {
      throw const CockpitWebCdpException(
        'invalidWebUrl',
        'Web navigation requires an absolute URL.',
      );
    }
    final response = await connection.page.navigate(url);
    final errorText = response.result?['errorText'];
    if (errorText is String && errorText.isNotEmpty) {
      throw CockpitWebCdpException('webNavigationFailed', errorText);
    }
    return const CockpitWebCdpActionResult(changed: true);
  }

  Future<CockpitWebCdpActionResult> _readWindows() async {
    final response = await connection.sendCommand('Target.getTargets');
    final values = response.result?['targetInfos'];
    final pages = values is List<Object?>
        ? values
              .whereType<Map<Object?, Object?>>()
              .where((value) => value['type'] == 'page')
              .map(
                (value) => <String, Object?>{
                  'id': value['targetId'],
                  'title': value['title'],
                  'url': value['url'],
                  'attached': value['attached'],
                },
              )
              .toList(growable: false)
        : const <Map<String, Object?>>[];
    return CockpitWebCdpActionResult(
      stdout: jsonEncode(<String, Object?>{'windows': pages}),
    );
  }

  Future<CockpitWebCdpActionResult> _readSystemState() async {
    final value = await _evaluate('''
(() => ({
  url: location.href,
  title: document.title,
  ready: document.readyState,
  focused: document.hasFocus(),
  visibility: document.visibilityState,
  viewport: {width: window.innerWidth, height: window.innerHeight,
             pixelRatio: window.devicePixelRatio},
  scroll: {x: window.scrollX, y: window.scrollY}
}))()
''');
    return CockpitWebCdpActionResult(stdout: jsonEncode(value));
  }

  Future<Object?> _evaluate(String expression) async {
    final result = await connection.runtime.evaluate(
      expression,
      returnByValue: true,
      awaitPromise: true,
    );
    return result.value;
  }

  Future<void> _mouse(
    String type, {
    required num x,
    required num y,
    String button = 'none',
    int buttons = 0,
  }) => connection.sendCommand('Input.dispatchMouseEvent', <String, dynamic>{
    'type': type,
    'x': x,
    'y': y,
    'button': button,
    'buttons': buttons,
    'clickCount': type == 'mousePressed' || type == 'mouseReleased' ? 1 : 0,
  });
}

int _integer(Map<String, Object?> values, String key, {required int fallback}) {
  final value = values[key];
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  throw CockpitWebCdpException(
    'invalidWebCdpParameter',
    '$key must be an integer.',
  );
}

num _number(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value is num && value.isFinite) return value;
  throw CockpitWebCdpException(
    'invalidWebCdpParameter',
    '$key must be a finite number.',
  );
}

Map<String, dynamic> _keyDescriptor(String value) {
  final normalized = value.toLowerCase();
  return switch (normalized) {
    'enter' || 'return' => <String, dynamic>{
      'key': 'Enter',
      'code': 'Enter',
      'text': '\r',
      'windowsVirtualKeyCode': 13,
      'nativeVirtualKeyCode': 13,
    },
    'tab' => <String, dynamic>{
      'key': 'Tab',
      'code': 'Tab',
      'text': '\t',
      'windowsVirtualKeyCode': 9,
      'nativeVirtualKeyCode': 9,
    },
    'escape' || 'esc' => <String, dynamic>{
      'key': 'Escape',
      'code': 'Escape',
      'windowsVirtualKeyCode': 27,
      'nativeVirtualKeyCode': 27,
    },
    'backspace' => <String, dynamic>{
      'key': 'Backspace',
      'code': 'Backspace',
      'windowsVirtualKeyCode': 8,
      'nativeVirtualKeyCode': 8,
    },
    'delete' => <String, dynamic>{
      'key': 'Delete',
      'code': 'Delete',
      'windowsVirtualKeyCode': 46,
      'nativeVirtualKeyCode': 46,
    },
    'arrowup' || 'up' => <String, dynamic>{
      'key': 'ArrowUp',
      'code': 'ArrowUp',
      'windowsVirtualKeyCode': 38,
      'nativeVirtualKeyCode': 38,
    },
    'arrowdown' || 'down' => <String, dynamic>{
      'key': 'ArrowDown',
      'code': 'ArrowDown',
      'windowsVirtualKeyCode': 40,
      'nativeVirtualKeyCode': 40,
    },
    'arrowleft' || 'left' => <String, dynamic>{
      'key': 'ArrowLeft',
      'code': 'ArrowLeft',
      'windowsVirtualKeyCode': 37,
      'nativeVirtualKeyCode': 37,
    },
    'arrowright' || 'right' => <String, dynamic>{
      'key': 'ArrowRight',
      'code': 'ArrowRight',
      'windowsVirtualKeyCode': 39,
      'nativeVirtualKeyCode': 39,
    },
    'space' || ' ' => <String, dynamic>{
      'key': ' ',
      'code': 'Space',
      'text': ' ',
      'windowsVirtualKeyCode': 32,
      'nativeVirtualKeyCode': 32,
    },
    _ when value.runes.length == 1 => <String, dynamic>{
      'key': value,
      'code': 'Key${value.toUpperCase()}',
      'text': value,
    },
    _ => throw CockpitWebCdpException(
      'unsupportedWebKey',
      'Chromium key "$value" is not supported.',
    ),
  };
}
