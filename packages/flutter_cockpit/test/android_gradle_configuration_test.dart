import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Android plugin applies Kotlin wiring for its Kotlin sources', () {
    final buildFile = _packageFile('android/build.gradle');
    expect(buildFile.existsSync(), isTrue);

    final source = buildFile.readAsStringSync();
    expect(source, contains('src/main/kotlin'));
    expect(source, contains('id "org.jetbrains.kotlin.android"'));
    expect(source, contains('id "com.android.library"'));
    expect(source, isNot(contains('apply plugin:')));
    expect(source, contains('org.jetbrains.kotlin:kotlin-gradle-plugin'));
    expect(source, contains('tasks.withType'));
    expect(source, contains('KotlinCompile'));
    expect(source, contains('jvmTarget = "17"'));
    expect(source, isNot(contains('kotlin {')));
    expect(source, isNot(contains('JvmTarget.JVM_17')));
  });
}

File _packageFile(String relativePath) {
  final workspaceFile = File('packages/flutter_cockpit/$relativePath');
  if (workspaceFile.existsSync()) {
    return workspaceFile;
  }
  return File(relativePath);
}
