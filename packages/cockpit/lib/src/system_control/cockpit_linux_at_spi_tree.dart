import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';

const String cockpitLinuxAtSpiCommandExecutable =
    '__flutter_cockpit_linux_at_spi';

typedef CockpitLinuxAtSpiTreeReader =
    Future<String> Function({
      String? appId,
      int? processId,
      required int maxDepth,
      required int maxNodes,
      required Duration timeout,
    });

typedef CockpitLinuxAtSpiProbe =
    Future<CockpitLinuxAtSpiProbeResult> Function({required Duration timeout});

typedef CockpitLinuxAtSpiMethodCaller =
    Future<DBusMethodSuccessResponse> Function(
      String interface,
      String method,
      List<DBusValue> values, {
      DBusSignature? replySignature,
    });

final class CockpitLinuxAtSpiProbeResult {
  const CockpitLinuxAtSpiProbeResult.available()
    : available = true,
      failureReason = null;

  const CockpitLinuxAtSpiProbeResult.blocked(this.failureReason)
    : available = false;

  final bool available;
  final String? failureReason;
}

final class CockpitLinuxAtSpiException implements Exception {
  const CockpitLinuxAtSpiException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

Future<Set<String>> cockpitReadLinuxAtSpiInterfaces(
  CockpitLinuxAtSpiMethodCaller methodCaller,
) async {
  final response = await methodCaller(
    'org.a11y.atspi.Accessible',
    'GetInterfaces',
    const <DBusValue>[],
    replySignature: DBusSignature('as'),
  );
  return response.returnValues.single
      .asStringArray()
      .map(_normalizeLinuxAtSpiInterface)
      .toSet();
}

Future<String> cockpitReadLinuxAtSpiRole(
  CockpitLinuxAtSpiMethodCaller methodCaller,
) async {
  try {
    final response = await methodCaller(
      'org.a11y.atspi.Accessible',
      'GetRoleName',
      const <DBusValue>[],
      replySignature: DBusSignature('s'),
    );
    final name = response.returnValues.single.asString().trim();
    if (name.isNotEmpty) return name;
  } on Object {
    // GetRoleName is optional in the AT-SPI protocol; GetRole is canonical.
  }
  final response = await methodCaller(
    'org.a11y.atspi.Accessible',
    'GetRole',
    const <DBusValue>[],
    replySignature: DBusSignature('u'),
  );
  final role = response.returnValues.single.asUint32();
  return role < _linuxAtSpiRoleNames.length
      ? _linuxAtSpiRoleNames[role]
      : 'role-$role';
}

Future<CockpitLinuxAtSpiProbeResult> cockpitProbeLinuxAtSpi({
  required Duration timeout,
}) async {
  _CockpitAtSpiConnection? connection;
  try {
    connection = await _CockpitAtSpiConnection.open().timeout(timeout);
    await connection.readRegistryChildren().timeout(timeout);
    return const CockpitLinuxAtSpiProbeResult.available();
  } on TimeoutException {
    return const CockpitLinuxAtSpiProbeResult.blocked('atSpiProbeTimedOut');
  } on Object catch (error) {
    return CockpitLinuxAtSpiProbeResult.blocked(_compactFailureReason(error));
  } finally {
    await connection?.close();
  }
}

Future<String> cockpitReadLinuxAtSpiTree({
  String? appId,
  int? processId,
  required int maxDepth,
  required int maxNodes,
  required Duration timeout,
}) async {
  if ((appId == null || appId.trim().isEmpty) &&
      (processId == null || processId <= 0)) {
    throw const CockpitLinuxAtSpiException(
      'missingLinuxAtSpiTarget',
      'Linux AT-SPI tree reads require an app id or process id.',
    );
  }
  _CockpitAtSpiConnection? connection;
  try {
    connection = await _CockpitAtSpiConnection.open().timeout(timeout);
    return await connection
        .readTree(
          appId: appId,
          processId: processId,
          maxDepth: maxDepth,
          maxNodes: maxNodes,
        )
        .timeout(timeout);
  } on TimeoutException {
    throw CockpitLinuxAtSpiException(
      'linuxAtSpiTimedOut',
      'Linux AT-SPI tree read exceeded ${timeout.inMilliseconds}ms.',
    );
  } on CockpitLinuxAtSpiException {
    rethrow;
  } on Object catch (error) {
    throw CockpitLinuxAtSpiException(
      'linuxAtSpiReadFailed',
      _compactFailureReason(error),
    );
  } finally {
    await connection?.close();
  }
}

final class _CockpitAtSpiConnection {
  _CockpitAtSpiConnection._(this._client);

