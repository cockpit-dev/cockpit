<div align="center">
  <a href="https://github.com/cockpit-dev/cockpit">
    <img src="assets/brand/cockpit-mark.svg" width="112" alt="Cockpit logo">
  </a>
  <h1>Cockpit</h1>
  <p><strong>面向真实 Flutter 应用的 AI-first 控制与验证平台。</strong></p>
  <p>检查真实界面 · 执行真实操作 · 留下可复核证据</p>
  <p>
    <a href="https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml"><img src="https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml/badge.svg?branch=main" alt="CI"></a>
    <a href="https://github.com/cockpit-dev/cockpit/blob/main/LICENSE"><img src="https://img.shields.io/github/license/cockpit-dev/cockpit" alt="MIT 许可证"></a>
    <a href="https://pub.dev/packages/cockpit"><img src="https://img.shields.io/pub/v/cockpit?logo=dart&amp;label=cockpit" alt="cockpit on pub.dev"></a>
  </p>
  <p><a href="README.md">English</a> · <a href="docs/agent-integrations.md">AI host 接入</a> · <a href="skills/cockpit/INSTALL.md">安装 Cockpit</a></p>
</div>

Cockpit 让 AI 操作正在运行的应用，而不是对截图猜测。Flutter 拥有一等的结构检查和
真实交互能力；原生、桌面和 Web 应用也可以作为黑盒 targets 使用。

## 一眼看懂

- **真正理解 Flutter。** 直接检查已挂载的 `Element` 与 `RenderObject`，生成稳定结构
  选择器，操作自定义组件并展开懒加载内容，不要求业务页面添加 `Semantics` 标签。
- **一条短开发链路。** 启动一次并复用短小写 base-36 handle，持续检查、点击、输入、
  滚动、打开链接、reload、诊断和截图。
- **覆盖真实边界。** 支持系统弹窗、原生页面、platform view、WebView、deep link、日志、
  运行时错误和 network evidence，覆盖 Android、iOS、macOS、Linux、Windows 与 Web。
- **为 AI 节省上下文。** 默认输出简洁 LON；需要解析时再用 JSON 或 YAML。大树和证据只
  返回经过验证的路径。
- **一个公开控制面。** CLI、MCP、REST/SSE、Cockpit Console 和 Flutter 集成测试共享
  同一套类型化资源与 operation contract。

## 60 秒 Flutter 流程

在完成 development shell 接入的 Flutter 项目中执行：

```bash
cockpit dev start
cockpit dev inspect "Save"
cockpit dev tap "Save"
cockpit dev type "hello" --into "Message"
cockpit dev scroll "Activity"
cockpit dev reload
cockpit dev diagnose
cockpit dev screenshot
```

`dev` 负责项目发现、进程、端口、bridge 和 session 隔离。遇到歧义会明确失败而不是猜测；
遇到意外叠层或系统提示会给出有界恢复路径。

多个 checkout 会自动保持隔离，日常使用 `cockpit dev` 无需手动注册 workspace；可用
`cockpit session list` 和 `cockpit session show HANDLE` 查看运行中的项目。显式 `--session HANDLE` 只作用于当前命令，
返回的恢复 `next` 会继续绑定同一个 development session。

## Flutter 集成测试

继续使用 Flutter 官方 `integration_test` runner，同时获得 Cockpit 的真实定位、原生证据
和宿主操作：

```bash
flutter pub add --dev flutter_cockpit_test
```

```dart
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
```

支持结构与多条件选择器、真实 hit-test 手势、懒加载和嵌套滚动、断言、快照、原生截图、
录屏、viewport、系统操作，以及每次调用独立的 timeout。

## 选择合适的包

| 包 | 用途 |
| --- | --- |
| [`cockpit`](packages/cockpit) | CLI、Supervisor、driver、MCP、REST/SSE、case、suite、报告和 artifact |
| [`flutter_cockpit`](packages/flutter_cockpit) | 应用内 Flutter 检查与控制 bridge |
| [`flutter_cockpit_test`](packages/flutter_cockpit_test) | 带 Cockpit 选择器和原生证据的 Flutter `integration_test` |
| [`cockpit_protocol`](packages/cockpit_protocol) | 共享 DTO、schema、测试 DSL 和 OpenAPI |
| [`cockpit_console`](packages/cockpit_console) | 独立桌面 UI：session、run、operation、日志和网络活动 |

已发布包最低需要 Dart 3.8.0；Flutter 包最低需要 Flutter 3.32.0。不要在生产
`lib/` 代码中添加 `flutter_cockpit` import，应放在 development shell 或仅测试 package。

