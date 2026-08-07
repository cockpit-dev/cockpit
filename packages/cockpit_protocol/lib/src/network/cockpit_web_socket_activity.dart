import 'package:collection/collection.dart';

enum CockpitWebSocketDirection { sent, received }

enum CockpitWebSocketFrameKind { continuation, text, binary, close, ping, pong }

final class CockpitWebSocketFrame {
  /// Creates a CockpitWebSocketFrame.
  const CockpitWebSocketFrame({
    required this.sequence,
    required this.direction,
    required this.kind,
    required this.at,
    required this.payloadBytes,
    required this.finalFragment,
    required this.compressed,
    this.preview,
  });

  final int sequence;
  final CockpitWebSocketDirection direction;
  final CockpitWebSocketFrameKind kind;
  final DateTime at;
  final int payloadBytes;
  final bool finalFragment;
  final bool compressed;
  final String? preview;

  /// Encodes this CockpitWebSocketFrame as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'sequence': sequence,
    'direction': direction.name,
    'kind': kind.name,
    'at': at.toUtc().toIso8601String(),
    'payloadBytes': payloadBytes,
    'finalFragment': finalFragment,
    'compressed': compressed,
    if (preview != null) 'preview': preview,
  };

  /// Decodes a CockpitWebSocketFrame from a JSON object.
  factory CockpitWebSocketFrame.fromJson(Map<String, Object?> json) {
    return CockpitWebSocketFrame(
      sequence: json['sequence']! as int,
      direction: CockpitWebSocketDirection.values.byName(
        json['direction']! as String,
      ),
      kind: CockpitWebSocketFrameKind.values.byName(json['kind']! as String),
      at: DateTime.parse(json['at']! as String).toUtc(),
      payloadBytes: json['payloadBytes']! as int,
      finalFragment: json['finalFragment'] as bool? ?? true,
      compressed: json['compressed'] as bool? ?? false,
      preview: json['preview'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CockpitWebSocketFrame &&
          other.sequence == sequence &&
          other.direction == direction &&
          other.kind == kind &&
          other.at == at &&
          other.payloadBytes == payloadBytes &&
          other.finalFragment == finalFragment &&
          other.compressed == compressed &&
          other.preview == preview;

  @override
  int get hashCode => Object.hash(
    sequence,
    direction,
    kind,
    at,
    payloadBytes,
    finalFragment,
    compressed,
    preview,
  );
}

final class CockpitWebSocketActivity {
  /// Creates a CockpitWebSocketActivity.
  const CockpitWebSocketActivity({
    required this.sentFrames,
    required this.receivedFrames,
    required this.sentBytes,
    required this.receivedBytes,
    required this.recentFrames,
    this.framesTruncated = false,
  });

  final int sentFrames;
  final int receivedFrames;
  final int sentBytes;
  final int receivedBytes;
  final List<CockpitWebSocketFrame> recentFrames;
  final bool framesTruncated;

  static const ListEquality<CockpitWebSocketFrame> _framesEquality =
      ListEquality<CockpitWebSocketFrame>();

  /// Encodes this CockpitWebSocketActivity as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'sentFrames': sentFrames,
    'receivedFrames': receivedFrames,
    'sentBytes': sentBytes,
    'receivedBytes': receivedBytes,
    'recentFrames': recentFrames.map((frame) => frame.toJson()).toList(),
    'framesTruncated': framesTruncated,
  };

  /// Decodes a CockpitWebSocketActivity from a JSON object.
  factory CockpitWebSocketActivity.fromJson(Map<String, Object?> json) {
    return CockpitWebSocketActivity(
      sentFrames: json['sentFrames'] as int? ?? 0,
      receivedFrames: json['receivedFrames'] as int? ?? 0,
      sentBytes: json['sentBytes'] as int? ?? 0,
      receivedBytes: json['receivedBytes'] as int? ?? 0,
      recentFrames: (json['recentFrames'] as List<Object?>? ?? const [])
          .map(
            (frame) => CockpitWebSocketFrame.fromJson(
              Map<String, Object?>.from(frame! as Map<Object?, Object?>),
            ),
          )
          .toList(growable: false),
      framesTruncated: json['framesTruncated'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CockpitWebSocketActivity &&
          other.sentFrames == sentFrames &&
          other.receivedFrames == receivedFrames &&
          other.sentBytes == sentBytes &&
          other.receivedBytes == receivedBytes &&
          _framesEquality.equals(other.recentFrames, recentFrames) &&
          other.framesTruncated == framesTruncated;

  @override
  int get hashCode => Object.hash(
    sentFrames,
    receivedFrames,
    sentBytes,
    receivedBytes,
    _framesEquality.hash(recentFrames),
    framesTruncated,
  );
}
