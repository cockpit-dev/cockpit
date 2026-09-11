# cockpit_test

[English](README.md) · 简体中文

平台无关的可编程测试场景，供所有 Cockpit runner 共享。场景只需面向
`CockpitTester` 契约编写一次，即可不加改动地运行在 Flutter 集成测试、带
Cockpit bridge 的 release/profile 应用，或原生黑盒目标上。

这个包刻意保持精简，除 `cockpit_protocol` 外零依赖：它只负责编写契约本身。
具体的 tester、runner、进程管理与平台驱动都位于下游包中。

## 契约

```dart
import 'package:cockpit_test/cockpit_test.dart';

final smoke = CockpitTestScenario(
  id: 'save-settings',
  requiredCapabilities: const {'tap', 'type', 'assertText'},
  body: (tester) async {
    await tester.tap('#settings');
    await tester.type('Alice', into: '#name');
    await tester.tap('#save');
    await tester.expectText(
      '#status',
      const CockpitLocalizedText(
        'settings.saved',
        values: {'en-US': 'Saved', 'zh-CN': '已保存'},
      ),
    );
  },
);
```

场景组合成语言矩阵：

```dart
final suite = CockpitTestSuiteProgram(
  id: 'settings-smoke',
  locales: const [
    CockpitLocaleProfile('en-US'),
    CockpitLocaleProfile('zh-CN'),
  ],
  cases: [CockpitTestCaseProgram(id: 'save', scenario: smoke)],
);
```

执行经由 `CockpitTestRunner` 完成。默认的生命周期 runner 与具体的 tester
随 [`cockpit`](../cockpit) 包发布：

```dart
import 'package:cockpit/cockpit.dart';

final result = await const CockpitProgrammaticTestRunner().runSuite(
  suite,
  createTester: (locale) async => RemoteCockpitTester(
    client: CockpitRemoteSessionClient(
      baseUri: endpoint,
      authToken: remoteToken,
    ),
    workspaceRoot: workspaceRoot,
    initialLocale: locale,
  ),
);
```

每次 case/语言尝试的结果为 `passed`、`failed` 或 `blocked`。当目标的实际能力
无法满足场景声明的 `requiredCapabilities` 时，会在场景体执行之前以
`CockpitTestCapabilityException` 判定为 `blocked`；绝不会靠静默跳过步骤或
填充零值数据来假装通过。

## 场景规则

场景只能使用选择器、协议值和当前激活的语言。它不得 import
`WidgetTester`、`BuildContext` 或任何原生 SDK。runner 的生命周期、安装与
清理都留在场景体之外，从而保证同一段代码在每个目标上走完全相同的路径：

- Flutter 集成测试通过
  [`flutter_cockpit_test`](../flutter_cockpit_test) 复用场景。
- 带 Cockpit bridge 的 release/profile 应用使用 `RemoteCockpitTester`。
- 未接入 Cockpit 的应用通过平台系统控制适配器使用 `SystemCockpitTester`。

## 语言优先的国际化

`CockpitLocaleProfile` 为每次尝试携带经过校验的 BCP-47 标签、地区与文字
方向。`CockpitLocalizedText` 依据当前激活语言惰性解析翻译，因此场景内切换
语言后，下一条断言就能观察到新语言，而不是构造时刻的快照。缺少翻译会抛出
`CockpitTestLocalizationException`，而不是回退成错误语言的字符串。

## 了解更多

- [跨 runner 的可编程测试](../../docs/cross-runner-programmatic-testing.md)
- [`cockpit_protocol` 契约](../cockpit_protocol/README.md)
- [`cockpit` 的 runner 与 tester](../cockpit/README.md)
