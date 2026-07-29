<div align="center">
  <a href="https://github.com/cockpit-dev/cockpit">
    <img src="assets/brand/cockpit-mark.svg" width="128" alt="Cockpit logo">
  </a>
  <h1>Cockpit 2.0</h1>
  <p><strong>统一完成 Flutter 快速开发验证与任意应用黑盒 E2E。</strong></p>
  <p>
    <a href="https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml"><img src="https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml/badge.svg?branch=main" alt="Cockpit 2.0 发布门禁"></a>
    <a href="https://github.com/cockpit-dev/cockpit/blob/main/LICENSE"><img src="https://img.shields.io/github/license/cockpit-dev/cockpit" alt="BSD 3-Clause 许可证"></a>
  </p>
  <p>
    <a href="https://pub.dev/packages/cockpit"><img src="https://img.shields.io/pub/v/cockpit?logo=dart&amp;label=cockpit" alt="pub.dev 上的 cockpit 包"></a>
    <a href="https://pub.dev/packages/flutter_cockpit"><img src="https://img.shields.io/pub/v/flutter_cockpit?logo=flutter&amp;label=flutter_cockpit" alt="pub.dev 上的 flutter_cockpit 包"></a>
    <a href="https://pub.dev/packages/cockpit_protocol"><img src="https://img.shields.io/pub/v/cockpit_protocol?logo=dart&amp;label=cockpit_protocol" alt="pub.dev 上的 cockpit_protocol 包"></a>
  </p>
  <p>
    <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-%E2%89%A53.8.0-0175C2?logo=dart&amp;logoColor=white" alt="Dart 3.8.0 或更高版本"></a>
    <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-%E2%89%A53.32.0-02569B?logo=flutter&amp;logoColor=white" alt="Flutter 3.32.0 或更高版本"></a>
    <a href="https://github.com/cockpit-dev/cockpit#black-box-targets"><img src="https://img.shields.io/badge/platforms-6%20supported-2E7D32" alt="支持 Android、iOS、macOS、Linux、Windows 和 Web"></a>
  </p>
  <p><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a></p>
</div>

Cockpit 是面向 AI、CI 和本地开发的生产级 E2E 自动化与验证框架。
Cockpit 2.0 可以把已安装的 Android/iOS 应用作为黑盒独立操控，也可以通过
Flutter 语义桥获得更丰富的应用内能力；CLI、MCP 和未来独立客户端共享同一套
类型化协议。

核心能力包括：

- 独立 YAML/JSON case 与 suite；
- Flutter semantic、原生 accessibility、system、visual、coordinate 平面；
- target 发现、注册、启动、检查与真实能力声明；
- 依赖 DAG、fixture、matrix、retry、有界并发和 fail-fast；
- 持久事件、可恢复 suite 检查点、精确 session 亲和、取消、artifact，以及
  完整离线回归报告 bundle；
- 每用户一个认证 Supervisor，每 workspace 一个隔离 worker；
- 资源化 CLI、HTTP/SSE API 和 MCP，不内置 GUI。

## 包结构

- [`cockpit_protocol`](packages/cockpit_protocol)：平台无关 DTO、测试 DSL、
  JSON Schema 和 OpenAPI。
- [`cockpit`](packages/cockpit)：Supervisor、worker、平台 driver、CLI、MCP、
  报告和 artifact。
- [`flutter_cockpit`](packages/flutter_cockpit)：可选的 Flutter 语义、观测、截图
  和录屏桥。

最低版本为 Dart 3.8.0、Flutter 3.32.0：

```yaml
dev_dependencies:
  cockpit: any
  flutter_cockpit: any # 仅 Flutter 语义桥需要
```

Cockpit 应保持为开发依赖。黑盒原生应用测试不要求修改被测应用源码，也不要求
接入 Flutter 包。

## 安装 Skill

仓库维护的 skill 位于 [`skills/cockpit`](skills/cockpit)。

推荐让当前 AI 宿主直接完成安装，复制下面的提示词：

```text
Install the cockpit skill for the current AI host by following https://github.com/cockpit-dev/cockpit/blob/main/skills/cockpit/INSTALL.md
```

完整的宿主安装说明见
[`skills/cockpit/INSTALL.md`](skills/cockpit/INSTALL.md)，原生适配器和 MCP
配置见 [Agent 接入指南](docs/agent-integrations.md)。

## 运行架构

`cockpit` 命令会发现或启动 `COCKPIT_HOME` 下的常驻 daemon。daemon 负责认证、
workspace 身份、授权、准入、lease、端口、run 投影和 artifact；每个活跃
workspace/engine 启动独立 worker。系统不存在跨项目的全局 latest project 或
latest session。

