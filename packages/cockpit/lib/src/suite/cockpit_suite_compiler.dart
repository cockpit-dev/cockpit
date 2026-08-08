import 'dart:convert';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';

import '../test/cockpit_test_document_compiler.dart';
import 'cockpit_suite_execution_plan.dart';
import 'cockpit_suite_matrix_expander.dart';

abstract interface class CockpitSuiteCaseResolver {
  Future<CockpitCompiledTestCase> resolveFile(
    CockpitTestSuiteFileCaseSource source,
  );
}

final class CockpitSuiteCompilationException implements Exception {
  CockpitSuiteCompilationException(this.diagnostics)
    : assert(diagnostics.isNotEmpty);

  final List<CockpitTestDiagnostic> diagnostics;

  @override
  String toString() => diagnostics.map((item) => item.message).join('\n');
}

final class CockpitSuiteCompiler {
  const CockpitSuiteCompiler({
    CockpitSuiteMatrixExpander matrixExpander =
        const CockpitSuiteMatrixExpander(),
  }) : _matrixExpander = matrixExpander;

  final CockpitSuiteMatrixExpander _matrixExpander;

  Future<CockpitSuiteExecutionPlan> compile({
    required CockpitCompiledTestSuite compiledSuite,
    required CockpitSuiteCaseResolver resolver,
    Map<String, Object?> inputs = const <String, Object?>{},
  }) async {
    final suite = compiledSuite.suite;
    final resolvedEntries = <String, CockpitCompiledTestCase>{};
    for (final entry in suite.cases) {
      resolvedEntries[entry.id] = await _resolve(entry.source, resolver);
    }
    final resolvedFixtures = <String, _ResolvedFixture>{};
    for (final fixture in suite.fixtures) {
      resolvedFixtures[fixture.id] = _ResolvedFixture(
        fixture: fixture,
        setup: await _resolve(fixture.setup, resolver),
        teardown: fixture.teardown == null
            ? null
            : await _resolve(fixture.teardown!, resolver),
      );
    }
    _validateRuntimeInputs(inputs, resolvedEntries, resolvedFixtures);
    _validateFixtureScopes(suite, resolvedFixtures);
    final built = _buildNodes(suite, resolvedEntries, resolvedFixtures, inputs);
    return CockpitSuiteExecutionPlan(
      suite: suite,
      sourceSha256: compiledSuite.sourceSha256,
      nodes: built.nodes,
      attemptNodes: built.attemptNodes,
    );
  }

  Future<CockpitCompiledTestCase> _resolve(
    CockpitTestSuiteCaseSource source,
    CockpitSuiteCaseResolver resolver,
  ) => switch (source) {
    CockpitTestSuiteInlineCaseSource() => Future<CockpitCompiledTestCase>.value(
      CockpitCompiledTestCase(
        testCase: source.testCase,
        sourceSha256: sha256
            .convert(utf8.encode(_canonical(source.testCase.toJson())))
            .toString(),
        sourceMap: const <String, CockpitTestSourceLocation>{},
      ),
    ),
    CockpitTestSuiteFileCaseSource() => resolver.resolveFile(source),
  };

  _BuiltNodes _buildNodes(
    CockpitTestSuite suite,
    Map<String, CockpitCompiledTestCase> entries,
    Map<String, _ResolvedFixture> fixtures,
    Map<String, Object?> runtimeInputs,
  ) {
    final builders = <String, _NodeBuilder>{};
    final rowsByEntry = <String, List<_CaseRow>>{};
    _addCaseRows(suite, entries, rowsByEntry, builders, runtimeInputs);
    _addCaseAttemptFixtures(
      suite,
      fixtures,
      rowsByEntry,
      builders,
      runtimeInputs,
    );
    _addSuiteFixtures(suite, fixtures, rowsByEntry, builders, runtimeInputs);
    _wireCaseDependencies(suite, rowsByEntry, builders);
    final scheduledIds = <String>{
      for (final builder in builders.values)
        if (_isScheduled(builder)) builder.nodeId,
    };
    return _BuiltNodes(
      nodes: <CockpitSuitePlanNode>[
        for (final builder in builders.values)
          if (scheduledIds.contains(builder.nodeId))
            builder.build(
              dependencies: _scheduledDependencies(
                builder,
                builders,
                scheduledIds,
              ),
            ),
      ],
      attemptNodes: <CockpitSuitePlanNode>[
        for (final builder in builders.values)
          if (!scheduledIds.contains(builder.nodeId)) builder.build(),
      ],
    );
  }

