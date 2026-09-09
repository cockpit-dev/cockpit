# flutter_cockpit 项目改进清单（impr.md）

> 生成于 2026-09-09，基线 commit `1784cd45`（main）；本轮实现提交为 `656a12f`。全部发现均已人工核对源码验证，`dart analyze` 当前无告警。已完成项在下文以 `[x]` 标记；未标记项仍是待处理审计建议，不将其误报为已修复。
>
> **给后续代理的使用说明：**
> - 路径均相对仓库根目录 `/Users/iota9star/Development/workspace/flutter/flutter_cockpit`。行号基于上述 commit，若已漂移请按「位置」中的函数/类名与代码摘录全文检索定位。
> - 每项包含：位置、现状代码（摘录自当前源码）、问题、修复建议、验证方式。修复时请先阅读完整上下文，遵循 AGENTS.md 规范（生产级实现、无 TODO、完成后跑 `dart fix --apply` / `dart format` / `dart analyze`）。
> - 严重级别：🔴 高（正确性/可用性缺陷，建议优先）、🟡 中（边界场景缺陷、资源泄漏、明显性能问题）、🔵 低（死代码、一致性、轻微性能）。
> - 修改完成后逐项在本文中将该项标记为 `[x]` 并附 commit 号。

## 总览索引

| 分区 | 范围 | 条目 |
| --- | --- | --- |
| A | cockpit — Supervisor/会话/开发会话运行时 | A-1 🔴 A-2 🔴 A-3 🟡 A-4 🔴 A-5 🔴 A-6 🟡 A-7 🟡 A-8 🟡 A-9 🟡 A-10 🟡 A-11 🟡 A-12 🔵 A-13 🔵 A-14 🟡 A-15 🟡 A-16 🟡 A-17 🟡 A-18 🟡 A-19 🟡 A-20 🟡 |
| B | cockpit — CLI/用例执行/录制 | B-1 🔴 B-2 🔴 B-3 🔵 B-4 🟡 B-5 🔵 B-6 🟡 B-7 🟡 |
| C | cockpit — 基础设施/进程/网络 | C-1 🔴 C-2 🟡 C-3 🟡 C-4 🟡 C-5 🔵 C-6 🟡 C-7 🟡 |
| D | flutter_cockpit — 应用内桥接 | D-1 🔴 D-2 🔴 D-3 🟡 D-4 🟡 D-5 🟡 D-6 🟡 D-7 🔵 D-8 🔵 D-9 🔵 D-10 🟡 D-11 🔵 D-12 🟡 D-13 🟡 D-14 🟡 D-15 🟡 D-16 🟡 D-17 🟡 D-18 🟡 D-19 🟡 D-20 🔵 D-21 🔵 D-22 🟡 D-23 🔵 |
| E | cockpit_protocol / flutter_cockpit_test | E-1 🟡 E-2 🟡 E-3 🟡 E-4 🟡 E-5 🟡 E-6 🔵 E-7 🔵 E-8 🔵 E-9 🔵 E-10 🟡 E-11 🟡 E-12 🟡 E-13 🔵 E-14 🔵 E-15 🔵 E-16 🟡 |
| F | console / demo / 文档 / CI / 工程配置 | F-1 🟡 F-2 🟡 F-3 🔵 F-4 🔵 F-5 🔵 F-6 🟡 F-7 🟡 F-8 🟡 F-9 🟡 F-10 🟡 F-11 🔵 F-12 🔵 F-13 🔵 F-14 🔵 F-15 🔵 F-16 🔵 F-17 🔵 F-18 🔵 F-19 🟡 F-20 🔵 |
| S | 安全与加固（跨包） | S-1 🔴 S-2 🔴 S-3 🟡 S-4 🟡 S-5 🟡 |
| G | 功能建议 | G-1 🟡 G-2 🔵 G-3 🔵 G-4 🔵 G-5 🔵 |
| H | 测试补缺 | H-1 🟡 H-2 🟡 H-3 🟡 H-4 🟡 H-5 🟡 H-6 🔵 H-7 🟡 H-8 🟡 |

共 111 项：11 🔴（正确性/安全缺陷）、64 🟡（边界缺陷/资源泄漏/性能/flaky 测试）、36 🔵（一致性/死代码/文档/功能增强）。`dart analyze` 干净、全量测试套件通过（root 69 + flutter_cockpit 555 + flutter_cockpit_test 53 + cockpit 1593 + protocol 69 + console 124 + demo 全绿），无 TODO/FIXME 残留——即所有条目都是现有测试未覆盖或守卫盲区中的潜伏问题。

> 审查轮次：① 按模块地毯式（A–F 分区 + G/H）；② 并发/安全/协议数据/生命周期四视角（A-15/16、B-6、C-7、D-13～D-23、E-10～E-16、S 分区、H-4）；③ 文档契约/状态机/测试质量/二次深扫（A-17～A-20、B-7、S-5、F-6～F-15、H-5～H-8）；④ 未覆盖角落（工具脚本/镜像资产/docs/配置，F-16～F-20）。每条均经人工核对源码后收录。

---

## A. packages/cockpit — Supervisor 与会话运行时

### [x] A-1 🔴 端口移交失败后，等待中的 `release()`/`relinquish()` 重抛旧错误，释放逻辑永不执行（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/supervisor/cockpit_port_handoff.dart:226-232`（`CockpitPortReservation.release()` 开头的等待循环）；同样模式见 `relinquish()`（240-243 行）以及 `handoff()` 开头的同型循环。
- **现状代码**：
  ```dart
  Future<CockpitLeaseResource> release() async {
    while (_transition != null) {
      await _transition;
    }
    if (_state == CockpitPortReservationState.released) return _lease;
  ```
- **问题**：`_transition` 是当前进行中的移交/释放操作。若先前的 `handoff()` 失败（`_performHandoff` 在隔离后总是抛 `CockpitLeaseException`），并发等待该 future 的 `release()` 会在 `await _transition` 处直接重抛那个陈旧的 `portHandoffFailed` 错误，释放逻辑不会执行——回环 socket 保持占用，租约只能等 TTL 过期回收。调用方（如超时路径与 dispose 竞争同一 reservation 时）正是这种并发场景。
- **修复建议**：等待前一个转换时吞掉其错误再继续自己的转换，例如 `await _transition.catchError((_) {});`（或 `try { await _transition; } catch (_) {}`），保证 `release()`/`relinquish()` 无论如何都能进入自己的状态迁移。`handoff()`/`relinquish()` 开头的等待循环同理。
- **验证**：新增单测：先让 `handoff()` 失败（如模拟 owner 不匹配），再调用 `release()`，断言不抛旧错误且 lease 进入 released/quarantined、socket 已关闭。现有 `cockpit_port_handoff` 相关测试文件中补充该用例。

### [x] A-2 🔴 `_dispatchRun` 末段无 catch：终态写入失败时未处理异步错误逃逸守护进程（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/supervisor/cockpit_supervisor_runtime.dart:949-960`（`_dispatchRun` 尾部 `try { await _ensureTerminalRunTruth(...) } finally { ... }`）；发起点在 889-897 行 `unawaited(_dispatchRun(active, submission))`。
- **现状代码**：
  ```dart
  try {
    await _ensureTerminalRunTruth(
      run,
      operation: operation,
      dispatchError: dispatchError,
    );
  } finally {
    run.terminal = true;
    ...
  }
  ```
- **问题**：worker 调用错误已被捕获进 `dispatchError`，但 `_ensureTerminalRunTruth` 内部做 `projection.readEvents` + `projection.publish`，在存储错误、projection 损坏、或其计算的 `sequence` 因 worker 事件恰好在读取与发布之间落盘而失效（`cockpit_supervisor_run_projection.dart:227-235` 的 `'Published event conflicts with its durable sequence index.'`）时会抛异常。此处只有 `finally` 没有 `catch`，异常经 `unawaited` 逃逸为守护进程内的未处理异步错误。更糟的是 `finally` 无条件执行 `run.terminal = true` 并把 run 从 `_activeRuns` 移除——事件存储里却没有终态事件，形成两个矛盾真相：API projection 永远显示 `queued/running`（再无任何东西会调度或终态冻结它），而 `cancelRun`（`cockpit_supervisor_runtime.dart:1154-1162`）看到 `active == null` 静默返回 `replayed: true`，取消根本没送达。
- **修复建议**：将 `_ensureTerminalRunTruth` 包在自己的 try/catch 中，失败时记录守护进程日志并**重试或保留 run 活跃**（而不是无条件在 finally 标记 terminal），确保内存状态与持久化真相一致；彻底失败时给 run 写入降级 terminal 状态（如 `infrastructureFailure`）。
- **验证**：单测注入一个 publish 抛错的 projection，断言 `_dispatchRun` 不产生未处理异常、`_activeRuns` 中该 run 已移除、日志含错误记录。

### [x] A-3 🟡 worker 池心跳失败路径可从 `Timer.periodic` 回调抛出未处理异常（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/supervisor/cockpit_worker_pool.dart:161-164`（定时器）与 480-487 行（`_heartbeat` 的 catch 分支）；`terminate` 抛错点在 `packages/cockpit/lib/src/supervisor/cockpit_local_worker_launcher.dart:344-348`（`_LocalWorkerConnection._terminate` 抛 `CockpitWorkerPoolException('workerTerminationFailed')`）。
- **现状代码**：
  ```dart
  } on Object {
    slot.heartbeatFailures += 1;
    if (slot.heartbeatFailures >= _heartbeatFailureThreshold) {
      await connection.terminate(force: true);
    }
  }
  ```
- **问题**：不健康的 worker 若同时拒绝退出（`_waitForExit` 超时），`terminate()` 自身抛错，沿 `_heartbeat` → `_heartbeatAll` 的 `Future.wait` → `unawaited(...)` 定时器回调逃逸，成为守护进程的未处理异步错误。
- **修复建议**：catch 分支内对 `terminate` 再包一层 try/catch，失败时记日志并保留 slot 状态（可再触发一次重启或标记 slot 不可用），保证任何路径都不从定时器回调抛错。
- **验证**：单测模拟 `terminate` 抛错 + 心跳连续失败达到阈值，断言无未处理异常抛出且 slot 走重启/标记逻辑。

### [x] A-4 🔴 `reload()` 调用 machine client 无超时：`flutter run --machine` 卡死时 HTTP 请求永久挂起（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/development/cockpit_development_session_supervisor.dart:296-303`（`reload` 内 switch）；被调方 `packages/cockpit/lib/src/development/cockpit_flutter_run_machine_client.dart:191-213`（`sendRequest` 返回 `completer.future`，该 completer 仅由响应或进程退出完成，无超时）。
- **现状代码**：
  ```dart
  switch (mode) {
    case CockpitDevelopmentReloadMode.hotReload:
      await machineClient.hotReload(appId: appId);
    case CockpitDevelopmentReloadMode.hotRestart:
      await machineClient.hotRestart(appId: appId);
  ```
- **问题**：`flutter run --machine` 进程活着但卡死（构建卡住等）时，`hotReload`/`hotRestart` 的 completer 永不完成，`POST /reload` 控制面请求永久挂起。对比同文件中 `stop()` 带 200ms 竞争、`detach()` 带 2s 超时，此路径完全无界；客户端超时后该处理任务还泄漏。
- **修复建议**：与 `stop()` 一致，给 machine 调用加有界超时（如 30-60s，可做成参数），超时后抛出带 `next` 指引的明确错误（建议用户 `dev restart` 或 `diagnose`）。
- **验证**：单测用一个永不完成的 fake machine client，断言 `reload()` 在超时后返回明确错误而非挂起。

### [x] A-5 🔴 run 准入存储有 1 万条硬上限且从不清理：长驻守护进程最终永久拒绝所有新 run（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/supervisor/cockpit_supervisor_run_admission_store.dart:178-180`。
- **现状代码**：
  ```dart
  if (state.byKey.length >= maximumAdmissions) {
    throw const FormatException('Supervisor run admission bound exceeded.');
  }
  ```
- **问题**：全目录检索确认 admission 从未被清理（不像 lease 有 `_pruneReleased`/`idempotencyRetention`）。累计 1 万次提交后，守护进程对每个新 run 都抛错，只能手工删状态文件恢复；长跑 CI/共享守护进程必然触达。
- **修复建议**：仿照 lease 的做法增加基于时间的清理：对已终态且超过保留期（如 7 天）的 admission 在写入路径上顺带修剪，或提供显式 prune；同时把 `maximumAdmissions` 语义从「历史总量」改为「活跃+保留期内数量」。
- **验证**：单测构造满量存储，写入新 admission 触发修剪后成功；断言过期终态记录被移除、未终态记录保留。

### [x] A-6 🟡 `_validatedRunOwners` 只增不减，守护进程生命周期内无限增长（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/supervisor/cockpit_supervisor_runtime.dart:120`（声明）；写入点 1647、1675 行；读取点 1540/1579/1616/1625/1637 行。
- **现状代码**：
  ```dart
  final Map<String, String> _validatedRunOwners = {};
  ```
- **问题**：每个验证过的 run 永久保留一个条目（对比 `_runOwnerValidations` 在 finally 中清理）。长驻守护进程处理大量 run 后稳定泄漏内存。
- **修复建议**：改为有界 LRU（如最多 1024 条），或在 run 从 projection 保留窗口中消失时移除对应条目。
- **验证**：单测注册超过上限数量的 run owner 校验，断言 map 大小不超过上限且最新条目可用。

### A-7 🟡 worker 崩溃时资源授权 `_grants` 与端口桥 `_expectedOwners`/`_handoffTokens` 永久残留

- **位置**：`packages/cockpit/lib/src/supervisor/cockpit_worker_resource_authority.dart:39,167,190,244,299-301`（`_grants` 仅在 `_releaseGrant` 中移除）；`packages/cockpit/lib/src/supervisor/cockpit_supervisor_worker_port_bridge.dart:42-45`（`_expectedOwners` 69 行写入、`_handoffTokens` 90 行写入，无任何移除路径）。
- **现状代码**：
  ```dart
  final Map<String, _AuthorityGrant> _grants = <String, _AuthorityGrant>{};
  // ...
  final Map<String, CockpitExpectedPortOwner> _expectedOwners = ...;
  final Map<String, String> _handoffTokens = <String, String>{};
  ```
- **问题**：worker 异常死亡时，租约 TTL 回收会清理租约与端口 socket，但内存中的 `_grants` 条目（持有 `CockpitPortReservation`）和桥接映射永久留存，随守护进程运行时间无界增长。
- **修复建议**：在租约回收/隔离路径上（lease recovery quarantine/release 时）联动清除对应 grantId 的 `_grants`、`_expectedOwners`、`_handoffTokens` 条目；或提供按 holderId/workspaceId 批量清除的钩子。
- **验证**：单测创建 grant → 杀死 worker → 触发租约回收，断言三个 map 中相关条目均已移除。

### [x] A-8 🟡 损坏的 `output-metadata.json` 直接中止 Android 启动，而不落到 APK 目录回退（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/session/cockpit_android_remote_session_launcher.dart:389`（`_readAndroidBuildMetadataCandidate` 内 `jsonDecode` 无容错）；调用循环在 324-339 行同样无逐候选 catch。
- **现状代码**：
  ```dart
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<Object?, Object?>) {
    return null;
  }
  ```
- **问题**：构建被中断后残留的截断 metadata 文件（常见场景）会抛 `FormatException`，直接冒泡中止 `_resolveAndroidBuildArtifact`，而后面本可成功解析的 `flutter-apk` 目录回退（341-366 行）永远走不到。
- **修复建议**：在 `_readAndroidBuildMetadataCandidate` 内将读取+解析包进 try/catch（`FileSystemException`/`FormatException` 均返回 null 跳过该候选）。
- **验证**：单测放一个截断的 `output-metadata.json` 与一个合法 APK 目录，断言仍能通过回退解析出 artifact。

### [x] A-9 🟡 `CockpitDaemonHost.stop()` 先到先得：后续 emergency 停机请求被静默降级为已运行的 drain（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/supervisor/cockpit_daemon_host.dart:132-138`。
- **现状代码**：
  ```dart
  Future<void> stop(CockpitDaemonShutdownMode mode) {
    final existing = _stopOperation;
    if (existing != null) return existing;
    final operation = _stop(mode);
    _stopOperation = operation;
    return operation;
  }
  ```
- **问题**：SIGTERM 先触发 `stop(drain)` 后，后续 `POST /_cockpit/lifecycle {"mode":"emergency"}` 只是拿回已在执行的 drain 操作（`workerPool.close` 宽限可达 10s），请求方以为紧急停机已生效，实际未升级。
- **修复建议**：记录已请求的 mode，当新请求的 mode 更强（emergency > drain）时升级停机（例如强制关闭 HTTP server / 跳过剩余宽限），并让升级请求 await 原操作收尾。
- **验证**：单测先 `stop(drain)` 再 `stop(emergency)`，断言实际执行了升级路径（如 server 被强制关闭）且两次 future 都完成。

