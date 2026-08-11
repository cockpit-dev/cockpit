import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:cockpit/src/foundation/cockpit_canonical_paths.dart';
import 'package:cockpit/src/foundation/cockpit_filesystem_identity.dart';
import 'package:cockpit/src/foundation/cockpit_home.dart';
import 'package:cockpit/src/foundation/cockpit_ids.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/foundation/cockpit_windows_directory_authority.dart';
import 'package:cockpit/src/foundation/cockpit_windows_filesystem_identity.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('secure identifiers', () {
    test('use short lowercase Base36 resource tokens without collisions', () {
      final idGenerator = CockpitSecureIdGenerator(random: Random(7));
      final identifiers = <String>{
        for (final kind in CockpitIdKind.values) idGenerator.next(kind),
      };
      expect(identifiers, hasLength(CockpitIdKind.values.length));
      for (final kind in CockpitIdKind.values) {
        expect(
          idGenerator.next(kind),
          matches(RegExp('^${kind.prefix}[a-z0-9]{10}\$')),
        );
      }

      final tokenGenerator = CockpitSecureTokenGenerator(random: Random(11));
      final resourceIds = <String>{
        for (var index = 0; index < 4096; index += 1)
          tokenGenerator.nextIdToken(),
      };
      expect(resourceIds, hasLength(4096));
      expect(resourceIds, everyElement(matches(RegExp(r'^[a-z0-9]{10}$'))));
      expect(tokenGenerator.nextToken(), hasLength(43));
    });
  });

  group('cockpit home', () {
    test('resolves explicit and platform user-state locations', () {
      expect(
        const CockpitHomeResolver(
          platform: CockpitHostPlatform.linux,
          environment: <String, String>{
            'COCKPIT_HOME': '/var/lib/../state/cockpit',
          },
          userHome: '/home/user',
        ).resolve(),
        '/var/state/cockpit',
      );
      expect(
        const CockpitHomeResolver(
          platform: CockpitHostPlatform.linux,
          environment: <String, String>{'XDG_STATE_HOME': '/state/user'},
          userHome: '/home/user',
        ).resolve(),
        '/state/user/cockpit',
      );
      expect(
        const CockpitHomeResolver(
          platform: CockpitHostPlatform.macos,
          environment: <String, String>{},
          userHome: '/Users/user',
        ).resolve(),
        '/Users/user/Library/Application Support/Cockpit',
      );
      expect(
        const CockpitHomeResolver(
          platform: CockpitHostPlatform.windows,
          environment: <String, String>{
            'LOCALAPPDATA': r'C:\Users\user\AppData\Local',
          },
          userHome: r'C:\Users\user',
        ).resolve(),
        r'C:\Users\user\AppData\Local\Cockpit',
      );
      expect(
        () => const CockpitHomeResolver(
          platform: CockpitHostPlatform.linux,
          environment: <String, String>{'COCKPIT_HOME': 'relative/home'},
          userHome: '/home/user',
        ).resolve(),
        throwsA(
          isA<CockpitHomeResolutionException>().having(
            (error) => error.code,
            'code',
            'invalidHomePath',
          ),
        ),
      );
    });

    test(
      'creates owner-only home layout and sensitive files on POSIX',
      () async {
        final temporary = await Directory.systemTemp.createTemp(
          'cockpit-home-',
        );
        addTearDown(() => temporary.delete(recursive: true));
        final paths = await CockpitHome(
          paths: CockpitHomePaths(p.join(temporary.path, 'home')),
          permissionHardener: const CockpitPosixPermissionHardener(),
        ).initialize();
        for (final directoryPath in paths.directories) {
          expect(FileStat.statSync(directoryPath).mode & 0x1ff, 0x1c0);
        }
        final file = p.join(paths.registryDirectory, 'secret.json');
        await CockpitAtomicJsonFile(
          permissionHardener: const CockpitPosixPermissionHardener(),
          directorySyncer: const _NoopDirectorySyncer(),
        ).write(file, <String, Object?>{'secret': true});
        expect(FileStat.statSync(file).mode & 0x1ff, 0x180);
      },
      skip: Platform.isWindows,
    );

    test('syncs individual POSIX files and directories', () async {
      final temporary = await Directory.systemTemp.createTemp('cockpit-sync-');
      addTearDown(() => temporary.delete(recursive: true));
      final file = File(p.join(temporary.path, 'state.json'));
      await file.writeAsString('{"ready":true}\n', flush: true);

      final platform = Platform.isMacOS
          ? CockpitHostPlatform.macos
          : CockpitHostPlatform.linux;
      final syncer = CockpitSystemDirectorySyncer(platform);
      await syncer.sync(file.path);
      await syncer.sync(temporary.path);

      expect(await file.readAsString(), '{"ready":true}\n');
    }, skip: Platform.isWindows);
  });

  group('locked atomic JSON', () {
    test('fails closed on corrupt and unknown-version data', () async {
      final temporary = await Directory.systemTemp.createTemp('cockpit-json-');
      addTearDown(() => temporary.delete(recursive: true));
      final path = p.join(temporary.path, 'counter.json');
      final store = _counterStore(path);
      await store.transact<void>(
        (value) async => CockpitLockedJsonUpdate.write(value + 1, null),
      );
      await File(path).writeAsString('{broken');
      await expectLater(
        store.read(),
        throwsA(
          isA<CockpitStorageException>().having(
            (error) => error.code,
            'code',
            'storageCorrupt',
          ),
        ),
      );
      expect(await File(path).readAsString(), '{broken');
      await File(path).writeAsString(
        jsonEncode(<String, Object?>{
          'schemaVersion': 'counter/v3',
          'value': 9,
        }),
      );
      await expectLater(store.read(), throwsA(isA<CockpitStorageException>()));
      expect(jsonDecode(await File(path).readAsString()), <String, Object?>{
        'schemaVersion': 'counter/v3',
        'value': 9,
      });
    });

    test(
      'serializes read-modify-write transactions across processes',
      () async {
        final temporary = await Directory.systemTemp.createTemp(
          'cockpit-lock-',
        );
        addTearDown(() => temporary.delete(recursive: true));
        final script = File(p.join(temporary.path, 'increment.dart'));
        await script.writeAsString(_incrementProcessSource);
        final packageConfig = _packageConfigPath();
        final statePath = p.join(temporary.path, 'counter.json');
        final results = await Future.wait(<Future<ProcessResult>>[
          for (var process = 0; process < 4; process += 1)
            Process.run(Platform.resolvedExecutable, <String>[
              '--packages=$packageConfig',
              script.path,
              statePath,
              '25',
            ]),
        ]);
        for (final result in results) {
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}\n${result.stderr}',
          );
        }
        expect(await _counterStore(statePath).read(), 100);
        expect(
          temporary.listSync().where((entity) => entity.path.endsWith('.tmp')),
          isEmpty,
        );
      },
    );

    test('serializes concurrent transactions within one process', () async {
      final temporary = await Directory.systemTemp.createTemp('cockpit-local-');
      addTearDown(() => temporary.delete(recursive: true));
      final path = p.join(temporary.path, 'counter.json');
      final stores = <CockpitLockedJsonStore<int>>[
        for (var index = 0; index < 4; index += 1) _counterStore(path),
      ];
      await Future.wait(<Future<void>>[
        for (var index = 0; index < 40; index += 1)
          stores[index % stores.length].transact<void>(
            (value) async => CockpitLockedJsonUpdate.write(value + 1, null),
          ),
      ]);
      expect(await stores.first.read(), 40);
    });

    test(
      'cleans a stale temp once before concurrent same-key writes',
      () async {
        final temporary = await Directory.systemTemp.createTemp(
          'cockpit-temp-recovery-',
        );
        addTearDown(() => temporary.delete(recursive: true));
        final canonicalRoot = await temporary.resolveSymbolicLinks();
        final path = p.join(canonicalRoot, 'counter.json');
        final store = _counterStore(path);
        await store.transact<void>(
          (value) => CockpitLockedJsonUpdate.write(value, null),
        );
        final stale = await File(
          p.join(
            canonicalRoot,
            '.counter.json.123.${List<String>.filled(24, 'a').join()}.tmp',
          ),
        ).writeAsString('partial');

        await Future.wait(<Future<void>>[
          for (var index = 0; index < 2; index += 1)
            store.transact<void>(
              (value) => CockpitLockedJsonUpdate.write(value + 1, null),
            ),
        ]);

        expect(await store.read(), 2);
        expect(await stale.exists(), isFalse);
      },
    );

    test('does not inspect or delete a live temp before its lock', () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpit-live-temp-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final canonicalRoot = await temporary.resolveSymbolicLinks();
      final path = p.join(canonicalRoot, 'counter.json');
      final store = _counterStore(path);
      await store.transact<void>(
        (value) => CockpitLockedJsonUpdate.write(value + 1, null),
      );
      final live = File(
        p.join(
          canonicalRoot,
          '.counter.json.456.${List<String>.filled(24, 'b').join()}.tmp',
        ),
      );
      final script = await File(
        p.join(canonicalRoot, 'hold_lock.dart'),
      ).writeAsString(_liveTempProcessSource);
      final holder = await Process.start(Platform.resolvedExecutable, <String>[
        script.path,
        '$path.lock',
        live.path,
      ]);
      addTearDown(() => holder.kill());
      expect(
        await holder.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 5)),
        'ready',
      );
      var completed = false;
      final read = store.read().whenComplete(() => completed = true);
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(completed, isFalse);
      expect(await live.exists(), isTrue);

      holder.stdin.writeln('release');
      await holder.stdin.close();
      expect(await read, 1);
      expect(await live.exists(), isFalse);
      expect(await holder.exitCode, 0);
    });

    test('rejects oversized writes before replacing readable state', () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpit-size-limit-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final path = p.join(temporary.path, 'payload.json');
      const allowed = 'near-limit-\u6570\u636e';
      const oversized = '$allowed\u754c';
      const codec = _PayloadCodec();
      final maximumBytes = utf8
          .encode('${jsonEncode(codec.encode(allowed))}\n')
          .length;
      final syncer = _CountingDirectorySyncer();
      final store = CockpitLockedJsonStore<String>(
        path: path,
        codec: codec,
        createInitial: () => '',
        permissionHardener: Platform.isWindows
            ? const CockpitWindowsInheritedAclPermissionHardener()
            : const CockpitPosixPermissionHardener(),
        directorySyncer: syncer,
        maximumBytes: maximumBytes,
      );
      await store.transact<void>(
        (_) async => CockpitLockedJsonUpdate.write(allowed, null),
      );
      final originalSource = await File(path).readAsBytes();
      expect(originalSource.length, maximumBytes);
      final syncsBeforeRejection = syncer.count;
      await expectLater(
        store.transact<void>(
          (_) async => CockpitLockedJsonUpdate.write(oversized, null),
        ),
        throwsA(
          isA<CockpitStorageException>()
              .having((error) => error.code, 'code', 'storageTooLarge')
              .having((error) => error.path, 'path', path),
        ),
      );
      expect(await File(path).readAsBytes(), originalSource);
      expect(await store.read(), allowed);
      expect(syncer.count, syncsBeforeRejection);
      expect(
        temporary.listSync().where((entity) => entity.path.endsWith('.tmp')),
        isEmpty,
      );
      await store.transact<void>(
        (_) async => CockpitLockedJsonUpdate.write('small', null),
      );
      expect(await store.read(), 'small');
    });
  });

  group('lexical and canonical paths', () {
    test('handles Windows drive, UNC, case, and segment boundaries', () {
      const paths = CockpitLexicalPaths(CockpitPathStyle.windows);
      expect(paths.equals(r'C:\Work\App', r'c:\work\app\.'), isTrue);
      expect(paths.contains(r'C:\Work\App', r'c:\work\app\lib'), isTrue);
      expect(paths.contains(r'C:\Work\App', r'C:\Work\Application'), isFalse);
      expect(
        paths.equals(r'\\Server\Share\App', r'\\server\share\app'),
        isTrue,
      );
      expect(
        paths.contains(
          r'\\Server\Share\App',
          r'\\SERVER\SHARE\APP\packages\demo',
        ),
        isTrue,
      );
    });

    test('resolves directory symlinks to their real target', () async {
      if (Platform.isWindows) return;
      final temporary = await Directory.systemTemp.createTemp('cockpit-path-');
      addTearDown(() => temporary.delete(recursive: true));
      final target = await Directory(p.join(temporary.path, 'target')).create();
      final link = Link(p.join(temporary.path, 'link'));
      await link.create(target.path);
      final result = await const CockpitCanonicalDirectoryResolver().resolve(
        link.path,
      );
      expect(result.path, await target.resolveSymbolicLinks());
    });

    test(
      'labels unsupported filesystem identity fallback explicitly',
      () async {
        final identity =
            await const CockpitBestEffortFilesystemIdentityProvider(
              _UnsupportedMetadataProvider(),
            ).identify('/canonical/workspace');
        expect(
          identity.quality,
          CockpitFilesystemIdentityQuality.stablePathFallback,
        );
        expect(identity.value, matches(r'^path-sha256:[a-f0-9]{64}$'));
      },
    );
  });

  group('Windows filesystem identity', () {
    test('parses fixed-width volume and 128-bit file identifiers', () async {
      final probe = _FakeWindowsFileIdentityProbe(
        const CockpitWindowsFileIdentityProbeResult(
          exitCode: 0,
          stdout: '0123456789ABCDEF|00112233445566778899AABBCCDDEEFF\r\n',
          stderr: '',
        ),
      );
      final identity = await CockpitWindowsFilesystemIdentityProvider(
        probe: probe,
      ).identify(r'C:\Work\App');
      expect(
        identity.value,
        'windows:0123456789abcdef:00112233445566778899aabbccddeeff',
      );
      expect(
        identity.quality,
        CockpitFilesystemIdentityQuality.windowsVolumeAndFileId,
      );
      expect(probe.paths, <String>[r'C:\Work\App']);
    });

    test('fails closed on probe errors and malformed identities', () async {
      await expectLater(
        CockpitWindowsFilesystemIdentityProvider(
          probe: _FakeWindowsFileIdentityProbe(
            const CockpitWindowsFileIdentityProbeResult(
              exitCode: 5,
              stdout: '',
              stderr: 'access denied',
            ),
          ),
        ).identify(r'C:\Work\App'),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.message,
            'message',
            contains('access denied'),
          ),
        ),
      );
      for (final output in <String>[
        '',
        '0123456789abcdef',
        '0123456789abcdef|0011',
        '0123456789abcdef|00112233445566778899aabbccddeefg',
        '0123456789abcdef|00112233445566778899aabbccddeeff|extra',
      ]) {
        await expectLater(
          CockpitWindowsFilesystemIdentityProvider(
            probe: _FakeWindowsFileIdentityProbe(
              CockpitWindowsFileIdentityProbeResult(
                exitCode: 0,
                stdout: output,
                stderr: '',
              ),
            ),
          ).identify(r'C:\Work\App'),
          throwsA(isA<FileSystemException>()),
          reason: 'Unexpectedly accepted "$output".',
        );
      }
    });

    test('system Windows assembly never consults POSIX fallback', () async {
      final probe = _FakeWindowsFileIdentityProbe(
        const CockpitWindowsFileIdentityProbeResult(
          exitCode: 0,
          stdout: 'fedcba9876543210|ffeeddccbbaa99887766554433221100',
          stderr: '',
        ),
      );
      final identity = await CockpitSystemFilesystemIdentityProvider(
        platform: CockpitHostPlatform.windows,
        metadataProvider: const _ThrowingMetadataProvider(),
        windowsProbe: probe,
      ).identify(r'\\Server\Share\App');
      expect(
        identity.value,
        'windows:fedcba9876543210:ffeeddccbbaa99887766554433221100',
      );
      expect(identity.quality.isStrong, isTrue);
      expect(CockpitFilesystemIdentityQuality.deviceAndInode.isStrong, isTrue);
      expect(
        CockpitFilesystemIdentityQuality.stablePathFallback.isStrong,
        isFalse,
      );
    });

    test('system POSIX assembly fails closed without metadata', () async {
      await expectLater(
        CockpitSystemFilesystemIdentityProvider(
          platform: CockpitHostPlatform.linux,
          metadataProvider: const _UnsupportedMetadataProvider(),
          windowsProbe: _FakeWindowsFileIdentityProbe(
            const CockpitWindowsFileIdentityProbeResult(
              exitCode: 0,
              stdout: 'fedcba9876543210|ffeeddccbbaa99887766554433221100',
              stderr: '',
            ),
          ),
        ).identify('/workspace'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test(
      'default probe returns a stable identity for a real directory',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'cockpit-windows-identity-',
        );
        addTearDown(() => directory.delete(recursive: true));
        const provider = CockpitWindowsFilesystemIdentityProvider();
        final first = await provider.identify(directory.path);
        final second = await provider.identify(directory.path);
        expect(
          first.quality,
          CockpitFilesystemIdentityQuality.windowsVolumeAndFileId,
        );
        expect(first.value, matches(r'^windows:[0-9a-f]{16}:[0-9a-f]{32}$'));
        expect(second.value, first.value);
      },
      skip: !Platform.isWindows,
    );

    test('native probe requests complete stable directory identity', () async {
      final sourceUri = await Isolate.resolvePackageUri(
        Uri.parse(
          'package:cockpit/src/foundation/'
          'cockpit_windows_filesystem_identity.dart',
        ),
      );
      expect(sourceUri, isNotNull);
      final source = await File.fromUri(sourceUri!).readAsString();
      expect(source, contains("'CreateFileW'"));
      expect(source, contains("'GetFileInformationByHandleEx'"));
      expect(source, contains('const int _fileIdInfoClass = 18;'));
      expect(source, contains('sizeOf<_CockpitWindowsFileIdInfo>() != 24'));
      expect(source, contains('_fileFlagBackupSemantics'));
      expect(source, contains('shareDelete: true'));
      expect(source, isNot(contains('powershell.exe')));
      expect(source, isNot(contains('Add-Type')));
    });

    test(
      'combined authority parser preserves identity and ACL decisions',
      () async {
        final probe = _FakeWindowsDirectoryAuthorityProbe(
          const CockpitWindowsFileIdentityProbeResult(
            exitCode: 0,
            stdout:
                '0123456789ABCDEF|00112233445566778899AABBCCDDEEFF|'
                'True|TRUE|false\r\n',
            stderr: '',
          ),
        );
        final snapshot = await CockpitWindowsDirectoryAuthorityProvider(
          probe: probe,
        ).inspect(r'C:\Work\App');
        expect(
          snapshot.identity.value,
          'windows:0123456789abcdef:00112233445566778899aabbccddeeff',
        );
        expect(snapshot.identity.quality.isStrong, isTrue);
        expect(snapshot.security.ownerVerified, isTrue);
        expect(snapshot.security.ownerTrusted, isTrue);
        expect(snapshot.security.unsafeWritable, isFalse);
        expect(probe.paths, <String>[r'C:\Work\App']);
      },
    );

    test(
      'combined authority probe holds a native no-delete-share lease',
      () async {
        final sourceUri = await Isolate.resolvePackageUri(
          Uri.parse(
            'package:cockpit/src/foundation/'
            'cockpit_windows_directory_authority.dart',
          ),
        );
        expect(sourceUri, isNotNull);
        final source = await File.fromUri(sourceUri!).readAsString();
        expect(source, contains('shareDelete: false'));
        expect(
          source.indexOf('shareDelete: false'),
          lessThan(source.indexOf('CockpitNativeWindowsSecurityProvider')),
        );
        expect(
          source.indexOf('lease?.close()'),
          greaterThan(source.indexOf('CockpitNativeWindowsSecurityProvider')),
        );
        expect(source, isNot(contains('powershell.exe')));
        expect(source, isNot(contains('Get-Acl')));
      },
    );

    test(
      'combined authority probe attests a real directory',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'cockpit-windows-authority-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final snapshot = await const CockpitWindowsDirectoryAuthorityProvider()
            .inspect(directory.path);
        expect(
          snapshot.identity.value,
          matches(r'^windows:[0-9a-f]{16}:[0-9a-f]{32}$'),
        );
        expect(snapshot.identity.quality.isStrong, isTrue);
        expect(snapshot.security.ownerVerified, isTrue);
        expect(snapshot.security.ownerTrusted, isTrue);
        expect(snapshot.security.unsafeWritable, isFalse);
      },
      skip: !Platform.isWindows,
    );
  });

  test('Windows ACL inspection fails closed on every mutation mask', () async {
    final sourceUri = await Isolate.resolvePackageUri(
      Uri.parse('package:cockpit/src/foundation/cockpit_windows_security.dart'),
    );
    expect(sourceUri, isNotNull);
    final source = await File.fromUri(sourceUri!).readAsString();
    expect(source, contains("'GetNamedSecurityInfoW'"));
    expect(source, contains("'OpenProcessToken'"));
    expect(source, contains("'GetTokenInformation'"));
    expect(source, contains("'ConvertSidToStringSidW'"));
    expect(source, contains("'GetAclInformation'"));
    expect(source, contains("'GetAce'"));
    expect(source, contains('dacl.value == nullptr'));
    expect(source, contains('0x00000002'));
    expect(source, contains('0x00000004'));
    expect(source, contains('0x00000010'));
    expect(source, contains('0x00000040'));
    expect(source, contains('0x00000100'));
    expect(source, contains('0x00010000'));
    expect(source, contains('0x00040000'));
    expect(source, contains('0x00080000'));
    expect(source, contains('0x40000000'));
    expect(source, contains('0x10000000'));
    expect(source, isNot(contains('powershell.exe')));
    expect(source, isNot(contains('Get-Acl')));
  });
}