  final DBusClient _client;

  static Future<_CockpitAtSpiConnection> open() async {
    final session = DBusClient.session(introspectable: false);
    try {
      final bus = DBusRemoteObject(
        session,
        name: 'org.a11y.Bus',
        path: DBusObjectPath('/org/a11y/bus'),
      );
      final response = await bus.callMethod(
        'org.a11y.Bus',
        'GetAddress',
        const <DBusValue>[],
        replySignature: DBusSignature('s'),
      );
      final address = response.returnValues.single.asString().trim();
      if (address.isEmpty) {
        throw const CockpitLinuxAtSpiException(
          'linuxAtSpiAddressMissing',
          'The desktop accessibility bus returned an empty address.',
        );
      }
      return _CockpitAtSpiConnection._(
        DBusClient(DBusAddress(address), introspectable: false),
      );
    } finally {
      await session.close();
    }
  }

  Future<void> close() => _client.close();

  Future<List<_AtSpiReference>> readRegistryChildren() {
    return _childrenOf(
      const _AtSpiReference(
        bus: 'org.a11y.atspi.Registry',
        path: '/org/a11y/atspi/accessible/root',
      ),
    );
  }

  Future<String> readTree({
    required String? appId,
    required int? processId,
    required int maxDepth,
    required int maxNodes,
  }) async {
    final roots = await readRegistryChildren();
    final target = await _selectTarget(
      roots,
      appId: appId,
      processId: processId,
    );
    final read = await _readBoundedTree(
      target.reference,
      maxDepth: maxDepth,
      maxNodes: maxNodes,
    );
    final records = read.records;
    if (records.isEmpty) {
      throw const CockpitLinuxAtSpiException(
        'linuxAtSpiTreeEmpty',
        'The target application exposed no readable AT-SPI nodes.',
      );
    }
    final nodes = <Map<String, Object?>>[
      for (final record in records) record.node,
    ];
    for (var index = records.length - 1; index >= 0; index -= 1) {
      final parent = records[index].parent;
      if (parent == null) continue;
      (nodes[parent]['children'] as List<Map<String, Object?>>).add(
        nodes[index],
      );
    }
    return jsonEncode(<String, Object?>{
      'platform': 'linux',
      'target': <String, Object?>{
        if (appId != null && appId.trim().isNotEmpty) 'appId': appId.trim(),
        'processId': target.processId,
        if (target.name.isNotEmpty) 'name': target.name,
      },
      'maxDepth': maxDepth,
      'maxNodes': maxNodes,
      'nodeCount': records.length,
      'truncated': read.truncated,
      'tree': nodes.first,
    });
  }

  Future<_AtSpiTarget> _selectTarget(
    List<_AtSpiReference> roots, {
    required String? appId,
    required int? processId,
  }) async {
    final candidates = await Future.wait(<Future<_AtSpiTarget?>>[
      for (final reference in roots) _readTarget(reference),
    ]);
    final readable = candidates.whereType<_AtSpiTarget>().toList();
    if (processId != null && processId > 0) {
      final matches = readable
          .where((candidate) => candidate.processId == processId)
          .toList();
      if (matches.length == 1) return matches.single;
      if (matches.length > 1) {
        return matches.firstWhere(
          (candidate) => candidate.name.isNotEmpty,
          orElse: () => matches.first,
        );
      }
      throw CockpitLinuxAtSpiException(
        'linuxAtSpiTargetNotFound',
        'No AT-SPI application belongs to process $processId.',
      );
    }

    final expected = appId!.trim().toLowerCase();
    final exact = <_AtSpiTarget>[];
    final partial = <_AtSpiTarget>[];
    for (final candidate in readable) {
      final identities = <String>{
        candidate.name.toLowerCase(),
        candidate.reference.bus.toLowerCase(),
        ..._processIdentities(candidate.processId),
      }..removeWhere((value) => value.isEmpty);
      if (identities.contains(expected)) {
        exact.add(candidate);
      } else if (identities.any(
        (identity) =>
            identity.contains(expected) || expected.contains(identity),
      )) {
        partial.add(candidate);
      }
    }
    final matches = exact.isNotEmpty ? exact : partial;
    if (matches.length == 1) return matches.single;
    if (matches.isEmpty) {
      throw CockpitLinuxAtSpiException(
        'linuxAtSpiTargetNotFound',
        'No AT-SPI application matches $appId.',
      );
    }
    throw CockpitLinuxAtSpiException(
      'linuxAtSpiTargetAmbiguous',
      'Several AT-SPI applications match $appId; select the target by process id.',
    );
  }