### A-10 🟡 工件下载对整个传输+校验共用一个 30s 请求预算，大工件必然失败

- **位置**：`packages/cockpit/lib/src/supervisor/cockpit_supervisor_api_client.dart:683`（deadline 基于 `_requestTimeout`），流式下载循环 732-735 行与下载后 sha256 校验 752-760 行复用同一 deadline。
- **现状代码**：
  ```dart
  final deadline = DateTime.now().toUtc().add(_requestTimeout);
  ...
  while (await chunks.moveNext().timeout(
    _remainingRequestTime(deadline, 'GET', path),
  ```
- **问题**：元数据校验允许 `declaredSize` 最大 16 GiB，但默认 30s 的 `_requestTimeout` 同时覆盖 body 流与哈希计算——任何传输+哈希总耗时超过请求超时的大工件都会确定性地以 `transportFailed` 失败。
- **修复建议**：为下载 body 使用独立预算（按 declaredSize 比例放大，或改为「无总限 + 空闲超时（chunk 间最大间隔）」），哈希阶段同样单独限时。
- **验证**：单测用慢速本地 HTTP server 提供 >30s 传输时长的工件，断言能下载成功；断言空闲流仍会在空闲超时后被切断。

### A-11 🟡 SSE 空转轮询每 100ms 全量解码并校验整个 workspace projection

- **位置**：`packages/cockpit/lib/src/supervisor/cockpit_supervisor_sse.dart:61-77`（100ms 轮询 `runtime.events` 与 `runtime.run(runId)`）；深层代价在 `cockpit_supervisor_runtime.dart:1085-1101,1177-1185` → `cockpit_supervisor_run_projection.dart:318-338,1249+`（`_decodeProjection` 全量解码 + 1417-1423 行 O(事件数) 连续性循环）。`runs()` 列表与 `run-cases` 路由（`cockpit_supervisor_http_api.dart:478-479`）同样每次全量解码。
- **问题**：存储上限 64MB/1 万 run 时，每个空闲 SSE 客户端每 100ms 触发两次全状态解码；多客户端叠加后守护进程 CPU 被读路径吃光。
- **修复建议**：按 store 文件的 (mtime,size) 或版本号缓存已解码 projection，写路径更新时失效；或改为内存 projection 增量维护、磁盘仅做持久化镜像。
- **验证**：基准测试：10k run 的 store 上连续 100 次 `events` 读取，断言引入缓存后解码次数为 O(1) 且延迟显著下降。

### A-12 🔵 租约注册表纯读操作也走完整写事务（锁文件+全量解码+编码+原子写）

- **位置**：`packages/cockpit/lib/src/supervisor/cockpit_lease_registry_support.dart:6-14`（`get()`/`list()`/`activeReferenceCount()` 返回 `CockpitLockedJsonUpdate.write(...)`）；底层 `cockpit_locked_json_store.dart:311-317` 证明 write 无条件落盘。`cockpit_lease_admission.dart:199-236` 的 50ms 等待循环每次迭代做两次完整事务。
- **修复建议**：读操作返回 `CockpitLockedJsonUpdate.readOnly`（需先确认状态未变；可比较编码字节或由 store 维护脏标记），等待循环改用 readOnly。
- **验证**：单测断言 `get`/`list` 不再产生文件写入（监控文件 mtime/写入计数）。

### A-13 🔵 `publish`/`publishArtifacts` 在 `_updateRetention` 中第二次全量解码 store

- **位置**：`packages/cockpit/lib/src/supervisor/cockpit_supervisor_run_projection.dart:295,514`（事务完成后调用）与 `1082-1099`（`_updateRetention` 重新 read+decode 整个文档，仅为算一个 run 的 `artifactCount`/终态）。
- **修复建议**：在事务内部用已解码状态派生 retention 所需信息，删除二次读取。
- **验证**：现有 projection 测试全绿即可；可加断言发布路径只解码一次（打桩计数）。

### A-14 🟡 每次工件访问都对整文件重算 sha256 并重新解析 report/manifest JSON，下载再读一遍文件

- **位置**：`packages/cockpit/lib/src/supervisor/cockpit_supervisor_run_projection.dart:918-925`（`requireArtifact` 全文件 sha256）；`requireSuiteReport` 在 586-592 行额外重新读取并 `jsonDecode` `report.json`。
- **现状代码**：
  ```dart
  final size = await File(candidate).length();
  final digest = (await sha256.bind(File(candidate).openRead()).first)
      .toString();
  ```
- **问题**：`artifactFile` 下载与 `requireSuiteReport` 每次请求都付出整文件哈希 + JSON 解析，随后 HTTP 下载再把文件流一遍——大媒体工件每次下载 2 倍以上 I/O。
- **修复建议**：发布时一次性验证并缓存摘要（按 path+mtime+size 失效），或仅在 size/mtime 与记录不一致时才重哈希；report 解析结果同样缓存。
- **验证**：单测两次下载同一 artifact，断言第二次不再读文件做哈希（打桩计数），且 mtime 变化后会重新校验。

### [x] A-15 🟡 `_settleReadyState` 无条件清空 `_pendingStartupSettle`，且 `reload()` 绕过单飞守卫：并发 settle 互相踩踏、settle 存活超过 dispose（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/development/cockpit_development_session_supervisor.dart`——尾部清空在 599-605 行（`_pendingStartupSettle = null;`）；单飞守卫 `_beginStartupRecovery`（`_pendingStartupSettle ??= ...`）在 659-662 行；`reload()` 在 304 行附近**直接**调用 `_settleReadyState`；`_disposeResources`（843-853 行）不等待在途 settle。
- **现状代码**：
  ```dart
  _log('settle end state=${_status.state.jsonValue} ...');
  _pendingStartupSettle = null;   // 无条件清空，不校验是否是自己
  return ready;
  ```
- **问题**：startup settle S1 在途时，一次 `POST /reload` 直接跑 S2；S2 结束时把 `_pendingStartupSettle` 置 null 而 S1 仍在跑。下一个 machine 事件触发 `_beginStartupRecovery()` 看到 null 启动 S3——S1/S3 并发，两者都循环探测并调用 `_setStatus`，状态来回抖动，`waitForStartupRecovery()` 可能返回中间态。另外 dispose 不等待在途 settle，`done` 完成后 settle 循环还会对已关闭会话探测写状态长达 `_startupSettleTimeout`（默认 30s）。
- **修复建议**：清空前校验 `identical(thisSettle, _pendingStartupSettle)`；`reload` 的 settle 走同一单飞守卫；`_disposeResources` 中 await（或协作取消）在途 settle。
- **验证**：单测构造「startup settle 在途 + reload」交错，断言任一时刻只有一个 settle 在跑；dispose 后断言不再有探测日志。

### [x] A-16 🟡 开发会话 `_log` 的 `unawaited(logger(message))` 无错误接收：一次日志写失败即产生未处理异步错误（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/development/cockpit_development_session_supervisor.dart:855-861`（`_log`）；`_logger` 为 worker 侧 `_logSession(...)`，做真实文件 I/O（含日志轮转/flush）。
- **现状代码**：
  ```dart
  void _log(String message) {
    final logger = _logger;
    if (logger == null) {
      return;
    }
    unawaited(logger(message));
  }
  ```
- **问题**：`_log` 在几乎每个状态迁移（含 `_setStatus`、machine 事件处理、settle 循环）被调用。一次日志写失败（磁盘压力、轮转期间文件被替换）就产生无监听的错误 future → worker 内未处理异步错误，纯诊断失败可能触发 worker 的非安全终止路径。
- **修复建议**：`unawaited(logger(message).catchError((_) {}))`（或让 `_logSession` 自身吞错并计数），对齐 `cockpit_worker_runtime.dart:461-492` 对 resume future 的防护写法。
- **验证**：单测注入抛错的 logger，断言连续 `_log` 调用不产生未处理异常。

### [x] A-17 🟡 worker 池：`shutdownWorkspace` 在重启窗口移除 slot 后，持有 `slot.ready` 的调用方永久挂起（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/supervisor/cockpit_worker_pool.dart`——`startCall` 返回 `existing.ready`（216 行）；`shutdownWorkspace` 移除 slot 并取消重启定时器（296-299 行）；`_start` 的 launch 完成回调在 slot 已被移除时直接 return **不完成 completer**（353-360 行，只有 launch 失败路径完成它）；`ready` getter（520-522 行）在 connection 为 null 时返回 pending 的 `readyCompleter.future`；`startCall` 的 `deadline` 只传给 `connection.call`，不约束获取连接阶段。
- **问题**：worker 退出 → `_connectionExited` 置空 connection、重置 completer、安排重启退避（最长 10s）。此窗口内 `_dispatchRun`（`cockpit_supervisor_runtime.dart:932`）或 `cancelRun` 拿到 pending completer future；随后 `removeWorkspace`/`close` 执行 `shutdownWorkspace`——没有任何代码完成该 completer。`call.result` 永不结算、`_dispatchRun` 永不返回、`_activeRuns[runId]` 永久泄漏、run 永远显示 `running` 且无实际调度，`slot.activeCalls` 永远 ≥1。
- **修复建议**：`shutdownWorkspace` 对被移除 slot 的 `readyCompleter` 注入失败（如 `workerPoolClosed`），并/或让 `startCall` 把「获取连接」与调用 deadline 竞争。
- **验证**：单测：worker 退出后立即 shutdownWorkspace，断言在途 `startCall` 以明确错误完成而非挂起，`_activeRuns` 不残留。

### [x] A-18 🟡 `_appStartedObserved` 从不复位 + settle 终写覆盖崩溃真相：`failed` 被回退成永久 `starting`（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/development/cockpit_development_session_supervisor.dart:107`（`_appStartedObserved` 仅在 410/430/731 行置 true，无任何复位）；`_probeAppReachability`（608-621 行）依赖该陈旧标志返回 `true`；settle 终写（569-580 行）在探测不确定时写 `starting`。
- **问题**：settle 进行中应用崩溃：`app.stop` 事件处理器正确写入 `failed`；settle 超时后 `_probeAppReachability` 因 `machineClient.lastExitCode == null`（Android/iOS 上 flutter-run 比应用活得久）且平台探测不确定（web/未知平台/adb 离线时按设计返回 null，见 `cockpit_platform_app_reachability.dart:39-44`）而返回 `true`，settle 的最终 `_setStatus` 把 `failed` 回退成 `starting`——此后 `_pendingStartupSettle` 已为 null 且不会再有 `app.start`/`app.started` 事件，状态永久搁浅在瞬态 `starting`（只有外部 `refreshStartupRecovery` 恰好执行才能逃出）。
- **修复建议**：`app.stop`/进程退出时复位 `_appStartedObserved = false`；settle 终写不得降级事件处理器已写入的终态（failed/stopped）。
- **验证**：单测：settle 在途时注入 app.stop + 不确定探测，断言最终状态保持 `failed`。

### [x] A-19 🟡 `stop()`/`detach()` 不中止在途 settle：settle 终写把用户请求的 `stopped` 覆写为 `failed`/`starting`（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/development/cockpit_development_session_supervisor.dart`——`stop()`（337-374 行）写 `state: stopped` 并杀 machine client；`detach()`（376-405 行）；settle 循环（538-596 行）**不检查** `_explicitStopRequested`/`_controlPlaneClosed`（grep 确认这些标志只在事件处理器与 bind 路径被检查）。
- **问题**：`POST /stop` 在 `_pendingStartupSettle` 探测期间到达：stop 写入 `stopped` 并关控制面后，settle 继续探测到自己的 deadline（30s+），全部失败，`_probeAppReachability` 见 `lastExitCode != null` → `appExited` → 终写把 `stopped` 覆写为 `failed`（detach 路径则可能覆写为 `starting`）。`currentStatus()`/`waitForStartupRecovery()` 观察者看到会话从用户请求的 `stopped` 倒退，且 `_doneCompleter` 早已触发——同一状态对象上的矛盾写者。
- **修复建议**：settle 循环每轮检查 `_explicitStopRequested || _controlPlaneClosed` 并中止；中止时跳过终写 `_setStatus`。
- **验证**：单测：settle 在途时调用 stop，断言最终状态保持 `stopped` 且 settle 日志显示中止。

### [x] A-20 🟡 reload 失败把状态搁浅在 `starting` 且无任何恢复调度（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/development/cockpit_development_session_supervisor.dart:315-334`（reload 的 catch 分支）。
- **现状代码**：
  ```dart
  state: appStillReady
      ? CockpitDevelopmentSessionState.ready
      : _status.state == CockpitDevelopmentSessionState.failed
      ? CockpitDevelopmentSessionState.failed
      : CockpitDevelopmentSessionState.starting,
  ```
- **问题**：热重载失败且桥暂时不可达（如 iOS 隧道抖动，`remoteSessionReachable == false`、状态尚非 `failed`）时写 `starting`——但此刻 `_pendingStartupSettle` 已为 null（604 行清除），`_beginStartupRecovery` 只由 `app.start`/`app.started`/`bindRemoteSession` 触发，中途 reload 失败后都不会再来。会话无限期停留在瞬态 `starting`，向外界伪装成恢复中。
- **修复建议**：reload 失败时要么恢复 reload 前状态，要么显式调度 `_beginStartupRecovery()`。
- **验证**：单测：reload 抛错 + 桥不可达，断言状态回到 reload 前值或有恢复 settle 被调度。

---

## B. packages/cockpit — CLI、用例执行与录制

### [x] B-1 🔴 用例「优雅取消」在操作按期完成后仍会被延迟的强杀定时器打断（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/runner/cockpit_case_execution_control.dart:89-111`（`cockpitRacePrimaryControl` 的 `_PrimaryCancellation` 分支）。`forceAbort` 的接线在 `packages/cockpit/lib/src/worker/cockpit_worker_runtime_registry.dart` 中（`forceAbortSession`，负责停止应用并移除会话/录制/probe/自有工件）。
- **现状代码**：
  ```dart
  case _PrimaryCancellation<T>():
    final settled = operation.then<void>((_) {}, onError: ...);
    final graceExpired = clock.delay(control.cancellationGrace).then<void>((_) {
      unawaited(control.forceAbortActive().catchError(...));
    });
    await Future.any<void>(<Future<void>>[settled, graceExpired, ...]);
    ...
    throw const CockpitCaseCancelled();
  ```
- **问题**：`Future.any` 不会取消落败的 future。当被取消的操作在 `cancellationGrace`（默认 2s）内优雅完成时，`cockpitRacePrimaryControl` 立即返回 `CockpitCaseCancelled`，内核进入 finally 清理段（录制停止、工件收集，预算 `cleanupTimeoutMs` 默认 30s）；但 `graceExpired` 定时器依然武装着，约 2s 后无条件触发 `forceAbortActive()`——把每次「优雅取消」都悄悄变成延迟强杀，可能摧毁正在收尾的录制与工件。
- **修复建议**：用 `settled` 完成时置位的标志（或直接持有 `Timer` 并在 settle 时 `cancel()`）门控 grace 回调，确保仅当操作在宽限窗口内**未**完成时才强杀。
- **验证**：单测：请求取消后让 operation 在 100ms 内正常完成，等待 3×grace 时长，断言 `forceAbort` 从未被调用；反向用例（operation 挂起超过 grace）断言强杀被调用。

### [x] B-2 🔴 片段（fragment）菱形调用让文档编译器在步数上限生效前指数爆炸、永久挂起（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/test/cockpit_test_document_compiler.dart:948-969`（`_expandedStepCount` 的内层 `countSteps`，无记忆化、无提前退出）；上限检查在 655-662 行、且只在计数完成后执行；`_validateCallGraph`（869-905 行）只拒绝环，`maxNesting`（527 行附近）只限制控制块嵌套而非 fragment 调用深度。
- **现状代码**：
  ```dart
  case CockpitTestCallOperationTemplate(:final fragment):
    final fragmentSteps = testCase.fragments[fragment];
    if (fragmentSteps != null && !fragmentStack.contains(fragment)) {
      count += countSteps(fragmentSteps, <String>{
        ...fragmentStack,
        fragment,
      });
    }
  ```
- **问题**：构造 f1 包含两个调用 f2 的 call step、f2 包含两个调用 f3……约 30 个几 KB 的小片段（远小于 1MiB 文档上限）即可让 `countSteps` 执行约 2^30 次访问，编译器在 `expanded > limits.maxExpandedSteps` 判定有机会执行前就挂死，worker 被卡住。
- **修复建议**：计数改为累计变量并在每层递增后立即检查 `if (runningTotal > limits.maxExpandedSteps) throw FormatException('expandedStepLimitExceeded', ...)`（把上限检查前移进递归）；或对「无环 + 相同栈前缀」的 fragment 计数做记忆化。
- **验证**：单测构造 25 层菱形调用文档，断言编译在毫秒级返回 `expandedStepLimitExceeded` 诊断而非挂起。

