import 'package:flutter/material.dart';
import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';

/// A development-only hook that an application can expose around real work.
/// Production code may keep the hook absent; Cockpit only connects it during
/// an explicit profile capture.
abstract final class CheckoutHooks {
  static void Function(String name, Map<String, Object?> args)? onEvent;

  static void emit(String name, [Map<String, Object?> args = const {}]) {
    onEvent?.call(name, args);
  }
}

void main() {
  cockpitTestWidgets(
    'profile a checkout interaction',
    app: () => const _CheckoutApp(),
    body: (cockpit) async {
      final report = await cockpit.profile(
        () async {
          CheckoutHooks.emit('checkout.open', const {'items': 3});
          await cockpit.tap('Checkout');
          CheckoutHooks.emit('checkout.confirmed');
        },
        name: 'checkout',
        plugins: <CockpitPerformancePlugin>[_CheckoutPerformancePlugin()],
      );

      // The full report is also available through IntegrationTest's reportData
      // and can be exported to JSON, HTML, or Chrome trace by the test facade.
      assert(report.plugins.any((plugin) => plugin.id == 'checkout-hook'));
    },
  );
}

final class _CheckoutPerformancePlugin extends CockpitPerformancePlugin {
  _CheckoutPerformancePlugin() : super(id: 'checkout-hook');

  @override
  CockpitPerformancePluginRun open(CockpitPerformancePluginContext context) =>
      _CheckoutPerformanceRun(context.sink);
}

final class _CheckoutPerformanceRun extends CockpitPerformancePluginRun {
  _CheckoutPerformanceRun(this.sink);

  final CockpitPerformanceSink sink;

  @override
  void start() {
    CheckoutHooks.onEvent = (name, args) {
      sink.instant(
        name,
        category: 'business',
        args: args,
        location: const CockpitPerformanceLocation(
          uri: 'package:checkout/checkout.dart',
          line: 42,
        ),
      );
    };
  }

  @override
  void stop(CockpitPerformancePluginStats stats) {
    CheckoutHooks.onEvent = null;
  }
}

final class _CheckoutApp extends StatefulWidget {
  const _CheckoutApp();

  @override
  State<_CheckoutApp> createState() => _CheckoutAppState();
}

final class _CheckoutAppState extends State<_CheckoutApp> {
  var _confirmed = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: Center(
          child: _confirmed
              ? const Text('Confirmed')
              : FilledButton(
                  onPressed: () => setState(() => _confirmed = true),
                  child: const Text('Checkout'),
                ),
        ),
      ),
    );
  }
}
