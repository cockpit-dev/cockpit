import 'dart:convert';
import 'dart:io';

import 'package:acpd/acpd.dart';
import 'package:cockpit_console/src/ui/widgets/acp_prompt_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('acp_attachment_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('embeds UTF-8 context with the ACP resource discriminator', () async {
    final file = File(p.join(root.path, 'context.md'))
      ..writeAsStringSync('# Context');

    final attachment = await loadAcpPromptAttachment(
      file.path,
      AcpPromptAttachmentKind.embeddedContext,
    );

    expect(attachment.content, isA<EmbeddedResource>());
    expect(attachment.content.type, 'resource');
    final resource = (attachment.content as EmbeddedResource).resource;
    expect(resource, isA<TextResourceContents>());
    expect((resource as TextResourceContents).text, '# Context');
    expect(resource.mimeType, 'text/markdown');
  });

  test('embeds binary context without corrupting bytes', () async {
    final bytes = <int>[0, 255, 1, 2, 3];
    final file = File(p.join(root.path, 'context.bin'))
      ..writeAsBytesSync(bytes);

    final attachment = await loadAcpPromptAttachment(
      file.path,
      AcpPromptAttachmentKind.embeddedContext,
    );

    final resource = (attachment.content as EmbeddedResource).resource;
    expect(resource, isA<BlobResourceContents>());
    expect(base64Decode((resource as BlobResourceContents).blob), bytes);
  });

  test('loads supported image as inline base64 content', () async {
    final bytes = <int>[137, 80, 78, 71];
    final file = File(p.join(root.path, 'image.png'))..writeAsBytesSync(bytes);

    final attachment = await loadAcpPromptAttachment(
      file.path,
      AcpPromptAttachmentKind.image,
    );

    final image = attachment.content as ImageContent;
    expect(image.mimeType, 'image/png');
    expect(base64Decode(image.data), bytes);
    expect(attachment.inlineBytes, bytes.length);
  });

  test('audio attachment identity uses the canonical file URI', () async {
    final file = File(p.join(root.path, 'sample.wav'))
      ..writeAsBytesSync(<int>[82, 73, 70, 70]);

    final attachment = await loadAcpPromptAttachment(
      file.path,
      AcpPromptAttachmentKind.audio,
    );

    expect(
      attachment.identity,
      'audio:${Uri.file(file.resolveSymbolicLinksSync())}',
    );
    expect(attachment.content, isA<AudioContent>());
  });

  test('file link sends metadata without inline payload', () async {
    final file = File(p.join(root.path, 'spec.yaml'))
      ..writeAsStringSync('kind: case');

    final attachment = await loadAcpPromptAttachment(
      file.path,
      AcpPromptAttachmentKind.fileLink,
    );

    final link = attachment.content as ResourceLink;
    expect(link.type, 'resource_link');
    expect(link.mimeType, 'application/yaml');
    expect(link.size, file.lengthSync());
    expect(attachment.inlineBytes, 0);
  });

  test('prompt budget rejects combined inline payload above the limit', () {
    const block = TextContentBlock(text: 'x');
    final attachments = [
      AcpPromptAttachment(
        kind: AcpPromptAttachmentKind.image,
        name: 'a',
        detail: 'a',
        identity: 'a',
        content: block,
        sourceBytes: acpMaximumPromptInlineBytes,
        inlineBytes: acpMaximumPromptInlineBytes,
      ),
      const AcpPromptAttachment(
        kind: AcpPromptAttachmentKind.audio,
        name: 'b',
        detail: 'b',
        identity: 'b',
        content: block,
        sourceBytes: 1,
        inlineBytes: 1,
      ),
    ];

    expect(
      () => validateAcpPromptAttachmentBudget(attachments),
      throwsA(isA<AcpPromptAttachmentException>()),
    );
  });

  test('manual resource link requires an absolute URI', () {
    expect(
      () => createAcpResourceLink(name: 'Docs', uri: Uri.parse('docs/readme')),
      throwsA(isA<AcpPromptAttachmentException>()),
    );
  });
}
