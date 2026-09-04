# SigmaDraw

A semantically-aware Digital Signal Processing diagramming editor in
Flutter. The full mission/spec lives in
[`sigmadraw-implementation-prompt.md`](./sigmadraw-implementation-prompt.md)
— this README tracks what's actually built, how to build it, and decisions
made along the way. Section references (`§3`, `§12`, ...) below refer to
that document.

## Status

Built and verified so far (each gate below is green — see "Build & test"):

- **Phase 0 — Scaffolding.** Melos/Dart-workspace monorepo, app shell,
  CI (`.github/workflows/ci.yml`), shared lint config, empty package
  scaffolds, architecture-mining notes from the reference codebases
  ([`docs/inkscape-notes.md`](./docs/inkscape-notes.md),
  [`docs/xournalpp-notes.md`](./docs/xournalpp-notes.md)).
- **Phase 1 — Document + SVG round-trip.** `packages/sd_document`: an
  observable, namespace-aware XML tree; lossless parse/serialize via
  `package:xml`; the private `sd:` namespace semantic layer (§3); native
  vs. plain-SVG save modes; golden round-trip tests.
- **Phase 2 — Rendering + canvas.** `packages/sd_render`: an SVG-subset
  interpreter (path-data mini-language incl. arcs, shapes, `transform`,
  inheritance-aware fill/stroke/color), a retained scene tree rebuilt from
  the document, a quadtree spatial index, pan/zoom/grid, precise
  fill/stroke hit-testing, and click/marquee selection with move +
  uniform-corner-scale drag handles — all wired into `apps/sigmadraw` over
  a small hand-built demo document. 77 tests, several of which caught real
  bugs during development (see git history / code comments, e.g. the
  `hitTestHandle` closest-not-first fix). Also gained basic `marker-end`
  arrowhead rendering, added while building Phase 3's stencils.
- **Phase 3 — Stencils (core) + placement.** `packages/sd_stencils`: a
  data-driven `StencilDefinition` model (geometry generator + ports +
  param schema + `directFeedthrough`) and 12 core §5.1-5.3 primitives
  (adder, gain, pickoff node, source/sink, delay, continuous delay,
  up/downsampler, sampler, ZOH/FOH) — composite/macro stencils
  (tapped-delay-line, rate converters, ...) are deliberately deferred to
  Phase 7. `packages/sd_ui` gained a searchable/draggable stencil
  palette, a drop-to-place canvas wrapper, an element tree, and a
  property inspector. 25 + 7 tests.
- **Phase 2/9 addendum — connectors.** `sd_render`'s canvas gained
  drag-from-port-to-port connector creation (a straight-line `sd:edge`,
  correctly directed regardless of which end you drag from/to) and
  live port dots, plus `marker-end` arrowhead rendering — without these
  there was no way to actually wire up a diagram to analyze. Orthogonal
  routing (libavoid-style) is still Phase 9's job.
- **Phase 4 + 8 (reprioritized ahead of 5-7) — the semantic graph and its
  analysis.** `packages/sd_graph`: typed `Port`/`Block`/`Edge` extracted
  from a document's `sd:*` attributes; full §4 validation (dangling
  edges, type-widening rules, vlen/sample-rate mismatches, unsupported
  arity, unconnected ports); Tarjan-SCC-based algebraic-loop detection;
  sample-rate propagation (×L/÷M at up/downsamplers); Mason's gain
  formula over a small symbolic-expression engine, producing a real
  `H(z)`; GNU-Radio-style JSON/YAML netlist + Graphviz DOT export.
  **Verified against a full biquad Direct Form II Transposed built from
  the Phase 3 primitives** (adder/gain/delay, wired exactly as a real
  diagram would be): it validates with no algebraic loop, and Mason's
  formula yields `H(z) = (b0+b1·z⁻¹+b2·z⁻²)/(1+a1·z⁻¹+a2·z⁻²)` — checked
  both analytically (by hand) and numerically at several points,
  including with unbound symbolic coefficients — this is §13's named
  acceptance criterion. `sd_ui` gained a live Problems panel and an H(z)
  readout, both wired into the app. 45 + 21 tests (7 new in `sd_ui`, 3 in
  `sd_render` for connector creation).
  Not implemented: hierarchical/subsystem blocks (flagged via
  `Block.isSubsystem`, not built), pole-zero generation, and treating a
  multirate block as anything but unity gain in H(z) — all documented in
  code comments at the point they matter.
