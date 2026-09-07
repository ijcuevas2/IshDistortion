import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_export/sd_export.dart';
import 'package:sd_stencils/sd_stencils.dart';

SdDocument _simpleChain() {
  final doc = createBlankSdDocument();
  doc.root.appendChild(source.instantiate(instanceId: 'src', x: 0, y: 0));
  doc.root.appendChild(
    gain.instantiate(instanceId: 'g1', x: 150, y: 0, params: {'gain': 2.5}),
  );
  doc.root.appendChild(sink.instantiate(instanceId: 'snk', x: 300, y: 0));
  doc.root.appendChild(
    buildEdge(
      id: 'e1',
      fromBlock: 'src',
      fromPort: 'out1',
      toBlock: 'g1',
      toPort: 'in1',
    ),
  );
  doc.root.appendChild(
    buildEdge(
      id: 'e2',
      fromBlock: 'g1',
      fromPort: 'out1',
      toBlock: 'snk',
      toPort: 'in1',
    ),
  );
  return doc;
}

Future<bool> _pdflatexAvailable() async {
  try {
    final result = await Process.run('pdflatex', ['--version']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  group('exportToPdf', () {
    test('produces a real, non-empty PDF file at outputPath', () async {
      if (!await _pdflatexAvailable()) {
        return; // No LaTeX toolchain in this environment — nothing to verify.
      }
      final tempDir = await Directory.systemTemp.createTemp(
        'sigmadraw-pdf-export-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final outputPath = '${tempDir.path}/diagram.pdf';

      await exportToPdf(_simpleChain(), outputPath);

      final file = File(outputPath);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(0));
      // A real PDF, not just a file that happens to exist.
      final header = file.openSync().readSync(5);
      expect(String.fromCharCodes(header), '%PDF-');
    });

    test(
      'leaves no pdflatex intermediate files (.aux/.log) next to outputPath',
      () async {
        if (!await _pdflatexAvailable()) {
          return;
        }
        final tempDir = await Directory.systemTemp.createTemp(
          'sigmadraw-pdf-export-test-',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final outputPath = '${tempDir.path}/diagram.pdf';

        await exportToPdf(_simpleChain(), outputPath);

        final siblingNames = tempDir
            .listSync()
            .map((e) => e.path.split(Platform.pathSeparator).last)
            .toList();
        expect(siblingNames, ['diagram.pdf']);
      },
    );

    test('overwrites an existing file at outputPath', () async {
      if (!await _pdflatexAvailable()) {
        return;
      }
      final tempDir = await Directory.systemTemp.createTemp(
        'sigmadraw-pdf-export-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final outputPath = '${tempDir.path}/diagram.pdf';
      File(outputPath).writeAsStringSync('not actually a pdf yet');

      await exportToPdf(_simpleChain(), outputPath);

      final header = File(outputPath).openSync().readSync(5);
      expect(String.fromCharCodes(header), '%PDF-');
    });
  });
}
