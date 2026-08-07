/// dart:io transport implementations for acpd.
///
/// Provides:
/// - [StdioTransport] — wraps a process's stdin/stdout (or the current
///   process's) as a newline-delimited JSON [Transport].
/// - [AcpAgent] — spawns an agent subprocess, connects its stdio, and manages
///   the process lifecycle.
/// - [LineBufferedCodec] — frames raw byte streams as newline-delimited JSON
///   messages.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' as io show Process, ProcessSignal, stdin, stdout;

import 'package:acpd/acpd.dart';

/// The direction of a line on the wire, for tracing/debugging.
enum LineDirection {
  /// Client → agent.
  outbound,

  /// Agent → client.
  inbound,
}

/// Frames a byte stream into newline-delimited JSON-RPC messages.
///
/// Bytes are accumulated in a bounded buffer and split on `\n`. Each complete
/// line is strict-decoded as UTF-8 (malformed byte sequences deterministically
/// produce a parse error — never replacement-character corruption) and then
/// classified as a valid [RpcMessage] or a recoverable protocol violation via
/// [decodeLine].
///
/// The buffer is bounded by [maxLineBytes] (default 16 MiB, aligned with the
/// console ACP write ceiling and large document/session payloads). A line that
/// exceeds the ceiling emits exactly one [ErrorCode.parseError] outcome and the
/// codec discards bytes through the next newline, after which framing recovers
/// — a single runaway line never tears down the connection.
///
/// Recoverable transports consume [frames] (every outcome, including failures);
/// legacy callers may use [messages] (the valid-message subset). Incomplete
/// trailing data is held until more bytes arrive or [close] flushes it.
class LineBufferedCodec {
  /// Constructs a codec with an optional [maxLineBytes] line ceiling.
  LineBufferedCodec({this.maxLineBytes = 16 * 1024 * 1024})
      : _byteBuffer = Uint8List(_initialCapacity(maxLineBytes));

  static int _initialCapacity(int maximum) {
    if (maximum <= 0) {
      throw ArgumentError.value(maximum, 'maxLineBytes', 'Must be positive.');
    }
    return maximum < 8192 ? maximum : 8192;
  }

  /// Maximum number of bytes allowed in a single line (excluding the newline).
  ///
  /// A line that exceeds this ceiling produces one parse-error outcome and is
  /// discarded through its terminating newline, after which framing resumes.
  final int maxLineBytes;

  Uint8List _byteBuffer;
  int _byteLength = 0;
  final _messageController = StreamController<RpcMessage>.broadcast(sync: true);
  final _frameController = StreamController<DecodedLine>.broadcast(sync: true);

  /// The stream of valid decoded messages (the success subset of [frames]).
  ///
  /// Retained for backwards compatibility. Recoverable failures never appear
  /// here; they are only delivered on [frames].
  Stream<RpcMessage> get messages => _messageController.stream;

  /// The stream of per-line decode outcomes, including recoverable failures.
  ///
  /// Emits one [DecodedLine] per complete line. A valid line yields a message;
  /// a malformed line yields a [DecodedLine.failure]. Real framing overflows
  /// and malformed UTF-8 are reported here as [ErrorCode.parseError], never as
  /// stream errors.
  Stream<DecodedLine> get frames => _frameController.stream;

  /// Feeds raw bytes into the codec.
  ///
  /// Bytes are accumulated in [_byteBuffer] until a newline. A line that
  /// exceeds [maxLineBytes] emits exactly one parse-error and enters a
  /// discarding state: every subsequent byte up to and including the next
  /// newline is dropped, so a single runaway line produces exactly one error
  /// and framing recovers cleanly at the next line boundary.
  void add(List<int> bytes) {
    if (_closed) throw StateError('LineBufferedCodec is closed');
    for (final byte in bytes) {
      if (byte == 0x0A) {
        if (_discarding) {
          _discarding = false;
          _byteLength = 0;
          continue; // end of the discarded oversized line
        }
        _flushLine();
        continue;
      }
      if (_discarding) continue; // drop bytes from the oversized line
      if (_byteLength == maxLineBytes) {
        _emitOverLimit();
        continue;
      }
      _ensureCapacity(_byteLength + 1);
      _byteBuffer[_byteLength++] = byte;
    }
  }