  bool _isScheduled(_NodeBuilder builder) =>
      builder.kind == CockpitSuitePlanNodeKind.testCase ||
      builder.caseNodeId == null;

  Set<String> _scheduledDependencies(
    _NodeBuilder builder,
    Map<String, _NodeBuilder> builders,
    Set<String> scheduledIds,
  ) {
    final result = <String>{};
    final visited = <String>{};
    void visit(String nodeId) {
      if (!visited.add(nodeId)) return;
      if (scheduledIds.contains(nodeId)) {
        result.add(nodeId);
        return;
      }
      for (final dependency in builders[nodeId]!.dependencies) {
        visit(dependency);
      }
    }

    for (final dependency in builder.dependencies) {
      visit(dependency);
    }
    return result;
  }

  void _addCaseRows(
    CockpitTestSuite suite,
    Map<String, CockpitCompiledTestCase> entries,
    Map<String, List<_CaseRow>> rowsByEntry,
    Map<String, _NodeBuilder> builders,
    Map<String, Object?> runtimeInputs,
  ) {
    var rowCount = 0;
    final selectedEntries = _selectedEntryIds(suite);
    for (final entry in suite.cases) {
      final rows = _matrixExpander.expand(
        suite.matrix,
        selectedAxes: entry.matrixAxes,
      );
      final targets = entry.targetIds.isEmpty
          ? const <String?>[null]
          : (entry.targetIds.toList()..sort()).cast<String?>();
      final selected = selectedEntries.contains(entry.id);
      final entryRows = <_CaseRow>[];
      for (final matrix in rows) {
        for (final targetId in targets) {
          rowCount += 1;
          if (rowCount > suite.matrix.maxCombinations * suite.cases.length) {
            throw const FormatException(
              'Suite case expansion exceeds its bound.',
            );
          }
          final identity = <String, Object?>{
            'entryId': entry.id,
            'matrix': matrix,
            'targetId': ?targetId,
          };
          final isolationNodeId = _nodeId('isolation', entry.id, identity);
          final nodeId = _nodeId('case', entry.id, identity);
          final row = _CaseRow(
            entry: entry,
            isolationNodeId: isolationNodeId,
            mainNodeId: nodeId,
            matrix: matrix,
            targetId: targetId,
            selected: selected,
          );
          entryRows.add(row);
          _put(
            builders,
            _NodeBuilder(
              nodeId: isolationNodeId,
              entryId: entry.id,
              kind: CockpitSuitePlanNodeKind.isolation,
              compiledCase: entries[entry.id]!,
              inputs: _nodeInputs(
                entries[entry.id]!,
                entry.inputs,
                runtimeInputs,
                matrix,
              ),
              matrix: matrix,
              targetId: targetId,
              retry: entry.retry ?? suite.execution.retry,
              selected: selected,
              alwaysRun: false,
              isolation: suite.execution.isolation,
              caseNodeId: nodeId,
            ),
          );
          _put(
            builders,
            _NodeBuilder(
              nodeId: nodeId,
              entryId: entry.id,
              kind: CockpitSuitePlanNodeKind.testCase,
              compiledCase: entries[entry.id]!,
              inputs: _nodeInputs(
                entries[entry.id]!,
                entry.inputs,
                runtimeInputs,
                matrix,
              ),
              matrix: matrix,
              targetId: targetId,
              retry: entry.retry ?? suite.execution.retry,
              selected: selected,
              alwaysRun: false,
              caseNodeId: nodeId,
            )..dependencies.add(isolationNodeId),
          );
        }
      }
      rowsByEntry[entry.id] = List<_CaseRow>.unmodifiable(entryRows);
    }
    if (rowCount == 0) {
      throw const FormatException('Suite expansion produced no case rows.');
    }
  }

  bool _isSelected(CockpitTestSuite suite, CockpitTestSuiteEntry entry) {
    if (suite.includeTags.isNotEmpty &&
        entry.tags.intersection(suite.includeTags).isEmpty) {
      return false;
    }
    return entry.tags.intersection(suite.excludeTags).isEmpty;
  }

