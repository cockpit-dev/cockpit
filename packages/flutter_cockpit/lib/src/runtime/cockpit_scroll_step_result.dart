final class CockpitScrollStepResult {
  const CockpitScrollStepResult({
    required this.didScroll,
    this.strategy = 'none',
    this.scrollableKey,
    this.scrollablePath,
    this.scrollableTypeName,
    this.scrollableCandidateIndex,
    this.scrollableCandidateCount,
    this.pixelsBefore,
    this.pixelsAfter,
    this.nextPixels,
    this.minScrollExtent,
    this.maxScrollExtent,
    this.viewportDimension,
    this.acceptsUserOffset,
    this.allowsProgrammaticScroll,
    this.hadGestureTarget = false,
    this.hadSemanticAction = false,
    this.matchedRegistryTarget = false,
    this.targetVisibilityObserved = false,
    this.targetMounted = false,
    this.targetVisible = false,
  });

  final bool didScroll;
  final String strategy;
  final String? scrollableKey;
  final String? scrollablePath;
  final String? scrollableTypeName;
  final int? scrollableCandidateIndex;
  final int? scrollableCandidateCount;
  final double? pixelsBefore;
  final double? pixelsAfter;
  final double? nextPixels;
  final double? minScrollExtent;
  final double? maxScrollExtent;
  final double? viewportDimension;
  final bool? acceptsUserOffset;
  final bool? allowsProgrammaticScroll;
  final bool hadGestureTarget;
  final bool hadSemanticAction;
  final bool matchedRegistryTarget;
  final bool targetVisibilityObserved;
  final bool targetMounted;
  final bool targetVisible;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'didScroll': didScroll,
      'strategy': strategy,
      if (scrollableKey != null) 'scrollableKey': scrollableKey,
      if (scrollablePath != null) 'scrollablePath': scrollablePath,
      if (scrollableTypeName != null) 'scrollableTypeName': scrollableTypeName,
      if (scrollableCandidateIndex != null)
        'scrollableCandidateIndex': scrollableCandidateIndex,
      if (scrollableCandidateCount != null)
        'scrollableCandidateCount': scrollableCandidateCount,
      if (pixelsBefore != null) 'pixelsBefore': pixelsBefore,
      if (pixelsAfter != null) 'pixelsAfter': pixelsAfter,
      if (nextPixels != null) 'nextPixels': nextPixels,
      if (minScrollExtent != null) 'minScrollExtent': minScrollExtent,
      if (maxScrollExtent != null) 'maxScrollExtent': maxScrollExtent,
      if (viewportDimension != null) 'viewportDimension': viewportDimension,
      if (acceptsUserOffset != null) 'acceptsUserOffset': acceptsUserOffset,
      if (allowsProgrammaticScroll != null)
        'allowsProgrammaticScroll': allowsProgrammaticScroll,
      'hadGestureTarget': hadGestureTarget,
      'hadSemanticAction': hadSemanticAction,
      'matchedRegistryTarget': matchedRegistryTarget,
      if (targetVisibilityObserved) 'targetVisibilityObserved': true,
      if (targetMounted) 'targetMounted': true,
      if (targetVisible) 'targetVisible': true,
    };
  }
}
