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

/// Whether [executable] can be spawned at all — a `ProcessException`
/// (the executable itself missing from `PATH`) is the only thing that
/// should skip these tests; whatever exit code it reports for a bare
/// `-v` is irrelevant (some tools, `pdftops` among them on some
/// poppler builds, exit nonzero for a version query).
Future<bool> _toolchainAvailable(String executable) async {
  try {
    await Process.run(executable, ['-v']);
    return true;
  } on ProcessException {
    return false;
  }
}

void main() {
  group('exportToEps', () {
    test('produces a real, non-empty, correctly-bounded EPS file', () async {
      if (!await _toolchainAvailable('pdflatex') ||
          !await _toolchainAvailable('pdftops')) {
        return; // No LaTeX/poppler toolchain in this environment.
      }
      final tempDir = await Directory.systemTemp.createTemp(
        'sigmadraw-eps-export-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final outputPath = '${tempDir.path}/diagram.eps';

      await exportToEps(_simpleChain(), outputPath);

      final file = File(outputPath);
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content, startsWith('%!PS-Adobe'));
      expect(content, contains('EPSF'));
      // A real, non-degenerate bounding box — not "0 0 0 0" or missing
      // entirely, which is exactly the failure mode the classic
      // `dvips -E` pipeline hit for this project's diagrams (see
      // exportToEps's own doc comment) before switching to pdftops.
      final bboxLine = content
          .split('\n')
          .firstWhere((l) => l.startsWith('%%BoundingBox:'));
      final numbers = bboxLine
          .substring('%%BoundingBox:'.length)
          .trim()
          .split(RegExp(r'\s+'))
          .map(double.parse)
          .toList();
      expect(numbers, hasLength(4));
      final width = numbers[2] - numbers[0];
      final height = numbers[3] - numbers[1];
      expect(width, greaterThan(10));
      expect(height, greaterThan(10));
    });

    test(
      'leaves no pdflatex/pdftops intermediate files next to outputPath',
      () async {
        if (!await _toolchainAvailable('pdflatex') ||
            !await _toolchainAvailable('pdftops')) {
          return;
        }
        final tempDir = await Directory.systemTemp.createTemp(
          'sigmadraw-eps-export-test-',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final outputPath = '${tempDir.path}/diagram.eps';

        await exportToEps(_simpleChain(), outputPath);

        final siblingNames = tempDir
            .listSync()
            .map((e) => e.path.split(Platform.pathSeparator).last)
            .toList();
        expect(siblingNames, ['diagram.eps']);
      },
    );

    test('overwrites an existing file at outputPath', () async {
      if (!await _toolchainAvailable('pdflatex') ||
          !await _toolchainAvailable('pdftops')) {
        return;
      }
      final tempDir = await Directory.systemTemp.createTemp(
        'sigmadraw-eps-export-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final outputPath = '${tempDir.path}/diagram.eps';
      File(outputPath).writeAsStringSync('not actually an eps yet');

      await exportToEps(_simpleChain(), outputPath);

      expect(File(outputPath).readAsStringSync(), startsWith('%!PS-Adobe'));
    });
  });
}
