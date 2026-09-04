# MISSION: Build "SigmaDraw" — a semantically-aware Digital Signal Processing diagramming editor in Flutter

You are implementing a production-grade, cross-platform DSP diagram editor. Read this entire brief before writing code. Work in phases (Section 12). After each phase, ensure the app builds and its tests pass on at least one desktop target before moving on.

## 0. NON-NEGOTIABLE CONSTRAINTS

1. Framework: Flutter (stable channel). Language: Dart (null-safe). Native plugin code only where required for pen input: C++ (Windows), Swift/Obj-C (macOS/iOS), Kotlin (Android), C/GTK (Linux).
2. Platforms: Desktop (Windows, macOS, Linux) + Android tablets + iPadOS. All features degrade gracefully where a platform lacks a capability.
3. Native document format = PLAIN SVG. The `.svg` file IS the document; it must render correctly in any standard SVG viewer (browser, Inkscape, Illustrator, librsvg/Cairo, LaTeX \includesvg). All semantic/graph data lives in a PRIVATE XML NAMESPACE so other viewers ignore it but our app round-trips it losslessly. Follow Inkscape's plain-SVG + private-namespace approach exactly.
4. Semantically aware: maintain a real signal-flow graph — typed ports, directed connectivity, validation, analysis (rate propagation, algebraic-loop detection, Mason's gain formula). It is NOT merely a drawing tool.
5. UI: a WPF/Microsoft-Office-style RIBBON (tabs, groups, large/small buttons, galleries, contextual tabs, dialog launchers, progressive collapse). Build a ribbon-STYLE UI; do not pixel-copy Microsoft Office chrome (licensing).
6. Do NOT rasterize the canvas. Render vector content with custom painters. Do NOT depend on `<foreignObject>` for portability. Do NOT block the UI isolate on export/LaTeX/routing.

## 1. FIRST STEP — MINE THE REFERENCE SOURCE TREES

Before designing, read these repos already on disk. Extract ARCHITECTURE and translate it idiomatically into Dart/Flutter. Do NOT transliterate C++ line-by-line. Produce `docs/inkscape-notes.md` and `docs/xournalpp-notes.md` capturing what you learned.

### ~/inkscape (SVG editing, document model, undo, snapping, connectors, export)

- `src/xml/` — Node/Repr XML tree + observer/event-vector. -> serializable node tree with change observers.
- `src/object/` (SPObject, SPItem) — object tree mirroring the XML tree. -> semantic object model observing the XML model (dual-tree design).
- `src/document-undo.cpp/.h` — transactions, event grouping ("maybe done"), undo stack of diffs. -> command/undo system with coalescing.
- `src/ui/knot/` (SPKnot), control-point selection, node-editing tool (`src/ui/tools/`). -> on-canvas transform/edit handles.
- `src/snap.cpp`, SnapManager, snappers, snap sources/targets/indicator. -> snapping subsystem.
- `src/display/` — CanvasItem tree, drawing items, tiled/buffered rendering. -> scene/display-list + dirty regions.
- `src/3rdparty/adaptagrams/libavoid/` + `src/ui/tools/connector-tool.cpp` — object-avoiding routing. Study `Avoid::Router`, `ConnRef`, `ConnType_Orthogonal`, `RouterFlag`. Three stages: (1) orthogonal visibility graph, (2) A* min-bend/min-length path, (3) centering + nudging (Wybrow/Marriott/Stuckey, Graph Drawing 2009). -> pure-Dart orthogonal connector router.
- `src/live_effects/` — parametric/live shapes (inspiration for live DSP blocks).
- `src/extension/internal/cairo-renderer.cpp` — vector PDF/PS export. -> SVG-DOM->PDF vector converter.
- CSS cascade/style handling. Pencil tool = Schneider curve fitting.

### ~/xournalpp (stylus/ink, canvas repaint, LaTeX tool)

- `src/core/gui/inputdevices/` — InputContext + StylusInputHandler/TouchInputHandler/MouseInputHandler/TouchDrawingInputHandler; per-device class override. -> InputRouter with device classification and defensive rules ("never trust the input system"; only draw on positive pressure; handle proximity defensively).
- `src/core/model/Stroke.*` — Stroke + Point(pressure). -> ink stroke model.
- Pressure inference for pressureless devices (speed-based atan sigmoid: `inverseSpeed = dt/(distance+0.01)`; `pressure = pi/2 + atan(inverseSpeed*3.14 - 1.3)`) -> fallback.
- `src/core/control/tools/EraseHandler.cpp` — standard/whiteout/delete-stroke erasers.
- `src/core/control/latex/` — external LaTeX invocation + embedding. -> desktop LaTeX pipeline.
- `src/core/view/` XojPageView/repaint-region logic. -> dirty-region invalidation.

## 2. PROJECT / MODULE LAYOUT (melos monorepo)

```
/apps/sigmadraw            # app shell (main, DI wiring, platform runners)
/packages/sd_document      # SVG DOM model, XML (de)serialization, private-namespace round-trip
/packages/sd_graph         # signal-flow graph: ports, edges, types, rates, validation, analysis
/packages/sd_stencils      # DSP symbol library (geometry, ports, params, defaults, semantics)
/packages/sd_render        # scene/display-list, CustomPainters, spatial index, hit-testing
/packages/sd_ink           # stroke model, pressure->width, stabilizers, outline generation
/packages/sd_input         # pointer/pen pipeline + platform channels; palm rejection; prediction
/packages/sd_ui            # ribbon, panels, element tree, inspector, palette, status bar
/packages/sd_latex         # math rendering (pure-Dart) + desktop TeX pipeline + caching
/packages/sd_export        # SVG writer, PDF/vector, PNG, EPS/PS, TikZ emitter, printing
/packages/sd_commands      # command pattern, undo/redo, transactions, history
/plugins/sd_pen_windows    # C++ WinTab + WM_POINTER
/plugins/sd_pen_macos      # Swift NSEvent tablet
/plugins/sd_pen_linux      # C GTK/GDK/libinput
/plugins/sd_pen_android    # Kotlin MotionEvent + MotionPredictor
/plugins/sd_pen_ios        # Swift UIPencilInteraction/coalesced/predicted
```

State management: plain document model via ChangeNotifier/ValueListenable + Riverpod for DI/scoping. Document is the single source of truth; feed a Listenable to `CustomPainter.repaint` (never rebuild the canvas widget per event). Heavy work (SVG parse, PDF export, LaTeX, routing, spatial reindex) runs in isolates (`Isolate.run`/`compute`).

## 3. DOCUMENT MODEL & SVG SERIALIZATION

- In-memory document tree = SINGLE SOURCE OF TRUTH. Node: element type, attributes map, children, style, transform, typed `semantic` payload.
- Serialize via the `xml` package. On load, PRESERVE ALL unknown foreign attributes/elements so third-party edits round-trip.
- Private namespace: declare `xmlns:sd="https://sigmadraw.app/ns/dsp/1.0"` (URI is an identifier, not a live URL).
- Dual representation per DSP block (mirror Inkscape live shapes): emit standard SVG geometry (`<g>` with paths/text/`<use>`) that renders everywhere, PLUS `sd:` attributes carrying semantics:
  - `sd:type` (adder, gain, delay, upsampler, fft, biquad-df2t, ...), `sd:id`, `sd:label`, `sd:params` (JSON), `sd:ports` (JSON list of `{id,dir,dtype,vlen,rate,x,y,angle}`).
  - Edges: `sd:edge` with `sd:from="blockId:portId"`, `sd:to="blockId:portId"`, `sd:route` (orthogonal|polyline|curved), `sd:signalLabel`.
  - Ink strokes: `sd:stroke` with `sd:pressure` (encoded per-point widths); visible geometry is a FILLED OUTLINE `<path>` (see §6), never a variable-width stroke.
  - Document-level: `sd:schema`, `sd:sampleRate`, `sd:defaultDtype`; layers via `inkscape:groupmode="layer"` compatibility + `sd:layer`.
- Reusable symbols in `<defs><symbol>`; instances via `<use>`. Arrowheads via `<marker>`. Use `vector-effect="non-scaling-stroke"` where wire width must be zoom-independent.
- Two save modes: native save keeps `sd:`; Export Plain SVG strips `sd:`/editor-only markup (like Inkscape "Plain SVG").
- SVG round-trip equality (incl. foreign content) is a first-class acceptance test.

## 4. SEMANTIC GRAPH MODEL (sd_graph)

- Port: `{id, name, direction(in/out), dtype (real|complex|int|short|byte|bit + vector-of + matrix), vlen (default 1), sampleRate (rational/symbolic), wordLength (optional Qm.n), position, arity}`. Model after GNU Radio (dtype, vlen, domain=stream|message, optional).
- Block: typed instance with parameter schema, port list, hierarchical/subsystem support (bridge ports to inner graph), `directFeedthrough` flag (true unless it contains a delay/state that breaks the loop).
- Edge: directed port->port; validate dtype compatibility (define real->complex widening rules), rate compatibility, vlen match.
- Validation rules (Problems panel, with severity): unconnected required port, dangling edge, type mismatch, vlen mismatch, sample-rate mismatch, delay-free (algebraic) loop, unsupported arity.
- Analysis:
  - Rate propagation: from sources, xL at upsamplers, /M at downsamplers; flag inconsistencies.
  - Algebraic-loop detection: build directed graph, run Tarjan's SCC; an SCC is an algebraic loop iff a cycle exists where no edge path has a delay AND all blocks have direct feedthrough. Auto-fix "insert z^-1". (A valid diagram has no feedback loop that doesn't pass through a delay.)
  - Transfer function via Mason's gain formula: `H = (sum_k P_k*Delta_k)/Delta`; `Delta = 1 - sum(loop gains) + sum(non-touching loop-pair products) - sum(triples)...`; `Delta_k` = Delta with loops touching path k removed. Enumerate forward paths + loops; branch gains from block params (gain value, z^-1, ...). Display symbolic/rational H(z).
  - Netlist export: GNU-Radio-style YAML/JSON (blocks, params, typed connections) + optional Graphviz DOT.
  - Pole-zero generation: from H(z), factor num/den -> z-plane plot (unit circle, x poles, o zeros) as a first-class insertable object.

