import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:sd_document/sd_document.dart';

/// Raised when the external `pdflatex`/`dvisvgm` toolchain fails. [log]
/// carries the tool's raw stdout+stderr for diagnosis (e.g. surfacing in an
/// equation-editor dialog), separate from the short [message].
class LatexCompileException implements Exception {
  const LatexCompileException(this.message, {this.log});

  final String message;
  final String? log;

  @override
  String toString() =>
      log == null ? 'LatexCompileException: $message' : '$message\n$log';
}

/// The result of compiling a LaTeX source string to real vector content via
/// [compileLatexToSvg] — ready to splice into a document with [embedLatex].
///
/// [defs] and [content] are plain, disconnected `sd_document` nodes (not
/// yet attached to any document): [content] is a `<g>` wrapping ordinary
/// `<path>`/`<use>` geometry (glyph outlines dvisvgm emitted, referencing
/// [defs] by id) and already carries [sourceTex] as its `sd:latex`
/// (`SdLatexSemantics.latexSource`); [defs] are the glyph-outline `<path>`
/// definitions that geometry's `<use>` elements reference, meant to be
/// merged into the host document's own `<defs>`. Every id dvisvgm minted has
/// already been prefixed to be unique to this one compiled equation, so
/// [defs] from two different [LatexEmbed]s can coexist in the same `<defs>`
/// without colliding.
class LatexEmbed {
  const LatexEmbed({
    required this.sourceTex,
    required this.defs,
    required this.content,
    required this.widthPt,
    required this.heightPt,
  });

  final String sourceTex;
  final List<SdNode> defs;
  final SdElement content;

  /// The compiled equation's natural size, in the `pt` (1/72in) units
  /// `dvisvgm` reports them in — before [embedLatex]'s `scale`.
  final double widthPt;
  final double heightPt;
}

/// Compiles [texSource] (bare math-mode content — no `$...$`/`\[...\]`,
/// same convention as `Expr.toTex()` and [LatexLabel]) to real vector
/// glyph-outline SVG via the desktop pipeline (§11): `pdflatex` (a
/// `standalone`+`preview`-class document, cropped tight to the equation)
/// piped through `dvisvgm --pdf --no-fonts` (outline every glyph as a
/// `<path>`, so the result depends on no font being installed to redisplay
/// correctly — genuine vector content, not a rasterized image or a
/// font-dependent `<text>`). Throws [LatexCompileException] if either tool
/// is missing or the source doesn't compile (e.g. a genuine LaTeX syntax
/// error) — there is no silent fallback here, unlike [LatexLabel]'s
/// on-screen KaTeX-subset rendering, since a document author invoking this
/// path has explicitly asked for the real-TeX-toolchain result.
///
/// The external processes and the (potentially non-trivial, for a long
/// expression) XML rewriting below run in a background [Isolate.run], per
/// §2/§14's "do not block the UI isolate on ... LaTeX compile" — only the
/// raw SVG text crosses back to the calling isolate, deliberately avoiding
/// sending a `SdElement`/`SdNode` object graph across that boundary.
///
/// Compiling the same [texSource] repeatedly (e.g. on every keystroke of an
/// equation editor, or once per instance of a duplicated label) re-runs the
/// whole external pipeline — callers that want to avoid that should go
/// through [LatexRenderCache] instead of calling this directly.
Future<LatexEmbed> compileLatexToSvg(String texSource) async {
  final rawSvg = await Isolate.run(() => _runPdflatexAndDvisvgm(texSource));
  return _parseAndPrefixIds(texSource, rawSvg);
}

/// Splices [embed] into [document] as a new top-level `<g>` positioned at
/// ([x], [y]) — document user-space units — and returns that element (e.g.
/// to select it immediately, or to remove it again). [scale] converts the
/// equation's native `pt` size to document user units *on top of* that
/// placement; 1 document unit == 1pt at `scale == 1`. There is no single
/// "correct" ratio (`sd_document` doesn't tie its user units to a physical
/// size), so the default (3) is simply chosen to sit a normal H(z)-sized
/// annotation at roughly the same visual scale as this project's stencils
/// (`StencilMetrics.squareBlock == 80`) — pass an explicit [scale] to match
/// a document's own convention instead.
///
/// Ensures [document] has a top-level `<defs>` (creating one if absent,
/// same pattern as `sd_stencils`' `ensureArrowMarker`) and merges [embed]'s
/// glyph-outline defs into it.
SdElement embedLatex(
  SdDocument document,
  LatexEmbed embed, {
  required double x,
  required double y,
  double scale = 3,
}) {
  final content = positionLatexEmbed(document, embed, x: x, y: y, scale: scale);
  document.root.appendChild(content);
  return content;
}

