/// Scenario definitions: declarative goal + command sequences that the
/// recorder executes against a live Cockpit session.
///
/// Schema (`cockpit.training/scenario-v1`):
///
/// ```yaml
/// schema: cockpit.training/scenario-v1
/// id: settings_dark_mode
/// app:
///   name: cockpit_demo
///   directory: examples/cockpit_demo/cockpit
///   platform: macos
/// goal: Turn on dark mode in settings
/// paraphrases: [switch the theme to dark, enable dark mode]
/// completion: Dark mode is on; verified via inspect.
/// includeSetup: false
/// steps:
///   - action: tap
///     selector: Settings
///     expect: {ok: true}
///   - action: type
///     text: hello
///     into: Message
///   - action: screenshot
///   - command: cockpit dev status
///     timeoutMs: 5000
/// ```
library;

import 'package:yaml/yaml.dart';

const String scenarioSchema = 'cockpit.training/scenario-v1';

/// What the recorder does when a step expectation is not met.
enum ScenarioFailurePolicy { abort, continueRun }

class ScenarioFormatException implements Exception {
  ScenarioFormatException(this.issues) : message = issues.join('\n');

  final List<String> issues;
  final String message;

  @override
  String toString() => 'Invalid scenario:\n$message';
}

class ScenarioApp {
  const ScenarioApp({
    required this.name,
    required this.directory,
    required this.platform,
  });

  final String name;
  final String directory;
  final String platform;
}

/// Expectation for a step: `ok` compares against the exit code (default
/// true); `code`, when set on a failing step, requires the error code to
/// appear in the observation or stderr.
class ScenarioExpectation {
  const ScenarioExpectation({required this.ok, this.code});

  final bool ok;
  final String? code;

  Map<String, Object?> toJson() => <String, Object?>{
    'ok': ok,
    if (code != null) 'code': code,
  };
}

class ScenarioStep {
  const ScenarioStep({
    this.action,
    this.command,
    this.selector,
    this.text,
    this.into,
    this.key,
    this.args = const <String>[],
    this.timeoutMs = 30000,
    this.expect = const ScenarioExpectation(ok: true),
    this.onFailure = ScenarioFailurePolicy.abort,
  });

  final String? action;
  final String? command;

  /// Positional selector for selector-taking actions such as `tap`.
  final String? selector;
  final String? text;
  final String? into;
  final String? key;
  final List<String> args;
  final int timeoutMs;
  final ScenarioExpectation expect;
  final ScenarioFailurePolicy onFailure;

  bool get isScreenshot => action == 'screenshot';

  /// Executable argv without the binary: `dev tap Settings --session h`.
  ///
  /// [screenshotPath] is the absolute output path the recorder prepared for
  /// screenshot steps; it collapses to the file name in [displayCommand].
  List<String> buildArgv({
    required String sessionHandle,
    required String screenshotPath,
  }) {
    final argv = <String>[];
    if (command != null) {
      final tokens = command!.trim().split(RegExp(r'\s+'));
      if (tokens.first == 'cockpit') {
        tokens.removeAt(0);
      }
      argv.addAll(tokens);
    } else {
      final action = this.action!;
      argv
        ..add('dev')
        ..add(action);
      switch (action) {
        case 'type':
          if (text != null) {
            argv.add(text!);
          }
          if (into != null) {
            argv
              ..add('--into')
              ..add(into!);
          }
        case 'press':
          if (key != null) {
            argv.add(key!);
          }
        case 'screenshot':
          argv
            ..add('--save')
            ..add(screenshotPath);
        default:
          if (selector != null) {
            argv.add(selector!);
          }
      }
      argv.addAll(args);
    }
    argv
      ..add('--session')
      ..add(sessionHandle);
    return argv;
  }

  /// The command string recorded in the trajectory: the semantic agent
  /// command with tokens that contain whitespace single-quoted.
  String displayCommand({
    required String sessionHandle,
    required String screenshotName,
  }) {
    final argv = buildArgv(
      sessionHandle: sessionHandle,
      screenshotPath: screenshotName,
    );
    return [
      'cockpit',
      ...argv,
    ].map((token) => token.contains(' ') ? "'$token'" : token).join(' ');
  }