## 5. DSP STENCIL LIBRARY (sd_stencils) — IMPLEMENT ALL

Base metrics from tikz-dsp (scale to a base cell, keep aspect ratios): operator circle diameter 4 units; square block 8 units; filter block width 14 units; node radius 1 unit; wire width 0.25, block outline 0.3; operator-label spacing 2. Each stencil defines: id, category, SVG geometry generator, ports (id/dir/dtype/vlen/position/angle), parameter schema, default label(s), semantic mapping, directFeedthrough flag. Arrowheads via markers.

**5.1 Primitives/SFG:** adder/summing junction (per-arm +/- signs; also quadrant/cross summer), subtractor, multiplier/gain triangle (label k), gain block variants, filled pickoff node (dspnodefull) + open node (dspnodeopen), directed edge + arrowhead, signal branch label (x[n], y[n], subscripts), constant/source, sink/output.

**5.2 Delay & shift:** unit delay z^-1, general z^-k (param k, feedthrough=false), continuous e^-sT, tapped-delay-line macro, shift register/register.

**5.3 Multirate & sampling:** upsampler ^M (rate xL, insert M-1 zeros), downsampler/decimator vM (rate /M), rational rate converter macro (^L->filter->vM), ideal sampler/switch, ZOH, first-order hold, anti-aliasing/anti-imaging filters, polyphase notation, noble-identity variants.

