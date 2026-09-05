<div align="center">
  <a href="https://github.com/cockpit-dev/cockpit">
    <img src="https://raw.githubusercontent.com/cockpit-dev/cockpit/main/assets/brand/cockpit-mark.svg" width="128" alt="Cockpit logo">
  </a>
  <h1>flutter_cockpit_test</h1>
  <p><strong>使用 Cockpit 的真实定位、控制、证据和诊断引擎编写正常的 Flutter 集成测试。</strong></p>
  <p>
    <a href="https://pub.dev/packages/flutter_cockpit_test"><img src="https://img.shields.io/pub/v/flutter_cockpit_test?logo=flutter&amp;label=pub.dev" alt="flutter_cockpit_test version on pub.dev"></a>
    <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-%E2%89%A53.32.0-02569B?logo=flutter&amp;logoColor=white" alt="Flutter 3.32.0 或更高版本"></a>
    <a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/flutter_cockpit_test/LICENSE"><img src="https://img.shields.io/github/license/cockpit-dev/cockpit" alt="MIT license"></a>
  </p>
  <p><a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/flutter_cockpit_test/README.md">English</a> · <a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/flutter_cockpit_test/README.zh-CN.md">简体中文</a></p>
</div>

`flutter_cockpit_test` 是一个仅用于开发测试的 facade。它继续使用 Flutter
官方 `integration_test` runner，并补足 `flutter_test` 本身没有的能力：面向源码的
Element 选择器、真实命中测试操作、懒加载列表滚动、紧凑快照、原生截图、录屏、窗口
尺寸控制，以及显式的宿主/系统操作。

## 安装

把它添加到开发 shell 或仅测试 package 中，不要加入生产应用代码：

```bash
flutter pub add --dev flutter_cockpit_test
```

这个包用于已经接入 `flutter_cockpit` 的不发布 `cockpit/` shell。它不依赖 Cockpit
CLI、daemon、MCP server 或任何 secret store。

## 快速开始

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';

void main() {
  cockpitTestWidgets(
    '创建任务',
    app: buildDevelopmentApp,
    body: (cockpit) async {
      await cockpit.tap('New task');
      await cockpit.type('Buy milk', into: 'Task title');
      await cockpit.tap('Save');
      await cockpit.expectText('Task created', 'Task created');
    },
  );
}

Widget buildDevelopmentApp() {
  return const MaterialApp(home: TaskEditorScreen());
}
```

helper 会把普通 Flutter widget 包在 `FlutterCockpitApp` 中。如果 builder 已经
返回 `FlutterCockpitApp`，则会原样挂载并复用已有 Cockpit root，方便从现有开发 shell
渐进迁移。

选择器与 `cockpit dev` 使用同一套语法：

```dart
await cockpit.tap('#save');
await cockpit.hover('更多选项');
await cockpit.tap(null, at: const Offset(400, 300),
    device: PointerDeviceKind.mouse, buttons: kSecondaryButton);
await cockpit.tap('Dialog >> FilledButton["Continue"]');
await cockpit.type('hello', into: '@message');
await cockpit.scroll('Settings >> Text["Advanced"]', align: 'center');
await cockpit.wheel(
  target: '#list',
  delta: const Offset(0, 120),
  steps: 2,
);
```

普通文本是精确匹配。源码已知时优先使用 `#id`、`@key`、Widget 类型、祖先链和多条件
定位，不需要为了 Cockpit 修改业务 `Key` 或 `Semantics`。

facade 直接覆盖完整 Flutter 交互闭环：指针手势（`tap`、`hover`、`longPress`、`doubleTap`、`drag`、`fling`、`swipe`、
`pinch`、`rotate`、`panZoom`、`multiTouch`、`wheel`）、文本和键盘输入（`type`、`clear`、`copy`、`paste`、`focus`、
`setTextEditingValue`、`selectText`、`keyDown`、`keyUp`、`hotkey`、`press`）、控件和导航（`increase`、`decrease`、
`showOnScreen`、`scroll`、`waitFor`、`waitForUi`、`waitForRoute`、`back`、`dismiss`、`dismissKeyboard`），以及断言和证据
（`expectVisible`、`expectText`、`screenshot`、`snapshot`、`watch`、`execute`）。每条命令都会
通过与 live bridge 相同的提交和 reveal 逻辑推进 Flutter 测试时钟，路由跳转和异步 UI 更新
不需要手写 sleep。只有在确实需要 Flutter 专属 matcher 或自定义 pump 时，才使用
`cockpit.flutter`。

