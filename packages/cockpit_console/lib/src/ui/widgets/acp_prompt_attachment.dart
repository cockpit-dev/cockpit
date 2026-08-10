import 'dart:convert';
import 'dart:io';

import 'package:acpd/acpd.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

const acpMaximumInlineAttachmentBytes = 8 * 1024 * 1024;
const acpMaximumPromptInlineBytes = 10 * 1024 * 1024;

enum AcpPromptAttachmentKind { image, audio, embeddedContext, fileLink }

final class AcpPromptAttachment {
  const AcpPromptAttachment({
    required this.kind,
    required this.name,
    required this.detail,
    required this.identity,
    required this.content,
    required this.sourceBytes,
    required this.inlineBytes,
  });

  final AcpPromptAttachmentKind kind;
  final String name;
  final String detail;
  final String identity;
  final ContentBlock content;
  final int sourceBytes;
  final int inlineBytes;
}

final class AcpPromptAttachmentException implements Exception {
  const AcpPromptAttachmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<AcpPromptAttachment?> pickAcpPromptAttachment(
  AcpPromptAttachmentKind kind,
) async {
  final result = await FilePicker.pickFiles(
    allowMultiple: false,
    withData: false,
    type: switch (kind) {
      AcpPromptAttachmentKind.image => FileType.custom,
      AcpPromptAttachmentKind.audio => FileType.custom,
      AcpPromptAttachmentKind.embeddedContext ||
      AcpPromptAttachmentKind.fileLink => FileType.any,
    },
    allowedExtensions: switch (kind) {
      AcpPromptAttachmentKind.image => _imageExtensions,
      AcpPromptAttachmentKind.audio => _audioExtensions,
      AcpPromptAttachmentKind.embeddedContext ||
      AcpPromptAttachmentKind.fileLink => null,
    },
    dialogTitle: switch (kind) {
      AcpPromptAttachmentKind.image => 'Attach image',
      AcpPromptAttachmentKind.audio => 'Attach audio',
      AcpPromptAttachmentKind.embeddedContext => 'Embed context file',
      AcpPromptAttachmentKind.fileLink => 'Link file',
    },
  );
  if (result == null) return null;
  final path = result.files.single.path;
  if (path == null || path.isEmpty) {
    throw const AcpPromptAttachmentException(
      'The selected file does not expose a local path.',
    );
  }
  return loadAcpPromptAttachment(path, kind);
}

Future<AcpPromptAttachment> loadAcpPromptAttachment(
  String path,
  AcpPromptAttachmentKind kind,
) async {
  final file = File(path);
  final stat = await file.stat();
  if (stat.type != FileSystemEntityType.file) {
    throw const AcpPromptAttachmentException(
      'The selected path is not a regular file.',
    );
  }
  final canonicalPath = await file.resolveSymbolicLinks();
  final name = p.basename(canonicalPath);
  final mimeType = acpMimeTypeForPath(canonicalPath);
  final uri = Uri.file(canonicalPath).toString();
  final sourceBytes = stat.size;

  if (kind == AcpPromptAttachmentKind.fileLink) {
    return AcpPromptAttachment(
      kind: kind,
      name: name,
      detail: '$mimeType · ${formatAcpByteSize(sourceBytes)} · linked',
      identity: 'link:$uri',
      content: ResourceLink(
        name: name,
        uri: uri,
        mimeType: mimeType,
        size: sourceBytes,
      ),
      sourceBytes: sourceBytes,
      inlineBytes: 0,
    );
  }

  _validateInlineFileSize(sourceBytes);
  final bytes = await file.readAsBytes();
  return switch (kind) {
    AcpPromptAttachmentKind.image => _imageAttachment(
      name: name,
      uri: uri,
      mimeType: mimeType,
      bytes: bytes,
    ),
    AcpPromptAttachmentKind.audio => _audioAttachment(
      name: name,
      uri: uri,
      mimeType: mimeType,
      bytes: bytes,
    ),
    AcpPromptAttachmentKind.embeddedContext => _contextAttachment(
      name: name,
      uri: uri,
      mimeType: mimeType,
      bytes: bytes,
    ),
    AcpPromptAttachmentKind.fileLink => throw StateError('Handled above.'),
  };
}

AcpPromptAttachment createAcpResourceLink({
  required String name,
  required Uri uri,
  String? description,
  String? mimeType,
}) {
  final cleanName = name.trim();
  if (cleanName.isEmpty || !uri.hasScheme) {
    throw const AcpPromptAttachmentException(
      'Resource links require a name and an absolute URI.',
    );
  }
  final value = uri.toString();
  return AcpPromptAttachment(
    kind: AcpPromptAttachmentKind.fileLink,
    name: cleanName,
    detail: mimeType == null ? value : '$mimeType · $value',
    identity: 'link:$value',
    content: ResourceLink(
      name: cleanName,
      uri: value,
      description: description?.trim().isEmpty ?? true
          ? null
          : description!.trim(),
      mimeType: mimeType?.trim().isEmpty ?? true ? null : mimeType!.trim(),
    ),
    sourceBytes: 0,
    inlineBytes: 0,
  );
}

void validateAcpPromptAttachmentBudget(
  Iterable<AcpPromptAttachment> attachments,
) {
  final total = attachments.fold<int>(
    0,
    (sum, attachment) => sum + attachment.inlineBytes,
  );
  if (total > acpMaximumPromptInlineBytes) {
    throw AcpPromptAttachmentException(
      'Inline attachments use ${formatAcpByteSize(total)}. The prompt limit is '
      '${formatAcpByteSize(acpMaximumPromptInlineBytes)}.',
    );
  }
}

String acpMimeTypeForPath(String path) {
  final extension = p.extension(path).toLowerCase();
  return _mimeTypes[extension] ?? 'application/octet-stream';
}

String formatAcpByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(kib < 10 ? 1 : 0)} KiB';
  final mib = kib / 1024;
  return '${mib.toStringAsFixed(mib < 10 ? 1 : 0)} MiB';
}