## 给 AI Agent 安装

先安装 CLI：

```bash
dart pub global activate cockpit any
cockpit --help
```

修改宿主配置前，先用下面的提示词获取并阅读完整安装文档：

```text
First fetch and read the complete Cockpit installation guide with `curl -fsSL https://raw.githubusercontent.com/cockpit-dev/cockpit/main/skills/cockpit/INSTALL.md`, then install or update the Cockpit runtime once and load the complete Skill. Use CLI + Skill as the default control surface; configure one Cockpit MCP server only if this host cannot reliably run shell commands or typed tools are explicitly needed. Do not configure a second MCP server or duplicate Skill copy.
```

规范入口是 [`skills/cockpit/INSTALL.md`](skills/cockpit/INSTALL.md)，覆盖 Codex、Claude Code、
Cursor、Gemini CLI、Kiro、OpenCode、GitHub Copilot、Windsurf、Cline、Roo Code、Pi、OMP 和
Oh My Pi。完整接入说明见 [`docs/agent-integrations.md`](docs/agent-integrations.md)。

CLI 和 MCP 共享同一个 Supervisor、session registry 和 artifact store。默认使用 CLI +
Skill；只有明确需要 typed tools 时才选择 MCP。每个任务只启用一个主入口，不要通过两者
重复执行同一个修改操作。

## Case、Suite 与 API

同一条流程可以直接升级为可重复验证。公开 Supervisor 资源包括 `roots`、`workspaces`、
`operations`、`targets`、`documents`、`cases`、`suites`、`runs` 和 `artifacts`，控制面是
`/api/v2`，MCP 客户端是 `cockpit_mcp`。

```bash
cockpit daemon start
cockpit root add --path /work/projects --label projects
cockpit workspace register --root-id ROOT --path /work/projects/app
cockpit target register --workspace-id WORKSPACE --platform android \
  --device-id emulator-5554 --target-kind nativeApp --app-id com.example.app
cockpit case run --file cases/login.yaml --idempotency-key login-local
cockpit suite run --file suites/regression.yaml --idempotency-key regression-local
```

使用 `cockpit serve-mcp`（或 `cockpit_mcp`）启动 MCP。REST 客户端先从
`/api/v2/operations/schema` 读取 operation descriptor，再执行对应命令；认证 SSE 提供
可恢复的 run event。Cockpit Console 使用同一套公开资源，可同时监听多个 development
session。

## 可预测的 Flutter 定位

定位器直接读取源码可验证的 Element/RenderObject 结构，不依赖猜测。返回的 `sel` 可以
直接交给 action；多个条件取交集；稳定祖先范围优先于脆弱的 widget path。已知自定义控件
时可直接使用 `CompanyButton >> Text["Save"]`。

交互归属始终明确：合并到祖先的 `Semantics` 不会让被动后代变成可操作 target。
`IgnorePointer(ignoring: true)` 或 `AbsorbPointer(absorbing: true)` 下的后代不会声明
mutation action；存在多个被代理 control 时不猜测状态。

`dev scroll TARGET` 会发现正确的滚动容器、挂载 lazy 内容、处理嵌套祖先、触边反向搜索并
验证真实 hit-test。只有需要周边结构时才使用 `dev tree --view more` 或 `--view full`，
标准输出只返回已验证的 artifact 路径。

## 授权策略

本地开发可使用进程级 yolo；CI、staging 和 production 应使用明确策略。Cockpit 不读取
keychain 或 secret store。

```json
{
  "schemaVersion": "cockpit.supervisor.authorization/v2",
  "allowedDangerousOperations": ["app.launch", "app.restart", "app.stop", "command.run", "evidence.screenshot.capture", "target.launch"],
  "allowedOperationSafetyEffects": ["capture", "externalSideEffect", "permission", "recording", "reset", "system"],
  "allowedTargetEnvironments": ["development", "test", "staging"],
  "allowedSafetyEffects": ["communication", "credentialSensitive", "destructive", "externalNavigation", "financial", "permissionChange"],
  "allowedEnvironmentSecretNames": []
}
```

## 继续了解

- [`cockpit` 指南](packages/cockpit/README.zh-CN.md)
- [`flutter_cockpit` 指南](packages/flutter_cockpit/README.zh-CN.md)
- [`flutter_cockpit_test` 指南](packages/flutter_cockpit_test/README.zh-CN.md)
- [`cockpit_protocol` 指南](packages/cockpit_protocol/README.md)
- [`Cockpit Skill`](skills/cockpit/SKILL.md)
- [`Agent 接入指南`](docs/agent-integrations.md)

Cockpit 以 MIT 许可证开源。
