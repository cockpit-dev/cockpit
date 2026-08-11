import 'package:collection/collection.dart';

import '../control/cockpit_command_type.dart';
import '../foundation/cockpit_foundation_value_reader.dart';

enum CockpitWidgetTreeProfile {
  minimal('minimal'),
  standard('standard'),
  full('full');

  /// Creates a [CockpitWidgetTreeProfile] with its serialized value.
  const CockpitWidgetTreeProfile(this.jsonValue);

  /// Value used by JSON, LON, and YAML projections.
  final String jsonValue;

  /// Decodes a widget-tree profile from its serialized value.
  static CockpitWidgetTreeProfile fromJson(Object? json) {
    return values.firstWhere(
      (profile) => profile.jsonValue == json,
      orElse: () => throw ArgumentError.value(
        json,
        'json',
        'Unsupported widget tree profile.',
      ),
    );
  }
}

final class CockpitWidgetTreeOptions {
  /// Creates bounded widget-tree capture options.
  const CockpitWidgetTreeOptions({
    this.profile = CockpitWidgetTreeProfile.minimal,
    this.maxNodes = 800,
    this.maxProps = 0,
  });

  /// Creates the concise actionable/content tree profile.
  const CockpitWidgetTreeOptions.minimal()
    : this(profile: CockpitWidgetTreeProfile.minimal);

  /// Creates the mounted public Widget structure profile.
  const CockpitWidgetTreeOptions.standard()
    : this(profile: CockpitWidgetTreeProfile.standard, maxNodes: 5000);

  /// Creates the complete mounted Element diagnostics profile.
  const CockpitWidgetTreeOptions.full()
    : this(
        profile: CockpitWidgetTreeProfile.full,
        maxNodes: 100000,
        maxProps: 24,
      );

  /// Detail profile applied while selecting and projecting nodes.
  final CockpitWidgetTreeProfile profile;

  /// Maximum number of nodes emitted in the response or artifact.
  final int maxNodes;

  /// Maximum diagnostic properties emitted per node.
  final int maxProps;

  /// Encodes these options as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'profile': profile.jsonValue,
    'maxNodes': maxNodes,
    'maxProps': maxProps,
  };

  /// Decodes widget-tree capture options from a JSON object.
  factory CockpitWidgetTreeOptions.fromJson(Map<String, Object?> json) {
    CockpitFoundationValueReader.keys(json, const <String>{
      'profile',
      'maxNodes',
      'maxProps',
    }, r'$');
    return CockpitWidgetTreeOptions(
      profile: json['profile'] == null
          ? CockpitWidgetTreeProfile.minimal
          : CockpitWidgetTreeProfile.fromJson(json['profile']),
      maxNodes: json['maxNodes'] == null
          ? 800
          : CockpitFoundationValueReader.integer(
              json['maxNodes'],
              r'$.maxNodes',
              min: 1,
              max: 500000,
            ),
      maxProps: json['maxProps'] == null
          ? 0
          : CockpitFoundationValueReader.integer(
              json['maxProps'],
              r'$.maxProps',
              min: 0,
              max: 256,
            ),
    );
  }

  /// Returns a copy with the supplied fields replaced.
  CockpitWidgetTreeOptions copyWith({
    CockpitWidgetTreeProfile? profile,
    int? maxNodes,
    int? maxProps,
  }) => CockpitWidgetTreeOptions(
    profile: profile ?? this.profile,
    maxNodes: maxNodes ?? this.maxNodes,
    maxProps: maxProps ?? this.maxProps,
  );

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitWidgetTreeOptions &&
            other.profile == profile &&
            other.maxNodes == maxNodes &&
            other.maxProps == maxProps;
  }

  @override
  int get hashCode => Object.hash(profile, maxNodes, maxProps);
}

