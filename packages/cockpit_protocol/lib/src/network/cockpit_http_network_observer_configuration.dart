final class CockpitHttpNetworkObserverConfiguration {
  /// Creates a CockpitHttpNetworkObserverConfiguration.
  const CockpitHttpNetworkObserverConfiguration({
    this.maxRetainedEntries = 200,
    this.maxHeaderCount = 24,
    this.maxHeaderValueLength = 256,
    this.maxBodyBytes = 4096,
    this.captureHeaders = true,
    this.captureBodies = true,
    this.redact = true,
    this.maxWebSocketFrames = 24,
    this.maxWebSocketPreviewBytes = 1024,
  });

  final int maxRetainedEntries;
  final int maxHeaderCount;
  final int maxHeaderValueLength;
  final int maxBodyBytes;
  final bool captureHeaders;
  final bool captureBodies;
  final int maxWebSocketFrames;
  final int maxWebSocketPreviewBytes;

  /// Removes credential values from captured diagnostics by default.
  ///
  /// Set this to false only in a development-only entrypoint when the raw
  /// request and response values are required for local diagnosis.
  final bool redact;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitHttpNetworkObserverConfiguration &&
            other.maxRetainedEntries == maxRetainedEntries &&
            other.maxHeaderCount == maxHeaderCount &&
            other.maxHeaderValueLength == maxHeaderValueLength &&
            other.maxBodyBytes == maxBodyBytes &&
            other.captureHeaders == captureHeaders &&
            other.captureBodies == captureBodies &&
            other.maxWebSocketFrames == maxWebSocketFrames &&
            other.maxWebSocketPreviewBytes == maxWebSocketPreviewBytes &&
            other.redact == redact;
  }

  @override
  int get hashCode => Object.hash(
    maxRetainedEntries,
    maxHeaderCount,
    maxHeaderValueLength,
    maxBodyBytes,
    captureHeaders,
    captureBodies,
    maxWebSocketFrames,
    maxWebSocketPreviewBytes,
    redact,
  );
}
