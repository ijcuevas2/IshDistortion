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
  `Block.isSubsystem`, not built — pole-zero generation followed later,
  see below) and treating a multirate block as anything but unity gain
  in H(z) — both documented in code comments at the point they matter.
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
- **Phase 10 (partial) — TikZ export.** `packages/sd_export`:
  `exportToTikz` walks the semantic graph (`sd_graph`) and emits
  standard-TikZ source (not the rarely-installed `tikz-dsp` package) —
  one named, styled node per block (circle for adders/pickoff nodes,
  triangle for gains, rectangle otherwise) positioned from its resolved
  world transform, and one `\draw[->] (a) -- (b)` per edge, relying on
  TikZ's own shape-boundary clipping rather than replicating port
  geometry. **Verified against §13's own acceptance bar ("TikZ export
  compiles") by actually invoking `pdflatex`** — not just asserting on
  the generated string — in a scratch temp directory, on both a small
  hand-built chain and a full generated `buildBiquadDf2t` filter, and
  checking a real, non-empty PDF comes out with exit code 0. (The
  toolchain check is graceful: the two compilation tests skip themselves
  if `pdflatex` isn't on `PATH`, rather than failing an environment that
  never had LaTeX installed.) 8 new tests.
- **Phase 9 — math rendering, both paths §11 asks for.**
  `sd_graph` gained `Expr.toTex()` (mirrors `toString()`'s precedence
  handling exactly, substituting real LaTeX: braced `z^{-k}`, `\frac`,
  and `<letter><digits>`-shaped coefficients like `b0`/`a1` rendered as a
  proper subscript `b_{0}`/`a_{1}`) — verified the same way as Mason's
  formula itself: not string-matching, but actually `pdflatex`-compiling
  the rendered H(z) for the §13 biquad case, numerically *and*
  symbolically. `sd_document` gained `sd:latex`/`SdLatexSemantics`
  (§11's "store original LaTeX source, textext-style editable"). The new
  `packages/sd_latex`: `LatexLabel` wraps `flutter_math_fork` for fast
  on-screen rendering (falls back to showing its own raw source, not a
  bare error, for a command outside that KaTeX subset) — now wired into
  `sd_ui`'s H(z) panel, which shows real typeset math instead of a
  monospace expression string; `compileLatexToSvg`/`embedLatex` is the
  *desktop* path — `pdflatex` -> `dvisvgm --pdf --no-fonts`, run off the
  UI isolate, id-prefixed by a content hash so multiple embedded
  equations never collide — producing real vector glyph-outline
  `<path>`/`<use>` content spliced into the document as an ordinary `<g>`
  (verified end to end: compiled for real, round-tripped through native
  SVG save/reload, and confirmed to actually paint via this project's own
  `SpatialIndex`/`buildScene`, not just "looks like plausible XML");
  `LatexRenderCache` avoids recompiling an unchanged source. 26 new
  tests (11 in `sd_graph`, 3 in `sd_document`, 12 in `sd_latex`).
  Not implemented: an equation-editor dialog/launcher (§10's Insert
  ribbon item — there's no ribbon yet either), the built-in DSP label
  helpers beyond what a stencil already renders itself (x[n]/y[n]-on-
  edge, ...), and the optional experimental WASM-TeX fallback.
- **`sd_commands` — undo/redo (§2/§12), wired into every editing
  surface.** Not owned by one phase (§2 lists it as its own package,
  "needed by 2+"), and until now completely unbuilt despite the app
  already having several real ways to mutate a document. The classic
  Command pattern (`SdCommand.apply`/`unapply`, not Inkscape's own
  whole-tree-diffing approach — a deliberate, documented simplification)
  plus an `UndoStack` with explicit transactions: `beginTransaction`/
  `commitTransaction` collapse everything executed in between into one
  undo step (Inkscape calls the same idea "event grouping"/"maybe
  done"), which is what turns a drag's dozens of per-frame attribute
  writes into the single "Undo" a user expects. Wired into every
  existing mutation site: `sd_render`'s `SigmaCanvas` (move drags, scale
  drags, and connector creation — each takes an optional `UndoStack?`,
  `null` preserving the old direct-mutation behavior exactly), and
  `sd_ui`'s `InspectorPanel` (label/param edits) and `StencilCanvasArea`
  (palette drop-to-place). The app shell shares one `UndoStack` across
  all of these and exposes it via app-bar Undo/Redo buttons *and*
  Ctrl+Z/Ctrl+Shift+Z/Ctrl+Y keyboard shortcuts — both verified with real
  widget tests (drag a block, undo via the button; place a stencil, undo
  via the keyboard). 38 new tests (27 in the new `sd_commands`, 4 in
  `sd_render`, 3 in `sd_ui`, 3 in the app). Not implemented: wiring
  ElementTree/ProblemsPanel-triggered edits (neither mutates the
  document) and disk-backed persistence of the history across a
  document reload — delete followed later, see below.
- **Phase 6 (partial) — the ink pipeline, and an actual "draw with the
  mouse" tool.** `packages/sd_ink` (pure Dart): a real §6 pipeline —
  speed-based pressure inference (an atan sigmoid — slower reads as
  more pressure) for pressureless devices, a moving-average stabilizer,
  Ramer-Douglas-Peucker simplification, Catmull-Rom curve fitting
  (spline-interpolating pressure *and* position together, not just
  position), and — the core geometry — converting the resulting
  variable-width centerline into a **filled outline** `<path>` (offset
  polygon each side; a single tap becomes a filled circle) rather than
  a variable-width stroke, so it renders in any plain SVG viewer with
  no special support needed. Verified with hand-derived geometry (a
  straight constant-pressure stroke's outline vertices match a
  6.75-unit half-width rectangle to `1e-6`, computed independently by
  hand from the pressure curve — not just "some path came out").
  `sd_document` gained `sd:strokePoints`/`strokeCenterline`, alongside
  the already-existing `sd:pressure`, so the *editable* control polygon
  (not just its pressures) actually round-trips — the outline alone
  can't be reconstructed back into a centerline once width varies
  point-to-point. Wired into `sd_render`'s `SigmaCanvas` as a real,
  minimal `CanvasTool` (`select`/`ink` — a two-value precursor to §10's
  ribbon tool selector): the ink tool draws a lightweight raw-polyline
  preview overlay while dragging (never running the full pipeline
  per-point) and commits the real outline path — through the same
  `UndoStack` as everything else — on pen-up. The app bar's segmented
  button switches tools for real. 42 new tests (4 `sd_document`, 30
  `sd_ink`, 6 `sd_render`, 2 the app) — including an end-to-end one that
  taps the Ink button, drags with a simulated mouse, and undoes it via
  the same Undo button a placed stencil would use.
  Not implemented: the Kalman/Krita "pulled string" stabilizers,
  Schneider curve fitting, velocity-based width modulation, tilt-shaped
  nibs, and erasers beyond whole-stroke delete (not even wired to a UI
  gesture yet — only proven via `RemoveChildCommand` in `sd_commands`'s
  own tests).
- **§7 — device classification and palm rejection.** The new
  `packages/sd_input`: `classifyDevice` (pen/pen-eraser/touch/mouse,
  straight off Flutter's own `PointerEvent.kind` — nothing platform-
  specific is needed for this part), `PalmRejectionFilter` ("while a
  stylus is in proximity/down, route touch to pan/zoom only" — tracked
  across every simultaneous pointer, not just one, and by *proximity*
  via `onPointerHover`, not just by being fully down), and
  `hasInkablePressure` (Xournal++'s "never trust the input system; only
  ink on positive pressure"). Wired into `SigmaCanvas`'s ink tool in
  place of the ad hoc stylus check it had before. Finding this actually
  worth wiring up (rather than just unit-testing `sd_input` in
  isolation) surfaced a real bug: `SigmaCanvas`'s drag state
  (`_dragMode`/`_inkPoints`/...) was a single global state machine with
  no notion of *which* pointer owned it, so a second, simultaneous
  pointer (exactly what a resting palm is, next to an active stylus)
  silently clobbered the first's in-progress stroke — a real widget
  test simulating both at once caught it. Fixed with a `_dragPointer`
  id guard (every handler now ignores events from any pointer other
  than whichever one is driving the current drag) — see the
  architecture-decisions note on its one known remaining limitation
  (ordering: stylus-then-palm is handled, palm-then-stylus isn't). 19
  new tests in `sd_input`, 2 more in `sd_render` (the palm-rejection
  scenario itself, both orderings).
  Not implemented: the 5 native pen plugins (`PenSample` streams,
  capability-query channels, and each platform's own pressure/tilt/
  twist/eraser API) — this sandbox can only build/run the Linux desktop
  target anyway, and even Linux's own pen support (libinput/XInput2/
  Wayland tablet_v2) is real native-code work on its own — nor
  coalesced/predicted point history or a "Pen status" capability UI.
- **§5.11 — pole-zero analysis, from the same H(z) the transfer-function
  panel already computes.** `sd_graph` gained `Complex` (a minimal
  complex-number type — `dart:math` has none), `findPolynomialRoots`
  (Durand-Kerner/Weierstrass simultaneous root-finding), and
  `computePoleZero`, which reads `H(z)` as a ratio of polynomials in
  `z` (walking the `Expr` tree, substituting any bound parameters) and
  finds each polynomial's roots. Verified against the biquad DF2T's
  poles/zeros computed independently by hand via the quadratic formula
  (matching to `1e-6`) — the same rigor as the Mason's-formula
  acceptance test itself, not just "a plausible-looking result came
  out". That verification caught two real bugs before either shipped:
  a reversed-polynomial mixup in the `z^-1`-to-`z` conversion (an
  earlier version silently produced the *reciprocal* roots), and an
  unhandled case where every path from source to sink passes through
  at least one delay (e.g. a bare `source -> delay -> sink`, `H(z) =
  z^-1`) — the numerator/denominator's own smallest present power
  wasn't being factored out, so `findPolynomialRoots` rejected the
  result outright instead of reporting the single pole at the origin
  it actually has. `sd_render` gained `PoleZeroPlotPainter` (the unit
  circle, axes, `x` poles, `o` zeros); `sd_ui`'s new `PoleZeroPanel`
  wires it to the live document (mirroring `TransferFunctionPanel`'s
  pattern exactly) and calls out stability explicitly ("every pole
  strictly inside the unit circle") rather than leaving it to be
  eyeballed against the circle. A 5th app tab, "Pole-Zero", makes it
  reachable in the running app. 38 new tests (24 `sd_graph`, 8
  `sd_render`, 5 `sd_ui`, 1 the app).
  Not implemented: the rest of §5.11's analysis plots (Bode, Nyquist,
  spectrogram, ...) and hierarchical/subsystem-aware analysis (the
  same scope cut Mason's formula itself already documents).
- **§10's Home-tab "Clipboard" group, in miniature — Delete/Copy/
  Paste.** `sd_document` gained `cloneNode` (a generic deep, fully-
  detached clone of any node — the foundation copy/paste needs, since
  an `SdElement` is mutable and parented, so paste can't just reuse the
  original object). `sd_render` gained `deleteSelection` (an undoable
  transaction that also deletes every edge attached to a deleted
  *block*, so deleting one doesn't leave dangling wires for
  `sd_graph`'s validation to merely report as a separate problem),
  `SdClipboard` (an in-memory clipboard — nothing OS-level, nothing
  persists across a restart), and `copySelectionToClipboard`/
  `pasteFromClipboard` (paste mints a fresh id for each pasted block/
  edge to avoid colliding with the target document, and offsets the
  paste so it doesn't land exactly on top of what was copied — edge
  connectivity *between* copied elements isn't preserved, a documented
  scope cut: the common "duplicate one block" case doesn't need it).
  Wired into the app bar (Delete/Copy/Paste buttons, gated on whether
  anything is selected) and the keyboard (Delete/Backspace/Ctrl+C/
  Ctrl+V), all routed through the same `UndoStack`. A real widget test
  caught a genuine gap while verifying this: undoing a delete restores
  the *document* but not the prior *selection* (there's no way for
  `UndoStack` to know what a command affected without `SdCommand`
  exposing that, which nothing needs badly enough yet to add) — the
  test now asserts that documented behavior instead of the wrong
  assumption it started from. 25 new tests (8 `sd_document`, 13
  `sd_render`, 4 the app).
  Not implemented: reaching the OS clipboard (so paste can't cross
  into/out of another application), and preserving wiring when copying
  more than one connected block at once.

**Next, if this continues**: Ribbon UI (5), the 5 native pen plugins
(6/7), the rest of vector export — PDF/PNG/EPS/print (10) —, the rest
of §5.11's analysis plots, and polish (11) are all **not started**, and
§5.5/§5.7/§5.8 remain thin and Phase 9's equation-editor UI is missing
(previous bullets). Given the true scope of §0-§15 (a production,
cross-platform, multi-native-plugin app), these were not attempted in
the interest of not shipping shallow/fake versions of them — see
"What's not built" below.

`plugins/sd_pen_*` are placeholder READMEs — see each one for what
it'll need to become.

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
- **All 5 native pen plugins (§6-§7, Phase 6).** The stroke model,
  pressure/speed pipeline, outline geometry, device classification, and
  palm rejection all exist and are wired into a real (if minimal) draw
  tool (see above) — what's missing is every
  `plugins/sd_pen_{windows,macos,linux,android,ios}` native plugin
  itself. This sandbox can only build/run the Linux desktop target
  anyway, so the other 4 couldn't have been compiled or tested here
  even if written, and Linux's own pen support (§7: libinput/XInput2/
  Wayland tablet_v2) is a real native-code undertaking on its own.
- **The rest of §5.5/§5.7/§5.8/§5.11 (Phase 7).** §5.5's FIR/biquad/
  cascade are generated (see above) but lattice/parallel/wave-digital/
  comb/CIC/state-space forms aren't; §5.7 (comms/modulation — mixer,
  NCO, PLL, Costas loop, ...) and §5.8 (adaptive/statistical — LMS/RLS,
  ...) are entirely unimplemented. §5.11's pole-zero plot is done (see
  above) — Bode, Nyquist, and spectrogram plots aren't. None of the filter
  generators have a palette/drag-to-canvas entry point yet either —
  they're called directly (as the tests do); wiring one into
  `StencilPalette`/`StencilCanvasArea` (which only knows single-block
  `StencilDefinition`s, not multi-element `FilterStructure`s) is
  unstarted UI work.
- **The rest of LaTeX (§11, Phase 9).** Both rendering paths exist and
  are wired into the H(z) panel (see above) — what's missing is UI to
  *author* a standalone equation with them: an equation-editor dialog/
  launcher (§10's Insert ribbon item), and the built-in DSP label
  helpers (gain-coefficient-on-triangle, `x[n]`/`y[n]`-on-edge, ...)
  beyond what a stencil already renders itself.
- **The rest of vector export (§11, Phase 10): PDF, PNG@DPI, EPS/PS, and
  print dialogs.** TikZ export is done (see above) and Phase 1's SVG
  native/plain export already existed; a real, standard-TikZ,
  `pdflatex`-verified path is the one export format beyond SVG that
  exists so far.
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
/packages/sd_graph         # ✅ Phase 4+8+5.11 — semantic graph, validation, Tarjan, Mason, rate/netlist, pole-zero
/packages/sd_stencils      # ✅ Phase 3+7 (partial) — §5.1,2,3,4,6,9,10 + FIR/biquad/cascade generators
/packages/sd_render        # ✅ Phase 2 (+connectors) — scene, pan/zoom, selection, port-to-port wiring
/packages/sd_ink           # ✅ Phase 6 (partial) — stroke model, pressure curves, outline geometry, wired as a canvas tool
/packages/sd_input         # ✅ Phase 7 (partial) — device classification, palm rejection; 5 native plugins pending
/packages/sd_ui            # 🚧 Phase 3+4 (partial) — palette/tree/inspector/problems/H(z)/pole-zero; ribbon in 5
/packages/sd_latex         # ✅ Phase 9 — flutter_math_fork on-screen + pdflatex/dvisvgm desktop pipeline
/packages/sd_export        # ✅ Phase 10 (partial) — TikZ export, pdflatex-verified; PDF/PNG/EPS/print pending
/packages/sd_commands      # ✅ undo/redo + transactions (no phase owns it alone; needed by 2+) — wired into sd_render+sd_ui+app
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
- **TikZ export targets standard TikZ, not the `tikz-dsp` package.**
  `tikz-dsp` isn't in this sandbox's LaTeX distribution (nor most others
  by default — it's a niche CTAN package), so depending on it would make
  the "TikZ export compiles" acceptance test (§13) environment-fragile.
  Standard `\node[...]`/`\draw[->]` with named nodes gets the same
  visual result (TikZ clips the arrow to each node's shape boundary
  automatically) without the dependency, and is verified by literally
  shelling out to `pdflatex` on the generated source in a temp
  directory — a string-content assertion alone can't actually prove a
  `.tex` file compiles.
- **The desktop LaTeX pipeline is `dvisvgm --pdf`, not the classic
  `latex` (dvi) -> `dvisvgm` route.** Both exist in this sandbox's TeX
  distribution, but going through `pdflatex` directly (the same tool
  Phase 10's TikZ export already shells out to, and the one `xelatex`/
  `lualatex`-only packages actually need) then handing dvisvgm the PDF
  (`--pdf`) is one fewer intermediate format and one fewer external tool
  invocation than compiling to DVI first — dvisvgm has supported reading
  PDF directly for years, so there's no fidelity cost.
- **A compiled equation's ids are prefixed with a hash of its own source,
  not left as dvisvgm emitted them (`g4-1`, `g3-2`, ...).** Those short
  ids are only unique *within one compiled equation* — embedding two
  different equations in the same document's shared `<defs>` without
  renaming them would silently let one equation's `<use>` resolve to the
  other's (differently-shaped) glyph outline once ids collide. The hash
  (`fnv1a64Hex` — a small dependency-free FNV-1a, not a cryptographic
  hash; nothing security-sensitive keys off it) only needs to be unique
  across the handful of equations one real document embeds, not globally
  unique, so this deliberately doesn't reach for `package:crypto`.
- **`sd_latex`'s desktop pipeline runs the external processes in
  `Isolate.run`, but returns only the raw SVG *text* across the isolate
  boundary — never an `SdElement`/`SdNode` object graph.** §2/§14 are
  explicit that LaTeX compilation must not block the UI isolate; sending
  a plain `String` back is unambiguously safe to pass between isolates
  and sidesteps ever having to reason about whether this project's
  mutable, parent-linked document-tree nodes are safe to transfer (they
  likely are — Dart's isolate messaging preserves object graphs,
  including cycles — but there's no need to depend on that when the
  actual expensive step, external process I/O, doesn't require it).
- **`sd_commands` groups a drag into one undo step via explicit
  transactions, not time-window/same-attribute coalescing.** An earlier
  design had each new command ask the undo stack's top entry "can you
  merge with this?" (matching attribute + a short time window) — simpler
  to call, but fundamentally guesses at user intent: two edits to the
  same attribute a beat apart could be either one continuous drag or two
  genuinely separate actions, and a heuristic can't tell them apart
  reliably. `beginTransaction`/`commitTransaction` instead ties grouping
  to the actual gesture lifecycle a caller already knows about
  (pointer-down/pointer-up), which is exactly what Inkscape's own
  `document-undo.cpp` reference does ("event grouping"/"maybe done") —
  and it generalizes for free to grouping edits to *different* elements
  (e.g. a future "delete a block and its edges") that no attribute-based
  heuristic could ever merge.
- **Every call site that can mutate a document takes an optional
  `UndoStack?`, defaulting to `null` (direct mutation, no undo
  tracking), rather than requiring one.** `SigmaCanvas`, `InspectorPanel`,
  and `StencilCanvasArea` all predate `sd_commands` and had passing tests
  exercising their direct-mutation behavior; making the stack optional
  means adopting undo/redo was purely additive — every prior test still
  passes unmodified — instead of a breaking change propagated through
  three packages at once.
- **An ink stroke's persisted, editable form is its *simplified*
  centerline (post-smoothing, post-RDP), not the raw pointer samples or
  the further-subdivided Catmull-Rom points the outline geometry
  actually uses.** The raw samples are noisy (that's the whole reason
  to stabilize them) and the curve-fit samples are one specific
  tessellation of infinitely many that would render identically — persisting
  either would make a later "drag this centerline point" editor either
  fight the noise or have far more points than a user could sensibly
  grab. The simplified polygon is the smallest point set that still
  captures the stroke's actual shape, which is exactly what such an
  editor should expose.
- **The live in-progress-stroke overlay draws a raw polyline through
  the unprocessed samples, not a preview of the real filled outline.**
  Running smoothing + RDP + Catmull-Rom + offset-polygon generation on
  every single pointer-move — for a stroke that could accumulate
  hundreds of samples before pen-up — is exactly the per-point heavy
  work §6 says an ink overlay must never do. The full pipeline runs
  exactly once, at pen-up, against the now-complete sample list.
- **The ink tool is gated by a new two-value `CanvasTool` enum
  (`select`/`ink`) on `SigmaCanvas`, rather than, say, a boolean flag or
  overloading the existing pointer-down hit-testing.** §10's real tool
  selector (a ribbon button group) doesn't exist yet, but *something*
  has to tell `SigmaCanvas` "every gesture is a stroke now, regardless
  of what's underneath the pointer" — a boolean would've worked
  equally well for two tools, but naming it as an enum now means adding
  a third tool later (once the ribbon exists) touches one `switch`, not
  a second boolean flag interacting with the first.
- **`SigmaCanvas`'s drag state gained a `_dragPointer` id guard —
  discovered necessary, not designed in from the start.** Wiring
  `sd_input` in for real (rather than only unit-testing it in
  isolation) meant writing a widget test with a stylus and a touch
  pointer active at once, which exposed a real bug: `_dragMode`/
  `_inkPoints`/etc. were a single global state machine with no notion
  of *which* pointer owned them, so a second simultaneous pointer (a
  resting palm, next to an active stylus) silently overwrote the
  first's in-progress stroke. Every handler now ignores events from any
  pointer other than whichever one is driving the current drag. This
  is a targeted fix, not general multi-pointer support: it only
  prevents a second, ignored pointer from corrupting the first's state,
  and resolves ties by whichever pointer went down *first* — a stylus
  going down *after* an already-dragging touch is itself ignored
  rather than preempting it, unlike the reverse (and much more
  realistic — a hovering stylus is normally sensed before the hand's
  palm makes contact) ordering, which does work correctly.

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
