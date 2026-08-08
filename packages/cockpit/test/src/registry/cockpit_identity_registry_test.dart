import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/foundation/cockpit_canonical_paths.dart';
import 'package:cockpit/src/foundation/cockpit_filesystem_identity.dart';
import 'package:cockpit/src/foundation/cockpit_home.dart';
import 'package:cockpit/src/foundation/cockpit_ids.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/foundation/cockpit_windows_directory_authority.dart';
import 'package:cockpit/src/infrastructure/cockpit_clock.dart';
import 'package:cockpit/src/registry/cockpit_allowed_root_registry.dart';
import 'package:cockpit/src/registry/cockpit_directory_ancestor_policy.dart';
import 'package:cockpit/src/registry/cockpit_directory_attestation.dart';
import 'package:cockpit/src/registry/cockpit_registry_database.dart';
import 'package:cockpit/src/registry/cockpit_registry_models.dart';
import 'package:cockpit/src/registry/cockpit_registry_records.dart';
import 'package:cockpit/src/registry/cockpit_scoped_reference_index.dart';
import 'package:cockpit/src/registry/cockpit_workspace_marker_store.dart';
import 'package:cockpit/src/registry/cockpit_workspace_registry.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('allowed roots and confinement', () {
    test(
      'canonicalizes, rejects overlap, and confines symlink targets',
      () async {
        if (Platform.isWindows) return;
        final fixture = await _RegistryFixture.create();
        addTearDown(fixture.dispose);
        final rootDirectory = await fixture.directory('root');
        final nested = await Directory(
          p.join(rootDirectory.path, 'nested'),
        ).create();
        final outside = await fixture.directory('outside');
        final root = await fixture.roots.register(rootDirectory.path);
        final same = await fixture.roots.register(rootDirectory.path);
        expect(same.rootId, root.rootId);
        expect(root.filesystemIdentity, startsWith('posix:'));
        expect(root.rootId, matches(r'^rt-[A-Za-z0-9]{16}$'));
        await expectLater(
          fixture.roots.register(nested.path),
          throwsRegistry('rootOverlap'),
        );
        final link = Link(p.join(rootDirectory.path, 'outside-link'));
        await link.create(outside.path);
        await expectLater(
          fixture.workspaces.register(rootId: root.rootId, path: link.path),
          throwsRegistry('workspaceOutsideRoot'),
        );
        final prefixSibling = await fixture.directory('root-sibling');
        await expectLater(
          fixture.workspaces.register(
            rootId: root.rootId,
            path: prefixSibling.path,
          ),
          throwsRegistry('workspaceOutsideRoot'),
        );
        if (!Platform.isWindows) {
          final unsafe = await fixture.directory('unsafe');
          final chmod = await Process.run('chmod', <String>[
            '777',
            unsafe.path,
          ]);
          expect(chmod.exitCode, 0);
          await expectLater(
            fixture.roots.register(unsafe.path),
            throwsRegistry('rootUnsafePermissions'),
          );
        }
      },
    );
  });

  group('directory authority races', () {
    test('Windows ACL probes use SID-native access rules', () {
      for (final script in <String>[
        cockpitWindowsSecurityInspectionPowerShell,
        cockpitWindowsDirectoryAuthorityPowerShell,
      ]) {
        expect(
          script,
          contains(r'GetOwner([System.Security.Principal.SecurityIdentifier])'),
        );
        expect(script, contains(r'GetAccessRules('));
        expect(
          script,
          contains(r'[System.Security.Principal.SecurityIdentifier]'),
        );
        expect(script, contains(r'$rule.IdentityReference.Value'));
        expect(script, isNot(contains('.Translate(')));
      }
    });

    test('rejects identity changes during security inspection', () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpit-attestation-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final identities = _MutableIdentityProvider('identity-before');
      final metadata = _MutatingMetadataProvider(() {
        identities.value = 'identity-after';
      });
      final attestor = CockpitDirectoryAttestor(
        directoryResolver: const CockpitCanonicalDirectoryResolver(),
        identityProvider: identities,
        securityInspector: CockpitDirectorySecurityInspector(
          platform: CockpitHostPlatform.linux,
          metadataProvider: metadata,
        ),
        ancestorPolicy: const _AllowAllAncestorPolicy(),
        lexicalPaths: CockpitLexicalPaths(
          Platform.isWindows
              ? CockpitPathStyle.windows
              : CockpitPathStyle.posix,
        ),
        requireStrongIdentity: true,
      );

      await expectLater(
        attestor.attest(temporary.path, CockpitDirectoryAttestationScope.root),
        throwsRegistry('directoryAttestationChanged'),
      );
    });

    test(
      'system POSIX attestor compares coherent metadata snapshots',
      () async {
        final temporary = await Directory.systemTemp.createTemp(
          'cockpit-system-attestation-',
        );
        addTearDown(() => temporary.delete(recursive: true));
        final metadata = _SequenceMetadataProvider(<CockpitPosixMetadata>[
          const CockpitPosixMetadata(
            device: 7,
            inode: 11,
            ownerUserId: 1000,
            mode: 448,
          ),
          const CockpitPosixMetadata(
            device: 7,
            inode: 11,
            ownerUserId: 1000,
            mode: 384,
          ),
        ]);
        const resolver = CockpitCanonicalDirectoryResolver();
        final canonicalPath = (await resolver.resolve(temporary.path)).path;
        final attestor = CockpitSystemDirectoryAttestor(
          platform: CockpitHostPlatform.linux,
          directoryResolver: resolver,
          metadataProvider: metadata,
          ancestorPolicy: const _AllowAllAncestorPolicy(),
          lexicalPaths: const CockpitLexicalPaths(CockpitPathStyle.posix),
        );

        await expectLater(
          attestor.attest(
            temporary.path,
            CockpitDirectoryAttestationScope.root,
          ),
          throwsRegistry('directoryAttestationChanged'),
        );
        expect(metadata.paths, <String>[canonicalPath, canonicalPath]);
      },
    );

    test('rejects a non-sticky writable ancestor', () async {
      if (Platform.isWindows) return;
      final fixture = await _RegistryFixture.create();
      addTearDown(fixture.dispose);
      final parent = await fixture.directory('unsafe-parent');
      final target = await Directory(p.join(parent.path, 'target')).create();
      final chmod = await Process.run('chmod', <String>['777', parent.path]);
      expect(chmod.exitCode, 0);

      await expectLater(
        fixture.roots.register(target.path),
        throwsRegistry('directoryAncestorUnsafePermissions'),
      );
    });

    test('accepts a trusted child below a sticky temporary ancestor', () async {
      if (Platform.isWindows) return;
      final directory = await Directory(
        p.join(
          '/tmp',
          'cockpit-sticky-$pid-${DateTime.now().microsecondsSinceEpoch}',
        ),
      ).create();
      addTearDown(() => directory.delete(recursive: true));
      final platform = Platform.isMacOS
          ? CockpitHostPlatform.macos
          : CockpitHostPlatform.linux;
      final metadata = CockpitSystemPosixMetadataProvider(platform);
      final canonical = await const CockpitCanonicalDirectoryResolver().resolve(
        directory.path,
      );

      await CockpitSystemDirectoryAncestorPolicy(
        platform: platform,
        metadataProvider: metadata,
      ).verify(canonical.path);
    });

    test(
      'accepts a trusted Windows workspace below a writable drive root',
      () async {
        final security = _MappedWindowsSecurityProvider(
          const <String, CockpitDirectorySecurity>{
            r'C:\': CockpitDirectorySecurity(
              posixApplicable: false,
              ownerVerified: false,
              ownerTrusted: true,
              unsafeWritable: true,
            ),
            r'C:\Users': CockpitDirectorySecurity(
              posixApplicable: false,
              ownerVerified: false,
              ownerTrusted: true,
              unsafeWritable: false,
            ),
            r'C:\Users\runneradmin': CockpitDirectorySecurity(
              posixApplicable: false,
              ownerVerified: true,
              ownerTrusted: true,
              unsafeWritable: false,
            ),
          },
        );

        await CockpitSystemDirectoryAncestorPolicy(
          platform: CockpitHostPlatform.windows,
          metadataProvider: const _MappedMetadataProvider(
            currentUserId: 1000,
            values: <String, CockpitPosixMetadata>{},
          ),
          windowsSecurityProvider: security,
        ).verify(r'C:\Users\runneradmin\workspace');

        expect(security.paths, <String>[
          r'C:\',
          r'C:\Users',
          r'C:\Users\runneradmin',
        ]);
      },
    );

    test('rejects an ancestor owned by an untrusted user', () async {
      final metadata = _MappedMetadataProvider(
        currentUserId: 1000,
        values: const <String, CockpitPosixMetadata>{
          '/': CockpitPosixMetadata(
            device: 1,
            inode: 1,
            ownerUserId: 0,
            mode: 493,
          ),
          '/trusted': CockpitPosixMetadata(
            device: 1,
            inode: 2,
            ownerUserId: 0,
            mode: 493,
          ),
          '/trusted/untrusted': CockpitPosixMetadata(
            device: 1,
            inode: 3,
            ownerUserId: 2000,
            mode: 493,
          ),
        },
      );

      await expectLater(
        CockpitSystemDirectoryAncestorPolicy(
          platform: CockpitHostPlatform.linux,
          metadataProvider: metadata,
        ).verify('/trusted/untrusted/target'),
        throwsRegistry('directoryAncestorOwnerUntrusted'),
      );
    });

    test('rejects a stored root replaced before workspace admission', () async {
      final controller = _ControllableDirectoryAttestor();
      final fixture = await _RegistryFixture.create(
        decorateDirectoryAttestor: controller.bind,
      );
      addTearDown(fixture.dispose);
      final rootDirectory = await fixture.directory('root');
      final root = await fixture.roots.register(rootDirectory.path);
      expect(
        controller.calls
            .where((scope) => scope == CockpitDirectoryAttestationScope.root)
            .length,
        1,
      );
      controller.interceptNext(
        CockpitDirectoryAttestationScope.root,
        before: () async {
          await rootDirectory.delete(recursive: true);
          await rootDirectory.create();
        },
        transform: _changedAttestation,
      );

      await expectLater(
        fixture.workspaces.register(
          rootId: root.rootId,
          path: rootDirectory.path,
        ),
        throwsRegistry('rootIdentityChanged'),
      );
      expect((await fixture.database.read()).workspaces, isEmpty);
    });

    test(
      'does not update registry when workspace changes during marker write',
      () async {
        final controller = _ControllableDirectoryAttestor();
        final fixture = await _RegistryFixture.create(
          decorateDirectoryAttestor: controller.bind,
        );
        addTearDown(fixture.dispose);
        final rootDirectory = await fixture.directory('root');
        final root = await fixture.roots.register(rootDirectory.path);
        final workspaceDirectory = await Directory(
          p.join(rootDirectory.path, 'workspace'),
        ).create();
        final workspace = await fixture.workspaces.register(
          rootId: root.rootId,
          path: workspaceDirectory.path,
        );
        controller.interceptNext(
          CockpitDirectoryAttestationScope.workspace,
          skipMatches: 6,
          before: () async {
            await workspaceDirectory.delete(recursive: true);
            await workspaceDirectory.create();
          },
          transform: _changedAttestation,
        );

        await expectLater(
          fixture.workspaces.rebindProject(
            workspaceId: workspace.workspaceId,
            expectedProjectId: workspace.projectId,
            projectId: 'project_after_race',
          ),
          throwsRegistry('directoryAttestationChanged'),
        );
        final state = await fixture.database.read();
        expect(state.workspaces.single.projectId, workspace.projectId);
        expect(state.markerMutations, hasLength(1));
      },
    );
  });

  group('workspace identity', () {
    test(
      'handles idempotency, move, copy, conflicts, and explicit rebind',
      () async {
        final fixture = await _RegistryFixture.create();
        addTearDown(fixture.dispose);
        final rootDirectory = await fixture.directory('root');
        final root = await fixture.roots.register(rootDirectory.path);
        final original = await Directory(
          p.join(rootDirectory.path, 'original'),
        ).create();
        final created = await fixture.workspaces.register(
          rootId: root.rootId,
          path: original.path,
        );
        expect(
          created.disposition,
          CockpitWorkspaceRegistrationDisposition.created,
        );
        expect(
          File(
            p.join(original.path, '.dart_tool/cockpit/workspace.json'),
          ).existsSync(),
          isTrue,
        );
        final existing = await fixture.workspaces.register(
          rootId: root.rootId,
          path: original.path,
        );
        expect(existing.workspaceId, created.workspaceId);
        expect(
          existing.disposition,
          CockpitWorkspaceRegistrationDisposition.existing,
        );

        final movedPath = p.join(rootDirectory.path, 'moved');
        final movedDirectory = await original.rename(movedPath);
        final moved = await fixture.workspaces.register(
          rootId: root.rootId,
          path: movedDirectory.path,
        );
        expect(moved.workspaceId, created.workspaceId);
        expect(moved.checkoutId, created.checkoutId);
        expect(
          moved.disposition,
          CockpitWorkspaceRegistrationDisposition.moved,
        );

        final copyDirectory = Directory(p.join(rootDirectory.path, 'copy'));
        await _copyDirectory(movedDirectory, copyDirectory);
        final copied = await fixture.workspaces.register(
          rootId: root.rootId,
          path: copyDirectory.path,
        );
        expect(
          copied.disposition,
          CockpitWorkspaceRegistrationDisposition.copied,
        );
        expect(copied.projectId, created.projectId);
        expect(copied.workspaceId, isNot(created.workspaceId));
        expect(copied.checkoutId, isNot(created.checkoutId));

        final conflictDirectory = Directory(
          p.join(rootDirectory.path, 'conflict'),
        );
        await _copyDirectory(movedDirectory, conflictDirectory);
        final conflictMarker = File(
          p.join(conflictDirectory.path, '.dart_tool/cockpit/workspace.json'),
        );
        final originalMarkerSource = await conflictMarker.readAsString();
        final conflictJson =
            jsonDecode(originalMarkerSource) as Map<String, Object?>;
        conflictJson['projectId'] = 'project_conflict';
        await conflictMarker.writeAsString(jsonEncode(conflictJson));
        await expectLater(
          fixture.workspaces.register(
            rootId: root.rootId,
            path: conflictDirectory.path,
          ),
          throwsRegistry('ambiguousWorkspace'),
        );
        await conflictMarker.writeAsString(originalMarkerSource);
        final rebound = await fixture.workspaces.explicitRebind(
          workspaceId: created.workspaceId,
          expectedCheckoutId: created.checkoutId,
          rootId: root.rootId,
          path: conflictDirectory.path,
        );
        expect(
          rebound.disposition,
          CockpitWorkspaceRegistrationDisposition.copied,
        );
        expect(rebound.projectId, created.projectId);
        expect(rebound.workspaceId, isNot(created.workspaceId));
      },
    );

    test('project rebind intent recovers both interruption points', () async {
      final fixture = await _RegistryFixture.create();
      addTearDown(fixture.dispose);
      final rootDirectory = await fixture.directory('root');
      final root = await fixture.roots.register(rootDirectory.path);
      final workspaceDirectory = await Directory(
        p.join(rootDirectory.path, 'workspace'),
      ).create();
      final workspace = await fixture.workspaces.register(
        rootId: root.rootId,
        path: workspaceDirectory.path,
      );
      await fixture.addProjectIntent(
        workspace.workspaceId,
        workspace.projectId,
        'project_authored_one',
      );
      await fixture.workspaces.list();
      expect(
        (await fixture.marker(workspaceDirectory.path)).projectId,
        'project_authored_one',
      );
      expect(
        (await fixture.workspaces.get(workspace.workspaceId)).projectId,
        'project_authored_one',
      );

      await fixture.addProjectIntent(
        workspace.workspaceId,
        'project_authored_one',
        'project_authored_two',
      );
      final marker = await fixture.marker(workspaceDirectory.path);
      await fixture.markerStore.write(
        workspaceDirectory.path,
        CockpitWorkspaceMarker(
          workspaceId: marker.workspaceId,
          projectId: 'project_authored_two',
          checkoutId: marker.checkoutId,
          createdAt: marker.createdAt,
        ),
      );
      await fixture.workspaces.list();
      expect(
        (await fixture.workspaces.get(workspace.workspaceId)).projectId,
        'project_authored_two',
      );
      final rebound = await fixture.workspaces.rebindProject(
        workspaceId: workspace.workspaceId,
        expectedProjectId: 'project_authored_two',
        projectId: 'project_authored_final',
      );
      expect(
        rebound.disposition,
        CockpitWorkspaceRegistrationDisposition.reboundProject,
      );
      expect(
        (await fixture.marker(workspaceDirectory.path)).projectId,
        'project_authored_final',
      );
    });

    test(
      'rejects a registered path whose filesystem identity changed',
      () async {
        final fixture = await _RegistryFixture.create();
        addTearDown(fixture.dispose);
        final rootDirectory = await fixture.directory('root');
        await fixture.roots.register(rootDirectory.path);
        await rootDirectory.delete(recursive: true);
        await rootDirectory.create();
        await expectLater(
          fixture.roots.register(rootDirectory.path),
          throwsRegistry('rootIdentityChanged'),
        );
      },
    );

    test('fails closed when a live copy source identity changed', () async {
      final fixture = await _RegistryFixture.create();
      addTearDown(fixture.dispose);
      final rootDirectory = await fixture.directory('root');
      final root = await fixture.roots.register(rootDirectory.path);
      final source = await Directory(
        p.join(rootDirectory.path, 'source'),
      ).create();
      await fixture.workspaces.register(rootId: root.rootId, path: source.path);
      final copied = Directory(p.join(rootDirectory.path, 'copied'));
      await _copyDirectory(source, copied);
      await source.delete(recursive: true);
      await source.create();
      await expectLater(
        fixture.workspaces.register(rootId: root.rootId, path: copied.path),
        throwsRegistry('workspaceSourceIdentityChanged'),
      );
    });

    test(
      'rejects same-path replacement and unproven missing-source move',
      () async {
        final fixture = await _RegistryFixture.create();
        addTearDown(fixture.dispose);
        final rootDirectory = await fixture.directory('root');
        final root = await fixture.roots.register(rootDirectory.path);
        final samePath = await Directory(
          p.join(rootDirectory.path, 'same-path'),
        ).create();
        final registered = await fixture.workspaces.register(
          rootId: root.rootId,
          path: samePath.path,
        );
        final marker = await fixture.marker(samePath.path);
        await samePath.delete(recursive: true);
        await samePath.create();
        await fixture.markerStore.write(samePath.path, marker);
        await expectLater(
          fixture.workspaces.register(rootId: root.rootId, path: samePath.path),
          throwsRegistry('workspaceIdentityChanged'),
        );
        await expectLater(
          fixture.workspaces.explicitRebind(
            workspaceId: registered.workspaceId,
            expectedCheckoutId: registered.checkoutId,
            rootId: root.rootId,
            path: samePath.path,
          ),
          throwsRegistry('workspaceRebindIdentityMismatch'),
        );
        final rebound = await fixture.workspaces.explicitRebind(
          workspaceId: registered.workspaceId,
          expectedCheckoutId: registered.checkoutId,
          rootId: root.rootId,
          path: samePath.path,
          allowIdentityChange: true,
        );
        expect(
          rebound.disposition,
          CockpitWorkspaceRegistrationDisposition.existing,
        );
        expect(
          (await fixture.workspaces.register(
            rootId: root.rootId,
            path: samePath.path,
          )).workspaceId,
          registered.workspaceId,
        );

        final source = await Directory(
          p.join(rootDirectory.path, 'source'),
        ).create();
        await fixture.workspaces.register(
          rootId: root.rootId,
          path: source.path,
        );
        final staleCopy = Directory(p.join(rootDirectory.path, 'stale-copy'));
        await _copyDirectory(source, staleCopy);
        await source.delete(recursive: true);
        await expectLater(
          fixture.workspaces.register(
            rootId: root.rootId,
            path: staleCopy.path,
          ),
          throwsRegistry('workspaceMoveRequiresRebind'),
        );
      },
    );

    test('rejects marker parents and files that traverse symlinks', () async {
      if (Platform.isWindows) return;
      final fixture = await _RegistryFixture.create();
      addTearDown(fixture.dispose);
      final rootDirectory = await fixture.directory('root');
      final root = await fixture.roots.register(rootDirectory.path);
      final workspace = await Directory(
        p.join(rootDirectory.path, 'workspace'),
      ).create();
      final outside = await fixture.directory('outside-marker');
      await Link(p.join(workspace.path, '.dart_tool')).create(outside.path);
      await expectLater(
        fixture.workspaces.register(rootId: root.rootId, path: workspace.path),
        throwsRegistry('workspaceMarkerUnsafePath'),
      );
      expect(
        File(p.join(outside.path, 'cockpit', 'workspace.json')).existsSync(),
        isFalse,
      );
    });
  });

  group('lifecycle and scoped references', () {
    test('enforces workspace scope and root removal policies', () async {
      final fixture = await _RegistryFixture.create();
      addTearDown(fixture.dispose);
      final rootDirectory = await fixture.directory('root');
      final root = await fixture.roots.register(rootDirectory.path);
      final first = await fixture.registerChild(root, rootDirectory, 'first');
      final second = await fixture.registerChild(root, rootDirectory, 'second');
      final third = await fixture.registerChild(root, rootDirectory, 'third');
      await fixture.references.setSession(first.workspaceId, 'session_shared');
      await fixture.references.setSession(second.workspaceId, 'session_shared');
      await fixture.references.setSession(first.workspaceId, 'session_unique');
      expect(
        (await fixture.references.resolveSession(
          first.workspaceId,
          'session_shared',
        )).workspaceId,
        first.workspaceId,
      );
      await expectLater(
        fixture.references.resolveSession(second.workspaceId, 'session_unique'),
        throwsRegistry('crossWorkspaceReference'),
      );
      await expectLater(
        fixture.references.resolveSession(third.workspaceId, 'session_shared'),
        throwsRegistry('ambiguousReference'),
      );
      await fixture.references.setRun(
        workspaceId: first.workspaceId,
        runId: 'run_first',
        active: true,
        retained: false,
        artifactCount: 0,
      );
      await fixture.references.setRun(
        workspaceId: second.workspaceId,
        runId: 'run_second',
        active: false,
        retained: false,
        artifactCount: 0,
      );
      expect(
        (await fixture.references.resolveLatestRun(first.workspaceId)).runId,
        'run_first',
      );
      expect(
        (await fixture.references.resolveLatestRun(second.workspaceId)).runId,
        'run_second',
      );
      await expectLater(
        fixture.references.clearLatestRun(
          second.workspaceId,
          expectedRunId: 'run_wrong',
        ),
        throwsRegistry('latestRunConflict'),
      );
      expect(
        await fixture.references.clearLatestRun(
          second.workspaceId,
          expectedRunId: 'run_second',
        ),
        isTrue,
      );
      await expectLater(
        fixture.references.resolveLatestRun(second.workspaceId),
        throwsRegistry('referenceNotFound'),
      );
      await expectLater(
        fixture.roots.remove(root.rootId),
        throwsRegistry('rootInUse'),
      );
      await expectLater(
        fixture.roots.remove(
          root.rootId,
          policy: CockpitRemovalPolicy.drain,
          drainTimeout: const Duration(milliseconds: 10),
        ),
        throwsRegistry('rootInUse'),
      );
      expect(
        (await fixture.roots.get(root.rootId)).state,
        CockpitRootState.draining,
      );
      final forced = await fixture.roots.remove(
        root.rootId,
        policy: CockpitRemovalPolicy.force,
      );
      expect(forced.tombstoneRetained, isFalse);
      expect(await fixture.roots.list(), isEmpty);
      expect(await fixture.workspaces.list(), isEmpty);
      expect(rootDirectory.existsSync(), isTrue);
      for (final name in <String>['first', 'second', 'third']) {
        expect(
          Directory(p.join(rootDirectory.path, name)).existsSync(),
          isTrue,
        );
        expect(
          File(
            p.join(
              rootDirectory.path,
              name,
              '.dart_tool/cockpit/workspace.json',
            ),
          ).existsSync(),
          isTrue,
        );
      }
      final drainRootDirectory = await fixture.directory('drain-root');
      final drainRoot = await fixture.roots.register(drainRootDirectory.path);
      await fixture.registerChild(drainRoot, drainRootDirectory, 'workspace');
      final drained = await fixture.roots.remove(
        drainRoot.rootId,
        policy: CockpitRemovalPolicy.drain,
      );
      expect(drained.tombstoneRetained, isFalse);
      expect(drainRootDirectory.existsSync(), isTrue);
    });

    test(
      'retains and releases non-authorizing tombstones without deletion',
      () async {
        final fixture = await _RegistryFixture.create();
        addTearDown(fixture.dispose);
        final rootDirectory = await fixture.directory('root');
        final root = await fixture.roots.register(rootDirectory.path);
        final workspace = await fixture.registerChild(
          root,
          rootDirectory,
          'workspace',
        );
        final evidence = File(p.join(workspace.canonicalPath, 'evidence.bin'));
        await evidence.writeAsBytes(<int>[1, 2, 3]);
        await fixture.references.setRun(
          workspaceId: workspace.workspaceId,
          runId: 'run_retained',
          active: true,
          retained: true,
          artifactCount: 2,
        );
        await expectLater(
          fixture.workspaces.unregister(workspace.workspaceId),
          throwsRegistry('workspaceInUse'),
        );
        final workspaceRetirement = await fixture.workspaces.unregister(
          workspace.workspaceId,
          policy: CockpitRemovalPolicy.force,
        );
        expect(workspaceRetirement.tombstoneRetained, isTrue);
        final rootRetirement = await fixture.roots.remove(
          root.rootId,
          policy: CockpitRemovalPolicy.force,
        );
        expect(rootRetirement.tombstoneRetained, isTrue);
        expect(evidence.existsSync(), isTrue);
        expect(Directory(workspace.canonicalPath).existsSync(), isTrue);
        final replacementRoot = await fixture.roots.register(
          rootDirectory.path,
        );
        final replacementWorkspace = await fixture.workspaces.register(
          rootId: replacementRoot.rootId,
          path: workspace.canonicalPath,
        );
        expect(replacementRoot.rootId, isNot(root.rootId));
        expect(replacementWorkspace.workspaceId, isNot(workspace.workspaceId));
        expect(replacementWorkspace.checkoutId, isNot(workspace.checkoutId));
        expect(await fixture.roots.list(), hasLength(2));
        expect(await fixture.workspaces.list(), hasLength(2));
        await fixture.references.releaseRunRetention(
          workspace.workspaceId,
          'run_retained',
        );
        await fixture.references.releaseArtifactReferences(
          workspace.workspaceId,
          'run_retained',
          2,
        );
        final remainingRoots = await fixture.roots.list();
        expect(remainingRoots, hasLength(1));
        expect(remainingRoots.single.rootId, replacementRoot.rootId);
        final remainingWorkspaces = await fixture.workspaces.list();
        expect(remainingWorkspaces, hasLength(1));
        expect(
          remainingWorkspaces.single.workspaceId,
          replacementWorkspace.workspaceId,
        );
        expect(evidence.existsSync(), isTrue);
      },
    );

    test(
      'allows an active parent root beside a retained descendant tombstone',
      () async {
        final fixture = await _RegistryFixture.create();
        addTearDown(fixture.dispose);
        final parentDirectory = await fixture.directory('parent');
        final retiredRootDirectory = await Directory(
          p.join(parentDirectory.path, 'retired-root'),
        ).create();
        final retiredRoot = await fixture.roots.register(
          retiredRootDirectory.path,
        );
        final retiredWorkspace = await fixture.registerChild(
          retiredRoot,
          retiredRootDirectory,
          'workspace',
        );
        await fixture.references.setRun(
          workspaceId: retiredWorkspace.workspaceId,
          runId: 'run_retained_overlap',
          active: false,
          retained: true,
          artifactCount: 1,
        );

        await fixture.workspaces.unregister(
          retiredWorkspace.workspaceId,
          policy: CockpitRemovalPolicy.force,
        );
        final retirement = await fixture.roots.remove(
          retiredRoot.rootId,
          policy: CockpitRemovalPolicy.force,
        );
        expect(retirement.tombstoneRetained, isTrue);

        final parentRoot = await fixture.roots.register(parentDirectory.path);
        expect(parentRoot.state, CockpitRootState.active);
        expect(await fixture.roots.list(), hasLength(2));

        await fixture.references.releaseRunRetention(
          retiredWorkspace.workspaceId,
          'run_retained_overlap',
        );
        await fixture.references.releaseArtifactReferences(
          retiredWorkspace.workspaceId,
          'run_retained_overlap',
          1,
        );
        final remainingRoots = await fixture.roots.list();
        expect(remainingRoots, hasLength(1));
        expect(remainingRoots.single.rootId, parentRoot.rootId);
        expect(remainingRoots.single.state, CockpitRootState.active);
      },
    );

    test(
      'drain removes authority first and remains bounded when active',
      () async {
        final fixture = await _RegistryFixture.create();
        addTearDown(fixture.dispose);
        final rootDirectory = await fixture.directory('root');
        final root = await fixture.roots.register(rootDirectory.path);
        final workspace = await fixture.registerChild(
          root,
          rootDirectory,
          'workspace',
        );
        await fixture.references.setSession(
          workspace.workspaceId,
          'session_live',
        );
        await expectLater(
          fixture.workspaces.unregister(
            workspace.workspaceId,
            policy: CockpitRemovalPolicy.drain,
            drainTimeout: const Duration(milliseconds: 10),
          ),
          throwsRegistry('workspaceInUse'),
        );
        expect(
          (await fixture.workspaces.get(workspace.workspaceId)).state,
          CockpitWorkspaceState.draining,
        );
        await expectLater(
          fixture.references.setSession(workspace.workspaceId, 'session_new'),
          throwsRegistry('workspaceNotActive'),
        );
        await fixture.workspaces.unregister(
          workspace.workspaceId,
          policy: CockpitRemovalPolicy.force,
        );
      },
    );

    test('enforces drain timeout independently of activity owner', () async {
      final fixture = await _RegistryFixture.create(
        activityController: const _NeverDrainActivityController(),
      );
      addTearDown(fixture.dispose);
      final rootDirectory = await fixture.directory('root');
      final root = await fixture.roots.register(rootDirectory.path);
      final workspace = await fixture.registerChild(
        root,
        rootDirectory,
        'workspace',
      );
      await expectLater(
        fixture.workspaces.unregister(
          workspace.workspaceId,
          policy: CockpitRemovalPolicy.drain,
          drainTimeout: const Duration(milliseconds: 5),
        ),
        throwsRegistry('drainTimeout'),
      );
      expect(
        (await fixture.workspaces.get(workspace.workspaceId)).state,
        CockpitWorkspaceState.draining,
      );
    });

    test('root removal coordinates pending marker mutation recovery', () async {
      final fixture = await _RegistryFixture.create();
      addTearDown(fixture.dispose);
      final rootDirectory = await fixture.directory('root');
      final root = await fixture.roots.register(rootDirectory.path);
      final workspace = await fixture.registerChild(
        root,
        rootDirectory,
        'workspace',
      );
      await fixture.addProjectIntent(
        workspace.workspaceId,
        workspace.projectId,
        'project_pending',
      );
      await expectLater(
        fixture.roots.remove(root.rootId, policy: CockpitRemovalPolicy.force),
        throwsRegistry('markerMutationPending'),
      );
      expect(
        (await fixture.roots.get(root.rootId)).state,
        CockpitRootState.active,
      );
      await fixture.workspaces.list();
      await fixture.roots.remove(
        root.rootId,
        policy: CockpitRemovalPolicy.force,
      );
      expect(await fixture.roots.list(), isEmpty);
    });

    test(
      'admission fences external references during workspace removal',
      () async {
        final owner = _ControllableReferenceOwner()..pauseNextCount();
        final fixture = await _RegistryFixture.create(
          referenceOwners: <CockpitRegistryReferenceOwner>[owner],
        );
        addTearDown(fixture.dispose);
        final rootDirectory = await fixture.directory('root');
        final root = await fixture.roots.register(rootDirectory.path);
        final workspace = await fixture.registerChild(
          root,
          rootDirectory,
          'workspace',
        );
        final removal = fixture.workspaces.unregister(workspace.workspaceId);
        await owner.countPaused;
        final admission = owner.admit(workspace.workspaceId, () async {
          final current = await fixture.workspaces.get(workspace.workspaceId);
          if (current.state != CockpitWorkspaceState.active) {
            throw const CockpitRegistryException(
              code: 'workspaceNotActive',
              message: 'Workspace does not grant admission authority.',
            );
          }
        });
        await owner.admissionQueued;
        expect(owner.authorityChecks, 0);
        owner.resumeCount();
        await removal;
        await expectLater(admission, throwsRegistry('workspaceNotFound'));
        expect(owner.authorityChecks, 1);
        expect(owner.counts[workspace.workspaceId] ?? 0, 0);
        expect(owner.scopes.first.rootIds, isEmpty);
        expect(owner.scopes.first.workspaceIds, <String>{
          workspace.workspaceId,
        });
      },
    );

    test(
      'reject preserves authority when an external reference exists',
      () async {
        final owner = _ControllableReferenceOwner();
        final fixture = await _RegistryFixture.create(
          referenceOwners: <CockpitRegistryReferenceOwner>[owner],
        );
        addTearDown(fixture.dispose);
        final rootDirectory = await fixture.directory('root');
        final root = await fixture.roots.register(rootDirectory.path);
        final workspace = await fixture.registerChild(
          root,
          rootDirectory,
          'workspace',
        );
        owner.counts[workspace.workspaceId] = 1;
        await expectLater(
          fixture.workspaces.unregister(workspace.workspaceId),
          throwsRegistry('workspaceInUse'),
        );
        expect(
          (await fixture.workspaces.get(workspace.workspaceId)).state,
          CockpitWorkspaceState.active,
        );
      },
    );

    test('root removal fences the root authority scope', () async {
      final owner = _ControllableReferenceOwner();
      final fixture = await _RegistryFixture.create(
        referenceOwners: <CockpitRegistryReferenceOwner>[owner],
      );
      addTearDown(fixture.dispose);
      final rootDirectory = await fixture.directory('root');
      final root = await fixture.roots.register(rootDirectory.path);
      await fixture.registerChild(root, rootDirectory, 'workspace');
      await fixture.roots.remove(
        root.rootId,
        policy: CockpitRemovalPolicy.force,
      );
      expect(owner.scopes.single.rootIds, <String>{root.rootId});
      expect(owner.scopes.single.workspaceIds, isEmpty);
    });

    test(
      'root reject sees a workspace registered after its snapshot',
      () async {
        final owner = _ControllableReferenceOwner();
        final fixture = await _RegistryFixture.create(
          referenceOwners: <CockpitRegistryReferenceOwner>[owner],
        );
        addTearDown(fixture.dispose);
        final rootDirectory = await fixture.directory('root');
        final root = await fixture.roots.register(rootDirectory.path);
        final retained = await fixture.registerChild(
          root,
          rootDirectory,
          'retained',
        );
        await fixture.references.setRun(
          workspaceId: retained.workspaceId,
          runId: 'run_retained_for_race',
          active: true,
          retained: true,
          artifactCount: 0,
        );
        await fixture.workspaces.unregister(
          retained.workspaceId,
          policy: CockpitRemovalPolicy.force,
        );
        owner.pauseNextCount();
        final removal = fixture.roots.remove(root.rootId);
        await owner.countPaused;
        final concurrent = await fixture.registerChild(
          root,
          rootDirectory,
          'concurrent',
        );
        owner.resumeCount();
        await expectLater(removal, throwsRegistry('rootInUse'));
        expect(
          (await fixture.roots.get(root.rootId)).state,
          CockpitRootState.active,
        );
        expect(
          (await fixture.workspaces.get(concurrent.workspaceId)).state,
          CockpitWorkspaceState.active,
        );
      },
    );
  });

  group('persisted registry semantics', () {
    test(
      'allows workspace equals root after verifying its ancestor chain',
      () async {
        final fixture = await _RegistryFixture.create();
        addTearDown(fixture.dispose);
        final rootDirectory = await fixture.directory('root');
        final root = await fixture.roots.register(rootDirectory.path);
        final workspace = await fixture.workspaces.register(
          rootId: root.rootId,
          path: rootDirectory.path,
        );
        final stored = await fixture.workspaces.get(workspace.workspaceId);
        expect(workspace.canonicalPath, root.canonicalPath);
        expect(stored.filesystemIdentity, root.filesystemIdentity);
      },
    );

    test(
      'rejects semantic corruption without resetting persisted data',
      () async {
        final corruptions =
            <String, void Function(Map<String, Object?> registry)>{
              'relative root path': (registry) {
                _jsonRecord(registry, 'roots', 0)['canonicalPath'] =
                    'relative/root';
              },
              'non-normalized workspace path': (registry) {
                final workspace = _jsonRecord(registry, 'workspaces', 0);
                final path = workspace['canonicalPath']! as String;
                workspace['canonicalPath'] = p.join(
                  path,
                  '..',
                  p.basename(path),
                );
              },
              'overlapping roots': (registry) {
                final root = _jsonRecord(registry, 'roots', 0);
                final duplicate = Map<String, Object?>.from(root)
                  ..['rootId'] = 'root_overlap'
                  ..['canonicalPath'] = p.join(
                    root['canonicalPath']! as String,
                    'nested',
                  )
                  ..['filesystemIdentity'] = 'identity_overlap';
                _jsonRecords(registry, 'roots').add(duplicate);
              },
              'duplicate root filesystem identity': (registry) {
                final root = _jsonRecord(registry, 'roots', 0);
                final duplicate = Map<String, Object?>.from(root)
                  ..['rootId'] = 'root_duplicate_identity'
                  ..['canonicalPath'] = p.join(
                    p.dirname(root['canonicalPath']! as String),
                    'root-sibling',
                  );
                _jsonRecords(registry, 'roots').add(duplicate);
              },
              'duplicate workspace path': (registry) {
                final workspace = _jsonRecord(registry, 'workspaces', 0);
                final duplicate = _distinctWorkspaceJson(workspace)
                  ..['filesystemIdentity'] = 'identity_duplicate_path';
                _jsonRecords(registry, 'workspaces').add(duplicate);
              },
              'workspace outside root': (registry) {
                final root = _jsonRecord(registry, 'roots', 0);
                _jsonRecord(registry, 'workspaces', 0)['canonicalPath'] = p
                    .join(
                      p.dirname(root['canonicalPath']! as String),
                      'outside-root',
                    );
              },
              'workspace references the wrong root': (registry) {
                final root = _jsonRecord(registry, 'roots', 0);
                final secondRoot = Map<String, Object?>.from(root)
                  ..['rootId'] = 'root_wrong_target'
                  ..['canonicalPath'] = p.join(
                    p.dirname(root['canonicalPath']! as String),
                    'other-root',
                  )
                  ..['filesystemIdentity'] = 'identity_other_root';
                _jsonRecords(registry, 'roots').add(secondRoot);
                _jsonRecord(registry, 'workspaces', 0)['rootId'] =
                    'root_wrong_target';
              },
              'strong workspace identity collision': (registry) {
                final workspace = _jsonRecord(registry, 'workspaces', 0)
                  ..['filesystemIdentity'] = 'posix:999999:999999'
                  ..['identityQuality'] = 'deviceAndInode';
                final duplicate = _distinctWorkspaceJson(workspace)
                  ..['canonicalPath'] = p.join(
                    p.dirname(workspace['canonicalPath']! as String),
                    'identity-collision',
                  );
                _jsonRecords(registry, 'workspaces').add(duplicate);
              },
            };

        for (final corruption in corruptions.entries) {
          final fixture = await _RegistryFixture.create();
          try {
            final rootDirectory = await fixture.directory('root');
            final root = await fixture.roots.register(rootDirectory.path);
            await fixture.registerChild(root, rootDirectory, 'workspace');
            final file = File(fixture.paths.identityRegistry);
            final registry =
                jsonDecode(await file.readAsString()) as Map<String, Object?>;
            corruption.value(registry);
            final corruptedSource = jsonEncode(registry);
            await file.writeAsString(corruptedSource);
            await expectLater(
              fixture.roots.list(),
              throwsA(isA<CockpitStorageException>()),
              reason: corruption.key,
            );
            expect(
              await file.readAsString(),
              corruptedSource,
              reason: corruption.key,
            );
          } finally {
            await fixture.dispose();
          }
        }
      },
    );

    test('rejects invalid state before an atomic write', () async {
      final fixture = await _RegistryFixture.create();
      addTearDown(fixture.dispose);
      final rootDirectory = await fixture.directory('root');
      final root = await fixture.roots.register(rootDirectory.path);
      await fixture.registerChild(root, rootDirectory, 'workspace');
      final file = File(fixture.paths.identityRegistry);
      final originalSource = await file.readAsString();
      await expectLater(
        fixture.database.transact<void>((state) async {
          state.workspaces[0] = state.workspaces[0].copyWith(
            canonicalPath: 'relative/workspace',
          );
          return CockpitLockedJsonUpdate.write(state, null);
        }),
        throwsA(isA<FormatException>()),
      );
      expect(await file.readAsString(), originalSource);
    });
  });

  test('unknown registry schema never resets persisted data', () async {
    final fixture = await _RegistryFixture.create();
    addTearDown(fixture.dispose);
    final rootDirectory = await fixture.directory('root');
    await fixture.roots.register(rootDirectory.path);
    final file = File(fixture.paths.identityRegistry);
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    json['schemaVersion'] = 'cockpit.registry/v3';
    await file.writeAsString(jsonEncode(json));
    await expectLater(
      fixture.roots.list(),
      throwsA(isA<CockpitStorageException>()),
    );
    expect(
      (jsonDecode(await file.readAsString())
          as Map<String, Object?>)['schemaVersion'],
      'cockpit.registry/v3',
    );
  });
}

