import 'package:flutter_cockpit/flutter_cockpit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CockpitSnapshotProfile round-trips through json', () {
    expect(
      CockpitSnapshotProfile.fromJson('live'),
      CockpitSnapshotProfile.live,
    );
    expect(
      CockpitSnapshotProfile.fromJson('baseline'),
      CockpitSnapshotProfile.baseline,
    );
    expect(
      CockpitSnapshotProfile.fromJson('investigate'),
      CockpitSnapshotProfile.investigate,
    );
    expect(
      CockpitSnapshotProfile.fromJson('forensic'),
      CockpitSnapshotProfile.forensic,
    );
  });

  test('CockpitSnapshotOptions preserves defaults and overrides', () {
    const live = CockpitSnapshotOptions();
    expect(live.profile, CockpitSnapshotProfile.live);
    expect(live.query, isNull);
    expect(live.maxTargets, 25);
    expect(live.maxAncestorsPerTarget, 0);
    expect(live.maxPropertiesPerTarget, 0);
    expect(live.includeStyleDetails, isFalse);
    expect(live.includeDiagnosticProperties, isFalse);
    expect(live.artifact, CockpitSnapshotArtifactMode.inline);
    expect(live.includeRebuildActivity, isFalse);
    expect(live.maxRebuildEntries, 8);
    expect(live.networkQuery, const CockpitNetworkQuery());

    final forensic = CockpitSnapshotOptions(
      profile: CockpitSnapshotProfile.forensic,
      query: 'Submit',
      maxTargets: 5,
      maxAncestorsPerTarget: 4,
      maxPropertiesPerTarget: 10,
      includeStyleDetails: true,
      includeDiagnosticProperties: true,
      artifact: CockpitSnapshotArtifactMode.large,
      tree: const CockpitWidgetTreeOptions.full(),
      includeRebuildActivity: true,
      maxRebuildEntries: 12,
      includeNetworkActivity: true,
      networkQuery: const CockpitNetworkQuery(
        method: 'POST',
        uriContains: '/sync',
        onlyFailures: true,
        statusCodeAtLeast: 500,
      ),
    );

    final roundTrip = CockpitSnapshotOptions.fromJson(forensic.toJson());
    expect(roundTrip, forensic);
  });

  test('rich snapshot payload preserves structured diagnostic fields', () {
    final snapshot = CockpitSnapshot(
      routeName: '/checkout',
      diagnosticLevel: CockpitSnapshotProfile.investigate,
      truncated: true,
      diagnosticsArtifactRef: const CockpitArtifactRef(
        role: 'diagnostics',
        relativePath: 'diagnostics/step-001.json',
      ),
      treeArtifactRef: const CockpitArtifactRef(
        role: 'widget-tree',
        relativePath: 'trees/step-001.json',
      ),
      tree: CockpitWidgetTree(
        profile: CockpitWidgetTreeProfile.full,
        total: 2,
        visible: 1,
        truncated: false,
        nodes: <CockpitWidgetNode>[
          CockpitWidgetNode(
            node: 1,
            loc: '/scaffold/textbutton',
            parent: 0,
            depth: 1,
            type: 'TextButton',
            element: 'StatefulElement',
            render: 'RenderSemanticsAnnotations',
            text: 'Submit',
            visible: true,
            offstage: false,
            bounds: const CockpitWidgetBounds(
              x: 16,
              y: 320,
              width: 120,
              height: 48,
            ),
            actions: const <CockpitCommandType>[CockpitCommandType.tap],
          ),
        ],
      ),
      summary: const CockpitSnapshotSummary(
        visibleTargetCount: 3,
        targetsWithCockpitIdCount: 2,
        targetsWithTextCount: 3,
        styleDetailsIncluded: true,
        diagnosticPropertiesIncluded: true,
        ancestorSummariesIncluded: true,
        rebuildSummaryIncluded: true,
        accessibilitySummaryIncluded: true,
      ),
      focus: const CockpitFocusSnapshot(
        hasPrimaryFocus: true,
        primaryFocusDebugLabel: 'search-field',
        primaryFocusWidgetType: 'TextField',
        primaryFocusElementType: 'StatefulElement',
        primaryFocusLabel: 'Search',
        isTextInputFocus: true,
      ),
      rebuild: const CockpitRebuildSnapshot(
        totalRebuildCount: 8,
        uniqueElementCount: 2,
        capturedEntryCount: 1,
        truncated: true,
        entries: <CockpitRebuildEntry>[
          CockpitRebuildEntry(
            signature: 'checkout.submit',
            routeName: '/checkout',
            typeName: 'TextButton',
            rebuildCount: 8,
            builtOnceCount: 1,
            textPreview: 'Submit',
          ),
        ],
      ),
      visibleTargets: <CockpitSnapshotTarget>[
        CockpitSnapshotTarget(
          registrationId: 'checkout.submit',
          cockpitId: 'submit_button',
          keyValue: 'submit-key',
          text: 'Submit',
          typeName: 'ElevatedButton',
          routeName: '/checkout',
          supportedCommands: const <CockpitCommandType>[CockpitCommandType.tap],
          layout: const CockpitSnapshotLayout(
            width: 120,
            height: 48,
            dx: 16,
            dy: 320,
            constraintsSummary: 'tight 120x48',
          ),
          content: const CockpitSnapshotContent(
            displayLabel: 'Submit',
            textPreview: 'Submit',
          ),
          style: const CockpitSnapshotStyle(
            textColor: '#FFFFFFFF',
            backgroundColor: '#FF0000FF',
            fontSize: 16,
            fontWeight: 'w600',
            borderSummary: '1px solid #FFFFFFFF',
            shadowSummary: 'blur:4 offset:(0,2)',
          ),
          ancestors: const <CockpitSnapshotAncestor>[
            CockpitSnapshotAncestor(
              typeName: 'Column',
              cockpitId: 'checkout_layout',
              textPreview: null,
            ),
          ],
          diagnosticProperties: const <CockpitDiagnosticProperty>[
            CockpitDiagnosticProperty(
              name: 'padding',
              value: 'EdgeInsets.all(16.0)',
              category: CockpitDiagnosticCategory.spacing,
            ),
          ],
        ),
      ],
    );

    final roundTrip = CockpitSnapshot.fromJson(snapshot.toJson());
    expect(roundTrip, snapshot);
    expect(
      roundTrip.visibleTargets.single.layout?.constraintsSummary,
      'tight 120x48',
    );
    expect(roundTrip.visibleTargets.single.keyValue, 'submit-key');
    expect(
      roundTrip.visibleTargets.single.diagnosticProperties.single.category,
      CockpitDiagnosticCategory.spacing,
    );
    expect(roundTrip.summary?.ancestorSummariesIncluded, isTrue);
    expect(roundTrip.focus?.hasPrimaryFocus, isTrue);
    expect(roundTrip.focus?.primaryFocusLabel, 'Search');
    expect(roundTrip.focus?.isTextInputFocus, isTrue);
    expect(
      roundTrip.diagnosticsArtifactRef?.relativePath,
      'diagnostics/step-001.json',
    );
    expect(roundTrip.treeArtifactRef?.relativePath, 'trees/step-001.json');
    expect(roundTrip.tree?.nodes.single.text, 'Submit');
  });
}