final class CockpitWidgetBounds {
  /// Creates global logical bounds for a mounted Widget node.
  const CockpitWidgetBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.constraints,
  });

  /// Global logical x coordinate.
  final double x;

  /// Global logical y coordinate.
  final double y;

  /// Logical width.
  final double width;

  /// Logical height.
  final double height;

  /// Bounded render constraints included by the full profile.
  final String? constraints;

  /// Encodes these bounds as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    if (constraints != null) 'constraints': constraints,
  };

  /// Decodes Widget bounds from a JSON object.
  factory CockpitWidgetBounds.fromJson(Map<String, Object?> json) {
    return CockpitWidgetBounds(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      constraints: json['constraints'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitWidgetBounds &&
            other.x == x &&
            other.y == y &&
            other.width == width &&
            other.height == height &&
            other.constraints == constraints;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height, constraints);
}

final class CockpitWidgetProperty {
  /// Creates one bounded diagnostic property.
  const CockpitWidgetProperty({required this.name, required this.value});

  /// Diagnostic property name.
  final String name;

  /// Normalized bounded diagnostic value.
  final String value;

  /// Encodes this property as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'value': value,
  };

  /// Decodes a Widget diagnostic property from a JSON object.
  factory CockpitWidgetProperty.fromJson(Map<String, Object?> json) {
    return CockpitWidgetProperty(
      name: json['name']! as String,
      value: json['value']! as String,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitWidgetProperty &&
            other.name == name &&
            other.value == value;
  }

  @override
  int get hashCode => Object.hash(name, value);
}

final class CockpitWidgetNode {
  /// Creates one node in a mounted Flutter Widget tree projection.
  CockpitWidgetNode({
    required this.node,
    this.loc,
    this.parent,
    required this.depth,
    required this.type,
    this.element,
    this.state,
    this.render,
    this.cockpitId,
    this.semanticId,
    this.key,
    this.text,
    this.tip,
    this.route,
    required this.visible,
    required this.offstage,
    this.bounds,
    this.scroll,
    List<CockpitCommandType> actions = const <CockpitCommandType>[],
    List<CockpitWidgetProperty> props = const <CockpitWidgetProperty>[],
  }) : actions = List.unmodifiable(actions),
       props = List.unmodifiable(props);

  /// Stable node number within this tree capture.
  final int node;

  /// Opaque structural locator path, when the node is actionable.
  final String? loc;

  /// Nearest emitted parent node number.
  final int? parent;

  /// Depth in the complete mounted Element tree.
  final int depth;

  /// Runtime Widget type.
  final String type;

  /// Runtime Element type included by the full profile.
  final String? element;

  /// Runtime State type included by the full profile.
  final String? state;

  /// Runtime RenderObject type included by standard and full profiles.
  final String? render;

  /// Cockpit identifier discovered for the node.
  final String? cockpitId;

  /// Optional Semantics identifier discovered for the node.
  final String? semanticId;

  /// Stable public Widget key value, when available.
  final String? key;

  /// Direct normalized Widget text.
  final String? text;

  /// Direct normalized tooltip text.
  final String? tip;

  /// Current route owning the captured surface.
  final String? route;

  /// Whether the node is mounted, laid out, and intersects the root viewport.
  final bool visible;

  /// Whether this node is below an active `Offstage` boundary.
  final bool offstage;

  /// Global logical bounds, when a RenderBox is available.
  final CockpitWidgetBounds? bounds;

  /// Nearest scrollable ancestor node number, including this node if scrollable.
  final int? scroll;

  /// Commands currently advertised for this node.
  final List<CockpitCommandType> actions;

  /// Bounded diagnostic properties included by the full profile.
  final List<CockpitWidgetProperty> props;

  static const ListEquality<CockpitCommandType> _actionEquality =
      ListEquality<CockpitCommandType>();
  static const ListEquality<CockpitWidgetProperty> _propertyEquality =
      ListEquality<CockpitWidgetProperty>();

  /// Encodes this Widget node as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'node': node,
    if (loc != null) 'loc': loc,
    if (parent != null) 'parent': parent,
    'depth': depth,
    'type': type,
    if (element != null) 'element': element,
    if (state != null) 'state': state,
    if (render != null) 'render': render,
    if (cockpitId != null) 'cockpitId': cockpitId,
    if (semanticId != null) 'semanticId': semanticId,
    if (key != null) 'key': key,
    if (text != null) 'text': text,
    if (tip != null) 'tip': tip,
    if (route != null) 'route': route,
    'visible': visible,
    'offstage': offstage,
    if (bounds != null) 'bounds': bounds!.toJson(),
    if (scroll != null) 'scroll': scroll,
    if (actions.isNotEmpty)
      'actions': actions.map((action) => action.name).toList(growable: false),
    if (props.isNotEmpty)
      'props': props
          .map((property) => property.toJson())
          .toList(growable: false),
  };

  /// Decodes a Widget node from a JSON object.
  factory CockpitWidgetNode.fromJson(Map<String, Object?> json) {
    final boundsJson = json['bounds'] as Map<Object?, Object?>?;
    return CockpitWidgetNode(
      node: json['node']! as int,
      loc: json['loc'] as String?,
      parent: json['parent'] as int?,
      depth: json['depth']! as int,
      type: json['type']! as String,
      element: json['element'] as String?,
      state: json['state'] as String?,
      render: json['render'] as String?,
      cockpitId: json['cockpitId'] as String?,
      semanticId: json['semanticId'] as String?,
      key: json['key'] as String?,
      text: json['text'] as String?,
      tip: json['tip'] as String?,
      route: json['route'] as String?,
      visible: json['visible'] as bool? ?? false,
      offstage: json['offstage'] as bool? ?? false,
      bounds: boundsJson == null
          ? null
          : CockpitWidgetBounds.fromJson(Map<String, Object?>.from(boundsJson)),
      scroll: json['scroll'] as int?,
      actions: (json['actions'] as List<Object?>? ?? const <Object?>[])
          .map(CockpitCommandType.fromJson)
          .toList(growable: false),
      props: (json['props'] as List<Object?>? ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (property) => CockpitWidgetProperty.fromJson(
              Map<String, Object?>.from(property),
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitWidgetNode &&
            other.node == node &&
            other.loc == loc &&
            other.parent == parent &&
            other.depth == depth &&
            other.type == type &&
            other.element == element &&
            other.state == state &&
            other.render == render &&
            other.cockpitId == cockpitId &&
            other.semanticId == semanticId &&
            other.key == key &&
            other.text == text &&
            other.tip == tip &&
            other.route == route &&
            other.visible == visible &&
            other.offstage == offstage &&
            other.bounds == bounds &&
            other.scroll == scroll &&
            _actionEquality.equals(other.actions, actions) &&
            _propertyEquality.equals(other.props, props);
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    node,
    loc,
    parent,
    depth,
    type,
    element,
    state,
    render,
    cockpitId,
    semanticId,
    key,
    text,
    tip,
    route,
    visible,
    offstage,
    bounds,
    scroll,
    _actionEquality.hash(actions),
    _propertyEquality.hash(props),
  ]);
}

final class CockpitWidgetTree {
  /// Creates one bounded mounted Flutter Widget tree projection.
  CockpitWidgetTree({
    required this.profile,
    required this.total,
    required this.visible,
    required this.truncated,
    int? emitted,
    List<CockpitWidgetNode> nodes = const <CockpitWidgetNode>[],
  }) : nodes = List.unmodifiable(nodes),
       emitted = emitted ?? nodes.length;

  /// Detail profile used to create this tree.
  final CockpitWidgetTreeProfile profile;

  /// Total mounted Element count before profile filtering and truncation.
  final int total;

  /// Total mounted nodes visible through the root viewport.
  final int visible;

  /// Whether profile-selected nodes exceeded the emitted node limit.
  final bool truncated;

  /// Number of nodes emitted in [nodes].
  final int emitted;

  /// Profile-selected mounted Widget nodes.
  final List<CockpitWidgetNode> nodes;

  static const ListEquality<CockpitWidgetNode> _nodeEquality =
      ListEquality<CockpitWidgetNode>();

  /// Encodes this Widget tree as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'profile': profile.jsonValue,
    'total': total,
    'visible': visible,
    'emitted': emitted,
    'truncated': truncated,
    'nodes': nodes.map((node) => node.toJson()).toList(growable: false),
  };

  /// Decodes a Widget tree from a JSON object.
  factory CockpitWidgetTree.fromJson(Map<String, Object?> json) {
    return CockpitWidgetTree(
      profile: CockpitWidgetTreeProfile.fromJson(json['profile']),
      total: json['total']! as int,
      visible: json['visible']! as int,
      truncated: json['truncated'] as bool? ?? false,
      emitted: json['emitted'] as int?,
      nodes: (json['nodes'] as List<Object?>? ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (node) =>
                CockpitWidgetNode.fromJson(Map<String, Object?>.from(node)),
          )
          .toList(growable: false),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitWidgetTree &&
            other.profile == profile &&
            other.total == total &&
            other.visible == visible &&
            other.truncated == truncated &&
            other.emitted == emitted &&
            _nodeEquality.equals(other.nodes, nodes);
  }

  @override
  int get hashCode => Object.hash(
    profile,
    total,
    visible,
    truncated,
    emitted,
    _nodeEquality.hash(nodes),
  );
}
