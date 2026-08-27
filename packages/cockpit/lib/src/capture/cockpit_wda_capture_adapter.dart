import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../system_control/cockpit_ios_webdriver_agent_client.dart';
import 'cockpit_host_capture_adapter.dart';

final class CockpitWdaCaptureAdapter implements CockpitHostCaptureAdapter {
  CockpitWdaCaptureAdapter({
    required this.baseUri,
    CockpitIosWebDriverAgentClient? client,
    CockpitCaptureTempFileFactory tempFileFactory =
        cockpitCreateCaptureTempFile,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? CockpitIosWebDriverAgentClient(),
       _tempFileFactory = tempFileFactory;

  final Uri baseUri;
  final CockpitIosWebDriverAgentClient _client;
  final CockpitCaptureTempFileFactory _tempFileFactory;
  final Duration timeout;

  @override
  Future<CockpitCommandExecution> capture(CockpitCommand command) async {
    final request = command.screenshotRequest;
    if (request == null) {
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: 0,
        message: 'WebDriverAgent capture requires a screenshot request.',
      );
    }
    final stopwatch = Stopwatch()..start();
    final artifact = cockpitCaptureArtifactForRequest(request);
    final outputFile = await _tempFileFactory(
      cockpitCaptureFileName(request.name),
    );
    try {
      await outputFile.parent.create(recursive: true);
      final bytes = await _client.captureScreenshot(baseUri, timeout: timeout);
      await outputFile.writeAsBytes(bytes, flush: true);
      return await cockpitValidateHostCaptureOutput(
        command: command,
        artifact: artifact,
        durationMs: stopwatch.elapsedMilliseconds,
        outputFile: outputFile,
        captureDescription: 'WebDriverAgent screenshot',
      );
    } on Object catch (error) {
      if (await outputFile.exists()) await outputFile.delete();
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: 'WebDriverAgent screenshot failed.',
        details: <String, Object?>{'error': error.toString()},
      );
    }
  }
}