### [x] B-3 🔵 `dev status` 中约 48 行不可达的五路诊断扇出死代码（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/cli/cockpit_dev_runtime.dart`。458 行 `if (diagnose) return _diagnose(session);` 先返回 diagnose=true 分支；467-491 行 `if (!diagnose) { ... return writeEnvelope(action: 'status', ...); }` 返回 diagnose=false 分支；其后直到 539 行的 `Future.wait`（target.inspect/ui.inspect/errors.read/network.read/logs.read 五路调用及其 writeEnvelope）不可达；463 行的 `diagnose ? 'diagnose' : 'status'` 三元也因此恒为 `'status'`。
- **问题**：五路扇出逻辑实际在 `_diagnose`/`_diagnosticReads` 中，此处是重构残留。死代码误导维护者以为 `status` 会执行诊断扇出，在此处的修改不会有任何效果。
- **修复建议**：删除 492-539 行不可达代码块，并将 463 行三元简化为 `'status'`。
- **验证**：`dart analyze` 通过；`cockpit dev status` 与 `cockpit dev diagnose` 的输出快照测试（如有）保持不变。

### B-4 🟡 simctl 录制：持久化会话写入失败时录制进程与流订阅泄漏

- **位置**：`packages/cockpit/lib/src/recording/cockpit_simctl_recording_adapter.dart:131-158`（`startRecording`）。
- **现状代码**：
  ```dart
  try {
    await _waitForProcessStartup(...);
  } on Object {
    await stdoutSubscription.cancel();
    ...
    rethrow;
  }
  final startedAt = DateTime.now();
  await _writePersistedSession(...);   // 不在上面清理的保护范围内
  await stdoutSubscription.cancel();
  await stderrSubscription.cancel();
  ```
- **问题**：kill/取消清理只覆盖 `_waitForProcessStartup` 失败。`_writePersistedSession`（149 行）因磁盘满/权限等抛错时，`startRecording` 向上传播错误，但 `simctl recordVideo` 进程继续录制、两个流订阅未取消；且会话文件未写成，后续 `stopRecording` 只会报「无活动会话」，孤儿进程只能靠 `ps` 启发式发现。
- **修复建议**：把启动成功后的持久化写入也纳入同一清理保护（失败时取消两个订阅、SIGKILL 进程并等待退出、删除半写成的会话文件），或整体改写为 startup 之后任何一步失败都走统一 teardown。
- **验证**：单测让 `_writePersistedSession` 抛错，断言进程收到 kill、订阅已取消、无残留会话文件。

### [x] B-5 🔵 `daemon logs --lines` 帮助文本承诺 1-2000 范围但从不校验（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/cli/commands/daemon_commands.dart:108-119`；同文件已有可复用的严格校验样板 `run_commands.dart:483` 的 `_integer(arguments, 'limit', minimum: 1, maximum: 100)`。
- **现状代码**：
  ```dart
  parser.addOption('lines', defaultsTo: '50',
    help: 'Maximum number of trailing log lines (1-2000).'),
  ...
  final count = int.tryParse(arguments.option('lines')!);
  if (count == null) throw const FormatException('--lines is invalid.');
  ```
- **问题**：`--lines 0`、`--lines -5`、`--lines 5000000` 都被原样转发给守护进程，用户得到服务端错误或无界读取，而不是本地用法错误（exit 64），与 `run list --limit` 的行为不一致。
- **修复建议**：改用 `_integer(arguments, 'lines', minimum: 1, maximum: 2000)` 风格校验（若 helper 在别的文件，抽到共享位置）。
- **验证**：CLI 参数测试断言越界值返回用法错误 exit 64。

### B-6 🟡 套件调度器 `Future.any(running.values)` 在观察者回调抛错时重抛并放弃全部兄弟节点 future

- **位置**：`packages/cockpit/lib/src/suite/cockpit_suite_scheduler.dart:460-462`；观察者回调（`nodeStarted` 537 行、`attemptStarted` 562、`attemptCompleted` 577、`nodeCompleted` 613）实现在 `packages/cockpit/lib/src/worker/cockpit_suite_run_adapter.dart`，均为**无守卫的文件 I/O**（`_runStore.record*`、`_eventStore.append`）；调度器调用点在同文件 482/553/590/728 行。
- **现状代码**：
  ```dart
  final execution = await Future.any(running.values);
  running.remove(execution.nodeId);
  ```
- **问题**：磁盘错误让某个节点的 future 以错误完成时，`Future.any` 从 `run()` 重抛（外层 208 行的 catch 把整套件标记失败），但其余在跑的兄弟节点被放弃：它们继续对设备执行用例，而 worker 已按失败收尾并释放它们持有的资源授权/租约；兄弟节点稍后命中同样的日志错误时其错误无监听 → 未处理异步错误涌入 worker。
- **修复建议**：为每个节点 future 包装错误捕获 shim（`.then(ok, onError: capture)`）后再放入 `running`，错误路径先等待/停止兄弟节点再返回；或给观察者回调包 try/catch 把日志失败降级为警告。
- **验证**：单测让第二个节点的 `nodeStarted` 抛错，断言其余节点被有序停止（而非继续执行）、无未处理异常、套件结果包含该失败。

### B-7 🟡 simctl 录制恢复对持久化 PID 裸信任：PID 复用可误杀无关进程

- **位置**：`packages/cockpit/lib/src/recording/cockpit_simctl_recording_adapter.dart`——`_requestGracefulStop` 把 `session.pid` 无条件并入信号集（349-352 行）；`stopRecording` 的 `TimeoutException` 路径直接对裸 pid SIGKILL（188-195 行）；`_restoreableSessionExists`（288-294 行）同样只查存活。对照：ps 发现的 PID 有命令行校验（`_isSimctlRecordingCommand` 776-783 行：simctl/xcrun + recordVideo + 精确输出路径），但持久化 pid 只做存活检查（`_livePids` 478-486 行）。
- **问题**：持久化会话按设计跨进程重启存活；原录制进程退出后 macOS 激进回收 PID 时，`stopRecording`/恢复流程会向**现在拥有该 PID 的任意进程**发 SIGINT 再 SIGKILL（超时路径跳过 SIGINT 直接 SIGKILL）。
- **修复建议**：对 `session.pid` 先做与 `_discoverLiveRecordingPids` 相同的命令行校验（或校验启动身份）再纳入信号集；`_restoreableSessionExists` 同样处理。
- **验证**：单测注入一个存活但命令行不匹配的 pid，断言不被发信号；匹配的照常停止。

---

## C. packages/cockpit — 基础设施、进程与网络

### [x] C-1 🔴 桥接服务器在响应已部分写出后再写错误响应：二次异常逃逸为未处理异步错误（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/bridge/cockpit_web_remote_session_bridge_server.dart:102-129`（`_handleRequest` 的 catch 分支）；`_writeResponse` 在 956-982 行（对 `sourceFilePath` 走 `response.addStream(File(...).openRead())`，974 行附近）；订阅点 `server.listen(_handleRequest)` 在 80 行。
- **现状代码**：
  ```dart
  final response = await _resolveResponse(request);
  await _writeResponse(request.response, response);
  } on FormatException catch (error) {
    await _writeResponse(request.response, ... statusCode: HttpStatus.badRequest);
  } catch (error) {
    await _writeResponse(request.response, ... statusCode: HttpStatus.internalServerError);
  }
  ```
- **问题**：首次 `_writeResponse` 若在 body 中途失败（客户端在文件流传输中断开、文件在校验与读取之间消失），catch 分支会对**同一个已提交 status/headers/body 的 response** 再次 `_writeResponse`——对已发送响应设置 statusCode/headers 会抛错，该二次异常从 `_handleRequest` 逃逸，而 `listen(_handleRequest)` 不消费该 future，成为可击垮 worker/守护进程的未处理异步错误。
- **修复建议**：两个 catch 分支里的 `_writeResponse` 各自再包 try/catch，失败时 best-effort `response.close()`（或 `response.detachSocket()` 丢弃），保证任何写失败都不逃逸请求处理函数。
- **验证**：单测模拟客户端在文件 body 传输中途断开，断言无未处理异常且连接被关闭。

### C-2 🟡 每次主机截屏泄漏一个系统临时目录+文件（失败时还泄漏半成品）

- **位置**：`packages/cockpit/lib/src/capture/cockpit_host_capture_adapter.dart:21-26`（`cockpitCreateCaptureTempFile`——全仓库唯一创建点，无任何删除点）；各适配器失败路径不清理，如 `cockpit_macos_capture_adapter.dart:99-128`、`cockpit_linux_capture_adapter.dart:85-97`、`cockpit_simctl_capture_adapter.dart:64-75`、`cockpit_windows_capture_adapter.dart:94-101`、`cockpit_adb_capture_adapter.dart:91-102`；成功路径保留者只复制不删除（`packages/cockpit/lib/src/worker/cockpit_worker_artifact_retainer.dart:503-582`）；默认工厂注入点 `cockpit_system_control_action_service.dart:2873-2924`。
- **现状代码**：
  ```dart
  Future<File> cockpitCreateCaptureTempFile(String basename) async {
    final directory = await Directory.systemTemp.createTemp(
      'flutter_cockpit_capture_',
    );
    return File(p.join(directory.path, basename));
  }
  ```
- **问题**：每次截屏新建 `flutter_cockpit_capture_*` 目录，成功时保留者只把文件**复制**进工件区、失败/超时路径直接返回不删——在无 /tmp 定期清理的 Linux CI 主机上，长 E2E 会以每次数 MB 的速度无限增长。
- **修复建议**：所有失败路径在 finally 中删除临时文件及其父目录；成功路径在保留/发布完成后删除源临时文件（或把截屏直接写入 worker 已管理的 `producerRoot/tmp`，随 worker 生命周期清理）。
- **验证**：单测/集成断言截屏成功与失败两种路径后 `Directory.systemTemp` 中不再存在 `flutter_cockpit_capture_*` 目录。

### C-3 🟡 `DefaultCockpitHttpClient` 无法关闭且超时只「放弃」不「取消」：守护进程内积累半开连接

- **位置**：`packages/cockpit/lib/src/infrastructure/cockpit_http_client.dart:9-37`（接口无 `close()`；`_client` 惰性创建后永不释放）；守护进程启动即构造（`cockpit_supervisor_runtime.dart:206` → `CockpitPubDevSearchService`，调用方 `cockpit_pub_dev_search_service.dart:187-197` 只用 `.timeout(...)`）。
- **现状代码**：
  ```dart
  abstract interface class CockpitHttpClient {
    Future<String> read(Uri uri);
    Future<List<int>> readBytes(Uri uri);
  }
  ```
- **问题**：keep-alive 连接池永不释放；`.timeout` 不会中止底层请求，每次慢网络下的 pub.dev 搜索超时后，socket 与响应缓冲都留在内存中无法中止，长驻守护进程反复搜索会积累半开连接。
- **修复建议**：接口增加 `close()`（或按请求创建 `HttpClient` 并在 finally `close(force: true)`——参考 `cockpit_remote_session_client.dart:418-496` 的做法）；设置 `connectionTimeout`，让超时真正取消请求。
- **验证**：单测注入假 client 断言 close 被调用；泄漏测试断言超时后底层 client 的连接被强制关闭。

### C-4 🟡 `CockpitWorkerProcessManager._collect` 对子进程 stdout/stderr 无上限内存缓冲

- **位置**：`packages/cockpit/lib/src/worker/cockpit_worker_process_manager.dart:96-105`；该管理器被接入 worker 的工具/应用适配器（`cockpit_worker_runtime.dart:318,416-421`）；对比已有的有界实现 `packages/cockpit/lib/src/infrastructure/cockpit_process_output_collector.dart`（4MB 环形缓冲）。
- **现状代码**：
  ```dart
  Future<Object> _collect(Stream<List<int>> stream, Encoding? encoding) async {
    if (encoding == null) {
      final bytes = <int>[];
      await for (final chunk in stream) {
        bytes.addAll(chunk);
      }
      return bytes;
    }
    return stream.transform(encoding.decoder).join();
  }
  ```
- **问题**：多话的子进程（flutter 命令倾倒巨量日志、失控的测试二进制）会把全部输出积累在内存中，可致 worker OOM——尽管进程本身只按取消策略被杀。
- **修复建议**：复用 `CockpitProcessOutputCollector` 的有界/截断语义，或为 `_collect` 增加字节上限（超限截断并记录丢弃计数）。
- **验证**：单测让假进程输出超过上限的数据，断言结果被截断且进程内存不随输出无限增长。

### C-5 🔵 临时主机端口分配是「探测后释放」的 TOCTOU：并发进程可抢占端口

- **位置**：`packages/cockpit/lib/src/remote/cockpit_ios_port_forwarder.dart:198-209`（`_isHostPortAvailable`）与 211-218（`_allocateHostPort`）；同样模式 `cockpit_android_port_forwarder.dart:128-135`、`cockpit_local_session_port_resolver.dart:45-52`。
- **现状代码**：
  ```dart
  static Future<int> _allocateHostPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    try {
      return socket.port;
    } finally {
      await socket.close();
    }
  }
  ```
- **问题**：socket 关闭后才把端口交给 iproxy/adb forward/会话使用，窗口期内任何并发绑定该端口的进程都会偷走它；iOS 路径的 `_waitUntilListening`（131-168 行）随后可能「成功」连上一个陌生进程。
- **修复建议**：尽可能持有已绑定 listener 直到消费者就绪再移交/关闭；或当 iproxy/adb 报告绑定失败时自动换端口重试，而不是信任预探测结果。
- **验证**：并发测试：分配端口后立即由测试方抢占该端口，断言前向器能检测并重试或给出明确错误，而非静默连错进程。

### C-6 🟡 worker run 事件存储把每个 run 的完整事件列表在内存中保留到 worker 生命周期结束

- **位置**：`packages/cockpit/lib/src/worker/cockpit_worker_run_event_store.dart:159-165`（`_events`/`_eventIds`/`_acknowledged` 声明；写入点 211、439-442 行；全文件无任何 `_events.remove`/`_eventIds.remove`/`_acknowledged.remove`）。
- **现状代码**：
  ```dart
  final Map<String, List<CockpitRunEvent>> _events = <String, List<CockpitRunEvent>>{};
  final Set<String> _eventIds = <String>{};
  final Map<String, int> _acknowledged = <String, int>{};
  ```
- **问题**：`_terminalSupervisorRuns` 只停止继续发布，不回收历史。长驻 workspace worker 跑大量 case（每个 run 上限 `maximumEventsPerRun`=10 万条 JSON 重的事件）会在内存中单调积累；跑几天的 dev worker 逐渐耗尽内存。
- **修复建议**：run 终态且 supervisor 已确认最终序号（或超时）后，丢弃内存列表；迟到的 `replayEvents` 请求回放到磁盘 `events.ndjson`。
- **验证**：单测跑完并确认多个 run 后断言 `_events` 为空（或仅保留最近 N 个），replay 请求仍能从磁盘完整回放。

### C-7 🟡 iOS 端口转发 `ensureForwarded` 对 `_forwards` 的检查-后-写入竞争：并发调用泄漏孤儿 iproxy 进程

- **位置**：`packages/cockpit/lib/src/remote/cockpit_ios_port_forwarder.dart:41-44`（`_findForward` 检查）与 83-91 行（await 之后才 `_forwards[key] = forwarded`；失败路径按 key remove 不校验身份）。
- **现状代码**：
  ```dart
  final existing = _findForward(deviceId: deviceId, devicePort: devicePort);
  if (existing != null) return existing.hostPort;
  ...
  _forwards[forwarded.key] = forwarded;
  try {
    await _waitUntilListening(forwarded);
    return hostPort;
  } on Object {
    _forwards.remove(forwarded.key);
  ```
- **问题**：两个并发 `ensureForwarded`（同一 deviceId+devicePort；套件 maxConcurrency>1 时真实存在）都通过检查、都启动 iproxy，后者覆盖前者的表项——前者进程失联，`removeForwarded`/`close()` 永远杀不掉它，永久占用主机端口。失败路径更糟：A 的 remove 会删掉 B 刚写入的表项，B 成功后其进程同样失联。
- **修复建议**：改为 per-key 的在途 future 记忆化（single-flight map：首个调用启动，后续 await 同一 future）；remove 前用 `identical` 校验仍持有该表项。
- **验证**：单测并发调用 `ensureForwarded` 同一 key 两次，断言只启动一个 iproxy、两个调用者拿到同一 hostPort；失败注入时断言只清理自己拥有的表项。