/// The positioning half of [embedLatex], stopping short of attaching the
/// result to [document] — for a caller that needs that final attach to be
/// its own undo boundary (e.g. an equation-insert dialog routing it
/// through `InsertChildCommand`) while still merging [embed]'s glyph-
/// outline `<defs>` unconditionally. That defs merge is deliberately
/// *not* part of the undo boundary: an undone insert can leave a glyph
/// `<path>` sitting unreferenced in `<defs>`, which is inert (never
/// painted, never round-tripped-away) rather than incorrect — the same
/// bookkeeping-vs-visible-content split `sd_stencils`' `ensureArrowMarker`
/// already relies on elsewhere in this codebase.
///
/// Returns [embed]'s content element, positioned and ready to attach
/// (typically via `document.root.appendChild` or an `InsertChildCommand`
/// wrapping it) — not yet attached to [document] itself.
SdElement positionLatexEmbed(
  SdDocument document,
  LatexEmbed embed, {
  required double x,
  required double y,
  double scale = 3,
}) {
  SdElement? defs;
  for (final e in document.root.childElements) {
    if (e.name.local == 'defs') {
      defs = e;
      break;
    }
  }
  if (defs == null) {
    defs = SdElement(const SdQName('defs'));
    document.root.insertChildAt(0, defs);
  }
  for (final glyphDef in embed.defs) {
    defs.appendChild(glyphDef);
  }

  embed.content.setAttribute(
    const SdQName('transform'),
    'translate(${_fmt(x)}, ${_fmt(y)}) scale(${_fmt(scale)})',
  );
  return embed.content;
}

/// Caches [compileLatexToSvg] results by source text (§11: "cache by hash
/// of source" — keying a `Map` by the source string directly is at least
/// as precise as keying it by a hash of that string, without needing one;
/// [compileLatexToSvg]'s *own* id-minting still uses a real hash — see
/// [fnv1a64Hex] — since ids from two different equations must not collide
/// inside one document's shared `<defs>`, which a full-source key alone
/// wouldn't guarantee once two [LatexEmbed]s are merged together). A cache
/// hit returns instantly with no external process spawned at all — the
/// common case once a document's equations have each compiled once.
///
/// The in-flight `Future` itself is cached (not just a completed result),
/// so calling [render] twice with the same source before the first call
/// finishes still only compiles once.
class LatexRenderCache {
  LatexRenderCache({Future<LatexEmbed> Function(String texSource)? compiler})
    : _compiler = compiler ?? compileLatexToSvg;

  final Future<LatexEmbed> Function(String texSource) _compiler;
  final _cache = <String, Future<LatexEmbed>>{};

  Future<LatexEmbed> render(String texSource) =>
      _cache.putIfAbsent(texSource, () => _compiler(texSource));

  /// Number of distinct sources currently cached — for tests/diagnostics.
  int get length => _cache.length;

  void clear() => _cache.clear();
}

// --- desktop toolchain invocation (runs inside Isolate.run) --------------

Future<String> _runPdflatexAndDvisvgm(String texSource) async {
  final tempDir = await Directory.systemTemp.createTemp('sigmadraw-latex-');
  try {
    File('${tempDir.path}/eq.tex').writeAsStringSync(
      '\\documentclass[preview,border=0.2pt]{standalone}\n'
      '\\usepackage{amsmath}\n'
      '\\begin{document}\n'
      '\$$texSource\$\n'
      '\\end{document}\n',
    );

    final pdflatex = await Process.run('pdflatex', [
      '-interaction=nonstopmode',
      '-halt-on-error',
      'eq.tex',
    ], workingDirectory: tempDir.path);
    if (pdflatex.exitCode != 0) {
      throw LatexCompileException(
        'pdflatex could not compile this equation.',
        log: '${pdflatex.stdout}\n${pdflatex.stderr}',
      );
    }

    final dvisvgm = await Process.run('dvisvgm', [
      '--pdf',
      '--no-fonts',
      '-o',
      'eq.svg',
      'eq.pdf',
    ], workingDirectory: tempDir.path);
    if (dvisvgm.exitCode != 0) {
      throw LatexCompileException(
        'dvisvgm could not convert the compiled equation to SVG.',
        log: '${dvisvgm.stdout}\n${dvisvgm.stderr}',
      );
    }

    return File('${tempDir.path}/eq.svg').readAsStringSync();
  } on ProcessException catch (e) {
    throw LatexCompileException(
      'pdflatex/dvisvgm is not available on PATH.',
      log: e.toString(),
    );
  } finally {
    await tempDir.delete(recursive: true);
  }
}