List<Object?> _jsonRecords(Map<String, Object?> registry, String field) =>
    registry[field]! as List<Object?>;

Map<String, Object?> _jsonRecord(
  Map<String, Object?> registry,
  String field,
  int index,
) => _jsonRecords(registry, field)[index]! as Map<String, Object?>;

Map<String, Object?> _distinctWorkspaceJson(Map<String, Object?> workspace) =>
    Map<String, Object?>.from(workspace)
      ..['workspaceId'] = 'workspace_corrupt_duplicate'
      ..['projectId'] = 'project_corrupt_duplicate'
      ..['checkoutId'] = 'checkout_corrupt_duplicate';

Matcher throwsRegistry(String code) => throwsA(
  isA<CockpitRegistryException>().having((error) => error.code, 'code', code),
);

final class _RegistryFixture {
  const _RegistryFixture._({
    required this.temporary,
    required this.paths,
    required this.database,
    required this.roots,
    required this.workspaces,
    required this.references,
    required this.markerStore,
  });

  final Directory temporary;
  final CockpitHomePaths paths;
  final CockpitRegistryDatabase database;
  final CockpitAllowedRootRegistry roots;
  final CockpitWorkspaceRegistry workspaces;
  final CockpitScopedReferenceIndex references;
  final CockpitWorkspaceMarkerStore markerStore;