---

## D. packages/flutter_cockpit — 应用内桥接运行时

### D-1 🔴 命令硬超时只是「放弃等待」：被放弃的手势继续派发指针，队列并发启动下一条命令

- **位置**：`packages/flutter_cockpit/lib/src/executor/in_app_cockpit_command_executor.dart:336-354`（`_executeWithArtifacts` 的 `execution.timeout(...)`）；队列释放点同文件 7108-7118 行（`_CockpitCommandQueue._startNext` 的 `whenComplete`）；队列自身的文档注释（7079-7085 行）明确要求命令绝不并发。
- **现状代码**：
  ```dart
  return await execution.timeout(
    enforcedTimeout,
    onTimeout: () => _commandTimeoutExecution(...),
  );
  // —— 队列 ——
  task.zone.run<Future<void>>(() => Future<void>.sync(task.operation))
      .whenComplete(() {
    _active = false;
    scheduleMicrotask(_startNext);
  });
  ```
- **问题**：`Future.timeout` 不取消底层工作。超时后 `_executeWithArtifacts` 返回兜底结果，队列的 `whenComplete` 随之把 `_active` 置 false 并启动下一条命令——但被放弃的 drag/wait 等仍在派发指针事件，两条命令的指针流交错（例如被放弃的 drag 指针 1 仍按住，下一条 tap 也用指针 1），正是队列注释禁止的场景。
- **修复建议**：队列只应在**底层操作 future**（而非超时 future）结算后释放 `_active`（让入队闭包同时暴露底层 future）；超时路径对被放弃命令注入 pointer-cancel（或调用执行器的取消钩子）以终止残留手势。
- **验证**：单测：一条 `timeoutMs` 极小的 drag 超时后立即排入 tap，断言 tap 执行时不存在未释放的指针（检查队列 `_active` 语义与指针状态）。

### [x] D-2 🔴 `HttpClientRequest.done` 绕过观测：pending 网络记录永不完成，idle 等待永久报忙（fixed in 656a12f）

- **位置**：`packages/flutter_cockpit/lib/src/network/cockpit_http_network_observer.dart:528-529`。
- **现状代码**：
  ```dart
  @override
  Future<HttpClientResponse> get done => _delegate.done;
  ```
- **问题**：`close()`（612 行）与 `abort()`（599 行）会终结 pending 记录，但 dart:io 文档支持的 `addStream(...); await request.done` 写法完全绕过观测：记录永远留在 `_pending`、`_inFlightCount` 永不递减，`waitForIdle()`（103 行）必然超时，`_pending` 无界增长；且返回的是未观测的原始 response，其 body 也不被捕获。
- **修复建议**：`done` 走与 `close()` 相同的包装：终结 pending 记录并返回观测版 response。
- **验证**：单测用 `await request.addStream(stream); final r = await request.done;` 发请求，断言记录完成、`waitForIdle()` 正常返回、response body 被观测。

### [x] D-3 🟡 远端工件注册表无界增长（内存 + 临时文件）（fixed in 656a12f）

- **位置**：`packages/flutter_cockpit/lib/src/remote/cockpit_remote_session_endpoint_handler.dart:179-180`（`_downloadableArtifacts` 声明）；写入点 621、646、688、822 行（命令工件、录制、超过 16KB 的 `/snapshot` 负载各写一个临时文件）；仅在下载 miss（974/983 行）与 `close()`（187 行）时移除。
- **问题**：长 E2E/浸泡会话中每步截图、每次 `artifact=always` 快照都累积条目与临时文件（`deleteOnClose` 文件只在关闭时删），内存中 `bytes` 条目还保留完整负载。
- **修复建议**：注册表加 LRU 上限（如 256 条），驱逐时删除对应 `deleteOnClose` 文件；`bytes` 条目超过阈值落盘。
- **验证**：单测注册超过上限的工件，断言最旧条目及其临时文件被驱逐删除。

### [x] D-4 🟡 启动途中被 dispose 时，远端会话 server/bridge client 泄漏（端口永久占用）（fixed in 656a12f）

- **位置**：`packages/flutter_cockpit/lib/src/runtime/flutter_cockpit_root.dart:730-738`（`await server.start(); _remoteSessionServer = server;`）；Web 分支 718-719 行同样；`dispose()` 在 475 行附近通过 `unawaited(_remoteSessionServer?.close())` 清理。
- **问题**：`_beginRemoteSessionStart` 由 `initState` 触发，`await server.start()` 之后不检查 state 是否已销毁。若 Root 在绑定过程中被 dispose，`dispose()` 关闭的还是 null 引用；随后 server 绑定成功并赋给已死的 state，永远监听端口（bridge client 同理）。
- **修复建议**：`_startRemoteSessionIfEnabled` 中每次 `await` 后检查已销毁标志（如 `mounted` 或自维护的 `_disposed`），已销毁则立即 `close()` 刚创建的 server/client 并返回。
- **验证**：widget 测试：触发远端启动后立刻 dispose root，pump 足够帧，断言端口不再被监听（尝试再 bind 同端口成功）。

### [x] D-5 🟡 远端命令参数 `moveEventCount` 未夹紧：一条命令即可冻结 UI isolate（fixed in 656a12f）

- **位置**：`packages/flutter_cockpit/lib/src/executor/in_app_cockpit_command_executor.dart:1159`（`moveEventCount: _intParameter(command, 'moveEventCount') ?? 0`，另见 1300/1382/1415/1449 行）；引擎侧 `packages/flutter_cockpit/lib/src/gesture/cockpit_gesture_engine.dart:1386-1389` 对显式正值原样返回（对比 wheel 的 `steps` ≤1000、multi-touch ≤10000 的夹紧）。
- **现状代码**：
  ```dart
  if (requestedCount > 0) {
    return requestedCount;
  }
  ```
- **问题**：自动估算有 72-180 的夹紧，但显式计数不设限。经未鉴权远端端点下发的 `moveEventCount: 100000000` 会让手势循环执行上亿次（每步还有 `_delay`），等效冻结应用；叠加 D-1，超时也无法终止它。
- **修复建议**：在 `_resolvedMoveEventCount` 或参数解析处把显式 `moveEventCount` 夹紧到合理上限（如 10000，与 multi-touch 对齐）。
- **验证**：单测传入超大 moveEventCount，断言实际派发次数被夹紧；命令仍正常完成。

### [x] D-6 🟡 `cockpitShortId` 的全局 `_issued` 集合只增不减：每条运行时事件/日志行永久驻留（fixed in 656a12f）

- **位置**：`packages/flutter_cockpit/lib/src/runtime/cockpit_short_id.dart:6-7,24`；高频消费者 `cockpit_flutter_runtime_observer.dart:255`（`_nextEventId() => cockpitShortId('e')`，含每行 debugPrint/print）。
- **现状代码**：
  ```dart
  final Set<String> _issued = <String>{};
  ```
- **问题**：事件环形缓冲本身有界（`maxRetainedEvents`），但 id 去重集永不清理——多话应用长时间浸泡会稳定泄漏（百万行日志 → 数十 MB）。
- **修复建议**：事件 id 改用单调计数器（或时间戳+计数）生成，无需全局去重集；确需随机的场景改为每会话重置或有界集合。
- **验证**：单测生成大量 id 后断言 `_issued` 大小有界；id 唯一性不回归。

### D-7 🔵 widget 树快照对每个元素计算两次几何（`_boundsFor` 双调），且 `maxNodes` 丢弃前也算

- **位置**：`packages/flutter_cockpit/lib/src/runtime/cockpit_widget_tree_builder.dart:142-144`（`_RawWidgetNode` 构造器初始化列表中 `bounds = _boundsFor(element)` 与 `visible = _isVisible(element, viewport)`）与 262-267 行（`_isVisible` 内再次 `_boundsFor(element)`）。
- **现状代码**：
  ```dart
  offstage = _isOffstage(element),
  bounds = _boundsFor(element),
  visible = _isVisible(element, viewport);
  // —— _isVisible ——
  final bounds = _boundsFor(element)?.rect;
  ```
- **问题**：`_boundsFor` 是 `localToGlobal`（O(深度)）。万节点的树上一次 `/snapshot?tree` 请求约 2 万次几何遍历（外加 `_isOffstage` 的全祖先遍历），全部发生在 UI isolate；被 `maxNodes` 截断丢弃的节点也照算。
- **修复建议**：计算一次 bounds 并把 rect 传入 `_isVisible`；对确定不会输出的节点（超出 maxNodes）跳过几何计算。
- **验证**：基准测试对比修改前后万节点树快照耗时；现有树快照测试全绿。

### D-8 🔵 目标去重对所有发现目标 O(n²)，比较函数内部还有祖先遍历

- **位置**：`packages/flutter_cockpit/lib/src/runtime/cockpit_native_target_discovery.dart:398-415`（`_deduplicateDiscoveredTargets` 的 `indexWhere` 内嵌套三种重复判定，可升级为 `_areRelatedElements` 两次祖先遍历）。
- **问题**：每次 inspect 对同 label 目标较多的界面（网格/平铺卡片）退化为 n²/2 次昂贵比较，发生在 UI isolate。
- **修复建议**：先按廉价信号（route+text/semanticId/key）分桶，桶内再精确比较；或对每个目标的比较次数设上限。
- **验证**：基准测试构造 500 个同 label 目标，断言去重耗时从平方级降为近线性，结果不变。

### D-9 🔵 `_CockpitScrollableCandidate.textPreview` 每次访问解析 4 次语义信息

- **位置**：`packages/flutter_cockpit/lib/src/runtime/cockpit_surface.dart:3403-3407`；该 getter 在滚动匹配/排序循环（2539、2752 行附近）中每候选每步调用；release 模式下 `cockpitResolveSemanticsTargetInfo` 可回退到全语义树遍历（`cockpit_semantics_bridge.dart:161-221`）。
- **现状代码**：
  ```dart
  String? get textPreview =>
      cockpitResolveSemanticsTargetInfo(element)?.label ??
      cockpitResolveSemanticsTargetInfo(element)?.hint ??
      cockpitResolveSemanticsTargetInfo(semanticsElement)?.label ??
      cockpitResolveSemanticsTargetInfo(semanticsElement)?.hint;
  ```
- **修复建议**：候选构造时（其本身不可变）解析一次并缓存到字段，getter 直接返回。
- **验证**：现有滚动定位测试全绿；可加打桩断言每次滚动匹配中每个候选至多解析一次。

### D-10 🟡 路由转场监听表在转场中途移除路由时泄漏 Route+listener

- **位置**：`packages/flutter_cockpit/lib/src/runtime/flutter_cockpit_binding.dart:601-621`（listener 仅在动画到达 completed/dismissed 时移除）；登记表 108-109 行。
- **问题**：转场进行中被 `Navigator.removeRoute`/`replace` 移除的路由，其 controller 被销毁而不会有终态回调，表项（持有 Route 与闭包）无限期留存——频繁取消转场的应用持续泄漏。
- **修复建议**：同时监听 `NavigatorObserver.didRemove`/`didReplace` 清除对应表项；或给表加数量/时长上限兜底。
- **验证**：widget 测试：push 后立即 removeRoute，pump 完帧，断言监听表为空。

### D-11 🔵 共享手势引擎 `late final` 捕获首个 `gestureDelay`，运行时改配置静默失效

- **位置**：`packages/flutter_cockpit/lib/src/runtime/cockpit_surface.dart:93-96`（`late final CockpitGestureEngine _gestureEngine = CockpitGestureEngine(delay: widget.gestureDelay, ...)`）；`didUpdateWidget`（302-312 行）只重建 `_discoveryEngine` 不重建手势引擎；`FlutterCockpitRoot.build` 在 492 行附近转发 `binding.configuration.gestureDelay` 且 `updateConfiguration` 可在运行时修改它。
- **修复建议**：`didUpdateWidget` 中当 `oldWidget.gestureDelay != widget.gestureDelay` 时重建 `_gestureEngine`（hover 状态重置可接受）。
- **验证**：widget 测试：运行时更新 gestureDelay 后派发手势，断言实际事件间隔采用新延迟。

### D-12 🟡 `CockpitTargetNode` 经 GlobalKey 移出 surface 子树后保留旧注册表的过期注册

- **位置**：`packages/flutter_cockpit/lib/src/runtime/cockpit_surface.dart:3501-3507`（`_registerTarget` 在 `registry == null` 时直接 return，不会注销 `_registry`）。
- **现状代码**：
  ```dart
  void _registerTarget() {
    final surface = CockpitSurface.maybeOf(context);
    final registry = surface?.registry;
    if (registry == null) {
      return;
    }
  ```
- **问题**：reparent 出 surface 后 `didChangeDependencies` 触发时 registry 为 null 直接返回，旧 registry 中残留一个 `diagnosticNodeProvider` 解析到 surface 外元素的活目标——定位器可能匹配到过期几何并对其执行动作。
- **修复建议**：`registry == null` 分支先 `_registry?.unregister(widget.registrationId); _registry = null;` 再返回。
- **验证**：widget 测试：GlobalKey 把已注册目标从 surface 内移到 surface 外，断言旧注册表不再包含该 registrationId。

### [x] D-13 🟡 远端端点预算超时后放弃命令 future 且无错误接收：迟到的异常成为被测应用内的未处理错误（fixed in 656a12f）

- **位置**：`packages/flutter_cockpit/lib/src/remote/cockpit_remote_session_endpoint_handler.dart:348-356`（`_executeCommandWithinBudget`）。与 D-1（执行器队列层）互补但独立：此处是端点层对被放弃 future 未挂错误吸收。
- **现状代码**：
  ```dart
  try {
    return await _commandExecutor(command).timeout(enforcedTimeout);
  } on TimeoutException {
    return CockpitCommandExecution(...);
  ```
- **问题**：超时胜出时 `_commandExecutor(command)` 被放弃且**没有任何错误监听**。执行器稍后以错误完成（如 `_requireSurfaceState` 抛 `StateError('FlutterCockpitRoot is not mounted.')` 或任何内部失败）时，错误无监听 → 被测应用内未处理异步错误；同时「已超时」的命令还在继续改 UI，驱动的下一条命令会观察到被放弃命令的残留修改。
- **修复建议**：对被放弃的 future 挂一个吸收尾巴（`cmdFuture.then((_){}, onError: (_){})` 记录诊断），并在服务下一条命令前等待/终止在途命令（与 D-1 的队列级修复配合）。
- **验证**：单测让执行器在超时后抛错，断言无未处理异常且错误被记录；断言下一条命令开始前上一条已终结。

### [x] D-14 🟡 应用内远端服务器与 C-1 同型的「已提交响应二次写入」：异常逃逸 `listen` 回调进入被测应用（fixed in 656a12f）

- **位置**：`packages/flutter_cockpit/lib/src/remote/cockpit_remote_session_server.dart:103-111`（`_handleRequest` catch 分支再次 `_writeResponse(request.response, ...)`）与 126-132 行（文件流 `response.addStream(File(...).openRead())`）；`server.listen(_handleRequest)` 在 64 行附近丢弃 future。
- **问题**：工件文件在快照与下载之间被删除/轮转时 `addStream` 异步失败，catch 对**已提交 status/headers 的响应**再次设置 `statusCode` 抛 `StateError`，逃逸出 `_handleRequest` 成为被测应用的未处理异步错误，客户端连接悬挂。与 C-1 是不同组件（这是应用内 server，C-1 是主机侧 bridge server），需同样修复。
- **修复建议**：与 C-1 相同：catch 内的 `_writeResponse` 各自包 try/catch，已提交时只 best-effort `response.close()`。
- **验证**：单测在 body 流传输中途删除文件，断言无未处理异常、连接被关闭。

### [x] D-15 🟡 `FlutterCockpitBinding.startRecording` 允许 start→start：第二次原生录制覆盖会话句柄，第一次 OS 级录制成为孤儿（fixed in 656a12f）

- **位置**：`packages/flutter_cockpit/lib/src/runtime/flutter_cockpit_binding.dart:158-180`（守卫只查 `_recordingStarting`/性能捕获互斥，**不查 `_activeRecordingSession != null`**）；对照端点层的正确守卫 `cockpit_remote_session_endpoint_handler.dart:705-712`。
- **现状代码**：
  ```dart
  if (_recordingStarting ||
      _performanceStarting ||
      _activePerformanceSession != null ||
      performanceCollector.isRunning) {
    throw StateError('Screen recording cannot overlap a performance capture.');
  ```
