import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  final frames = <CockpitPerformanceFrame>[
    const CockpitPerformanceFrame(
      index: 0,
      timestampUs: 100,
      wallTimeUs: 900,
      buildUs: 4000,
      rasterUs: 5000,
      vsyncUs: 1000,
      totalUs: 10000,
      layerCount: 2,
      layerBytes: 10,
      pictureCount: 3,
      pictureBytes: 20,
      frameNumber: 7,
      buildStartUs: 150,
      buildFinishUs: 4150,
      rasterStartUs: 4200,
      rasterFinishUs: 10100,
    ),
    const CockpitPerformanceFrame(
      index: 1,
      timestampUs: 17100,
      wallTimeUs: 17900,
      buildUs: 20000,
      rasterUs: 3000,
      vsyncUs: 1000,
      totalUs: 26000,
      layerCount: 4,
      layerBytes: 40,
      pictureCount: 5,
      pictureBytes: 50,
    ),
  ];

  test('summary derives jank, percentiles, cache peaks, and observed fps', () {
    final summary = CockpitPerformanceSummary.fromFrames(
      frames,
      frameBudgetUs: 16667,
    );

    expect(summary.frameCount, 2);
    expect(summary.build.sampleCount, 2);
    expect(summary.jankCount, 1);
    expect(summary.fps, closeTo(58.8235, 0.001));
    expect(summary.build.missedBudget, 1);
    expect(summary.total.p90Us, 24400);
    expect(summary.total.missedBudget, 1);
    expect(summary.build.budgetUs, 16667);
    expect(summary.layerCacheMax, <String, int>{'count': 4, 'bytes': 40});
    expect(summary.pictureCacheMax, <String, int>{'count': 5, 'bytes': 50});
    expect(summary.toJson()['build'], containsPair('n', 2));
  });

  test('jank uses total span and repeated timestamps do not fabricate fps', () {
    final summary =
        CockpitPerformanceSummary.fromFrames(<CockpitPerformanceFrame>[
          const CockpitPerformanceFrame(
            index: 0,
            timestampUs: 0,
            wallTimeUs: 0,
            buildUs: 1000,
            rasterUs: 1000,
            vsyncUs: 1000,
            totalUs: 20000,
            layerCount: 0,
            layerBytes: 0,
            pictureCount: 0,
            pictureBytes: 0,
          ),
          const CockpitPerformanceFrame(
            index: 1,
            timestampUs: 0,
            wallTimeUs: 16000,
            buildUs: 1000,
            rasterUs: 1000,
            vsyncUs: 1000,
            totalUs: 1000,
            layerCount: 0,
            layerBytes: 0,
            pictureCount: 0,
            pictureBytes: 0,
          ),
        ], frameBudgetUs: 16667);

    expect(summary.jankCount, 1);
    expect(summary.fps, isNull);
  });

  test('empty summary does not invent fps', () {
    final summary = CockpitPerformanceSummary.fromFrames(
      const <CockpitPerformanceFrame>[],
      frameBudgetUs: 16667,
    );

    expect(summary.frameCount, 0);
    expect(summary.fps, isNull);
    expect(summary.toJson().containsKey('fps'), isFalse);
    expect(summary.toJson()['build'], <String, Object?>{'n': 0, 'bud': 16667});
  });

  test('report rejects inconsistent duration and frame counts', () {
    final summary = CockpitPerformanceSummary.fromFrames(
      frames,
      frameBudgetUs: 16667,
    );
    final start = DateTime.utc(2026, 1, 1);

    expect(
      () => CockpitPerformanceReport(
        startedAt: start,
        finishedAt: start.add(const Duration(milliseconds: 10)),
        durationUs: 10000,
        durationMs: 9,
        platform: 'test',
        buildMode: 'profile',
        mode: CockpitPerformanceMode.light,
        summary: summary,
        frames: frames,
      ),
      throwsFormatException,
    );
    expect(
      () => CockpitPerformanceReport(
        startedAt: start,
        finishedAt: start,
        durationUs: 0,
        durationMs: 0,
        platform: 'test',
        buildMode: 'profile',
        mode: CockpitPerformanceMode.light,
        summary: summary,
        frames: const <CockpitPerformanceFrame>[],
      ),
      throwsFormatException,
    );
  });

  test('round trip preserves raw frame timestamps and compact fields', () {
    final summary = CockpitPerformanceSummary.fromFrames(
      frames,
      frameBudgetUs: 16667,
    );
    final start = DateTime.utc(2026, 1, 1);
    final report = CockpitPerformanceReport(
      startedAt: start,
      finishedAt: start.add(const Duration(milliseconds: 10)),
      durationUs: 10000,
      durationMs: 10,
      platform: 'test',
      buildMode: 'profile',
      mode: CockpitPerformanceMode.profile,
      summary: summary,
      frames: frames,
      events: <CockpitPerformanceEvent>[
        CockpitPerformanceEvent(
          name: 'build',
          category: 'Dart',
          timestampUs: -2,
          durationUs: 3,
          processId: 7,
          threadId: 11,
          eventId: 'event-1',
          scope: 'scope-1',
          bindId: 'bind-1',
          source: 'checkout-aop',
          isolateId: 'isolates/1',
          uri: 'package:checkout/checkout.dart',
          line: 42,
          column: 7,
        ),
      ],
      plugins: <CockpitPerformancePluginStats>[
        CockpitPerformancePluginStats(
          id: 'checkout-aop',
          state: 'available',
          version: '1.0.0',
          eventCount: 1,
          spanCount: 1,
          instantCount: 0,
          counterCount: 0,
          durationUs: 3,
          maxDurationUs: 3,
          categories: const <String, int>{'business': 1},
        ),
      ],
    );
    final decoded = CockpitPerformanceReport.fromJson(report.toJson());

    expect(decoded.frames, frames);
    expect(decoded.frames.first.wallTimeUs, 900);
    expect(decoded.frames.first.buildQueueUs, 50);
    expect(decoded.frames.first.rasterQueueUs, 50);
    expect(decoded.frames.first.pipelineSpanUs, 10000);
    expect(decoded.buildMode, 'profile');
    expect(decoded.events.single.timestampUs, -2);
    expect(decoded.events.single.processId, 7);
    expect(decoded.events.single.threadId, 11);
    expect(decoded.events.single.eventId, 'event-1');
    expect(decoded.events.single.scope, 'scope-1');
    expect(decoded.events.single.bindId, 'bind-1');
    expect(decoded.events.single.source, 'checkout-aop');
    expect(decoded.events.single.isolateId, 'isolates/1');
    expect(decoded.events.single.uri, 'package:checkout/checkout.dart');
    expect(decoded.events.single.line, 42);
    expect(decoded.events.single.column, 7);
    expect(decoded.plugins.single.id, 'checkout-aop');
    expect(decoded.plugins.single.durationUs, 3);
    expect(decoded.plugins.single.categories, <String, int>{'business': 1});
    expect(decoded.summary.build.toJson(), containsPair('bud', 16667));
  });

  test('rejects incomplete populated phases and timezone-free reports', () {
    expect(
      () => CockpitPerformancePhaseSummary.fromJson(<String, Object?>{
        'n': 1,
        'bud': 16667,
        'avg': 1,
      }),
      throwsFormatException,
    );

    final summary = CockpitPerformanceSummary.fromFrames(
      const <CockpitPerformanceFrame>[],
      frameBudgetUs: 16667,
    );
    expect(
      () => CockpitPerformanceReport.fromJson(<String, Object?>{
        'schema': 'cockpit.performance/v2',
        'started': '2026-01-01T00:00:00',
        'finished': '2026-01-01T00:00:00Z',
        'durationUs': 0,
        'durationMs': 0,
        'platform': 'test',
        'mode': 'light',
        'summary': summary.toJson(),
      }),
      throwsFormatException,
    );
  });

  test('event arguments are snapshotted instead of remaining mutable', () {
    final nested = <String, Object?>{
      'items': <Object?>[
        <String, Object?>{'value': 1},
      ],
    };
    final event = CockpitPerformanceEvent(
      name: 'work',
      category: 'Dart',
      timestampUs: 1,
      durationUs: 2,
      args: nested,
    );
    (nested['items']! as List<Object?>).clear();

    expect(event.args['items'], hasLength(1));
    expect(
      () => (event.args['items']! as List<Object?>).clear(),
      throwsUnsupportedError,
    );
  });

  test('memory report preserves bounded RSS samples and summary', () {
    final report = CockpitPerformanceMemoryReport(
      intervalMs: 100,
      samples: const <CockpitPerformanceMemorySample>[
        CockpitPerformanceMemorySample(
          timestampUs: 0,
          rssBytes: 100,
          processPeakBytes: 100,
        ),
        CockpitPerformanceMemorySample(
          timestampUs: 100000,
          rssBytes: 160,
          processPeakBytes: 180,
        ),
      ],
      droppedSamples: 2,
    );

    final decoded = CockpitPerformanceMemoryReport.fromJson(report.toJson());
    expect(decoded.samples, report.samples);
    expect(decoded.summary.averageRssBytes, 130);
    expect(decoded.summary.deltaRssBytes, 60);
    expect(decoded.droppedSamples, 2);
  });

  test('memory report rejects a forged summary', () {
    final report = <String, Object?>{
      'source': 'processInfo',
      'intervalMs': 100,
      'summary': <String, Object?>{
        'n': 1,
        'start': 100,
        'end': 100,
        'min': 100,
        'max': 100,
        'avg': 100,
        'peak': 100,
        'delta': 1,
      },
      'samples': <Object?>[
        <String, Object?>{'t': 0, 'rss': 100, 'peak': 100},
      ],
    };
    expect(
      () => CockpitPerformanceMemoryReport.fromJson(report),
      throwsFormatException,
    );
  });

  test('DevTools CPU, heap, and GPU projections round-trip compactly', () {
    final profile = CockpitDevToolsProfile(
      source: 'vm',
      state: 'available',
      cpu: CockpitCpuProfile(
        samplePeriodUs: 1000,
        maxStackDepth: 32,
        sampleCount: 1,
        timeOriginUs: 100,
        timeExtentUs: 200,
        functions: const <CockpitCpuFunction>[
          CockpitCpuFunction(
            name: 'main',
            inclusiveTicks: 1,
            exclusiveTicks: 1,
            uri: 'package:test/main.dart',
            line: 12,
            column: 0,
          ),
        ],
        samples: const <CockpitCpuSample>[
          CockpitCpuSample(timestampUs: 120, stack: <int>[0]),
        ],
      ),
      heap: CockpitHeapProfile(
        before: const CockpitHeapPoint(
          usageBytes: 10,
          capacityBytes: 20,
          externalBytes: 2,
        ),
        after: const CockpitHeapPoint(
          usageBytes: 12,
          capacityBytes: 24,
          externalBytes: 3,
        ),
        classes: const <CockpitHeapClass>[
          CockpitHeapClass(
            name: 'Foo',
            currentBytes: 8,
            currentInstances: 2,
            accumulatedBytes: 10,
            accumulatedInstances: 3,
          ),
        ],
        groupBefore: const CockpitHeapPoint(
          usageBytes: 20,
          capacityBytes: 30,
          externalBytes: 4,
        ),
        groupAfter: const CockpitHeapPoint(
          usageBytes: 24,
          capacityBytes: 34,
          externalBytes: 5,
        ),
        accumulatorResetAt: 1700000000100,
        serviceGcAt: 1700000000200,
      ),
      gpu: const CockpitGpuProfile(
        source: 'vmTimeline',
        events: 2,
        shaderEvents: 1,
        durationUs: 40,
      ),
      gc: const CockpitGcProfile(
        eventCount: 3,
        timedCount: 2,
        newCount: 2,
        oldCount: 1,
        totalPauseUs: 90,
        p50PauseUs: 30,
        p90PauseUs: 50,
        maxPauseUs: 60,
        newPauseUs: 40,
        oldPauseUs: 50,
      ),
      isolate: CockpitIsolateProfile(
        before: CockpitIsolateStats(
          id: 'isolates/1',
          name: 'main',
          groupId: 'groups/1',
          runnable: true,
          livePorts: 2,
          libraryCount: 18,
          extensionCount: 3,
          startTimeMs: 1700000000000,
          pauseOnExit: false,
          exceptionPauseMode: 'Unhandled',
          rootLibUri: 'package:test/main.dart',
          number: '1',
          pauseKind: 'PauseException',
          pauseTimestampMs: 1700000000050,
          pauseAsync: true,
          breakpointCount: 2,
          newHeap: const CockpitHeapPoint(
            usageBytes: 4,
            capacityBytes: 8,
            externalBytes: 1,
          ),
          oldHeap: const CockpitHeapPoint(
            usageBytes: 6,
            capacityBytes: 12,
            externalBytes: 1,
          ),
        ),
        after: CockpitIsolateStats(
          id: 'isolates/1',
          name: 'main',
          groupId: 'groups/1',
          runnable: true,
          livePorts: 2,
          libraryCount: 18,
          extensionCount: 3,
          startTimeMs: 1700000000000,
          pauseOnExit: false,
          exceptionPauseMode: 'Unhandled',
          rootLibUri: 'package:test/main.dart',
          number: '1',
          pauseKind: 'PauseException',
          pauseTimestampMs: 1700000000050,
          pauseAsync: true,
          breakpointCount: 2,
          newHeap: const CockpitHeapPoint(
            usageBytes: 4,
            capacityBytes: 8,
            externalBytes: 1,
          ),
          oldHeap: const CockpitHeapPoint(
            usageBytes: 6,
            capacityBytes: 12,
            externalBytes: 1,
          ),
        ),
        beforeAll: <CockpitIsolateStats>[
          CockpitIsolateStats(id: 'isolates/1', name: 'main', runnable: true),
          CockpitIsolateStats(id: 'isolates/2', name: 'worker', runnable: true),
        ],
        afterAll: <CockpitIsolateStats>[
          CockpitIsolateStats(id: 'isolates/1', name: 'main', runnable: true),
          CockpitIsolateStats(
            id: 'isolates/3',
            name: 'worker-2',
            runnable: true,
          ),
        ],
        droppedBefore: 1,
        events: const <CockpitIsolateEvent>[
          CockpitIsolateEvent(
            kind: 'IsolateStart',
            timestampMs: 1700000000100,
            isolateId: 'isolates/3',
            name: 'worker-2',
            groupId: 'groups/1',
            extensionRpc: 'ext.flutter.inspector.getRootWidgetSummaryTree',
          ),
        ],
        droppedEvents: 2,
      ),
      timeline: CockpitTimelineProfile(
        recorder: 'ring',
        availableStreams: const <String>['Dart', 'GC'],
        recordedStreams: const <String>['Dart'],
      ),
      vm: CockpitVmRuntimeProfile(
        name: 'vm',
        version: '3.8.0',
        operatingSystem: 'macos',
        hostCpu: 'arm64',
        targetCpu: 'arm64',
        architectureBits: 64,
        pid: 42,
        startTimeMs: 1700000000000,
        isolateCount: 2,
        isolateGroupCount: 1,
        systemIsolateCount: 1,
      ),
      vmMemory: CockpitVmMemoryProfile(
        before: CockpitVmMemorySnapshot(
          timestampUs: 0,
          root: CockpitVmMemoryNode(
            name: 'Process',
            sizeBytes: 1024,
            children: <CockpitVmMemoryNode>[
              CockpitVmMemoryNode(name: 'Dart heap', sizeBytes: 768),
              CockpitVmMemoryNode(name: 'Native', sizeBytes: 256),
            ],
          ),
        ),
        after: CockpitVmMemorySnapshot(
          timestampUs: 100000,
          root: CockpitVmMemoryNode(
            name: 'Process',
            sizeBytes: 1280,
            children: <CockpitVmMemoryNode>[
              CockpitVmMemoryNode(name: 'Dart heap', sizeBytes: 896),
              CockpitVmMemoryNode(name: 'Native', sizeBytes: 384),
            ],
          ),
        ),
      ),
      logs: const <CockpitVmLogEvent>[
        CockpitVmLogEvent(
          timestampMs: 1700000000300,
          level: 900,
          sequence: 4,
          message: 'slow request',
          logger: 'app.network',
          zone: 'request-zone',
          error: 'timeout',
          stack: 'package:test/main.dart:12',
          isolateId: 'isolates/1',
        ),
      ],
      debug: const <CockpitVmDebugEvent>[
        CockpitVmDebugEvent(
          kind: 'PauseException',
          timestampMs: 1700000000400,
          isolateId: 'isolates/1',
          isolateName: 'main',
          status: 'paused',
          details: 'uncaught',
          pauseAsync: true,
          frame: 'main',
          uri: 'package:test/main.dart',
          line: 12,
          column: 3,
          exception: 'StateError',
          breakpoint: 2,
        ),
      ],
      droppedLogs: 3,
      droppedDebug: 5,
    );
    final compact = profile.toJson();
    final compactCpu = compact['cpu']! as Map<String, Object?>;
    expect(compactCpu, isNot(contains('f')));
    expect(compactCpu, isNot(contains('s')));
    final decoded = CockpitDevToolsProfile.fromJson(compact);
    expect(decoded.cpu!.samples, isEmpty);
    expect(decoded.cpu!.functions, isEmpty);
    expect(decoded.heap!.after.usageBytes, 12);
    expect(decoded.heap!.classes.single.name, 'Foo');
    expect(decoded.heap!.groupAfter!.usageBytes, 24);
    expect(decoded.gpu!.shaderEvents, 1);
    expect(decoded.gc!.eventCount, 3);
    expect(decoded.gc!.p90PauseUs, 50);
    expect(decoded.isolate!.after!.livePorts, 2);
    expect(decoded.isolate!.beforeAll, hasLength(2));
    expect(
      decoded.isolate!.afterAll.where((item) => item.id == 'isolates/3'),
      isNotEmpty,
    );
    expect(decoded.isolate!.droppedBefore, 1);
    expect(decoded.isolate!.droppedAfter, 0);
    expect(decoded.isolate!.events.single.kind, 'IsolateStart');
    expect(decoded.isolate!.events.single.isolateId, 'isolates/3');
    expect(
      decoded.isolate!.events.single.extensionRpc,
      'ext.flutter.inspector.getRootWidgetSummaryTree',
    );
    expect(decoded.isolate!.droppedEvents, 2);
    expect(decoded.isolate!.after!.number, '1');
    expect(decoded.isolate!.after!.pauseKind, 'PauseException');
    expect(decoded.isolate!.after!.pauseAsync, true);
    expect(decoded.isolate!.after!.newHeap!.usageBytes, 4);
    expect(decoded.isolate!.after!.oldHeap!.usageBytes, 6);
    expect(decoded.logs.single.message, 'slow request');
    expect(decoded.logs.single.zone, 'request-zone');
    expect(decoded.logs.single.stack, 'package:test/main.dart:12');
    expect(decoded.debug.single.uri, 'package:test/main.dart');
    expect(decoded.debug.single.breakpoint, 2);
    expect(decoded.droppedLogs, 3);
    expect(decoded.droppedDebug, 5);
    expect(decoded.timeline!.recordedStreams, <String>['Dart']);
    expect(decoded.vm!.targetCpu, 'arm64');
    expect(decoded.vm!.isolateCount, 2);
    expect(decoded.vmMemory!.before!.root.children.first.name, 'Dart heap');
    expect(decoded.vmMemory!.after!.root.sizeBytes, 1280);
    final full = CockpitDevToolsProfile.fromJson(
      profile.toJson(includeRaw: true),
    );
    expect(full.cpu!.samples.single.stack, <int>[0]);
    expect(full.cpu!.functions.single.name, 'main');
    expect(full.cpu!.functions.single.line, 12);
    expect(full.cpu!.functions.single.column, 0);
    expect(full.heap!.accumulatorResetAt, 1700000000100);
    expect(full.heap!.serviceGcAt, 1700000000200);
    expect(full.isolate!.before!.pauseOnExit, false);
    expect(full.isolate!.before!.exceptionPauseMode, 'Unhandled');
    expect(full.isolate!.before!.rootLibUri, 'package:test/main.dart');
  });

  test('DevTools heap samples preserve order and compact drop count', () {
    final profile = CockpitHeapProfile(
      before: const CockpitHeapPoint(
        usageBytes: 10,
        capacityBytes: 20,
        externalBytes: 1,
      ),
      after: const CockpitHeapPoint(
        usageBytes: 14,
        capacityBytes: 24,
        externalBytes: 2,
      ),
      classes: const <CockpitHeapClass>[],
      droppedClasses: 2,
      intervalMs: 100,
      samples: const <CockpitHeapSample>[
        CockpitHeapSample(
          timestampUs: 0,
          usageBytes: 10,
          capacityBytes: 20,
          externalBytes: 1,
        ),
        CockpitHeapSample(
          timestampUs: 100000,
          usageBytes: 14,
          capacityBytes: 24,
          externalBytes: 2,
        ),
      ],
      droppedSamples: 3,
    );
    final json = profile.toJson();
    expect(json['dropped'], 2);
    expect(json['drop'], 3);
    expect(json.containsKey('droppedSamples'), isFalse);
    final decoded = CockpitHeapProfile.fromJson(json);
    expect(decoded.samples.last.usageBytes, 14);
    expect(decoded.droppedSamples, 3);
    expect(
      () => CockpitHeapProfile(
        before: const CockpitHeapPoint(
          usageBytes: 10,
          capacityBytes: 20,
          externalBytes: 1,
        ),
        after: const CockpitHeapPoint(
          usageBytes: 14,
          capacityBytes: 24,
          externalBytes: 2,
        ),
        classes: const <CockpitHeapClass>[],
        samples: const <CockpitHeapSample>[
          CockpitHeapSample(
            timestampUs: 10,
            usageBytes: 10,
            capacityBytes: 20,
            externalBytes: 1,
          ),
          CockpitHeapSample(
            timestampUs: 9,
            usageBytes: 10,
            capacityBytes: 20,
            externalBytes: 1,
          ),
        ],
      ),
      throwsFormatException,
    );
  });

  test(
    'allocation traces and Perfetto payloads stay compact until full export',
    () {
      final trace = CockpitCpuProfile(
        samplePeriodUs: 1000,
        maxStackDepth: 8,
        sampleCount: 1,
        timeOriginUs: 0,
        timeExtentUs: 1000,
        functions: const <CockpitCpuFunction>[
          CockpitCpuFunction(
            name: 'allocateThing',
            inclusiveTicks: 1,
            exclusiveTicks: 1,
          ),
        ],
        samples: const <CockpitCpuSample>[
          CockpitCpuSample(timestampUs: 10, stack: <int>[0]),
        ],
      );
      final profile = CockpitDevToolsProfile(
        source: 'vm',
        state: 'available',
        allocationTraces: <CockpitAllocationTrace>[
          CockpitAllocationTrace(
            classId: 'classes/1',
            className: 'Thing',
            profile: trace,
          ),
        ],
        perfetto: CockpitPerfettoProfile(
          cpu: CockpitPerfettoTrace(
            kind: 'cpu',
            data: 'AQID',
            originUs: 0,
            extentUs: 1000,
            samplePeriodUs: 1000,
            maxStackDepth: 8,
            sampleCount: 1,
            pid: 42,
          ),
        ),
      );
      final compact = profile.toJson();
      expect(compact['perfetto'], isNot(contains('data')));
      expect((compact['alloc'] as List).single['trace']['n'], 1);
      expect((compact['alloc'] as List).single['trace'], isNot(contains('s')));
      final compactDecoded = CockpitDevToolsProfile.fromJson(compact);
      expect(compactDecoded.perfetto!.cpu!.data, isNull);
      expect(compactDecoded.perfetto!.cpu!.sampleCount, 1);
      final full = profile.toJson(includeRaw: true);
      expect((full['perfetto'] as Map)['cpu']['data'], 'AQID');
      final decoded = CockpitDevToolsProfile.fromJson(full);
      expect(decoded.allocationTraces.single.className, 'Thing');
      expect(decoded.perfetto!.cpu!.sampleCount, 1);
    },
  );

  test('VM process-memory trees stay bounded and compact', () {
    final node = CockpitVmMemoryNode(
      name: 'Process',
      sizeBytes: 100,
      children: <CockpitVmMemoryNode>[
        CockpitVmMemoryNode(name: 'Dart', sizeBytes: 60),
      ],
      droppedChildren: 3,
    );
    final snapshot = CockpitVmMemorySnapshot(timestampUs: 12, root: node);
    final profile = CockpitVmMemoryProfile(before: snapshot);
    final json = profile.toJson();
    expect(json['before'], isA<Map<String, Object?>>());
    expect(
      (json['before']! as Map<String, Object?>)['root'],
      containsPair('drop', 3),
    );
    final decoded = CockpitVmMemoryProfile.fromJson(json);
    expect(decoded.before!.root.sizeBytes, 100);
    expect(decoded.before!.root.children.single.name, 'Dart');
    expect(
      () => CockpitVmMemoryNode(
        name: 'invalid',
        sizeBytes: 1,
        children: <CockpitVmMemoryNode>[
          CockpitVmMemoryNode(name: 'too large', sizeBytes: 2),
        ],
      ),
      throwsFormatException,
    );
  });

  test('DevTools display and widget rebuild projections round-trip', () {
    final profile = CockpitDevToolsProfile(
      source: 'vm',
      state: 'available',
      display: CockpitDisplayProfile(
        refreshRateHz: 120,
        frameBudgetUs: 8333,
        viewId: 'view-1',
      ),
      rebuild: CockpitRebuildProfile(
        frames: <CockpitRebuildFrame>[
          CockpitRebuildFrame(
            frameNumber: 7,
            entries: const <CockpitRebuildCount>[
              CockpitRebuildCount(locationId: 2, count: 3),
            ],
          ),
        ],
        locations: <CockpitRebuildLocation>[
          CockpitRebuildLocation(
            id: 2,
            uri: 'package:demo/main.dart',
            line: 12,
            column: 4,
            name: 'HomePage',
          ),
        ],
        totals: <CockpitRebuildTotal>[
          CockpitRebuildTotal(locationId: 2, count: 3),
        ],
        unresolvedLocations: 1,
      ),
    );
    final decoded = CockpitDevToolsProfile.fromJson(profile.toJson());
    expect(decoded.display!.refreshRateHz, 120);
    expect(decoded.display!.frameBudgetUs, 8333);
    expect(decoded.rebuild!.frames.single.entries.single.count, 3);
    expect(decoded.rebuild!.locations.single.name, 'HomePage');
    expect(decoded.rebuild!.totals.single.count, 3);
    expect(decoded.rebuild!.unresolvedLocations, 1);
  });

  test('retains isolate lifecycle events when snapshots are unavailable', () {
    final profile = CockpitDevToolsProfile(
      source: 'vm',
      state: 'available',
      isolate: CockpitIsolateProfile(
        events: const <CockpitIsolateEvent>[
          CockpitIsolateEvent(kind: 'IsolateExit', isolateId: 'isolates/2'),
        ],
      ),
    );

    final decoded = CockpitDevToolsProfile.fromJson(profile.toJson());
    expect(decoded.isolate, isNotNull);
    expect(decoded.isolate!.events.single.kind, 'IsolateExit');
  });
}
