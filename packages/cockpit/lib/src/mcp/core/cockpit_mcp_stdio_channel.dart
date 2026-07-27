import 'dart:async';

import 'package:dart_mcp/stdio.dart' as dart_mcp;
import 'package:stream_channel/stream_channel.dart';

StreamChannel<String> cockpitMcpStdioChannel({
  required Stream<List<int>> input,
  required StreamSink<List<int>> output,
}) {
  return dart_mcp.stdioChannel(input: input, output: output);
}
