<div align="center">
  <a href="https://github.com/cockpit-dev/cockpit">
    <img src="https://raw.githubusercontent.com/cockpit-dev/cockpit/main/assets/brand/cockpit-mark.svg" width="128" alt="Cockpit logo">
  </a>
  <h1>cockpit</h1>
  <p><strong>Flutter 开发控制面与无头黑盒 E2E 执行器。</strong></p>
  <p>
    <a href="https://pub.dev/packages/cockpit"><img src="https://img.shields.io/pub/v/cockpit?logo=dart&amp;label=pub.dev" alt="pub.dev 上的 cockpit 版本"></a>
    <a href="https://pub.dev/packages/cockpit/score"><img src="https://img.shields.io/pub/points/cockpit?logo=dart" alt="cockpit pub points"></a>
    <a href="https://pub.dev/packages/cockpit/score"><img src="https://img.shields.io/pub/likes/cockpit?logo=dart" alt="cockpit 在 pub.dev 上的点赞数"></a>
    <a href="https://pub.dev/packages/cockpit/score"><img src="https://img.shields.io/pub/popularity/cockpit?logo=dart" alt="cockpit 在 pub.dev 上的流行度"></a>
  </p>
  <p>
    <a href="https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml"><img src="https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml/badge.svg?branch=main" alt="CI"></a>
    <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-%E2%89%A53.8.0-0175C2?logo=dart&amp;logoColor=white" alt="Dart 3.8.0 或更高版本"></a>
    <a href="https://github.com/cockpit-dev/cockpit#black-box-targets"><img src="https://img.shields.io/badge/platforms-6%20supported-2E7D32" alt="支持 Android、iOS、macOS、Linux、Windows 和 Web"></a>
    <a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/cockpit/LICENSE"><img src="https://img.shields.io/github/license/cockpit-dev/cockpit" alt="BSD 3-Clause 许可证"></a>
  </p>
  <p><a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/cockpit/README.md">English</a> · <a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/cockpit/README.zh-CN.md">简体中文</a></p>
</div>

`cockpit` 是 Cockpit 3.0 面向 Flutter/Dart 开发与无头黑盒 E2E 的认证宿主控制面，
包含 Supervisor daemon、隔离 workspace worker、resource-oriented CLI 和轻量 MCP
server，不内置 GUI 或 Web dashboard。

## 安装

需要 Dart 3.8.0 或更高版本；Flutter workspace 使用 Flutter 3.32.0 或更高版本
内置的 Dart SDK。

```bash
dart pub global activate cockpit any
cockpit --help
```

使用 `cockpit update` 安装并验证最新版本，同时要求 Pub 解析出的版本不得低于当前
executable；即使 Pub 版本索引尚未刷新，也会安全失败而不会把 Cockpit 降级。随后
它会把源码安装的原生 executable 安全交还给 Pub，再恢复为单个优化后的 AOT
executable，删除旧版与临时升级 payload，并在保留授权模式和持久化状态的前提下
替换旧 Supervisor。Dart Pub 的共享下载缓存仍由 Pub 自己管理，Cockpit 不会删除
其他包的缓存。

包发布四个 executable：

- `cockpit`：交互式资源命令
- `cockpit_mcp`：MCP stdio server
- `cockpitd`：Supervisor daemon 与 foreground CI runner
- `cockpit_worker`：私有 workspace worker 进程

### 接入 AI Agent

推荐让当前 AI 宿主直接安装 CLI、完整 Skill、原生适配器和 MCP，复制下面的提示词：

```text
Install Cockpit for the current AI host, including the CLI, complete cockpit Skill, native adapter, and cockpit_mcp when supported, by following https://github.com/cockpit-dev/cockpit/blob/main/skills/cockpit/INSTALL.md
```

