import 'package:http/http.dart' as http;

abstract interface class CockpitHttpClient {
  Future<String> read(Uri uri);

  Future<List<int>> readBytes(Uri uri);

  Future<void> close() async {}
}

final class DefaultCockpitHttpClient implements CockpitHttpClient {
  DefaultCockpitHttpClient({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<void> close() async => _client.close();

  @override
  Future<String> read(Uri uri) async {
    final response = await _client.get(uri);
    _checkResponse(response, uri);
    return response.body;
  }

  @override
  Future<List<int>> readBytes(Uri uri) async {
    final response = await _client.get(uri);
    _checkResponse(response, uri);
    return response.bodyBytes;
  }

  void _checkResponse(http.Response response, Uri uri) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw StateError(
      'HTTP request to $uri failed with status ${response.statusCode}.',
    );
  }
}