所有手势都会发送真实且经过 hit-test 的指针事件。目标无法被定位时可用 `at` 坐标；`device` 和 `buttons` 可覆盖
鼠标、触控笔和触摸行为，无需修改业务代码。`wheel` 会发送真实的 `PointerScrollEvent`，因此 `Scrollable`、自定义
`Listener(onPointerSignal: ...)` 和支持触控板的组件都会收到与实际鼠标/触控板一致的输入。每个 `delta` 对应一个事件；
只有场景确实需要时才设置 `steps`、`interval`、`device` 或显式 `at` 坐标。

每条 facade 命令默认超时 10 秒。已知较慢的单次操作直接传入 `timeout` 覆盖，必须为正数且
不超过 1 小时：

```dart
await cockpit.waitForRoute('/reports', timeout: const Duration(seconds: 30));
await cockpit.tap('Refresh', timeout: const Duration(seconds: 5));
```

`CockpitTestOptions.commandTimeout` 会修改所有 Flutter 命令的默认值。原生截图、录屏、
viewport 和能力查询使用独立的 2 分钟默认值，可通过 `nativeTimeout` 或每个原生方法的
`timeout` 单独覆盖。录屏启动超时会先请求取消，再报告超时，避免留下挂起的授权请求。

## 原生与宿主能力

Flutter 测试 binding 负责 Flutter widget。Cockpit 原生 facade 覆盖已安装插件暴露的
应用窗口能力：

```dart
final available = await cockpit.native.queryCaptureAvailability();
if (available) {
  final capture = await cockpit.native.captureScreenshot(
    name: 'task-created',
    timeout: const Duration(seconds: 30),
  );
  // capture.screenshot.artifact.relativePath 是证据文件路径。
}

final recording = await cockpit.native.queryRecordingCapabilities();
if (recording.supportsNativeRecording) {
  await cockpit.native.startRecording(
    name: 'task-flow',
    timeout: const Duration(minutes: 2),
  );
  // 执行流程
  final result = await cockpit.native.stopRecording(
    timeout: const Duration(seconds: 30),
  );
  // result.artifact 或 result.sourceFilePath 是录屏路径。
}

final resized = await cockpit.native.resizeViewport(width: 800, height: 600);
```

系统弹窗、App Link、无障碍控件及其他宿主操作属于 Cockpit system plane，必须通过
测试宿主显式提供：

```dart
await cockpit.host.action(
  'openUri',
  parameters: {'uri': 'myapp://tasks/42'},
);
```

通过 `CockpitTestOptions.hostCommand` 配置宿主 adapter，把命令转发给 Cockpit 公共
控制 API。没有配置时，宿主操作会立即给出明确错误，不会猜测或隐藏外部副作用。

## Flutter API 仍然可用

`CockpitTester.flutter` 就是原始 `WidgetTester`，可继续使用自定义 matcher、golden
断言、pump 控制及 Cockpit 有意不覆盖的 Flutter API。需要更底层能力时，
`CockpitTester.execute` 可以直接执行完整的 `CockpitCommand`。

每条命令都会记录到应用内 Cockpit session，并把紧凑的 `cockpit` 条目合并到
`integration_test` 的 `reportData`。大快照和二进制证据保存在 artifact 中，不会倾倒
到测试输出。

## VM 调试控制

当测试运行器提供 Dart VM Service 时，`cockpit.debugger` 提供一套可复用的调试会话，
覆盖 Dart-Code 常用的暂停、继续、单步、堆栈、求值、断点和 Flutter service extension
流程：

```dart
final state = await cockpit.debugger.status();
if (state.runnable == true) await cockpit.debugger.pause();
final paused = await cockpit.debugger.status(stackLimit: 32);
final value = await cockpit.debugger.evaluateInFrame(0, 'cart.length');
await cockpit.debugger.resume();
```