  static Future<_RegistryFixture> create({
    CockpitRegistryActivityController activityController =
        const CockpitPassiveRegistryActivityController(),
    List<CockpitRegistryReferenceOwner> referenceOwners =
        const <CockpitRegistryReferenceOwner>[],
    CockpitDirectoryAttestationProvider Function(
      CockpitDirectoryAttestationProvider delegate,
    )?
    decorateDirectoryAttestor,
  }) async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-registry-',
    );
    final platform = Platform.isWindows
        ? CockpitHostPlatform.windows
        : Platform.isMacOS
        ? CockpitHostPlatform.macos
        : CockpitHostPlatform.linux;
    final hardener = Platform.isWindows
        ? const CockpitWindowsInheritedAclPermissionHardener()
        : const CockpitPosixPermissionHardener();
    final paths = await CockpitHome(
      paths: CockpitHomePaths(p.join(temporary.path, 'home')),
      permissionHardener: hardener,
    ).initialize();
    const syncer = _NoopDirectorySyncer();
    final lexical = CockpitLexicalPaths(
      Platform.isWindows ? CockpitPathStyle.windows : CockpitPathStyle.posix,
    );
    final database = CockpitRegistryDatabase.create(
      paths: paths,
      permissionHardener: hardener,
      directorySyncer: syncer,
      lexicalPaths: lexical,
    );
    final metadata = CockpitSystemPosixMetadataProvider(platform);
    final identities = CockpitBestEffortFilesystemIdentityProvider(metadata);
    final security = CockpitDirectorySecurityInspector(
      platform: platform,
      metadataProvider: metadata,
    );
    final ids = CockpitSecureIdGenerator();
    const clock = _FixedClock();
    const resolver = CockpitCanonicalDirectoryResolver();
    final markerStore = CockpitWorkspaceMarkerStore(
      CockpitAtomicJsonFile(
        permissionHardener: hardener,
        directorySyncer: syncer,
      ),
    );
    final baseAttestor = CockpitDirectoryAttestor(
      directoryResolver: resolver,
      identityProvider: identities,
      securityInspector: security,
      ancestorPolicy: CockpitSystemDirectoryAncestorPolicy(
        platform: platform,
        metadataProvider: metadata,
      ),
      lexicalPaths: lexical,
      requireStrongIdentity: false,
    );
    final attestor =
        decorateDirectoryAttestor?.call(baseAttestor) ?? baseAttestor;
    return _RegistryFixture._(
      temporary: temporary,
      paths: paths,
      database: database,
      roots: CockpitAllowedRootRegistry(
        database: database,
        directoryAttestor: attestor,
        idGenerator: ids,
        clock: clock,
        lexicalPaths: lexical,
        activityController: activityController,
        referenceOwners: referenceOwners,
      ),
      workspaces: CockpitWorkspaceRegistry(
        database: database,
        markerStore: markerStore,
        directoryAttestor: attestor,
        idGenerator: ids,
        clock: clock,
        lexicalPaths: lexical,
        activityController: activityController,
        referenceOwners: referenceOwners,
      ),
      references: CockpitScopedReferenceIndex(database),
      markerStore: markerStore,
    );
  }

  Future<Directory> directory(String name) =>
      Directory(p.join(temporary.path, name)).create();

  Future<CockpitWorkspaceRegistrationResult> registerChild(
    CockpitRootResource root,
    Directory rootDirectory,
    String name,
  ) async {
    final child = await Directory(p.join(rootDirectory.path, name)).create();
    return workspaces.register(rootId: root.rootId, path: child.path);
  }

  Future<CockpitWorkspaceMarker> marker(String workspacePath) async =>
      (await markerStore.read(workspacePath))!;

  Future<void> addProjectIntent(
    String workspaceId,
    String expectedProjectId,
    String projectId,
  ) => database.transact<void>((state) async {
    state.markerMutations.add(
      CockpitMarkerMutationRecord(
        workspaceId: workspaceId,
        expectedProjectId: expectedProjectId,
        projectId: projectId,
      ),
    );
    return CockpitLockedJsonUpdate.write(state, null);
  });

  Future<void> dispose() => temporary.delete(recursive: true);
}