完整的宿主安装与验收说明见
[`skills/cockpit/INSTALL.md`](https://github.com/cockpit-dev/cockpit/blob/main/skills/cockpit/INSTALL.md)，
原生适配器和 MCP 配置见
[Agent 接入指南](https://github.com/cockpit-dev/cockpit/blob/main/docs/agent-integrations.md)。

## Flutter 快速路径

从目标 checkout 内执行。Cockpit 会管理发现、Supervisor、workspace/target 注册、
应用进程、端口和 bridge 状态：

```bash
cockpit dev start cockpit/main.dart --platform macos
cockpit dev status
cockpit dev inspect "Save"
cockpit dev tree
cockpit dev tap "Save"
cockpit dev wait
cockpit dev screenshot
cockpit dev reload
cockpit dev diagnose --verbosity standard
```

入口和平台可推断时直接省略。Cockpit 会按 canonical Flutter project 保存一个 active
数字 handle，并用 checkout identity 保证隔离；同一项目可以保留不同平台或 target 的
多个 handle。需要确认或切换时使用 `cockpit session list`、`cockpit session show
HANDLE` 和 `cockpit dev use HANDLE`。显式 `--session` 只选择当前命令，不会改变已保存
的 active handle。`dev` 自动使用仅限本地进程的 yolo Supervisor。Cockpit 不读取
keychain 或 secret store，`--env` 只传给当前进程。

Flutter 检查会直接遍历已挂载的 Element 与 RenderObject，不要求开发者编写
`Semantics`。有界搜索使用 `dev inspect QUERY`；只有确实需要结构上下文时才使用
`dev tree`、`dev tree --verbosity standard` 或 `dev tree --verbosity full`。
完整树始终写入 artifact，stdout 只返回经过验证的路径。action 支持 `--path`；
应优先使用 ID、精确文本、key 和类型，仍有歧义时再复制检查结果中的 `loc`。

## 多项目交互

交互式 API 命令会按需启动当前用户的 Supervisor。每个项目根目录和 checkout 都要
显式注册：

```bash
cockpit daemon start
cockpit root add --path /work/projects --label projects
cockpit workspace register --root-id <rootId> --path /work/projects/app-a
cockpit workspace register --root-id <rootId> --path /work/projects/app-b
cockpit workspace list
```

## CLI 输出

默认输出是 minimal canonical LON，正常命令不写输出参数。
`--verbosity standard|full` 只增加上下文，不改变操作准确性；
`--format json|yaml|jsonl|path|none` 用于改变编码或输出方式。需要完整对象时使用
`--verbosity full --output <file>.lon`；仅在配合 `jq`、JSON-only 消费者或检查 JSON
线协议时才请求 JSON。`--output` 只返回已验证路径；
`artifact read` 强制写文件，二进制、Base64、hash 和对决策无意义的字节数都不会
进入终端输出。

workspace 命令可以显式传 `--workspace-id`。省略时，Cockpit 会用当前目录匹配已注册且
active 的 workspace，并要求结果唯一；不会回退到全局 latest run、active session 或
其他 checkout。

```bash
cd /work/projects/app-a
cockpit op list
cockpit case list
```

`op run` 只接收类型化 LON、JSON 或 YAML，并且只能执行 Supervisor 已公开的
operation。
descriptor 决定 scope、idempotency 和默认 timeout，不提供任意 URL 或 HTTP method
传输；只有需要在公开最大值内覆盖预算时才传 `--timeout`。

```bash
cockpit op run analyze.workspace \
  --workspace-id <workspaceId>
```

## 授权策略

危险 operation、operation safety effect、测试 safety effect 和 production target
都需要显式授权。严格策略文件位于
`COCKPIT_HOME/authorization.json`，daemon 启动时只加载一次。

```bash
cockpit daemon policy validate --file authorization.json
cockpit daemon policy apply --file authorization.json --restart
cockpit daemon policy show
```

本地需要显式全权 daemon 时，使用 `cockpit daemon start --yolo`（或
`daemon restart --yolo`）。该模式只对本次 daemon 进程生效。daemon 已健康运行时，
不带开关的 start/restart 会保留当前授权；daemon 未运行时则使用持久化受限策略
启动。需要明确回到 restricted 时，先停止 daemon 再无开关启动。daemon 状态、
attempt 和 suite 报告都会记录实际 `auth`。

不带 `--restart` 时只能在 daemon 停止状态下应用。默认策略拒绝危险操作、敏感测试
effect，以及 production/unknown target。

quarantined lease 默认持续阻塞资源。先通过公开的 `lease.list` 获取精确身份，再使用
已授权 `reset` effect 的 `lease.recover` 重试 cleanup。`forceRelease: true` 仅允许
解除身份完全匹配的逻辑资源隔离；forwarded port 必须通过真实 cleanup 验证。

## 规范用例回放

先校验文档，再用文档摘要标识的 indexed case 提交执行。回放必须显式提供 workspace、
document、case 和 idempotency identity。

```bash
cockpit case validate \
  --workspace-id <workspaceId> \
  --file example/cases/flutter_login.yaml

cockpit case run \
  --workspace-id <workspaceId> \
  --document-id <documentId> \
  --case-id flutter-login \
  --idempotency-key ci-login-001

cockpit run get --run-id <runId>
cockpit run events --run-id <runId> --after-sequence 0
```

run events 使用认证 SSE，支持 `afterSequence` 与 `Last-Event-ID` 恢复，并显式返回
gap、terminal 和 disconnect。artifact 读取使用 `--output` 指定文件；Cockpit 根据
服务端资源校验媒体类型、大小与 SHA-256，不一致时不会落盘。

## Suite 与黑盒 Target

suite 复用已索引 case，并提供依赖 DAG、作用域 fixture、matrix、并发、重试、
fail-fast、恢复，以及 JSON/JUnit/HTML/Markdown 聚合报告。

恢复会持久化 node/attempt 检查点和精确 fixture/row session 绑定。worker 退出时
正在运行的 attempt 会变为 `interrupted`，只有 suite retry 策略允许时才继续；绑定
session 丢失会明确返回环境失败，不会静默替换。

默认的 `restartApp` 隔离会在每个 case 的 attempt fixture 之前执行。只有驱动明确
支持时才使用 `resetAppData`；仅当 suite 设计本身需要共享状态时才显式选择
`sharedSession`。

同一个 locator 中的字段按交集匹配，`fallbacks` 是按顺序尝试的备选定位。原生黑盒
target 在 accessibility 能力明确支持时还可以使用状态、层级和空间关系约束。运行时
无法忠实执行某项约束时会明确拒绝，不会静默丢弃条件。
`text` 和 `label` 默认使用 `matchMode: exact`；需要扩展匹配时必须显式选择
`contains`、容忍拼写误差的 `fuzzy` 或 `regex`。多个候选会按当前 route 和匹配质量选择唯一最优项；最高分
并列时返回 `ambiguousTarget`，可增加条件、关系约束或使用 0-based `index` 选择列表项。

```bash
cockpit suite validate --file example/suites/regression.yaml
cockpit suite run \
  --workspace-id <workspaceId> \
  --document-id <documentId> \
  --suite-id regression \
  --idempotency-key ci-regression-001
cockpit suite report --run-id <runId> \
  --output-dir cockpit-report
```

已安装原生应用和其他 system-controlled surface 通过 workspace target 注册；稳定的
平台 app/package id 直接放在 target 上，必要时 case 的 target requirements 可以覆盖。
Android 使用 ADB accessibility 与设备控制，iOS 使用 WebDriverAgent 完成
accessibility 和交互。多设备或多 workspace 并发时，应为每个 target 分配独立 WDA
endpoint。

已安装 Flutter 应用或原生/Flutter 混合栈使用 `targetKind: flutterApp`、真实
`appId`、不绑定 entrypoint，并让 case 运行在 `native` plane。Cockpit 通过 system
accessibility 启动和操作它，同时启用 Flutter-aware 重复 semantics 归一化；原生页面和
内嵌 platform view 仍在同一棵树中。绑定 entrypoint 的 target 只用于开发态可选 bridge，
通过 semantic plane 提供 Widget、route 和 runtime 检查。

```bash
cockpit target register \
  --workspace-id <workspaceId> \
  --platform android \
  --device-id emulator-5554 \
  --target-kind nativeApp \
  --app-id com.example.app \
  --environment test \
  --mode automation \
  --idempotency-key android-target-001

cockpit target register \
  --workspace-id <workspaceId> \
  --platform ios \
  --device-id <deviceUdid> \
  --target-kind nativeApp \
  --app-id com.example.app \
  --wda-url http://127.0.0.1:8101 \
  --environment test \
  --mode automation \
  --idempotency-key ios-target-001
```

使用 `target list` 和 `target get` 恢复已注册资源，使用 `target launch` 激活 target，
使用 `target inspect` 读取实时能力。
已启动的 Flutter 或混合栈 target 以 `target.inspect` operation 结果中的
`output.systemControl` 脱敏 profile 作为次级 native driver 的能力权威。不要从
`app.get` 重建该 profile，其中的平台应用标识与进程标识会按设计隐藏。

Flutter target 启动支持重复的 `--dart-define`、`--dart-define-from-file`、
`--flutter-arg`、`--env KEY=VALUE`，以及默认 20 分钟、最长 31 分钟的
`--timeout`。MCP 和通用 operation 使用相同的嵌套
`launchConfiguration` 字段：`dartDefines`、`dartDefineFromFiles`、
`flutterArgs`、`environment`。Cockpit 管理的启动参数不能被覆盖，配置值也不会在
结果中返回。
Android 和 iOS 上的 `environment` 只配置 Flutter 构建进程，移动应用进程不会继承
任意宿主机环境变量；应用自身需要读取的值应使用 Dart define 或应用自己的配置通道。

operation descriptor 会公开 `executionMode`、`defaultTimeoutMs` 和
`maximumTimeoutMs`。同步操作阻塞到结果，并用一个 `--timeout` 时长覆盖默认预算。
case/suite 提交是返回 `runId` 的持久化异步 job；`--timeout` 控制整体运行预算
（case 默认 30 分钟、最长 6 小时，suite 默认
2 小时、最长 24 小时）。

case 的 `setup`、主步骤、`finally` 及 suite fixture 都可以使用 `type: system` 与
capability 已公开的 action/parameters，使安装、激活、权限、设备状态和清理共用同一套
安全策略、超时、事件与报告链路。

步骤级 `plane` 可以把 case 默认值覆盖为 `semantic`、`native`、`visual` 或
`coordinate`；未指定时 runtime 根据 action 和 locator 自动选择。Flutter bridge
session 会为同一 target 保留 system driver，使语义 Widget 步骤与 native、visual、
coordinate 步骤可以出现在同一个 case。condition 以及 fragment/if/retry/loop 内的步骤
继承有效 plane，除非自己显式覆盖。

文本控制包含 `copyText`、`eraseText`、`pasteText`；`travel` 按有界的经纬度点序列
执行，并支持 route 或单点延迟。visual locator 指向 workspace 内模板文件；
`assertScreenshot` 指向 workspace 内 baseline，并将 actual、baseline、确定性 diff
文件写入 attempt evidence。baseline 必须按平台、设备或 viewport、像素比和方向等稳定
profile 选择；尺寸不一致代表 profile 错误或布局回归，不会自动缩放。pre/post 取证应由
suite fixture、case `setup`/`finally`、step `evidence` 和显式录屏操作在实际拥有该
生命周期的作用域组合表达。

## Foreground CI

CI 与交互模式共用同一 HTTP API 和 worker boundary。foreground 模式管理 daemon
生命周期，注册传入 checkout，提交 `CockpitRunSubmission` JSON，等待 terminal run
truth，并按 outcome 返回进程状态。

```bash
cockpitd \
  --home=/tmp/cockpit-ci \
  --foreground-workspace=/workspace/app \
  --foreground-submission=/workspace/run-submission.json
```

submission 包含规范 case source、idempotency key、inputs 和 required features；
foreground 模式负责填入注册后的 `workspaceId`。

仓库发布门禁并行运行格式、分析、全部 package/示例测试、发布 dry-run，以及 Android、
iOS、macOS、Linux、Web、Windows 真实回归。Android 与 iOS 必须证明原生
locator/action/assertion 控制，截图回退不能通过核心平台门禁。只有所有 job 都到达成功终态
才允许发布。每个平台回归都通过可见断言验证真实业务变更、完整 Flutter 手势/文本/键盘/
语义命令面、suite 控制流、证据和离线报告 bundle。应等待完整矩阵结束后，再依据 report、
event、artifact 和 daemon log 统一定位失败，不在执行中反复猜测。

## API Discovery

`CockpitDaemonLifecycleClient.ensure()` 初始化 Cockpit home、校验进程 identity，并返回
当前 discovery。生产客户端随后：

1. 只向 discovery 中的 loopback endpoint 发送 bearer token；
2. 读取 `GET /api/v2/server`；
3. 协商 API major/minor 和 required features；
4. 严格解码公开 foundation DTO；
5. 只调用 advertised `/api/v2` resource 与 operation。

完整的通用客户端控制面为：

```text
GET  /api/v2/operations
GET  /api/v2/workspaces/{workspaceId}/operations
GET  /api/v2/operations/schema
POST /api/v2/operations
POST /api/v2/workspaces/{workspaceId}/operations
GET  /api/v2/runs/{runId}/events
```

REST 负责命令和资源，认证 SSE 负责可恢复的持久 run event。WebSocket 仅保留给
Flutter Web 内部 bridge，不是公开客户端命令传输。operation invocation envelope
负责 scope、idempotency 和 deadline，`input` 只包含对应 live request schema 声明的
字段。

CLI 和 MCP 共用 `CockpitSupervisorApiClient`，统一处理 1 MiB 响应上限、bounded
pagination、SSE resume、结构化 API error 和 artifact 完整性校验。

## MCP

使用 CLI 命令或独立 executable：

```bash
cockpit serve-mcp
cockpit_mcp
cockpit serve-mcp --profile dart
```

```json
{
  "mcpServers": {
    "cockpit": {
      "command": "cockpit_mcp",
      "args": []
    }
  }
}
```

MCP 提供 server、capabilities、roots、workspaces、operations、targets、documents、
cases、suites、runs 和 artifacts 的 bounded resources；tools 覆盖 target 生命周期、
case/suite 验证执行、run get/cancel/events、artifact list 和校验式 artifact 文件下载。所有调用都经过认证
Supervisor HTTP boundary，MCP 进程不直接构造 application services。

profile 用于控制注入的工具域：默认是 `core`，可选 `dart`、`flutter`、`app`、
`e2e` 和 `all`；`flutter` 包含 `dart`，`e2e` 包含 `app`。可重复使用 `--enable`、
`--disable` 精确覆盖 feature 或 category。Dart profile 提供 analyze、format、fix、
test、LSP、pub、package URI/search 和项目创建能力，不嵌入也不转发官方 Dart MCP
server。

## 客户端边界

公开 `/api/v2` resources、SSE stream、foundation DTO 和 artifact 完整性契约是唯一的
客户端边界。未来 Flutter GUI 或第三方 SDK 必须使用该协议，不能在进程内链接
Supervisor application services。

导出的 `cockpit-report/` 是完整离线 run artifact，而不是 server UI。
`suite report --output-dir cockpit-report` 会下载 manifest 及其声明的全部报告文件，
逐项校验大小和 SHA-256，并在 bundle 完整后才提交目录；目标目录不能预先存在。
`index.html`
内嵌 CSS、JavaScript 和规范报告数据，媒体使用 bundle 相对路径；`report.json` 是稳定的
单文件渲染输入，根 `manifest.json` 以归属、大小、媒体类型和 SHA-256 覆盖全部导出文件。
客户端必须保持目录结构并校验 manifest，`cockpitd` 无需提供 HTML route。Summary、
Coverage、Executions、Evidence、Diagnostics 和 Environment/files 是同一事实图的
任务视图，不是按人员角色复制出的报告。

协议资料见 [`../../docs/contracts`](../../docs/contracts)，规范 LON/JSON/YAML 用例见
[`example/cases`](example/cases)。
