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
数量摘要，同时记录 VM heap 时间线样本、isolate 健康快照，以及 timeline recorder 的可用/已记录
stream 元数据。长场景可以用 `cpu: false` 或 `heap: false` 关闭对应采集，并通过
`maxCpuSamples`、`maxHeapClasses`、`maxHeapSamples` 控制内存上限：

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

DevTools 区域包含 VM heap 趋势图、CPU/heap/GPU 汇总、isolate 生命周期行，以及 recorder/stream
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

两个导出 API 都会保留所有 retained 帧、VM 事件及参数、内存样本、VM heap 样本、分配类、isolate
快照、timeline stream 列表、启动里程碑和明确
的 retention/drop 计数。终端和普通测试结果继续保持紧凑；导出保留完整的已记录细节。
唯一的限制是采集时设置的 `maxEvents`、帧保留上限和内存采样上限，
这些限制以及丢弃数量都会写入导出文件。

不传 `path` 时会在 `build/cockpit/performance/` 下生成唯一文件。自定义宿主可以使用
`CockpitPerformanceHtml.render(report)` 或
`CockpitPerformanceHtml.renderMany(reports)` 直接得到 HTML 字符串，不访问文件系统；
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

它与 VS Code/DevTools 的对应关系如下：

| DevTools/VS Code 视图 | Cockpit 采集结果 | 查看位置 |
| --- | --- | --- |
| Performance 时间线与帧图 | FrameTiming、jank、帧节奏、VM 事件 | HTML 报告与 report JSON |
| 慢帧归因 | 重叠的 retained VM 区间，以及仅由证据提供的源码标签 | Jank & stalls 面板 |
| Raster cache | Layer/picture cache 数量和字节数 | Cache 图表与帧明细 |
| Memory 与 GC | 原生 RSS 样本和 VM GC 事件 | Memory、Cache/GC 图表 |
| CPU profiler | VM CPU 采样与有界调用栈 | CPU sampling 面板与完整报告 |
| Memory heap/allocation | VM heap 点位与有界分配类计数 | Heap & allocation 面板与完整报告 |
| VM runtime health | Heap 趋势、isolate 快照、recorder/stream 元数据 | VM runtime 面板与详情弹窗 |
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
