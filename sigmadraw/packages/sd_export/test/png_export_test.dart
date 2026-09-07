import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_export/sd_export.dart';
import 'package:sd_stencils/sd_stencils.dart';

SdDocument _simpleDocument({num width = 200, num height = 150}) {
  final doc = createBlankSdDocument(width: width, height: height);
  doc.root.appendChild(
    gain.instantiate(instanceId: 'g1', x: 20, y: 20, params: {'gain': 2.0}),
  );
  return doc;
}

/// Decodes [bytes] back to pixel dimensions — a real round-trip check,
/// not just "some file came out". The whole decode sequence
/// (`instantiateImageCodec` *and* `getNextFrame`, not just the first
/// call) has to run inside one `tester.runAsync` — see this file's own
/// top-level doc comment on why.
Future<(int, int)> _decodedSize(WidgetTester tester, Uint8List bytes) async {
  final size = await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return (frame.image.width, frame.image.height);
  });
  return size!;
}

/// `Picture.toImage`/`Image.toByteData` (inside `exportToPng` itself) and
/// `instantiateImageCodec`/`getNextFrame` (this file's own verification)
/// are real `dart:ui` engine-rendering/decoding calls — confirmed (see
/// the standalone isolate-run-testwidgets-hang memory) to hang forever
/// if awaited directly inside a `testWidgets` test. `tester.runAsync` is
/// Flutter's own documented fix for exactly this shape of call, so every
/// such call in this file goes through it — including, importantly, the
/// *entire* multi-await sequence in one `runAsync` call each time, not
/// just its first `await` (a single dangling un-wrapped await elsewhere
/// in the same sequence hangs just as much as wrapping nothing at all).
void main() {
  group('exportToPng', () {
    testWidgets('produces a real, correctly-sized PNG file', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync(
        'sigmadraw-png-export-test-',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final outputPath = '${tempDir.path}/diagram.png';
      final document = _simpleDocument(width: 200, height: 150);

      await tester.runAsync(() => exportToPng(document, outputPath));

      final file = File(outputPath);
      expect(file.existsSync(), isTrue);
      final bytes = file.readAsBytesSync();
      expect(bytes.length, greaterThan(0));
      // A real PNG, not just a file that happens to exist.
      expect(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);

      final (width, height) = await _decodedSize(tester, bytes);
      expect(width, 200);
      expect(height, 150);
    });

    testWidgets('scale multiplies the pixel dimensions', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync(
        'sigmadraw-png-export-test-',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final outputPath = '${tempDir.path}/diagram.png';
      final document = _simpleDocument(width: 100, height: 80);

      await tester.runAsync(
        () => exportToPng(
          document,
          outputPath,
          options: const PngExportOptions(scale: 2),
        ),
      );

      final bytes = File(outputPath).readAsBytesSync();
      final (width, height) = await _decodedSize(tester, bytes);
      expect(width, 200);
      expect(height, 160);
    });

    testWidgets('overwrites an existing file at outputPath', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync(
        'sigmadraw-png-export-test-',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final outputPath = '${tempDir.path}/diagram.png';
      File(outputPath).writeAsStringSync('not actually a png yet');

      await tester.runAsync(() => exportToPng(_simpleDocument(), outputPath));

      final bytes = File(outputPath).readAsBytesSync();
      expect(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    });

    testWidgets('throws ArgumentError for a document with no width/height', (
      tester,
    ) async {
      final document = SdDocument(
        root: SdElement(
          const SdQName('svg', SdNamespace.svg),
          namespaceDeclarations: {
            null: SdNamespace.svg,
            SdPrefix.sd: SdNamespace.sd,
          },
        ),
      );

      // exportToPng is `async`, so a synchronous throw inside it is
      // still only ever observable via the *returned Future*'s error
      // (async-function semantics never throw synchronously to the
      // caller) — expectLater on the Future itself, not
      // expect(closure, throwsArgumentError), is the correct matcher
      // shape here.
      await expectLater(
        exportToPng(document, '/irrelevant.png'),
        throwsArgumentError,
      );
    });
  });
}