  Set<String> _selectedEntryIds(CockpitTestSuite suite) {
    final byId = <String, CockpitTestSuiteEntry>{
      for (final entry in suite.cases) entry.id: entry,
    };
    final selected = <String>{};
    void select(String id) {
      if (!selected.add(id)) return;
      for (final dependency in byId[id]!.dependsOn) {
        select(dependency);
      }
    }

    for (final entry in suite.cases) {
      if (_isSelected(suite, entry)) select(entry.id);
    }
    return selected;
  }

  void _validateRuntimeInputs(
    Map<String, Object?> inputs,
    Map<String, CockpitCompiledTestCase> entries,
    Map<String, _ResolvedFixture> fixtures,
  ) {
    final accepted = <String>{
      for (final compiled in entries.values) ..._inputNames(compiled),
      for (final fixture in fixtures.values) ...<String>{
        ..._inputNames(fixture.setup),
        if (fixture.teardown != null) ..._inputNames(fixture.teardown!),
      },
    };
    final unknown = inputs.keys.toSet().difference(accepted).toList()..sort();
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Unknown suite runtime input${unknown.length == 1 ? '' : 's'}: '
        '${unknown.join(', ')}.',
      );
    }
  }

  Map<String, Object?> _nodeInputs(
    CockpitCompiledTestCase compiled,
    Map<String, Object?> authoredInputs,
    Map<String, Object?> runtimeInputs,
    Map<String, Object?> matrix,
  ) {
    final accepted = _inputNames(compiled);
    return _bindMatrix(<String, Object?>{
      ...authoredInputs,
      for (final entry in runtimeInputs.entries)
        if (accepted.contains(entry.key)) entry.key: entry.value,
    }, matrix);
  }

  void _validateFixtureScopes(
    CockpitTestSuite suite,
    Map<String, _ResolvedFixture> fixtures,
  ) {
    for (final fixture in suite.fixtures) {
      if (fixture.scope != CockpitTestFixtureScope.suite) continue;
      for (final dependency in fixture.dependsOn) {
        if (fixtures[dependency]!.fixture.scope !=
            CockpitTestFixtureScope.suite) {
          throw FormatException(
            'Suite fixture ${fixture.id} cannot depend on caseAttempt fixture $dependency.',
          );
        }
      }
    }
  }

  void _addCaseAttemptFixtures(
    CockpitTestSuite suite,
    Map<String, _ResolvedFixture> fixtures,
    Map<String, List<_CaseRow>> rowsByEntry,
    Map<String, _NodeBuilder> builders,
    Map<String, Object?> runtimeInputs,
  ) {
    for (final rows in rowsByEntry.values) {
      for (final row in rows) {
        final closure = _fixtureClosure(row.entry.fixtures, fixtures);
        for (final fixtureId in closure) {
          final resolved = fixtures[fixtureId]!;
          final fixture = resolved.fixture;
          if (fixture.scope != CockpitTestFixtureScope.caseAttempt) continue;
          final setupId = _attemptFixtureId('fixtureSetup', fixtureId, row);
          final setup = _NodeBuilder(
            nodeId: setupId,
            entryId: row.entry.id,
            kind: CockpitSuitePlanNodeKind.fixtureSetup,
            compiledCase: resolved.setup,
            inputs: _nodeInputs(
              resolved.setup,
              fixture.inputs,
              runtimeInputs,
              row.matrix,
            ),
            matrix: row.matrix,
            targetId: fixture.targetId ?? row.targetId,
            retry: suite.execution.retry,
            selected: row.selected,
            alwaysRun: false,
            caseNodeId: row.mainNodeId,
          )..dependencies.add(row.isolationNodeId);
          for (final dependency in fixture.dependsOn) {
            final dependencyFixture = fixtures[dependency]!.fixture;
            setup.dependencies.add(
              dependencyFixture.scope == CockpitTestFixtureScope.suite
                  ? _suiteFixtureId('fixtureSetup', dependency)
                  : _attemptFixtureId('fixtureSetup', dependency, row),
            );
          }
          _put(builders, setup);
          builders[row.mainNodeId]!.dependencies.add(setupId);

          final teardownCase = resolved.teardown;
          if (teardownCase == null) continue;
          _put(
            builders,
            _NodeBuilder(
              nodeId: _attemptFixtureId('fixtureTeardown', fixtureId, row),
              entryId: row.entry.id,
              kind: CockpitSuitePlanNodeKind.fixtureTeardown,
              compiledCase: teardownCase,
              inputs: _nodeInputs(
                teardownCase,
                fixture.inputs,
                runtimeInputs,
                row.matrix,
              ),
              matrix: row.matrix,
              targetId: fixture.targetId ?? row.targetId,
              retry: suite.execution.retry,
              selected: row.selected,
              alwaysRun: true,
              cleanupGuardNodeId: setupId,
              caseNodeId: row.mainNodeId,
            )..dependencies.addAll(<String>{setupId, row.mainNodeId}),
          );
        }
        _wireAttemptFixtureTeardownOrder(row, closure, fixtures, builders);
      }
    }
  }

  void _wireAttemptFixtureTeardownOrder(
    _CaseRow row,
    Set<String> closure,
    Map<String, _ResolvedFixture> fixtures,
    Map<String, _NodeBuilder> builders,
  ) {
    for (final fixtureId in closure) {
      final fixture = fixtures[fixtureId]!.fixture;
      if (fixture.scope != CockpitTestFixtureScope.caseAttempt ||
          fixtures[fixtureId]!.teardown == null) {
        continue;
      }
      final teardown =
          builders[_attemptFixtureId('fixtureTeardown', fixtureId, row)]!;
      for (final dependentId in closure) {
        final dependent = fixtures[dependentId]!;
        if (dependent.fixture.scope == CockpitTestFixtureScope.caseAttempt &&
            dependent.fixture.dependsOn.contains(fixtureId) &&
            dependent.teardown != null) {
          teardown.dependencies.add(
            _attemptFixtureId('fixtureTeardown', dependentId, row),
          );
        }
      }
    }
  }

  void _addSuiteFixtures(
    CockpitTestSuite suite,
    Map<String, _ResolvedFixture> fixtures,
    Map<String, List<_CaseRow>> rowsByEntry,
    Map<String, _NodeBuilder> builders,
    Map<String, Object?> runtimeInputs,
  ) {
    final consumers = <String, Set<String>>{};
    for (final entry in suite.cases) {
      final closure = _fixtureClosure(entry.fixtures, fixtures);
      for (final fixtureId in closure) {
        if (fixtures[fixtureId]!.fixture.scope ==
            CockpitTestFixtureScope.suite) {
          consumers.putIfAbsent(fixtureId, () => <String>{}).add(entry.id);
        }
      }
    }
    for (final fixtureId in consumers.keys) {
      final resolved = fixtures[fixtureId]!;
      final fixture = resolved.fixture;
      final selected = consumers[fixtureId]!.any(
        (entryId) => rowsByEntry[entryId]!.any((row) => row.selected),
      );
      final setup = _NodeBuilder(
        nodeId: _suiteFixtureId('fixtureSetup', fixtureId),
        entryId: fixtureId,
        kind: CockpitSuitePlanNodeKind.fixtureSetup,
        compiledCase: resolved.setup,
        inputs: _nodeInputs(
          resolved.setup,
          fixture.inputs,
          runtimeInputs,
          const <String, Object?>{},
        ),
        matrix: const <String, Object?>{},
        targetId: fixture.targetId,
        retry: suite.execution.retry,
        selected: selected,
        alwaysRun: false,
      );
      setup.dependencies.addAll(
        fixture.dependsOn
            .where(consumers.containsKey)
            .map((id) => _suiteFixtureId('fixtureSetup', id)),
      );
      _put(builders, setup);
      final teardownCase = resolved.teardown;
      if (teardownCase == null) continue;
      final teardown = _NodeBuilder(
        nodeId: _suiteFixtureId('fixtureTeardown', fixtureId),
        entryId: fixtureId,
        kind: CockpitSuitePlanNodeKind.fixtureTeardown,
        compiledCase: teardownCase,
        inputs: _nodeInputs(
          teardownCase,
          fixture.inputs,
          runtimeInputs,
          const <String, Object?>{},
        ),
        matrix: const <String, Object?>{},
        targetId: fixture.targetId,
        retry: suite.execution.retry,
        selected: selected,
        alwaysRun: true,
        cleanupGuardNodeId: setup.nodeId,
      )..dependencies.add(setup.nodeId);
      for (final entryId in consumers[fixtureId]!) {
        teardown.dependencies.addAll(
          builders.values
              .where(
                (node) =>
                    node.entryId == entryId &&
                    (node.kind == CockpitSuitePlanNodeKind.testCase ||
                        node.kind == CockpitSuitePlanNodeKind.fixtureTeardown),
              )
              .map((node) => node.nodeId),
        );
      }
      _put(builders, teardown);
    }
    for (final fixtureId in consumers.keys) {
      final teardown = builders[_suiteFixtureId('fixtureTeardown', fixtureId)];
      if (teardown == null) continue;
      for (final dependentId in consumers.keys) {
        final dependent = fixtures[dependentId]!;
        if (dependent.fixture.dependsOn.contains(fixtureId) &&
            dependent.teardown != null) {
          teardown.dependencies.add(
            _suiteFixtureId('fixtureTeardown', dependentId),
          );
        }
      }
    }
  }

  void _wireCaseDependencies(
    CockpitTestSuite suite,
    Map<String, List<_CaseRow>> rowsByEntry,
    Map<String, _NodeBuilder> builders,
  ) {
    final fixtures = <String, CockpitTestFixture>{
      for (final fixture in suite.fixtures) fixture.id: fixture,
    };
    for (final rows in rowsByEntry.values) {
      for (final row in rows) {
        final boundary = builders[row.isolationNodeId]!;
        for (final dependency in row.entry.dependsOn) {
          for (final dependencyRow in rowsByEntry[dependency]!) {
            boundary.dependencies.addAll(
              _rowCompletionNodeIds(dependencyRow, fixtures),
            );
          }
        }
        for (final fixtureId in _fixtureClosureIds(
          row.entry.fixtures,
          fixtures,
        )) {
          if (fixtures[fixtureId]!.scope == CockpitTestFixtureScope.suite) {
            boundary.dependencies.add(
              _suiteFixtureId('fixtureSetup', fixtureId),
            );
          }
        }
      }
    }
  }

  Iterable<String> _rowCompletionNodeIds(
    _CaseRow row,
    Map<String, CockpitTestFixture> fixtures,
  ) {
    final teardownIds = <String>[
      for (final fixtureId in _fixtureClosureIds(row.entry.fixtures, fixtures))
        if (fixtures[fixtureId]!.scope == CockpitTestFixtureScope.caseAttempt &&
            fixtures[fixtureId]!.teardown != null)
          _attemptFixtureId('fixtureTeardown', fixtureId, row),
    ];
    return <String>[row.mainNodeId, ...teardownIds];
  }

  void _put(Map<String, _NodeBuilder> builders, _NodeBuilder builder) {
    if (builders.putIfAbsent(builder.nodeId, () => builder) != builder) {
      throw FormatException(
        'Suite generated duplicate node ${builder.nodeId}.',
      );
    }
  }
}