// --- SVG post-processing (runs on the calling isolate) --------------------

const _xlinkHref = SdQName('href', SdNamespace.xlink);
const _plainHref = SdQName('href');
const _idAttr = SdQName('id');

/// Parses dvisvgm's raw output, splits it into `<defs>` vs. everything else
/// (dvisvgm always emits at most one top-level `<defs>`, holding only the
/// glyph outline `<path>`s its `<use>` elements reference), prefixes every
/// id/href pair with a hash of [texSource] so two different compiled
/// equations can share one document's `<defs>` without their (dvisvgm-
/// chosen, short, e.g. `g4-1`) ids colliding, and records [texSource] on
/// the wrapping `<g>` per `SdLatexSemantics`.
LatexEmbed _parseAndPrefixIds(String texSource, String rawSvg) {
  final svg = parseSdDocument(rawSvg).root;
  final prefix = 'sdlatex-${fnv1a64Hex(texSource)}';

  SdElement? defsElement;
  final contentChildren = <SdNode>[];
  for (final child in svg.children.toList()) {
    if (child is SdElement && child.name.local == 'defs') {
      defsElement = child;
    } else {
      contentChildren.add(child);
    }
  }

  void rewriteIds(SdElement element) {
    final id = element.getAttribute(_idAttr);
    if (id != null) element.setAttribute(_idAttr, '$prefix-$id');
    for (final hrefAttr in [_xlinkHref, _plainHref]) {
      final href = element.getAttribute(hrefAttr);
      if (href != null && href.startsWith('#')) {
        element.setAttribute(hrefAttr, '#$prefix-${href.substring(1)}');
      }
    }
    for (final child in element.childElements) {
      rewriteIds(child);
    }
  }

  final defsChildren = <SdNode>[
    if (defsElement != null) ...defsElement.children,
  ];
  for (final node in [...defsChildren, ...contentChildren]) {
    if (node is SdElement) rewriteIds(node);
  }

  final content = SdElement(const SdQName('g'), children: contentChildren)
    ..latexSource = texSource;

  return LatexEmbed(
    sourceTex: texSource,
    defs: defsChildren,
    content: content,
    widthPt: _parseLeadingNumber(svg.getAttribute(const SdQName('width'))),
    heightPt: _parseLeadingNumber(svg.getAttribute(const SdQName('height'))),
  );
}

final _leadingNumber = RegExp(r'^([\d.eE+-]+)');

double _parseLeadingNumber(String? raw) {
  if (raw == null) return 0;
  final match = _leadingNumber.firstMatch(raw.trim());
  return match == null ? 0 : double.tryParse(match.group(1)!) ?? 0;
}

String _fmt(double v) => v.toStringAsFixed(3);

// --- content hash (id-prefix minting only — not cryptographic) -----------

/// FNV-1a, 64-bit: a small, dependency-free, deterministic hash — plenty
/// for minting a short id-prefix unique enough across the handful of
/// distinct equations one document realistically embeds (a genuine
/// collision would only matter if two *different* sources hashed equal,
/// which nothing here defends against beyond this hash's own spread; not
/// used for anything security-sensitive). Native-target-only: `int` is a
/// true 64-bit word on the Dart VM/AOT, which is all this project targets
/// (see README — no web build has been attempted).
String fnv1a64Hex(String source) {
  const fnvPrime = 0x100000001b3;
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(source)) {
    hash ^= byte;
    hash *= fnvPrime; // wraps to 64 bits on a native (VM/AOT) target.
  }
  // `int.toUnsigned(64)` can't actually produce a non-negative result —
  // there's no 64-bit-wide *positive* two's-complement representation once
  // the top bit is set, so `toUnsigned` only genuinely works below 64 bits.
  // Dropping to 63 bits here (still a huge, plenty-collision-resistant
  // space for this many-orders-of-magnitude-smaller use case) is what
  // actually guarantees a non-negative value to hex-format, rather than a
  // `toRadixString` that would print a leading `-` on roughly half of all
  // inputs.
  return hash.toUnsigned(63).toRadixString(16).padLeft(16, '0');
}