```text
CLI / MCP / 第三方客户端
          |
      认证 HTTP/SSE
          |
       Supervisor
          |
  workspace 隔离 worker
          |
Flutter bridge / Android ADB / iOS WDA / host driver
```

并行开发多个项目时，先分别注册，之后显式传 `workspaceId`，或者从唯一匹配的
workspace 目录中执行命令：

```bash
dart run cockpit daemon start
dart run cockpit root add --path /work/projects --label projects
dart run cockpit workspace register --root-id <rootId> --path /work/projects/app-a
dart run cockpit workspace register --root-id <rootId> --path /work/projects/app-b
dart run cockpit workspace list
```

## CLI 输出

默认 `auto` 格式是面向 Agent 终端循环的紧凑语义文本。使用
`--detail minimal|standard|full` 控制投影体积，使用
`--stdout-format json` 获取完整协议 envelope，使用 `jsonl` 流式读取 run event。
`--output <file>` 会原子写入完整 JSON，终端仅返回路径、字节数和 SHA-256。
artifact 二进制始终下载到 `--output`，绝不以 Base64 输出。

## 生产授权

危险操作和测试 safety effect 默认拒绝。授权文件固定为
`COCKPIT_HOME/authorization.json`；使用 CLI 校验和原子替换。daemon 运行时必须
重启后才能使用新授权，避免同一进程中权限漂移。

```json
{
  "schemaVersion": "cockpit.supervisor.authorization/v2",
  "allowedDangerousOperations": [
    "app.launch",
    "app.restart",
    "app.stop",
    "command.batch",
    "command.run",
    "evidence.screenshot.capture",
    "lease.recover",
    "recording.start",
    "recording.stop",
    "system.action",
    "target.launch"
  ],
  "allowedOperationSafetyEffects": [
    "capture",
    "externalSideEffect",
    "permission",
    "recording",
    "reset",
    "system"
  ],
  "allowedTargetEnvironments": [
    "development",
    "test",
    "staging",
    "production"
  ],
  "allowedSafetyEffects": [
    "communication",
    "credentialSensitive",
    "destructive",
    "externalNavigation",
    "financial",
    "permissionChange"
  ],
  "allowedEnvironmentSecretNames": ["E2E_PASSWORD"]
}
```

```bash
dart run cockpit daemon policy validate --file authorization.json
dart run cockpit daemon policy apply --file authorization.json --restart
dart run cockpit daemon policy show
```

本地需要显式全权运行时，使用 `dart run cockpit daemon start --yolo`（或
`daemon restart --yolo`）。YOLO 只对本次 daemon 进程生效；不带该开关的启动或
重启会使用持久化的受限策略。`daemon status`、attempt manifest 和 suite
`report.json` 都会记录实际 `authorizationMode`。

quarantined lease 会持续阻塞资源，直到 cleanup 验证成功。Supervisor 提供
`lease.list`，以及需要显式授权 `reset` effect 的 `lease.recover`；恢复请求必须精确
匹配 lease、workspace、resource 和 holder 身份。只有逻辑资源可在明确传入
`forceRelease: true` 后解除未验证隔离，forwarded port 永远必须通过真实 cleanup
验证，不能强制释放。

只有被点名的环境变量 secret 会传入 worker。`production` 和 `unknown` 可以显式
授权，但默认策略不会放行。

## 黑盒应用

无需修改应用即可注册已经安装的 Android/iOS 应用：

```bash
dart run cockpit target register \
  --workspace-id <workspaceId> \
  --platform android \
  --device-id emulator-5554 \
  --target-kind nativeApp \
  --app-id com.example.app \
  --environment test \
  --mode automation \
  --idempotency-key android-target-001

dart run cockpit target launch --workspace-id <workspaceId> --target-id <targetId> \
  --idempotency-key android-launch-001
dart run cockpit target inspect --workspace-id <workspaceId> --target-id <targetId>
```

Android 使用 ADB 和原生 accessibility；iOS Simulator 使用 `simctl`，原生 iOS
UI 操作使用可达的 WebDriverAgent；物理 iOS 设备在可用时通过 `devicectl` 管理
安装和生命周期。环境不具备某项能力时，Cockpit 会返回 unsupported/blocked，
不会伪造成功。

已经安装的 Flutter 应用或原生壳内嵌 Flutter 的混合应用，应使用
`targetKind: flutterApp`、真实 `appId` 且不绑定 entrypoint，并让 case 使用
`native` plane。Cockpit 会通过 system control 启动应用并无侵入操作完整原生
accessibility tree；Flutter-aware resolver 只在局部折叠同 bounds 的祖先/后代重复
semantics 并优先可操作节点，不会屏蔽原生页面、platform view、WebView 或真实列表项。
只有需要开发态 bridge 时才使用绑定 entrypoint 的 Flutter target 和 `semantic` plane。

