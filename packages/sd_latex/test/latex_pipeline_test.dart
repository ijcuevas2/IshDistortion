import 'dart:io';

import 'package:flutter/widgets.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_latex/sd_latex.dart';
import 'package:sd_render/sd_render.dart';

Future<bool> _toolchainAvailable() async {
  try {
    final pdflatex = await Process.run('pdflatex', ['--version']);
    final dvisvgm = await Process.run('dvisvgm', ['--version']);
    return pdflatex.exitCode == 0 && dvisvgm.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// The union of every indexed entry's world bounds anywhere in [subtreeRoot]
/// (inclusive). `SpatialIndex.worldBoundsFor` alone only matches entries
/// whose *own* `element` is exactly the element passed in — for content
/// reached via `<use>`, that's the `<use>` leaf itself (see
/// `SpatialEntry.selectableElement`'s doc comment), never some ancestor
/// `<g>` several levels up, which is exactly the shape `embedLatex`
/// produces (a wrapping `<g>` around dvisvgm's own nested `<g>`/`<use>`
/// structure) — so a real "does this wrapper have any visible content at
/// all" check has to look at the whole subtree, not one exact element.
Rect? _subtreeWorldBounds(SpatialIndex index, SdElement subtreeRoot) {
  final subtree = {subtreeRoot, ...subtreeRoot.descendantElements};
  Rect? bounds;
  for (final entry in index.entries) {
    if (!subtree.contains(entry.element)) continue;
    bounds = bounds == null
        ? entry.worldBounds
        : bounds.expandToInclude(entry.worldBounds);
  }
  return bounds;
}

void main() {
  group('fnv1a64Hex', () {
    test('is deterministic for the same input', () {
      expect(fnv1a64Hex('H(z) = 1'), fnv1a64Hex('H(z) = 1'));
    });

    test('differs for different input', () {
      expect(fnv1a64Hex(r'a_1'), isNot(fnv1a64Hex(r'a_2')));
    });

    test('is a fixed-width lowercase hex string', () {
      expect(fnv1a64Hex('x'), matches(RegExp(r'^[0-9a-f]{16}$')));
    });
  });

  group('LatexRenderCache', () {
    LatexEmbed fakeEmbed(String tex) => LatexEmbed(
      sourceTex: tex,
      defs: const [],
      content: SdElement(const SdQName('g'))..latexSource = tex,
      widthPt: 10,
      heightPt: 10,
    );

    test('only invokes the compiler once per distinct source', () async {
      var calls = 0;
      final cache = LatexRenderCache(
        compiler: (tex) async {
          calls++;
          return fakeEmbed(tex);
        },
      );

      await cache.render('x^2');
      await cache.render('x^2');
      await cache.render('x^2');
      expect(calls, 1);
      expect(cache.length, 1);

      await cache.render('y^2');
      expect(calls, 2);
      expect(cache.length, 2);
    });

    test(
      'a second call before the first resolves still only compiles once',
      () async {
        var calls = 0;
        final cache = LatexRenderCache(
          compiler: (tex) async {
            calls++;
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return fakeEmbed(tex);
          },
        );

        final results = await Future.wait([
          cache.render('x^2'),
          cache.render('x^2'),
        ]);
        expect(calls, 1);
        expect(results[0].sourceTex, 'x^2');
      },
    );

    test('clear() forces recompilation', () async {
      var calls = 0;
      final cache = LatexRenderCache(
        compiler: (tex) async {
          calls++;
          return fakeEmbed(tex);
        },
      );
      await cache.render('x^2');
      cache.clear();
      await cache.render('x^2');
      expect(calls, 2);
    });
  });

  group('compileLatexToSvg / embedLatex (real pdflatex + dvisvgm)', () {
    test(
      'produces real, non-empty vector content that actually renders',
      () async {
        if (!await _toolchainAvailable()) return;

        final embed = await compileLatexToSvg(
          r'H(z) = \frac{1}{1 + a_1 z^{-1}}',
        );
        expect(embed.defs, isNotEmpty);
        expect(embed.content.name.local, 'g');
        expect(embed.content.latexSource, r'H(z) = \frac{1}{1 + a_1 z^{-1}}');
        expect(embed.widthPt, greaterThan(0));
        expect(embed.heightPt, greaterThan(0));

        final doc = createBlankSdDocument();
        embedLatex(doc, embed, x: 100, y: 100);

        // Round-trip through native SVG save/reload — the embedded fragment
        // must survive exactly like any other document content (§3).
        final saved = writeSdDocument(doc, mode: SdSaveMode.native);
        expect(saved, contains('sd:latex'));
        final reloaded = parseSdDocument(saved);

        // And it must be real, paintable geometry through this project's own
        // renderer — not just plausible-looking XML — with non-trivial
        // bounds (i.e. the <use> elements actually resolved their glyph
        // <path> targets, rather than silently drawing nothing).
        final index = SpatialIndex.build(buildScene(reloaded));
        final embedded = reloaded.root.descendantElements.firstWhere(
          (e) => e.latexSource != null,
        );
        final bounds = _subtreeWorldBounds(index, embedded);
        expect(bounds, isNotNull);
        expect(bounds!.width, greaterThan(0));
        expect(bounds.height, greaterThan(0));
      },
    );

    test(
      'two different equations embedded in one document never collide ids',
      () async {
        if (!await _toolchainAvailable()) return;

        final a = await compileLatexToSvg(r'a_1 + a_2');
        final b = await compileLatexToSvg(r'b_0 - b_1 z^{-1}');
        final doc = createBlankSdDocument();
        embedLatex(doc, a, x: 0, y: 0);
        embedLatex(doc, b, x: 200, y: 0);

        final saved = writeSdDocument(doc, mode: SdSaveMode.native);
        final reloaded = parseSdDocument(saved);
        final ids = [
          for (final e in reloaded.root.descendantElements)
            ?e.getAttribute(const SdQName('id')),
        ];
        expect(
          ids.toSet(),
          hasLength(ids.length),
          reason: 'duplicate id: $ids',
        );

        // Both equations' own content must still resolve to real geometry —
        // i.e. neither equation's <use> ended up pointing at the other's
        // (differently-shaped) glyphs after the merge.
        final index = SpatialIndex.build(buildScene(reloaded));
        final embeddedGroups = reloaded.root.descendantElements
            .where((e) => e.latexSource != null)
            .toList();
        expect(embeddedGroups, hasLength(2));
        for (final g in embeddedGroups) {
          final bounds = _subtreeWorldBounds(index, g);
          expect(bounds, isNotNull);
          expect(bounds!.width, greaterThan(0));
          expect(bounds.height, greaterThan(0));
        }
      },
    );

    test('throws LatexCompileException for unbalanced/invalid TeX', () async {
      if (!await _toolchainAvailable()) return;
      await expectLater(
        compileLatexToSvg(r'\frac{1}{'),
        throwsA(isA<LatexCompileException>()),
      );
    });
  });
}