final class _FixedClock implements CockpitClock {
  const _FixedClock();

  @override
  DateTime now() => DateTime.utc(2026, 7, 21, 12);
}

final class _AllowAllAncestorPolicy implements CockpitDirectoryAncestorPolicy {
  const _AllowAllAncestorPolicy();

  @override
  Future<void> verify(String canonicalPath) async {}
}

final class _MutableIdentityProvider
    implements CockpitFilesystemIdentityProvider {
  _MutableIdentityProvider(this.value);

  String value;

  @override
  Future<CockpitFilesystemIdentity> identify(String canonicalPath) async =>
      CockpitFilesystemIdentity(
        value: value,
        quality: CockpitFilesystemIdentityQuality.deviceAndInode,
      );
}

final class _MutatingMetadataProvider implements CockpitPosixMetadataProvider {
  _MutatingMetadataProvider(this._mutate);

  final void Function() _mutate;
  var _didMutate = false;

  @override
  Future<int?> currentUserId() async => 1000;

  @override
  Future<CockpitPosixMetadata?> read(String canonicalPath) async {
    if (!_didMutate) {
      _didMutate = true;
      _mutate();
    }
    return const CockpitPosixMetadata(
      device: 1,
      inode: 1,
      ownerUserId: 1000,
      mode: 448,
    );
  }
}