final class _ResolvedFixture {
  const _ResolvedFixture({
    required this.fixture,
    required this.setup,
    required this.teardown,
  });

  final CockpitTestFixture fixture;
  final CockpitCompiledTestCase setup;
  final CockpitCompiledTestCase? teardown;
}

final class _BuiltNodes {
  const _BuiltNodes({required this.nodes, required this.attemptNodes});

  final List<CockpitSuitePlanNode> nodes;
  final List<CockpitSuitePlanNode> attemptNodes;
}

final class _CaseRow {
  const _CaseRow({
    required this.entry,
    required this.isolationNodeId,
    required this.mainNodeId,
    required this.matrix,
    required this.targetId,
    required this.selected,
  });

  final CockpitTestSuiteEntry entry;
  final String isolationNodeId;
  final String mainNodeId;
  final Map<String, Object?> matrix;
  final String? targetId;
  final bool selected;
}

final class _NodeBuilder {
  _NodeBuilder({
    required this.nodeId,
    required this.entryId,
    required this.kind,
    required this.compiledCase,
    required this.inputs,
    required this.matrix,
    required this.targetId,
    required this.retry,
    required this.selected,
    required this.alwaysRun,
    this.isolation,
    this.cleanupGuardNodeId,
    this.caseNodeId,
  });

