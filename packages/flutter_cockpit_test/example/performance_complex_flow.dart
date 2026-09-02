import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';

/// Runs the same realistic flow once in memory and once with a live JSONL
/// archive, then writes a compact JSON export and a self-contained HTML view.
///
/// Execute from the repository root with:
///
///   flutter test --no-pub packages/flutter_cockpit_test/example/performance_complex_flow.dart
///
/// The test prints only the three artifact paths needed for inspection.
void main() {
  cockpitTestWidgets(
    'exports a complex performance flow',
    app: () => const _StoreApp(),
    body: (cockpit) async {
      final memoryReport = await cockpit.profile(
        () => _runStoreFlow(cockpit),
        name: 'memory-flow',
      );
      final jsonPath = await cockpit.exportPerformanceJson(
        title: 'complex-memory',
      );

      final archive = await cockpit.openPerformanceArchive(
        name: 'complex-stream',
      );
      final streamedReport = await cockpit.profile(
        () => _runStoreFlow(cockpit),
        name: 'stream-flow',
        archive: archive,
        plugins: <CockpitPerformancePlugin>[_storePlugin()],
      );
      final archiveInfo = await archive.close();
      final html = CockpitPerformanceHtml.renderMany(
        <CockpitPerformanceReport>[
          memoryReport,
          streamedReport.copyWithArchive(archiveInfo),
        ],
        title: 'Complex store performance',
        startup: cockpit.startup,
      );
      final htmlFile = File(
        'build/cockpit/performance/complex-store-${DateTime.now().toUtc().millisecondsSinceEpoch}.html',
      );
      await htmlFile.parent.create(recursive: true);
      await htmlFile.writeAsString(html, flush: true);

      print(jsonPath);
      print(archiveInfo.manifest);
      print(htmlFile.absolute.path);
    },
  );
}

Future<void> _runStoreFlow(CockpitTester cockpit) async {
  _StoreProbe.mark('catalog.open');
  await cockpit.tap('Open catalog');
  await cockpit.waitFor('Catalog');
  await cockpit.scroll('Product 24', align: 'center');
  _StoreProbe.mark('product.open', <String, Object?>{'index': 24});
  await cockpit.tap('Product 24');
  await cockpit.waitFor('Product 24 details');
  await cockpit.tap('Add to cart');
  await cockpit.flutter.pump(const Duration(milliseconds: 400));
  await cockpit.expectVisible('Added to cart');
  _StoreProbe.mark('cart.updated');
  await cockpit.back();
  await cockpit.back();
  await cockpit.waitFor('Open catalog');
}

CockpitPerformancePlugin _storePlugin() => _StorePerformancePlugin();

final class _StorePerformancePlugin extends CockpitPerformancePlugin {
  _StorePerformancePlugin() : super(id: 'store-flow');

  @override
  CockpitPerformancePluginRun open(CockpitPerformancePluginContext context) =>
      _StorePerformanceRun(context.sink);
}

final class _StorePerformanceRun extends CockpitPerformancePluginRun {
  _StorePerformanceRun(this.sink);

  final CockpitPerformanceSink sink;

  @override
  void start() {
    _StoreProbe.onMark = (name, args) {
      sink.instant(
        name,
        category: 'store',
        args: args,
        location: const CockpitPerformanceLocation(
          uri: 'package:demo/store_flow.dart',
          line: 48,
        ),
      );
    };
  }

  @override
  void stop(CockpitPerformancePluginStats stats) {
    _StoreProbe.onMark = null;
  }
}

abstract final class _StoreProbe {
  static void Function(String, Map<String, Object?>)? onMark;

  static void mark(
    String name, [
    Map<String, Object?> args = const <String, Object?>{},
  ]) {
    onMark?.call(name, args);
  }
}

final class _StoreApp extends StatelessWidget {
  const _StoreApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(home: _HomePage());
}

final class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

final class _HomePageState extends State<_HomePage> {
  var _cart = 0;

  void _openCatalog() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CatalogPage(onAdd: () => setState(() => _cart += 1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cockpit Store')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('Cart count: $_cart'),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _openCatalog,
            child: const Text('Open catalog'),
          ),
        ],
      ),
    ),
  );
}

final class _CatalogPage extends StatelessWidget {
  const _CatalogPage({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Catalog')),
    body: ListView.builder(
      itemCount: 40,
      itemBuilder: (context, index) => ListTile(
        title: Text('Product $index'),
        subtitle: Text('Inventory item $index'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _ProductPage(index: index, onAdd: onAdd),
          ),
        ),
      ),
    ),
  );
}

final class _ProductPage extends StatefulWidget {
  const _ProductPage({required this.index, required this.onAdd});

  final int index;
  final VoidCallback onAdd;

  @override
  State<_ProductPage> createState() => _ProductPageState();
}

final class _ProductPageState extends State<_ProductPage> {
  var _added = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Product ${widget.index} details')),
    body: Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(24),
        color: _added ? Colors.green.shade100 : Colors.blue.shade100,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Product ${widget.index} details'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _added
                  ? null
                  : () {
                      widget.onAdd();
                      setState(() => _added = true);
                    },
              child: const Text('Add to cart'),
            ),
            if (_added) const Text('Added to cart'),
          ],
        ),
      ),
    ),
  );
}