  void _ensureCapacity(int required) {
    if (required <= _byteBuffer.length) return;
    var capacity = _byteBuffer.length * 2;
    if (capacity < required) capacity = required;
    if (capacity > maxLineBytes) capacity = maxLineBytes;
    final grown = Uint8List(capacity)..setRange(0, _byteLength, _byteBuffer);
    _byteBuffer = grown;
  }

  /// Whether bytes are being discarded following an over-limit line.
  bool _discarding = false;
  bool _closed = false;

  /// Signals end-of-stream, flushing any unterminated trailing line.
  ///
  /// A partial line held in the buffer when the stream ends is decoded and
  /// emitted (after CR stripping). If the codec was discarding an oversized
  /// line when the stream ended, the partial bytes are dropped.
  void close() {
    if (_closed) return;
    _closed = true;
    if (!_discarding && _byteLength > 0) {
      var end = _byteLength;
      if (_byteBuffer[end - 1] == 0x0D) end--;
      if (end > 0) {
        _decodeAndEmit(Uint8List.sublistView(_byteBuffer, 0, end));
      }
    }
    _byteLength = 0;
    _discarding = false;
    _messageController.close();
    _frameController.close();
  }

  void _flushLine() {
    // The LF that triggered this flush was NOT added to [_byteBuffer] (see
    // [add]); the buffer holds exactly the line's bytes. Strip a trailing CR
    // if present, then decode synchronously before reusing the buffer.
    var end = _byteLength;
    if (end > 0 && _byteBuffer[end - 1] == 0x0D) end--;
    if (end > 0) {
      _decodeAndEmit(Uint8List.sublistView(_byteBuffer, 0, end));
    }
    _byteLength = 0;
  }

  /// Emits a single parse-error for an over-limit line and enters the
  /// discarding state. The bytes accumulated so far (the oversized run) are
  /// dropped here; subsequent bytes are dropped in [add] until the LF resets
  /// the codec via the `_discarding` branch.
  void _emitOverLimit() {
    _discarding = true;
    final error = RpcError.fromCode(ErrorCode.parseError,
        data: {'reason': 'line exceeded $maxLineBytes bytes'});
    _frameController.add(DecodedLine.failure(error));
    // Preserve legacy messages-stream behavior: a malformed line surfaces as
    // an error on [messages]. Recoverable transports read [frames] instead and
    // never see this as a fatal stream error.
    _messageController.addError(error, StackTrace.current);
    _byteLength = 0;
  }

  void _decodeAndEmit(List<int> lineBytes) {
    String line;
    try {
      // Strict decode: no allowMalformed. A split multibyte sequence cannot
      // reach here because we only decode at newline boundaries, so every
      // code point is complete; a genuinely malformed sequence throws and
      // becomes a deterministic parse-error.
      line = utf8.decode(lineBytes);
    } catch (error, stackTrace) {
      final failure = RpcError.fromCode(
        ErrorCode.parseError,
        data: const {'reason': 'line is not valid UTF-8'},
      );
      _frameController.add(DecodedLine.failure(failure));
      // Legacy messages-stream parity: surface the decode failure as an error.
      _messageController.addError(error, stackTrace);
      return;
    }
    final outcome = decodeLine(line);
    _frameController.add(outcome);
    if (outcome.isMessage) {
      _messageController.add(outcome.message!);
    } else {
      // Legacy messages-stream parity: an invalid envelope surfaces as an error
      // on [messages], matching the previous decodeMessage-throwing behavior.
      _messageController.addError(outcome.failure!, StackTrace.current);
    }
  }
}