  Future<_AtSpiTarget?> _readTarget(_AtSpiReference reference) async {
    try {
      final name = await _accessibleProperty(reference, 'Name');
      final processId = await _client.getConnectionUnixProcessId(reference.bus);
      return _AtSpiTarget(
        reference: reference,
        processId: processId,
        name: name?.asString().trim() ?? '',
      );
    } on Object {
      return null;
    }
  }

  Future<({List<_AtSpiNodeRecord> records, bool truncated})> _readBoundedTree(
    _AtSpiReference root, {
    required int maxDepth,
    required int maxNodes,
  }) async {
    final records = <_AtSpiNodeRecord>[];
    final pending = <_AtSpiPendingNode>[
      _AtSpiPendingNode(reference: root, parent: null, depth: 0),
    ];
    final seen = <String>{};
    var truncated = false;
    const batchSize = 24;

    while (pending.isNotEmpty && records.length < maxNodes) {
      final count = <int>[
        batchSize,
        pending.length,
        maxNodes - records.length,
      ].reduce((left, right) => left < right ? left : right);
      final batch = pending.sublist(0, count);
      pending.removeRange(0, count);
      final reads = await Future.wait(<Future<_AtSpiNodeRead>>[
        for (final item in batch) _readNode(item.reference),
      ]);
      for (var index = 0; index < batch.length; index += 1) {
        final item = batch[index];
        final key = '${item.reference.bus}:${item.reference.path}';
        if (!seen.add(key)) continue;
        final recordIndex = records.length;
        final read = reads[index];
        records.add(_AtSpiNodeRecord(parent: item.parent, node: read.node));
        if (item.depth >= maxDepth) {
          if (read.children.isNotEmpty) truncated = true;
          continue;
        }
        if (records.length >= maxNodes) {
          if (read.children.isNotEmpty || pending.isNotEmpty) truncated = true;
          continue;
        }
        for (final child in read.children) {
          if (records.length + pending.length >= maxNodes) {
            truncated = true;
            break;
          }
          final childKey = '${child.bus}:${child.path}';
          if (seen.contains(childKey)) continue;
          pending.add(
            _AtSpiPendingNode(
              reference: child,
              parent: recordIndex,
              depth: item.depth + 1,
            ),
          );
        }
      }
    }
    if (pending.isNotEmpty) truncated = true;
    return (records: records, truncated: truncated);
  }

  Future<_AtSpiNodeRead> _readNode(_AtSpiReference reference) async {
    try {
      final values = await Future.wait<Object?>(<Future<Object?>>[
        _readChildren(reference),
        _readAccessibleProperties(reference),
        _readRole(reference),
        _readInterfaces(reference),
        _readStates(reference),
      ]);
      final children = values[0]! as List<_AtSpiReference>;
      final properties = values[1]! as Map<String, DBusValue>;
      final role = values[2]! as String;
      final interfaces = values[3]! as Set<String>;
      final states = values[4]! as Set<int>;
      final frame = interfaces.contains('Component')
          ? await _readFrame(reference)
          : null;
      final name = _stringValue(properties['Name']);
      final description = _stringValue(properties['Description']);
      final accessibleId = _stringValue(properties['AccessibleId']);
      final helpText = _stringValue(properties['HelpText']);
      final node = <String, Object?>{
        if (role.isNotEmpty) 'role': role,
        'visible': states.contains(30) && states.contains(25),
        'enabled': states.contains(8) && states.contains(24),
        if (states.contains(11)) 'focusable': true,
        if (states.contains(12)) 'focused': true,
        if (states.contains(4) || states.contains(41)) 'checkable': true,
        if (states.contains(4)) 'checked': true,
        if (states.contains(10)) 'expanded': true,
        if (states.contains(20)) 'pressed': true,
        if (states.contains(23)) 'selected': true,
        if (interfaces.contains('Action')) 'clickable': true,
        if (interfaces.contains('Text')) 'editable': states.contains(7),
        if (role.toLowerCase().contains('scroll')) 'scrollable': true,
        if (role.toLowerCase().contains('password')) 'password': true,
        'children': <Map<String, Object?>>[],
      };
      switch (name) {
        case final value?:
          node['name'] = value;
      }
      switch (description) {
        case final value?:
          node['description'] = value;
      }
      switch (accessibleId) {
        case final value?:
          node['id'] = value;
          node['testid'] = value;
      }
      switch (helpText) {
        case final value?:
          node['hint'] = value;
      }
      switch (frame) {
        case final value?:
          node['frame'] = value;
      }
      return _AtSpiNodeRead(node: node, children: children);
    } on Object {
      return _AtSpiNodeRead(
        node: <String, Object?>{
          'role': 'defunct',
          'visible': false,
          'children': <Map<String, Object?>>[],
        },
        children: const <_AtSpiReference>[],
      );
    }
  }