**5.4 Quantization & conversion:** quantizer (staircase), ADC, DAC, dither injection, saturation/limiter, rounding/truncation.

**5.5 Filter structures (composite/expandable templates):** FIR direct/transposed-direct/lattice/cascade/parallel; IIR Direct Form I, II, Transposed DF II (encode df2T state eqns), cascade of biquads/SOS, parallel, coupled/normalized lattice, state-space (A,B,C,D); wave digital; allpass; comb; CIC/Hogenauer (integrator+comb, params N/R/M). Each instantiates as a subsystem with correct internal adders/gains/delays and typed ports; must satisfy the no-delay-free-loop rule.

**5.6 Transforms:** FFT/IFFT/DFT (param N); radix-2 butterfly DIT and DIF (2 in/2 out, twiddle W_N^k, -1 on lower branch; DIT twiddle before, DIF after), bit-reversal, DCT/DWT, QMF/analysis/synthesis filter banks, wavelet decomposition tree macro.

**5.7 Comms/modulation:** mixer (circle x)+LO, NCO/DDS, phase shifter, 90-degree hybrid, I/Q mod & demod, matched filter, correlator, integrate-and-dump, PLL (phase detector, loop filter, VCO, divider), Costas loop, AGC, equalizer, interleaver/deinterleaver, encoder/decoder, mapper/demapper, RRC pulse shaper, channel, AWGN source, constellation object.

