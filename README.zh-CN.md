<p align="center">
  <img src="assets/brand/cockpit-mark.svg" width="128" alt="Cockpit logo">
</p>

# Cockpit 2.0

[English](README.md)

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
  JSON/JUnit/HTML/AI 报告；
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
  cockpit: ^2.0.0
  flutter_cockpit: ^2.0.0 # 仅 Flutter 语义桥需要
```

Cockpit 应保持为开发依赖。黑盒原生应用测试不要求修改被测应用源码，也不要求
接入 Flutter 包。

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

每个已公开 operation 都包含 `executionMode`、`defaultTimeoutMs` 和
`maximumTimeoutMs`。同步操作会阻塞到结果，可通过
`operation run --timeout-ms <值>` 或绝对 `--deadline` 覆盖预算，两者不能同时传入。
case/suite 是持久化异步 job：提交后立即返回 `runId`，客户端再消费事件并读取终态报告。
`case run --timeout-ms` 默认 30 分钟、最长 6 小时；`suite run --timeout-ms` 默认
2 小时、最长 24 小时。步骤和清理超时仍是互相独立的内部预算。

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
dart run cockpit suite report --run-id <runId>
```

worker 意外退出后，已完成节点不会重跑，执行中的 attempt 会变为 `interrupted`，
只有 suite retry 策略允许时才继续。持久化的 fixture/row session 必须恢复为同一
健康资源；无法证明时会明确失败，不会假装 fixture 状态仍有效。

## MCP、客户端与 CI

```bash
dart run cockpit serve-mcp
# 或
dart run cockpit_mcp
```

MCP 只是认证 Supervisor 客户端，不会在进程内构造 driver 或应用服务。它提供有界的
roots、workspaces、operations、targets、documents、cases、suites、runs 和 artifacts
资源。官方或第三方 GUI 应使用 `/api/v2`、认证 SSE、公开 DTO 和带 digest 校验的
artifact 下载。2.0 暂不提供 Flutter GUI，也不内置 HTML dashboard；HTML 只作为
可移植回归报告 artifact 生成。

包括 OpenCode/OMP skill 在内的各类 Agent 宿主接入方式见
[Agent 接入指南](docs/agent-integrations.md)。

CI 可以让前台 daemon 独占生命周期：

```bash
dart run cockpitd \
  --home=/tmp/cockpit-ci \
  --foreground-workspace=/workspace/app \
  --foreground-submission=/workspace/run-submission.json
```

## 发布门禁

`.github/workflows/example-e2e.yml` 是 Cockpit 2.0 发布前的强制门禁。
quality job 会统一验证格式、静态分析、仓库契约、所有 package 与示例测试，并对三个
公开包执行发布 dry-run；通过后才会运行 Android、iOS、macOS、Linux、Web 和
Windows 真实回归。只有 quality 与全部平台 job 都成功终止，并产出可校验的终态报告
和 artifact，版本才允许发布。排查失败时先等待整个矩阵结束，再统一以上传的 report、
event stream、artifact 和 daemon log 为准，避免边运行边反复猜测。

## 文档

详细文档：

- [`packages/cockpit/README.md`](packages/cockpit/README.md)
- [`packages/flutter_cockpit/README.md`](packages/flutter_cockpit/README.md)
- [`packages/cockpit_protocol/README.md`](packages/cockpit_protocol/README.md)
- [`docs/agent-integrations.md`](docs/agent-integrations.md)
- [`docs/architecture/cockpit-2.0-foundation-migration-inventory.md`](docs/architecture/cockpit-2.0-foundation-migration-inventory.md)
