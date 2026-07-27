# cockpit

[![pub package](https://img.shields.io/pub/v/cockpit?logo=dart&label=pub.dev)](https://pub.dev/packages/cockpit)
[![License](https://img.shields.io/github/license/cockpit-dev/cockpit)](https://github.com/cockpit-dev/cockpit/blob/main/packages/cockpit/LICENSE)

[English](https://github.com/cockpit-dev/cockpit/blob/main/packages/cockpit/README.md)

`cockpit` 是 Cockpit 2.0 的认证宿主客户端和无头执行包，包含 Supervisor daemon、
隔离 workspace worker、resource-oriented CLI 和轻量 MCP server，不内置 GUI 或 Web
dashboard。

## 安装

需要 Dart 3.8.0 或更高版本；Flutter workspace 使用 Flutter 3.32.0 或更高版本
内置的 Dart SDK。

```yaml
dev_dependencies:
  cockpit: ^2.0.0
```

包发布四个 executable：

- `cockpit`：交互式资源命令
- `cockpit_mcp`：MCP stdio server
- `cockpitd`：Supervisor daemon 与 foreground CI runner
- `cockpit_worker`：私有 workspace worker 进程

## 多项目交互

交互式 API 命令会按需启动当前用户的 Supervisor。每个项目根目录和 checkout 都要
显式注册：

```bash
dart run cockpit daemon start
dart run cockpit root add --path /work/projects --label projects
dart run cockpit workspace register --root-id <rootId> --path /work/projects/app-a
dart run cockpit workspace register --root-id <rootId> --path /work/projects/app-b
dart run cockpit workspace list
```

## CLI 输出

默认 `auto` 格式是适合 Agent 循环的紧凑语义文本。可用
`--detail minimal|standard|full` 控制投影，用显式 `--stdout-format json`
取得无损数据，或让 `run events` 使用流式 `jsonl`。`--output <file>` 原子写入
完整 JSON，终端只返回路径、大小和 SHA-256；`artifact read` 强制写文件，绝不输出
二进制或 Base64。

workspace 命令可以显式传 `--workspace-id`。省略时，Cockpit 会用当前目录匹配已注册且
active 的 workspace，并要求结果唯一；不会回退到全局 latest run、active session 或
其他 checkout。

```bash
cd /work/projects/app-a
dart run cockpit operation list
dart run cockpit case list
```

`operation run` 只接收类型化 JSON，并且只能执行 Supervisor 已公开的 operation。
descriptor 决定 scope 与 idempotency，不提供任意 URL 或 HTTP method 传输。

```bash
dart run cockpit operation run \
  --kind analyze.workspace \
  --workspace-id <workspaceId> \
  --input-json '{}'
```

## 授权策略

危险 operation、operation safety effect、测试 safety effect、production target
和 worker 环境 secret 都需要显式授权。严格策略文件位于
`COCKPIT_HOME/authorization.json`，daemon 启动时只加载一次。

```bash
dart run cockpit daemon policy validate --file authorization.json
dart run cockpit daemon policy apply --file authorization.json --restart
dart run cockpit daemon policy show
```

本地需要显式全权 daemon 时，使用 `dart run cockpit daemon start --yolo`（或
`daemon restart --yolo`）。该模式只对本次 daemon 进程生效；不带开关启动会回到
持久化受限策略。daemon 状态、attempt 和 suite 报告都会记录实际
`authorizationMode`。

不带 `--restart` 时只能在 daemon 停止状态下应用。默认策略拒绝危险操作、敏感测试
effect，以及 production/unknown target。

quarantined lease 默认持续阻塞资源。先通过公开的 `lease.list` 获取精确身份，再使用
已授权 `reset` effect 的 `lease.recover` 重试 cleanup。`forceRelease: true` 仅允许
解除身份完全匹配的逻辑资源隔离；forwarded port 必须通过真实 cleanup 验证。

## 规范用例回放

先校验文档，再用文档摘要标识的 indexed case 提交执行。回放必须显式提供 workspace、
document、case 和 idempotency identity。

```bash
dart run cockpit case validate \
  --workspace-id <workspaceId> \
  --file example/cases/flutter_login.yaml

dart run cockpit case run \
  --workspace-id <workspaceId> \
  --document-id <documentId> \
  --case-id flutter-login \
  --idempotency-key ci-login-001 \
  --inputs-json '{}'

dart run cockpit run get --run-id <runId>
dart run cockpit run events --run-id <runId> --after-sequence 0
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
dart run cockpit suite validate --file example/suites/regression.yaml
dart run cockpit suite run \
  --workspace-id <workspaceId> \
  --document-id <documentId> \
  --suite-id regression \
  --idempotency-key ci-regression-001
dart run cockpit suite report --run-id <runId>
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
dart run cockpit target register \
  --workspace-id <workspaceId> \
  --platform android \
  --device-id emulator-5554 \
  --target-kind nativeApp \
  --app-id com.example.app \
  --environment test \
  --mode automation \
  --idempotency-key android-target-001

dart run cockpit target register \
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
`--flutter-arg`、`--env KEY=VALUE`，以及最长 1800000 毫秒的
`--launch-timeout-ms`。MCP 和通用 operation 使用相同的嵌套
`launchConfiguration` 字段：`dartDefines`、`dartDefineFromFiles`、
`flutterArgs`、`environment`。Cockpit 管理的启动参数不能被覆盖，配置值也不会在
结果中返回。

operation descriptor 会公开 `executionMode`、`defaultTimeoutMs` 和
`maximumTimeoutMs`。同步操作阻塞到结果，并接受相对 `--timeout-ms` 或绝对
`--deadline`。case/suite 提交是返回 `runId` 的持久化异步 job；可选
`--timeout-ms` 控制整体运行预算（case 默认 30 分钟、最长 6 小时，suite 默认
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
文件写入 attempt evidence。pre/post 取证应由 suite fixture、case `setup`/`finally`、
step `evidence` 和显式录屏操作在实际拥有该生命周期的作用域组合表达。

## Foreground CI

CI 与交互模式共用同一 HTTP API 和 worker boundary。foreground 模式管理 daemon
生命周期，注册传入 checkout，提交 `CockpitRunSubmission` JSON，等待 terminal run
truth，并按 outcome 返回进程状态。

```bash
dart run cockpitd \
  --home=/tmp/cockpit-ci \
  --foreground-workspace=/workspace/app \
  --foreground-submission=/workspace/run-submission.json
```

submission 包含规范 case source、idempotency key、inputs 和 required features；
foreground 模式负责填入注册后的 `workspaceId`。

仓库发布门禁会先运行格式、分析、全部 package/示例测试和发布 dry-run，再启动
Android、iOS、macOS、Linux、Web、Windows 真实回归。只有所有 job 都到达成功终态
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

CLI 和 MCP 共用 `CockpitSupervisorApiClient`，统一处理 1 MiB 响应上限、bounded
pagination、SSE resume、结构化 API error 和 artifact 完整性校验。

## MCP

使用 CLI 命令或独立 executable：

```bash
dart run cockpit serve-mcp
dart run cockpit_mcp
dart run cockpit serve-mcp --profile dart
```

```json
{
  "mcpServers": {
    "cockpit": {
      "command": "dart",
      "args": ["run", "cockpit_mcp"]
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

生成的 `cockpit-report/` 是完整离线 run artifact，而不是 server UI。`index.html`
内嵌 CSS、JavaScript 和规范报告数据，媒体使用 bundle 相对路径；`report.json` 是稳定的
单文件渲染输入，根 `manifest.json` 以归属、大小、媒体类型和 SHA-256 覆盖全部导出文件。
客户端必须保持目录结构并校验 manifest，`cockpitd` 无需提供 HTML route。

协议资料见 [`../../docs/contracts`](../../docs/contracts)，规范 YAML/JSON 用例见
[`example/cases`](example/cases)。
