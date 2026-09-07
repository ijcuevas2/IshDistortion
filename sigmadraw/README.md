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
  coefficient sets and evaluation points each. Not implemented at the
  time: §5.7 (comms/modulation), §5.8 (adaptive/statistical), §5.11
  (analysis-plot objects — all four landed in later checkpoints; see
  above), and the rest of §5.5 (transposed FIR, lattice, DF-I/II,
  parallel, comb, allpass, and CIC all landed later too, see below;
  only wave-digital/coupled-lattice/state-space remain unbuilt). 33
  new tests.
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
- **Phase 10 (partial) — PDF export, on top of that same TikZ
  pipeline.** `exportToPdf` compiles the exact TikZ source
  `exportToTikz` produces via the same `pdflatex` invocation
  `tikz_export_test.dart` already verified compiles — the difference is
  this is now a real library entry point (writes a real `.pdf` file at
  a caller-given path) rather than only a test assertion. Compiles in
  its own scratch temp directory (never the caller's chosen output
  location) so `pdflatex`'s `.aux`/`.log`/... intermediates never leak
  out — only the resulting `.pdf` is copied to `outputPath`, overwriting
  whatever was there (ordinary "export"/"save" semantics). Runs off the
  UI isolate via `Isolate.run`, the same technique (and the same
  reasoning — §2/§14's "do not block the UI isolate on ... export") as
  `sd_latex`'s `compileLatexToSvg`: only plain strings cross the
  isolate boundary, never an `SdDocument` itself. Throws
  `PdfExportException` (mirroring `LatexCompileException`'s shape) if
  `pdflatex` is missing or the source fails to compile — no silent
  fallback, since an explicit export request should fail loudly rather
  than write a blank/wrong file. 3 new tests (all real, pdflatex-
  compiling end-to-end checks, gracefully skipped if `pdflatex` isn't on
  `PATH` — same convention as `exportToTikz`'s own compile tests).
  `sd_ui` gained `ExportPdfDialog` — a new Export ribbon tab's "PDF"
  action, closing the same UI-entry-point gap the equation dialog
  closed for `sd_latex`: type (or accept the suggested) output path,
  Export runs the real pipeline, a `SnackBar` on the app shell confirms
  where it went. Building this surfaced a real, previously-latent
  testing pitfall: `Isolate.run` does not reliably complete when
  exercised from inside a `testWidgets` test (confirmed by watching a
  first draft of this dialog's own test hang indefinitely with no
  `pdflatex` process ever spawned, per `ps`) — the same reason
  `InsertLatexDialog` already went through an injectable
  `LatexRenderCache` rather than calling `compileLatexToSvg` directly,
  just not one this project had hit head-on before. Fixed the same way:
  `ExportPdfDialog.exportPdf` is now injectable (default: the real
  `exportToPdf`), and its own tests exercise the dialog's reaction to
  success/`PdfExportException`/a bad path via an injected fake — the
  real pipeline stays fully covered in `pdf_export_test.dart`'s plain,
  non-widget tests instead. Also broadened the dialog's own error
  handling to a separate `FileSystemException` catch (friendlier
  message) alongside `PdfExportException`, since a hand-typed path
  (there's no native file-picker dependency here) can easily name an
  unwritable location — `exportToPdf`'s own compile step can succeed
  before failing only on the final copy. 6 new `sd_ui` tests, 1 new app
  test. Not implemented at the time: PNG@DPI and EPS/PS (both see
  below — landed in later checkpoints), print dialogs, and a real
  native file-save picker (a plain text field stands in for one).
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
  Not implemented at the time: the rest of §5.11's analysis plots (Bode,
  Nyquist, and a spectrogram — which needs an actual sampled signal to
  analyze rather than only a symbolic transfer function — all landed in
  later checkpoints; see below) and hierarchical/subsystem-aware
  analysis (the same scope cut Mason's formula itself already
  documents).
- **§5.11 — Bode plot, evaluating that same H(z) around the unit
  circle instead of solving it for roots.** `sd_graph` gained
  `computeBodePlot`: magnitude (dB) and *unwrapped* phase (degrees) of
  `H(e^{jω})` swept linearly from DC (`ω=0`) to Nyquist (`ω=π`) —
  linear, not log, since a discrete-time transfer function's whole
  meaningful domain is that one finite interval, unlike a classical
  continuous-time Bode plot's many-decade log axis. Reuses
  `computePoleZero`'s own `rationalPolynomials` reading of `H(z)` as a
  ratio of `z^-1`-power sparse maps, but evaluates each directly via
  `Complex` arithmetic at a specific point rather than clearing a
  common factor and solving for roots (evaluating at `z=e^{jω}` is
  always well-defined — that point is never zero — so none of
  `_clearedZPolynomial`'s root-finding-specific care is needed here).
  Verified with several hand-derivable cases: a pure gain (flat
  magnitude, zero phase at *every* frequency), a pure unit delay
  (exactly 0 dB, phase exactly `-ω` — an all-pass, linear-phase system,
  checked at every swept point, not just one), and the same biquad
  `pole_zero_test.dart` already verifies — its independently-confirmed
  zeros at `z=±1` land exactly at this plot's DC and Nyquist ends,
  cross-checking the two features against each other from two
  unrelated code paths (root-finding vs. point-evaluation). `sd_render`
  gained `BodePlotPainter` (a two-pane magnitude/phase chart; a
  magnitude of `±infinity` — a pole or zero landing exactly on the
  unit circle — clamps to the chart's own axis range rather than
  running off it, the same convention real plotting tools use);
  `sd_ui`'s new `BodePanel` mirrors `PoleZeroPanel`'s message-state
  pattern exactly. A 6th app tab, "Bode", makes it reachable. Building
  this also surfaced a genuine ribbon usability gap, fixed alongside
  it: `RibbonAction`'s caption label was a plain, non-interactive
  `Text` sibling next to the real tap target (`IconButton`) — found by
  a new app-level test that (correctly, per real ribbon UX) tapped a
  button by its label rather than its icon and got nothing. Fixed by
  wrapping the whole control in one `InkWell`. 25 new tests (9
  `sd_graph`, 8 `sd_render`, 6 `sd_ui` — including the ribbon tap-target
  regression test — 2 the app).
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
- **Phase 5 — the Ribbon UI, and Phase 9's missing equation dialog.**
  `sd_ui` gained a hand-rolled, data-driven `Ribbon` (`RibbonTab` >
  `RibbonGroup` > `RibbonAction`/`child`) — tabs of titled command
  clusters, the shape common to Office/WPS/LibreOffice ribbons, built
  from plain Material widgets rather than any one of them's actual
  chrome (the brief's own "do not pixel-copy Office ribbon chrome").
  Replaces the app bar's old plain `Row` of buttons: a **Home** tab
  with Undo/Redo, Clipboard (Copy/Paste/Delete), Tools (the existing
  Select/Ink `SegmentedButton`, now living in a group's `child` slot),
  and a new **Zoom** group (`SigmaCanvasState.zoomByFactor`/
  `fitToContentAuto`, reached through `StencilCanvasArea`'s
  `canvasKey`); an **Insert** tab with an **Equation** action opening
  the new `InsertLatexDialog` — the UI entry point Phase 9's own doc
  comment had flagged as the one missing piece of the LaTeX pipeline.
  The dialog shows a live preview via the fast on-screen `LatexLabel`
  path while typing, then on Insert runs the real `pdflatex`+`dvisvgm`
  toolchain (through an injectable `LatexRenderCache`, so tests don't
  each spawn a real LaTeX process) and splices the result in as one
  undoable step — see the `positionLatexEmbed` architecture note below
  for how that's made undoable without changing `embedLatex`'s own
  contract. Existing icon-based widget-test finders
  (`find.widgetWithIcon(IconButton, Icons.undo)` etc.) needed no
  changes: every `RibbonAction` still renders as a real `IconButton`
  with the same icon, just re-parented into the ribbon. 22 new tests
  (5 `sd_render` — the zoom controls — 12 `sd_ui`, and the app's
  existing suite re-verified green against the new shell). Not
  implemented: a Stencils flyout on the Insert tab — deliberately
  skipped since the always-visible palette sidebar already covers
  drag-to-place discovery and a flyout would only duplicate it — and
  docking/undocking panels (still a fixed three-pane layout).
- **§2/§10 — document persistence: Save and Open, the app's first of
  any kind.** Until now every diagram lived only in memory and vanished
  when the app closed — Phase 1's `writeSdDocument`/`parseSdDocument`
  had existed since the very first session but had no UI caller at all.
  `sd_ui` gained `SaveDocumentDialog` (serializes via `writeSdDocument`,
  a plain synchronous file write — no toolchain, no `Isolate.run`, so
  none of `ExportPdfDialog`'s injectable-seam machinery is needed here)
  and `OpenDocumentDialog` (reads + `parseSdDocument`s a file,
  deliberately *not* replacing the app's document itself — see its own
  doc comment — just handing the parsed result back to whoever asked).
  The app shell's Home tab gained a **File** group (Open/Save, ahead of
  Undo) — the *first* group in the ribbon's own tab, not appended at
  the end, matching where a real ribbon (and this project's own
  brief) puts file operations. `_openDocument` is the one place that
  actually *adopts* an opened document: swaps `_document` (no longer
  `late final`) and its `DocumentListenable` (disposing the old one),
  and clears `UndoStack`/`SelectionModel` — stale undo history or a
  stale selection referencing the *old* document's elements could never
  apply to the new one, the exact scenario `UndoStack.clear`'s own doc
  comment names. The canvas and the tabbed panels area are each keyed
  on `ValueKey(_document)` so every panel caching its own
  `DocumentListenable` in `initState` (several do) gets a clean remount
  bound to the new document on Open, rather than silently continuing to
  react to a document that's no longer current — found necessary by a
  real app-level test that opened a second document and initially still
  saw the first one's content. Building this also required a genuine
  `Ribbon` layout fix: a 5th Home-tab group (File, on top of
  Undo/Clipboard/Tools/Zoom) overflowed a normal window's width, so the
  group row now scrolls horizontally instead of clipping unreachable
  content — the same real-world behavior any ribbon needs once enough
  groups accumulate on one tab, not something this project can
  outgrow more gracefully by coincidence. 10 new `sd_ui` tests, 2 new
  app tests. Not implemented: a real native file-save/open picker (a
  plain text field stands in for one, same as `ExportPdfDialog`), "Save
  As" vs. "Save" distinction, a document-dirty/unsaved-changes
  indicator, and prompting before an Open discards unsaved work.
- **Phase 10 — PNG export, closing §11's "PNG@DPI" target.**
  `sd_export` gained `exportToPng`: renders the document through the
  *exact same* on-screen scene-painting code `SigmaCanvas` itself uses
  (`buildScene` + a newly-extracted `paintSceneNode` — factored out of
  `ScenePainter`, which now just calls it, so the live canvas and this
  offscreen export can never quietly diverge into two different
  renderers) onto an offscreen `dart:ui` `PictureRecorder`/`Canvas`,
  sized to the document's own declared `width`/`height` (times an
  optional `scale`, for a "2x" export) rather than its content's
  bounding box — the same convention any standard SVG viewer uses for
  those attributes. Deliberately *not* run through `Isolate.run` (see
  its own doc comment): `dart:ui`'s rendering primitives are tied to
  the single UI isolate a Flutter engine runs on, so there's no
  background isolate to hand this off to — `Picture.toImage`/
  `Image.toByteData` are still genuinely async (real rasterization on
  the engine's own raster thread), so this doesn't block the event
  loop the way a long synchronous computation would.
  `sd_ui` gained `ExportPngDialog` and the app's Export tab a "Raster"
  group alongside "Vector"'s PDF action. Testing this hit a *third*
  variant of this session's `Isolate.run`/`testWidgets` finding:
  `Picture.toImage`/`toByteData` hang the same way `Isolate.run` does
  when awaited directly in a `testWidgets` test — but `tester.runAsync`
  (Flutter's own documented fix for exactly this) resolved it
  immediately for a *direct* call to `exportToPng`, no workaround
  needed, in `sd_export`'s own `png_export_test.dart`. It does *not*,
  however, mix with `tester.tap`/`pumpAndSettle` calls inside its own
  callback — so `ExportPngDialog`'s own widget tests (which need to
  *trigger* the export via a simulated tap, not call it directly) still
  needed the same injectable-seam pattern `ExportPdfDialog` uses for an
  unrelated reason. See the standalone `isolate-run-testwidgets-hang`
  memory (kept in sync with all three findings) for the fuller writeup.
  4 new `sd_export` tests (real, `runAsync`-wrapped, decoding the
  output back to confirm actual pixel dimensions — not just "a file
  came out"), 6 new `sd_ui` tests, 1 new app test.
- **§5.11 — Nyquist plot, the third and last of this project's "big
  three" transfer-function analysis views (pole-zero, Bode, Nyquist).**
  `sd_graph` gained `computeNyquistPlot`: `H(e^{jω})` traced directly in
  the complex plane over the *full* closed contour (`ω` from `-π` to
  `π`), unlike `computeBodePlot`'s `[0, π]` half — a Nyquist plot is
  conventionally the closed curve itself, so stopping at DC would only
  draw half of it. Exploits conjugate symmetry (`H(e^{-jω})` is the
  complex conjugate of `H(e^{jω})` for any real-coefficient transfer
  function — every one this project's stencils can produce) to get the
  `ω < 0` half for free by mirroring the already-computed `ω ≥ 0` half,
  rather than evaluating `H` at twice as many points; `-π` itself is
  omitted from the result (it's the same physical point on the unit
  circle as `+π`, already present, so including both would duplicate
  rather than close the contour). Verified with the same style of
  hand-derivable cases as Bode (a pure gain: every point collapses to
  one; a pure delay: the whole contour lies exactly on the unit circle)
  plus a direct symmetry check and the same biquad DC/Nyquist hand
  derivation Bode's own tests use. `sd_render` gained
  `NyquistPlotPainter` (axes, the traced closed contour, and the
  classical `-1` reference point marked for orientation — this project
  doesn't implement Nyquist's own encirclement-counting stability
  criterion, since §5.11's pole-zero plot already gives a simpler,
  sufficient stability readout for a discrete-time system: every pole
  strictly inside the unit circle); `sd_ui`'s new `NyquistPanel` mirrors
  `BodePanel`'s message-state pattern exactly. Wired as the app's 7th
  tab. 8 new `sd_graph` tests, 5 new `sd_render` tests, 5 new `sd_ui`
  tests, 1 new app test.
- **Phase 10 — EPS export, and a real toolchain-choice finding.**
  `sd_export` gained `exportToEps`, closing §11's "EPS/PS" target — but
  *not* via the classic `latex` (DVI) + `dvips -E` pipeline EPS export
  more traditionally uses, even though that toolchain is present on
  this system. Confirmed by hand: it produces a well-formed but
  entirely *empty* EPS for this project's TikZ diagrams — `dvips`'s own
  reported `%%BoundingBox` looked plausible, but Ghostscript's
  independent ink-based bounding-box detection (`gs -sDEVICE=bbox`)
  found nothing actually drawn on the page. The `standalone` document
  class's bounding-box computation (or TikZ itself) evidently depends
  on pdfTeX-only primitives a plain, non-PDF `latex` run doesn't
  provide. `exportToEps` instead reuses `exportToPdf`'s own
  already-verified `pdflatex` compile step (factored out into a new,
  shared `compileTexToPdfInDirectory` — the same "make the shared step
  non-private, document why" pattern `svgUnitsPerCm` already
  established) and converts *that* PDF to EPS via `pdftops -eps`
  (poppler-utils) — confirmed by hand, the same way, to produce a real,
  correctly-bounded EPS. `PdfExportException` (the compile stage) and a
  new `EpsExportException` (the `pdftops` stage) are both possible,
  and distinguished, since either half of this two-stage pipeline can
  independently fail. `sd_ui` gained `ExportEpsDialog` (the same
  injectable-seam shape as `ExportPdfDialog`, for the same
  `Isolate.run`/`testWidgets` reason) and the app's Export ribbon tab
  gained an "EPS" action alongside "PDF" in the Vector group. 3 new
  `sd_export` tests (real, compiling end-to-end, checking an actual
  non-degenerate bounding box — not just "a file came out"), 7 new
  `sd_ui` tests, 1 new app test.
- **Phase 7/11 — the spectrogram plot.**
  Unlike pole-zero/Bode/Nyquist (all three only ever evaluate `H(z)`
  itself, symbolically or at points), a spectrogram is fundamentally a
  property of a *signal* — so `sd_graph` gained
  `simulateDifferenceEquation` (reads `H(z)` via the same
  `rationalPolynomials` sparse `z^-1`-power maps Bode/Nyquist evaluate,
  normalizes to a dense, `a[0]`-divided direct-form recursion, and runs
  it sample-by-sample against a real input signal — samples before
  index 0 treated as zero, i.e. the filter starts at rest),
  `generateChirp` (a linear DC-to-Nyquist sweep, `x[n] = sin(pi*n^2 /
  (2*(N-1)))` — deliberately not a fixed tone or noise: sweeping any
  LTI filter with a full-spectrum signal and watching what survives at
  each output *time* visibly reveals its passband, in a way one static
  Bode curve doesn't), a direct `O(n^2)` `dft` (not an FFT — this
  project's STFT window sizes are small enough, tens to a few hundred
  samples, that the simpler, directly-verifiable direct sum is plenty
  fast, and nothing else here needs a general FFT), and
  `computeSpectrogram` itself (Hann-windowed STFT of `H`'s simulated
  chirp response, one-sided bins via the same conjugate-symmetry
  reasoning `computeNyquistPlot` already uses the other direction).
  `sd_render` gained `SpectrogramPainter` (time left-to-right, DC-to-
  Nyquist bottom-to-top — matching the pole-zero/Nyquist painters'
  "up is higher" convention — magnitude as a two-stop heatmap color;
  reuses `bodeAxisRange` for its own dB range rather than a second
  near-identical implementation); `sd_ui`'s new `SpectrogramPanel`
  mirrors `BodePanel`/`NyquistPanel`'s message-state pattern exactly.
  Wired as the app's 8th tab. Correction to earlier wording in this
  section: §5.11 actually names 11 plots (pole-zero, magnitude, phase,
  group delay, impulse/step stem, spectrogram, constellation, eye
  diagram, Bode, Nyquist, root locus) — Bode's own two panes cover
  magnitude+phase, so this and the three bullets above it *do* cover
  6 of the 11, but "closes out §5.11 entirely" (as an earlier draft of
  this bullet claimed) was wrong; see "What's not built" for the
  other 5, addressed in later checkpoints where noted.
  18 new `sd_graph` tests, 10 new `sd_render` tests, 5 new `sd_ui`
  tests, 1 new app test.
- **Phase 7 — four more §5.5 filter structures.** `sd_stencils` gained
  `buildFirTransposedDirectForm`, `buildFirLattice`,
  `buildIirDirectFormI`, and `buildIirDirectFormII`, alongside the
  three from the bullet above. `buildFirTransposedDirectForm` realizes
  the *same* `H(z)` as `buildFirDirectForm` via the network-
  transposition theorem's dual topology (no delay chain on the input;
  delays sit on the running-sum edges instead) — verified both by hand
  derivation and by a direct cross-check against `buildFirDirectForm`'s
  own already-verified `H(z)`, for identical coefficients.
  `buildFirLattice` takes the lattice structure's own native parameters
  (reflection coefficients `k_1..k_p`, not direct-form `b_i`s) and is
  verified against the closed-form direct-form-equivalent coefficients
  hand-derived from the lattice's z-domain recursion for `p`=1, 2, and
  3 (e.g. `p=2`: `c0=1, c1=k1(1+k2), c2=k2`) — an independent derivation,
  not a re-run of the generator's own stage-by-stage code.
  `buildIirDirectFormI`/`buildIirDirectFormII` generalize
  `buildBiquadDf2t` (fixed at order 2) to arbitrary order, and are both
  cross-checked against `buildBiquadDf2t` directly for matching
  coefficients (same `H(z)`, different — and differently-costly —
  topologies; see the "Architecture decisions" bullet below on what
  actually differs between DF-I/DF-II/DF2T). One real test bug found
  and fixed along the way (not an implementation bug): an early version
  of the DF-I/DF-II "1st-order case" tests evaluated `H(z)` at a `z`
  that landed exactly on that `H(z)`'s own pole, comparing infinity to
  infinity — `closeTo` correctly refuses to call that "close" (the
  difference is `NaN`), so the fix was picking a different sample
  point, not the implementation. 19 new `sd_stencils` tests.
- **Phase 7 — parallel, comb, allpass, and CIC, four more §5.5
  structures.** `buildBiquadParallel` fans one input into every
  section directly (unlike `buildBiquadCascade`'s output-to-input
  chaining) and sums the outputs, so `H(z)` is a *sum* of each
  section's rather than a product — verified against the sum of each
  section's independently-computed `H(z)`. `buildCombFilter` covers
  both feedforward/FIR (`H(z) = 1 + g·z⁻ᴹ`) and feedback/recursive/IIR
  (`H(z) = 1/(1-g·z⁻ᴹ)`) forms with one `delay` block whose own `k`
  param is set directly to `M` (Mason already reads a delay's `k` as
  `z^-k`, so no `M`-long chain of unit delays is needed the way e.g.
  the FIR generators build one for an unrelated reason — exposing
  every intermediate tap for its own coefficient). `buildAllpassFilter`
  is a thin, honest wrapper over `buildIirDirectFormII`
  (`b: [c, 1], a: [c]`) rather than a second hand-wired topology for
  what is, structurally, just its own order-1 case — verified two ways:
  against the textbook formula directly, and (the real defining
  property of "allpass") that `computeBodePlot`'s own magnitude comes
  out at exactly 0dB at every one of 50 swept frequencies, for four
  different coefficients — 200 assertions confirming `|H(e^{jω})|=1`
  for every `ω`, not simply asserting the formula's own algebra.
  `buildCicFilter` places `stages` real integrators, an actual
  `downsampler` block (only when `decimation > 1`), then `stages` real
  comb sections — a genuinely complete CIC/Hogenauer topology, not a
  same-rate stand-in — but is honest about a real limit inherited from
  Phase 4/8's own documented scope cut: `computeTransferFunction`
  cannot report one meaningful combined `H(z)` across a real rate
  change, so only `decimation: 1` (no `downsampler` in the diagram at
  all) is asserted end to end (against the product-of-cascaded-stages
  closed form); `decimation > 1` is verified structurally (a real,
  correctly-wired, loop-free diagram) without claiming an `H(z)` this
  project's Mason engine can't actually give. 13 new `sd_stencils`
  tests.
- **Phase 7 — the coupled/normalized (all-pole, then pole-*and*-zero)
  lattice, closing out §5.5's lattice family.** `buildAllPoleLattice`
  is the feedback dual of `buildFirLattice`: the *same* per-stage two-
  multiplier relationship, run in reverse (input injected at the top
  stage `f_p`, output taken at the bottom `f_0`), realizing `H(z) =
  1/A_p(z)` for exactly the same `A_p` polynomial `buildFirLattice`
  realizes directly. Each stage solves its own forward equation for
  `f_{m-1}` given `f_m` (the standard "invert one lattice section"
  step); verified for `p`=1, 2, and 3 against the *reciprocal* of
  `buildFirLattice`'s own already-independently-derived closed forms.
  `buildLatticeLadderFilter` then extends it with a second "ladder"
  path — every stage's own `f_m` tapped by its own coefficient and
  summed into the output — the standard Gray-Markel structure for
  realizing a general pole-*and*-zero IIR system from an all-pole
  lattice core (reflection coefficients alone only ever place poles).
  Verified three ways: a `p`=1 and a `p`=2 case, each derived *fresh*
  via z-domain substitution reusing `buildAllPoleLattice`'s own
  already-verified per-stage `F_m/X` relationships (not a textbook
  numerator-coefficient formula taken on faith); and that zeroing
  every ladder coefficient except `c_0=1` reduces it to exactly
  `buildAllPoleLattice`'s own `H(z)`. Refactored `buildAllPoleLattice`
  to share its stage-building core with the new function (returning
  every stage's own `f_m` tap, not just `f_0`) — the same "make the
  shared step non-private, document why" pattern `svgUnitsPerCm`
  established. §5.5's lattice family (FIR direct/transposed/lattice,
  IIR all-pole/pole-zero lattice) is now complete — only wave-digital
  and state-space (A,B,C,D) remain from all of §5.5. 10 new
  `sd_stencils` tests (90 → 100).
- **Phase 7 — state-space (A,B,C,D), leaving only wave-digital in all
  of §5.5.** `buildStateSpaceFilter` is the one filter-structure
  generator here that's naturally matrix-parameterized (`x[n+1] =
  A·x[n] + B·u[n]`, `y[n] = C·x[n] + D·u[n]`, for an `n`-dimensional
  state vector) rather than a fixed handful of scalar coefficients —
  one `delay` per state variable, each one's *input* wired to the
  freshly-computed next-state formula (`n+1` gains summed via a chain
  of adders, same pattern every other generator here already uses),
  its *output* read as the current state; the output tap sums `C·x +
  D·u` the same way. Verified two ways: an `n=1` case against the
  closed-form scalar formula `H(z) = D + z⁻¹·C·B/(1-z⁻¹·A)`, and an
  `n=2` case against a direct, textbook 2×2 matrix-inversion
  computed independently in the test itself (not re-deriving the
  generator's own wiring) — both derived from `H(z) = D +
  z⁻¹·C·(I-z⁻¹·A)⁻¹·B`, which the generator's own doc comment derives
  from the fact that a `delay` block's `output = z⁻¹·input` (already
  established throughout this project) is exactly what a state
  register's own update equation needs, with no separate "next state"
  bookkeeping beyond the diagram's own wiring. 6 new `sd_stencils`
  tests (100 → 106).
- **§5.7/§5.8 leaf stencils.** New `sd_stencils/lib/src/comms.dart`
  (§5.7, 26 stencils: mixer, NCO/DDS, phase shifter, 90° hybrid, I/Q
  mod/demod, matched filter, correlator, integrate-and-dump, the
  PLL's own named sub-blocks — phase detector/loop filter/VCO/
  frequency divider — as separately-placeable stencils rather than one
  opaque "PLL" box, Costas loop, AGC, equalizer, interleaver/
  deinterleaver, encoder/decoder, mapper/demapper, RRC pulse shaper,
  channel, AWGN source, and a constellation reference block) and
  `adaptive.dart` (§5.8: LMS/RLS — with the spec's own "error input +
  dashed coefficient-update path," the dashed line a schematic
  indicator only, no separate real port for a filter's internal taps —
  and a generic estimator; `correlator` is shared with `comms.dart`
  rather than duplicated, since §5.7 *and* §5.8 both name it). Most of
  these are, honestly, "topological/visual only" labeled boxes — the
  same simplification `control.dart`'s `plant`/`controller` already
  make for §5.9 — since a real mixer/PLL/AGC/etc. is a whole subsystem,
  not one concrete z-domain gain a symbolic `H(z)` could meaningfully
  represent. `hybrid90`/`iqDemodulator` are two more multi-output
  blocks sharing the `butterfly`'s own documented Mason-analysis
  caveat. `geometry.dart`'s `lineShape` gained an optional `dashArray`
  param for the LMS/RLS dashed line (additive, every existing call
  site unaffected). Registered in `StencilRegistry.builtIn` and
  exported from the package barrel. 33 new `sd_stencils` tests
  (mirroring `extended_stencils_test.dart`'s existing generic "every
  leaf stencil instantiates/every port lies within its own footprint"
  loop, which already caught a real bug once before — see the
  systolic-cell note in that file — plus targeted checks for the new
  multi-port/multi-input shapes) (106 → 139).
- **§5.11 — group delay, impulse/step response, and root locus (the
  three of the section's remaining 5 plots that are mechanically
  tractable reusing existing infrastructure — see the correction
  above on why 5, not 0, remained).** `sd_graph` gained
  `computeGroupDelay` (`tau(omega) = -dphi/domega`), computed via an
  *exact* symbolic derivative of `H` with respect to `w = z^-1`
  (`tau = Re[w*H'(w)/H(w)]`, standard complex calculus through the
  chain rule) rather than a finite-difference approximation of
  `computeBodePlot`'s own sampled phase, which would only ever be
  approximately right — verified against hand-derivable exact cases
  (a pure `k`-sample delay: exactly `tau = k` at every frequency; a
  pure gain: exactly `0`) *and*, for a biquad, against an
  independently-implemented fine central-difference computed fresh in
  the test (not re-deriving the same symbolic formula twice), matching
  to `1e-3` — real confidence the analytic formula is right, not just
  self-consistent. `computeImpulseResponse`/`computeStepResponse` are
  thin, honest wrappers over the already-existing
  `simulateDifferenceEquation` (an impulse/step response *is*, by
  definition, that function's own reaction to one specific signal),
  verified against the exact same hand-computed geometric-decay case
  `simulateDifferenceEquation`'s own tests use, plus the step
  response's own closed-form geometric partial sum. `computeRootLocus`
  is literally `computePoleZero` called once per swept value of one
  still-symbolic coefficient (the same `bindings` mechanism every
  other analysis here already resolves symbols through) — no new
  root-finding logic — verified against a hand-derivable single-pole
  sweep (`H(z) = 1/(1+k*z^-1)` puts a pole at exactly `z = -k`) and
  that a *second*, un-swept symbol still correctly returns `null`.
  Only the `sd_graph` computation layer landed this checkpoint — no
  painter/panel/app-tab yet for any of the three (see "What's not
  built"). 20 new `sd_graph` tests (114 → 134).
- **§5.11 — group delay, impulse/step response, and root locus get
  their UI layer, bringing 9 of the section's 11 named plots to a full
  painter/panel/app tab.** `sd_render` gains `GroupDelayPainter`
  (single-curve pane, reusing `bodeAxisRange`), `ImpulseStepPainter`
  (two stacked stem/lollipop panes — one vertical line per sample, the
  conventional way a discrete-time response is drawn, not a connected
  curve), and `RootLocusPainter` (the unit circle/axes convention
  `PoleZeroPlotPainter` already established, reusing its own
  `complexToCanvas` directly, plus every pole/zero across every swept
  sample as a scatter — a *deliberate* scope cut from a textbook root-
  locus plot's connected per-root trajectories, which would need a
  pole-tracking/matching step between samples since Durand-Kerner's
  root order isn't trajectory-stable; a disclosed gap, not a silent
  one). `sd_ui` gains matching `GroupDelayPanel`/`ImpulseStepPanel`
  (the usual three message states) and `RootLocusPanel` — which is
  genuinely different: root locus's whole point is sweeping a still-
  *unresolved* coefficient, so this panel finds it automatically via a
  new `Expr.freeSymbols` getter rather than treating an unbound symbol
  as an error the way every other panel does — zero free symbols means
  nothing to sweep, more than one means an ambiguous "which one?" (both
  their own message states), exactly one gets swept from `0` to `2` (a
  fixed default, not yet an adjustable UI control — a disclosed
  simplification). Wired as the app's 9th-11th tabs; the tabbed-panels
  `TabBar` is now `isScrollable` (11 tabs no longer fit the fixed-width
  sidebar at once — the same overflow shape the Ribbon's own
  horizontal-scroll fix already addressed elsewhere), and every
  existing tab-tap test needed `tester.ensureVisible` added first (a
  tap at an off-screen coordinate warns even where it doesn't outright
  fail).
  **Two real bugs found and fixed along the way, not worked around in
  the test:** (1) `computePoleZero` threw an uncaught `ArgumentError`
  instead of returning `null` for an `H(z)` that's identically zero at
  one specific bound value (e.g. a `gain` block bound to exactly `0`)
  — `findPolynomialRoots`'s own "leading coefficient must not be zero"
  check is correct in isolation, but nothing upstream was catching the
  genuinely-degenerate polynomial before it got there; fixed by
  returning `null` for that case, the same "can't do this specific
  analysis" outcome an unbound symbol already produces. (2)
  `computeRootLocus` aborted its *entire* sweep (returning `null`) if
  even one individually-swept value hit that same degeneracy — overly
  fragile for what's usually just one exact point out of many; fixed
  to skip only that one sample and keep the rest, returning `null`
  overall only if every single swept value fails (the real "nothing
  here worked" signal). 3 new `sd_graph` tests for the fix itself, 5
  new `Expr.freeSymbols` tests, 11 new `sd_render` tests, 16 new
  `sd_ui` tests, 3 new app tests.
- **Phase 1/11 — plain SVG export, closing a gap that turned out to be
  UI-only.** `sd_document`'s own `writeSdDocument(..., mode:
  SdSaveMode.plain)` — which strips every `sd:*` attribute for a
  portable file any SVG tool can open, mirroring Inkscape's own "Plain
  SVG" export — already existed and was already tested three times
  over (`svg_round_trip_test.dart` et al.), from Phase 1; the "not
  built" gap this README had been carrying was only ever the ribbon
  entry point. `sd_ui`'s new `ExportSvgDialog` is a near-identical
  sibling of `SaveDocumentDialog` (same plain-synchronous-write shape,
  so the same "no `Isolate.run`, no injectable seam needed" reasoning
  applies) calling `SdSaveMode.plain` instead of the default
  `SdSaveMode.native`. Wired as a third "SVG" action in the Export
  ribbon's Vector group, next to PDF/EPS. Because writing plain SVG
  needs no external process, this is also the *first* export dialog
  whose own app-level test safely taps its real Export button end to
  end (`save_open_test.dart`, alongside Save/Open) rather than only
  confirming the dialog opens the way PDF/EPS/PNG's own app tests are
  limited to. 5 new `sd_ui` tests, 1 new app test.

**Next, if this continues**: the 5 native pen plugins (6/7) and print
export (10) are all **not started**; §5.5's wave-digital form remains
unbuilt (see the "Architecture decisions" entry on why — a real Mason
prerequisite, not just a to-do).
Given the true scope of §0-§15 (a
production, cross-platform, multi-native-plugin app), these were not
attempted in the interest of not shipping shallow/fake versions of
them — see "What's not built" below.

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

- **The rest of the Ribbon/docking UI (§10, Phase 5).** A real tabbed
  `Ribbon` (Home/Insert/Export, see above) now drives Undo/Redo/File/
  Clipboard/Tools/Zoom and the equation/PDF/PNG dialogs — what's still
  missing is a
  gallery-style stencil picker on the ribbon itself (the sidebar
  palette covers this today), more tabs as more features need ribbon
  entry points, and any panel docking/undocking (still a fixed
  three-pane layout, not floatable/rearrangeable).
- **All 5 native pen plugins (§6-§7, Phase 6).** The stroke model,
  pressure/speed pipeline, outline geometry, device classification, and
  palm rejection all exist and are wired into a real (if minimal) draw
  tool (see above) — what's missing is every
  `plugins/sd_pen_{windows,macos,linux,android,ios}` native plugin
  itself. This sandbox can only build/run the Linux desktop target
  anyway, so the other 4 couldn't have been compiled or tested here
  even if written, and Linux's own pen support (§7: libinput/XInput2/
  Wayland tablet_v2) is a real native-code undertaking on its own.
- **The rest of §5.5/§5.7/§5.8/§5.11 (Phase 7).**
  §5.5's FIR direct/transposed-direct/lattice, biquad DF2T/DF-I/DF-II,
  biquad cascade/parallel, comb, allpass, CIC, the coupled/normalized
  (all-pole, then pole-and-zero) lattice, and state-space (A,B,C,D)
  are all generated (see above) — only wave-digital forms remain
  unbuilt from §5.5, and investigating it surfaced a real prerequisite,
  not just "a different primitive vocabulary": a wave-digital adaptor
  (series/parallel) is inherently a multi-input/multi-output block —
  each output wave a *different* linear combination of the *same*
  input waves, exactly the shape `transforms.dart`'s own radix-2
  `butterfly` stencil already has, whose doc comment already flags
  that `sd_graph`'s Mason engine tracks paths/loops by block id, not
  by `(block, port)` pair, so a diagram where two different output
  ports' paths reconverge — structurally unavoidable in any real WDF
  adaptor network, not an edge case — may not get a fully correct
  `H(z)` until that engine is made port-aware. Building adaptor
  stencils now would mean shipping something this project couldn't
  verify to the same standard as everything above (real, independently
  hand-derived `H(z)` checks) — so, the same call already made for
  print dialogs and the native pen plugins, it's left undone rather
  than shipped shallow; making Mason port-aware is the real
  prerequisite, and is its own separate undertaking on `sd_graph`'s
  core (touched by pole-zero/Bode/Nyquist/spectrogram alike), not a
  `filter_templates.dart`-sized addition.
  §5.7 (comms/modulation) and §5.8 (adaptive/statistical) leaf
  stencils are now built (see above) — and, unlike the filter-
  structure generators just above (which return a `FilterStructure`,
  not a placeable `StencilDefinition`, so still need their own UI
  entry point), these needed none: every ordinary `StencilDefinition`
  registered in `StencilRegistry.builtIn()` is already
  search/drag-to-canvas-placeable through the existing, stencil-
  agnostic `StencilPalette`/`StencilCanvasArea` — confirmed by
  `extended_stencils_test.dart`'s own registry-inclusion check, not
  just assumed.
  §5.11's "Analysis Plot" section actually names 11 plots, not 4 — a
  miscounting error in this README's own earlier drafts, corrected
  here: pole-zero, magnitude, phase, group delay, impulse/step stem,
  spectrogram, constellation, eye diagram, Bode, Nyquist, and root
  locus. `computeBodePlot`'s two panes cover magnitude+phase, so
  pole-zero/Bode/Nyquist/spectrogram/group-delay/impulse-step/root-
  locus (see above) cover 9 of the 11 — and, as of a later checkpoint,
  all 9 have a real painter, panel, and app tab (group delay/impulse-
  step/root-locus's own UI landed after this bullet was first written;
  see above). Only a constellation *plot* and an eye diagram remain
  entirely unbuilt — both need a symbol-level modulation/timing
  simulation harness this project doesn't have at all, likely a
  genuinely different shape of problem again, the same kind of finding
  wave-
  digital's own investigation above surfaced. None of
  the filter generators have a palette/drag-to-canvas entry point yet
  either — they're called directly (as the tests do); wiring one into
  `StencilPalette`/`StencilCanvasArea` (which only knows single-block
  `StencilDefinition`s, not multi-element `FilterStructure`s) is
  unstarted UI work.
- **The rest of LaTeX (§11, Phase 9).** Both rendering paths exist and
  are wired into the H(z) panel, and the Insert ribbon's `Equation`
  action now covers authoring a standalone equation (see above) — what
  remains is the built-in DSP label helpers (gain-coefficient-on-
  triangle, `x[n]`/`y[n]`-on-edge, ...) beyond what a stencil already
  renders itself, and the optional experimental WASM-TeX fallback.
- **The rest of vector/raster export (§11, Phase 10): print dialogs.**
  TikZ, PDF, EPS, PNG, and now plain SVG export are all done, and all
  but TikZ have a ribbon UI entry point (see above) — TikZ's own
  output is meant to be pasted into a LaTeX document, so a file-save
  dialog isn't obviously the right UI for it anyway, unlike SVG's,
  which turned out to be a real (if small, UI-only) gap. There's also
  no real native file-save picker anywhere yet — every
  export/save/open path that needs one uses a plain text field for the
  path instead.
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
/packages/sd_graph         # ✅ Phase 4+8+5.11 (9/11 plots, all with UI) — semantic graph, validation, Tarjan, Mason, rate/netlist, pole-zero/Bode/Nyquist/spectrogram/group-delay/impulse-step/root-locus
/packages/sd_stencils      # ✅ Phase 3+7 (partial) — §5.1-4,6,7,8,9,10 leaf stencils + §5.5 nearly complete (FIR/IIR/lattice/comb/allpass/CIC/state-space; only wave-digital left) generators
/packages/sd_render        # ✅ Phase 2 (+connectors, +5.11 plot painters, 9/11) — scene, pan/zoom, selection, port-to-port wiring, pole-zero/Bode/Nyquist/spectrogram/group-delay/impulse-step/root-locus painters
/packages/sd_ink           # ✅ Phase 6 (partial) — stroke model, pressure curves, outline geometry, wired as a canvas tool
/packages/sd_input         # ✅ Phase 7 (partial) — device classification, palm rejection; 5 native plugins pending
/packages/sd_ui            # ✅ Phase 3+4+5 — Ribbon (Home/Insert/Export), save/open+equation+PDF/EPS/PNG/SVG-export dialogs, palette/tree/inspector/problems + 9/11 §5.11 plot panels
/packages/sd_latex         # ✅ Phase 9 — flutter_math_fork on-screen + pdflatex/dvisvgm desktop pipeline
/packages/sd_export        # ✅ Phase 10 (partial) — TikZ+PDF+EPS+PNG export (PDF/EPS/PNG have ribbon UI entry points); print pending
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
  selector (now a ribbon button group, in a `RibbonGroup.child` slot —
  see below) didn't exist yet when this was written, but *something*
  has to tell `SigmaCanvas` "every gesture is a stroke now, regardless
  of what's underneath the pointer" — a boolean would've worked
  equally well for two tools, but naming it as an enum meant adding a
  third tool later touches one `switch`, not a second boolean flag
  interacting with the first.
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
- **`Ribbon` is a hand-rolled `Column`-of-`Row`s over plain Material
  widgets, not the `fluent_ui` package.** `fluent_ui` would get closer
  to real Office/WPS chrome for free, but it's a large, opinionated
  Fluent-Design widget set (its own theming, its own button/nav
  primitives) — adopting it under time pressure risks spending the
  effort learning/fighting its API rather than shipping the actual
  Home/Insert functionality, and the brief itself asks *not* to
  pixel-copy Office's chrome, which is `fluent_ui`'s whole point. A
  small data model (`RibbonTab`/`RibbonGroup`/`RibbonAction`) plus a
  ~150-line stateful widget was enough to get tabs, titled groups, and
  icon-over-label buttons — the load-bearing *shape*, not the skin.
- **`Ribbon` is purely data-driven (`List<RibbonTab>` in, nothing else)
  — reactive enabled-state is the caller's job, via whatever
  `Listenable`s a given action's `onPressed` actually depends on.**
  The alternative (`Ribbon` taking live model references and computing
  "is Undo enabled" itself) would couple a generic, reusable shell to
  this app's specific models (`UndoStack`, `SelectionModel`, ...). The
  app shell instead wraps its one `Ribbon(tabs: ...)` construction in a
  single `ListenableBuilder` over `Listenable.merge([_documentListenable,
  _selection])`, rebuilding the whole (cheap, POD) tab/group/action
  list fresh on every relevant change — replacing what used to be a
  separate `ListenableBuilder` per app-bar button.
- **`InsertLatexDialog` doesn't call `embedLatex` — it calls the new,
  narrower `positionLatexEmbed` and inserts the result itself.**
  `embedLatex` does two things in one non-undoable step: merge the
  compiled equation's glyph-outline `<defs>` into the document, and
  append the visible content. Only the second needs to be an undo
  boundary — an undone insert leaving an unreferenced glyph `<path>`
  behind in `<defs>` is inert (never painted, never round-tripped
  away), the same bookkeeping-vs-content split `sd_stencils`'
  `ensureArrowMarker` already relies on. `positionLatexEmbed` is a
  refactor, not a new code path — `embedLatex` itself now just calls it
  and appends, so its existing tests/contract are unchanged (re-run
  green) while the dialog gets the finer-grained seam it needs for
  `InsertChildCommand`.
- **The Insert-ribbon's Equation action has no accompanying Stencils
  flyout.** The brief's own §10 groups "Stencils" and an equation
  launcher together under Insert; the always-visible sidebar
  `StencilPalette` already covers drag-to-place discovery, so a flyout
  duplicating it would add UI surface (and tests) without adding
  capability — a deliberate scope trim, not an oversight, revisited
  only if docking later makes the sidebar itself optional/hideable.
- **The Bode plot sweeps `omega` linearly over `[0, pi]`, not a
  classical continuous-time Bode plot's log-frequency axis.** A
  log axis exists to make many *decades* of frequency (near-DC out to
  far past a system's corner frequencies) readable on one chart; a
  discrete-time transfer function's entire meaningful domain is the
  single finite interval `[0, pi]` rad/sample (DC to Nyquist) — the
  same reason digital-filter tools like MATLAB's `freqz` plot linearly
  over that interval rather than borrowing the continuous-time
  convention.
- **`computeBodePlot` evaluates `H(z)` directly via `Complex`
  arithmetic at `z = e^{jω}`, rather than reusing
  `computePoleZero`'s leading-coefficient-first, common-factor-cleared
  polynomial array.** That clearing step (`_clearedZPolynomial`) exists
  specifically so `findPolynomialRoots` never sees a spurious zero
  leading coefficient — a concern only *root-finding* has. Evaluating
  at one specific, always-nonzero point (`e^{jω}` is never `0`) has no
  such problem, so the Bode path evaluates `rationalPolynomials`'
  sparse `z^-1`-power maps directly instead, needing only a small
  `Complex`-valued Horner evaluation, not the reversed-polynomial care
  `pole_zero.dart`'s own doc comments document at length.
- **`RibbonAction`'s tap target is the whole control (icon + caption),
  via an outer `InkWell` around the inner `IconButton`, not the icon
  alone.** Found missing by a new app-level test that tapped a ribbon
  button by its visible label (exactly what a real user would try) and
  got nothing — the caption was a plain, inert `Text` sibling. The
  inner `IconButton` stays a real, independently findable widget (so
  every existing `find.widgetWithIcon(IconButton, ...)`-based test kept
  working unchanged); the outer `InkWell` only ever catches a tap that
  lands outside it, on the caption — Flutter's gesture arena resolves
  the overlap rather than double-firing.
- **`PdfExportException` duplicates `sd_latex`'s `LatexCompileException`
  shape rather than reusing it.** The two exceptions represent the same
  *kind* of failure (an external LaTeX-toolchain process is missing or
  errors out) in two otherwise-unrelated packages; adding an
  `sd_export` -> `sd_latex` dependency just to share one ten-line
  exception class would be the wrong direction of coupling (export
  doesn't otherwise need anything `sd_latex` provides) for what it
  would save.
- **`exportToPdf`'s default `scale` duplicates `TikzExportOptions`'
  own default (`1 / svgUnitsPerCm`) as a literal expression, rather
  than reading `const TikzExportOptions().scale` directly.** The
  latter reads more directly but isn't a valid Dart constant expression
  (property access on a const object isn't itself const) — so
  `tikz_export.dart`'s `svgUnitsPerCm` was made non-private instead,
  giving both files one real shared source of truth for the number
  itself, even though the *expression* combining it is written out
  twice.
- **`Isolate.run` does not reliably complete when called from inside a
  `testWidgets` test — any function built on it needs an injectable
  seam if a dialog around it is going to have real widget tests.**
  Discovered the hard way: an early `ExportPdfDialog` test called the
  real `exportToPdf` directly and hung indefinitely — `ps` during the
  hang showed `flutter_tester` running but no `pdflatex` process ever
  spawned, meaning the isolate spawn/handoff itself never completed
  inside that specialized test-hosting engine (a normal Dart VM process
  or a real running app doesn't have this problem — `sd_export`'s own
  plain, non-widget `pdf_export_test.dart` calls `exportToPdf` for real
  without issue). `InsertLatexDialog` had already sidestepped this via
  an injectable `LatexRenderCache` rather than calling
  `compileLatexToSvg` directly, but not for this reason on record —
  this was the first time the underlying constraint got hit and
  understood directly. `ExportPdfDialog.exportPdf` is now the same
  shape of seam (default: the real `exportToPdf`); a future dialog
  wrapping any other `Isolate.run`-based pipeline should follow the
  same pattern from the start rather than rediscover this.
- **The pitfall above turned out broader than "just `Isolate.run`":
  building `SaveDocumentDialog`/`OpenDocumentDialog` next (pure
  synchronous file I/O, no isolate anywhere) hit the *same symptom* —
  a test hung indefinitely — on `await Directory.systemTemp.createTemp
  (...)` specifically; switching that one call to `createTempSync`
  fixed it immediately in an otherwise-identical test.** The real
  pattern is: some async `dart:io` operations (not only isolate-
  spawning ones) don't reliably complete inside `testWidgets`'s zone —
  plain *synchronous* file I/O (confirmed fine) isn't affected. Found
  by writing a series of narrowing diagnostic tests (bare file I/O in a
  test body -> file I/O in a button's `onPressed` -> the real dialog
  widget -> the real dialog with the *exact* failing test's setup)
  until the one line that mattered was isolated, rather than guessing.
  Every dialog test in this project now uses sync `dart:io` calls
  throughout for exactly this reason. See the standalone
  cross-project memory this and the bullet above were promoted to
  (`isolate-run-testwidgets-hang.md`, kept in sync with both findings)
  for the fuller writeup.
- **`_openDocument` swaps `_document`/`_documentListenable` wholesale
  and keys the canvas and tabbed-panels area on `ValueKey(_document)`,
  rather than mutating the existing document's content in place to
  match what was opened.** A `StatefulWidget`'s `initState` runs once;
  several panels (`PoleZeroPanel`, `BodePanel`, `TransferFunctionPanel`,
  ...) bind their own `DocumentListenable` there and never re-bind it
  if `widget.document` merely changes identity on an otherwise-
  unchanged `State` — they'd keep reacting to the *old* document
  forever. Fixing every one of those panels individually (a
  `didUpdateWidget` override apiece) would work too, but touches many
  already-shipped files for the same fix repeated N times; a single
  `ValueKey` at the two points that actually own document identity
  forces Flutter to fully discard and recreate that whole subtree
  instead — found necessary (not merely theorized) by a real app-level
  test that opened a second document and initially still saw the
  first one's content in the Elements tab.
- **`Ribbon`'s group row is a horizontally scrolling
  `SingleChildScrollView`, not a plain `Row`.** Adding the File group
  (Open/Save) as a 5th group on Home — on top of Undo/Clipboard/Tools/
  Zoom — overflowed a normal window's width, caught by a `RenderFlex
  overflowed` assertion in a real app-level test. A production ribbon
  would more likely wrap to a second row or collapse a group behind a
  dropdown once its tab is this full, but scrolling is the simplest
  change that never clips content unreachably, and is itself a normal,
  expected ribbon behavior (Office's own ribbon does this) rather than
  a workaround specific to this one test's window size.
- **`exportToPng` reuses `ScenePainter`'s own node-painting logic
  (extracted to a standalone `paintSceneNode` function `ScenePainter`
  itself now calls) rather than writing separate paint code for
  offscreen export.** The alternative — a second implementation walking
  `SceneNode`/drawing paths/paints for the export path specifically —
  risks the on-screen canvas and an exported image *silently* drifting
  apart over time as one gets a bugfix or a new node kind the other
  doesn't. One function used both ways structurally guarantees "what
  you see is what gets exported" rather than relying on two
  implementations happening to agree; `ScenePainter`'s own contract and
  tests are unchanged.
- **`ExportPngDialog` still needs an injectable `exportPng` seam even
  though `exportToPng` itself has no `Isolate.run`/external process —
  `tester.runAsync` alone isn't enough once the call is *triggered by a
  simulated tap* rather than made directly.** `runAsync` fixed testing
  `exportToPng` directly (a plain call in a test body — see
  `png_export_test.dart`), but wrapping a `tester.tap`+`pumpAndSettle`
  sequence inside `runAsync` (to exercise the dialog's own Export
  button) made `pumpAndSettle` itself time out — `runAsync`'s callback
  is documented to hold only the raw async operation, not `tester.*`
  interactions. The seam is the same shape as `ExportPdfDialog.exportPdf`
  but for a different underlying reason; see the standalone
  `isolate-run-testwidgets-hang` memory for the fuller comparison.
- **`computeNyquistPlot` computes only the `ω ≥ 0` half of the contour
  and mirrors it for `ω < 0`, rather than evaluating `H` at points
  spanning the full `[-π, π]` range directly.** Every transfer function
  this project's stencils can produce has real coefficients (gains,
  delay counts, ...), and `H(e^{-jω})` is always the complex conjugate
  of `H(e^{jω})` for such a function — a standard result, not specific
  to this codebase — so computing the negative half is free once the
  non-negative half (already needed, and already computed identically
  to `computeBodePlot`'s own sweep) exists. Halves the number of
  `Expr`/`Complex` evaluations for the same visual result.
- **`exportToEps` converts an already-compiled PDF via `pdftops -eps`,
  not the classic `latex` (DVI) + `dvips -E` pipeline EPS export more
  traditionally uses — confirmed by hand that the latter silently
  produces an empty file for this project's TikZ diagrams.** `dvips`'s
  own reported `%%BoundingBox` looked entirely plausible on inspection;
  only Ghostscript's independent ink-based bounding-box detection
  (`gs -sDEVICE=bbox`) revealed nothing was actually drawn on the page.
  The `standalone` document class's bounding-box computation (or TikZ
  itself) evidently depends on pdfTeX-only primitives a plain, non-PDF
  `latex` run doesn't provide — plausible-looking metadata is not the
  same as verifying real output, the same lesson this project's export
  functions have applied from the start (see `exportToTikz`'s own
  `pdflatex`-compiles-for-real tests). Going through the PDF this
  project already knows compiles correctly sidesteps the whole
  question; `pdflatex`'s compile step itself is shared with
  `exportToPdf` via a new, non-private `compileTexToPdfInDirectory`
  (the same reasoning `svgUnitsPerCm` already established for sharing
  one file's internals with another in this package).
- **A spectrogram needs an actual sampled signal, so `computeSpectrogram`
  manufactures one — a chirp, not noise, a fixed tone, or silence.**
  Pole-zero/Bode/Nyquist all only ever evaluate `H(z)` itself
  (symbolically, or at specific points on the unit circle); a
  spectrogram is inherently a property of a signal's time-varying
  spectrum, so there's no `H(z)`-only equivalent to fall back on. A
  linear DC-to-Nyquist chirp is the deliberate choice of *which* signal:
  driving any LTI filter with a full-spectrum sweep and watching which
  frequencies survive at which output *time* is a standard way to make
  a filter's passband visible directly in the plot (it visibly fades in
  and out as the sweep passes through the passband) — a single fixed
  tone would only test one frequency, and noise/silence wouldn't show
  the passband's edges as cleanly or wouldn't excite the filter at all.
- **`dft` is a direct `O(n^2)` sum, not an FFT — and `computeSpectrogram`
  reports only one-sided bins, via the same conjugate-symmetry
  reasoning `computeNyquistPlot` already uses.** This project's STFT
  window sizes are small (tens to a few hundred samples), so the
  simpler, directly-verifiable direct sum is plenty fast, and there's no
  other need for a general FFT anywhere else in the codebase yet —
  adding one just for this would be speculative generality. Each frame
  is Hann-windowed before its `dft` (reducing the spectral leakage a
  bare rectangular window would otherwise show at each frame's edges),
  and — since the simulated response is real-valued, so its spectrum is
  conjugate-symmetric, the same fact `computeNyquistPlot` exploits the
  *other* direction to get the `ω < 0` half for free — only bins `0`
  through `windowSize/2` are reported; the negative-frequency half would
  be redundant. `spectrogramMagnitudeRange` also reuses `bodeAxisRange`
  directly for its own dB-range-with-padding-and-cap logic rather than
  a second near-identical implementation, the same `svgUnitsPerCm`-style
  sharing as the bullet above.
- **`buildFirTransposedDirectForm` is built via the network-
  transposition theorem, not by independently re-deriving a topology
  that happens to match.** Transposing a signal-flow graph — reverse
  every edge, swap the input/output roles, and swap each pickoff
  (fan-out) node for a summing junction and vice versa — is a standard
  result: it always preserves the transfer function. Applying it to
  `buildFirDirectForm`'s own graph (one pickoff fanning into a tapped
  delay line, multiplied and summed) mechanically produces the
  transposed form's actual shape (one pickoff, no delay chain on the
  input; delays on the running-sum edges instead) — which is also
  *why* the two are guaranteed to share `H(z)`, not merely observed to
  by testing. `buildIirDirectFormI` and `buildIirDirectFormII` make
  the *cost* difference between "Direct Form I" and "Direct Form II"
  concrete rather than just naming it: DF-I keeps two separate delay
  chains (one `M`-long for the numerator's `x` taps, one `N`-long for
  the denominator's fed-back `y` taps — `M+N` delays total), while
  DF-II computes one intermediate signal `w[n] = x[n] - Σaᵢw[n-i]`
  and reads *both* the feedback and the feedforward taps off that
  same `max(M,N)`-long delay line — the "canonical"/minimal-delay
  property DF-II is specifically named for. `buildBiquadDf2t` (already
  built) is the *transposed* DF-II, a third distinct topology again —
  all three, for matching coefficients, are cross-checked to produce
  the identical `H(z)` despite realizing it with different numbers and
  arrangements of delays, gains, and adders.
- **`buildCombFilter` sets a single `delay` block's own `k` param
  directly to the comb's delay length, rather than chaining that many
  unit delays the way the FIR generators deliberately do.** Those FIR
  generators need one node per delay tap because each tap gets its own
  independent per-coefficient gain; a comb filter only ever reads the
  *one*, fully-delayed sample, so a single general `z^-k` delay (Mason
  already reads a delay's own `k` param as `z^-k`, unrelated to this
  checkpoint) is both simpler and the structurally honest realization
  — chaining unit delays here would just be a longer way to draw the
  same thing.
- **`buildCicFilter` builds a real, decimating CIC topology (integrator
  stages, an actual `downsampler`, comb stages) rather than quietly
  downgrading to a same-rate stand-in — but its tests only assert an
  end-to-end `H(z)` for `decimation: 1`.** `computeTransferFunction`
  treating a `downsampler` as unity gain is a scope cut this project
  made back in Phase 4/8, not a new one; asserting a combined `H(z)`
  across a *real* rate change here would mean testing something Mason
  doesn't actually attempt to get right, so a `decimation > 1`
  structure is verified the way it honestly can be (loop-free, validly
  wired) instead of papering over the gap with a numerically-lucky-
  looking but physically meaningless assertion.
- **A real naming-shadow bug, caught by `analyze --fatal-infos` before
  any test ran.** `buildCombFilter`'s own `gain` parameter (the most
  natural name for what it is) shadowed the top-level `gain`
  `StencilDefinition` this same file already imports from
  `primitives.dart` for every other generator — `gain.instantiate(...)`
  inside that one function silently resolved to the *parameter*
  instead, which the analyzer caught immediately as "the method
  'instantiate' isn't defined for the type 'num'" rather than letting
  it become a runtime surprise. Fixed by renaming the parameter to
  `gainCoefficient`, not by prefixing the whole file's `primitives.dart`
  import (which every other generator in the file already relies on
  staying unprefixed).
- **`buildLatticeLadderFilter`'s tests derive its expected `H(z)` fresh
  by hand for `p`=1 and `p`=2, rather than encoding a remembered
  Gray-Markel numerator-coefficient formula.** The relationship
  between a lattice-ladder's own ladder coefficients and the resulting
  numerator polynomial is one of the less commonly-restated results in
  DSP texts, and getting it wrong from memory — then "verifying" it
  against a test that encodes the *same* wrong memory — would look
  identical to getting it right, right up until the wiring reused
  elsewhere disagreed. Substituting `buildAllPoleLattice`'s own
  already-independently-verified per-stage `F_m/X` relationships
  directly into `Y = Σ c_m·F_m` and simplifying by hand for small `p`
  produces a formula this project can actually trust — the same
  standard this project has applied to every hand-derived expected
  value so far (the biquad DF2T's textbook `H(z)`, the FIR lattice's
  own closed forms, ...), just harder to skip here since no textbook
  formula was sitting nearby to (mis)quote instead.
- **Dart's null-aware map-literal syntax checks the *value* side with
  `key: ?value`, not the key side with `?key: value`.** `?key: value`
  (which `lineShape`'s new `dashArray` param tried first) omits the
  entry only if the *key* is null — meaningless for a `const SdQName`
  key that's never null, and the analyzer says so directly ("the map
  entry key can't be null"). `key: ?value` is the one that omits the
  entry when `value` is null, which is what a nullable trailing
  parameter like `dashArray` actually needs. Easy to get backwards
  since `if (value != null) key: value` (the older, always-correct
  form still used elsewhere in this same function for `markerEnd`)
  reads left-to-right in condition-then-key order, while the new
  syntax's "?" binds to whichever side is actually nullable.
- **`computeRootLocus` skips an individually-degenerate swept value
  rather than treating it as a whole-sweep failure.** Every other
  "returns `null` on failure" function in this library has exactly one
  underlying `H(z)`, so any failure there really does mean "this whole
  analysis is impossible." A sweep is different: it evaluates `H(z)`
  at many different bound values of the same expression, and it's
  common (not a corner case) for *one* of those values to land exactly
  on a genuine, narrow degeneracy — a swept gain passing through
  exactly the one value that makes the numerator identically zero, for
  instance — while every other value is perfectly fine. Aborting the
  entire plot because of one such point would make root locus far less
  useful than it should be for a completely ordinary sweep range; the
  fix is the same "return `null` only when every value fails" rule a
  human reading the resulting plot would already expect.

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