还可以使用 `stack`、`evaluate`、`getObject`、`addBreakpoint`、`removeBreakpoint`、
`setBreakpointEnabled`、`setPauseMode`、`setLibraryDebuggable`、`reloadSources` 和显式的
`callServiceExtension`。返回值只包含有界的对象摘要、
帧变量、暂停状态和真实源码位置；集合内容只有在显式调用 `getObject` 并指定分页参数时
才会读取。`available` 是无副作用探测，不支持 VM Service 的 Web 或 release harness 会
明确返回不可用错误，不会伪造调试数据。

## 性能采集

使用与应用相同的测试时钟和帧管线，对一次交互进行性能采集。Cockpit 会保留原始的
vsync 与 raster 完成墙钟时间戳，并记录引擎提供的 `FrameTiming`（build、raster、vsync、
总耗时、raster cache、jank budget，以及
p50/p90/p99/最大值）。原生 Flutter 平台还会采集官方 integration-test VM timeline、GC
事件和有界进程 RSS 样本；Web 不支持这些来源时会明确标记 unavailable，不会伪造数据：
如果本地直接用 `flutter test` 运行且进程没有暴露 VM Service URI，操作仍会正常执行，报告会标记 `unavailable:vm`；使用 `flutter drive` 或原生 instrumentation 时继续采集官方 VM timeline：

```dart
final report = await cockpit.profile(
  () async {
    await cockpit.tap('#open-list');
    await cockpit.scroll('#list');
  },
  name: 'open-list',
  streams: const <String>['Dart', 'GC', 'Embedder'],
);
expect(report.summary.jankCount, 0);
```

原生采集默认每 100ms 采样一次进程 RSS，并保留起始/结束/最小/最大/平均/峰值/增量汇总和有界样本时间线。只有确实不需要进程指标时才设置 `memory: false`；需要调整时间分辨率时使用 `sampleEvery`，使用 `streams` 和 `timeline` 选择 VM 跟踪，并用 `maxEvents` 限制保留的时间线事件数量。不支持的目标会明确标记 memory 不可用，不会报告 0。
诊断某次卡顿时，可以设置 `trackBuilds`、`trackUserBuilds`、`trackLayouts` 和
`trackPaints`，采集 Flutter 与 DevTools 对应的真实 Widget/RenderObject 时间线区间。
这些开关默认关闭，因为额外插桩会改变耗时；采集结束后 Cockpit 会恢复进入采集前的全局状态。

当 VM Service 可用时，`profile()` 还会采集 DevTools CPU Profiler 和 Memory 视图背后的真实
CPU 采样与 Dart allocation profile。完整报告保留采样栈和有界的分配类，普通测试输出只保留
数量摘要，同时记录 VM heap 时间线样本、所有已发现 isolate 的前后健康快照和 Isolate stream 生命周期事件（VM 提供时还保留注册的 RPC），以及 timeline recorder 的可用/已记录
stream 元数据。长场景可以用 `cpu: false` 或 `heap: false` 关闭对应采集，并通过
`maxCpuSamples`、`maxHeapClasses`、`maxHeapSamples` 控制内存上限：

当运行时提供真实信息时，CPU 函数会保留已验证的源码位置（URI、行、列）。Heap 报告还会保留 VM allocation accumulator 最近重置时间和最近一次 service GC 时间；isolate 快照会保留 pause-on-exit、异常暂停模式以及 root library URI。VM 没有提供的字段保持缺失，不会猜测填充。

采集默认还会监听 VM 的 `Logging` 和 `Debug` stream。Logging 只保留 VM 通知中已经提供的消息、级别、logger、错误和堆栈；Debug 只保留暂停/恢复/异常/重载上下文以及通知中真实提供的源码位置。这些都是有界元数据，不会隐式执行对象求值，也不会阻塞被测 action。若某次采集不需要其中一类事件，可设置 `logs: false` 或 `debug: false`。当运行时提供时，isolate 快照还会保留新生代/老生代堆空间和断点数量。
超长场景可以用 `maxLogs` 和 `maxDebug` 调整两类事件的保留上限；默认值已经足够覆盖常规交互，并且完整导出仍只保留有界数据。