- **问题**：第一次录制成功后（`_recordingStarting` 已复位、`_activeRecordingSession` 已置位）再次顺序调用 `startRecording` 会通过守卫启动第二次原生录制并覆盖 `_activeRecordingSession`——第一次 OS 级录制无人停止、持续写文件；后续 `stopRecording` 只按最新 request 收尾。绑定是状态机的真正所有者，任何绕过端点守卫的直连路径（宿主嵌入、`FlutterCockpitRoot.startRecording`）都踩中；错误消息也与实际场景不符（总说性能捕获重叠）。
- **修复建议**：守卫加入 `_activeRecordingSession != null`（抛准确错误），对齐端点层。
- **验证**：单测连续两次 `startRecording`，断言第二次被拒且第一次会话仍可正常 stop。

### [x] D-16 🟡 dispose / updateConfiguration 直接丢弃活动录制会话句柄而不停止原生录制（fixed in 656a12f）

- **位置**：`packages/flutter_cockpit/lib/src/runtime/flutter_cockpit_binding.dart:273-278`（`dispose()` 中 `_activeRecordingSession = null;`）与 357-362 行（`updateConfiguration` 换 nativeRecording 适配器时同样只置 null）。测试侧 teardown 会走到 `FlutterCockpit.dispose()`。
- **问题**：经远端桥开始的验收录制，在测试结束/应用换掉 cockpit root 后，iOS/Android 系统级录屏继续进行（文件增长、录屏指示器常亮、耗电），且占用系统录制通道可能导致下一个测试的 `startRecording` 失败。`cockpit_native_tester.dart:101-111` 的 `close()` 只覆盖 `cockpit.native` 路径。
- **修复建议**：`dispose()` 与适配器置换前 best-effort `stopRecording`/`cancelRecordingStart`（失败仅记录）。
- **验证**：widget 测试：录制进行中 dispose root，断言 native 录制收到停止调用。

### [x] D-17 🟡 `CockpitRuntimeStepBuffer` 无上限：每个框架错误追加一条无人排空的步骤记录（fixed in 656a12f）

- **位置**：`packages/flutter_cockpit/lib/src/runtime/cockpit_runtime_step_buffer.dart:46-47`（`_steps.add(...)` 无上限无淘汰）；写入路径 `flutter_cockpit_binding.dart:753-757`（`_recordCriticalRuntimeEvent` 对每个 FlutterError/平台错误/zone 错误调用）；公共 API `FlutterCockpit.recordStep` 写同一缓冲；只有 `reassemble()`/热重启清空。
- **问题**：调试应用反复抛错（如每帧 RenderFlex overflow）且无远端会话排空（`drainRecordedSteps` 仅被端点拉取）时，缓冲随应用生命周期无限增长——对照事件环形缓冲本身有 `maxRetainedEvents` 上限。
- **修复建议**：为缓冲加上限与丢弃计数（对齐 observer ring），溢出时保新弃旧并记录 dropped 数。
- **验证**：单测连续注入超过上限的错误事件，断言缓冲长度封顶且 dropped 计数正确。

### [x] D-18 🟡 `runWithDiagnosticsZone` 吞掉全部未捕获错误，不再走平台默认错误路径（fixed in 656a12f）

- **位置**：`packages/flutter_cockpit/lib/src/runtime/cockpit_flutter_runtime_observer.dart:49-72`（`runZonedGuarded` 处理器只 `recordUnhandledError` + `onError?.call`）；`FlutterCockpit.runApp`（`packages/flutter_cockpit/lib/flutter_cockpit.dart:57-73`）把整个应用装进该 zone。
- **问题**：`runZonedGuarded` 的处理器消费了错误：它不会到达 `PlatformDispatcher.instance.onError`，默认未捕获错误路径（控制台 "Unhandled exception" 输出/崩溃上报）消失——应用的致命异步错误只存在于 Cockpit 的 120 条环形记录里。同文件的平台错误钩子则明确转发（`_handlePlatformError` 214-217 行），行为自相矛盾。
- **修复建议**：记录后转发（`FlutterError.reportError` 或保存的先前处理器），保持应用既有错误语义。
- **验证**：单测在 zone 内抛异步错误，断言先前的全局错误处理器仍被调用。

### [x] D-19 🟡 `updateConfiguration` 置换正在采集的性能收集器：进行中的 `profile()` 被销毁且后续 stop 抛 StateError（fixed in 656a12f）

- **位置**：`packages/flutter_cockpit/lib/src/runtime/flutter_cockpit_binding.dart:316-321`（`performanceCollector.dispose()` 不检查 `isRunning`）；`CockpitTester.profile()` 在 `packages/flutter_cockpit_test/lib/src/cockpit_test.dart:1079` 捕获 collector 引用，成功路径 1326 行附近无守卫调用 `collector.stop(...)`（`cockpit_performance_collector.dart:199-201` 对未运行 stop 抛 `StateError`）。
- **问题**：采集中途更新配置（`FlutterCockpitApp.didUpdateWidget` 换 config、宿主重新 `initialize`）会 detach 收集器并清空 `_frames`，profile 的采集整体丢失，随后 `stop` 的 StateError 还会掩盖原始原因。
- **修复建议**：当前收集器 `isRunning` 时跳过/延迟置换（或先走正常报告路径停止再换）。
- **验证**：单测在 profile 进行中调用 `updateConfiguration` 换收集器，断言采集正常完成（或被显式报告终止）而非 StateError。

### [x] D-20 🔵 macOS 原生语义通道只有 `enable()` 没有 `disable()`：root 卸载后系统 AX 通路保持开启（fixed in 656a12f）

- **位置**：`packages/flutter_cockpit/lib/src/runtime/flutter_cockpit_root.dart:684-687`（`await _nativeSemantics.enable();`）；实现 `packages/flutter_cockpit/lib/src/runtime/cockpit_native_semantics.dart:13`（仅 `enable()`）；root `dispose()`（467-480 行）只释放框架侧 `_semanticsHandle`。
- **问题**：cockpit root 卸载或 `FlutterCockpit.dispose()`（macOS 上每个测试 teardown 都会执行）后，通道开启的原生 macOS accessibility 路径对进程余生保持开启——性能开销 + 跨测试泄漏语义状态。
- **修复建议**：`CockpitNativeSemantics` 增加 `disable()` 通道调用并在 root `dispose()` 中调用。
- **验证**：widget 测试 dispose root 后断言 disable 通道被调用。

### [x] D-21 🔵 会话控制器关闭后 `FlutterCockpit.recordStep` / `CockpitTester.execute` 抛裸 StateError（fixed in 656a12f）

- **位置**：`packages/flutter_cockpit/lib/src/runtime/flutter_cockpit.dart:140-141`（`binding.sessionController.recordStep(...)` 无守卫）；`packages/flutter_cockpit_test/lib/src/cockpit_test.dart:1460-1463`（`recordCommandResult` 同样）。绑定自己已知此隐患并在运行时事件路径捕获（`flutter_cockpit_binding.dart:758-766` 注释 "Runtime observation must never crash the app after a session has closed"）。
- **问题**：宿主关闭 session controller 后，迟到的运行时步骤或在途命令完成会从无关异步路径抛 `StateError('Cockpit session is already closed.')`，替换掉测试 API 已存入 `_results` 的命令结果。
- **修复建议**：两个调用点按 `_recordCriticalRuntimeEvent` 的方式捕获该 StateError（记诊断不抛出）。
- **验证**：单测关闭 controller 后调用 recordStep/execute 收尾路径，断言不抛错且结果保留。

### [x] D-22 🟡 `hotkey` 清理循环无逐键隔离：第一个 key-up 抛错后其余修饰键永久按下（fixed in 656a12f）

- **位置**：`packages/flutter_cockpit_test/lib/src/cockpit_test.dart:1733-1745`（finally 中顺序 `await _keyEvent(sendKeyUpEvent, ...)` 无 per-key try/catch）。
- **问题**：settle pump 中的 widget 构建错误或基础设施失败使第一个 key-up 抛错时，`pressed` 中其余修饰键永不释放——同测试后续所有交互都带着按住的 Ctrl/Shift（且清理错误掩盖原始错误）。
- **修复建议**：每个 key-up 独立 try/catch，记录失败但继续释放其余键。
- **验证**：单测注入第一个 key-up 抛错，断言其余键仍被释放、原始错误不被掩盖。

### D-23 🔵 帧预算在收集器构造时一次性采样：变频屏/多窗口下 jank 分类失真

- **位置**：`packages/flutter_cockpit/lib/src/performance/cockpit_performance_collector.dart:41`（`_frameBudgetUs = frameBudgetUs ?? _defaultFrameBudgetUs()`，构造时固化）与 407-418 行（`_defaultFrameBudgetUs` 读 `implicitView.display.refreshRate`）。
- **问题**：ProMotion/变频屏或窗口跨 60↔120Hz 显示器移动时，后续所有采集按陈旧预算分类——120Hz 采集按 60Hz 预算会报告约 2 倍 jank。多窗口应用中 `addTimingsCallback` 汇总所有视图的帧，却只用 implicit view 的预算。
- **修复建议**：每次 `start()`（或每份报告）从活跃视图的 display 重新解析预算。
- **验证**：单测模拟刷新率变化后 start 新采集，断言采用新预算。

---

## E. packages/cockpit_protocol 与 packages/flutter_cockpit_test — 协议与测试 API

### E-1 🟡 枚举解码普遍用 `values.byName`：跨版本数据抛 `ArgumentError` 而非协议错误，且整个响应解码崩溃

- **位置**：模式遍布 `packages/cockpit_protocol/lib/src`，代表文件：`model/cockpit_task_status.dart:6-8`、`control/cockpit_command_status.dart:5-7`、`runtime/cockpit_plane_kind.dart:7-9`、`model/cockpit_observation.dart:16-18`、`control/cockpit_command_type.dart:44`、`network/cockpit_network_entry.dart:114-117` 等 20+ 处（`grep -rn "values.byName" packages/cockpit_protocol/lib` 可全量列出）。受影响解码链如 `remote/cockpit_remote_command_response.dart:96-101`（设备端新版本发回新枚举值）与 `model/cockpit_run_manifest.dart:139`（持久化 manifest）。
- **现状代码**：
  ```dart
  static CockpitTaskStatus fromJson(Object? value) {
    return CockpitTaskStatus.values.byName(value! as String);
  }
  ```
- **问题**：未知枚举值抛 `ArgumentError`、缺失字段抛空检查 `TypeError`——都不是协议层能捕获的 `FormatException`/`CockpitApiException`，错误处理无法按协议错误分类；对照 test 文档侧已用 `CockpitTestValueReader.enumeration`（`test/cockpit_test_value_reader.dart:136-151`）正确实现。
- **修复建议**：为协议包提供统一的枚举解析 helper（抛 `FormatException` 带路径），逐文件替换 `values.byName` 写法；对确实可扩展的枚举走 `CockpitEnumValue` 协商策略。
- **验证**：单测对每个替换点喂未知值/缺失值，断言抛 `FormatException` 且消息含字段路径。

### [x] E-2 🟡 模板字面量含 `${` 时无法往返：literal 序列化后被静默重解释为 stringTemplate（fixed in 656a12f）

- **位置**：`packages/cockpit_protocol/lib/src/test/cockpit_test_value.dart:41-74`（`toJson` 对 literal 输出原始字符串；`fromJson` 对包含 `${` 的字符串一律按 `stringTemplate` 解析）；`_validateLiteral`（`cockpit_test_value_reader.dart:50-68`）不限制 `${`。
- **现状代码**：
  ```dart
  if (expectedType == CockpitTestValueType.string &&
      value is String &&
      value.contains(r'${')) {
    return CockpitTestTemplateValue.stringTemplate(value);
  }
  ```
- **问题**：程序化构造 literal `'Total: ${amount}'` 合法且 `toJson` 原样输出，但重新解码变成 stringTemplate，随后 `CockpitTestAction.fromJson` 报 `Unbound action value`（`cockpit_test_action.dart:259-263`）。schema 等价性测试（`cockpit_test_schema_parity_test.dart:119-123`）因再次序列化输出相同字符串而无法发现。
- **修复建议**：在 `_validateLiteral` 中拒绝字符串 literal 包含 `${`（强制显式使用 stringTemplate），使线格式无歧义。
- **验证**：单测断言构造含 `${` 的 literal 抛 `FormatException`；现有 literal/template 用例全绿。

### [x] E-3 🟡 能力/操作描述符的多数枚举字段硬编码 `CockpitDecodePolicy.requests`，无视协商出的 decodePolicy（fixed in 656a12f）

- **位置**：`packages/cockpit_protocol/lib/src/foundation/cockpit_capabilities.dart:65-70`（`scope` 解析）；`cockpit_operation_descriptor.dart:224-231`（`_enum` 用于 scope/mutationClass/idempotency/executionMode）。对照同文件 198-206 行 `safetyEffects` 正确使用 `policy: decodePolicy, extensibleResponse: true`（`foundation_protocol_test.dart:565-583` 断言了该行为）。
- **现状代码**：
  ```dart
  T _enum<T extends Enum>(Object? value, List<T> values, String path) {
    return CockpitEnumValue<T>.parse(
      value, values, path,
      policy: CockpitDecodePolicy.requests,
    ).requireKnown();
  ```
- **问题**：客户端即使协商了 `foundation.response.extensibleEnums`，新版本 server 的能力文档带一个新 scope/mutationClass 值时仍抛硬 `FormatException`，功能门控形同虚设。
- **修复建议**：`_enum` 与 resource `scope` 解析改为透传调用方的 `decodePolicy`（响应侧配 `extensibleResponse: true`），与 `safetyEffects` 对齐。
- **验证**：单测用协商策略解码含未知 scope 的描述符，断言按可扩展枚举处理而非抛错。

### E-4 🟡 `cockpit.debug` 惰性初始化：teardown 才首次访问时把已污染的全局当作「初始值」恢复

- **位置**：`packages/flutter_cockpit_test/lib/src/cockpit_test.dart:346`（`late final CockpitDebugTools debug = CockpitDebugTools();`）；teardown 调用点 126 行 `cockpit.debug.restore()`；`CockpitDebugTools` 构造函数捕获 `_initial = _readCurrent()`（`cockpit_debug_tools.dart:55` 附近）。
- **问题**：测试体直接改 Flutter 进程级开关（如 `debugPaintSizeEnabled = true`、`timeDilation`）而不经过 `cockpit.debug` 时，首次访问发生在 teardown 的 `restore()`——它把污染态快照为初始值并「恢复」到污染值，把 overlay/慢动画泄漏给后续测试，恰好违背该类的文档承诺。
- **修复建议**：在 `CockpitTester._` 构造函数中立即构造 `CockpitDebugTools()`（与 `native` 的处理一致），去掉 `late final`。
- **验证**：两个连续测试：第一个直接改 `timeDilation`，断言第二个测试开始时全局开关已恢复默认。

### E-5 🟡 `watch()` 用墙钟超时对比逻辑泵时长，且允许 `timeout == duration`：默认参数下必然提前超时

- **位置**：`packages/flutter_cockpit_test/lib/src/cockpit_test.dart:2469-2475`（校验 `effectiveTimeout < duration` 才拒绝，允许相等）；循环 2496-2527 行（进度用 `logicalElapsed` 泵进时间，预算用 `wallClock` 真实时间，且每次采样做 `root.snapshot()` + 两次 `jsonEncode`）。默认 `effectiveTimeout = options.commandTimeout`（10s，`cockpit_test_options.dart:5,33`）。
- **问题**：`watch(duration: 10s)` 通过校验（10 ≥ 10），但真实设备上快照+编码开销使墙钟先到 10s，`endedBy: 'timeout'` 静默截断数据，断言 `samples`/`elapsed` 的用例间歇性失败。
- **修复建议**：要求 `effectiveTimeout > duration` 并留出采样开销余量（如 `duration + 2×interval` 起步），或超时也按逻辑时钟计量；文档注明两者时钟差异。
- **验证**：单测 `watch(duration: timeout)` 在慢环境（注入慢 snapshot）下断言以 `duration` 正常结束或校验阶段直接拒绝参数。

### E-6 🔵 `CockpitTestStepTemplate.timeoutMs` 构造器与解码器边界漂移：构造合法、再解码失败

- **位置**：`packages/cockpit_protocol/lib/src/test/cockpit_test_step.dart:25-27`（构造器只查 `> 0`）；解码器 147-154 行强制 `1..3600000`。
- **问题**：程序化构造 `timeoutMs: 7200000` 的步骤可正常构建与序列化，但其 `toJson()` 产物无法重新解码（`FormatException`），往返不对称。
- **修复建议**：构造器同步强制 `1..3600000`（与 schema `maximum` 一致）；对同类构造/解码边界漂移做一次排查（可参考 H-3 的属性测试）。
- **验证**：单测断言构造越界值抛 `FormatException`；往返测试通过。

