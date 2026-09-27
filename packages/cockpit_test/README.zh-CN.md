# cockpit_test

[English](README.md) · 简体中文

供 Cockpit runner 共享的、平台无关的进程内测试场景。场景只需面向
`CockpitTester` 编写一次，同一个 Dart closure 就能运行在 Flutter 集成测试、带
bridge 的 release/profile 应用或原生黑盒目标上。

`cockpit_test` 只依赖 `cockpit_protocol`。它负责共享的编写、preflight、语言、runner
与结果契约；具体 tester 和平台生命周期仍由下游包负责。

## 编写场景

```dart
import 'package:cockpit_test/cockpit_test.dart';

final smoke = CockpitTestScenario(
  id: 'save-settings',
  requirements: CockpitTestRequirements(
    commands: const {
      CockpitCommandType.tap,
      CockpitCommandType.enterText,
      CockpitCommandType.assertText,
    },
    locators: const {CockpitLocatorKind.cockpitId},
  ),
  body: (tester) async {
    await tester.tap('#settings');
    await tester.type('Alice', into: '#name');
    await tester.tap('#save');
    await tester.expectText(
      '#status',
      CockpitLocalizedText(
        'settings.saved',
        values: const {'en-US': 'Saved', 'zh-CN': '已保存'},
      ),
    );
  },
);
```

requirements 直接使用协议 enum，因此 tester 的 `type()` 会准确检查
`CockpitCommandType.enterText`，不会再让字符串别名与 wire contract 漂移。命令、定位器
策略和少量非命令特性分别使用独立的类型集合。

把场景组合成非空语言矩阵：

```dart
final suite = CockpitTestSuiteProgram(
  id: 'settings-smoke',
  locales: [
    CockpitLocaleProfile('en-US'),
    CockpitLocaleProfile('zh-Hant-TW'),
  ],
  cases: [CockpitTestCaseProgram(id: 'save', scenario: smoke)],
);
```

使用任意具体 tester 执行：

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
`CockpitTestError`。目标不支持 typed requirement 时，会在场景体执行前阻塞。空 suite
无法构造，空 attempt 集合也不会被判定为成功。

## Flutter 集成测试

`flutter_cockpit_test` 复用 Flutter 官方 `integration_test` runner 以及现有 mount/teardown
生命周期：

```dart
cockpitScenarioWidgets(
  '保存设置',
  app: buildDevelopmentApp,
  scenario: smoke,
);
```

只有测试确实需要 Flutter 专属 API 时，才改用 `cockpitTestWidgets`。

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