AcpPromptAttachment _imageAttachment({
  required String name,
  required String uri,
  required String mimeType,
  required List<int> bytes,
}) {
  if (!mimeType.startsWith('image/')) {
    throw AcpPromptAttachmentException(
      '“$name” is not a supported image file.',
    );
  }
  return AcpPromptAttachment(
    kind: AcpPromptAttachmentKind.image,
    name: name,
    detail: '$mimeType · ${formatAcpByteSize(bytes.length)}',
    identity: 'image:$uri',
    content: ImageContent(
      data: base64Encode(bytes),
      mimeType: mimeType,
      uri: uri,
    ),
    sourceBytes: bytes.length,
    inlineBytes: bytes.length,
  );
}

AcpPromptAttachment _audioAttachment({
  required String name,
  required String uri,
  required String mimeType,
  required List<int> bytes,
}) {
  if (!mimeType.startsWith('audio/')) {
    throw AcpPromptAttachmentException(
      '“$name” is not a supported audio file.',
    );
  }
  return AcpPromptAttachment(
    kind: AcpPromptAttachmentKind.audio,
    name: name,
    detail: '$mimeType · ${formatAcpByteSize(bytes.length)}',
    identity: 'audio:$uri',
    content: AudioContent(data: base64Encode(bytes), mimeType: mimeType),
    sourceBytes: bytes.length,
    inlineBytes: bytes.length,
  );
}

AcpPromptAttachment _contextAttachment({
  required String name,
  required String uri,
  required String mimeType,
  required List<int> bytes,
}) {
  late final ResourceContents resource;
  if (_isTextMime(mimeType)) {
    try {
      resource = TextResourceContents(
        text: utf8.decode(bytes),
        uri: uri,
        mimeType: mimeType,
      );
    } on FormatException {
      resource = BlobResourceContents(
        blob: base64Encode(bytes),
        uri: uri,
        mimeType: mimeType,
      );
    }
  } else {
    resource = BlobResourceContents(
      blob: base64Encode(bytes),
      uri: uri,
      mimeType: mimeType,
    );
  }
  return AcpPromptAttachment(
    kind: AcpPromptAttachmentKind.embeddedContext,
    name: name,
    detail: '$mimeType · ${formatAcpByteSize(bytes.length)} · embedded',
    identity: 'resource:$uri',
    content: EmbeddedResource(resource: resource),
    sourceBytes: bytes.length,
    inlineBytes: bytes.length,
  );
}

void _validateInlineFileSize(int bytes) {
  if (bytes == 0) {
    throw const AcpPromptAttachmentException('The selected file is empty.');
  }
  if (bytes > acpMaximumInlineAttachmentBytes) {
    throw AcpPromptAttachmentException(
      'The selected file is ${formatAcpByteSize(bytes)}. Inline attachments '
      'are limited to ${formatAcpByteSize(acpMaximumInlineAttachmentBytes)}.',
    );
  }
}

bool _isTextMime(String mimeType) =>
    mimeType.startsWith('text/') ||
    const {
      'application/json',
      'application/ld+json',
      'application/toml',
      'application/xml',
      'application/yaml',
    }.contains(mimeType);

const _imageExtensions = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'];
const _audioExtensions = ['wav', 'mp3', 'm4a', 'aac', 'flac', 'ogg', 'opus'];

const _mimeTypes = <String, String>{
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.bmp': 'image/bmp',
  '.wav': 'audio/wav',
  '.mp3': 'audio/mpeg',
  '.m4a': 'audio/mp4',
  '.aac': 'audio/aac',
  '.flac': 'audio/flac',
  '.ogg': 'audio/ogg',
  '.opus': 'audio/opus',
  '.txt': 'text/plain',
  '.md': 'text/markdown',
  '.dart': 'text/x-dart',
  '.json': 'application/json',
  '.jsonl': 'application/x-ndjson',
  '.yaml': 'application/yaml',
  '.yml': 'application/yaml',
  '.toml': 'application/toml',
  '.xml': 'application/xml',
  '.html': 'text/html',
  '.css': 'text/css',
  '.js': 'text/javascript',
  '.ts': 'text/typescript',
  '.csv': 'text/csv',
  '.svg': 'image/svg+xml',
  '.pdf': 'application/pdf',
  '.zip': 'application/zip',
};