  final String nodeId;
  final String entryId;
  final CockpitSuitePlanNodeKind kind;
  final CockpitCompiledTestCase compiledCase;
  final Map<String, Object?> inputs;
  final Map<String, Object?> matrix;
  final String? targetId;
  final CockpitTestSuiteRetryPolicy retry;
  final bool selected;
  final bool alwaysRun;
  final CockpitTestSuiteIsolation? isolation;
  final String? cleanupGuardNodeId;
  final String? caseNodeId;
  final Set<String> dependencies = <String>{};

  CockpitSuitePlanNode build({Iterable<String>? dependencies}) =>
      CockpitSuitePlanNode(
        nodeId: nodeId,
        entryId: entryId,
        kind: kind,
        compiledCase: compiledCase,
        inputs: Map<String, Object?>.unmodifiable(inputs),
        matrix: Map<String, Object?>.unmodifiable(matrix),
        targetId: targetId,
        dependencies: dependencies ?? this.dependencies,
        retry: retry,
        selected: selected,
        alwaysRun: alwaysRun,
        isolation: isolation,
        cleanupGuardNodeId: cleanupGuardNodeId,
        caseNodeId: caseNodeId,
      );
}

Set<String> _fixtureClosure(
  Iterable<String> roots,
  Map<String, _ResolvedFixture> fixtures,
) => _fixtureClosureIds(roots, <String, CockpitTestFixture>{
  for (final entry in fixtures.entries) entry.key: entry.value.fixture,
});