  Future<List<_AtSpiReference>> _readChildren(_AtSpiReference reference) async {
    try {
      return await _childrenOf(reference);
    } on Object {
      return const <_AtSpiReference>[];
    }
  }

  Future<Map<String, DBusValue>> _readAccessibleProperties(
    _AtSpiReference reference,
  ) async {
    try {
      return await _object(
        reference,
      ).getAllProperties('org.a11y.atspi.Accessible');
    } on Object {
      return const <String, DBusValue>{};
    }
  }

  Future<String> _readRole(_AtSpiReference reference) async {
    try {
      final object = _object(reference);
      return await cockpitReadLinuxAtSpiRole(
        (interface, method, values, {replySignature}) => object.callMethod(
          interface,
          method,
          values,
          replySignature: replySignature,
        ),
      );
    } on Object {
      return '';
    }
  }

  Future<List<_AtSpiReference>> _childrenOf(_AtSpiReference reference) async {
    final response = await _object(reference).callMethod(
      'org.a11y.atspi.Accessible',
      'GetChildren',
      const <DBusValue>[],
      replySignature: DBusSignature('a(so)'),
    );
    return response.returnValues.single
        .asArray()
        .map(_referenceFromValue)
        .whereType<_AtSpiReference>()
        .toList(growable: false);
  }

  Future<Set<String>> _readInterfaces(_AtSpiReference reference) async {
    try {
      final object = _object(reference);
      return await cockpitReadLinuxAtSpiInterfaces(
        (interface, method, values, {replySignature}) => object.callMethod(
          interface,
          method,
          values,
          replySignature: replySignature,
        ),
      );
    } on Object {
      return const <String>{};
    }
  }

  Future<Set<int>> _readStates(_AtSpiReference reference) async {
    try {
      final response = await _object(reference).callMethod(
        'org.a11y.atspi.Accessible',
        'GetState',
        const <DBusValue>[],
        replySignature: DBusSignature('au'),
      );
      final words = response.returnValues.single.asUint32Array().toList();
      final states = <int>{};
      for (var wordIndex = 0; wordIndex < words.length; wordIndex += 1) {
        final word = words[wordIndex];
        for (var bit = 0; bit < 32; bit += 1) {
          if ((word & (1 << bit)) != 0) states.add(wordIndex * 32 + bit);
        }
      }
      return states;
    } on Object {
      return const <int>{};
    }
  }

  Future<Map<String, int>?> _readFrame(_AtSpiReference reference) async {
    try {
      final response = await _object(reference).callMethod(
        'org.a11y.atspi.Component',
        'GetExtents',
        const <DBusValue>[DBusUint32(0)],
      );
      final values =
          response.returnValues.length == 1 &&
              response.returnValues.single.signature == DBusSignature('(iiii)')
          ? response.returnValues.single.asStruct()
          : response.returnValues;
      if (values.length != 4) return null;
      final x = values[0].asInt32();
      final y = values[1].asInt32();
      final width = values[2].asInt32();
      final height = values[3].asInt32();
      if (width <= 0 || height <= 0) return null;
      return <String, int>{'x': x, 'y': y, 'width': width, 'height': height};
    } on Object {
      return null;
    }
  }

  Future<DBusValue?> _accessibleProperty(
    _AtSpiReference reference,
    String name,
  ) async {
    try {
      return await _object(
        reference,
      ).getProperty('org.a11y.atspi.Accessible', name);
    } on Object {
      return null;
    }
  }

