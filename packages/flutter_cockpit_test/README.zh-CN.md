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

## 运行

使用 Flutter 原生集成测试命令：

```bash
flutter test integration_test/task_flow_test.dart -d <device>
```

在 Cockpit 管理的开发 session 中也可以运行同一份测试，步骤会保留在 session 时间线
和 artifacts 中。Case/Suite 文档仍用于 AI 生成、黑盒、矩阵和跨平台 journey；这个包
是 Flutter 源码项目更顺手的 Dart 测试层。