如果要调查某个具体类型的分配调用栈，先从 heap 报告取得 VM class id，再显式传入最多 20 个
`allocationClassIds`。这是额外开销较高的 VM tracing，默认不会开启：

```dart
final report = await cockpit.profile(
  () => runScenario(),
  allocationClassIds: <String>['classes/123'],
);
// report.devTools?.allocationTraces 只包含选中的类型。
```

需要在 Perfetto 中离线分析完整 VM CPU/时间线 proto 时设置 `perfetto: true`。普通报告只保留
有界元数据，完整 HTML/JSON 导出会保留 base64 原始载荷；原生宿主还可以用
`exportPerformancePerfetto()` 为每次采集写出独立的 `.pftrace` 文件：

```dart
final report = await cockpit.profile(
  () => runScenario(),
  perfetto: true,
);
final tracePaths = await cockpit.exportPerformancePerfetto();
```

Perfetto 受 VM recorder 和平台能力影响。如果 RPC 不支持，或当前 recorder 直接写入系统/文件，
本次采集仍然有效，只会在 coverage 中将该 trace 标记为不可用。

### 按场景选择内存或流式归档

短流程直接使用 `profile()`，报告保留在内存中，便于立即断言和生成单文件
HTML。可能运行数小时的集成/E2E 流程，应显式打开 JSONL 归档并传给
`profile`：帧、VM/插件事件、堆样本、RSS、日志和 Debug 事件会边采集边写入
分片文件，而内存中的报告只保留用于快速查看的投影：

```dart
final archive = await cockpit.openPerformanceArchive(name: 'overnight-flow');
await cockpit.profile(
  () => runOvernightJourney(),
  name: 'overnight-flow',
  archive: archive,
);
// 测试 teardown 会自动关闭已经注册的归档并刷新 manifest。
```

显式归档默认使用 `lossless`，不设置积压上限并保留每条记录。受限 CI runner
如需硬性限制，可改用 `CockpitPerformanceArchiveMode.low` 并设置
`maxPendingBytes`；超出上限的记录会被丢弃，manifest 和报告会记录准确数量。
分片大小、刷新间隔、轮询间隔和积压上限都可以配置。`archive.info.manifest` 是定位全部
分片所需的唯一路径。manifest 内保存相对于自身的分片路径，因此 CI 下载后整个目录可以
直接移动；`archive.info.chunks` 仍返回本机直接访问用的绝对路径。对已完成报告调用 `exportPerformanceJsonl()` 也会逐条写出 JSONL，
不会构造巨大的 JSON 数组。独立 HTML 只加载内存摘要，避免数 GB 事件拖垮浏览器。
当 Android、iOS、macOS 或 CI worker 分别产出归档时，可以使用
`CockpitPerformanceArchive.merge([...])` 增量合并 manifest 或单独的
`.jsonl`/`.jsonl.part` 分片。它会逐行校验并写入新的分片，保留每个来源的顺序、隔离重复
capture id，并返回新的 manifest 路径；不同设备的单调时钟没有共同基准，因此不会伪造全局排序。
HTML 内嵌的是小体量内存报告。直接以 `file://` 打开时，浏览器安全策略不允许它扫描项目路径
或自动读取外部 JSON/JSONL；需要用本地 HTTP 服务打开，或通过浏览器文件选择器明确选择
manifest/分片。不要把数 GB 的流直接嵌入 HTML。

当 VM 暴露 isolate group 时，heap 报告还会保留 group 级别的起止内存点位，覆盖多 isolate
应用，同时不会在每个采样 tick 额外轮询所有 group。

```dart
final report = await cockpit.profile(
  () => runScenario(),
  cpu: true,
  heap: true,
  maxCpuSamples: 20000,
  maxHeapClasses: 100,
);
```

同一个 facade 也提供 DevTools 的可视化诊断开关，不需要修改生产代码：