final class _SequenceMetadataProvider implements CockpitPosixMetadataProvider {
  _SequenceMetadataProvider(this._values);

  final List<CockpitPosixMetadata> _values;
  final List<String> paths = <String>[];
  var _index = 0;

  @override
  Future<int?> currentUserId() async => 1000;

  @override
  Future<CockpitPosixMetadata?> read(String canonicalPath) async {
    paths.add(canonicalPath);
    return _values[_index++];
  }
}

final class _MappedMetadataProvider implements CockpitPosixMetadataProvider {
  const _MappedMetadataProvider({
    required int currentUserId,
    required this.values,
  }) : _currentUserId = currentUserId;

  final int _currentUserId;
  final Map<String, CockpitPosixMetadata> values;

  @override
  Future<int?> currentUserId() async => _currentUserId;

  @override
  Future<CockpitPosixMetadata?> read(String canonicalPath) async =>
      values[canonicalPath];
}

final class _MappedWindowsSecurityProvider
    implements CockpitWindowsSecurityProvider {
  _MappedWindowsSecurityProvider(this.values);

  final Map<String, CockpitDirectorySecurity> values;
  final List<String> paths = <String>[];

  @override
  Future<CockpitDirectorySecurity> inspect(String canonicalPath) async {
    paths.add(canonicalPath);
    return values[canonicalPath]!;
  }
}