CockpitLockedJsonStore<int> _counterStore(String path) =>
    CockpitLockedJsonStore<int>(
      path: path,
      codec: const _CounterCodec(),
      createInitial: () => 0,
      permissionHardener: Platform.isWindows
          ? const CockpitWindowsInheritedAclPermissionHardener()
          : const CockpitPosixPermissionHardener(),
      directorySyncer: const _NoopDirectorySyncer(),
    );

String _packageConfigPath() {
  var current = Directory.current.absolute;
  while (true) {
    final candidate = File(
      p.join(current.path, '.dart_tool', 'package_config.json'),
    );
    if (candidate.existsSync()) return candidate.path;
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate package_config.json.');
    }
    current = parent;
  }
}

const String _liveTempProcessSource = r'''
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final lock = await File(arguments[0]).open(mode: FileMode.append);
  await lock.lock(FileLock.blockingExclusive);
  await File(arguments[1]).writeAsString('live');
  stdout.writeln('ready');
  await stdin.first;
  await lock.unlock();
  await lock.close();
}
''';

final class _CounterCodec implements CockpitJsonCodec<int> {
  const _CounterCodec();

  @override
  int decode(Object? json) {
    if (json is! Map<Object?, Object?> ||
        json.length != 2 ||
        json['schemaVersion'] != 'counter/v2' ||
        json['value'] is! int) {
      throw const FormatException('Invalid counter/v2 document.');
    }
    return json['value']! as int;
  }