- **Phase 7 (partial) — more of the stencil library.** `sd_stencils`
  gained §5.4 (quantizer/ADC/DAC/saturation/rounding/dither), §5.6
  (FFT/IFFT, bit-reversal, a 2-in/2-out radix-2 butterfly — the first
  multi-output stencil, with a documented Mason-analysis caveat where
  that matters), §5.9 (plant/controller/integrator/differentiator), and
  §5.10 (MAC/accumulator/register/mux/demux/ROM/systolic cell). More
  significantly, §5.5's filter *structures* are implemented as composite
  generators (`buildFirDirectForm`, `buildBiquadDf2t`,
  `buildBiquadCascade`) that place and wire a whole subgraph of Phase 3
  primitives — `buildBiquadDf2t` is the exact topology verified against
  Mason's formula above, now packaged as one call. All three generators'
  output is verified against `sd_graph`'s Mason engine: FIR against
  `Σcᵢ·z⁻ⁱ`, the biquad against the textbook DF2T `H(z)`, and the cascade
  against the product of its sections' individual `H(z)` — for several
  coefficient sets and evaluation points each. Not implemented: §5.7
  (comms/modulation), §5.8 (adaptive/statistical), §5.11 (analysis-plot
  objects), and the rest of §5.5 (lattice/parallel/wave-digital/comb/CIC,
  state-space). 33 new tests.

**Next, if this continues**: Ribbon UI (5), ink/pen input + 5 native
plugins (6), LaTeX (9), vector export (10), and polish (11) are all
**not started**, and §5.5/§5.7/§5.8/§5.11 remain thin (previous bullet).
Given the true scope of §0-§15 (a production, cross-platform, multi-
native-plugin app), these were not attempted in the interest of not
shipping shallow/fake versions of them — see "What's not built" below.

`packages/sd_ink`, `sd_input`, `sd_latex`, `sd_export`, and `sd_commands`
are still empty scaffolds (a `library;` stub, no `test/`), and
`plugins/sd_pen_*` are placeholder READMEs — see each one for what it'll
need to become in Phase 6.

## What's not built (be honest about scope)

This spec describes a production, multi-platform application with 5
native pen-input plugins, ~80 DSP stencils, a full ribbon+docking UI, a
LaTeX pipeline, and vector export — realistically months of work for a
team, not one sitting. What exists now is a solid, fully-tested
**foundation and vertical slice**: place a block, wire it to another,
see it validated, see its transfer function — all for real, nothing
faked. Concretely still missing:

- **Ribbon UI (§10, Phase 5).** The app is a plain `Row` of panels, not
  the tabbed/contextual ribbon with galleries and dialog launchers.
- **Ink/pen (§6-§7, Phase 6) and all 5 native plugins.** No stroke
  model, no pointer-classification/palm-rejection pipeline, and none of
  `plugins/sd_pen_{windows,macos,linux,android,ios}` has been written —
  this sandbox can only build/run the Linux desktop target anyway, so
  the other 4 plugins couldn't have been compiled or tested here even
  if written.
- **The rest of §5.5/§5.7/§5.8/§5.11 (Phase 7).** §5.5's FIR/biquad/
  cascade are generated (see above) but lattice/parallel/wave-digital/
  comb/CIC/state-space forms aren't; §5.7 (comms/modulation — mixer,
  NCO, PLL, Costas loop, ...), §5.8 (adaptive/statistical — LMS/RLS,
  ...), and §5.11 (analysis-plot objects — pole-zero, Bode, Nyquist,
  spectrogram, ...) are entirely unimplemented. None of the filter
  generators have a palette/drag-to-canvas entry point yet either —
  they're called directly (as the tests do); wiring one into
  `StencilPalette`/`StencilCanvasArea` (which only knows single-block
  `StencilDefinition`s, not multi-element `FilterStructure`s) is
  unstarted UI work.
- **LaTeX (§11, Phase 9)**, **vector PDF/EPS/TikZ export and printing**
  (§11, Phase 10) — Phase 1's SVG native/plain export is the only export
  path that exists.
- **Polish (§11, Phase 11)**: autosave, templates, dark mode, i18n,
  accessibility, perf tuning at the ≥10,000-element scale, tablet UX.