### E-7 🔵 multiTouch 步数上限在两个创作面不一致（文档 32 vs Dart API 10000），校验强度也不同

- **位置**：`packages/cockpit_protocol/lib/src/test/cockpit_test_action.dart:678-683`（文档解码限 1..32）；`packages/flutter_cockpit_test/lib/src/cockpit_test.dart:2805-2811`（Dart 门面允许 ≤10000）。
- **问题**：经 `cockpit.multiTouch` 创作的 50 步序列无法表达为 `cockpit.test/v2` 文档；反向地，文档序列还缺少门面侧的相位顺序校验（`_validateMultiTouch`，2828-2862 行，要求 down 先于 move）。
- **修复建议**：统一为同一上限，并把相位顺序校验抽为共享函数供两侧使用。
- **验证**：单测两侧各自构造越界与乱序序列，断言一致拒绝。

### E-8 🔵 `CockpitTestValueReader.jsonValue` 无深度/节点上限的递归：深嵌套扩展值触发 `StackOverflowError`

- **位置**：`packages/cockpit_protocol/lib/src/test/cockpit_test_value_reader.dart:153-184`（直接递归）；对照 foundation 侧已加固的迭代实现与上限（`cockpit_foundation_value_reader.dart:239-254`、`cockpit_foundation_constraints.dart:3-5`，深度 64 + 节点上限 + 环检测）。`keys(..., allowExtensions: true)`（43 行附近）同样逐值调用。
- **问题**：`jsonDecode` 本身非递归不会挂，但随后 `jsonValue` 冻结深嵌套 `x-` 扩展值时递归溢出，进程直接崩（`StackOverflowError` 不可捕获），而非 `FormatException`。
- **修复建议**：复用 foundation 的有界迭代冻结逻辑（深度/节点上限、报带路径的 `FormatException`）。
- **验证**：单测构造 10 万层嵌套的扩展值，断言得到 `FormatException` 而非崩溃。

### E-9 🔵 `CockpitRemoteBridgeResponse.bytesBase64` 只查类型不查内容：坏 Base64 在远离解码点的 getter 才炸

- **位置**：`packages/cockpit_protocol/lib/src/remote/cockpit_remote_bridge_message.dart:126-130`（`fromJson` 仅校验是 String）；惰性解码在 82-83 行（`binaryBody => base64Decode(bytesBase64!)`）。
- **修复建议**：`fromJson` 内完成 base64 校验/解码（或至少验证可解码），让坏线数据在边界处以带路径的 `FormatException` 失败。
- **验证**：单测喂非法 base64，断言 `fromJson` 直接抛 `FormatException`。

### [x] E-10 🟡 `CockpitLocator.fromJson` 静默截断小数 index 并接受负值：选错目标而无任何报错（fixed in 656a12f）

- **位置**：`packages/cockpit_protocol/lib/src/control/cockpit_locator.dart:393`；请求侧入口 `packages/flutter_cockpit/lib/src/executor/in_app_cockpit_command_executor.dart:6536`。
- **现状代码**：
  ```dart
  index: (json['index'] as num?)?.toInt(),
  ```
- **问题**：`{"text":"Row","index":1.9}` 被静默截断为 1（点第 2 个匹配，无错误），`{"index":-3}` 也被接受。包内其他数值解码全部拒绝非整数（`CockpitFoundationValueReader.integer` 要求 `is int`），这是唯一的静默截断点，且直接决定动作落在哪个目标上。
- **修复建议**：要求 `json['index'] is int`（拒绝 double），构造器校验 `index >= 0`。
- **验证**：单测喂 1.9/-3，断言抛 `FormatException`；整数路径不变。

### E-11 🟡 网络条目等 DTO 用 `DateTime.parse(...).toUtc()` 接受无时区偏移的本地时间：产物随宿主时区漂移

- **位置**：`packages/cockpit_protocol/lib/src/network/cockpit_network_entry.dart:112,120-122`、`network/cockpit_web_socket_activity.dart:49`、`model/cockpit_step_record.dart:143`、`model/cockpit_run_manifest.dart:140,143`。对照严格实现 `cockpit_foundation_value_reader.dart:189-196`（要求 `endsWith('Z') && isUtc`）。
- **现状代码**：
  ```dart
  startedAt: DateTime.parse(json['startedAt']! as String).toUtc(),
  ```
- **问题**：`"2026-09-09T10:00:00"`（无偏移；手写 fixture、回放日志或非 Dart 生产者）被解释为**本地时间**再转 UTC——同一产物在不同时区宿主上解码为不同时刻，重新编码后墙钟时间改变。
- **修复建议**：这些字段改走严格 UTC reader（拒绝无显式 `Z`/偏移的字符串）。
- **验证**：单测喂无偏移时间串，断言抛 `FormatException`；带 `Z` 的路径不变。

### E-12 🟡 时长/字节字段用 `as int` 强转：十进制 JSON 数值抛 TypeError 而非 FormatException，且无下界校验

- **位置**：`packages/cockpit_protocol/lib/src/control/cockpit_command_result.dart:91`（`durationMs: json['durationMs']! as int`）等；同类 `network/cockpit_network_entry.dart:113,134-135`、`network/cockpit_web_socket_activity.dart:44,50,117-120`、`network/cockpit_network_endpoint_summary.dart:41-45`。
- **问题**：`{"durationMs":1e3}` 在 VM 上解码为 double `1000.0`，`as int` 抛 `TypeError`——只捕获 `FormatException` 的解码错误处理（如 `cockpit_remote_session_client.dart:790` 的模式）接不住，坏输入变成未分类崩溃而非 400/解码错误。另外 `-9`、`-1` 等负值畅通（这些 DTO 无 min 校验）。
- **修复建议**：换成有界 reader（`integer(value, path, min: 0)`）或共享的抛 `FormatException` 的整型转换 helper。
- **验证**：单测喂 `1e3`/`-9`，断言抛 `FormatException` 带路径。

### E-13 🔵 选择器 `format` 无 maxLength 校验而 `parse` 有：顾问可产出无法回放的 sel

- **位置**：`packages/cockpit_protocol/lib/src/control/cockpit_selector.dart:36-38`（parse 检查 `maxLength`）对比 98-103 行（format 无检查）；消费方 `packages/cockpit/lib/src/application/cockpit_ui_locator_advisor.dart:487`（把任意活树 locator 格式化进给代理的 `sel` 建议）。
- **问题**：文本超长（>~4096 字符）的目标经 `format()` 产出超长选择器，代理拿它执行 `dev tap <sel>` 时 parse 直接抛 `Selector is too long.`
- **修复建议**：`format()` 同样执行 maxLength（截断加显式标记或直接失败），保证产出的 sel 永远可回放。
- **验证**：单测构造超长文本 locator，断言 format 的产物能被 parse 接受或明确失败。

### E-14 🔵 活目标 ref 大小写不对称：`parse` 小写化而 `format` 原样输出，往返后 locator 不相等

- **位置**：`packages/cockpit_protocol/lib/src/control/cockpit_selector.dart:77`（format `':${locator.ref}'` 原样）对比 247 行（parse `toLowerCase()`）；公共构造器不校验 ref 字符集/大小写。
- **问题**：`CockpitLocator(ref: 'AB12CD')` 经 format→parse 变成 `'ab12cd'`，`parse(format(L)) != L` 破坏以相等为键的去重/缓存。生成的 ref 本是小写 base-36，但无强制。
- **修复建议**：`CockpitLocator` 构造器校验 ref 为小写字母数字（或 format 时小写化），两个方向一致。
- **验证**：单测大写 ref 往返，断言相等。

### E-15 🔵 网络体脱敏对 JSON 重编码：数字词形/重复键被静默规范化，证据预览不再忠实于线上字节

- **位置**：`packages/cockpit_protocol/lib/src/network/cockpit_network_redactor.dart:98-99`。
- **现状代码**：
  ```dart
  try {
    return jsonEncode(_value(jsonDecode(value), depth: 0));
  } on FormatException {
  ```
- **问题**：`{"a":1e3,"b":9223372036854775808,"c":1,"c":2}` 的预览变为 `{"a":1000.0,"b":9223372036854776000,"c":2}`——除脱敏外，指数形式整数变 `.0` double、超 int64 丢精度、重复键后者胜。对 body 内容做断言的代理看到的数字与服务器实际发送的不同。
- **修复建议**：对 JSON 体在字节忠实度重要时仅做文本层脱敏（`text()` 通路），或用保留词形的解析通道处理。
- **验证**：单测上述输入，断言预览保留原始数字词形（仅敏感值被掩码）。

### E-16 🟡 手动性能窗口继承 10s 命令超时，且失败在 teardown 被静默吞掉：核心场景零报告但测试仍绿

- **位置**：`packages/flutter_cockpit_test/lib/src/cockpit_test.dart:534-546`（manual window 实现为 `profile(() => finished.future, ...)`）、1071 行（`timeout ?? options.commandTimeout`，默认 10s，`cockpit_test_options.dart:5,33`）、585-597 行（`_closeManualPerformanceCaptures` 吞掉全部异常；579-584 行的 onError 也只丢弃）。
- **问题**：API 明确设计为「稍后关闭」的手动窗口，整个窗口时长被 10s 命令超时封顶——超过即被 `TimeoutException` 强制掐断；若测试体随后正常结束，teardown 吞掉超时、失败的 reportFuture 无人消费，测试绿灯收场但性能报告数为 0：该功能核心用例的静默数据丢失。
- **修复建议**：手动窗口默认采用大得多的上限（如原生集成测试超时或不封顶+空闲超时）；teardown 时若手动窗口从未产出报告，输出显式诊断。
- **验证**：单测开一个超过 commandTimeout 的手动窗口后正常结束，断言窗口完整产出报告或测试带明确诊断失败。

---

## F. cockpit_console、cockpit_demo 与工程配置

### F-1 🟡 原生插件一致性测试与配套校验脚本从未在 CI 运行（孤儿资产）

- **位置**：测试 `examples/cockpit_demo/cockpit/integration_test/native_plugin_conformance_test.dart`（整个 `'public native plugin conformance'` 测试）；校验脚本 `.github/scripts/validate-native-conformance-report.py:21-31`（断言 report.status/platform 等）。`.github/workflows/example-e2e.yml` 只运行 `cockpit_facade_test.dart`、`performance_profile_test.dart`、`performance_plugin_modes_test.dart`（180-202、746-777 行附近）；`grep -rn "native_plugin_conformance\|validate-native-conformance" .github/` 无任何匹配。
- **问题**：唯一按平台快照原生截屏/录制能力的测试，以及为 gate 其报告而写的 58 行校验器，都是孤儿——要么真实覆盖率静默丢失，要么这两个文件会持续腐化。
- **修复建议**：在 example-e2e 工作流的 android/ios 回归 job 中增加 `flutter drive --driver=integration_test/driver.dart --target=integration_test/native_plugin_conformance_test.dart` 步骤并把报告管道接到现有 python 校验器；若确认放弃则删除两个文件。
- **验证**：CI 上该步骤执行且校验器通过；本地可用 `cockpit dev start` + `flutter drive` 复现。

### F-2 🟡 Cockpit Console 自身的 E2E 回归套件从未被任何工作流执行

- **位置**：`packages/cockpit_console/cockpit/e2e/suites/console_regression.suite.yaml`（自述 "Release smoke coverage for Flutter and non-invasive native Console control."）及其 cases；`.github/workflows/cockpit-console-release.yml:57-63` 的 "Validate Console release" job 只跑 `flutter analyze` 与 `flutter test`，无任何对 `console_regression` 的引用。
- **问题**：自述为发布冒烟覆盖的套件从未运行，Console 的 UI 回归只能靠 widget 单测兜底，fixture 也会无人验证地漂移。
- **修复建议**：在 console 发布工作流（或 CI 工作流）中构建 console 后执行 `dart run cockpit suite run --file cockpit/e2e/suites/console_regression.suite.yaml`；或删除该套件。
- **验证**：CI 步骤存在且套件达到终态 pass。

### F-3 🔵 console 携带死代码响应缓存层与两个仅为它存在的依赖

- **位置**：`packages/cockpit_console/lib/src/providers/response_cache.dart:18,131`（`ConsoleCache`/`consoleCacheProvider`）；`packages/cockpit_console/pubspec.yaml:27-28`（`kache: ^2.0.0`、`kache_hive_ce: ^2.0.0`）；过期文档声明 `packages/cockpit_console/lib/cockpit_console.dart:6`（"and kache_hive_ce for API response caching"）。
- **问题**：`grep -rn "consoleCacheProvider\|ConsoleCache\|watchJson\|watchMemory" packages/cockpit_console/lib` 仅命中 `response_cache.dart` 自身与其导出——所有数据 provider 都直接经 `ensureClient()` 拉取（`data_providers.dart`）。约 135 行未用持久化代码 + 两个无谓的 pub 依赖还被导出为公共 API。
- **修复建议**：要么把缓存接入列表 provider（如果本就计划做），要么删除 `response_cache.dart`、其导出、文档声明与两个依赖。
- **验证**：`flutter pub get` 后 `flutter analyze` 通过；如删除，`grep kache` 无残留。

### F-4 🔵 console 四组持久化偏好键是死代码（无任何读写方，仅测试在用）

- **位置**：`packages/cockpit_console/lib/src/providers/preferences_store.dart`——`sidebarCollapsed`（145-151）、`recentDocuments`/`addRecentDocument`（154-166）、`fontScale`/`setFontScale`（169-175）、`chatHistory`/`addChatMessage`/`clearChatHistory`（203-226，含"保留最近 100 条"逻辑）。全 `lib/` 检索这四个键名只命中 store 自身与 `packages/cockpit_console/test/preferences_store_test.dart`；应用实际使用的键是 themeMode、localeMode、selectedWorkspaceId、lastAgentId、lastSessionCwd、customAgentExecutable、customAgentArgs（`cockpit_console_app.dart`、`ai_chat_screen.dart`）。
- **修复建议**：删除未用键/ setter 及其测试；或若本就是计划功能（聊天历史上限暗示如此），接入侧栏/编辑器/聊天 UI（可并入 G-2 功能建议一起做）。
- **验证**：删除后 analyze/test 通过；保留则 UI 中可观察到对应行为。

### F-5 🔵 console（Flutter 桌面应用）误用纯 Dart lints，`flutter_lints` 依赖形同虚设

- **位置**：`packages/cockpit_console/analysis_options.yaml:10`（`include: ../../analysis_options.yaml` → 根 `analysis_options.yaml:1` 的 `include: package:lints/recommended.yaml`）；未生效依赖 `packages/cockpit_console/pubspec.yaml:37`（`flutter_lints: ^6.0.0`）。对照 `examples/cockpit_demo/analysis_options.yaml` 正确使用 `include: package:flutter_lints/flutter.yaml`。
- **问题**：console 错过全部 Flutter 专项推荐规则（如 `sized_box_for_whitespace` 家族），CI 的 analyze 门对这个包弱于 demo 应用；声明的 dev 依赖不起作用。
- **修复建议**：console 的 `analysis_options.yaml` 改为 `include: package:flutter_lints/flutter.yaml`（保留本地 exclude 与规则覆盖），随后修复新暴露的告警。
- **验证**：`cd packages/cockpit_console && flutter analyze` 无告警。

### F-6 🟡 README 快速入门的 `cockpit target register` 缺少必填的 `--idempotency-key`：照文档执行必然在步骤 4 失败

- **位置**：`README.md:144-145` 与 `README.zh-CN.md:130-131`（示例无 idempotency-key）；代码 `packages/cockpit/lib/src/cli/commands/resource_commands.dart:491`（`..addOption('idempotency-key', mandatory: true)`）。仓库内 skill 参考文档已是正确形式（`.agents/skills/cockpit/references/environments.md:240-249`）。
- **问题**：该选项已改为必填（幂等变更需要重放键），但 README 入门块未同步。按文档执行在步骤 4 抛 `UsageException`（exit 64），整个 "Cases, suites, and API" 快速入门在 `case run` 之前就断掉。
- **修复建议**：两个 README 的 `target register` 示例补上 `--idempotency-key <key>`。
- **验证**：照 README 命令序列逐条执行到 `case run` 成功。

### F-7 🟡 CI 格式化门禁漏掉根目录 `tool/`，且漂移已实际发生（`tool/install_cockpit.dart` 当前未格式化）

