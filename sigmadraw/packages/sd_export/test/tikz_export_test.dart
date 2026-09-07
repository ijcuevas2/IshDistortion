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
  doc.root.appendChild(delay.instantiate(instanceId: 'd1', x: 300, y: 0));
  doc.root.appendChild(sink.instantiate(instanceId: 'snk', x: 450, y: 0));
  doc.root.appendChild(
    buildEdge(
      id: 'e1',
      fromBlock: 'src',
      fromPort: 'out1',
      toBlock: 'g1',
      toPort: 'in1',
      signalLabel: 'x[n]',
    ),
  );
  doc.root.appendChild(
    buildEdge(
      id: 'e2',
      fromBlock: 'g1',
      fromPort: 'out1',
      toBlock: 'd1',
      toPort: 'in1',
    ),
  );
  doc.root.appendChild(
    buildEdge(
      id: 'e3',
      fromBlock: 'd1',
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
  group('exportToTikz (string content)', () {
    test('emits one node per block and one arrow per edge', () {
      final tex = exportToTikz(_simpleChain());
      expect(
        'node[tri]'.allMatches(tex.replaceAll(' ', '')),
        hasLength(1),
      ); // the gain
      expect(
        RegExp(r'\\node\[').allMatches(tex),
        hasLength(4),
      ); // src, g1, d1, snk
      expect(RegExp(r'\\draw\[->\]').allMatches(tex), hasLength(3));
    });

    test('a gain block\'s label is its coefficient', () {
      final tex = exportToTikz(_simpleChain());
      expect(tex, contains('{2.5}'));
    });

    test('a delay block\'s label is z^{-1} in math mode', () {
      final tex = exportToTikz(_simpleChain());
      expect(tex, contains(r'{$z^{-1}$}'));
    });

    test('an edge signal label is rendered at its midpoint', () {
      final tex = exportToTikz(_simpleChain());
      expect(tex, contains(r'node[midway, above] {$x[n]$}'));
    });

    test('non-standalone mode omits the documentclass/document wrapper', () {
      final tex = exportToTikz(
        _simpleChain(),
        options: const TikzExportOptions(standalone: false),
      );
      expect(tex, isNot(contains(r'\documentclass')));
      expect(tex, contains(r'\begin{tikzpicture}'));
    });

    test('an explicit block label is LaTeX-escaped', () {
      final doc = createBlankSdDocument();
      doc.root.appendChild(
        gain.instantiate(instanceId: 'g1', label: '50% & more_stuff'),
      );
      final tex = exportToTikz(doc);
      expect(tex, contains(r'50\% \& more\_stuff'));
    });
  });

  group('exportToTikz output actually compiles', () {
    test('pdflatex accepts the generated standalone document and produces a PDF', () async {
      if (!await _pdflatexAvailable()) {
        return; // No LaTeX toolchain in this environment — nothing to verify.
      }
      final tex = exportToTikz(_simpleChain());
      final tempDir = await Directory.systemTemp.createTemp(
        'sigmadraw-tikz-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final texFile = File('${tempDir.path}/diagram.tex')
        ..writeAsStringSync(tex);
      final result = await Process.run('pdflatex', [
        '-interaction=nonstopmode',
        '-halt-on-error',
        texFile.path,
      ], workingDirectory: tempDir.path);

      expect(
        result.exitCode,
        0,
        reason:
            'pdflatex failed:\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
      final pdf = File('${tempDir.path}/diagram.pdf');
      expect(pdf.existsSync(), isTrue);
      expect(pdf.lengthSync(), greaterThan(0));
    });

    test(
      'a richer diagram (a generated biquad filter) also compiles',
      () async {
        if (!await _pdflatexAvailable()) {
          return;
        }
        final doc = createBlankSdDocument();
        final structure = buildBiquadDf2t(
          idPrefix: 'bq',
          b0: 1,
          b1: 0.5,
          b2: 0.25,
          a1: -0.3,
          a2: 0.1,
        );
        for (final element in structure.elements) {
          doc.root.appendChild(element);
        }
        final tex = exportToTikz(doc);
        final tempDir = await Directory.systemTemp.createTemp(
          'sigmadraw-tikz-test-',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final texFile = File('${tempDir.path}/diagram.tex')
          ..writeAsStringSync(tex);

        final result = await Process.run('pdflatex', [
          '-interaction=nonstopmode',
          '-halt-on-error',
          texFile.path,
        ], workingDirectory: tempDir.path);

        expect(
          result.exitCode,
          0,
          reason: 'pdflatex failed:\n${result.stdout}\n${result.stderr}',
        );
        expect(File('${tempDir.path}/diagram.pdf').existsSync(), isTrue);
      },
    );
  });
}