**5.8 Adaptive/statistical:** LMS/RLS block with error input + dashed coefficient-update path, estimator blocks, correlator.

**5.9 Control overlap:** plant, controller, feedback path, error summing junction (negative sign), H(z)/H(s)/G(s) boxes, integrator 1/s, differentiator s, state-space block, observer/Kalman.

**5.10 Hardware:** MAC, accumulator, register, mux/demux, ROM/coefficient memory, address generator, pipeline register markers, systolic-array cell, Qm.n word-length wire annotations.

**5.11 Analysis plots (first-class objects):** pole-zero (z-plane), magnitude, phase, group delay, impulse/step stem, spectrogram, constellation, eye diagram, Bode, Nyquist, root locus. Each has data + rendered vector geometry, editable and exportable.

Ship a searchable, categorized stencil palette mirroring 5.1-5.11 with drag-to-canvas and custom-symbol creation/reuse.

## 6. INK PIPELINE (sd_ink)

- Stroke = ordered Points `{x, y, pressure, tilt, timestamp}`.
- Pressure->width via user-editable transfer curve (default min 20%, max 135% of nominal, per Xournal++); optional velocity-based width modulation; pressure inference fallback (speed->atan sigmoid) for pressureless input.
- Stabilizers (selectable): moving average, exponential smoothing, Kalman, Krita "pulled string"/rope, Catmull-Rom/cubic-Bezier fitting; RDP simplification; Schneider curve-fit for pencil-to-path.
- Variable-width -> SVG: convert the variable-width centerline into a FILLED OUTLINE `<path>` (offset polygon each side). Store per-point widths in `sd:` for re-editing.
- Erasers: standard (width-based), whiteout, delete-stroke.
- In-progress stroke drawn into a lightweight OVERLAY layer/Picture, committed to the scene on pen-up. Never re-render the whole scene per point.

## 7. INPUT / PEN PIPELINE (sd_input) + NATIVE PLUGINS

Use `Listener` (not GestureDetector) for inking to bypass the gesture arena. Read `PointerEvent.kind`, `pressure`, `tilt`, `orientation`, `distance`, `buttons` (kPrimaryStylusButton/kSecondaryStylusButton), `radius`. Use coalesced/history points where available.

Device classification & palm rejection: classify each pointer (pen/eraser-tip/touch/mouse). While a stylus is in proximity/down, route touch to pan/zoom only. Defensive rules (Xournal++): never trust the input system; only ink on positive pressure; handle proximity/enter/leave without trusting their coordinates.

Each native plugin exposes a uniform Dart stream `PenSample{x, y, pressure0..1, tiltX, tiltY, twist, buttons, inverted, inProximity, timestamp}` via EventChannel; a MethodChannel for capability query/config:

