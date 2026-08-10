import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    stderr.writeln('Expected LOCK READY RELEASE paths.');
    exitCode = 64;
    return;
  }
  final lock = await File(arguments[0]).open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.blockingExclusive);
    await File(arguments[1]).writeAsString('ready');
    final release = File(arguments[2]);
    while (!await release.exists()) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  } finally {
    await lock.unlock();
    await lock.close();
  }
}