final class _ControllableDirectoryAttestor
    implements CockpitDirectoryAttestationProvider {
  late CockpitDirectoryAttestationProvider _delegate;
  final List<CockpitDirectoryAttestationScope> calls =
      <CockpitDirectoryAttestationScope>[];
  final List<_AttestationInterception> _interceptions =
      <_AttestationInterception>[];

  CockpitDirectoryAttestationProvider bind(
    CockpitDirectoryAttestationProvider delegate,
  ) {
    _delegate = delegate;
    return this;
  }

  void interceptNext(
    CockpitDirectoryAttestationScope scope, {
    int skipMatches = 0,
    required Future<void> Function() before,
    required CockpitDirectoryAttestation Function(
      CockpitDirectoryAttestation value,
    )
    transform,
  }) {
    _interceptions.add(
      _AttestationInterception(
        scope: scope,
        remainingMatches: skipMatches,
        before: before,
        transform: transform,
      ),
    );
  }

  @override
  Future<CockpitDirectoryAttestation> attest(
    String path,
    CockpitDirectoryAttestationScope scope,
  ) async {
    calls.add(scope);
    final index = _interceptions.indexWhere((value) => value.scope == scope);
    if (index < 0) return _delegate.attest(path, scope);
    final interception = _interceptions[index];
    if (interception.remainingMatches > 0) {
      interception.remainingMatches -= 1;
      return _delegate.attest(path, scope);
    }
    _interceptions.removeAt(index);
    await interception.before();
    return interception.transform(await _delegate.attest(path, scope));
  }
}