  /// Whether an executed result satisfies this step's expectation.
  bool evaluate({
    required int exitCode,
    required String stdout,
    required String stderr,
    required bool timedOut,
  }) {
    if (expect.ok) {
      return !timedOut && exitCode == 0;
    }
    final failed = timedOut || exitCode != 0;
    if (!failed) return false;
    final code = expect.code;
    if (code == null) return true;
    return stdout.contains(code) || stderr.contains(code);
  }
}

class Scenario {
  const Scenario({
    required this.id,
    required this.app,
    required this.goal,
    required this.paraphrases,
    required this.completion,
    required this.includeSetup,
    required this.steps,
  });

  final String id;
  final ScenarioApp app;
  final String goal;
  final List<String> paraphrases;
  final String completion;
  final bool includeSetup;
  final List<ScenarioStep> steps;
}

/// Parses a scenario document. Throws [ScenarioFormatException] listing
/// every validation issue at once.
Scenario parseScenario(String source, {required String sourceName}) {
  final issues = <String>[];
  Object? document;
  try {
    document = loadYaml(source);
  } on YamlException catch (error) {
    throw ScenarioFormatException([
      '$sourceName: YAML syntax error: ${error.message}',
    ]);
  }
  if (document is! Map) {
    throw ScenarioFormatException(['$sourceName: document must be a mapping.']);
  }
  final root = _plainMap(document);

  if (root['schema'] != scenarioSchema) {
    issues.add(
      "$sourceName: unsupported schema '${root['schema']}' "
      "(expected '$scenarioSchema').",
    );
  }

  String? requireString(String field) {
    final value = root[field];
    if (value is! String || value.isEmpty) {
      issues.add("$sourceName: '$field' must be a non-empty string.");
      return null;
    }
    return value;
  }

  final id = requireString('id');
  final goal = requireString('goal');
  final completion = requireString('completion');

  final appNode = root['app'];
  final ScenarioApp? app;
  if (appNode is! Map) {
    issues.add("$sourceName: 'app' must be a mapping.");
    app = null;
  } else {
    final map = _plainMap(appNode);
    String? appField(String field) {
      final value = map[field];
      if (value is! String || value.isEmpty) {
        issues.add("$sourceName: 'app.$field' must be a non-empty string.");
        return null;
      }
      return value;
    }

    final name = appField('name');
    final directory = appField('directory');
    final platform = appField('platform');
    app = name == null || directory == null || platform == null
        ? null
        : ScenarioApp(name: name, directory: directory, platform: platform);
  }

  final paraphrasesNode = root['paraphrases'];
  final paraphrases = <String>[];
  if (paraphrasesNode == null) {
    // Optional field.
  } else if (paraphrasesNode is! List) {
    issues.add("$sourceName: 'paraphrases' must be a list of strings.");
  } else {
    for (final entry in paraphrasesNode) {
      if (entry is String && entry.isNotEmpty) {
        paraphrases.add(entry);
      } else {
        issues.add("$sourceName: 'paraphrases' entries must be non-empty.");
      }
    }
  }

  final includeSetupNode = root['includeSetup'];
  final bool includeSetup;
  if (includeSetupNode == null) {
    includeSetup = false;
  } else if (includeSetupNode is! bool) {
    issues.add("$sourceName: 'includeSetup' must be a boolean.");
    includeSetup = false;
  } else {
    includeSetup = includeSetupNode;
  }

  final stepsNode = root['steps'];
  final steps = <ScenarioStep>[];
  if (stepsNode is! List || stepsNode.isEmpty) {
    issues.add("$sourceName: 'steps' must be a non-empty list.");
  } else {
    for (var i = 0; i < stepsNode.length; i++) {
      final node = stepsNode[i];
      if (node is! Map) {
        issues.add("${_stepName(sourceName, i)}: must be a mapping.");
        continue;
      }
      final step = _parseStep(
        _plainMap(node),
        _stepName(sourceName, i),
        issues,
      );
      if (step != null) steps.add(step);
    }
  }

  if (issues.isNotEmpty) throw ScenarioFormatException(issues);

  return Scenario(
    id: id!,
    app: app!,
    goal: goal!,
    paraphrases: paraphrases,
    completion: completion!,
    includeSetup: includeSetup,
    steps: steps,
  );
}

