import 'cockpit_decode_policy.dart';
import 'cockpit_foundation_constraints.dart';
import 'cockpit_foundation_value_reader.dart';

final class CockpitPageRequest {
  /// Creates a CockpitPageRequest.
  CockpitPageRequest({this.limit = 50, this.cursor}) {
    if (limit < 1 || limit > cockpitFoundationPageSizeMaximum) {
      throw const FormatException('Page limit must be between 1 and 100.');
    }
    if (cursor != null) {
      CockpitFoundationValueReader.opaqueToken(cursor, r'$.cursor');
    }
  }

  final int limit;
  final String? cursor;

  /// Encodes this CockpitPageRequest as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'limit': limit,
    if (cursor != null) 'cursor': cursor,
  };

  /// Decodes a CockpitPageRequest from a JSON object.
  factory CockpitPageRequest.fromJson(Object? value, {String path = r'$'}) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(json, const <String>{
      'limit',
      'cursor',
    }, path);
    return CockpitPageRequest(
      limit: json['limit'] == null
          ? 50
          : CockpitFoundationValueReader.integer(
              json['limit'],
              '$path.limit',
              min: 1,
              max: cockpitFoundationPageSizeMaximum,
            ),
      cursor: json['cursor'] == null
          ? null
          : CockpitFoundationValueReader.opaqueToken(
              json['cursor'],
              '$path.cursor',
            ),
    );
  }
}

final class CockpitPage<T> {
  /// Creates a CockpitPage.
  CockpitPage({required Iterable<T> items, this.nextCursor, this.totalCount})
    : items = List<T>.unmodifiable(items) {
    if (this.items.length > cockpitFoundationPageSizeMaximum) {
      throw const FormatException('Page cannot contain more than 100 items.');
    }
    if (nextCursor != null) {
      CockpitFoundationValueReader.opaqueToken(nextCursor, r'$.nextCursor');
    }
    if (totalCount != null && totalCount! < this.items.length) {
      throw const FormatException('Page totalCount is smaller than items.');
    }
  }

  final List<T> items;
  final String? nextCursor;
  final int? totalCount;

  /// Encodes this CockpitPage as a JSON object.
  Map<String, Object?> toJson(Object? Function(T item) encodeItem) =>
      <String, Object?>{
        'items': items.map(encodeItem).toList(),
        if (nextCursor != null) 'nextCursor': nextCursor,
        if (totalCount != null) 'totalCount': totalCount,
      };

  static CockpitPage<T> fromJson<T>(
    Object? value,
    T Function(Object? value, String path, CockpitDecodePolicy policy)
    decodeItem, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{'items', 'nextCursor', 'totalCount'},
      path,
      required: const <String>{'items'},
      policy: decodePolicy,
    );
    final rawItems = CockpitFoundationValueReader.list(
      json['items'],
      '$path.items',
    );
    return CockpitPage<T>(
      items: <T>[
        for (var index = 0; index < rawItems.length; index += 1)
          decodeItem(rawItems[index], '$path.items[$index]', decodePolicy),
      ],
      nextCursor: json['nextCursor'] == null
          ? null
          : CockpitFoundationValueReader.opaqueToken(
              json['nextCursor'],
              '$path.nextCursor',
            ),
      totalCount: json['totalCount'] == null
          ? null
          : CockpitFoundationValueReader.integer(
              json['totalCount'],
              '$path.totalCount',
              min: 0,
            ),
    );
  }
}
