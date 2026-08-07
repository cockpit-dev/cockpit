final class CockpitSession {
  /// Creates a CockpitSession.
  const CockpitSession({
    required this.sessionId,
    required this.taskId,
    required this.platform,
    required this.startedAt,
  });

  final String sessionId;
  final String taskId;
  final String platform;
  final DateTime startedAt;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitSession &&
            other.sessionId == sessionId &&
            other.taskId == taskId &&
            other.platform == platform &&
            other.startedAt == startedAt;
  }

  @override
  int get hashCode => Object.hash(sessionId, taskId, platform, startedAt);
}
