import 'package:flutter_test/flutter_test.dart';

import '../cockpit/cockpit_bootstrap.dart';

void main() {
  test('development network capture excludes only local Cockpit control', () {
    expect(
      captureConsoleNetworkRequest(
        'GET',
        Uri.parse('http://127.0.0.1:47331/api/v2/workspaces'),
      ),
      isFalse,
    );
    expect(
      captureConsoleNetworkRequest(
        'GET',
        Uri.parse('http://localhost:47331/_cockpit/health'),
      ),
      isFalse,
    );
    expect(
      captureConsoleNetworkRequest(
        'GET',
        Uri.parse('http://[::1]:47331/_cockpit/lifecycle'),
      ),
      isFalse,
    );
    expect(
      captureConsoleNetworkRequest(
        'GET',
        Uri.parse('http://127.0.0.1:8080/application/data'),
      ),
      isTrue,
    );
    expect(
      captureConsoleNetworkRequest(
        'GET',
        Uri.parse('https://example.test/_cockpit/health'),
      ),
      isTrue,
    );
  });
}