- Within what *is* built: snapping, orthogonal connector routing
  (today's connectors are straight lines), multi-select-by-shift-click,
  keyboard shortcuts, and rotate/flip transform handles.

## Repo layout

Matches `sigmadraw-implementation-prompt.md` §2:

```
/apps/sigmadraw            # app shell (Flutter app, all 5 platform folders scaffolded)
/packages/sd_document      # ✅ Phase 1 — SVG DOM model, sd: namespace round-trip
/packages/sd_graph         # ✅ Phase 4+8 — semantic graph, validation, Tarjan, Mason, rate/netlist
/packages/sd_stencils      # ✅ Phase 3+7 (partial) — §5.1,2,3,4,6,9,10 + FIR/biquad/cascade generators
/packages/sd_render        # ✅ Phase 2 (+connectors) — scene, pan/zoom, selection, port-to-port wiring
/packages/sd_ink           # empty — Phase 6 (stroke model, pressure curves)
/packages/sd_input         # empty — Phase 6 (pointer/pen pipeline)
/packages/sd_ui            # 🚧 Phase 3+4 (partial) — palette/tree/inspector/problems/H(z); ribbon in 5
/packages/sd_latex         # empty — Phase 9 (math rendering)
/packages/sd_export        # empty — Phase 10 (SVG/PDF/PNG/EPS/TikZ export)
/packages/sd_commands      # empty — undo/redo (no phase owns it alone; needed by 2+)
/plugins/sd_pen_*           # placeholder READMEs — Phase 6 native pen plugins
/docs                       # architecture-mining notes (§1) + this project's own notes
```

## Architecture decisions not obvious from the spec

- **melos config lives in the root `pubspec.yaml`, not `melos.yaml`.**
  Melos ≥7 dropped the standalone `melos.yaml` file; its config is a
  `melos:` key in the same `pubspec.yaml` that declares the Dart/Flutter
  native `workspace:` list (melos reuses that list as its package set).
  There is one root manifest, not two.
- **Pure-Dart vs. Flutter packages.** `sd_document`, `sd_graph`,
  `sd_stencils`, `sd_ink`, and `sd_commands` are plain Dart packages (no
  Flutter SDK dependency) — testable with plain `dart test`, parseable off
  the UI isolate with `Isolate.run` with no engine to spin up.
  `sd_render`, `sd_input`, `sd_ui`, `sd_latex`, and `sd_export` are Flutter
  packages, since they genuinely need the framework (`CustomPainter`,
  `PointerEvent`, platform channels, widgets). See the `melos:` scripts in
  `pubspec.yaml` (`test-dart` / `test-flutter`), which filter on exactly
  this split.
- **`SdChangeNotifier` instead of Flutter's `ChangeNotifier`.** §2 asks for
  "feed a Listenable to `CustomPainter.repaint`", but `sd_document` can't
  depend on Flutter (previous bullet). `SdChangeNotifier`
  (`packages/sd_document/lib/src/document_tree.dart`) is a tiny
  dependency-free class with the exact same method names
  (`addListener`/`removeListener`/`notifyListeners`) as Flutter's
  `Listenable`/`ChangeNotifier`, so `sd_render` (Phase 2) can bridge one to
  a real `ChangeNotifier` with one line, with no adapter interface needed.
- **An edge is an attribute bag, not a `<sd:edge>` element.** §3 describes
  block semantics as attributes on an existing SVG element, then says
  edges are "`sd:edge` with `sd:from=...`, `sd:to=...`" — read literally
  that's ambiguous between a new element and an attribute. Implemented as
  an attribute (`sd:edge="<id>"`) on the SVG element that renders the wire
  (mirrors how `sd:type`+`sd:id` mark+identify a block), keeping edges in
  the same "plain geometry + `sd:` attributes" dual representation as
  blocks — see the doc comment on `SdEdgeSemantics`.
- **`sd_document`'s `sd:params`/`sd:ports` accessors are raw JSON, not a
  typed `Port`/dtype model.** That richer typed model is explicitly
  `sd_graph`'s job (§4), built in Phase 4 on top of these raw accessors.
  Keeping it out of `sd_document` keeps that package at the generic
  XML/round-trip level it's actually scoped to.
- **`directFeedthrough` is persisted as `sd:directFeedthrough`, not just
  held on an in-memory `StencilDefinition`.** A reopened document has to
  be analyzable (loop detection needs this per block) without access to
  whatever stencil registry originally created it — "the `.svg` file IS
  the document" (§0) has to include this fact, not just geometry.
- **Mason's formula uses a small symbolic `Expr` engine with eager-but-
  incomplete simplification, verified by evaluating at sample points
  rather than by canonical-form string comparison.** A fully-canonicalizing
  computer-algebra system is a project of its own; evaluating the derived
  `H(z)` at several `z`/parameter values against an independently-derived
  closed form (see `mason_test.dart`'s biquad case) is rigorous without
  needing one, and is how that test actually caught the rate-propagation
  bug described above.
- **An edge is created by dragging port-dot to port-dot on the canvas**
  (`sd_render`'s `SigmaCanvas`), not through a separate "connector tool" —
  there's no tool-mode concept yet (that's the ribbon's job, Phase 5), so
  the canvas just recognizes "pointer-down near a port" directly.

## Build & test

```sh
dart pub get              # resolve the workspace once
dart run melos bootstrap  # link packages, generate IDE files

dart run melos run format-check
dart run melos run analyze
dart run melos run test          # test-dart, then test-flutter
dart run melos run build-linux   # smoke-build the app shell (Linux)
```

(If `melos` is globally activated — `dart pub global activate melos` — you
can drop the `dart run` prefix.) CI (`.github/workflows/ci.yml`) runs the
same steps, plus a build smoke-test, on Linux/macOS/Windows.

## Git

A repo was initialized here (`git init`); commits so far track each
phase checkpoint (`git log --oneline`).