  @override
  Object? encode(int value) => <String, Object?>{
    'schemaVersion': 'counter/v2',
    'value': value,
  };
}

final class _PayloadCodec implements CockpitJsonCodec<String> {
  const _PayloadCodec();

  @override
  String decode(Object? json) {
    if (json is! Map<Object?, Object?> ||
        json.length != 2 ||
        json['schemaVersion'] != 'payload/v2' ||
        json['value'] is! String) {
      throw const FormatException('Invalid payload/v2 document.');
    }
    return json['value']! as String;
  }

  @override
  Object? encode(String value) => <String, Object?>{
    'schemaVersion': 'payload/v2',
    'value': value,
  };
}

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  const _NoopDirectorySyncer();

  @override
  Future<void> sync(String directoryPath) async {}
}

final class _CountingDirectorySyncer implements CockpitDirectorySyncer {
  int count = 0;

  @override
  Future<void> sync(String directoryPath) async {
    count += 1;
  }
}

final class _UnsupportedMetadataProvider
    implements CockpitPosixMetadataProvider {
  const _UnsupportedMetadataProvider();

  @override
  Future<int?> currentUserId() async => null;

  @override
  Future<CockpitPosixMetadata?> read(String canonicalPath) async => null;
}

final class _ThrowingMetadataProvider implements CockpitPosixMetadataProvider {
  const _ThrowingMetadataProvider();