/// A [Transport] backed by a [LineBufferedCodec] reading from an input stream
/// and writing lines to an output sink.
class StdioTransport implements RecoverableTransport {
  StdioTransport({
    required Stream<List<int>> input,
    required void Function(List<int>) writeOutput,
    required Future<void> Function() onClose,
    String name = 'stdio',
    this.onSend,
    this.onReceive,
  })  : _writeOutput = writeOutput,
        _onClose = onClose,
        _name = name {
    _codec = LineBufferedCodec();
    _incoming = StreamController<RpcMessage>.broadcast();
    _failures = StreamController<DecodedLine>.broadcast();
    _sub = input.listen(
      (bytes) {
        _codec.add(bytes);
      },
      onError: _incoming.addError,
      onDone: () {
        _codec.close();
      },
    );
    _codecSub = _codec.frames.listen(
      (outcome) {
        if (outcome.isMessage) {
          final msg = outcome.message!;
          onReceive?.call(msg.toLine().trim());
          _incoming.add(msg);
        } else {
          // Recoverable decode failure: deliver to decodeOutcomes so the
          // Connection answers it without tearing down. Valid messages are
          // never double-delivered: incoming carries them, decodeOutcomes
          // carries only failures.
          _failures.add(outcome);
        }
      },
      onError: _incoming.addError,
      onDone: () {
        _failures.close();
        _incoming.close();
      },
    );
  }

  /// Wraps the current process's stdin/stdout as a [Transport].
  ///
  /// Convenience for building an agent that runs in the current process.
  static StdioTransport stdio({
    void Function(String line)? onSend,
    void Function(String line)? onReceive,
  }) {
    return StdioTransport(
      name: 'stdio',
      input: io.stdin,
      writeOutput: io.stdout.add,
      onClose: () async {
        await io.stdout.flush();
      },
      onSend: onSend,
      onReceive: onReceive,
    );
  }

  final void Function(List<int>) _writeOutput;
  final Future<void> Function() _onClose;
  final String _name;
  late final LineBufferedCodec _codec;
  late final StreamController<RpcMessage> _incoming;
  late final StreamController<DecodedLine> _failures;
  late final StreamSubscription<List<int>> _sub;
  late final StreamSubscription<DecodedLine> _codecSub;
  bool _closed = false;

  /// Optional trace callback invoked with each line sent to the peer.
  final void Function(String line)? onSend;

  /// Optional trace callback invoked with each line received from the peer.
  final void Function(String line)? onReceive;

  @override
  Stream<RpcMessage> get incoming => _incoming.stream;

  @override
  Stream<DecodedLine> get decodeOutcomes => _failures.stream;

  @override
  void send(RpcMessage message) {
    if (_closed) {
      throw StateError('Transport "$_name" is closed');
    }
    final line = message.toLine();
    onSend?.call(line.trim());
    _writeOutput(utf8.encode(line));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub.cancel();
    _codec.close();
    await _codecSub.cancel();
    await _failures.close();
    await _incoming.close();
    await _onClose();
  }
}

/// Configuration for spawning an ACP agent subprocess.
///
/// Mirrors the rust-sdk `AcpAgentConfig`: an executable plus args and env,
/// with a fluent builder API ([arg]/[args]/[env]/[envs]) and accessors
/// ([command]/[arguments]/[environment]).
class AcpAgentConfig {
  const AcpAgentConfig({
    required this.command,
    this.args = const [],
    this.env = const {},
    this.workingDirectory,
  });

  /// Creates a config for the given executable, ready for fluent chaining.
  factory AcpAgentConfig.forCommand(String command) =>
      AcpAgentConfig(command: command);

  /// The agent executable (absolute path or resolvable name).
  final String command;

  /// Command-line arguments.
  final List<String> args;

  /// Environment variables (merged with the parent environment).
  final Map<String, String> env;

  /// Working directory for the subprocess.
  final String? workingDirectory;

  /// Appends one argument, returning a new config.
  AcpAgentConfig withArg(String arg) => copyWith(args: [...args, arg]);

  /// Appends multiple arguments, returning a new config.
  AcpAgentConfig withArgs(Iterable<String> values) =>
      copyWith(args: [...args, ...values]);

  /// Sets one environment variable, returning a new config.
  AcpAgentConfig withEnv(String name, String value) =>
      copyWith(env: {...env, name: value});

  /// Sets multiple environment variables, returning a new config.
  AcpAgentConfig withEnvs(Map<String, String> values) =>
      copyWith(env: {...env, ...values});

  /// Returns a copy with the given fields overridden.
  AcpAgentConfig copyWith({
    String? command,
    List<String>? args,
    Map<String, String>? env,
    String? workingDirectory,
  }) =>
      AcpAgentConfig(
        command: command ?? this.command,
        args: args ?? this.args,
        env: env ?? this.env,
        workingDirectory: workingDirectory ?? this.workingDirectory,
      );