- **位置**：`.github/workflows/example-e2e.yml:36-41`（`dart format ... packages/... examples/cockpit_demo test` 路径列表不含 `tool`）。已实证：`dart format --output=none --set-exit-if-changed tool` 输出 `Changed tool/install_cockpit.dart`（Dart 3.13 formatter）。
- **问题**：嵌套包内的 tool/ 会被递归覆盖，但根 `tool/` 不在任何路径列表中——文件今天就是未格式化状态，而门禁永远发现不了。
- **修复建议**：格式命令路径加入 `tool` 并执行一次 `dart format tool`（AGENTS.md 的本地检查命令同样建议补上）。
- **验证**：`dart format --output=none --set-exit-if-changed tool` 退出码 0。

### F-8 🟡 demo 到期日 chip 用 `Duration.inDays` 判定「今天」：每天 17:00 后 chip 错选，E2E 断言出现按墙钟的日周期 flake

- **位置**：`examples/cockpit_demo/lib/src/ui/screens/task_editor_screen.dart:87-88`（preset 锚定 `今天/明天 17:00`）与 316-321、329-335 行（chip 用 `_dueAt!.difference(DateTime.now()).inDays == 0/1` 判定选中）；同型逻辑在 `task_detail_screen.dart:329-340, 467-487`。chip 带 Semantics 标识（`task-editor-due-today`），是 E2E fixture 断言点。
- **问题**：`inDays` 截断整 24h 窗口而非日历日。本地 17:00 后，「明天 17:00」距今不足 24h → `inDays == 0`，锚定明天的 preset 反而点亮「Today」chip；17:00 到午夜之间「Tomorrow」chip（`inDays == 1`）对自己的 preset 永远点不亮。断言 chip 状态的测试每天在固定时间窗内必挂。
- **修复建议**：按日历日比较（比较 year/month/day，或先把时间部分清零再差值）。
- **验证**：单测在 18:00 与 10:00 两个模拟时刻构造 preset，断言选中状态一致正确。

### F-9 🟡 demo `runSyncNow` 无在途守卫且 `syncing` 状态发布过晚：双击/与自动同步并发会互相覆写结果

- **位置**：`examples/cockpit_demo/lib/src/app/todo_app_service.dart:649-679`（`syncing` 在首个 `await fetchTasks` 之后才写入）；按钮禁用条件 `settings_screen.dart:382-388` 依赖该状态。
- **问题**：fetch 与状态发布之间的窗口内双击（或与自动同步过程重叠）会并发启动两个 `TodoSyncMachine` 推同一批待同步任务；第二个实例基于陈旧 `queuedById` 快照的结果写会覆写第一个，产生互相矛盾的任务同步状态。
- **修复建议**：方法入口同步设置在途标志（或立即发布 `syncing`），已在途则直接返回。
- **验证**：单测并发调用两次 `runSyncNow`，断言只跑一个同步机。

### F-10 🟡 demo `TodoLoopbackSyncGateway._ensureServer` TOCTOU：并发首次调用泄漏一个已绑定的 HttpServer

- **位置**：`examples/cockpit_demo/lib/src/network/todo_sync_gateway.dart:166-177`（检查 `_baseUri` 后 await bind 再赋值）；`close()`（157-164 行）只关最后一个。
- **问题**：启动健康探测在途时用户再点设置页健康检查，两个调用都观察到 null、都 bind，第二次赋值覆盖 `_server`/`_subscription`——第一个 server 永久监听（端口泄漏、事件循环无法退出、请求由无人能关闭的网关处理）。
- **修复建议**：记忆化在途 future（`_serverFuture ??= _bind()`）而非检查已完成结果。
- **验证**：单测并发调用两次 ensureServer，断言只 bind 一次、close 后端口全部释放。

### F-11 🔵 demo 冲突解决屏 `_resolve` 无错误处理：一次失败后 `_isResolving` 永久为 true，三个解决按钮全部禁用

- **位置**：`examples/cockpit_demo/lib/src/ui/screens/sync_conflict_screen.dart:28-36`（两个 await 无 try/finally；按钮在 113-131 行由 `_isResolving` 门控）。
- **修复建议**：try/finally 复位 `_isResolving` 并以 SnackBar 呈现错误。
- **验证**：单测让 `resolveConflict` 抛错，断言按钮仍可用且错误可见。

### F-12 🔵 demo `_isDueToday` 用 UTC 日历字段对比本地 `DateTime.now()`：跨时区跑 CI 时「今天」桶错位

- **位置**：`examples/cockpit_demo/lib/src/ui/screens/todo_collection_screen.dart:1195-1204`（`task.dueAt` 为 UTC，`now` 为本地）；同一 UTC/本地错配还进入 cockpit 探测负载 `cockpit_demo_app.dart:214-220`（`dueTodayCount`）。
- **问题**：本地 17:00 跨 UTC 午夜的时区（如 UTC-8）里，UTC 日与本地日不一致，「今天」任务被排除或外来任务被纳入；E2E 观察到的 `dueTodayCount` 随时区变化——CI 与开发者在不同时区时是 flake 源。
- **修复建议**：比较前把 `now` 转 UTC（或 `dueAt` 转本地），两处一致。
- **验证**：单测在 UTC-8 与 UTC+8 两个时区下断言桶划分一致。

### F-13 🔵 console 五个屏的 hook `useState` 在 await 之后无存活检查即写入：导航离开触发 dispose 后断言崩溃

- **位置**：`packages/cockpit_console/lib/src/ui/screens/targets_screen.dart:61-77`（`doDiscover` 的 finally 写 `discovering.value`，`discover()` 带 60s 超时）；同型：`workspaces_screen.dart:374-379`、`:694-699`（`removing.value`，且写在 `context.mounted` 检查之前）、`runs_screen.dart:403-434`（`canceling.value`）、`:607-641`（`downloadingId.value`）。
- **问题**：flutter_hooks 在卸载时 dispose 底层 `ValueNotifier`；操作在途时导航离开，finally 对已 dispose 的 notifier 写值，触发 debug 断言 "A ValueNotifier was used after being disposed"。
- **修复建议**：用 `useEffect` 清理函数记录存活标志（或 `ref.onDispose`），每次 post-await 写入前检查。
- **验证**：widget 测试在 discover 进行中 pop 页面，断言无断言错误。

### F-14 🔵 console workspaces 列表 tile 有状态但无 key：刷新/删除时 `removing`/`expanded` 状态迁移到错误条目

- **位置**：`packages/cockpit_console/lib/src/ui/screens/workspaces_screen.dart:266-269`（roots）与 `:511-514`（workspaces）——`_RootTile`/`_WorkspaceTile` 持有 hook 状态但列表子项无 key，element 按位置匹配；`remove()` 内部会先 `refresh()`。
- **问题**：tile N 的 `removing` 转圈在途时任何刷新/删改使该位置换了条目——转圈出现在错误的 root 上，或 `expanded` 状态在删除兄弟项后跳到别的工作区。
- **修复建议**：按稳定 id 加 key（`ValueKey(root.rootId)` / `ValueKey(workspace.id)`）。
- **验证**：widget 测试在删除进行时插入新条目，断言转圈仍绑定原条目。

### F-15 🔵 console 聊天副标题截断按 UTF-16 码元：第 60 位落在代理对中间时结尾渲染为乱码

- **位置**：`packages/cockpit_console/lib/src/ui/screens/ai_chat_screen.dart:93-94`（`message.substring(0, 60)`）。
- **问题**：`length`/`substring` 按 UTF-16 码元操作；代理错误文本常含 emoji/CJK 扩展字符，截断可能落在代理对中间，产生未配对代理渲染为「�」。
- **修复建议**：用 `characters` 包截断（`message.characters.take(60)`）。
- **验证**：单测构造第 60 码元为高代理项的字符串，断言截断后无未配对代理。

### F-16 🔵 `.cursor/rules/cockpit.mdc` 使用不存在的 `cockpit operation list` 命令（CLI 注册名为 `op`），且不在任何镜像守卫测试范围内

- **位置**：`.cursor/rules/cockpit.mdc:18`（`cockpit operation list --workspace-id <workspaceId>`）；CLI 实际注册 `packages/cockpit/lib/src/cli/commands/resource_commands.dart:373`（`String get name => 'op';`）；其余表面（SKILL.md、`docs/contracts/ai-development-protocol.md:109`）均正确写 `op list`。守卫测试 `test/cockpit_skill_guidance_test.dart` 只覆盖 12 份 `skills/cockpit` 镜像树，不含 `.cursor/rules/*.mdc` 与 `.kiro/steering/*.md`。
- **问题**：遵循该规则的代理得到 "Could not find a command named operation"；这正是镜像守卫盲区导致的漂移实例。
- **修复建议**：改为 `cockpit op list --workspace-id <workspaceId>`；扩展 guidance 测试对 `.cursor/rules`/`.kiro/steering` 中的命令名做 lint。
- **验证**：`cockpit op list` 可执行；扩展后的守卫测试在故意写错命令名时变红。

### F-17 🔵 `skills/cockpit/INSTALL.md` Kiro 段落有编辑残留的重复句，并同步扩散到全部 12 份镜像副本

- **位置**：`skills/cockpit/INSTALL.md:212-213`；同一内容存在于 `.agents`、`.kiro`、`.omp`、`.cline`、`.cursor`、`.claude`、`.opencode`、`.pi` 及三份 `plugins/*/cockpit` 副本。
- **现状代码**：
  ```
  Kiro manages Power MCP servers internally and activates them with the Power;
  Kiro manages Power MCP servers internally. Select or invoke this Power only
  ```
- **问题**："Kiro manages Power MCP servers internally" 连续出现两次，是随镜像同步机制扩散到版本化产品表面的编辑事故。
- **修复建议**：修正 canonical `skills/cockpit/INSTALL.md` 后按镜像测试要求同步全部 12 份副本。
- **验证**：grep 全仓库只剩一处该句子；镜像守卫测试通过。

### F-18 🔵 `docs/agent-integrations.md` 验证清单编号重复（两个 `5.`，缺 `6.`）

- **位置**：`docs/agent-integrations.md:344-346`——第 5 条 "If MCP is configured…" 之后又是一个 `5.`（"Keep app proof proportional…"）。
- **问题**：多数渲染器会静默重排，但源码编号错误，纯文本读取方（代理、doc linter）看到两个步骤 5 而没有 6。
- **修复建议**：最后一条改为 `6.`。
- **验证**：markdown lint/人工核对编号连续。

### F-19 🟡 demo web 数据库资产新鲜度守卫只覆盖两份提交副本中的一份：内层 cockpit shell 的 wasm/worker 可静默漂移

- **位置**：`test/package_metadata_test.dart:758-762`（守卫只硬编码读 `examples/cockpit_demo/web/drift_worker.js.map` 与 `sqlite3.wasm`）；第二份完整副本提交于 `examples/cockpit_demo/cockpit/web/`（`drift_worker.js`、`drift_worker.js.map`、`sqlite3.wasm` 均在 git 内）。
- **问题**：内层开发 shell 副本若由不同 drift/sqlite3 版本重新生成，测试保持全绿而副本静默偏离 `pubspec.lock` 解析。
- **修复建议**：把守卫参数化为对两个目录（`examples/cockpit_demo/web` 与 `examples/cockpit_demo/cockpit/web`）各校验一次。
- **验证**：人为改动内层任一文件的版本标记，断言测试变红。

### F-20 🔵 空的 `third_party/` 目录残留（实际 vendored 代码在被 gitignore 的 `third/`）

- **位置**：`third_party/`（零文件）；真实 vendored 内容在 gitignore 的 `third/`（Maestro/、dart_ai/），仅被 `analysis_options.yaml:6` 的 exclude 引用。
- **问题**：空目录暗示一个并不存在的 vendoring 约定，误导导航。
- **修复建议**：删除空目录（git 不追踪空目录），或把 `third/` 整合进去并同步更新 analysis exclude。
- **验证**：目录消失且 `dart analyze` 不变。

---

## S. 安全与加固（跨包）

### [x] S-1 🔴 应用内远端会话端点完全无鉴权，且 Cockpit 在 Android/iOS 上将其绑定到 `0.0.0.0`（无线 iOS 绑定 `::`）（fixed in 656a12f）

- **位置**：
  - 服务端：`packages/flutter_cockpit/lib/src/remote/cockpit_remote_session_server.dart:53-56`（`HttpServer.bind(_configuration.host, ...)`）、76-94 行（`_handleRequest` 直接分发，无 token/Origin/Host 校验——`grep -rn "token\|auth\|Origin" packages/flutter_cockpit/lib/src/remote/` 零命中）。
  - 绑定策略：`packages/cockpit/lib/src/session/cockpit_remote_session_launcher.dart:115-122`（`cockpitRemoteBindHostForPlatform`：android/ios → `'0.0.0.0'`）。
  - 无线 iOS：`packages/cockpit/lib/src/development/cockpit_development_session_machine_launcher.dart:398-413`（隧道可达时 `bindHost: '::'`，`publicHost: tunnelIpAddress`）。
- **现状代码**：
  ```dart
  String cockpitRemoteBindHostForPlatform(String platform) {
    return switch (platform) {
      'android' => '0.0.0.0',
      'ios' => '0.0.0.0',
      ...
  ```
- **问题**：`POST /commands/execute` 可下发任意命令（tap/enterText/copyText/pasteText 等，见 `cockpit_command_type.dart:2-9`），`/snapshot` 暴露全部 UI 文本与网络记录。Android 应用共享设备网络命名空间——**同一手机上的任意其他应用**都可驱动被测应用、读取其界面内容；无线 iOS 场景端点经隧道 IP 从局域网可达；即便桌面回环场景，恶意网页可用无预检的 `text/plain` POST（简单请求）打默认端口，配合 DNS rebinding 读取响应。对照 Supervisor 守护进程的完整防护（loopback+Origin 拒绝+bearer token，`cockpit_daemon_host.dart:179-195`），该端点一样都没有。
- **修复建议**：启动器生成一次性随机 token（查询参数或请求头），服务端每个路由校验；校验 `Host`/`Origin`；默认仍绑回环，非回环绑定（Android/iOS 设备网络场景）必须由 token 保护；文档写明残留风险与关闭方式。
- **验证**：集成测试：无 token/错 token 的请求全部 401；带 token 正常；Origin 不匹配被拒。

### [x] S-2 🔴 桥接服务器 `/connect` WebSocket 无 Origin/token 校验：任意网页可劫持成为「应用」对端（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/bridge/cockpit_web_remote_session_bridge_server.dart:102-107`（升级判定）与 131-137 行（`_handleConnect` 直接 `WebSocketTransformer.upgrade(request)`，无任何校验）；连接表 52 行 `_connections` 无上限；客户端侧 `packages/flutter_cockpit/lib/src/remote/cockpit_remote_session_bridge_client.dart:119-129` 用无 token 的 `ws://host/connect`。
- **问题**：浏览器会为 WS 握手附带 `Origin`，但此处不校验——用户浏览器中的任意网页都能连上 `ws://127.0.0.1:<bridgePort>/connect` 成为「应用」对端：接收每个转发请求（方法/路径/JSON 体），以任意 `CockpitRemoteBridgeResponse` 应答（伪造快照/断言结果、外泄命令负载），并控制回给 HTTP 客户端的 `contentType`（466 行 `_endpointResponseFromBridgeResponse`）。连接无上限也允许资源耗尽。端口写入 handle JSON/日志，易被扫描。
- **修复建议**：connect URL 携带启动期 token（或首条消息鉴权），拒绝 Origin/token 不匹配的升级；限制并发连接数。
- **验证**：集成测试：无 token 升级被拒；有效 token 连通；超过连接上限被拒。

### [x] S-3 🟡 三个控制面服务器无请求体大小上限：未鉴权方可用超大 body/深层 JSON 炸弹 OOM 应用或守护进程（fixed in 656a12f）

- **位置**：
  - 应用内 server：`packages/flutter_cockpit/lib/src/remote/cockpit_remote_session_server.dart:78-85`（`utf8.decoder.bind(request).join()` 后 `jsonDecode`，无 Content-Length/字节上限）。
  - 开发会话控制面：`packages/cockpit/lib/src/development/cockpit_development_session_supervisor.dart:800-810`（`_readJsonBody` 同样无上限）。
  - 桥接服务器：`packages/cockpit/lib/src/bridge/cockpit_web_remote_session_bridge_server.dart:266-269,667-672`（`_forward`/`_startHostRecording` 无上限）、162 行（WS 帧承载 base64 录制数据，无消息大小上限）。
  - 对照仓库自己的标准：`cockpit_supervisor_http_support.dart:14,52-78`（`cockpitMaximumRequestBytes = 1 MiB` 流式检查）。
- **问题**：与 S-1 叠加时，一个本地低权限进程（或经 `fetch(..., {mode:'no-cors'})` 的网页）可用数 GB body 或深嵌套 JSON 炸弹直接 OOM 应用/worker/守护进程——Supervisor 已有防护，这三个服务器全部遗漏。
- **修复建议**：三处统一复用 `cockpitSupervisorHttpSupport.readJson` 的模式（Content-Length + 流式字节上限），JSON 解码加深度限制；WS 消息加帧大小上限。
- **验证**：单测对三个服务器各发超限 body/超深嵌套 JSON，断言返回 413/400 而非内存暴涨。

