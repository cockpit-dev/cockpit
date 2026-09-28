# cockpit_test

[English](README.md) · 简体中文

供 Cockpit runner 共享的、平台无关的进程内测试场景。场景只需面向
`CockpitTester` 编写一次，同一个 Dart closure 就能运行在 Flutter 集成测试、带
bridge 的 release/profile 应用或原生黑盒目标上。

`cockpit_test` 只依赖 `cockpit_protocol`。它负责共享的编写、preflight、语言、runner
与结果契约；具体 tester 和平台生命周期仍由下游包负责。

## 编写场景

场景就是一个 id 加一个执行体，其他都是可选的：

```dart
import 'package:cockpit_test/cockpit_test.dart';

final smoke = CockpitTestScenario(
  id: 'save-settings',
  body: (tester) async {
    await tester.tap('Settings');
    await tester.type('Alice', into: 'Name');
    await tester.tap('Save');
    await tester.expectText('#status', 'Saved');
  },
);
```

执行体只使用选择器、协议值、纯 Dart 和当前语言，绝不触碰
`WidgetTester`、`BuildContext` 或原生 SDK，因此同一份 closure 可以运行在所有执行面。

## 断言、等待与读回

目标侧断言与等待覆盖常见 UI 校验，以下每个方法在三个执行面上都是同一个协议操作：

```dart
// 文本匹配：默认精确匹配，另有 contains / fuzzy / regex。
await tester.expectText('#status', 'Saved');
await tester.expectText('#title', 'Settings', match: CockpitTextMatchMode.contains);

// 存在性等待，以及同样重要的缺席等待 —— 断言"某物已消失"的共享方式。
await tester.waitFor('#drawer');
await tester.waitFor('#spinner', absent: true);

// 把真实 UI 状态读回来，而不只是断言，然后用纯 Dart 比较。这些宿主侧
// helper 抛出的结构化断言失败会被 runner 归类为 failed，而不是内部错误。
final snapshot = await tester.collectSnapshot();
cockpitExpectEquals(snapshot.visibleTargets.length, 2);
cockpitExpectTrue(snapshot.routeName == 'settings');
cockpitExpectContains(await readLabels(snapshot), 'Saved');
```

宿主侧 helper 完整列表：`cockpitExpectEquals`（对数字、字符串、布尔、列表、集合和
Map 做深度相等）、`cockpitExpectTrue`、`cockpitExpectNotNull` 和
`cockpitExpectContains`（字符串、可迭代对象或 Map key 的成员判断）。

## 在 Flutter 上运行

`flutter_cockpit_test` 复用 Flutter 官方 `integration_test` runner 以及现有
mount/teardown 生命周期：

```dart
cockpitScenarioWidgets(
  '保存设置',
  app: buildDevelopmentApp,
  scenario: smoke,
);
```

只有测试确实需要在共享 `CockpitTester` 表面之外使用 Flutter 专属 API 时，才改用
`cockpitTestWidgets`。

## 一次跑完语言矩阵

把场景装进 suite —— 直接给场景即可，每个场景会自动成为以其 id 命名的用例：

```dart
final suite = CockpitTestSuiteProgram(
  id: 'settings-smoke',
  locales: [
    CockpitLocaleProfile('en-US'),
    CockpitLocaleProfile('zh-Hant-TW'),
  ],
  scenarios: [smoke],
);
```

只有当场景需要独立的用例 id 或 metadata 时，才传
`cases: [CockpitTestCaseProgram(id: ..., scenario: ...)]`。用任意具体 tester 执行；
单次运行的语言也是可选的，默认 `en-US`：

```dart
import 'package:cockpit/cockpit.dart';

final result = await const CockpitProgrammaticTestRunner().runSuite(
  suite,
  createTester: (locale) async => RemoteCockpitTester(
    client: client,
    workspaceRoot: workspaceRoot,
    initialLocale: locale,
  ),
);
```

每次 attempt 都明确为 `passed`、`failed` 或 `blocked`，并携带结构化
`CockpitTestError`。空 suite 无法构造，空 attempt 集合也不会被判定为成功。

## 跨执行面的选择器

`#cockpitId` 和 `@key` 选择器只在 Flutter 应用内部（in-app 与 bridge 执行面）可解析。
黑盒目标只能看到 accessibility tree，因此必须跨执行面运行的场景应只使用共享的定位
类别：文本（`'Save'` 或 `["text*="Save"]`）、tooltip、控件类型和 path。用
`CockpitSelector.format` 可以查看一个定位器如何编码。

## 能力预检（进阶）

声明类型化 requirements 是可选的。声明后，runner 会在执行体运行前对照目标检查，
一次性列出全部缺口：

```dart
CockpitTestRequirements(
  commands: const {
    CockpitCommandType.tap,
    CockpitCommandType.enterText,
  },
  locators: const {CockpitLocatorKind.text},
)
```

requirements 直接使用协议 enum，因此 tester 的 `type()` 会准确检查
`CockpitCommandType.enterText`，字符串别名不会与 wire contract 漂移。即使不声明
requirements，目标在运行途中回答"不支持该能力"时，attempt 也会被判定为 blocked
——与预检不一致的语义完全一致；声明 requirements 只是把这一结论提前，并一次性列出
全部缺失项。预检对黑盒目标以及带有可选集成（network observer、semantic 命令）的
应用最有价值；默认挂载的 Flutter 应用完整支持共享表面。

## 语言行为

`CockpitLocaleProfile` 在运行时校验并规范化 language、script 与 region subtag。例如
`ZH-hant-tw` 会变成 `zh-Hant-TW`。metadata 和翻译 Map 都会被复制为不可变值。

`CockpitLocalizedText` 根据当前语言惰性解析，回退顺序固定为：

1. 完整标签，例如 `zh-Hant-TW`；
2. language + script，例如 `zh-Hant`；
3. language，例如 `zh`。

缺少翻译会抛出 `CockpitTestLocalizationException`，不会静默选择无关语言。

## 进程内边界

场景体是 Dart closure。`toManifestJson()` 只是 ID、requirements、语言矩阵与 metadata 的
诊断投影，无法包含或恢复可执行代码。需要持久化、排队或跨语言执行时，请使用声明式
`cockpit.test/v2` 文档模型。

可运行示例位于
[`example/settings_smoke.dart`](example/settings_smoke.dart)。

## 了解更多

- [跨 runner 的可编程测试](../../docs/cross-runner-programmatic-testing.md)
- [`cockpit_protocol` 契约](../cockpit_protocol/README.md)
- [`cockpit` 具体 tester](../cockpit/README.md)