  DBusRemoteObject _object(_AtSpiReference reference) => DBusRemoteObject(
    _client,
    name: reference.bus,
    path: DBusObjectPath(reference.path),
  );
}

String _compactFailureReason(Object error) {
  final text = '$error'.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length <= 300 ? text : '${text.substring(0, 300)}…';
}

_AtSpiReference? _referenceFromValue(DBusValue value) {
  final fields = value.asStruct();
  if (fields.length != 2) return null;
  final bus = fields[0].asString().trim();
  final path = fields[1].asObjectPath().value;
  if (bus.isEmpty || path.isEmpty || path == '/') return null;
  return _AtSpiReference(bus: bus, path: path);
}

String? _stringValue(DBusValue? value) {
  if (value == null) return null;
  final text = value.asString().trim();
  return text.isEmpty ? null : text;
}

String _normalizeLinuxAtSpiInterface(String value) {
  final trimmed = value.trim();
  const prefix = 'org.a11y.atspi.';
  return trimmed.startsWith(prefix)
      ? trimmed.substring(prefix.length)
      : trimmed;
}

const List<String> _linuxAtSpiRoleNames = <String>[
  'invalid',
  'accelerator label',
  'alert',
  'animation',
  'arrow',
  'calendar',
  'canvas',
  'check box',
  'check menu item',
  'color chooser',
  'column header',
  'combo box',
  'date editor',
  'desktop icon',
  'desktop frame',
  'dial',
  'dialog',
  'directory pane',
  'drawing area',
  'file chooser',
  'filler',
  'focus traversable',
  'font chooser',
  'frame',
  'glass pane',
  'html container',
  'icon',
  'image',
  'internal frame',
  'label',
  'layered pane',
  'list',
  'list item',
  'menu',
  'menu bar',
  'menu item',
  'option pane',
  'page tab',
  'page tab list',
  'panel',
  'password text',
  'popup menu',
  'progress bar',
  'button',
  'radio button',
  'radio menu item',
  'root pane',
  'row header',
  'scroll bar',
  'scroll pane',
  'separator',
  'slider',
  'spin button',
  'split pane',
  'status bar',
  'table',
  'table cell',
  'table column header',
  'table row header',
  'tearoff menu item',
  'terminal',
  'text',
  'toggle button',
  'tool bar',
  'tool tip',
  'tree',
  'tree table',
  'unknown',
  'viewport',
  'window',
  'extended',
  'header',
  'footer',
  'paragraph',
  'ruler',
  'application',
  'autocomplete',
  'edit bar',
  'embedded',
  'entry',
  'chart',
  'caption',
  'document frame',
  'heading',
  'page',
  'section',
  'redundant object',
  'form',
  'link',
  'input method window',
  'table row',
  'tree item',
  'document spreadsheet',
  'document presentation',
  'document text',
  'document web',
  'document email',
  'comment',
  'list box',
  'grouping',
  'image map',
  'notification',
  'info bar',
  'level bar',
  'title bar',
  'block quote',
  'audio',
  'video',
  'definition',
  'article',
  'landmark',
  'log',
  'marquee',
  'math',
  'rating',
  'timer',
  'static',
  'math fraction',
  'math root',
  'subscript',
  'superscript',
  'description list',
  'description term',
  'description value',
  'footnote',
  'content deletion',
  'content insertion',
  'mark',
  'suggestion',
  'push button menu',
  'switch',
  'last defined',
];

Set<String> _processIdentities(int processId) {
  if (!Platform.isLinux || processId <= 0) return const <String>{};
  final identities = <String>{};
  try {
    final cmdline = File('/proc/$processId/cmdline').readAsStringSync();
    for (final part in cmdline.split('\u0000')) {
      final value = part.trim().toLowerCase();
      if (value.isEmpty) continue;
      identities.add(value);
      identities.add(value.split('/').last);
    }
  } on Object {
    // A short-lived application may disappear between registry and /proc reads.
  }
  try {
    final comm = File('/proc/$processId/comm').readAsStringSync().trim();
    if (comm.isNotEmpty) identities.add(comm.toLowerCase());
  } on Object {
    // The AT-SPI accessible name remains available when /proc is restricted.
  }
  return identities;
}

final class _AtSpiReference {
  const _AtSpiReference({required this.bus, required this.path});

  final String bus;
  final String path;
}

final class _AtSpiTarget {
  const _AtSpiTarget({
    required this.reference,
    required this.processId,
    required this.name,
  });

  final _AtSpiReference reference;
  final int processId;
  final String name;
}

final class _AtSpiPendingNode {
  const _AtSpiPendingNode({
    required this.reference,
    required this.parent,
    required this.depth,
  });

  final _AtSpiReference reference;
  final int? parent;
  final int depth;
}

final class _AtSpiNodeRead {
  const _AtSpiNodeRead({required this.node, required this.children});

  final Map<String, Object?> node;
  final List<_AtSpiReference> children;
}

final class _AtSpiNodeRecord {
  const _AtSpiNodeRecord({required this.parent, required this.node});

  final int? parent;
  final Map<String, Object?> node;
}
