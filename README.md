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
  property inspector, all wired into the app shell (plain `Row` layout —
  the dockable ribbon shell is Phase 5). 25 + 7 more tests.

**Reprioritized next**: rather than strictly Phase 4→5→6→7 in order, Phase
4 (semantic graph) and Phase 8 (analysis: Tarjan loop detection, Mason's
gain formula) are being pulled forward, since together they're this
project's core "semantically aware, not merely a drawing tool" claim and
§13's acceptance criteria name them explicitly (a biquad DF2T validating
and Mason yielding the correct H(z)). Ribbon UI (5), ink/pen + native
plugins (6), the rest of the stencil library (7), LaTeX (9), export (10),
and polish (11) follow as time allows.

Not started: `packages/sd_graph`, `sd_ink`, `sd_input`, `sd_latex`,
`sd_export`, and `sd_commands` are empty scaffolds (a `library;` stub, no
`test/`), and `plugins/sd_pen_*` are placeholder READMEs — see each one
for what it'll need to become in Phase 6.

## Repo layout

Matches `sigmadraw-implementation-prompt.md` §2:

```
/apps/sigmadraw            # app shell (Flutter app, all 5 platform folders scaffolded)
/packages/sd_document      # ✅ Phase 1 — SVG DOM model, sd: namespace round-trip
/packages/sd_graph         # empty — Phase 4 (semantic graph: ports/edges/types/validation)
/packages/sd_stencils      # ✅ Phase 3 (core) — DSP symbol library, §5.1-5.3; §5.4-5.11 in Phase 7
/packages/sd_render        # ✅ Phase 2 — scene/display-list, CustomPainters, pan/zoom, selection
/packages/sd_ink           # empty — Phase 6 (stroke model, pressure curves)
/packages/sd_input         # empty — Phase 6 (pointer/pen pipeline)
/packages/sd_ui            # 🚧 Phase 3 (partial) — palette/tree/inspector; ribbon/docking in Phase 5
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

A repo was initialized here (`git init`) but nothing has been committed
yet — the working tree is staged and ready whenever you want the first
commit.
