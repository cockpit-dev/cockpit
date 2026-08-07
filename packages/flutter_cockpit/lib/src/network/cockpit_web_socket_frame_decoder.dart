import 'dart:typed_data';

typedef CockpitDecodedWebSocketFrame = ({
  int opcode,
  bool finalFragment,
  bool compressed,
  bool textPayload,
  int payloadBytes,
  Uint8List previewBytes,
});

final class CockpitWebSocketFrameDecoder {
  CockpitWebSocketFrameDecoder({
    required this.maxPreviewBytes,
    required this.onFrame,
  });

  final int maxPreviewBytes;
  final void Function(CockpitDecodedWebSocketFrame frame) onFrame;

  final List<int> _header = <int>[];
  final BytesBuilder _preview = BytesBuilder(copy: false);
  int _headerBytes = 2;
  int _opcode = 0;
  int _payloadBytes = 0;
  int _payloadRemaining = -1;
  int _payloadRead = 0;
  bool _finalFragment = true;
  bool _compressed = false;
  bool _textPayload = false;
  int? _messageOpcode;
  bool _messageCompressed = false;
  List<int>? _mask;

  void add(List<int> bytes) {
    var offset = 0;
    while (offset < bytes.length) {
      if (_payloadRemaining < 0) {
        offset = _readHeader(bytes, offset);
        if (_payloadRemaining < 0) continue;
        if (_payloadRemaining == 0) _emit();
        continue;
      }

      final available = bytes.length - offset;
      final count = available < _payloadRemaining
          ? available
          : _payloadRemaining;
      _capturePreview(bytes, offset, count);
      offset += count;
      _payloadRead += count;
      _payloadRemaining -= count;
      if (_payloadRemaining == 0) _emit();
    }
  }

  int _readHeader(List<int> bytes, int offset) {
    while (offset < bytes.length && _header.length < _headerBytes) {
      _header.add(bytes[offset]);
      offset += 1;
      if (_header.length == 2) {
        final lengthCode = _header[1] & 0x7f;
        final extended = lengthCode == 126
            ? 2
            : lengthCode == 127
            ? 8
            : 0;
        _headerBytes = 2 + extended + ((_header[1] & 0x80) != 0 ? 4 : 0);
      }
    }
    if (_header.length != _headerBytes) return offset;

    final first = _header[0];
    final second = _header[1];
    _finalFragment = (first & 0x80) != 0;
    _compressed = (first & 0x40) != 0;
    _opcode = first & 0x0f;
    if (_opcode == 1 || _opcode == 2) {
      _messageOpcode = _opcode;
      _messageCompressed = _compressed;
    }
    _textPayload = _opcode == 1 || (_opcode == 0 && _messageOpcode == 1);
    if (_opcode == 0) _compressed = _messageCompressed;
    final lengthCode = second & 0x7f;
    var cursor = 2;
    if (lengthCode < 126) {
      _payloadBytes = lengthCode;
    } else if (lengthCode == 126) {
      _payloadBytes = (_header[cursor] << 8) | _header[cursor + 1];
      cursor += 2;
    } else {
      if ((_header[cursor] & 0x80) != 0) {
        _reset();
        return offset;
      }
      var length = 0;
      for (var index = 0; index < 8; index += 1) {
        length = (length << 8) | _header[cursor + index];
      }
      _payloadBytes = length;
      cursor += 8;
    }
    if ((second & 0x80) != 0) {
      _mask = _header.sublist(cursor, cursor + 4);
    }
    _payloadRemaining = _payloadBytes;
    _payloadRead = 0;
    return offset;
  }

  void _capturePreview(List<int> bytes, int offset, int count) {
    if (_compressed || !_textPayload) return;
    final remaining = maxPreviewBytes - _preview.length;
    if (remaining <= 0) return;
    final captured = count < remaining ? count : remaining;
    final mask = _mask;
    if (mask == null) {
      _preview.add(bytes.sublist(offset, offset + captured));
      return;
    }
    _preview.add(<int>[
      for (var index = 0; index < captured; index += 1)
        bytes[offset + index] ^ mask[(_payloadRead + index) % 4],
    ]);
  }

  void _emit() {
    final preview = _preview.takeBytes();
    if (_opcode <= 2 || (_opcode >= 8 && _opcode <= 10)) {
      try {
        onFrame((
          opcode: _opcode,
          finalFragment: _finalFragment,
          compressed: _compressed,
          textPayload: _textPayload,
          payloadBytes: _payloadBytes,
          previewBytes: preview,
        ));
      } on Object {
        // Passive frame diagnostics must never affect the observed socket.
      }
    }
    if (_finalFragment && _opcode <= 2) {
      _messageOpcode = null;
      _messageCompressed = false;
    }
    _reset();
  }

  void _reset() {
    _header.clear();
    _preview.clear();
    _headerBytes = 2;
    _opcode = 0;
    _payloadBytes = 0;
    _payloadRemaining = -1;
    _payloadRead = 0;
    _finalFragment = true;
    _compressed = false;
    _textPayload = false;
    _mask = null;
  }
}
