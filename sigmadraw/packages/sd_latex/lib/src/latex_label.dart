import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/widgets.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Fast, interactive on-screen math rendering (§11: "on-screen/tablet =
/// flutter_math_fork"). This is a KaTeX-subset renderer, not a full TeX
/// engine — a command it doesn't recognize is a parse error, not silently
/// dropped: [tex] then renders as its own raw source text instead (so a
/// label never just vanishes or shows a bare error icon), inside a
/// [Tooltip] naming what happened. The high-fidelity path for a document
/// that has an actual TeX toolchain is [compileLatexToSvg] (real vector
/// glyph outlines via `pdflatex`+`dvisvgm`), not this widget — see that
/// function's doc comment for when to use which.
class LatexLabel extends StatelessWidget {
  const LatexLabel(this.tex, {super.key, this.style});

  /// Bare TeX math-mode source — no surrounding `$...$`/`\[...\]`, matching
  /// what [Expr.toTex] (`sd_graph`) produces and what `Math.tex` itself
  /// expects.
  final String tex;

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tex,
      child: ExcludeSemantics(
        child: Math.tex(
          tex,
          mathStyle: MathStyle.text,
          textStyle: style,
          onErrorFallback: (error) => Tooltip(
            message: 'Could not render as math: ${error.message}',
            child: Text(tex, style: style),
          ),
        ),
      ),
    );
  }
}