  /// Serializes to the JSON form used by [AcpAgent.fromJson].
  Map<String, Object?> toJson() => {
        'command': command,
        if (args.isNotEmpty) 'args': args,
        if (env.isNotEmpty) 'env': env,
        if (workingDirectory != null) 'workingDirectory': workingDirectory,
      };

  /// Parses a config from its JSON form.
  factory AcpAgentConfig.fromJson(Map<String, Object?> json) {
    return AcpAgentConfig(
      command: json['command'] as String,
      args: (json['args'] as List?)?.cast<String>() ?? const [],
      env: (json['env'] as Map?)?.cast<String, String>() ?? const {},
      workingDirectory: json['workingDirectory'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpAgentConfig &&
          command == other.command &&
          _listEq(args, other.args) &&
          _mapEq(env, other.env) &&
          workingDirectory == other.workingDirectory;

  @override
  int get hashCode =>
      Object.hash(command, Object.hashAll(args), env, workingDirectory);
}

bool _listEq(List<String> a, List<String> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEq(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (a[key] != b[key]) return false;
  }
  return true;
}

/// A running ACP agent subprocess connected over stdio.
///
/// Spawns the agent with [AcpAgentConfig], exposes a [StdioTransport] for
/// communication, captures stderr, and manages the process lifecycle. Use
/// [transport] to feed a [Connection]/role. Call [close] to terminate the
/// subprocess.
///
/// Mirrors the rust-sdk `AcpAgent`: supports spawning from a config, a command
/// string, or JSON; captures stderr into a bounded tail available via
/// [stderrTail]; and invokes an optional [onLine] trace callback for every
/// line sent or received.
class AcpAgent {
  AcpAgent._(
      this._process, this._transport, this._stderrController, this._onLine);

  final io.Process _process;
  final StdioTransport _transport;
  final StreamController<String> _stderrController;
  final void Function(String line, LineDirection direction)? _onLine;

  /// The transport for this agent.
  Transport get transport => _transport;

  /// The OS process id.
  int get pid => _process.pid;

  /// A future that completes with the agent's exit code when it terminates.
  Future<int> get exitCode => _process.exitCode;

  /// The trace callback registered at [AcpAgent.start], if any.
  void Function(String line, LineDirection direction)? get onLine => _onLine;

  /// A stream of captured stderr lines.
  ///
  /// Bounded to a tail (default 64 KiB) to avoid unbounded memory growth for
  /// noisy agents.
  Stream<String> get stderr => _stderrController.stream;

  /// Spawns an agent subprocess from an [AcpAgentConfig].
  ///
  /// [onLine], if given, is invoked for every line sent to or received from
  /// the agent, with its [LineDirection].
  static Future<AcpAgent> start(
    AcpAgentConfig config, {
    void Function(String line, LineDirection direction)? onLine,
  }) async {
    final process = await io.Process.start(
      config.command,
      config.args,
      workingDirectory: config.workingDirectory,
      environment: config.env,
      runInShell: false,
    );
    final stderrController = StreamController<String>.broadcast();
    // Capture stderr line-by-line, bounded.
    _StderrTail.bind(process.stderr, stderrController);
    final transport = StdioTransport(
      name: 'acp-agent:${process.pid}',
      input: process.stdout,
      writeOutput: process.stdin.add,
      onClose: () async {
        await process.stdin.flush().catchError((_) {});
        await process.stdin.close().catchError((_) {});
      },
      onSend: onLine == null
          ? null
          : (line) => onLine(line, LineDirection.outbound),
      onReceive:
          onLine == null ? null : (line) => onLine(line, LineDirection.inbound),
    );
    return AcpAgent._(process, transport, stderrController, onLine);
  }

  /// Parses a command string like `"python agent.py --flag"` and spawns it.
  ///
  /// Shell-words are split respecting quotes. Environment assignments
  /// (`NAME=value`) appearing before the command are extracted into the env.
  static Future<AcpAgent> fromCommandString(
    String input, {
    void Function(String line, LineDirection direction)? onLine,
  }) {
    return start(_parseCommandString(input), onLine: onLine);
  }

  /// Parses a JSON config object and spawns the agent.
  ///
  /// Accepts `{"command": "...", "args": [...], "env": {...}}`.
  static Future<AcpAgent> fromJson(
    Map<String, Object?> json, {
    void Function(String line, LineDirection direction)? onLine,
  }) {
    return start(AcpAgentConfig.fromJson(json), onLine: onLine);
  }

  /// Terminates the subprocess gracefully (SIGTERM then SIGKILL after a grace
  /// period), returning the exit code.
  Future<int> close() async {
    await _transport.close();
    final code = await _process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _process.kill(io.ProcessSignal.sigkill);
        return _process.exitCode;
      },
    );
    await _stderrController.close();
    return code;
  }

  /// Forcibly kills the subprocess.
  bool kill([io.ProcessSignal signal = io.ProcessSignal.sigkill]) =>
      _process.kill(signal);
}

/// Parses a command string into an [AcpAgentConfig].
///
/// Leading `NAME=value` tokens are treated as environment variables; the first
/// remaining token is the command, the rest are args.
AcpAgentConfig _parseCommandString(String input) {
  final tokens = _shellSplit(input);
  final env = <String, String>{};
  var i = 0;
  while (i < tokens.length) {
    final eq = _parseEnvVar(tokens[i]);
    if (eq != null) {
      env[eq.$1] = eq.$2;
      i++;
    } else {
      break;
    }
  }
  if (i >= tokens.length) {
    throw FormatException('No command found in: $input');
  }
  return AcpAgentConfig(
    command: tokens[i],
    args: tokens.sublist(i + 1),
    env: env,
  );
}

/// Minimal shell-like word splitting that respects single/double quotes.
List<String> _shellSplit(String input) {
  final result = <String>[];
  final buf = StringBuffer();
  var inSingle = false;
  var inDouble = false;
  var escape = false;
  var hasContent = false;
  for (final ch in input.codeUnits) {
    if (escape) {
      buf.writeCharCode(ch);
      escape = false;
      hasContent = true;
      continue;
    }
    if (ch == 0x5C /* \ */ && !inSingle) {
      escape = true;
      continue;
    }
    if (ch == 0x27 /* ' */ && !inDouble) {
      inSingle = !inSingle;
      hasContent = true;
      continue;
    }
    if (ch == 0x22 /* " */ && !inSingle) {
      inDouble = !inDouble;
      hasContent = true;
      continue;
    }
    if ((ch == 0x20 /* space */ || ch == 0x09 /* tab */) &&
        !inSingle &&
        !inDouble) {
      if (hasContent) {
        result.add(buf.toString());
        buf.clear();
        hasContent = false;
      }
      continue;
    }
    buf.writeCharCode(ch);
    hasContent = true;
  }
  if (hasContent) result.add(buf.toString());
  return result;
}

/// Parses a `NAME=value` env-var assignment, or null if not one.
(String, String)? _parseEnvVar(String s) {
  final eq = s.indexOf('=');
  if (eq <= 0) return null;
  final name = s.substring(0, eq);
  // Env-var names must be valid identifiers-ish (alnum + underscore).
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) return null;
  return (name, s.substring(eq + 1));
}

/// Bounded stderr capture: decodes bytes, splits on newlines, and forwards to
/// a sink while keeping only the last [_maxBytes] of decoded text.
class _StderrTail {
  static const _maxBytes = 64 * 1024;

  static void bind(Stream<List<int>> input, StreamSink<String> output) {
    final buf = StringBuffer();
    input.listen((bytes) {
      buf.write(utf8.decode(bytes, allowMalformed: true));
      var content = buf.toString();
      // Trim to the tail bound, keeping whole lines.
      if (content.length > _maxBytes) {
        final cut = content.indexOf('\n', content.length - _maxBytes);
        content = cut >= 0 ? content.substring(cut + 1) : '';
      }
      var newlineIdx = content.indexOf('\n');
      while (newlineIdx >= 0) {
        final line = content.substring(0, newlineIdx);
        content = content.substring(newlineIdx + 1);
        if (line.isNotEmpty) output.add(line);
        newlineIdx = content.indexOf('\n');
      }
      buf
        ..clear()
        ..write(content);
    }, onDone: () {
      final remaining = buf.toString().trim();
      if (remaining.isNotEmpty) output.add(remaining);
    });
  }
}
