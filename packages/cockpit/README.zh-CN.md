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

不带 `--restart` 时只能在 daemon 停止状态下应用。默认策略拒绝危险操作、敏感测试
effect，以及 production/unknown target。

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
gap、terminal 和 disconnect。artifact 读取必须给出预期大小与 SHA-256；响应元数据或
实际字节不一致时直接拒绝。

## Suite 与黑盒 Target

suite 复用已索引 case，并提供依赖 DAG、作用域 fixture、matrix、并发、重试、
fail-fast、恢复，以及 JSON/JUnit/HTML/AI summary 聚合报告。

恢复会持久化 node/attempt 检查点和精确 fixture/row session 绑定。worker 退出时
正在运行的 attempt 会变为 `interrupted`，只有 suite retry 策略允许时才继续；绑定
session 丢失会明确返回环境失败，不会静默替换。

默认的 `restartApp` 隔离会在每个 case 的 attempt fixture 之前执行。只有驱动明确
支持时才使用 `resetAppData`；仅当 suite 设计本身需要共享状态时才显式选择
`sharedSession`。

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

case 的 `setup`、主步骤、`finally` 及 suite fixture 都可以使用 `type: system` 与
capability 已公开的 action/parameters，使安装、激活、权限、设备状态和清理共用同一套
安全策略、超时、事件与报告链路。

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
case/suite 验证执行、run get/cancel/events、artifact list 和校验式 artifact read。所有调用都经过认证
Supervisor HTTP boundary，MCP 进程不直接构造 application services。

## 客户端边界

公开 `/api/v2` resources、SSE stream、foundation DTO 和 artifact 完整性契约是唯一的
客户端边界。未来 Flutter GUI 或第三方 SDK 必须使用该协议，不能在进程内链接
Supervisor application services。

生成的 `report.html` 继续作为可携带 run artifact 保留；它不是 server UI，也不需要
`cockpitd` 提供 HTML route。

协议资料见 [`../../docs/contracts`](../../docs/contracts)，规范 YAML/JSON 用例见
[`example/cases`](example/cases)。
