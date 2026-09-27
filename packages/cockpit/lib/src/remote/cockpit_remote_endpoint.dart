final class CockpitRemoteEndpoint {
  const CockpitRemoteEndpoint({required this.baseUri, required this.authToken});

  final Uri baseUri;
  final String authToken;
}

CockpitRemoteEndpoint cockpitResolveRemoteEndpoint({
  required Uri baseUri,
  Iterable<String?> authTokens = const <String?>[],
  String path = 'remote endpoint',
}) {
  final tokens = <String>{};
  for (final authToken in authTokens) {
    final normalized = authToken?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      tokens.add(normalized);
    }
  }

  final queryTokens = baseUri.queryParametersAll['token'];
  if (queryTokens != null) {
    for (final queryToken in queryTokens) {
      final normalized = queryToken.trim();
      if (normalized.isNotEmpty) {
        tokens.add(normalized);
      }
    }
  }

  if (tokens.length > 1) {
    throw FormatException('Conflicting remote authentication tokens at $path.');
  }

  return CockpitRemoteEndpoint(
    baseUri: queryTokens == null ? baseUri : _withoutTokenQuery(baseUri),
    authToken: tokens.isEmpty ? '' : tokens.first,
  );
}

Uri _withoutTokenQuery(Uri uri) {
  final queryParameters = <String, Object?>{
    for (final entry in uri.queryParametersAll.entries)
      if (entry.key != 'token') entry.key: entry.value,
  };
  if (queryParameters.isEmpty) {
    final text = uri.toString();
    final queryStart = text.indexOf('?');
    if (queryStart < 0) return uri;
    final fragmentStart = text.indexOf('#', queryStart);
    return Uri.parse(
      fragmentStart < 0
          ? text.substring(0, queryStart)
          : '${text.substring(0, queryStart)}${text.substring(fragmentStart)}',
    );
  }
  return uri.replace(queryParameters: queryParameters);
}