Flutter target 通过 CLI、MCP 和 `operation run` 共用结构化启动配置。入口、设备、
模式、flavor 及远程控制参数由 Cockpit 管理；调用方可以传入多个 dart define、
define 文件、安全的额外 Flutter 参数、进程环境变量，以及最长 30 分钟的启动预算：

```bash
dart run cockpit target launch \
  --workspace-id <workspaceId> \
  --target-id <flutterTargetId> \
  --dart-define API_URL=https://api.example.test \
  --dart-define-from-file config/staging.json \
  --env LOG_LEVEL=debug \
  --flutter-arg=--track-widget-creation \
  --launch-timeout-ms 1800000 \
  --idempotency-key flutter-launch-001
```

等价的 operation input 使用 `launchConfiguration` 对象，字段为 `dartDefines`、
`dartDefineFromFiles`、`flutterArgs` 和 `environment`。启动配置值不会出现在操作
输出中；已经安装的黑盒 target 不接受 Flutter 启动字段。
Android 和 iOS 上的 `environment` 只配置 Flutter 构建进程，移动应用进程不会继承
任意宿主机环境变量；应用自身需要读取的值应使用 Dart define 或应用自己的配置通道。

每个已公开 operation 都包含 `executionMode`、`defaultTimeoutMs` 和
`maximumTimeoutMs`。同步操作会阻塞到结果，可通过
`operation run --timeout-ms <值>` 或绝对 `--deadline` 覆盖预算，两者不能同时传入。
case/suite 是持久化异步 job：提交后立即返回 `runId`，客户端再消费事件并读取终态报告。
`case run --timeout-ms` 默认 30 分钟、最长 6 小时；`suite run --timeout-ms` 默认
2 小时、最长 24 小时。步骤和清理超时仍是互相独立的内部预算。

每个步骤都可以用 `plane` 显式选择 `semantic`、`native`、`visual` 或
`coordinate`。没有覆盖时，截图断言自动走 visual，system 与位置轨迹动作走 native，
视觉/坐标 locator 走对应 plane，包含原生专用约束的 locator 走 native，其余步骤继承
case plane。绑定 entrypoint 的 Flutter session 会同时保留语义 driver 和同一应用/设备的
次级 system driver，因此一个 case 可以先检查 Widget，再跨越原生页面、platform view、
权限弹窗或只能视觉识别的区域，无需修改被测业务应用。
次级执行面的权威能力来自 `target.inspect` operation 结果中的
`output.systemControl`；该 profile 已脱敏，客户端不得尝试从 `app.get` 重建，因为平台
应用标识与进程标识会按设计隐藏。

统一动作集合除手势、编辑、键盘、等待、断言、取证、录屏和 system action 外，还包括
`copyText`、`eraseText`、`pasteText` 与有界 `travel` 轨迹。visual locator 使用
workspace 内的图片文件和可选相似度阈值；`assertScreenshot` 将实时截图与 workspace
内 baseline 对比，并把 actual、baseline、diff 图片作为离线 artifact 记录，图片字节
不会进入终端输出。baseline 必须按平台、设备或 viewport、像素比和方向等稳定 visual
profile 选择。尺寸不一致代表 profile 不匹配或布局回归，Cockpit 不会缩放图片来制造
可比较结果。

## Case 与 Suite

case/suite 使用 `schemaVersion: cockpit.test/v2`。先验证文档，再使用稳定的
idempotency key 提交：

```bash
dart run cockpit case validate --workspace-id <workspaceId> --file cases/login.yaml
dart run cockpit case run --workspace-id <workspaceId> \
  --document-id <documentId> --case-id login \
  --idempotency-key login-2026-07-24 --inputs-json '{}' \
  --timeout-ms 1800000

dart run cockpit suite validate --workspace-id <workspaceId> --file suites/regression.yaml
dart run cockpit suite run --workspace-id <workspaceId> \
  --document-id <documentId> --suite-id regression \
  --idempotency-key regression-2026-07-24
dart run cockpit suite report --run-id <runId> \
  --output-dir cockpit-report
```

worker 意外退出后，已完成节点不会重跑，执行中的 attempt 会变为 `interrupted`，
只有 suite retry 策略允许时才继续。持久化的 fixture/row session 必须恢复为同一
健康资源；无法证明时会明确失败，不会假装 fixture 状态仍有效。

生命周期按已有最小作用域组合：suite fixture 负责 campaign/attempt 级 setup 与
teardown，case `setup`/`finally` 负责 case 生命周期，step `evidence` 负责动作前后或
失败取证，显式 `startRecording`/`stopRecording` 包围真正需要录屏的步骤区间。
`if`、有界 `retry`/`loop` 和 fragment 可以在这些作用域内正常组合，因此无需再引入
一套重复的通用 pre/post hook。