  @override
  Future<int?> currentUserId() => throw StateError('POSIX metadata requested.');

  @override
  Future<CockpitPosixMetadata?> read(String canonicalPath) =>
      throw StateError('POSIX metadata requested.');
}

final class _FakeWindowsFileIdentityProbe
    implements CockpitWindowsFileIdentityProbe {
  _FakeWindowsFileIdentityProbe(this.result);

  final CockpitWindowsFileIdentityProbeResult result;
  final List<String> paths = <String>[];

  @override
  Future<CockpitWindowsFileIdentityProbeResult> inspect(
    String canonicalPath,
  ) async {
    paths.add(canonicalPath);
    return result;
  }
}

final class _FakeWindowsDirectoryAuthorityProbe
    implements CockpitWindowsDirectoryAuthorityProbe {
  _FakeWindowsDirectoryAuthorityProbe(this.result);

  final CockpitWindowsFileIdentityProbeResult result;
  final List<String> paths = <String>[];

  @override
  Future<CockpitWindowsFileIdentityProbeResult> inspect(
    String canonicalPath,
  ) async {
    paths.add(canonicalPath);
    return result;
  }
}

const _incrementProcessSource = r'''
import 'dart:io';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';

final class CounterCodec implements CockpitJsonCodec<int> {
  const CounterCodec();
  @override
  int decode(Object? json) {
    if (json is! Map<Object?, Object?> ||
        json.length != 2 ||
        json['schemaVersion'] != 'counter/v2' ||
        json['value'] is! int) {
      throw const FormatException('Invalid counter/v2 document.');
    }
    return json['value']! as int;
  }
  @override
  Object? encode(int value) => <String, Object?>{
    'schemaVersion': 'counter/v2',
    'value': value,
  };
}

final class NoopSyncer implements CockpitDirectorySyncer {
  const NoopSyncer();
  @override
  Future<void> sync(String directoryPath) async {}
}

Future<void> main(List<String> arguments) async {
  final store = CockpitLockedJsonStore<int>(
    path: arguments[0],
    codec: const CounterCodec(),
    createInitial: () => 0,
    permissionHardener: Platform.isWindows
        ? const CockpitWindowsInheritedAclPermissionHardener()
        : const CockpitPosixPermissionHardener(),
    directorySyncer: const NoopSyncer(),
  );
  for (var index = 0; index < int.parse(arguments[1]); index += 1) {
    await store.transact<void>(
      (value) async => CockpitLockedJsonUpdate.write(value + 1, null),
    );
  }
}
''';