- **Windows (C++):** PRIMARY = rely on Flutter's native WM_POINTER stylus (pressure+rotation reach PointerEvent; requires Wacom "Use Windows Ink"=ON). Verify your Flutter version delivers it; else implement WM_POINTER yourself: `EnableMouseInPointer(TRUE)`; handle WM_POINTERDOWN/UPDATE/UP; `GetPointerType`->PT_PEN; `GetPointerPenInfo`->POINTER_PEN_INFO (pressure 0-1024 -> /1024; rotation 0-359; tiltX/tiltY -90..90; gate each by `penMask & PEN_MASK_*`; PEN_FLAG_INVERTED/ERASER). SECONDARY = WinTab (tilt/twist/buttons/eraser AND Ink-OFF users): load Wintab32.dll; `WTInfo(WTI_DEFSYSCTX,...)`->LOGCONTEXT (`lcOptions |= CXO_MESSAGES`, `lcPktData = PACKETDATA`, don't grab system cursor); `WTOpen(hwnd,&lc,TRUE)`; hook FlutterView HWND WndProc via `registrar->RegisterTopLevelWindowProcDelegate`; on WT_PACKET call `WTPacket`->PACKET, read `pkNormalPressure` (normalize by WTInfo max), `pkOrientation` (orAzimuth/orAltitude/orTwist), `pkButtons`, `pkCursor` (eraser); `WTClose` on teardown. Let the user choose Ink vs WinTab.
- **macOS (Swift):** NO native Flutter support — tap NSEvent. Local monitor / override responder methods for `NSEventTypeTabletPoint`/`Proximity` AND mouse events with `subtype == .tabletPoint`. Read `pressure` (0-1), `tilt` (NSPoint -1..+1), `rotation` (deg), `tangentialPressure`, `buttonMask` (NSPenTipMask/NSPenLowerSideMask/NSPenUpperSideMask). Stream via EventChannel. (Reference engine POC on flutter/flutter#146387.)
- **Linux (C/GTK):** GDK device+axis handling; libinput tablet-tool; X11 XInput2 valuators vs Wayland tablet_v2 (pressure/kinds not in desktop embedder by default, #63209).
- **Android (Kotlin):** full MotionEvent — pressure, `getAxisValue(AXIS_TILT)`, AXIS_ORIENTATION, AXIS_DISTANCE, S Pen BUTTON_STYLUS_PRIMARY/SECONDARY, batched `getHistorical*`. Integrate androidx.input MotionPredictor; optional low-latency GLFrontBufferRenderer.
- **iOS (Swift):** `UITouch.force`/`maximumPossibleForce`, `altitudeAngle`, `azimuthAngle(in:)`, `coalescedTouches` + `predictedTouches` for latency, estimated-property backfill; `UIPencilInteraction` (double-tap iOS 12.1+, squeeze on Pencil Pro), hover. Consider flutter_apple_pencil (interactions) and pencil_kit (evaluate; may conflict with custom canvas).

Fallback when data unavailable: fall back to mouse/touch with pressure inference; disable pressure-dependent UI gracefully; surface detected capabilities in a "Pen status" area. NEVER hard-fail if a platform lacks tilt or pressure.

Latency: predicted+coalesced points; overlay for in-progress stroke; feed a Listenable to `CustomPainter.repaint`; RepaintBoundary around the ink overlay; meet §13 budgets.

## 8. RENDERING (sd_render)

- Explicit SCENE/DISPLAY LIST from the document; each element caches a retained Picture/geometry. Viewport culling by bounding box. Spatial index: R-tree or quadtree for hit-testing + culling.
- CustomPainter(s) drawing to Canvas; layers: static scene (RepaintBoundary) + selection/handles overlay + in-progress ink overlay + connectors overlay. Dirty-region invalidation (Inkscape tiled repaint / Xournal++ repaint-region).
- Hit-testing: bounding-box prefilter via spatial index, then precise `Path.contains` / stroke-outline test.
- Infinite canvas: matrix transform (pan/zoom), zoom-to-cursor, fit-to-content. Configurable grid (dot/line).
- Text via TextPainter. Dark mode = dark chrome + LIGHT canvas by default (toggle).

## 9. CONNECTORS, SNAPPING, EDITING

- Connector routing: pure-Dart orthogonal + polyline router modeled on libavoid's 3 stages (orthogonal visibility graph -> A* min-bend/min-length -> centering/nudging). Curved-corner option. Reroute on block move. Connectors attach to typed PORTS (port snap).
- Snapping: grid, object, port/anchor, alignment/smart guides with snap indicators (SnapManager pattern).
- Selection: single, marquee, lasso; group/ungroup; z-order; align/distribute.
- Transform handles: move/scale/rotate/flip (SPKnot-style control points).
- Layers; copy/paste with SVG-on-clipboard interchange.

## 10. UI (sd_ui) — RIBBON + PANELS

Base on fluent_ui (CommandBar, CommandBarButton, CommandBarCard, CommandBarItemDisplayMode, CommandBarOverflowBehavior.dynamicOverflow, compactBreakpointWidth, TreeView, flyouts); extend for ribbon tabs/groups/galleries/contextual tabs. Complement with MenuBar/MenuAnchor, window_manager, docking (multi_split_view/docking). Ribbon STYLE only — do not copy Office chrome.

Ribbon tabs (each group has a label; some have dialog launchers):

- **Home:** Clipboard, Undo/Redo, Selection tools (select/marquee/lasso/node-edit), Arrange (align/distribute/group/z-order), Zoom.
- **Insert:** DSP Symbols gallery (5.1-5.11, in-ribbon + searchable flyout), Connector (orthogonal/polyline/curved), Text/Label, LaTeX (equation editor launcher), Analysis Plot, Image.
- **Draw (contextual):** Pen/Pencil/Highlighter/Eraser, Pen thickness, Pressure-curve editor (dialog), Stabilizer, Color, Pen-button mapping.
- **Diagram/Semantics:** Set sample rate, Port types, Validate, Rate propagation, Detect algebraic loops (+auto-fix), Compute transfer function (Mason), Generate pole-zero, Netlist export.
- **Layout:** Grid/snap toggles, guides, layers, page setup.
- **View:** Zoom presets, fit, panels, dark mode, rulers.
- **Export:** Export SVG (native/plain), Export PDF, Print, PNG@DPI, EPS/PS, TikZ code.
- **Contextual tabs:** "Block Tools" (block selected), "Ink Tools" (ink selected), "Connector Tools" (wire selected).
- Progressive collapse via dynamicOverflow; Quick Access Toolbar; keytips/keyboard access.

Panels (dockable/resizable):

- **Element Tree:** hierarchical TreeView; each node shows metadata — type icon, `sd:label`, human-readable `sd:type` (e.g. "Unit Delay z^-1"), port summary, validation badge. Selection syncs with canvas.
- **Inspector/Properties (property grid):** parameters (typed editors), port table (dtype/vlen/rate), style, transform, semantic fields.
- **Stencil Palette:** searchable, categorized; drag-to-canvas; custom-symbol creation/reuse.
- **Problems panel:** validation results with jump-to-element.
- **Status bar:** cursor coords, zoom, sample rate, pen status/capabilities, selection count.

Tablet/touch adaptation: larger targets, collapsible ribbon, radial/pie quick-tool menu, two-finger pan/zoom while pen draws.

Keyboard: Shortcuts/Actions/Intent; standard set (Ctrl/Cmd+Z/Y/C/V/X/A/S, Del, arrows nudge, +/- zoom, space-pan, G group) + tool letters.

## 11. LaTeX, EXPORT, PRINTING

- **LaTeX (sd_latex):** on-screen/tablet = flutter_math_fork (KaTeX subset; document unsupported commands). Desktop with TeX = run pdflatex/xelatex (standalone class) -> `dvisvgm --no-fonts` -> inline glyph OUTLINE paths; embed into the diagram SVG; cache by hash of source; run in isolate. Store original LaTeX source in `sd:latex` (textext-style editable). Fallback without TeX = pure-Dart renderer; optionally investigate WASM TeX (tectonic/SwiftLaTeX) as experimental. Label helpers: gain coeff on triangle, H(z) in box, x[n]/y[n] on edges, z^-1 in delay box, subscripts.
- **Export (sd_export):** SVG writer (clean/minimal, coordinate precision/rounding, stable IDs, namespace handling; native keeps `sd:`, plain strips). PDF = convert SVG DOM DIRECTLY to pdf-package VECTOR ops (paths/transforms/text-as-outline or embedded fonts); do NOT rasterize; multi-page/page-setup/margins; use `printing` for platform print dialog + share. PNG @ arbitrary DPI. EPS/PS. TikZ export: emit tikz-dsp-style source (map each stencil to its tikz-dsp node style, ports->coordinates, edges->draws).

## 12. PHASED PLAN (each phase builds, runs, is tested)

- **Phase 0 Scaffolding:** melos monorepo, app shell, CI, lints, empty packages, `docs/*-notes.md` from mining ~/inkscape & ~/xournalpp.
- **Phase 1 Document + SVG round-trip:** model, xml (de)serialize, private namespace, preserve foreign content, native vs plain save. Golden round-trip tests.
- **Phase 2 Rendering + canvas:** scene/display-list, CustomPainters, pan/zoom/grid, spatial index, hit-testing, selection/handles.
- **Phase 3 Stencils (core) + placement:** primitives (5.1-5.3), palette, drag-place, inspector, element tree with metadata.
- **Phase 4 Semantic graph:** ports/edges/types, connectors with port snap, validation + Problems panel.
- **Phase 5 Ribbon UI:** tabs/groups/contextual tabs, panels, shortcuts, status bar.
- **Phase 6 Ink + pen** (Android/iOS first, then desktop plugins): ink pipeline, classification/palm rejection, native plugins, pressure/tilt/buttons, thickness, prediction, low-latency overlay.
- **Phase 7 Full stencil set:** 5.4-5.11 incl. filter templates, transforms, comms, control, hardware, analysis-plot objects.
- **Phase 8 Analysis:** rate propagation, Tarjan algebraic-loop detection + auto-fix, Mason transfer function, netlist export, pole-zero generation.
- **Phase 9 LaTeX:** pure-Dart + desktop dvisvgm pipeline + caching + editable source.
- **Phase 10 Export/print:** SVG(plain/native), vector PDF, PNG@DPI, EPS/PS, TikZ export, print dialogs.
- **Phase 11 Polish:** autosave/crash recovery, templates, dark mode, i18n, accessibility, performance tuning, tablet UX.

## 13. TESTING, PERFORMANCE BUDGETS, ACCEPTANCE

- **Unit tests:** graph model (types/rates/validation), Tarjan loop detection, Mason formula (verify against known textbook examples), SVG round-trip (parse->serialize->parse equality incl. foreign content).
- **Golden tests:** stencil rendering, full-diagram rendering, PDF/SVG export snapshots.
- **Integration tests:** place/connect/validate/export flows; simulated pen input.
- **Performance budgets:** perceived ink latency <= ~1 frame with prediction; hold 60fps (<=16ms/frame; 120fps/<=8ms on ProMotion where possible) with >=2,000 elements on screen and >=10,000 in document via culling + retained pictures; SVG parse/export and LaTeX/PDF off the UI isolate.
- **Acceptance:** (1) a native .svg opens correctly in a browser AND Inkscape; (2) reopening in SigmaDraw restores full semantics; (3) a biquad DF2T template validates with no algebraic loop and Mason yields the correct H(z); (4) pen pressure varies stroke width on at least Android/iOS and one desktop path; (5) TikZ export compiles.

## 14. CODING STANDARDS, DEPENDENCIES, FALLBACKS

- Effective-Dart lints, dart format, package-by-feature, immutable models where practical, no business logic in widgets.
- Dependencies (verify latest on pub.dev at build):
  - `xml` — SVG DOM (required; do NOT use a render-only SVG lib for the editable model).
  - `fluent_ui` — ribbon/CommandBar/TreeView base. Fallback: hand-rolled ribbon widgets.
  - `pdf` + `printing` — export/print. Fallback: custom PDF vector writer if `pdf` can't emit needed paths faithfully.
  - `flutter_math_fork` — on-screen math. Desktop truth = external TeX + dvisvgm.
  - `riverpod` (DI/state); `window_manager`/`bitsdojo_window` (desktop windowing); `multi_split_view`/`docking` (panels); `flutter_fancy_tree_view` or fluent_ui TreeView; `file_selector`/`file_picker` (file IO).
  - `jovial_svg` — ONLY for read-only thumbnail previews if ever needed; NOT the editable canvas (ignores XML namespaces; lacks `<pattern>`/non-scaling-stroke).
  - Pen: `flutter_apple_pencil`, `pencil_kit` (iOS) — evaluate; otherwise own plugins.
- When a package proves inadequate: wrap it behind an interface from day one; if it blocks a hard requirement (namespace round-trip, vector PDF, pen data), replace it with a custom implementation rather than compromising the requirement. Document the decision.

## 15. EXPLICITLY DO NOT

- Do NOT rasterize the editable canvas or export raster-in-PDF when vector is possible.
- Do NOT rely on `<foreignObject>` for portable output.
- Do NOT block the UI isolate on SVG parse, PDF export, LaTeX compile, or routing.
- Do NOT use a render-only SVG package as the document model.
- Do NOT drop unknown/foreign SVG content on load/save.
- Do NOT allow delay-free feedback loops to pass validation silently.
- Do NOT transliterate Inkscape/Xournal++ C++ into Dart — translate the architecture.
- Do NOT pixel-copy Microsoft Office ribbon chrome (licensing) — build a ribbon-style UI.
- Do NOT re-render the whole scene per pen point — use overlay + dirty regions.