每个完成的 suite 都会发布一个可携带的报告 bundle。使用
`suite report --output-dir cockpit-report` 导出；CLI 只下载 run manifest 声明的
文件，下载时校验元数据和 SHA-256，并在 bundle 完整后才提交目录，目标目录不能预先
存在。离线打开
`index.html` 即可按发布摘要、覆盖范围、执行过程、证据、诊断和环境/文件逐层查看；
搜索、筛选、深链接、响应式布局和打印布局均不依赖服务或网络。
这些入口按任务组织，而不是按角色复制或隐藏内容；开发、测试、产品和发布负责人查看的是
同一份事实与证据链，只是从各自当前需要解决的问题进入。
`report.json` 是唯一规范事实图，包含 suite/case 定义、attempt、详细步骤、断言和证据引用；
`manifest.json` 记录其余每个文件的语义归属、大小、媒体类型和 SHA-256。
`summary.md`、`junit.xml`、`run/events.jsonl`、语义化 case 目录以及截图、录屏、日志和
snapshot 都是同一事实图的可携带视图。客户端必须保持相对路径并先校验 manifest。

## MCP、客户端与 CI

```bash
dart run cockpit serve-mcp
# 或
dart run cockpit_mcp
dart run cockpit serve-mcp --profile dart
```

MCP 只是认证 Supervisor 客户端，不会在进程内构造 driver 或应用服务。它提供有界的
roots、workspaces、operations、targets、documents、cases、suites、runs 和 artifacts
资源。官方或第三方 GUI 应使用 `/api/v2`、认证 SSE、公开 DTO 和带 digest 校验的
artifact 下载。2.0 暂不提供 Flutter GUI，也不内置 HTML dashboard；HTML 只作为
可移植回归报告 artifact 生成。

默认 `core` profile 保持控制面精简；可选 profile 为 `dart`、`flutter`（包含
`dart`）、`app`、`e2e`（包含 `app`）和 `all`，并可用 `--enable <name>`、
`--disable <name>` 精确覆盖。`dart` profile 通过同一个 workspace 隔离 Supervisor
提供 analyze、format、fix、test、LSP、pub、package URI/search 和项目创建工具。
用户未安装官方 Dart MCP server 时它可以完整替代常用开发能力，但 Cockpit 不嵌入、
不代理官方 server。

Codex、Claude Code、Cursor、Gemini CLI、Kiro、OpenCode、GitHub Copilot、
Windsurf、Cline、Roo Code、Pi 和 Oh My Pi 的接入方式见
[Agent 接入指南](docs/agent-integrations.md)。

CI 可以让前台 daemon 独占生命周期：

```bash
dart run cockpitd \
  --home=/tmp/cockpit-ci \
  --foreground-workspace=/workspace/app \
  --foreground-submission=/workspace/run-submission.json
```

## 发布门禁

`.github/workflows/example-e2e.yml` 是 Cockpit 2.0 发布前的强制门禁。各个并行 job
会验证格式、静态分析、仓库契约、所有 package 与示例测试、三个公开包的发布 dry-run，
以及 Android、iOS、macOS、Linux、Web、Windows 真实回归。Android 与 iOS 必须证明
原生 locator/action/assertion 控制，只有截图回退不能通过核心平台门禁。只有全部 job
都成功终止，并产出可校验的终态报告
和 artifact，版本才允许发布。每个平台都会运行一条复杂 suite，覆盖 fixture、
setup/finally、fragment、分支、有限 retry/loop、逐步 timeout、matrix、有限并发、截图、
完整的创建/读取/删除业务流程、全部 Flutter 手势/文本/键盘/语义命令、按能力执行的录屏
和离线 bundle 完整性。每条命令都必须通过可见 UI 结果断言并进入规范报告，不能只凭命令
返回成功。排查失败时先等待整个矩阵结束，再统一以上传的 report、event stream、artifact
和 daemon log 为准，避免边运行边反复猜测。

## 文档

详细文档：

- [`packages/cockpit/README.md`](packages/cockpit/README.md)
- [`packages/flutter_cockpit/README.md`](packages/flutter_cockpit/README.md)
- [`packages/cockpit_protocol/README.md`](packages/cockpit_protocol/README.md)
- [`docs/agent-integrations.md`](docs/agent-integrations.md)
- [`skills/cockpit/references/environments.md`](skills/cockpit/references/environments.md)
- [`docs/architecture/cockpit-2.0-foundation-migration-inventory.md`](docs/architecture/cockpit-2.0-foundation-migration-inventory.md)