Set<String> _fixtureClosureIds(
  Iterable<String> roots,
  Map<String, CockpitTestFixture> fixtures,
) {
  final result = <String>{};
  void visit(String id) {
    if (!result.add(id)) return;
    for (final dependency in fixtures[id]!.dependsOn) {
      visit(dependency);
    }
  }

  for (final root in roots) {
    visit(root);
  }
  return result;
}

String _attemptFixtureId(String kind, String fixtureId, _CaseRow row) =>
    _nodeId(kind, fixtureId, <String, Object?>{
      'entryId': row.entry.id,
      'matrix': row.matrix,
      if (row.targetId != null) 'targetId': row.targetId,
    });

String _suiteFixtureId(String kind, String fixtureId) =>
    _nodeId(kind, fixtureId, const <String, Object?>{'scope': 'suite'});

String _nodeId(String kind, String owner, Object? identity) {
  final digest = sha256
      .convert(utf8.encode('$kind\u0000$owner\u0000${_canonical(identity)}'))
      .toString();
  return '${kind}_${digest.substring(0, 24)}';
}

Set<String> _inputNames(CockpitCompiledTestCase compiled) => <String>{
  for (final entry in compiled.testCase.variables.entries)
    if (entry.value.source == CockpitTestVariableSource.input) entry.key,
};

Map<String, Object?> _bindMatrix(
  Map<String, Object?> input,
  Map<String, Object?> matrix,
) => Map<String, Object?>.unmodifiable(<String, Object?>{
  for (final entry in input.entries)
    entry.key: _replaceMatrix(entry.value, matrix, '\$.inputs.${entry.key}'),
});

Object? _replaceMatrix(
  Object? value,
  Map<String, Object?> matrix,
  String path,
) {
  if (value is Map<Object?, Object?> &&
      value.length == 1 &&
      value.containsKey(r'$matrix')) {
    final axis = value[r'$matrix'];
    if (axis is! String || !matrix.containsKey(axis)) {
      throw FormatException('Unknown matrix binding at $path.');
    }
    return matrix[axis];
  }
  if (value is Map<Object?, Object?>) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: _replaceMatrix(
          entry.value,
          matrix,
          '$path.${entry.key}',
        ),
    };
  }
  if (value is List<Object?>) {
    return <Object?>[
      for (var index = 0; index < value.length; index += 1)
        _replaceMatrix(value[index], matrix, '$path[$index]'),
    ];
  }
  return value;
}

String _canonical(Object? value) => jsonEncode(_sortJson(value));

Object? _sortJson(Object? value) => switch (value) {
  Map<Object?, Object?> map => <String, Object?>{
    for (final key in map.keys.cast<String>().toList()..sort())
      key: _sortJson(map[key]),
  },
  List<Object?> list => list.map(_sortJson).toList(growable: false),
  _ => value,
};