### [x] S-4 🟡 Supervisor bearer token 用非常量时间字符串比较：逐字节时序侧信道（fixed in 656a12f）

- **位置**：`packages/cockpit/lib/src/supervisor/cockpit_daemon_host.dart:186-195`。
- **现状代码**：
  ```dart
  if (authorization != 'Bearer ${discovery.bearerToken}') {
  ```
- **问题**：`!=` 在首个不匹配字节即短路，泄漏逐字节时序信息。token 门禁全部 Supervisor 操作（run 提交、worker 操作、工件下载）且守护进程生命周期内长期不变；虽然仅绑回环，攻击者只需另一个能打开回环套接字的本地进程统计响应延迟（本地 RTT 噪声小）。token 生成本身没问题（`CockpitSecureTokenGenerator` 用 `Random.secure`）。
- **修复建议**：改为对两侧等长 HMAC 摘要做全长度常量时间比较（或引入常量时间比较 helper）。
- **验证**：单测断言错 token、错长度、正确 token 的行为不变；代码评审确认比较不再短路。

### [x] S-5 🟡 网络脱敏是固定名单制：裸 `key`/`code`/`pwd` 类凭证参数不掩码，与「credential-like 值默认掩码」的文档承诺不符（fixed in 656a12f）

- **位置**：`packages/cockpit_protocol/lib/src/network/cockpit_network_redactor.dart`——`isSensitiveName`（134-152 行）匹配 authorization/cookie/apikey（后缀）/accesskey/signature/sig/hmac/csrf/xsrf/bearer 及包含 password/passwd/secret/token/credential 的名字，**不含**裸 `key`、`code`、`pwd`；行内凭证正则（9-12 行）对 `key` 要求 `api`/`private` 前缀且无 `code` 分支。文档承诺见 `.agents/skills/cockpit/SKILL.md`（"Sensitive query, header, cookie, structured-body, and credential-like values are masked with `*` by default"）。
- **问题**：`https://host/reset?key=abc123` 或 OAuth 回调 `?code=...&key=...` 的完整值出现在每行 `dev network` 索引中；同样的名字经 `_value`/`body()`（90-120、172-190 行）在非 raw 的 JSON/form body 中也直通。headers/cookies/multipart/WS 帧均正确覆盖，只有这些无前缀凭证名漏网。
- **修复建议**：把裸 `key`、`code`、`pwd` 加入 `isSensitiveName` 与行内正则（注意 `code` 可能误伤状态码字段名，可先做精确匹配再观察），或收窄文档措辞到确切名单。
- **验证**：单测：`?key=`、`?code=`、form/JSON 中的同名字段被掩码；`--raw` 仍为唯一旁路。

---

## G. 功能建议（新增能力）

### G-1 🟡 落地 GOALS.md 承诺的「标准任务包 / 验收交付物」（handoff / acceptance）

- **背景**：`GOALS.md:113-134` 明确定义了标准任务产物（`manifest.json`、`environment.json`、`steps.json`、`observations.json`、`acceptance.md`、`handoff.json` 等），且将「验收打包、可复现、可发送」列为 V1 必达目标；但 `grep -rn "handoff.json\|acceptance" packages/cockpit/lib` 无对应实现（只有无关的 WDA/RPC handoff）。当前 `suite report`（`packages/cockpit/lib/src/cli/commands/run_commands.dart:411` 附近，`cockpit suite report --output-dir`）只导出规范化的 run 报告束。
- **建议**：在 suite/case run 达到终态后（发布路径参考 `packages/cockpit/lib/src/supervisor/cockpit_supervisor_run_projection.dart` 的 publish/retention），增加一个可选的「验收打包」步骤/命令（如 `cockpit run package --run-id RUN --output-dir DIR`），按 GOALS.md 的结构聚合 manifest/环境快照/步骤/观察/工件索引，并生成机器可续用的 `handoff.json` 与人读的 `acceptance.md`。为后续外部消息发送（阶段 3 目标）预留统一出口。
- **验收**：对一次真实 suite run 执行打包命令，产物结构与 GOALS.md 对齐、索引完整、`handoff.json` 可被独立脚本消费。

### G-2 🔵 把 console 已持久化但未接线的偏好接入 UI（完成半成品功能）

- **背景**：见 F-4——`packages/cockpit_console/lib/src/providers/preferences_store.dart` 中 `sidebarCollapsed`（145-151）、`recentDocuments`（154-166）、`fontScale`（169-175）、`chatHistory`（203-226）已实现持久化与测试，但 UI 从未使用（`cockpit_console_app.dart`、`ai_chat_screen.dart` 是现有接线样板）。
- **建议**：侧栏折叠状态持久化；主界面记录最近打开的 run/suite 文档（`recentDocuments`）；设置中提供 UI 字体缩放（`fontScale`）；AI 聊天历史跨启动保留（`chatHistory`，其 100 条上限逻辑已就绪）。若产品上决定不做，则按 F-4 删除。
- **验收**：对应交互重启应用后状态保留；preferences 测试覆盖读写路径。

### G-3 🔵 `cockpit daemon logs --follow` 实时日志流

- **背景**：`packages/cockpit/lib/src/cli/commands/daemon_commands.dart:108-119` 的 `daemon logs` 只能读尾部 N 行；守护进程侧已有可复用的 SSE 基础设施（`packages/cockpit/lib/src/supervisor/cockpit_supervisor_sse.dart`）与 run 事件流（`cockpit run events` 可断线续传），日志却没有流式读取方式。长 E2E 排障时只能反复轮询。
- **建议**：为 daemon 日志增加 `--follow`（SSE 或分页游标），CLI 端持续输出直到 Ctrl-C；与现有 `--lines` 组合决定回溯量。
- **验收**：`cockpit daemon logs --follow` 持续打印新日志；断开后重连不丢关键上下文。

### G-4 🔵 性能基线对比（`suite report` / profile 报告 diff）

- **背景**：截图已有精确对比（`cockpit dev screenshot --compare BASELINE --diff`，`packages/cockpit/lib/src/cli/commands/dev_screenshot_command.dart`），但性能报告没有等价物：`cockpit.profile` 报告含帧阶段分位数、jank、内存、缓存峰值等指标（见 skill 文档与 `flutter_cockpit_test` 的性能 API），回归只能人工对比两份 JSON。
- **建议**：新增 `cockpit run perf-compare --baseline PATH --current PATH [--threshold ...]`（或在 `suite report` 中加 `--baseline`），输出逐指标差值/百分比与超标标记，可作为 CI gate（类似截图 diff 的语义）。
- **验收**：对同一 demo 的两次 profile 报告执行对比，输出结构化 diff；构造一次退化场景能被阈值判定拦截。

### G-5 🔵 暴露多平台性能归档合并为 CLI 命令

- **背景**：`CockpitPerformanceArchive.merge`（`packages/flutter_cockpit_test/lib/src/cockpit_performance_archive.dart:128`）已支持合并多设备/CI 的 JSONL 归档（校验、增量重写、重复 handle 命名空间隔离），但只有 Dart API——CI 上多平台产物合并目前必须写临时 Dart 脚本。
- **建议**：增加 CLI 子命令（如 `cockpit artifact merge-performance --inputs DIR1 DIR2 ... --output-dir DIR`），复用该 API 并输出合并 manifest 路径。
- **验收**：合并 Android/iOS 两份归档后，HTML 查看器能按 capture handle 区分双端数据。

---

## H. 测试补缺（关键空白）

### H-1 🟡 远端桥消息 DTO 全仓库零测试

- **目标**：`packages/cockpit_protocol/lib/src/remote/cockpit_remote_bridge_message.dart`（`CockpitRemoteBridgeRequest/Response`：statusCode 100-599 边界、jsonBody/bytesBase64 互斥、base64 往返）。
- **建议**：新建 `packages/cockpit_protocol/test/cockpit_remote_bridge_message_test.dart`，覆盖合法/非法字段组合与错误消息内容（配合 E-9 修复后一起做最合适）。

### H-2 🟡 结构化输入 LON/JSON/YAML 回退链无测试

- **目标**：`packages/cockpit/lib/src/foundation/cockpit_structured_input.dart:7-25`（`decodeCockpitStructuredInput`）。现有测试未覆盖：合法 LON 但非法 JSON 的输入、YAML 恰好也是合法 JSON 时 JSON 分支必须获胜、非字符串键的 YAML、歧义片段。
- **建议**：在 `packages/cockpit/test/` 增加对应单测，固定回退顺序语义，防止未来调整顺序时静默改变行为。

### H-3 🟡 构造器 vs 解码器边界一致性缺属性测试

- **目标**：`packages/cockpit_protocol/test/cockpit_test_schema_parity_test.dart:82-126` 只做 JSON↔JSON 往返，无法发现「程序化构造合法、`toJson()` 再 `fromJson()` 失败」的漂移（现实案例即 E-2 的 `${` 歧义与 E-6 的 timeoutMs 上限）。
- **建议**：增加模型级属性测试：对每个核心 DTO 构造边界值实例，断言 `fromJson(m.toJson())` 成功且等价；边界值可从解码器的 min/max 参数自动派生。

### H-4 🟡 录制与性能收集器生命周期状态机零回归覆盖（恰是 D-15/D-16/D-19 所在路径）

- **目标**：`packages/flutter_cockpit/test/src/runtime/flutter_cockpit_root_recording_test.dart` 仅有 2 个用例（happy path 与 stop-before-start，9-145 行），未覆盖 start→start-while-active、活动录制中 dispose/换配置（D-16）、原生 stop 失败保留会话；`packages/flutter_cockpit/test/src/performance/cockpit_performance_collector_test.dart` 仅 3 个用例（8-115 行），未覆盖运行中 start、未运行 stop、`endWindow()` 冻结后续帧、dispose 后复用；`packages/flutter_cockpit_test/test/cockpit_test_test.dart:187-210` 只测快速顺序 `beginPerformance` 窗口，未覆盖超过 commandTimeout 的窗口（E-16）与动作期间应用抛异常的路径。
- **建议**：为每个非法状态转移补测试（start→start、stop→stop、dispose-mid-recording、dispose-mid-capture、window-timeout），断言记录到的结果而非只断言不抛。
- **验收**：新测试先在当前代码上复现 D-15/D-16/D-19/E-16（红），修复后转绿。

### [x] H-5 🟡 `melos test` 从不运行 cockpit_protocol 与 cockpit_console 的测试（fixed in 656a12f）

- **位置**：`melos.yaml:15-22`——脚本只跑根 `test/`、flutter_cockpit、flutter_cockpit_test、cockpit、demo 及 demo/cockpit；两个包（`packages/cockpit_protocol/test` 13 个文件约 5000 行：选择器解析、schema 等价、全部协议契约；`packages/cockpit_console/test` 14 个文件）都在 melos 包列表中（第 4、8 行）却不在任何脚本命令里。CI 有覆盖（`.github/workflows/example-e2e.yml:84-86,128-130`），但本地/文档化的 `melos test` 路径可以在这些套件全红时保持绿色。
- **修复建议**：脚本追加 `(cd packages/cockpit_protocol && dart test)` 与 `(cd packages/cockpit_console && flutter test --no-pub)`（或改用 `melos exec` 按依赖过滤）。
- **验证**：`melos test` 输出包含两个包的测试结果。

### H-6 🔵 schema 镜像等价测试在镜像消失时静默空转（永远通过）

- **位置**：`packages/cockpit_protocol/test/cockpit_test_schema_parity_test.dart:48-53`——12 个镜像副本（.agents/.claude/.cursor/plugins 等）的断言全部包在 `if (mirror.existsSync())` 里。
- **问题**：重构移动/重命名任何或全部 skill 镜像目录（canonical `schema/` 副本完好）时，所有分支被跳过、测试通过——恰好是这个测试要防的漂移。
- **修复建议**：循环前断言 `mirrorPaths.where((p) => File(p).existsSync())` 数量等于（或不少于）预期，镜像路径清单本身作为测试数据固化。
- **验证**：临时重命名一个镜像目录，断言测试失败。

### H-7 🟡 一批用真实墙钟时间做同步/上界断言的 flaky 测试（CI 高负载下随机挂）

- **位置与形态**（均已核对源码）：
  - 固定睡眠做同步：`packages/cockpit/test/src/bridge/cockpit_web_remote_session_bridge_server_test.dart:572-581`（`close()` 后固定 80ms 再断言 `/ready` 已降级）——应改为带 deadline 的轮询。
  - 叠加定时器证明否定：`packages/cockpit/test/src/worker/cockpit_worker_rpc_contract_test.dart:181,200-202,211-212`（handler 睡 80ms、调用 deadline 20ms、测试再睡 40ms 断言未完成）——事件循环一次 >40ms 停顿即假失败；应让 handler 等待测试控制的 Completer。
  - 真实进程/网络工作的墙上钟上界：`cockpit_daemon_process_smoke_test.dart:346-348`（杀真实守护进程断言 <1s）、`:423`、`cockpit_web_remote_session_bridge_server_test.dart:763,856,894,937`、`cockpit_adb_capture_adapter_test.dart:236`、`cockpit_remote_session_client_test.dart:925`、`cockpit_read_remote_snapshot_service_test.dart:399`——共享 runner 上 routinely 超时；应改为相对断言（elapsed < k×timeout）或注入假时钟。
  - 短等待证明否定（弱通过方向）：`cockpit_identity_foundation_test.dart:289-294`（25ms 断言读未完成——慢机器上无锁的坏实现若 >25ms 也通过）、`cockpit_development_session_supervisor_test.dart:131,801`（50ms）、`cockpit_worker_pool_test.dart:172-175`（40ms）——应改为可观察信号门控。
  - 6.5s 真实预算燃烧：`cockpit_execute_remote_command_service_test.dart:385-387,401-413`（唯一通过方式是真实烧 6.5s 证明传输预算>命令超时）——套件中最慢的单测且正好骑在断言边界上；应注入可配置常量做算术断言（同文件 417 行的姊妹测试已是该写法）。
- **修复建议**：按各条所述逐一改造（轮询/Completer 门控/相对断言/常量注入），消除对墙钟的绝对依赖。
- **验证**：在 CI 反复重跑受影响测试（或在本地用 CPU 压力工具）确认不再偶发失败。

### H-8 🟡 四个安全关键不变量零测试覆盖

- **位置**：
  1. **run 准入幂等 replay/conflict**：`packages/cockpit/test/src/supervisor/cockpit_supervisor_run_admission_store_test.dart` 仅 2 个用例（列表分页、终态 offset），`admit()`（`cockpit_supervisor_run_admission_store.dart:163-204`）的同键 replay、指纹冲突（167-169）、`maximumAdmissions` 上限（178-180）无任何测试——replay 若坏成总是铸造新 runId，重试的 `runs.create` 会静默复制 run 而无测试失败。
  2. **SSE 恢复语义**：`packages/cockpit/test/src/supervisor/cockpit_supervisor_sse_test.dart` 仅 1 个用例（`afterSequence=0`）；126 行 handler 的 `gap` 事件、`Last-Event-ID` 头解析（99-102 行）、`Last-Event-ID 与 afterSequence 不一致`拒绝（107 行）均无测试。
  3. **远端桥客户端重连**：`packages/flutter_cockpit/test/src/remote/cockpit_remote_session_bridge_client_test.dart` 仅 1 个用例；`onError`/`onDone` 重连（70-75 行）、重连在途时 `close()`（100-117 行）、固定延迟无限重连无上限（对永久宕机的桥是无界连接风暴）均未固定。
  4. **worker 重启退避增长是测试下的死代码**：全部池测试钉死 `initialRestartBackoff: 1ms, maximumRestartBackoff: 1ms`（`cockpit_worker_pool_test.dart:51,92,118,157` 等），`cockpit_worker_pool.dart:434-447` 的指数增长与封顶逻辑删掉也能全绿——崩溃循环的 worker 在生产会以 1ms 间隔锤重启。
- **修复建议**：四项各补一组测试：同键 replay/指纹冲突/上限；Last-Event-ID 与 gap 场景；重连与关闭竞争、重连预算语义；用可区分的 initial/maximum 与注入 delay 断言增长序列到封顶。
- **验证**：新测试在人为破坏对应逻辑（删掉增长/改成总是新 runId）时变红。

---

## 完成情况追踪

本轮已将真实完成项直接标为 `[x]`，并统一关联实现提交 `656a12f`。其余未标记条目仍保留原始审计证据和建议，后续处理时必须在验证通过后再补真实提交号；不得使用占位 hash。
