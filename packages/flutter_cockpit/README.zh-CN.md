<div align="center">
  <a href="https://github.com/cockpit-dev/cockpit">
    <img src="https://raw.githubusercontent.com/cockpit-dev/cockpit/main/assets/brand/cockpit-mark.svg" width="128" alt="Cockpit logo">
  </a>
  <h1>flutter_cockpit</h1>
  <p><strong>Cockpit 的一等 Flutter 开发适配器。</strong></p>
  <p>
    <a href="https://pub.dev/packages/flutter_cockpit"><img src="https://img.shields.io/pub/v/flutter_cockpit?logo=flutter&amp;label=pub.dev" alt="pub.dev 上的 flutter_cockpit 版本"></a>
    <a href="https://pub.dev/packages/flutter_cockpit/score"><img src="https://img.shields.io/pub/points/flutter_cockpit?logo=flutter" alt="flutter_cockpit pub points"></a>
    <a href="https://pub.dev/packages/flutter_cockpit/score"><img src="https://img.shields.io/pub/likes/flutter_cockpit?logo=flutter" alt="flutter_cockpit 在 pub.dev 上的点赞数"></a>
    <a href="https://pub.dev/packages/flutter_cockpit/score"><img src="https://img.shields.io/pub/popularity/flutter_cockpit?logo=flutter" alt="flutter_cockpit 在 pub.dev 上的流行度"></a>
  </p>
  <p>
    <a href="https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml"><img src="https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml/badge.svg?branch=main" alt="CI"></a>
    <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-%E2%89%A53.32.0-02569B?logo=flutter&amp;logoColor=white" alt="Flutter 3.32.0 或更高版本"></a>
    <a href="https://github.com/cockpit-dev/cockpit#black-box-targets"><img src="https://img.shields.io/badge/platforms-6%20supported-2E7D32" alt="支持 Android、iOS、macOS、Linux、Windows 和 Web"></a>
    <a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/flutter_cockpit/LICENSE"><img src="https://img.shields.io/github/license/cockpit-dev/cockpit" alt="MIT 许可证"></a>
  </p>
  <p><a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/flutter_cockpit/README.md">English</a> · <a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/flutter_cockpit/README.zh-CN.md">简体中文</a></p>
</div>

`flutter_cockpit` 是 Cockpit 面向 AI 驱动 Flutter 源码开发、检查与控制的一等应用内
适配器，独立于已安装生产应用使用的黑盒路径。

它提供：

- 通过 `FlutterCockpit.runApp` 或 `FlutterCockpitApp` 做运行时 bootstrap
- 点击、输入、手势、等待、断言、截图、快照等命令执行能力
- VM 平台使用 HTTP、Web 使用 Cockpit WebSocket bridge 的远程会话传输
- 结构化 Widget、Element、RenderObject、semantics、route、focus、log、runtime
  error、HTTP/SSE/WebSocket network 与 rebuild 状态
- snapshot、artifact、recording 和 bundle 模型
- 面向 AI 摘要的 target / plane / surface / fallback 运行时模型

## 安装

需要 Flutter 3.32.0 或更高版本。

```yaml
# cockpit/pubspec.yaml
dev_dependencies:
  flutter_cockpit: any
```

runtime 只作为开发依赖。所有 `flutter_cockpit` import 和接入代码都放在
`cockpit/` 下面，生产 `lib/` 代码和生产入口保持不变。

Darwin 原生接入同时支持 CocoaPods 与 Swift Package Manager。包内为 iOS 和
macOS 都提供 `.podspec` 与 `Package.swift`，二者复用同一套原生源码和隐私清单。
Flutter 会使用宿主工程选择的集成方式，CocoaPods 工程无需迁移到 SwiftPM。

runtime 包会为 Android、iOS、macOS、Linux、Windows 和 web 声明原生插件入口。
这样 cockpit 入口被编译时，应用窗口截图和录屏 fallback 可以稳定注册。接入代码
必须放在 `cockpit/`，不要放进生产 `lib/` 代码。应用内的 Flutter-view 截图、
基于 Element 的检查与控制、网络信号、运行时诊断和远程会话都在 runtime 内完成，
不要求业务应用编写 `Semantics`。系统弹窗、通知、
宿主截图、宿主录屏等系统级证据仍应通过 `cockpit` 的 system action 驱动，这样能力发现
和平台降级路径才保持真实。

### 接入 AI Agent

让当前 AI 宿主安装 CLI、完整 Skill、原生适配器和 MCP：

```text
First fetch and read the complete Cockpit installation guide with `curl -fsSL https://raw.githubusercontent.com/cockpit-dev/cockpit/main/skills/cockpit/INSTALL.md`, then install or update the CLI, complete cockpit Skill, native adapter, and cockpit_mcp for the current AI host exactly as that guide directs.
```

指南覆盖 Codex、Claude Code、Cursor、Gemini CLI、Kiro、OpenCode、Pi、
Oh My Pi、Cline、GitHub Copilot、Windsurf、Roo Code 和可移植 fallback 安装。

## 推荐接入方式

在 `cockpit/` 下创建一个不发布的 Flutter package。它在本地依赖真实应用，
并把 `flutter_cockpit` 放在 shell 自己的 `dev_dependencies` 中；两者都不会进入
生产 package 的依赖图。全局安装的 `cockpit` CLI 不是应用依赖。保持正常生产入口
和生产 `lib/` 不变，不要在生产 `lib/` 代码中 import `flutter_cockpit`。

```yaml
# cockpit/pubspec.yaml
name: your_app_cockpit
publish_to: none

