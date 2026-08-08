import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';

import '../infrastructure/cockpit_process_manager.dart';

const String cockpitMacosAccessibilityCommandExecutable =
    '__cockpit_macos_accessibility__';
const String cockpitMacosSystemDialogCommandExecutable =
    '__cockpit_macos_system_dialog__';

typedef CockpitMacosAccessibilityTreeReader =
    Future<String> Function({
      required int processId,
      required int maxDepth,
      required int maxNodes,
      required Duration timeout,
    });

typedef CockpitMacosApplicationProcessIdResolver =
    Future<int> Function({required String appId, required Duration timeout});

typedef CockpitMacosSystemDialogHandler =
    Future<String> Function({
      required int processId,
      required String decision,
      required Duration timeout,
    });

final class CockpitMacosAccessibilityException implements Exception {
  const CockpitMacosAccessibilityException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() => message;
}

Future<int> cockpitResolveMacosApplicationProcessId({
  required String appId,
  required Duration timeout,
  CockpitProcessManager processManager = const LocalCockpitProcessManager(),
}) async {
  if (!Platform.isMacOS) {
    throw UnsupportedError('macOS process resolution requires macOS.');
  }
  final result = await processManager
      .run(
        'osascript',
        <String>[
          '-l',
          'JavaScript',
          '-e',
          _resolveApplicationProcessScript,
          appId,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      )
      .timeout(timeout);
  if (result.exitCode != 0) {
    throw CockpitMacosAccessibilityException(
      code: 'macosApplicationProcessNotFound',
      message: '${result.stderr}'.trim().isEmpty
          ? 'No running macOS application matches $appId.'
          : '${result.stderr}'.trim(),
    );
  }
  final processId = int.tryParse('${result.stdout}'.trim());
  if (processId == null || processId <= 0) {
    throw CockpitMacosAccessibilityException(
      code: 'macosApplicationProcessNotFound',
      message: 'macOS application $appId returned no valid process id.',
    );
  }
  return processId;
}

Future<String> cockpitReadMacosAccessibilityTree({
  required int processId,
  required int maxDepth,
  required int maxNodes,
  required Duration timeout,
}) async {
  if (!Platform.isMacOS) {
    throw UnsupportedError('macOS accessibility trees require macOS.');
  }
  if (processId <= 0 || maxDepth < 1 || maxNodes < 1) {
    throw const CockpitMacosAccessibilityException(
      code: 'invalidMacosAccessibilityRequest',
      message: 'A positive process id, maxDepth, and maxNodes are required.',
    );
  }
  if (timeout <= Duration.zero) {
    throw TimeoutException('macOS accessibility deadline elapsed.');
  }
  return Isolate.run(
    () => _MacosAccessibilityApi.instance.readTree(
      processId: processId,
      maxDepth: maxDepth,
      maxNodes: maxNodes,
      timeout: timeout,
    ),
    debugName: 'cockpit.macosAccessibilityTree',
  );
}

Future<String> cockpitDismissMacosSystemDialog({
  required int processId,
  required String decision,
  required Duration timeout,
}) async {
  if (!Platform.isMacOS) {
    throw UnsupportedError('macOS system dialogs require macOS.');
  }
  if (processId <= 0 || (decision != 'accept' && decision != 'dismiss')) {
    throw const CockpitMacosAccessibilityException(
      code: 'invalidMacosSystemDialogRequest',
      message:
          'A positive process id and accept or dismiss decision are required.',
    );
  }
  if (timeout <= Duration.zero) {
    throw TimeoutException('macOS system dialog deadline elapsed.');
  }
  return Isolate.run(
    () => _MacosAccessibilityApi.instance.dismissSystemDialog(
      processId: processId,
      decision: decision,
      timeout: timeout,
    ),
    debugName: 'cockpit.macosSystemDialog',
  );
}

final class _MacosAccessibilityApi {
  _MacosAccessibilityApi._()
    : _applicationServices = DynamicLibrary.open(
        '/System/Library/Frameworks/ApplicationServices.framework/'
        'ApplicationServices',
      ),
      _coreFoundation = DynamicLibrary.open(
        '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
      ) {
    _createApplication = _applicationServices
        .lookupFunction<_CreateApplicationNative, _CreateApplicationDart>(
          'AXUIElementCreateApplication',
        );
    _copyAttributeValue = _applicationServices
        .lookupFunction<_CopyAttributeValueNative, _CopyAttributeValueDart>(
          'AXUIElementCopyAttributeValue',
        );
    _copyMultipleAttributeValues = _applicationServices
        .lookupFunction<
          _CopyMultipleAttributeValuesNative,
          _CopyMultipleAttributeValuesDart
        >('AXUIElementCopyMultipleAttributeValues');
    _setMessagingTimeout = _applicationServices
        .lookupFunction<_SetMessagingTimeoutNative, _SetMessagingTimeoutDart>(
          'AXUIElementSetMessagingTimeout',
        );
    _performAction = _applicationServices
        .lookupFunction<_PerformActionNative, _PerformActionDart>(
          'AXUIElementPerformAction',
        );
    _axValueGetType = _applicationServices
        .lookupFunction<_AxValueGetTypeNative, _AxValueGetTypeDart>(
          'AXValueGetType',
        );
    _axValueGetValue = _applicationServices
        .lookupFunction<_AxValueGetValueNative, _AxValueGetValueDart>(
          'AXValueGetValue',
        );
    _axElementTypeId = _applicationServices
        .lookupFunction<_GetTypeIdNative, _GetTypeIdDart>(
          'AXUIElementGetTypeID',
        )();
    _axValueTypeId = _applicationServices
        .lookupFunction<_GetTypeIdNative, _GetTypeIdDart>('AXValueGetTypeID')();
    _cfGetTypeId = _coreFoundation
        .lookupFunction<_CfGetTypeIdNative, _CfGetTypeIdDart>('CFGetTypeID');
    _cfEqual = _coreFoundation.lookupFunction<_CfEqualNative, _CfEqualDart>(
      'CFEqual',
    );
    _cfStringCreate = _coreFoundation
        .lookupFunction<_CfStringCreateNative, _CfStringCreateDart>(
          'CFStringCreateWithCString',
        );
    _cfStringGetLength = _coreFoundation
        .lookupFunction<_CfStringGetLengthNative, _CfStringGetLengthDart>(
          'CFStringGetLength',
        );
    _cfStringGetMaximumSize = _coreFoundation
        .lookupFunction<
          _CfStringGetMaximumSizeNative,
          _CfStringGetMaximumSizeDart
        >('CFStringGetMaximumSizeForEncoding');
    _cfStringGetCString = _coreFoundation
        .lookupFunction<_CfStringGetCStringNative, _CfStringGetCStringDart>(
          'CFStringGetCString',
        );
    _cfArrayCreate = _coreFoundation
        .lookupFunction<_CfArrayCreateNative, _CfArrayCreateDart>(
          'CFArrayCreate',
        );
    _cfArrayGetCount = _coreFoundation
        .lookupFunction<_CfArrayGetCountNative, _CfArrayGetCountDart>(
          'CFArrayGetCount',
        );
    _cfArrayGetValue = _coreFoundation
        .lookupFunction<_CfArrayGetValueNative, _CfArrayGetValueDart>(
          'CFArrayGetValueAtIndex',
        );
    _cfBooleanGetValue = _coreFoundation
        .lookupFunction<_CfBooleanGetValueNative, _CfBooleanGetValueDart>(
          'CFBooleanGetValue',
        );
    _cfNumberGetValue = _coreFoundation
        .lookupFunction<_CfNumberGetValueNative, _CfNumberGetValueDart>(
          'CFNumberGetValue',
        );
    _cfRelease = _coreFoundation
        .lookupFunction<_CfReleaseNative, _CfReleaseDart>('CFRelease');
    _cfStringTypeId = _coreFoundation
        .lookupFunction<_GetTypeIdNative, _GetTypeIdDart>(
          'CFStringGetTypeID',
        )();
    _cfArrayTypeId = _coreFoundation
        .lookupFunction<_GetTypeIdNative, _GetTypeIdDart>('CFArrayGetTypeID')();
    _cfBooleanTypeId = _coreFoundation
        .lookupFunction<_GetTypeIdNative, _GetTypeIdDart>(
          'CFBooleanGetTypeID',
        )();
    _cfNumberTypeId = _coreFoundation
        .lookupFunction<_GetTypeIdNative, _GetTypeIdDart>(
          'CFNumberGetTypeID',
        )();
  }

  static final _MacosAccessibilityApi instance = _MacosAccessibilityApi._();

  final DynamicLibrary _applicationServices;
  final DynamicLibrary _coreFoundation;
  late final _CreateApplicationDart _createApplication;
  late final _CopyAttributeValueDart _copyAttributeValue;
  late final _CopyMultipleAttributeValuesDart _copyMultipleAttributeValues;
  late final _SetMessagingTimeoutDart _setMessagingTimeout;
  late final _PerformActionDart _performAction;
  late final _AxValueGetTypeDart _axValueGetType;
  late final _AxValueGetValueDart _axValueGetValue;
  late final _CfGetTypeIdDart _cfGetTypeId;
  late final _CfEqualDart _cfEqual;
  late final _CfStringCreateDart _cfStringCreate;
  late final _CfStringGetLengthDart _cfStringGetLength;
  late final _CfStringGetMaximumSizeDart _cfStringGetMaximumSize;
  late final _CfStringGetCStringDart _cfStringGetCString;
  late final _CfArrayCreateDart _cfArrayCreate;
  late final _CfArrayGetCountDart _cfArrayGetCount;
  late final _CfArrayGetValueDart _cfArrayGetValue;
  late final _CfBooleanGetValueDart _cfBooleanGetValue;
  late final _CfNumberGetValueDart _cfNumberGetValue;
  late final _CfReleaseDart _cfRelease;
  late final int _axElementTypeId;
  late final int _axValueTypeId;
  late final int _cfStringTypeId;
  late final int _cfArrayTypeId;
  late final int _cfBooleanTypeId;
  late final int _cfNumberTypeId;

  String readTree({
    required int processId,
    required int maxDepth,
    required int maxNodes,
    required Duration timeout,
  }) {
    final application = _createApplication(processId);
    if (application == nullptr) {
      throw CockpitMacosAccessibilityException(
        code: 'macosAccessibilityProcessNotFound',
        message:
            'Unable to create a macOS accessibility target for process '
            '$processId.',
      );
    }
    final deadline = Stopwatch()..start();
    final attributes = _MacosAccessibilityAttributes.create(this);
    try {
      _setMessagingTimeout(
        application,
        math.min(timeout.inMicroseconds / Duration.microsecondsPerSecond, 5),
      );
      final windows = _copyAttribute(application, attributes.windows);
      try {
        final state = _MacosTreeReadState(
          maxDepth: maxDepth,
          maxNodes: maxNodes,
          timeout: timeout,
          stopwatch: deadline,
          sameElement: _sameElement,
        );
        final encodedWindows = <Map<String, Object?>>[];
        var selfReferentialWindows = 0;
        if (windows != nullptr && _typeId(windows) == _cfArrayTypeId) {
          final count = _cfArrayGetCount(windows);
          for (var index = 0; index < count && !state.exhausted; index += 1) {
            final window = _cfArrayGetValue(windows, index);
            if (window != nullptr && _typeId(window) == _axElementTypeId) {
              if (_sameElement(application, window)) {
                selfReferentialWindows += 1;
                continue;
              }
              final node = _readNode(window, 0, attributes, state);
              if (node != null) encodedWindows.add(node);
            }
          }
        }
        if (encodedWindows.isEmpty && selfReferentialWindows > 0) {
          throw const CockpitMacosAccessibilityException(
            code: 'macosAccessibilityPermissionStale',
            message:
                'macOS accessibility returned the application itself instead '
                'of its windows. Reset and grant Accessibility permission to '
                'the Cockpit host again.',
          );
        }
        return jsonEncode(<String, Object?>{
          'platform': 'macos',
          'target': <String, Object?>{
            'kind': 'processId',
            'value': '$processId',
          },
          'maxDepth': maxDepth,
          'maxNodes': maxNodes,
          'nodeCount': state.nodeCount,
          'truncated': state.nodeCount >= maxNodes,
          if (state.cycleCount > 0) 'cycleCount': state.cycleCount,
          'windows': encodedWindows,
        });
      } finally {
        if (windows != nullptr) _cfRelease(windows);
      }
    } finally {
      attributes.dispose(this);
      _cfRelease(application);
    }
  }

  String dismissSystemDialog({
    required int processId,
    required String decision,
    required Duration timeout,
  }) {
    final application = _createApplication(processId);
    if (application == nullptr) {
      throw CockpitMacosAccessibilityException(
        code: 'macosAccessibilityProcessNotFound',
        message:
            'Unable to create a macOS accessibility target for process '
            '$processId.',
      );
    }
    final stopwatch = Stopwatch()..start();
    final attributes = _MacosDialogAttributes.create(this);
    try {
      _setMessagingTimeout(
        application,
        math.min(timeout.inMicroseconds / Duration.microsecondsPerSecond, 5),
      );
      final windows = _copyAttribute(application, attributes.windows);
      try {
        if (windows == nullptr || _typeId(windows) != _cfArrayTypeId) {
          return 'dismissSystemDialog decision=$decision handled=false reason=noDialog';
        }
        final count = _cfArrayGetCount(windows);
        for (var index = 0; index < count; index += 1) {
          _checkDialogDeadline(stopwatch, timeout);
          final window = _cfArrayGetValue(windows, index);
          if (window == nullptr || _typeId(window) != _axElementTypeId) {
            continue;
          }
          final result = _handleDialogInElement(
            window,
            decision,
            attributes,
            stopwatch,
            timeout,
            depth: 0,
          );
          if (result == _MacosDialogResult.handled) {
            return 'dismissSystemDialog decision=$decision handled=true';
          }
          if (result == _MacosDialogResult.noSafeAction) {
            return 'dismissSystemDialog decision=$decision handled=false reason=noSafeAction';
          }
        }
        return 'dismissSystemDialog decision=$decision handled=false reason=noDialog';
      } finally {
        if (windows != nullptr) _cfRelease(windows);
      }
    } finally {
      attributes.dispose(this);
      _cfRelease(application);
    }
  }

  _MacosDialogResult _handleDialogInElement(
    Pointer<Void> element,
    String decision,
    _MacosDialogAttributes attributes,
    Stopwatch stopwatch,
    Duration timeout, {
    required int depth,
  }) {
    _checkDialogDeadline(stopwatch, timeout);
    if (depth > 8) return _MacosDialogResult.notDialog;

    final sheets = _copyAttribute(element, attributes.sheets);
    try {
      if (sheets != nullptr && _typeId(sheets) == _cfArrayTypeId) {
        final count = _cfArrayGetCount(sheets);
        for (var index = 0; index < count; index += 1) {
          final sheet = _cfArrayGetValue(sheets, index);
          if (sheet == nullptr || _typeId(sheet) != _axElementTypeId) continue;
          final result = _handleDialogInElement(
            sheet,
            decision,
            attributes,
            stopwatch,
            timeout,
            depth: depth + 1,
          );
          if (result != _MacosDialogResult.notDialog) return result;
        }
      }
    } finally {
      if (sheets != nullptr) _cfRelease(sheets);
    }

    if (_isDialog(element, attributes)) {
      return _performDialogDecision(element, decision, attributes)
          ? _MacosDialogResult.handled
          : _MacosDialogResult.noSafeAction;
    }

    return _MacosDialogResult.notDialog;
  }

  bool _isDialog(Pointer<Void> element, _MacosDialogAttributes attributes) {
    final role = _copyStringAttribute(element, attributes.role);
    final subrole = _copyStringAttribute(element, attributes.subrole);
    final modal = _copyBooleanAttribute(element, attributes.modal);
    return role == 'AXSheet' ||
        subrole == 'AXDialog' ||
        (role == 'AXWindow' && modal == true);
  }

  bool _performDialogDecision(
    Pointer<Void> dialog,
    String decision,
    _MacosDialogAttributes attributes,
  ) {
    final buttonAttributes = decision == 'accept'
        ? <Pointer<Void>>[attributes.defaultButton]
        : <Pointer<Void>>[attributes.cancelButton, attributes.closeButton];
    for (final attribute in buttonAttributes) {
      final button = _copyAttribute(dialog, attribute);
      try {
        if (button != nullptr &&
            _typeId(button) == _axElementTypeId &&
            _performIfSupported(button, attributes.pressAction)) {
          return true;
        }
      } finally {
        if (button != nullptr) _cfRelease(button);
      }
    }
    return _performIfSupported(
      dialog,
      decision == 'accept' ? attributes.confirmAction : attributes.cancelAction,
    );
  }

  bool _performIfSupported(Pointer<Void> element, Pointer<Void> action) {
    final error = _performAction(element, action);
    if (error == 0) return true;
    if (error == _axErrorActionUnsupported ||
        error == _axErrorAttributeUnsupported ||
        error == _axErrorNoValue) {
      return false;
    }
    _throwAxError(error, 'perform accessibility dialog action');
  }

  String? _copyStringAttribute(Pointer<Void> element, Pointer<Void> attribute) {
    final value = _copyAttribute(element, attribute);
    try {
      return value != nullptr && _typeId(value) == _cfStringTypeId
          ? _readCfString(value)
          : null;
    } finally {
      if (value != nullptr) _cfRelease(value);
    }
  }

  bool? _copyBooleanAttribute(Pointer<Void> element, Pointer<Void> attribute) {
    final value = _copyAttribute(element, attribute);
    try {
      return value != nullptr && _typeId(value) == _cfBooleanTypeId
          ? _cfBooleanGetValue(value) != 0
          : null;
    } finally {
      if (value != nullptr) _cfRelease(value);
    }
  }

  void _checkDialogDeadline(Stopwatch stopwatch, Duration timeout) {
    if (stopwatch.elapsed >= timeout) {
      throw TimeoutException('macOS system dialog action timed out.');
    }
  }

  Map<String, Object?>? _readNode(
    Pointer<Void> element,
    int depth,
    _MacosAccessibilityAttributes attributes,
    _MacosTreeReadState state,
  ) {
    if (!state.enterNode(element)) return null;
    final values = calloc<Pointer<Void>>();
    try {
      final error = _copyMultipleAttributeValues(
        element,
        attributes.nodeAttributes,
        0,
        values,
      );
      if (error != 0) _throwAxError(error, 'read accessibility attributes');
      final payload = values.value;
      if (payload == nullptr || _typeId(payload) != _cfArrayTypeId) {
        throw const CockpitMacosAccessibilityException(
          code: 'macosAccessibilityInvalidTree',
          message: 'macOS accessibility returned an invalid node payload.',
        );
      }
      final node = <String, Object?>{};
      _addString(node, 'role', payload, _MacosAttributeIndex.role);
      _addString(node, 'subrole', payload, _MacosAttributeIndex.subrole);
      _addString(node, 'title', payload, _MacosAttributeIndex.title);
      _addString(
        node,
        'description',
        payload,
        _MacosAttributeIndex.description,
      );
      _addString(node, 'value', payload, _MacosAttributeIndex.value);
      _addString(node, 'identifier', payload, _MacosAttributeIndex.identifier);
      _addString(node, 'hint', payload, _MacosAttributeIndex.help);
      _addBoolean(node, 'enabled', payload, _MacosAttributeIndex.enabled);
      _addBoolean(node, 'focused', payload, _MacosAttributeIndex.focused);
      _addBoolean(node, 'selected', payload, _MacosAttributeIndex.selected);
      _addBoolean(node, 'expanded', payload, _MacosAttributeIndex.expanded);
      final frame = _readFrame(payload);
      if (frame != null) node['frame'] = frame;
      if (depth < state.maxDepth && !state.exhausted) {
        final children = _arrayValue(payload, _MacosAttributeIndex.children);
        if (children != nullptr) {
          final encodedChildren = <Map<String, Object?>>[];
          final childCount = _cfArrayGetCount(children);
          for (
            var index = 0;
            index < childCount && !state.exhausted;
            index += 1
          ) {
            final child = _cfArrayGetValue(children, index);
            if (child != nullptr && _typeId(child) == _axElementTypeId) {
              final encoded = _readNode(child, depth + 1, attributes, state);
              if (encoded != null) encodedChildren.add(encoded);
            }
          }
          if (encodedChildren.isNotEmpty) node['children'] = encodedChildren;
        }
      }
      return node;
    } finally {
      if (values.value != nullptr) _cfRelease(values.value);
      calloc.free(values);
      state.leaveNode();
    }
  }

  bool _sameElement(Pointer<Void> left, Pointer<Void> right) =>
      _cfEqual(left, right) != 0;

  Pointer<Void> _copyAttribute(Pointer<Void> element, Pointer<Void> attribute) {
    final value = calloc<Pointer<Void>>();
    try {
      final error = _copyAttributeValue(element, attribute, value);
      if (error == _axErrorAttributeUnsupported || error == _axErrorNoValue) {
        return nullptr;
      }
      if (error != 0) _throwAxError(error, 'read accessibility attribute');
      return value.value;
    } finally {
      calloc.free(value);
    }
  }

  Pointer<Void> _valueAt(Pointer<Void> values, int index) {
    if (_typeId(values) != _cfArrayTypeId ||
        index < 0 ||
        index >= _cfArrayGetCount(values)) {
      return nullptr;
    }
    return _cfArrayGetValue(values, index);
  }

  Pointer<Void> _arrayValue(Pointer<Void> values, int index) {
    final value = _valueAt(values, index);
    return value != nullptr && _typeId(value) == _cfArrayTypeId
        ? value
        : nullptr;
  }

  void _addString(
    Map<String, Object?> node,
    String name,
    Pointer<Void> values,
    int index,
  ) {
    final value = _scalarText(_valueAt(values, index));
    if (value != null && value.isNotEmpty) node[name] = value;
  }

  void _addBoolean(
    Map<String, Object?> node,
    String name,
    Pointer<Void> values,
    int index,
  ) {
    final value = _valueAt(values, index);
    if (value != nullptr && _typeId(value) == _cfBooleanTypeId) {
      node[name] = _cfBooleanGetValue(value) != 0;
    }
  }

  Map<String, Object?>? _readFrame(Pointer<Void> values) {
    final position = _valueAt(values, _MacosAttributeIndex.position);
    final size = _valueAt(values, _MacosAttributeIndex.size);
    if (position == nullptr ||
        size == nullptr ||
        _typeId(position) != _axValueTypeId ||
        _typeId(size) != _axValueTypeId ||
        _axValueGetType(position) != _axValuePointType ||
        _axValueGetType(size) != _axValueSizeType) {
      return null;
    }
    final point = calloc<_MacosPoint>();
    final dimensions = calloc<_MacosSize>();
    try {
      if (_axValueGetValue(position, _axValuePointType, point.cast()) == 0 ||
          _axValueGetValue(size, _axValueSizeType, dimensions.cast()) == 0) {
        return null;
      }
      final x = point.ref.x;
      final y = point.ref.y;
      final width = dimensions.ref.width;
      final height = dimensions.ref.height;
      if (!x.isFinite ||
          !y.isFinite ||
          !width.isFinite ||
          !height.isFinite ||
          width < 0 ||
          height < 0) {
        return null;
      }
      return <String, Object?>{
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };
    } finally {
      calloc.free(point);
      calloc.free(dimensions);
    }
  }

  String? _scalarText(Pointer<Void> value) {
    if (value == nullptr) return null;
    final typeId = _typeId(value);
    if (typeId == _cfStringTypeId) return _readCfString(value);
    if (typeId == _cfBooleanTypeId) {
      return _cfBooleanGetValue(value) == 0 ? 'false' : 'true';
    }
    if (typeId == _cfNumberTypeId) {
      final number = calloc<Double>();
      try {
        if (_cfNumberGetValue(value, _cfNumberDoubleType, number.cast()) == 0) {
          return null;
        }
        final result = number.value;
        return result == result.truncateToDouble()
            ? '${result.toInt()}'
            : '$result';
      } finally {
        calloc.free(number);
      }
    }
    return null;
  }

  String _readCfString(Pointer<Void> value) {
    final length = _cfStringGetLength(value);
    final capacity = _cfStringGetMaximumSize(length, _cfStringEncodingUtf8) + 1;
    final buffer = calloc<Uint8>(capacity);
    try {
      if (_cfStringGetCString(
            value,
            buffer.cast(),
            capacity,
            _cfStringEncodingUtf8,
          ) ==
          0) {
        throw const CockpitMacosAccessibilityException(
          code: 'macosAccessibilityInvalidText',
          message: 'Unable to decode a macOS accessibility string.',
        );
      }
      return buffer.cast<Utf8>().toDartString();
    } finally {
      calloc.free(buffer);
    }
  }

  Pointer<Void> _createCfString(String value) {
    final source = value.toNativeUtf8();
    try {
      final result = _cfStringCreate(
        nullptr,
        source.cast(),
        _cfStringEncodingUtf8,
      );
      if (result == nullptr) {
        throw const CockpitMacosAccessibilityException(
          code: 'macosAccessibilityInitializationFailed',
          message: 'Unable to create a macOS accessibility attribute.',
        );
      }
      return result;
    } finally {
      malloc.free(source);
    }
  }

  int _typeId(Pointer<Void> value) => _cfGetTypeId(value);

  Never _throwAxError(int error, String operation) {
    final code = switch (error) {
      _axErrorApiDisabled => 'macosAccessibilityPermissionDenied',
      _axErrorInvalidUiElement => 'macosAccessibilityProcessNotFound',
      _axErrorCannotComplete => 'macosAccessibilityUnavailable',
      _ => 'macosAccessibilityFailed',
    };
    final guidance = error == _axErrorApiDisabled
        ? ' Grant Accessibility permission to the Cockpit host process.'
        : '';
    throw CockpitMacosAccessibilityException(
      code: code,
      message: 'Unable to $operation (AXError $error).$guidance',
    );
  }
}

final class _MacosAccessibilityAttributes {
  _MacosAccessibilityAttributes._({
    required this.windows,
    required this.nodeAttributes,
    required List<Pointer<Void>> ownedValues,
  }) : _ownedValues = ownedValues;

  final Pointer<Void> windows;
  final Pointer<Void> nodeAttributes;
  final List<Pointer<Void>> _ownedValues;

  static _MacosAccessibilityAttributes create(_MacosAccessibilityApi api) {
    final windows = api._createCfString('AXWindows');
    final values = <Pointer<Void>>[
      for (final name in const <String>[
        'AXRole',
        'AXSubrole',
        'AXTitle',
        'AXDescription',
        'AXValue',
        'AXIdentifier',
        'AXHelp',
        'AXEnabled',
        'AXFocused',
        'AXSelected',
        'AXExpanded',
        'AXPosition',
        'AXSize',
        'AXChildren',
      ])
        api._createCfString(name),
    ];
    final valuePointers = calloc<Pointer<Void>>(values.length);
    try {
      for (var index = 0; index < values.length; index += 1) {
        valuePointers[index] = values[index];
      }
      final nodeAttributes = api._cfArrayCreate(
        nullptr,
        valuePointers,
        values.length,
        nullptr,
      );
      if (nodeAttributes == nullptr) {
        throw const CockpitMacosAccessibilityException(
          code: 'macosAccessibilityInitializationFailed',
          message: 'Unable to create the macOS accessibility query.',
        );
      }
      return _MacosAccessibilityAttributes._(
        windows: windows,
        nodeAttributes: nodeAttributes,
        ownedValues: values,
      );
    } catch (_) {
      for (final value in values) {
        api._cfRelease(value);
      }
      api._cfRelease(windows);
      rethrow;
    } finally {
      calloc.free(valuePointers);
    }
  }

  void dispose(_MacosAccessibilityApi api) {
    api._cfRelease(nodeAttributes);
    for (final value in _ownedValues) {
      api._cfRelease(value);
    }
    api._cfRelease(windows);
  }
}

final class _MacosDialogAttributes {
  _MacosDialogAttributes._({
    required this.windows,
    required this.role,
    required this.subrole,
    required this.modal,
    required this.sheets,
    required this.defaultButton,
    required this.cancelButton,
    required this.closeButton,
    required this.pressAction,
    required this.confirmAction,
    required this.cancelAction,
    required List<Pointer<Void>> ownedValues,
  }) : _ownedValues = ownedValues;

  final Pointer<Void> windows;
  final Pointer<Void> role;
  final Pointer<Void> subrole;
  final Pointer<Void> modal;
  final Pointer<Void> sheets;
  final Pointer<Void> defaultButton;
  final Pointer<Void> cancelButton;
  final Pointer<Void> closeButton;
  final Pointer<Void> pressAction;
  final Pointer<Void> confirmAction;
  final Pointer<Void> cancelAction;
  final List<Pointer<Void>> _ownedValues;

  static _MacosDialogAttributes create(_MacosAccessibilityApi api) {
    final values = <Pointer<Void>>[
      for (final name in const <String>[
        'AXWindows',
        'AXRole',
        'AXSubrole',
        'AXModal',
        'AXSheets',
        'AXDefaultButton',
        'AXCancelButton',
        'AXCloseButton',
        'AXPress',
        'AXConfirm',
        'AXCancel',
      ])
        api._createCfString(name),
    ];
    return _MacosDialogAttributes._(
      windows: values[0],
      role: values[1],
      subrole: values[2],
      modal: values[3],
      sheets: values[4],
      defaultButton: values[5],
      cancelButton: values[6],
      closeButton: values[7],
      pressAction: values[8],
      confirmAction: values[9],
      cancelAction: values[10],
      ownedValues: values,
    );
  }

  void dispose(_MacosAccessibilityApi api) {
    for (final value in _ownedValues) {
      api._cfRelease(value);
    }
  }
}

enum _MacosDialogResult { handled, noSafeAction, notDialog }

abstract final class _MacosAttributeIndex {
  static const int role = 0;
  static const int subrole = 1;
  static const int title = 2;
  static const int description = 3;
  static const int value = 4;
  static const int identifier = 5;
  static const int help = 6;
  static const int enabled = 7;
  static const int focused = 8;
  static const int selected = 9;
  static const int expanded = 10;
  static const int position = 11;
  static const int size = 12;
  static const int children = 13;
}

final class _MacosTreeReadState {
  _MacosTreeReadState({
    required this.maxDepth,
    required this.maxNodes,
    required this.timeout,
    required this.stopwatch,
    required bool Function(Pointer<Void>, Pointer<Void>) sameElement,
  }) : _sameElement = sameElement;

  final int maxDepth;
  final int maxNodes;
  final Duration timeout;
  final Stopwatch stopwatch;
  final bool Function(Pointer<Void>, Pointer<Void>) _sameElement;
  final List<Pointer<Void>> _ancestors = <Pointer<Void>>[];
  int nodeCount = 0;
  int cycleCount = 0;

  bool get exhausted => nodeCount >= maxNodes;

  bool enterNode(Pointer<Void> element) {
    if (stopwatch.elapsed >= timeout) {
      throw TimeoutException('macOS accessibility tree read timed out.');
    }
    if (_ancestors.any((ancestor) => _sameElement(ancestor, element))) {
      cycleCount += 1;
      return false;
    }
    if (nodeCount >= maxNodes) {
      throw const CockpitMacosAccessibilityException(
        code: 'macosAccessibilityNodeBudgetExceeded',
        message: 'macOS accessibility node budget was exhausted.',
      );
    }
    nodeCount += 1;
    _ancestors.add(element);
    return true;
  }

  void leaveNode() => _ancestors.removeLast();
}

final class _MacosPoint extends Struct {
  @Double()
  external double x;

  @Double()
  external double y;
}

final class _MacosSize extends Struct {
  @Double()
  external double width;

  @Double()
  external double height;
}

const int _cfStringEncodingUtf8 = 0x08000100;
const int _cfNumberDoubleType = 13;
const int _axValuePointType = 1;
const int _axValueSizeType = 2;
const int _axErrorInvalidUiElement = -25202;
const int _axErrorCannotComplete = -25204;
const int _axErrorAttributeUnsupported = -25205;
const int _axErrorActionUnsupported = -25206;
const int _axErrorApiDisabled = -25211;
const int _axErrorNoValue = -25212;

typedef _CreateApplicationNative = Pointer<Void> Function(Int32 processId);
typedef _CreateApplicationDart = Pointer<Void> Function(int processId);
typedef _CopyAttributeValueNative =
    Int32 Function(
      Pointer<Void> element,
      Pointer<Void> attribute,
      Pointer<Pointer<Void>> value,
    );
typedef _CopyAttributeValueDart =
    int Function(
      Pointer<Void> element,
      Pointer<Void> attribute,
      Pointer<Pointer<Void>> value,
    );
typedef _CopyMultipleAttributeValuesNative =
    Int32 Function(
      Pointer<Void> element,
      Pointer<Void> attributes,
      Uint32 options,
      Pointer<Pointer<Void>> values,
    );
typedef _CopyMultipleAttributeValuesDart =
    int Function(
      Pointer<Void> element,
      Pointer<Void> attributes,
      int options,
      Pointer<Pointer<Void>> values,
    );
typedef _SetMessagingTimeoutNative =
    Int32 Function(Pointer<Void> element, Float timeoutSeconds);
typedef _SetMessagingTimeoutDart =
    int Function(Pointer<Void> element, double timeoutSeconds);
typedef _PerformActionNative =
    Int32 Function(Pointer<Void> element, Pointer<Void> action);
typedef _PerformActionDart =
    int Function(Pointer<Void> element, Pointer<Void> action);
typedef _AxValueGetTypeNative = Int32 Function(Pointer<Void> value);
typedef _AxValueGetTypeDart = int Function(Pointer<Void> value);
typedef _AxValueGetValueNative =
    Uint8 Function(Pointer<Void> value, Int32 valueType, Pointer<Void> output);
typedef _AxValueGetValueDart =
    int Function(Pointer<Void> value, int valueType, Pointer<Void> output);
typedef _GetTypeIdNative = UintPtr Function();
typedef _GetTypeIdDart = int Function();
typedef _CfGetTypeIdNative = UintPtr Function(Pointer<Void> value);
typedef _CfGetTypeIdDart = int Function(Pointer<Void> value);
typedef _CfEqualNative =
    Uint8 Function(Pointer<Void> left, Pointer<Void> right);
typedef _CfEqualDart = int Function(Pointer<Void> left, Pointer<Void> right);
typedef _CfStringCreateNative =
    Pointer<Void> Function(
      Pointer<Void> allocator,
      Pointer<Char> value,
      Uint32 encoding,
    );
typedef _CfStringCreateDart =
    Pointer<Void> Function(
      Pointer<Void> allocator,
      Pointer<Char> value,
      int encoding,
    );
typedef _CfStringGetLengthNative = IntPtr Function(Pointer<Void> value);
typedef _CfStringGetLengthDart = int Function(Pointer<Void> value);
typedef _CfStringGetMaximumSizeNative =
    IntPtr Function(IntPtr length, Uint32 encoding);
typedef _CfStringGetMaximumSizeDart = int Function(int length, int encoding);
typedef _CfStringGetCStringNative =
    Uint8 Function(
      Pointer<Void> value,
      Pointer<Char> buffer,
      IntPtr bufferSize,
      Uint32 encoding,
    );
typedef _CfStringGetCStringDart =
    int Function(
      Pointer<Void> value,
      Pointer<Char> buffer,
      int bufferSize,
      int encoding,
    );
typedef _CfArrayCreateNative =
    Pointer<Void> Function(
      Pointer<Void> allocator,
      Pointer<Pointer<Void>> values,
      IntPtr count,
      Pointer<Void> callbacks,
    );
typedef _CfArrayCreateDart =
    Pointer<Void> Function(
      Pointer<Void> allocator,
      Pointer<Pointer<Void>> values,
      int count,
      Pointer<Void> callbacks,
    );
typedef _CfArrayGetCountNative = IntPtr Function(Pointer<Void> value);
typedef _CfArrayGetCountDart = int Function(Pointer<Void> value);
typedef _CfArrayGetValueNative =
    Pointer<Void> Function(Pointer<Void> value, IntPtr index);
typedef _CfArrayGetValueDart =
    Pointer<Void> Function(Pointer<Void> value, int index);
typedef _CfBooleanGetValueNative = Uint8 Function(Pointer<Void> value);
typedef _CfBooleanGetValueDart = int Function(Pointer<Void> value);
typedef _CfNumberGetValueNative =
    Uint8 Function(Pointer<Void> value, Int32 numberType, Pointer<Void> output);
typedef _CfNumberGetValueDart =
    int Function(Pointer<Void> value, int numberType, Pointer<Void> output);
typedef _CfReleaseNative = Void Function(Pointer<Void> value);
typedef _CfReleaseDart = void Function(Pointer<Void> value);

const String _resolveApplicationProcessScript = r'''
ObjC.import('AppKit')

function run(argv) {
  const appId = argv[0]
  const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(appId)
  if (Number(apps.count) !== 1) {
    throw new Error(
      `Expected one running macOS application for ${appId}, found ${Number(apps.count)}`,
    )
  }
  return String(Number(apps.objectAtIndex(0).processIdentifier))
}
''';