```dart
cockpit.debug.apply(
  paintSize: true,
  repaintRainbow: true,
  performanceOverlay: true,
  timeScale: 5,
);
// 测试结束时 harness 会恢复所有开关。
```

GPU/shader 数据只接受真实证据：Flutter 发出匹配的 VM timeline 信号时才展示，否则明确
标记为不可用，绝不填充猜测的 GPU 数值。

完整的有界报告会写入
`IntegrationTestWidgetsFlutterBinding.reportData` 的
`cockpit.performance.open-list`，普通 Cockpit 结果只保留紧凑汇总。达到保留上限时会
明确输出 `dropped` 数量；出现丢弃时汇总只描述保留样本。没有帧的阶段会省略耗时聚合，
不会伪造 0；当原始引擎时间戳不足以建立严格递增帧率时会省略 `fps`。帧预算优先
取 Flutter 暴露的目标屏幕刷新率，否则记录精确四舍五入后的 60Hz fallback（16,667µs）。缺失或
unavailable 的指标不能当成 0 处理。HTML 只有在 VM 事件参数提供文件、URL、符号或行号时才展示代码证据；单独的帧耗时无法识别 Dart 代码，因此不会猜测来源。报告还会记录 `debug`、`profile` 或 `release` 构建模式；
debug 数据仅用于诊断，不能当作发布性能证据。

报告还提供 **Operation hotspots**，按真实 VM event 的 category 和名称聚合事件数、有时长事件数、总耗时、p90 和最长区间，先回答“到底是哪类具体操作慢”，再决定是否打开原始时间线。源码列只在对应事件参数实际带有位置时显示，不会从帧耗时推断文件。`fullJson()` 会在每个 capture 下的 `analysis` 字段保留这份有界聚合，同时完整保留原始 events。
同一份分析还会在时间线确实包含 GC 标记时记录 GC 事件数、带时长的暂停总量、p50、p90 和最大暂停；HTML 的 cache/GC 面板会把这些暂停指标和新生代/老生代次数一起展示。

### 埋点插件与 AOP 适配器

当应用能够提供开发期 hook 时，可以用 `CockpitPerformancePlugin` 记录仓储、网络、
数据库、渲染或业务操作。自定义插件继承 `CockpitPerformancePlugin`，`open` 为每次
采集创建独立的 `CockpitPerformancePluginRun`，把订阅、计数器等可变状态放在 Run 中，
避免重复或并发采集互相污染。插件只在一次显式采集中启动，不安装全局监听器，也不会改变
正常测试行为：

完整可运行示例见
[`example/performance_plugin.dart`](example/performance_plugin.dart)。

```dart
final report = await cockpit.profile(
  () => runCheckoutFlow(),
  plugins: <CockpitPerformancePlugin>[
    CheckoutPlugin(),
  ],
);
```

点事件使用 `instant`，耗时使用 `begin/end` 或 `trace`，数值使用
`counter`/`sample`。插件事件与 VM timeline 使用同一单调时间轴，并合并到
`report.events`；每个事件包含插件来源，以及可选的 isolate/源码位置。每个插件都有
事件数量、采样、分类过滤、payload 深度/大小上限和丢弃/非法/截断统计，保证采集有界。
插件抛出异常只会标记为 `failed`，不会让被测操作失败。通过 `report.plugins` 查看归因和
统计；compact 输出只保留计数，完整 JSON、HTML 和 Chrome trace 保留有界事件详情。
AOP 适配器应从显式开发 hook 调用 sink，不支持对生产代码做隐式全局注入。

简单的无状态埋点可以使用 `CockpitPerformancePlugin.callbacks(...)`，传入 `setup` 和可选的
`cleanup`。只要 hook 持有订阅、定时器、缓冲区或其他可变资源，就应使用自定义 Run。

插件启动和清理都受 `CockpitPerformancePluginOptions.lifecycleTimeout` 限制，默认两秒。
被测窗口会在插件清理和报告生成前关闭，因此清理开销不会被归因到被测交互；插件超时只会记录
失败原因，不会阻塞业务动作。