final class _AttestationInterception {
  _AttestationInterception({
    required this.scope,
    required this.remainingMatches,
    required this.before,
    required this.transform,
  });

  final CockpitDirectoryAttestationScope scope;
  int remainingMatches;
  final Future<void> Function() before;
  final CockpitDirectoryAttestation Function(CockpitDirectoryAttestation value)
  transform;
}

CockpitDirectoryAttestation _changedAttestation(
  CockpitDirectoryAttestation value,
) => CockpitDirectoryAttestation(
  directory: value.directory,
  identity: CockpitFilesystemIdentity(
    value: '${value.identity.value}:changed',
    quality: value.identity.quality,
  ),
  security: value.security,
);

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  const _NoopDirectorySyncer();

  @override
  Future<void> sync(String directoryPath) async {}
}

final class _NeverDrainActivityController
    implements CockpitRegistryActivityController {
  const _NeverDrainActivityController();

  @override
  Future<void> drainWorkspaces(Set<String> workspaceIds, Duration timeout) =>
      Completer<void>().future;

  @override
  Future<void> forceWorkspaces(Set<String> workspaceIds) async {}
}

final class _ControllableReferenceOwner
    implements CockpitRegistryReferenceOwner {
  final Map<String, int> counts = <String, int>{};
  final List<({Set<String> rootIds, Set<String> workspaceIds})> scopes =
      <({Set<String> rootIds, Set<String> workspaceIds})>[];

  Future<void> _tail = Future<void>.value();
  bool _insideFence = false;
  Completer<void>? _countPaused;
  Completer<void>? _countResume;
  final Completer<void> _admissionQueued = Completer<void>();
  var authorityChecks = 0;

  Future<void> get countPaused => _countPaused!.future;

  Future<void> get admissionQueued => _admissionQueued.future;

  void pauseNextCount() {
    _countPaused = Completer<void>();
    _countResume = Completer<void>();
  }

  void resumeCount() => _countResume!.complete();

  Future<void> admit(
    String workspaceId,
    Future<void> Function() verifyAuthority,
  ) {
    if (!_admissionQueued.isCompleted) _admissionQueued.complete();
    return withAdmissionFence(
      const <String>{},
      <String>{workspaceId},
      () async {
        authorityChecks += 1;
        await verifyAuthority();
        counts[workspaceId] = (counts[workspaceId] ?? 0) + 1;
      },
    );
  }

  @override
  Future<int> activeReferenceCount(String workspaceId) async {
    if (!_insideFence) {
      throw StateError('Reference count read outside admission fence.');
    }
    final paused = _countPaused;
    if (paused != null && !paused.isCompleted) {
      paused.complete();
      await _countResume!.future;
    }
    return counts[workspaceId] ?? 0;
  }

  @override
  Future<R> withAdmissionFence<R>(
    Set<String> rootIds,
    Set<String> workspaceIds,
    Future<R> Function() action,
  ) async {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    await previous;
    _insideFence = true;
    scopes.add((
      rootIds: Set<String>.unmodifiable(rootIds),
      workspaceIds: Set<String>.unmodifiable(workspaceIds),
    ));
    try {
      return await action();
    } finally {
      _insideFence = false;
      release.complete();
    }
  }
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(recursive: false)) {
    final targetPath = p.join(destination.path, p.basename(entity.path));
    if (entity is Directory) {
      await _copyDirectory(entity, Directory(targetPath));
    } else if (entity is File) {
      await entity.copy(targetPath);
    } else if (entity is Link) {
      await Link(targetPath).create(await entity.target());
    }
  }
}
