import 'dart:io';

import 'package:cockpit/src/development/cockpit_checkout_identity.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('collapses symlink aliases for a non-Git checkout', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-checkout-identity-',
    );
    addTearDown(() async => temporary.delete(recursive: true));
    final checkout = await Directory(
      p.join(temporary.path, 'checkout'),
    ).create();
    final alias = Link(p.join(temporary.path, 'alias'));
    await alias.create(checkout.path);
    final resolver = CockpitCheckoutIdentityResolver(
      processRunner: (_, _, {workingDirectory, environment}) async =>
          ProcessResult(1, 128, '', 'not a git repository'),
    );

    final direct = await resolver.resolve(checkout.path);
    final linked = await resolver.resolve(alias.path);

    expect(linked.value, direct.value);
    expect(linked.canonicalRoot, direct.canonicalRoot);
    expect(direct.isGit, isFalse);
  });

  test('distinguishes worktrees sharing one Git common directory', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-worktree-identity-',
    );
    addTearDown(() async => temporary.delete(recursive: true));
    final common = await Directory(p.join(temporary.path, 'common')).create();
    final firstRoot = await Directory(p.join(temporary.path, 'first')).create();
    final secondRoot = await Directory(
      p.join(temporary.path, 'second'),
    ).create();
    final firstGit = await Directory(
      p.join(temporary.path, 'git-first'),
    ).create();
    final secondGit = await Directory(
      p.join(temporary.path, 'git-second'),
    ).create();
    CockpitCheckoutIdentityResolver resolverFor(
      Directory root,
      Directory gitDirectory,
    ) => CockpitCheckoutIdentityResolver(
      processRunner: (_, _, {workingDirectory, environment}) async =>
          ProcessResult(
            1,
            0,
            '${root.path}\n${common.path}\n${gitDirectory.path}\n',
            '',
          ),
    );

    final first = await resolverFor(
      firstRoot,
      firstGit,
    ).resolve(firstRoot.path);
    final second = await resolverFor(
      secondRoot,
      secondGit,
    ).resolve(secondRoot.path);

    expect(first.gitCommonDirectory, second.gitCommonDirectory);
    expect(first.gitDirectory, isNot(second.gitDirectory));
    expect(first.value, isNot(second.value));
  });

  test(
    'falls back to filesystem identity when git cannot be launched',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpit-checkout-identity-',
      );
      addTearDown(() async => temporary.delete(recursive: true));
      final resolver = CockpitCheckoutIdentityResolver(
        processRunner: (_, _, {workingDirectory, environment}) async {
          throw const ProcessException('git', <String>[], 'not found', 127);
        },
      );

      final identity = await resolver.resolve(temporary.path);

      expect(identity.isGit, isFalse);
      expect(
        identity.canonicalRoot,
        p.normalize(await temporary.resolveSymbolicLinks()),
      );
    },
  );
}