DevTools 区域包含 VM heap 趋势图、CPU/heap/GPU 汇总、VM 身份与 isolate 数量、每个已发现 isolate 的前后健康快照，以及 VM Isolate stream 的启动、可运行、更新、重载、退出和扩展注册事件；新增/退出 isolate 与保留丢弃数会在运行时面板和完整 JSON 中显示，同时保留 recorder/stream
元数据。每个区域都有紧凑的 **Details** 操作，点击后使用原生弹窗查看有界 JSON 预览；完整样本
仍保留在 JSON 导出中，因此查看详情不会把整页撑开或卡住浏览器。CPU 详情还会根据 VM 返回的
函数索引聚合真实采样栈路径，不会猜测源码。

每次 `cockpitTestWidgets` 运行还会在紧凑的 `cockpit.startup` 条目和 HTML 报告中记录冷
启动阶段：应用构建/挂载、首个 pumped frame，以及初始可用时间。计时从 app builder 之前
立即开始，因此这些数值是可复现的 Dart harness 测量；宿主没有提供原生进程启动时间时，
不会猜测或伪造该部分数据。

宿主侧的 `integration_test_driver.dart` 应导入
`package:flutter_cockpit_test/flutter_cockpit_test_report.dart`。这是纯 Dart 入口，提供
报告模型和 HTML 渲染器，不会加载 `dart:ui`。

### 导出完整的离线 HTML 报告

`CockpitTester.exportPerformanceHtml()` 会把当前测试完成的所有性能采集写入一个独立
HTML 文件。文件内包含采集切换、帧 pacing 与预算图、按分类排列的 VM timeline、阶段
分位数、缓存/GC 压力、可搜索且可折叠的事件参数、分页帧表/事件表，以及精确的原始
JSON。它不需要服务器或外部资源即可打开：

```dart
final htmlPath = await cockpit.exportPerformanceHtml(
  title: 'Task flow performance',
  // path: 'build/reports/task-flow.html', // 可选
);
// 将 htmlPath 交给人工或 CI artifact 收集器。
```

如果需要机器读取的产物，可以使用 `performanceJson()` 或
`exportPerformanceJson()`。它会导出当前测试已经完成的所有采集，是完整规范
报告包，不是紧凑的 `integration_test` 结果：

```dart
final jsonPath = await cockpit.exportPerformanceJson(
  title: 'Task flow performance',
  // path: 'build/reports/task-flow.json', // 可选
);
```