String _stepName(String sourceName, int index) => '$sourceName: steps[$index]';

ScenarioStep? _parseStep(
  Map<String, Object?> node,
  String name,
  List<String> issues,
) {
  final issueCountBefore = issues.length;

  final action = node['action'];
  final command = node['command'];
  if ((action == null) == (command == null)) {
    issues.add("$name: exactly one of 'action' or 'command' is required.");
  } else if (action is String && action.isEmpty) {
    issues.add("$name: 'action' must be a non-empty string.");
  } else if (command is String && command.isEmpty) {
    issues.add("$name: 'command' must be a non-empty string.");
  }

  String? optionalString(String field) {
    final value = node[field];
    if (value == null) return null;
    if (value is! String || value.isEmpty) {
      issues.add("$name: '$field' must be a non-empty string.");
      return null;
    }
    return value;
  }

  final selector = optionalString('selector');
  final text = optionalString('text');
  final into = optionalString('into');
  final key = optionalString('key');

  final argsNode = node['args'];
  final args = <String>[];
  if (argsNode != null && argsNode is! List) {
    issues.add("$name: 'args' must be a list of strings.");
  } else if (argsNode is List) {
    for (final entry in argsNode) {
      if (entry is String) {
        args.add(entry);
      } else {
        issues.add("$name: 'args' entries must be strings.");
      }
    }
  }

  final timeoutNode = node['timeoutMs'];
  var timeoutMs = 30000;
  if (timeoutNode != null && (timeoutNode is! int || timeoutNode <= 0)) {
    issues.add("$name: 'timeoutMs' must be a positive integer.");
  } else if (timeoutNode is int) {
    timeoutMs = timeoutNode;
  }

  final expectNode = node['expect'];
  var expect = const ScenarioExpectation(ok: true);
  if (expectNode != null && expectNode is! Map) {
    issues.add("$name: 'expect' must be a mapping.");
  } else if (expectNode is Map) {
    final map = _plainMap(expectNode);
    final okNode = map['ok'] ?? true;
    final codeNode = map['code'];
    if (okNode is! bool) {
      issues.add("$name: 'expect.ok' must be a boolean.");
    } else if (codeNode != null && codeNode is! String) {
      issues.add("$name: 'expect.code' must be a string.");
    } else {
      expect = ScenarioExpectation(ok: okNode, code: codeNode as String?);
    }
  }

  final onFailureNode = node['onFailure'];
  var onFailure = ScenarioFailurePolicy.abort;
  if (onFailureNode != null && onFailureNode is! String) {
    issues.add("$name: 'onFailure' must be a string.");
  } else if (onFailureNode == 'abort' || onFailureNode == null) {
    onFailure = ScenarioFailurePolicy.abort;
  } else if (onFailureNode == 'continue') {
    onFailure = ScenarioFailurePolicy.continueRun;
  } else {
    issues.add(
      "$name: 'onFailure' must be 'abort' or 'continue' "
      "(got '$onFailureNode').",
    );
  }

  // Only this step's issues invalidate this step; earlier issues belong to
  // other fields/steps and are reported at the end of parseScenario.
  if (issues.length != issueCountBefore) return null;

  return ScenarioStep(
    action: action is String ? action : null,
    command: command is String ? command : null,
    selector: selector,
    text: text,
    into: into,
    key: key,
    args: args,
    timeoutMs: timeoutMs,
    expect: expect,
    onFailure: onFailure,
  );
}

/// Converts a YAML node mapping into plain Dart maps/lists so the rest of
/// the parser works with `Map<String, Object?>` only.
Map<String, Object?> _plainMap(Map<dynamic, dynamic> node) {
  final result = <String, Object?>{};
  for (final entry in node.entries) {
    if (entry.key is! String) continue;
    final value = entry.value;
    result[entry.key as String] = value is YamlList
        ? value.toList()
        : value is YamlMap
        ? _plainMap(value)
        : value;
  }
  return result;
}