environment:
  sdk: '>=3.8.0 <4.0.0'
  flutter: '>=3.32.0'

dependencies:
  flutter:
    sdk: flutter
  your_app:
    path: ..

dev_dependencies:
  flutter_cockpit: any
```

把 `your_app` 替换成真实应用 package 名，并在 `cockpit/` 内执行
`flutter pub get`。

如果应用使用 Pub workspace，把 `cockpit/` 加到根 `workspace` 列表，在 shell
manifest 中添加 `resolution: workspace`，并用兼容的应用版本约束替代 `path: ..`；
然后从 workspace 根目录执行 `flutter pub get`。这样 shell 仍只在本地解析，不会
把 Cockpit 加入生产 package 依赖。

```dart
import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';

import 'package:your_app/app_shell.dart';

Future<void> main() async {
  runApp(buildCockpitDevelopmentApp());
}

Widget buildCockpitDevelopmentApp() {
  return FlutterCockpitApp(
    config: FlutterCockpitConfig.production(
      remoteSession: CockpitRemoteSessionConfiguration.resolveFromEnvironment(
        fallback: const CockpitRemoteSessionConfiguration(
          enabled: true,
          host: '127.0.0.1',
          port: 47331,
        ),
      ),
    ),
    child: MaterialApp(
      navigatorObservers: <NavigatorObserver>[
        FlutterCockpit.navigatorObserver,
      ],
      home: const AppShell(),
    ),
  );
}
```

把 `package:your_app/app_shell.dart` 换成你现有应用根组件或 bootstrap
的真实 import。Cockpit 的 target launch 操作会注入
`FLUTTER_COCKPIT_REMOTE_*` 这组 dart-define，所以
`resolveFromEnvironment(...)` 可以在不接管生产入口的前提下启用远程控制面。
只从独立 shell 的 `main.dart` 接入 `FlutterCockpit.navigatorObserver`。`FlutterCockpitApp` 会自动发现 Flutter Router、`RouterConfig`、`go_router` 及其他 Router 类库使用的公开 `RouteInformationProvider`，所以业务 app 自有 router 通常不需要额外 route bridge。

嵌套 Navigator 需要各自使用独立 observer，这样嵌套路由 pop 后可以恢复当前父级路由：

```dart
Navigator(
  observers: <NavigatorObserver>[
    FlutterCockpit.createNavigatorObserver(),
  ],
  onGenerateRoute: buildRoute,
)
```

同一工厂可用于暴露 navigator observer 的路由库，包括 root navigator 和 shell navigator。对于挂载后才动态创建、无法从组件树发现的 router，可在 `cockpit/` 中通过 `FlutterCockpit.bindRouteInformationProvider(...)` 绑定其公开 provider。仅当 router 既不暴露 provider 也不暴露 observer 时，才使用 `FlutterCockpit.setCurrentRouteName(...)`；`flutter_cockpit` 不直接依赖任何第三方路由包。

运行：

```bash
cd cockpit
flutter run --target main.dart
```

## 运行时暴露的能力

- 低侵入根级 bootstrap
- 命令路由与执行
- UI 快照及 live、baseline、investigate、forensic 诊断档位，包括有界的已挂载
  Element 树
- accessibility、network、runtime、rebuild 信号
- 截图和录屏请求
- 远程会话状态与命令端点

HTTP 诊断默认用 `*` 掩码凭据值，同时保留鉴权类型、Cookie 名、query key 和 JSON
字段名等定位问题所需的结构。只有在本地确实需要查看有界原文时，才应在开发
专用入口显式使用 `CockpitHttpNetworkObserverConfiguration(redact: false)`；
不要在生产入口或生成证据的 CI 中关闭脱敏。

`FlutterCockpitRoot` 会把 Flutter hot reload 视为 runtime diagnostic generation
边界。reassemble 时会清除上一 generation 的错误和未消费 recorded steps；reload 后
应用新产生的错误仍会正常捕获。

宿主侧编排、MCP、workspace tooling 和交付验证在 [`cockpit`](https://pub.dev/packages/cockpit) 中。
运行时 bundle 模型现在会保留 `targetKind`、`primaryExecutionPlane`、`planesUsed`、`surfaceKindsUsed`、`fallbackCount`，以及 step / observation 级别的 plane 元数据，方便宿主侧准确解释这次控制是按预期平面完成，还是发生了受控降级。
在 web 上，runtime 直接支持 Flutter Element 与 Flutter-view 控制路径；method channel 会注册为“显式不可用”的 stub，这样能力判断会保持真实，不会退化成缺少插件的噪音报错。移动端和桌面端的原生 method-channel 录屏与截图会通过包的插件入口注册，并作为应用窗口级证据 fallback 使用；如果目标是证明系统弹窗、通知、宿主窗口或跨应用行为，仍优先使用 `cockpit` 提供的 system/host 证据链路。

包地址：[pub.dev/packages/flutter_cockpit](https://pub.dev/packages/flutter_cockpit)