导出的 JSON 遵循已发布的 `cockpit.performance/v2` schema：
[`cockpit_protocol/schema/cockpit.performance.v2.schema.json`](https://github.com/cockpit-dev/cockpit/blob/main/packages/cockpit_protocol/schema/cockpit.performance.v2.schema.json)。
同一份 schema 也校验 `IntegrationTestWidgetsFlutterBinding.reportData` 中
`cockpit.performance.<name>` 存放的单次采集 JSON，下游消费者用一份文档即可校验两种形态。

两个导出 API 都会保留所有 retained 帧、VM 事件及参数、内存样本、VM heap 样本、分配类、isolate
快照、timeline stream 列表、启动里程碑和明确
的 retention/drop 计数。终端和普通测试结果继续保持紧凑；导出保留完整的已记录细节。
唯一的限制是采集时设置的 `maxEvents`、帧保留上限和内存采样上限，
这些限制以及丢弃数量都会写入导出文件。

不传 `path` 时会在 `build/cockpit/performance/` 下生成唯一文件。自定义宿主可以使用
`CockpitPerformanceHtml.render(report)` 或
`CockpitPerformanceHtml.renderMany(reports)` 直接得到 HTML 字符串，不访问文件系统；
`renderMany` 会在采集选择器和对比表中保留每个报告真实的平台与构建模式，Android/iOS/macOS/Web
可以放在同一视图中比较，不会把不可用指标折叠成 0。
`CockpitPerformanceHtml.fullJson(reports)` 返回同一份完整规范 JSON。JSON 是机器读取的
规范导出，HTML 是给人查看的完整视图。
HTML 还提供相对时间 hover 图表、jank 分布、帧节奏、Raster cache 趋势、VM 分类耗时、Operation hotspots、卡顿/阻塞证据表、分开的 memory/cache/GC 视图，以及在存在持续区间时展示的 VM duration 火焰时间视图；没有区间时不会伪造调用栈。
传入启动数据时还会绘制 app build、首帧和 ready 三个冷启动里程碑。

报告还包含 **DevTools coverage** 面板，明确标记本次采集真正拥有的数据：
FrameTiming、Raster cache、VM timeline、GC、进程 RSS 和 harness 冷启动里程碑只有在
报告实际包含时才会显示为可用。CPU sampling、heap/allocation profile 以及匹配到的
GPU/shader timeline 信号都会直接来自 VM；平台不支持的计数保持不可用，不会伪造 0
或虚构调用栈。网络请求请使用 Cockpit 的 network evidence。顶部的 **Download
timeline** 会导出保留的 VM 事件为 Chrome trace 兼容的 `traceEvents` JSON 文件，
完整的 FrameTiming 和 memory 数据仍保留在报告 JSON 与 HTML 图表中。宿主侧也可以用
`CockpitPerformanceHtml.timelineJson(report)` 生成同样的时间线文件。
紧凑事件没有保留 async/flow 所需的关联 ID，因此这类阶段会安全降级为独立的瞬时或
持续事件，确保导出的 trace 可以被导入。

采集默认还会请求 VM Service 的 `getProcessMemoryUsage`（`vmMemory: true`）。它与平台
RSS 是两条独立数据：会保留采集前后的 VM 进程内存分层、大小、主要子项和明确的丢弃子项数量，
写入 `devtools.vmem`。树有界以保证测试内存和导出稳定；如果本次调查不需要 VM 内存地图，
可以设置 `vmMemory: false`。运行时不支持该 RPC 时会显示不可用，不会伪造为 0。

它与 VS Code/DevTools 的对应关系如下：

| DevTools/VS Code 视图 | Cockpit 采集结果 | 查看位置 |
| --- | --- | --- |
| Performance 时间线与帧图 | FrameTiming、jank、帧节奏、VM 事件 | HTML 报告与 report JSON |
| 慢帧归因 | 重叠的 retained VM 区间，以及仅由证据提供的源码标签 | Jank & stalls 面板 |
| Raster cache | Layer/picture cache 数量和字节数 | Cache 图表与帧明细 |
| Memory 与 GC | 原生 RSS 样本和 VM GC 事件 | Memory、Cache/GC 图表 |
| CPU profiler | VM CPU 采样与有界调用栈 | CPU sampling 面板与完整报告 |
| Memory heap/allocation | VM heap 点位、有界分配类计数与显式选择类型的调用栈 | Heap & allocation 面板与完整报告 |
| Perfetto CPU/timeline | recorder 支持时保留 VM 原始 proto | Perfetto 下载按钮或 `exportPerformancePerfetto()` |
| VM runtime health | Heap 趋势、isolate 快照、recorder/stream 元数据、VM 进程内存树 | VM runtime、VM process memory 面板与详情弹窗 |
| GPU/shader | 仅展示匹配到的真实 VM timeline 信号 | GPU / Shader signals 面板 |
| Network profiler | 独立的 Cockpit network evidence | `cockpit dev network` 产物 |

导出的 trace 是可导入 Chrome/DevTools 时间线的 VM 事件真实投影，不会凭空补齐
CPU 调用栈、GPU 计数、线程身份或源码位置。

普通测试输出会保持紧凑；导出不会。HTML 和 JSON 下载会保留所有 retained 帧、VM
事件、事件参数、内存样本、启动里程碑和明确的丢弃计数。`maxEvents`、帧保留上限和
内存采样上限是唯一的有界限制，所有丢弃信息都会出现在导出结果中。

## 运行

使用 Flutter 原生集成测试命令：

```bash
flutter test integration_test/task_flow_test.dart -d <device>
```

在 Cockpit 管理的开发 session 中也可以运行同一份测试，步骤会保留在 session 时间线
和 artifacts 中。Case/Suite 文档仍用于 AI 生成、黑盒、矩阵和跨平台 journey；这个包
是 Flutter 源码项目更顺手的 Dart 测试层。
