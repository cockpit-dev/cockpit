/// The acpd library — Dart SDK for the [Agent Client Protocol (ACP)][acp].
///
/// ACP is a JSON-RPC 2.0 based protocol standardizing communication between
/// code editors/IDEs and AI-powered coding agents. This package provides:
///
/// - **Schema types**: strongly-typed definitions of all ACP v1 wire messages.
/// - **JSON-RPC engine**: request/response correlation, notifications,
///   cancellation, and extension methods.
/// - **Roles**: [Client] and [Agent] abstractions with typed handler builders.
/// - **Session**: a high-level helper for the prompt-turn lifecycle.
///
/// Platform-specific transports live in companion packages:
/// - `package:acpd_io` — Stdio and process-based ([AcpAgent]) transports.
/// - `package:acpd_http` — HTTP/SSE and WebSocket transports.
/// - `package:acpd_test` — in-memory transport pair and mock roles.
///
/// [acp]: https://agentclientprotocol.com/
library;

// JSON codec helpers
export 'src/json_codec.dart';

// Schema — enums & primitives
export 'src/schema/enums.dart';
export 'src/schema/annotations.dart';
export 'src/schema/resource_contents.dart';
export 'src/schema/content.dart';
export 'src/schema/tool_call_content.dart';
export 'src/schema/tool_call.dart';
export 'src/schema/plan.dart';
export 'src/schema/updates.dart';
export 'src/schema/session_config.dart';
export 'src/schema/session_modes.dart';
export 'src/schema/session_update.dart';
export 'src/schema/mcp_server.dart';
export 'src/schema/capabilities.dart';
export 'src/schema/auth.dart';
export 'src/schema/requests.dart';
export 'src/schema/prompt_fs.dart';
export 'src/schema/terminal_permission.dart';

// JSON-RPC engine
export 'src/jsonrpc/message.dart';
export 'src/jsonrpc/connection.dart';

// Transport abstraction
export 'src/transport/transport.dart';

// Roles
export 'src/role/role.dart';

// Session helper
export 'src/session/session.dart';
