# Inkscape architecture notes for a Flutter/Dart rewrite

Source studied: `~/inkscape` (C++). Purpose: extract the *architectural concepts*
behind each Inkscape subsystem and design idiomatic Dart/Flutter equivalents for
`packages/sd_document`, `packages/sd_render`, `packages/sd_commands`, and the
connector router used from `packages/sd_ui`. This is not a porting guide — no
C++ is transliterated. Each section states what the C++ actually does (with
file/class/function citations) and then proposes a from-scratch Dart design.

## Contents

1. [XML/Repr tree (`src/xml/`)](#1-xmlrepr-tree)
2. [Object tree / dual-tree design (`src/object/`)](#2-object-tree--dual-tree-design)
3. [Undo/transaction system (`document-undo.cpp`)](#3-undotransaction-system)
4. [Knot handles + node tool (`src/ui/knot/`, `src/ui/tools/`, `src/ui/tool/`)](#4-knot-handles--node-editing-tool)
5. [Snapping (`src/snap.cpp` + snappers)](#5-snapping)
6. [Display tree / canvas rendering (`src/display/`)](#6-display-tree--canvas-rendering)
7. [Orthogonal connector routing (libavoid)](#7-orthogonal-connector-routing-libavoid)
8. [Live Path Effects (`src/live_effects/`)](#8-live-path-effects-lpe)
9. [Cairo vector renderer (`src/extension/internal/cairo-renderer.cpp`)](#9-cairo-vector-renderer)
10. [CSS cascade + Schneider curve fitting](#10-css-cascade--schneider-curve-fitting)

---

## 1. XML/Repr tree

### 1a. The C++ architecture, precisely

Files: `src/xml/node.h` (interface), `src/xml/simple-node.h/.cpp` (the one
concrete implementation), `element/text/comment/pi-node.h` (thin leaves),
`src/xml/simple-document.h/.cpp`, `src/xml/node-observer.h`,
`src/xml/composite-node-observer.h/.cpp`, `src/xml/helper-observer.h/.cpp`,
`src/xml/event.h/.cpp`, `src/xml/log-builder.h/.cpp`, `src/xml/repr.cpp`,
`src/xml/repr-io.cpp`, `src/gc-anchored.h/.cpp`, `src/inkgc/gc-managed.h`.

**One concrete implementation behind an abstract interface.** `Inkscape::XML::
Node` is abstract; `SimpleNode` is the *only* concrete storage/mutation
implementation, and `ElementNode`/`TextNode`/`CommentNode`/`PINode` are thin
leaves that just fix the node's `type()`. **Attributes**: a flat
`AttributeVector` of `{GQuark key; ptr_shared value}` — keys interned via
GLib's string-interning `GQuark`, values copied once into shared/GC storage
(`ptr_shared`) so multiple attributes can cheaply alias one backing buffer;
lookup is a linear scan (fine — SVG elements have few attributes). **Children**:
an *intrusive doubly-linked list* (`_first_child/_last_child/_next/_prev`
fields directly on `SimpleNode`, not a separate container), with a **lazily
recomputed position cache** (`_cached_position`, invalidated on any non-append
mutation, recomputed O(n) once then O(1) until next invalidation) — appending
a child is specially fast-pathed to avoid ever invalidating the cache.

**Memory: a hybrid tracing-GC + manual-refcount scheme that a Dart port
simply doesn't need.** Nodes live in a Boehm conservative tracing GC heap
(`GC::Managed<>`). Because `SPObject` (§2) is a *plain* heap object (`new`),
outside that GC heap, its raw `Node*` field can't by itself keep a node
alive — so `SPObject::invoke_build` explicitly calls `GC::anchor(repr)` (a
"phantom root" trick: allocate a tiny separately-tracked struct holding the
node's base address, so the conservative GC's mark phase finds it and keeps
the node reachable) and `releaseReferences()` calls `GC::release(repr)` to
balance it. **This entire mechanism collapses to nothing in Dart** — a
single real tracing GC and ordinary object references already give you
everything `GC::anchor`/`release` exists to simulate.

**Observer pattern**: `NodeObserver` has exactly six callbacks — none
actually `enforced-pure` despite the intent (`notifyChildAdded/Removed`,
`notifyChildOrderChanged`, `notifyContentChanged`, `notifyAttributeChanged`,
`notifyElementNameChanged`) — each carrying old+new values (or `nullptr` for
"first in order"/"no previous value"), enough to invert or replay any change
(feeding directly into §3's undo log). `CompositeNodeObserver` fans out to a
list of observers with careful reentrancy handling (an `_iterating` depth
counter; observers added/removed mid-dispatch go into a `_pending`
side-list merged in once the outermost dispatch finishes, rather than
corrupting the live iteration). **The clever part**: every node holds *two*
composites — `_observers` (direct) and `_subtree_observers` — and on every
reparent, a child's `_subtree_observers` composite is (re-)registered **as a
member observer of its new parent's** `_subtree_observers` composite. This
builds a **chain of composites mirroring the live tree topology**, so
"watch this whole subtree" doesn't require registering on every descendant
individually or walking down on every future insert — an event just bubbles
up through however many ancestor composites happen to have real listeners,
automatically staying correct as nodes move around. Every mutator calls the
document's logger **first** (§3's undo capture — a privileged, always-present
listener reached via a raw back-pointer, not through this fan-out at all),
**then** the regular `_observers` fan-out.

**Document/transaction primitive**: `SimpleDocument` plays three roles at
once (it *is* a `Node`, *is* the `Document` API, *is* the `NodeObserver`
returned by its own `logger()`). Its `beginTransaction`/`commit`/
`commitUndoable`/`rollback` are a **rollback-oriented** primitive — no
upfront snapshot, just "start recording, then either discard the recording,
hand it to the caller, or immediately replay it inverted to revert" — but in
practice Inkscape's real undo system (§3) always uses `commitUndoable` (hand
the log to an external stack) and never `rollback()` directly.

**Serialization is asymmetric on purpose**: libxml2 is used only to *parse*
(`repr-io.cpp`, with careful BOM/encoding sniffing, gzip transparent
handling for `.svgz`, legacy-namespace repair passes run once after
loading). **Writing is entirely hand-rolled** — Inkscape never uses
libxml2's writer. Worth copying two specific decisions: (1) **namespace
declarations are never persisted as tree state** — they're computed fresh
at save time by scanning the whole tree for which prefixes are actually in
use and synthesizing `xmlns:*` attributes on the fly, so a Dart writer
should do the same rather than tracking `xmlns` as ambient always-present
node state; (2) whitespace-only text nodes are dropped on load unless
`xml:space="preserve"` is in scope, and elements with mixed text+element
content are serialized "tight" (no injected pretty-print whitespace) to
avoid corrupting literal text content — both are real-world SVG
round-trip-fidelity details, not incidental.

### 1b. Dart translation proposal

Model the tree as a small sealed hierarchy, since Dart's `sealed class` +
pattern matching is the idiomatic replacement for C++'s
abstract-interface-plus-`type()`-enum:

```dart
sealed class XmlNode {
  XmlElement? parent;
}
final class XmlElement extends XmlNode {
  String tag;                        // e.g. "svg:rect" — keep namespace prefix
                                      // inline in the tag string; resolve
                                      // full URIs only at parse/serialize time
  final LinkedHashMap<String, String> attributes;  // insertion-ordered —
                                      // matches SVG's expectation that
                                      // attribute order is preserved on
                                      // round-trip; O(1) avg lookup beats
                                      // C++'s linear scan for free
  final List<XmlNode> children;      // see note below on why NOT an
                                      // intrusive linked list here
}
final class XmlText extends XmlNode { String content; bool isCData; }
final class XmlComment extends XmlNode { String content; }
final class XmlProcessingInstruction extends XmlNode { String target, content; }
```

- **Don't replicate the intrusive doubly-linked list for the base document
  tree.** It existed in C++ to avoid allocating a separate container object
  per node and to make splice/reorder O(1) without a vector's shift cost —
  real concerns in a hand-rolled C++ tree, not in Dart, where a plain
  `List<XmlNode>` is cheap, cache-friendlier for the common
  "iterate all children" case, and index-based access/insertion is fine at
  SVG-document sizes. **Do** keep an intrusive-list-shaped model specifically
  for the interactive node/path-editing structures in §4, where genuinely
  hot splice/reverse operations recur — that's a different, higher-level
  data structure (`EditablePath`'s node list), not this base tree.
- **No GC/refcount layer at all** — Dart references are enough; this is a
  place where the port is simply *less code* than the original, not a
  translation exercise.
- **Change notification: one document-level synchronous stream, not a
  per-node composite-observer chain.** Dart's `StreamController(sync: true)`
  already gives you ordered, synchronous, multi-subscriber delivery with
  none of `CompositeNodeObserver`'s active/pending reentrancy bookkeeping —
  emit one `XmlChangeEvent` (a sealed class mirroring the six callback
  shapes: `ChildAdded`/`ChildRemoved`/`OrderChanged`/`ContentChanged`/
  `AttributeChanged`/`TagChanged`, each carrying the node + old/new values)
  per mutation from a single `Stream<XmlChangeEvent> get changes` on the
  document. "Watch this subtree" becomes a plain `.where((e) =>
  e.node.isDescendantOfOrSelf(root))` filter over that one stream — no
  per-node rewiring on reparent needed at all, which is strictly simpler
  than the C++ chain-of-composites trick while providing the same
  capability.
  - **Exception, deliberately**: the undo-capture hook (§3) should be a
    **plain, synchronous method call from each mutator** (`document
    ._recordChange(...)`), not routed through the generic stream — mirror
    Inkscape's own choice to special-case it as a privileged first listener
    reached directly, rather than as just another stream subscriber, since
    undo capture must never be skippable/reorderable relative to the
    mutation it's recording.
- **Serialization**: write a small dedicated encoder (do not lean on
  `package:xml`'s writer if you need exact SVG round-trip fidelity) that (a)
  computes `xmlns:*` declarations by scanning actual tag/attribute prefixes
  in use at write time, never storing them as node state; (b) preserves the
  same whitespace/CDATA/mixed-content rules on both read and write. Parsing
  can reasonably use `package:xml`'s parser (or `package:xml_events` for a
  streaming parse of very large files) and then convert its tree into the
  `XmlNode` model above.
- **Fresh-design question worth resolving deliberately**: does `sd_document`
  need a *separate* XML-node tree at all, distinct from the semantic object
  tree in §2? Inkscape needs the split for two reasons: (a) a
  pre-existing generic XML/Repr layer predating the semantic layer, used for
  many things including undo diffing and a raw XML-editor UI; (b) **not
  every node has a semantic counterpart** (comments, unrecognized
  namespaces), and keeping them separate lets that foreign content
  round-trip losslessly even though nothing in the app understands it.
  Recommendation: **keep the two-tree split**, but only for reason (b) —
  lossless preservation of comments/foreign-namespace content/things an XML
  source-view editor touched — since that's valuable and hard to retrofit
  later. Reason (a) mostly disappears once undo is redesigned as explicit
  `Command` objects (§3) rather than XML-level diffing, so the semantic tree
  in `sd_document` doesn't need to *also* serve as an undo substrate the way
  `SPObject`/`Node` do — it can be a simpler, more directly serialization-
  and-rendering-focused layer.

---

## 2. Object tree / dual-tree design

### 2a. The C++ architecture, precisely

Files: `src/object/sp-object.h/.cpp`, `src/object/sp-item.h/.cpp`,
`src/object/sp-item-group.h/.cpp`, `src/object/sp-factory.h/.cpp`,
`src/object/tags.h`, `src/document.h/.cpp`.

**Construction — a factory keyed by tag name, plus a separate, compile-time
type-tag hierarchy for fast RTTI-free casting.** `SPFactory::createObject(id)`
looks up a ~130-entry `unordered_map<string, SPObject*(*)()>` keyed by either
the element's qualified tag (`"svg:rect"`) or, for legacy discriminator
cases, a `sodipodi:type` attribute value (so e.g. `<path sodipodi:type="star">`
constructs a different class than a plain `<path>`). **Separately**,
`tags.h` declares the whole class hierarchy once via an X-macro that expands
into a contiguous-range `enum class SPObjectTag` (every class gets
`[first,last]` spanning itself and descendants) plus a `tag()` virtual
returning that range's start — giving O(1) `is<T>`/`cast<T>` checks (a
range comparison) with no `dynamic_cast` anywhere in the hot path.

**`invoke_build(document, repr, cloned)` — the precise construction
sequence** matters and is worth reproducing exactly: (1) store
document/repr pointers, `GC::anchor(repr)` if not cloned; (2) call the
**virtual** `build(document, repr)` — whose **base-class implementation**
recursively walks the repr's children **directly** (factory + construct +
attach + recurse), i.e. **the initial subtree is built by a direct top-down
walk, not by synthesizing observer notifications**; (3) if not cloned, bind
into the document's id/repr lookup tables, generating a unique `id` if
missing; (4) **only now**, as the *last* step, `repr->addObserver(*this)` —
so an object starts listening for *future* live changes only after its own
(and its whole initial subtree's) construction has already completed. Later,
a **live** child-add re-uses much of the same logic (factory + construct +
attach) but is reached via the `notifyChildAdded` → `child_added()` virtual
dispatch instead. `release()` is the precise inverse: remove the repr
observer **first** (so the object's own teardown mutations don't loop back
through it), then run subclass cleanup **most-derived first**, calling
`Base::release()` last, with generic child-detachment happening only at the
final `SPObject::release()`.

**Sync direction 1 (XML → Object)**: all six `NodeObserver` callbacks are
declared `final` on `SPObject` — subclasses cannot intercept the raw
transport, only the **semantic** virtuals each callback dispatches to after
doing fixed bookkeeping: attribute change → `readAttr` (string → `SPAttr`
enum via a lookup) → virtual **`set(SPAttr, value)`**; child added/removed →
virtual **`child_added`/`remove_child`**; reorder → virtual
**`order_changed`**; content → virtual **`read_content`**; element rename →
virtual **`tag_name_changed`**, whose *default* implementation is just a
warning — **there is no generic support for an XML rename live-morphing an
object into a different subclass**, a real rough edge worth deliberately
fixing (or deliberately not supporting, but by explicit design) rather than
inheriting by accident.

**Sync direction 2 (Object → XML) — the repr is authoritative; SPObject
fields are a re-derived cache, with one deliberate hot-path exception.** The
class doc-comment states this outright: object-layer mutations that don't go
through the repr do *not* propagate back to it, "important for undo,
animations, and other features." Two write paths exist:
- **Immediate**: `object->setAttribute(...)` writes straight to the repr,
  which **synchronously re-enters the observer chain including notifying
  the object itself** — `set()` fires again, re-deriving in-memory state
  from the value *just written*. No infinite loop occurs because `set()`
  only ever mutates C++ fields, never writes back.
- **Deferred/hot-path**: a small, deliberate set of frequently-mutated
  fields (`SPItem::transform`, `SPObject::style`) are mutated **directly in
  memory only**, paired with `requestDisplayUpdate(...)` for live re-render,
  and are **not** written to the repr until an explicit `updateRepr()` flush
  — e.g. once at drag-end. **This is the exact same two-stage pattern as
  §4's knot write-back** (mutate live model cheaply every frame; serialize +
  commit once on release) — it appears independently in at least two places
  in the C++ codebase, which is a strong signal it should be **one shared,
  named mechanism** in the Dart port rather than two ad hoc implementations.

`write()` (the function that performs the flush) has **two modes** selected
by its arguments, both worth keeping as one method: an in-place flush onto
the *existing* live repr, or — when given `repr=null` plus a "build" flag —
clone this object's current state into a **brand-new** repr subtree,
optionally in an entirely different `Document` (used for object duplication
and for "Save As Plain SVG" style export to a temporary document). It's
genuinely the same operation ("materialize my current state as a repr
subtree") parameterized by target.

**Update/modified propagation — two independent bit-fields, two full-tree
passes, with an important order asymmetry.** `uflags` (pending *update*
work, e.g. recompute geometry) and `mflags` (pending *modified-signal* work,
e.g. notify listeners) are entirely separate, each bubbling to the parent
**only the first time** since the last flush (an "already propagated" guard
avoids redundant walks up an already-dirty chain) and, from the root,
scheduling the document to run a pass. `SPDocument` schedules **two GLib
idle handlers at different priorities** — one for the update pass, one
(lower priority, runs after) for connector-router rerouting —
`ensureUpToDate()` is the synchronous equivalent: loop the update pass (up
to 32 times, since settling one object can dirty another), run one router
pass, then repeat once more for anything the router's own changes dirtied.
**The two passes walk in opposite orders**: the *update* pass is top-down
context-push but **post-order self-finalization** — `SPGroup::update()`
updates every child *before* running its own tail logic, specifically so a
group's bounding box (computed from children) is correct by the time it's
needed. The *modified*-signal pass is the reverse — **pre-order**, self
before children. This asymmetry exists for a concrete correctness reason
(bbox computation) and getting it backwards would silently produce stale
bounding boxes — reproduce both orders deliberately as two distinct
tree-walk functions, don't conflate them into one "generic tree walk."

**`SPItem` adds**: transform composition (accumulate `item->transform` while
walking up to a common ancestor, special-casing the root's viewBox matrix);
**three distinct bounding-box types** — approximate (legacy), geometric
(bare path), and visual (stroke + markers + filter-region expansion,
intersected with clip/mask bounds) — with the visual one cached and
unconditionally invalidated at the top of every `update()`; and the
`invoke_show()`/`invoke_hide()` hook that creates/destroys this item's
`DrawingItem` view(s) in the display tree (§6).

**Orphan collection** (a *document-semantic* concept, unrelated to the
XML-tree's own GC): `hrefcount`/`_total_hrefcount` track incoming
`xlink:href`-style references; when an object's count (own + all
descendants') hits zero **and** it belongs to an explicit allowlist of
"delete when unreferenced" types (paint servers, style elements, LPE
objects, pages, ...), it's queued for deletion — this is how an unused
gradient/pattern/filter in `<defs>` gets cleaned up automatically, and is
deliberately *not* applied to most object types.

**The graph, precisely**: `SPDocument` owns both `rdoc` (the `XML::Document`)
and `root` (the root `SPObject`). Downward links are owned (repr's intrusive
child list; SPObject's own intrusive children list with manual
ref/unref-to-delete-at-zero semantics). Upward/cross links (`parent`,
`document`, `repr`) are raw, non-owning. **Coupling is one-directional**: an
`SPObject` holds and observes its `Node`, but `Node` has zero awareness that
any semantic layer exists — the only reverse lookup is a side-table
(`SPDocument::reprdef: map<Node*, SPObject*>`), not a field on `Node`
itself. Not every `Node` has an `SPObject` (comments, foreign namespaces map
to a null factory entry and are simply skipped).

### 2b. Dart translation proposal

```dart
abstract class SdObject {
  SdDocument document;
  XmlElement node;                 // the backing §1 node — always present,
                                    // never null, set once at construction
  SdObject? parent;
  final List<SdObject> children = [];

  // Transport layer — NOT overridable; dispatches to the semantic hooks below.
  // Registered once, as the LAST step of construction (mirrors invoke_build's
  // ordering exactly — see the constructor-sequence note).
  void _onXmlChange(XmlChangeEvent e) { switch (e) {
    case AttributeChanged(:final key, :final newValue): setAttribute(key, newValue);
    case ChildAdded(:final child, :final after): _handleChildAdded(child, after);
    // ... etc, one arm per XmlChangeEvent variant
  }}

  // Semantic hooks — subclasses override these, never _onXmlChange itself.
  void setAttribute(String key, String? value) {}      // ~ set(SPAttr,value)
  void onChildAdded(SdObject child, SdObject? after) {}
  void onChildRemoved(SdObject child) {}
  void onReordered(SdObject child, SdObject? newAfter) {}

  Element toXmlElement({SdDocument? targetDocument, bool cloneBuild = false});
                                    // one method, two purposes — flush-in-place
                                    // when targetDocument==null, clone-to-new-doc
                                    // otherwise (mirrors write()'s dual mode)
}
```

- **Skip the compile-time tag-range trick.** It existed to avoid
  `dynamic_cast` overhead in C++; Dart's `is`/`as` on a sealed-class-free
  ordinary class hierarchy is already fast, and Dart 3 sealed classes +
  pattern matching (`switch (obj) { SdRect r => ..., SdGroup g => ... }`)
  are the idiomatic replacement where exhaustive dispatch is wanted. Use a
  plain `Map<String, SdObject Function(SdDocument, XmlElement)>` factory
  keyed by tag name (plus a `sodipodi:type`-equivalent lookup only if a
  legacy-style discriminator is genuinely needed) — no X-macro required.
- **Reproduce the construction *sequencing* exactly, even though the
  mechanics (GC anchor, observer registration) simplify.** Build the initial
  subtree by directly walking the `XmlElement`'s children and constructing
  through the factory (not by replaying change events); bind into the
  document's id lookup map; only *then* subscribe to that node's future
  changes (via the document-wide stream from §1, filtered to this node) —
  getting this order backwards causes an object to see its own initial
  children as if they were live "child added" events, corrupting whatever
  bookkeeping those handlers do (e.g. display-tree insertion in §6, which
  legitimately differs between "initial build" and "live add").
- **One shared `LiveField<T>` convention for the "mutate live, flush later"
  pattern**, used for both `transform` and computed style — since this
  exact two-stage idea recurs in the C++ at both the object layer and the
  interactive-handle layer (§4), give it one name and one implementation in
  Dart rather than two independent ad hoc versions:
  ```dart
  class LiveField<T> {
    T value;                         // read/write freely, cheap, per-frame safe
    bool _dirty = false;
    void set(T v) { value = v; _dirty = true; onLiveChange?.call(); }
    void flush(void Function(T) writeToNode) {
      if (_dirty) { writeToNode(value); _dirty = false; }
    }
    void Function()? onLiveChange;   // hook a repaint request here
  }
  ```
  A shape's `transform`/`style` fields become `LiveField<Matrix4>`/
  `LiveField<SdStyle>`; interactive tools call `.set()` every frame and
  `.flush()` (wrapped in one `Command`, §3) once at gesture end.
- **Two explicit, separately-implemented tree-walk functions for update vs.
  notify, with their documented opposite orders preserved deliberately**:
  `updateLayout(SdObject root)` (post-order: recurse into children first,
  recompute this node's bbox/derived geometry after) and
  `notifyChanged(SdObject root, ChangeFlags flags)` (pre-order: notify this
  node's listeners, then recurse). Schedule both from `SdDocument` via
  `scheduleMicrotask`/`SchedulerBinding.addPostFrameCallback` rather than
  GLib idle priorities — two ordered phases (layout, then anything derived
  like the connector router from §7) achieve the same effect without
  needing a priority-queue abstraction Dart doesn't have built in.
  Reproduce the "bubble dirty flag to parent only the first time" guard —
  it's a cheap, valuable optimization independent of the scheduling
  mechanism.
- **Bounding boxes**: keep the three-tier distinction
  (`approximateBounds`/`geometricBounds`/`visualBounds`) as real, named
  methods/getters on a geometry mixin shared by every shape-bearing
  `SdObject`, with `visualBounds` cached and invalidated exactly at the top
  of `updateLayout` for that node — downstream consumers (snapping §5 wants
  cheap bounds for pruning; rendering §6 wants accurate bounds for culling)
  should be steered toward the *correct* tier deliberately, not given one
  generic "bounds" getter that silently picks one.
- **Orphan/defs cleanup**: implement as a plain `int hrefCount` field
  incremented/decremented by whatever holds an `href`-style reference
  (gradient/pattern/filter/marker consumers), with a small allowlist of
  "auto-delete at zero" types — this is a document-semantic policy, not a
  memory-management necessity in Dart (the GC would reclaim an unreferenced
  Dart object regardless), so keep it purely for the *user-visible* behavior
  of not leaving orphaned defs entries in the saved file.

---

## 3. Undo/transaction system

### 3a. The C++ architecture, precisely

Files: `src/document-undo.h/.cpp` (the public API), `src/event.h`
(`Inkscape::Event`, one undo-stack entry), `src/xml/event.h/.cpp`
(`Inkscape::XML::Event` and subclasses, one primitive repr mutation),
`src/xml/log-builder.h/.cpp` (the accumulator), `src/xml/simple-document.h/.cpp`
(the transaction state machine), `src/xml/simple-node.cpp` (where every
mutation reports itself), `src/event-log.cpp` (Undo History dialog).

**Two distinct "Event" types matter here.** `Inkscape::XML::Event` (+
`EventAdd`/`EventDel`/`EventChgAttr`/`EventChgContent`/`EventChgOrder`/
`EventChgElementName`) is a **primitive**: one atomic repr mutation, GC-kept
alive, linked via `next` into a **newest-first** singly-linked chain (built by
prepending). `Inkscape::Event` is a **stack entry**: it wraps the head of one
such chain plus a `description`/`icon_name` for the History dialog.
`SPDocument::undo`/`redo` (`document.h:449-450`) are
`std::deque<Inkscape::Event*>` — deques of stack entries, each internally a
whole chain of primitives.

**Capture mechanism — simpler and more centralized than a generic observer
fan-out.** There is no document-wide `CompositeNodeObserver` doing the
capturing. Instead, every `SimpleNode` holds a raw back-pointer to its owning
`Document`, and every mutating primitive (`setAttributeImpl`, `setContent`,
`addChild`, `removeChild`, `changeOrder`, `setCodeUnsafe` — `simple-node.cpp`)
calls `_document->logger()->notifyXxx(...)` **directly and unconditionally**,
in addition to its own per-node observer fan-out. `SimpleDocument` *is* the
logger (`logger()` returns `this`) and owns a `LogBuilder`; its `notifyXxx`
overrides do exactly `if (_in_transaction) _log_builder.addChild(...)` etc.
— **outside a transaction, mutations are not captured at all**, not merely
discarded after capture. This "document as one privileged, always-reachable
logger, gated by a boolean" is a much simpler design than a pub/sub tree walk,
and is the pattern worth keeping.

**Public API** (`document-undo.h`): `done(doc, description, icon)`,
`maybeDone(doc, key, description, icon)`, `undo(doc)`, `redo(doc)`,
`cancel(doc)`, `clearUndo`/`clearRedo`, `setUndoSensitive`/`getUndoSensitive`,
and the RAII guard `ScopedInsensitive`.

**`maybeDone`'s exact coalescing rule** (`document-undo.cpp:156-227`, verified
directly): unconditionally, first, `clearRedo(doc)` — **any** commit attempt
wipes redo, even before it's known whether anything actually changed. Then
the pending log is captured (`sp_repr_commit_undoable`) and coalesced with any
previously-parked partial log; if the result is empty, return (no stack
push). Otherwise: merge into the **top** existing entry iff **all** of: (1)
`key != null`, (2) not expired, (3) `doc.actionkey` is non-empty, (4)
`doc.actionkey == key` (exact string equality, no fuzzy match), (5) the undo
deque is non-empty. Otherwise push a **new** entry. `done()` is just
`maybeDone(doc, null, ...)`, so a plain `done()` call can never coalesce.
**Expiry is a sliding idle timeout**, not a fixed group duration: a timestamp
+ `action_expires` (hard-coded back to **10.0 seconds** after every keyed
commit, regardless of any custom value) — so a gesture emitting sub-events
every &lt;10s coalesces indefinitely however long it runs, but a &gt;10s pause
starts a fresh entry even with the same key. `resetKey(doc)` clears only the
key (used e.g. on selection change) to force the next `maybeDone` to start
fresh regardless of timing.

**Replay is literal re-invocation of the same mutation primitives with
inverted arguments, not a snapshot restore.** Every `XML::Event` subclass
implements both `_undoOne(NodeObserver&)` and `_replayOne(NodeObserver&)`
(e.g. `EventAdd::_undoOne` calls `notifyChildRemoved`, `_replayOne` calls
`notifyChildAdded`; attribute/content/order/name events just swap old/new).
Both are dispatched into a `NodeObserver`-shaped sink (`LogPerformer`) whose
overrides call the *real* tree mutators (`addChild`, `setAttribute`, ...) —
undo is not different in kind from a normal edit, it's the same primitives
fed inverse data. Because the chain is stored **newest-first**, `undo`
(`sp_repr_undo_log`) simply walks head→tail calling `undoOne` — already
correct LIFO order, no reversal needed. `redo` (`sp_repr_replay_log`) must
flatten into a vector and iterate it tail→head (oldest→newest) calling
`replayOne`. Nodes referenced by events are the **actual live, GC-kept-alive
node instances** — undoing a delete reinserts the *same* object, not a
reconstruction, which is why identity-based associations (selection, etc.)
survive undo/redo for free.

**Compaction**: after every append, `optimizeOne()` fuses/cancels adjacent
redundant events on the same node/key — an add immediately followed by
removing the same node cancels to nothing; consecutive attribute changes on
the same key collapse into one (old=earliest, new=latest) — this is what
keeps a long coalesced drag from growing one event per mouse-move tick.

**Re-entrancy / the `sensitive` flag**: `undo()`/`redo()` force
`doc.sensitive = false` for their entire duration (so any `done()` call
triggered as a side effect of the replay silently no-ops) and run the
document's normal update pass (`ensureUpToDate`) inside its own
transaction; if that pass itself produces incidental mutations, they are
**merged directly into an existing stack entry** (never become a new,
separate undo step) — or discarded if there's nowhere to put them.
`setUndoSensitive(false)` closes the ambient transaction entirely (so nothing
is captured until re-enabled) but preserves whatever had already accumulated
in `doc.partial`, folded into the next real commit. `ScopedInsensitive` is
the RAII save/restore wrapper used for "run this derived-recompute without
polluting undo."

**Soft size cap, not a hard one**: eviction (from the front/oldest) only runs
on **non-coalescing** commits (`if (!key) { while (limited && size >
maxSize) evictOldest(); }`, default max 200, preference-gated) — coalescing
sub-steps never trigger a trim mid-gesture. Redo is never independently
trimmed (it only grows by undo() moving already-bounded entries over).

**No real nested/compound transactions.** The entire "grouping" the History
dialog shows is a cosmetic view built by `EventLog` grouping *consecutive*
top-level pushes that share the same `icon_name` — unrelated to the
`actionkey` coalescing criterion — purely for the tree-view display; jumping
to a grouped row still costs one `undo()`/`redo()` call per member, looped by
the dialog. **The only mechanism that actually reduces step-count is the key
coalescing rule above.**

**Refresh after undo/redo** is not a bespoke signal — it falls out of the
same `SPDocument::modified_signal` that any ordinary edit's `ensureUpToDate`
pass emits, since `undo()`/`redo()` call that exact same update pass. A
separate `UndoStackObserver` channel (`notifyUndoCommitEvent/UndoEvent/
RedoEvent/UndoExpired/ClearUndoEvent/ClearRedoEvent`) exists specifically to
drive the History dialog and the Undo/Redo menu items' enabled state.

### 3b. Dart translation proposal

**Key design fork, worth making explicitly (and differently from Inkscape):**
Inkscape's undo is a **low-level XML-diff/event-sourcing log**, generic
across every mutation because it was retrofitted onto an existing C++ tree
with hundreds of call sites. A from-scratch Dart rewrite building
`packages/sd_commands` should instead make the undo stack out of **explicit,
semantic `Command` objects** — the package name itself signals this design,
and it has real advantages over a diff log: a command can define
*domain-meaningful* merge behavior (`TranslateCommand.tryMergeWith(other) =>
TranslateCommand(delta: a.delta + b.delta)`) instead of relying on generic
per-attribute diff collapsing, and it keeps "what the user did" legible for
a history UI without needing a separate cosmetic grouping layer. Keep the
lower-level XML-node observer/event mechanism (§1) for what it's actually
for — syncing the object tree and driving redraw/serialization — and build
the undo stack as a **separate, higher-level layer** on top of the document's
public mutation API, not by diffing raw XML.

```dart
abstract class Command {
  String get label;                 // for a history UI
  String? get mergeKey;             // null = never coalesces (== Inkscape's `done()`)
  void apply(SdDocument doc);       // perform / redo
  void unapply(SdDocument doc);     // undo (each Command knows its own inverse —
                                     // e.g. a move command just re-applies the negative delta;
                                     // no generic diff-inversion machinery needed)
  Command? tryMergeInto(Command previous) => null;  // domain-specific coalescing hook
}
```

- **`UndoManager`** (a `ChangeNotifier`, or a Riverpod `Notifier` if the rest
  of the app standardizes on Riverpod — pick once and use consistently across
  §2/§3/§7) owns `List<Command> _undo`, `List<Command> _redo`, and replicates
  Inkscape's *policy* exactly, since that policy is well-tuned from real
  usage even though the representation changes:
  - `done(Command cmd)`: `cmd.apply(doc); _redo.clear(); _undo.add(cmd);
    _trimIfOverLimit(); notifyListeners();` — **always** clears redo first,
    mirroring "any commit attempt invalidates redo."
  - `maybeDone(Command cmd)`: same, but if `cmd.mergeKey != null &&
    cmd.mergeKey == _lastKey && !_expired() && _undo.isNotEmpty`, try
    `cmd.tryMergeInto(_undo.last)`; on a non-null result, `apply` the delta
    and **replace** `_undo.last` with the merged command instead of pushing a
    new one. Reset a sliding `_lastCommitTime`/10-second window on every
    matching merge, exactly as Inkscape does — this single rule is what makes
    a multi-tick drag gesture undo as one step.
  - `resetMergeKey()`: equivalent of `resetKey` — call on selection change or
    tool switch to force the next `maybeDone` to start fresh.
  - `undo()`/`redo()`: set an internal `_replaying = true` flag for the
    duration (Dart's `try`/`finally` makes this trivially safe, no RAII
    boilerplate needed — cleaner than the C++ original), call
    `cmd.unapply(doc)`/`cmd.apply(doc)`, run the document's own derived-state
    recompute pass (the Dart analogue of `ensureUpToDate` — recomputing
    LPE-derived geometry, style cascade, etc., see §2/§8), and — deliberately,
    unlike Inkscape's undocumented asymmetry — merge any incidental mutations
    from that recompute into the **same entry that was just moved**, for both
    directions, for predictability.
  - Soft cap: evict the oldest `_undo` entry only from `done()` (never from a
    successful `maybeDone` merge), with a configurable max (default ~200).
  - Suppression: `T withoutUndo<T>(T Function() body)` — a plain
    try/finally toggling a `_suppressed` flag that `apply`/mutation calls
    check, the direct equivalent of `ScopedInsensitive`, used when e.g.
    recomputing LPE stacks or reloading a file.
  - Expose `ValueListenable<bool> get canUndo` / `canRedo` for toolbar button
    state (a `ValueNotifier<bool>` updated alongside the stacks, or derived
    via a Riverpod `Provider` from the stacks' lengths) — this is exactly
    what Inkscape's `UndoStackObserver`→`enable_undo_actions` wiring does.
- **History-panel grouping, if built, must stay a presentation-layer
  projection** (e.g. group consecutive commands by `runtimeType` or an
  explicit `category` field) that never changes how many `undo()` calls reach
  a given point — copy Inkscape's discipline here exactly: the display
  grouping and the replay granularity are deliberately decoupled.
- **Concurrency**: keep the entire undo/command pipeline synchronous on the
  main isolate. Unlike rendering (§6) or routing (§7), this is small,
  inherently sequential, and needs to interleave tightly with UI/gesture
  state — there's no benefit and real complexity cost to moving it off-thread.
- **Interaction with §1/§2's XML observer system**: a `Command.apply()`
  should call the document's normal public mutators (`node.setAttribute(...)`,
  `object.transform = ...`), which already fire the XML-node
  change notifications that keep the object tree and display tree in sync
  (§1/§2/§6) — the undo layer never touches raw XML nodes directly, it only
  orchestrates *which* public mutations happen and in which order, keeping
  a clean separation: XML/object-tree sync is about *consistency*, the
  command stack is about *history*.

---

## 4. Knot handles + node-editing tool

### 4a. The C++ architecture, precisely

Two genuinely separate, non-inheriting handle hierarchies coexist — confirmed
explicitly by the source's own comments in both `src/ui/knot/README` and
`src/ui/tool/README` ("*there are classes with similar functionality based on
the [other] class*"). Both ultimately draw through the same primitive,
`Inkscape::CanvasItemCtrl` (§6), and both hook the same generic
`CanvasItem::connect_event()` dispatch — only the C++ object model differs.

**`SPKnot`** (`src/ui/knot/knot.h/.cpp`) — the older, **composition-based**
primitive used by shape tools. Never subclassed; an owner *has-a* `SPKnot*`
and reacts to its sigc++ signals: `moved_signal`, `grabbed_signal`,
`ungrabbed_signal`, `click_signal`, `doubleclicked_signal`, `mousedown_signal`,
`event_signal` (universal override), `request_signal` (veto/modify a proposed
move). Fields: `pos` (desktop coords), one owned `CanvasItemPtr<CanvasItemCtrl>`,
per-state shape/size/color/cursor, manual refcount. It registers itself
directly as its `CanvasItemCtrl`'s event handler (no intermediate tool-level
dispatch) and drives its own drag lifecycle (grab on press, `moved_signal` on
motion past tolerance, `ungrabbed_signal`/`click_signal` on release,
`DocumentUndo::undo()` directly on Escape-cancel). **`SPKnot` itself never
calls `DocumentUndo::done`/`maybeDone`** — committing is entirely the owner's
responsibility.

**`KnotHolder`/`KnotHolderEntity`** (`knot-holder.h/.cpp`,
`knot-holder-entity.h/.cpp`) — one `KnotHolder` per edited `SPItem`, holding a
list of `KnotHolderEntity*`, one per semantic handle (rect corner-radius,
star point-count, ellipse arc angles, ...). A concrete entity overrides
`knot_get()` (model → point), `knot_set(p, origin, state)` (point → model
mutation), and usually `knot_ungrabbed()`; `KnotHolder::create()` wires the
knot's signals to the entity's virtuals. **The write-back pattern is
two-stage**, and is the reusable idea here: (1) *during drag*, `knot_set`
mutates a **typed C++ property** on the object (`rect->rx = ...`) and calls
`requestDisplayUpdate` for a live re-render — **XML is not touched yet**; (2)
*on release*, `KnotHolder::knot_ungrabbed_handler` calls
`object->updateRepr()` (serializes the typed property into the XML attribute
via the object's `write()`) then `DocumentUndo::done(...)`. This "mutate live
model cheaply every frame, serialize + commit once on release" pattern
recurs everywhere in Inkscape's interactive editing and is worth preserving
exactly.

**`ControlPoint`** (`src/ui/tool/control-point.h/.cpp`) — the newer,
**inheritance-based** primitive used exclusively by the node/pen tool
infrastructure (`Node`, `Handle`, `CurveDragPoint`, `TransformHandle` and its
6 subclasses, `SelectableControlPoint`). Extended via protected virtual hooks
(`grabbed`/`dragged`/`ungrabbed`/`clicked`/`move`/`setPosition` — classic
Template Method), supports `transferGrab()` (handing an in-progress drag from
one point to another — used to "pull a handle out of" a cusp node), and
tracks a process-wide static `mouseovered_point`.

**`SelectableControlPoint`/`ControlPointSelection`** — multi-selection: a
flat `unordered_set<SelectableControlPoint*>` (deliberately type-erased above
`Node`), rubber-band via point-in-polygon winding test against an
`_all_points` pool, shift-click toggles membership, and an Alt-drag "sculpt"
mode applies a cosine-falloff-weighted delta to nearby unselected points via
finite-difference linearization. Exposes `signal_selection_changed`,
`signal_update` (repaint), `signal_commit(CommitEvent)` (the undo trigger).

**`Node`** (`src/ui/tool/node.h/.cpp`) — one path vertex: position (inherited
from `ControlPoint`), two `Handle` tangent points (`_front`/`_back`, each a
`ControlPoint` subtype with a `_degenerate` flag meaning "retracted, segment
is a straight line"), and a `NodeType` (`CUSP`/`SMOOTH`/`AUTO`/`SYMMETRIC`)
that a `Handle::move()` enforces live (rotating/mirroring the sibling handle
to stay collinear, auto-demoting to cusp when both handles retract). Paths
are **intrusive circular doubly-linked lists**: `NodeList` (one subpath,
O(1) splice/reverse/shift, wrap-around iteration for closed paths) inside a
`SubpathList = std::list<shared_ptr<NodeList>>` (the whole editable path).
This non-trivial choice (vs. a flat array) is deliberate: node-tool
operations (join, break, weld, reverse, insert) are fundamentally splice
operations and are cheap only with this structure.

**`PathManipulator`** owns one path's `SubpathList` plus a back-reference to
the `SPObject` being edited (which can be a plain `SPPath` **or** an
LPE parameter's path — the same editor edits both). Write-back chain,
confirmed by direct reading: `update()` rebuilds a `Geom::PathVector` by
walking every `Node` and calling `build_segment()` (emits a line or a cubic
depending on adjacent handle degeneracy) → `_setGeometry()` sets the live
in-memory curve (`path->setCurveBeforeLPE`/`setCurve` — **not yet XML**) →
`writeXML()` calls `_path->updateRepr()` (the same generic `SPObject`
serialization as KnotHolder's stage 2) plus writes the `sodipodi:nodetypes`
string, then commits via `DocumentUndo::done`/`maybeDone`.

**`MultiPathManipulator`** coordinates every currently-relevant shape at once
(selection + any clip/mask/LPE-param being edited simultaneously) via
`map<ShapeRecord, shared_ptr<PathManipulator>>`. Critically, **all
`PathManipulator`s share one `ControlPointSelection`**, which is *how*
cross-path node operations work — nodes from two different paths can sit in
the same selection set and be dragged together; genuinely cross-object ops
(join, weld) splice one path's `NodeList` into another's directly. Bulk
per-path operations are simple broadcasts (`invokeForAll`); all commit paths
converge on `_done()`/`_maybeDone()` → `writeXML()` on every manipulator +
one `DocumentUndo` call.

**`TransformHandleSet`** draws rotate/scale/skew handles around the
selection's bounding box. Its base class computes an **absolute** target
affine each frame from the handle's math (corner-scale, side-stretch,
rotate-with-angle-snap, skew), diffs it against the previous frame's affine
to get an **incremental** delta, and emits that delta via `signal_transform`
— which `ControlPointSelection::transform(Geom::Affine)` applies to every
selected node. This incremental-broadcast pattern (compute absolute, diff
against last frame, broadcast delta) is a clean way to let one drag gesture
apply consistently to an arbitrary, possibly-growing set of listeners without
each of them needing to track the gesture's start state themselves.

### 4b. Dart translation proposal

**Unify what history split apart.** Design one hierarchy from the start,
shaped like `ControlPoint`'s inheritance model rather than `SPKnot`'s signal
soup (Dart doesn't need the C++-era workaround that produced two systems):

```dart
abstract class CanvasHandle {
  Offset position;                     // in the coordinate space the owner defines
  bool get isDegenerate => false;      // e.g. a retracted bezier handle
  HandleVisual get visual;             // shape/size/color for painting — a small value type

  void onGrabbed(DragStartDetails d) {}
  Offset onDragged(Offset proposed, DragUpdateDetails d) => proposed; // return value lets a
                                        // handle veto/constrain (== SPKnot's request_signal)
  void onDragged_apply(Offset newPos) {}   // mutate the LIVE model only — cheap, per frame
  void onUngrabbed() {}                    // stage 2: serialize + commit undo (see below)
  void onClicked(TapDetails d) {}
}
```

- A single Flutter-side **`HandleLayer` widget** (a `CustomPainter` +
  `Listener`/`GestureDetector` over the canvas) owns a `List<CanvasHandle>`
  supplied by whichever tool is active, does hit-testing (nearest handle
  within a tolerance radius, exactly like Inkscape's pick), and drives the
  grab/drag/release lifecycle — this replaces both `CanvasItemCtrl`'s
  per-item Gtk event hookup and the tool-specific dispatch, with one shared
  implementation.
- **Preserve the two-stage write-back discipline exactly** — it's the single
  most important idea to carry over: `onDragged_apply()` mutates a plain Dart
  field on a view-model object and calls something like
  `document.notifyLiveChange(item)` (cheap, triggers only a repaint, no undo
  entry, no XML/JSON write); `onUngrabbed()` builds one `Command` (§3) from
  the drag's start→end delta and calls `undoManager.maybeDone(command)`.
  This keeps every drag interaction at 60fps (no serialization or undo-log
  work per frame) while still producing exactly one clean undo step per
  gesture.
- **Shape-specific handles** (rect radius, star points, ellipse arcs) become
  small `CanvasHandle` subclasses or — more idiomatically in Dart — a single
  `PropertyHandle` parameterized by a `get`/`set` pair of closures into the
  shape's typed model (`PropertyHandle(get: () => rect.rx, set: (v) =>
  rect.rx = v.clamp(0, rect.width/2))`), directly mirroring
  `KnotHolderEntity::knot_get`/`knot_set` without needing a subclass per
  shape property.
- **Node/path editing** gets its own richer model, kept distinct from the
  generic handle layer above (matching Inkscape's own separation, just without
  the historical accident of two unrelated base classes):
  ```dart
  class PathNode {
    Offset position;
    Offset frontHandle, backHandle;   // absolute or relative — pick one, document it
    NodeType type;                    // cusp/smooth/auto/symmetric
  }
  class EditablePath {                // ~ PathManipulator, minus the XML bit
    final List<List<PathNode>> subpaths;  // a plain growable list is fine in Dart —
                                           // no manual-memory reason to intrusive-link,
                                           // but DO keep splice/insert/reverse as first-class
                                           // O(1)-amortized methods on this class rather than
                                           // ad hoc List<> surgery at call sites, so join/weld/
                                           // break read as intent, not index arithmetic.
    Path toGeometry() => ...;             // build_segment equivalent: emit line or cubic
                                           // per adjacent-handle degeneracy
  }
  ```
  A `NodeSelectionController` (shared across every `EditablePath` currently
  being edited, exactly like the shared `ControlPointSelection`) holds the
  selected-node set and is what makes cross-path node drags and rubber-band
  selection work uniformly.
- **Transform handles**: implement the same "compute absolute target affine
  per frame, diff against last frame, broadcast the incremental `Matrix4`"
  pattern via a `ValueNotifier<Matrix4>` or a plain callback — it's a clean,
  representation-agnostic way to drive an arbitrary selection's transform
  from one gesture regardless of how many nodes are selected.
- **Snapping integration**: call into the snapping engine (§5) from
  `onDragged` before returning the (possibly adjusted) proposed position —
  same call site Inkscape uses (`KnotHolderEntity::snap_knot_position`,
  `TransformHandle` pulling selected/unselected point snap candidates on
  grab).
- **State management**: since handles are inherently interactive/ephemeral
  (they exist only while a tool is active and mutate fast), a plain
  `ChangeNotifier`-per-active-tool (or a Riverpod `NotifierProvider` scoped
  to "current tool state") is the right granularity — don't route
  per-frame drag deltas through the same provider that the document/undo
  system uses, to avoid triggering wide rebuilds 60 times a second; only the
  final committed `Command` should touch that layer.

---

## 5. Snapping

### 5a. The C++ architecture, precisely

Files: `src/snap.h/.cpp` (`SnapManager`), `src/snapper.h/.cpp` (base
contract), `src/{line,grid,guide,object,alignment,distribution}-snapper.*`,
`src/snap-candidate.h`, `src/snap-enums.h`, `src/snap-preferences.h/.cpp`,
`src/snapped-{point,line,curve}.*`, `src/display/control/snap-indicator.*`,
plus the throttle in `src/ui/tools/tool-base.cpp`.

**`SnapManager`** is the coordinator, holding the concrete snappers as value
members (`guide`, `object`, `alignment`, `distribution`; grid snappers live
one-per-`SPGrid` and are collected on demand). Lifecycle per gesture:
`setup(desktop, ...)` (resets internal "already searched" flags and the
ignore-list) → any number of query calls → `unSetup()`. Real query entry
points: `freeSnap`/`freeSnapReturnByRef` (2-DOF), `constrainedSnap` (1-DOF,
along a `Snapper::SnapConstraint` — a tagged union of line/direction/circle),
`multipleConstrainedSnaps` (pick the nearest of several candidate
constraints, e.g. angle-snap), `snapTransformed` (a whole **set** of points
under one selection transform at once — see the multi-point note below).

**Input/output value types**: `SnapCandidatePoint` (point, a `SnapSourceType`
enum tag, an index distinguishing "first point of a batch" from subsequent
ones, optional bbox/origin-vector extras) in; `SnappedPoint` (snapped
coordinate, distance, tolerance, `SnapTargetType` tag, `alwaysSnap`/
`fullyConstrained`/`atIntersection` flags, and — only for alignment/
distribution results — extra "second point/bbox" fields for indicator
drawing) out. **`SnapSourceType`/`SnapTargetType`** (`snap-enums.h`) are
large, exhaustively-enumerated closed sets (nodes cusp/smooth, bbox
corner/edge/midpoint, path intersection, grid/guide line & intersection,
page edge/margin/bleed corner & center, rotation center, text anchor/
baseline, alignment-* and distribution-* variants) — this taxonomy is itself
the most reusable artifact here, independent of the scoring mechanics.

**`Snapper` is a push-style visitor, not a pull-style candidate list**:
`freeSnap(IntermSnapResults& isr, SnapCandidatePoint, ...)` **appends** into
a shared mutable accumulator (`IntermSnapResults { points; grid_lines;
guide_lines; curves; }`) rather than returning anything — every enabled
snapper contributes into the same bucket for one query.

**Candidate gathering is brute-force, bbox-pruned, and rebuilt from scratch
per gesture — there is no persistent spatial index.** `ObjectSnapper`
recurses the whole `SPObject` tree once per `setup()` cycle (guarded so 4
different snappers sharing the same walk only pay for it once), bbox-pruning
first against the visible viewport, then against the drag point's tolerance
radius; hard safety caps exist (200 candidate items, paths over 500 nodes
skipped) as explicit, documented cost controls rather than an asymptotic
fix. Grid/guide snapping is closed-form (nearest multiple of spacing / a
fixed line list). Alignment ("smart guides") and distribution ("equal
spacing") snappers are the most algorithmically involved: alignment tests
whether the dragged point shares an X or Y coordinate with any other object's
bbox corner/midpoint within tolerance; distribution recursively grows a
chain of side-by-side objects with equal gaps and tests whether the current
drag would extend or fit that pattern.

**Winner selection is two-stage** (`SnapManager::findBestSnap`): reduce to
one best candidate *within* each geometry bucket (points/lines/curves,
plus pairwise line/curve intersections when unconstrained) by raw distance,
then reduce *across* buckets via `SnappedPoint::isOtherSnapBetter(other)` — a
single, fully-specified boolean comparator (not a per-type priority table):
an unsnapped candidate never beats a snapped one; `alwaysSnap` beats
tolerance-gated candidates and can never be beaten; a fully-constrained
(node/intersection-grade) match beats a merely-line-constrained one; exact
ties prefer a plain node over an intersection label, then smaller secondary
distance, then an unconstrained snap over a constrained one. **This one
function effectively *is* Inkscape's whole priority system** — there's no
separate static per-type weight table.

**Tolerances are five independent screen-pixel values** (grid/guide/object/
alignment/distribution), converted to document space by dividing by the
current zoom — so the effective catch radius shrinks as you zoom in, which
matches user expectation (a fixed number of *pixels*, not document units).
An `alwaysSnap` per-category boolean bypasses tolerance entirely.

**Performance is not solved inside the snapping engine at all — it's solved
at the input-event layer.** `ToolBase::snap_delay_handler` tracks pointer
velocity and, above a small jitter threshold, sets a global "postponed" flag
(every `SnapManager` entry point checks this and short-circuits) and arms a
one-shot debounce timer that replays the last motion event once the pointer
settles; a button-release always force-flushes immediately. So: full
recompute per settled query, but queries are rate-limited well before they
ever reach the (stateless, brute-force) snap engine.

### 5b. Dart translation proposal

The taxonomy (source/target type enums) and the winner-selection contract
are the two things worth porting almost verbatim; the *implementation* of
candidate-gathering is exactly the place to use better data structures than
Inkscape's brute-force walk, since Dart/Flutter has no legacy call sites to
preserve.

```dart
enum SnapSource { bboxCorner, bboxMidpoint, bboxEdgeMidpoint, nodeCusp,
    nodeSmooth, lineMidpoint, pathIntersection, rotationCenter, guide,
    gridPitch, /* ... */ }
enum SnapTarget { bboxCorner, bboxEdge, bboxEdgeMidpoint, nodeCusp,
    nodeSmooth, path, pathIntersection, gridLine, gridIntersection,
    guideLine, guideIntersection, pageEdge, rotationCenter,
    alignmentBboxCorner, distributionX, distributionY, /* ... */ }

class SnapCandidate {
  final Offset point; final SnapSource source; final int batchIndex;
  final Rect? targetBbox;
}
class SnapResult {
  final Offset point; final double distance, tolerance;
  final SnapTarget target; final bool alwaysSnap, fullyConstrained, atIntersection;
  final double? secondaryDistance;       // intersection tie-break
  final (Offset, Offset)? alignmentLine; // for indicator drawing
  bool get snapped => distance.isFinite;
}
```

- **`Snapper` contract as a pull function, not a push-into-accumulator visitor**
  — Dart's collection literals make "return a list, caller concatenates" just
  as cheap as mutating a shared buffer, and it's easier to test each snapper
  in isolation: `Iterable<SnapResult> query(SnapCandidate p, SnapContext ctx);`
  where `SnapContext` carries the ignore-list, tolerance-in-document-units
  (already zoom-divided), and a read-only view of the document.
- **Winner selection**: port `isOtherSnapBetter`'s boolean rule directly
  — it's already a precise, self-contained specification; reimplementing it
  as a `Comparator<SnapResult>` (or a `compareTo` on a small wrapper) used
  with `Iterable.reduce` gets the exact same behavior with far less code than
  the two-stage bucket dance, since Dart doesn't need C++'s
  by-geometry-type container split to stay efficient at this candidate
  count (dozens, not thousands, per query).
- **Candidate gathering — do better than brute force from day one**, since
  this is pure new code with no legacy constraint: maintain a persistent
  spatial index (an R-tree or even a simple grid-bucketed `Map<CellKey,
  List<ObjectId>>`) on the document's item bounding boxes, updated
  incrementally as `sd_document` mutates (§1/§2 already need to notify on
  geometry change — hook the index update there), so a query is a
  logarithmic-ish range lookup instead of a full tree walk. This is a place
  to *intentionally diverge* from Inkscape's implementation while keeping
  its taxonomy and scoring contract identical — the brute-force walk was
  workable in a mature C++ codebase's incremental-improvement history, not
  something to reproduce on purpose.
- **Throttling stays at the input layer**, exactly as Inkscape places it —
  don't build rate-limiting into the snap-query functions themselves. A
  `PointerVelocityDebouncer` utility (track last N pointer samples, compute
  speed, suppress/replay similar to `snap_delay_handler`) sits between the
  raw `Listener.onPointerMove` stream and the tool's call into the snap
  engine; a `pointerUp`/`onPanEnd` always flushes synchronously so a drag
  never ends on a stale, unsnapped position.
- **Indicator**: a single ephemeral overlay widget (part of the same
  `HandleLayer`/temporary-items layer discussed in §4/§6) driven by the
  latest `SnapResult`, with a `Map<SnapTarget, String>` label table mirroring
  Inkscape's `source2string`/`target2string` — fade out on a short timer or
  immediately on the next unsuccessful query, matching
  `remove_snaptarget()`'s "only one shown at a time" rule.
- **State/perf**: keep the whole snap-query pipeline synchronous on the main
  isolate (it must complete within a single frame to feel responsive during
  a drag, and candidate sets are small) — this is not an isolate candidate
  the way routing/rendering are; the win here comes from a better data
  structure, not from parallelism.

---

## 6. Display tree / canvas rendering

### 6a. The C++ architecture, precisely

Files: `src/display/drawing.h/.cpp`, `drawing-item.h/.cpp`,
`drawing-{group,shape,image,text}.*`, `nr-filter*.cpp`;
`src/display/control/canvas-item*.*`; `src/ui/widget/canvas.h/.cpp` +
`src/ui/widget/canvas/{stores,updaters,synchronizer,graphics,
cairographics,glgraphics}.*`; `src/desktop.cpp` (layer setup).

Three layers, cleanly separated by responsibility, verified directly:

**(1) `DrawingItem` tree** (`Inkscape::Drawing`) — a render-only tree
mirroring the `SPItem` tree one-to-one (created via `SPItem::invoke_show`),
kept in sync by **explicit setter calls from the SP layer** (`setTransform`,
`setStyle`, `DrawingShape::setPath`, ...) — there is no diffing, the object
layer pushes precise deltas. Subclasses (`DrawingGroup`/`Shape`/`Image`/
`Text`) override protected `_updateItem`/`_renderItem`/`_pickItem` hooks
while the public `update()`/`render()`/`pick()` on the base class do all the
shared bookkeeping — a clean template-method split that maps directly onto
Flutter's own `RenderObject` `performLayout()`/`paint()` shape. Each item
tracks **three distinct boxes**: `_bbox` (device-pixel, stroke included),
`_drawbox` (bbox enlarged by filter region, intersected by clip/mask —
*this* is the box used for culling and for the dirty rect sent to screen),
and `_item_bbox` (user-space, for `objectBoundingBox`-relative gradient/filter
math).

**Two independent, precisely-scoped invalidation signals** — this is the
single most important structural fact for the port:
- **Geometry invalidation** (`_markForUpdate`, bit-flag based, e.g.
  `STATE_BBOX`): clears state bits **up the parent chain only until an
  already-dirty ancestor**, so marking dirty is O(depth); the actual
  recompute (`update()`, called top-down later) **short-circuits instantly**
  on any subtree whose state bits are already clean or whose box doesn't
  intersect the update area — so a full-tree `update()` call only ever
  visits genuinely dirty/overlapping subtrees.
- **Repaint invalidation** (`_markForRendering`): computes the item's
  *current* `_drawbox` (before whatever change triggered this call),
  extends it through any ancestor filter's `area_enlarge`, busts ancestor
  render caches along the way, and emits a **precise pixel rectangle** via
  `Drawing::_redraw_area_signal`. Every mutator calls this immediately
  (dirtying the *old* box) and then `_markForUpdate` (so the next geometry
  pass recomputes the *new* box and calls `_markForRendering` again itself)
  — a deliberate two-box dance that correctly repaints both where a shape
  used to be and where it now is.
- `Drawing` exposes exactly these two signals —
  `connectDrawingUpdated` (relayout needed) and `connectRedrewArea(Rect)`
  (repaint exactly this rect) — **keep them separate all the way out to the
  widget layer**; conflating "needs layout" and "needs paint" into one
  invalidation is the single easiest mistake to make when porting this.

**Compositing** (`DrawingItem::render`): isolation (a temporary surface +
`cairo_push_group`/`pop`) is only paid for when SVG semantics actually
require it — `needs_intermediate_rendering = clip || mask || filter ||
opacity<1 || nonNormalBlend || isolate`; the overwhelmingly common plain
opaque shape renders straight to the destination with **zero** group
overhead. CSS blend modes map directly to Cairo/GPU compositing operators.

**A real, budgeted, score-ranked render cache — not "cache everything behind
a boundary."** Every cacheable `DrawingItem` computes a `_cacheScore()`
(roughly: on-screen pixel area × filter-complexity multiplier), and once per
dirty `update()` pass, `Drawing::_pickItemsForCaching()` sorts all candidates
above a threshold by score and **greedily** enables caching on the
highest-value ones until a global byte budget (user-configurable, ~64 MiB
default) is exhausted — a genuinely global, cross-document budget decision,
not a per-widget opt-in. The cache surface itself tracks its own dirty
sub-region as a real region (not just a boolean), and even survives a pure
integer-pixel pan (translate the clean region + reuse pixels) while dropping
entirely on rotation/non-integer zoom.

**(2) `CanvasItem` tree** — the *complete* on-screen scene graph, confirmed
to include both UI chrome (`CanvasItemCtrl` for handles, `CanvasItemGuideLine`,
`CanvasItemQuad` for rubber-bands, `CanvasItemGrid`) **and** the document
content, which appears as exactly **one node**, `CanvasItemDrawing`, wrapping
the entire `Drawing` tree from (1). That bridge class is a thin, direct
forward: its `_update`/`_render` just call `Drawing::update()`/`render()` and
take bounds from the Drawing root's `drawbox()` — and `Drawing`'s own two
signals from (1) are precisely what drive `CanvasItemDrawing`'s
`request_update()`/`redraw_area()` calls. So DrawingItem invalidation is
*upstream of and drives* CanvasItem invalidation for that one node — not a
competing parallel system. Chrome items implement the same
`request_update`/`_update`/`render` contract but with trivial, immediate-mode
Cairo drawing (no clip/mask/filter/cache machinery at all — chrome is simple
by construction). Z-order is a fixed, explicitly-documented named layer
stack, bottom to top (`src/desktop.cpp`): catchall, page-background, drawing,
page-foreground, grids, guides, sketch (temp-before-permanent), temp
(self-expiring, e.g. snap indicator), controls (handles — always topmost).

**(3) The tiled/buffered rendering pump** (`src/ui/widget/canvas.cpp` +
`canvas/*`) — genuinely multi-threaded, not a single idle callback doing
sequential work:
- **Stores**: a backing Cairo/GL surface sized to viewport + prerender
  margin, tracked with a real `Cairo::Region` (union of rects) of
  already-drawn content, not a single dirty rect. A `Decoupled` mode kicks
  in the instant the view's affine changes (any zoom/rotate/pan frame): the
  old store is snapshotted and kept on screen (GPU-warped to approximate the
  new view) while a fresh store re-renders at the new affine underneath it —
  instant visual feedback during a gesture, real content catching up in the
  background.
- **Updaters**: three pluggable incremental strategies over the same "clean
  region" abstraction — plain responsive (subtract/union immediately),
  full-redraw-aware (snapshot the clean region if new damage arrives
  mid-flight, don't retarget an in-progress pass), and a genuine
  frequency-graded multiscale updater (tiles near the last mouse position
  get refreshed every frame; farther/already-clean regions get refreshed
  only every 2nd/4th/8th... frame) — three orthogonal knobs (spatial
  priority by distance-from-mouse, temporal priority by scale/frequency,
  and a hard wall-clock time budget per redraw pass) combine rather than one
  mechanism doing everything.
- **Real parallelism**: dirty regions are coarsened into a handful of large
  rects, pushed onto a max-heap ordered by distance from the mouse, and
  farmed out across a **`boost::asio::thread_pool`** — each worker
  independently rasterizes its tile through the CanvasItem→Drawing→
  DrawingItem tree (software Cairo, always — GL is used only to composite
  already-rasterized tiles onto the screen, never to rasterize vector
  content itself) and reports back through a `Synchronizer` (a
  cross-thread-safe wake mechanism) once done or once a time budget expires,
  yielding back to the GTK main loop either way.
- A **separate**, smaller thread pool (`dispatch_pool`) exists purely to
  parallelize the inner pixel loops of expensive raster filter primitives
  (Gaussian blur, morphology) — composable with, but independent from, the
  tile-level thread pool.

### 6b. Dart translation proposal

Flutter already gives you a layered render tree with its own
layout/paint-invalidation split (`RenderObject.markNeedsLayout()` vs
`markNeedsPaint()`) and a `Canvas`/`Picture`/layer-tree compositor — so the
goal is not to reimplement Inkscape's whole pipeline, but to **map its
structure onto Flutter's equivalents deliberately**, rather than flattening
everything into one big `CustomPainter.paint()` that redraws the whole
document every frame (the single most common and costly mistake in a naive
port).

- **`packages/sd_render` should define its own `DrawingItem`-equivalent
  tree** (`SdRenderObject` with `SdGroup`/`SdShape`/`SdImage`/`SdText`
  subclasses) that mirrors the `sd_document` object tree, **separately** from
  the Flutter widget/render-object tree — this is the direct analogue of
  keeping `Drawing` distinct from `CanvasItem`. Each node holds its own
  cached geometric bbox and a "paint bbox" (bbox ∪ filter growth ∩
  clip/mask), computed lazily and invalidated by explicit setter calls from
  the document layer (§1/§2's change notifications), never by re-diffing.
- **Keep two distinct, separately-coalescable invalidation channels**,
  exactly mirroring `_markForUpdate` vs `_markForRendering`:
  - a `ValueNotifier<Set<NodeId>>` (or a plain `Set` + manual
    `notifyListeners()`) for "these nodes' geometry/bbox needs recomputing,"
    consumed by a layout pass that walks only the dirty subtrees (bail out
    early exactly like `if ((~_state & flags) == 0) return;` — a cheap
    per-node early-exit check, not a tree-wide dirty flag);
  - a **separate** stream/notifier of `Rect` (accumulated into a
    `Path`/region union, e.g. via `path_drawing`-style rect union or just a
    `List<Rect>` merged opportunistically) for "repaint exactly this pixel
    area," which is what actually drives Flutter's repaint boundaries.
- **Use `RepaintBoundary` + a budgeted, score-ranked caching decision, not
  "wrap everything in a boundary."** Compute a cache-worthiness score per
  subtree (on-screen area × filter/complexity multiplier, directly
  analogous to `_cacheScore()`) and only wrap the top-scoring subtrees (under
  a configurable budget) in `RepaintBoundary`/`RenderRepaintBoundary` —
  wrapping *every* group in a boundary wastes memory on GPU-backed layers for
  content that repaints as cheaply as it composites. Recompute this ranking
  whenever the visible set or the document changes significantly (e.g. once
  per zoom-settle), not every frame.
- **Composite (clip/mask/opacity/blend) only when required**, mirroring
  `needs_intermediate_rendering`: wrap a subtree in `Opacity`/`ClipPath`/
  `ColorFiltered`/a custom `Layer` only when its own properties actually
  demand it (opacity < 1, non-normal blend, clip, mask, filter present) —
  Flutter's own `Opacity` widget already documents this exact same cost
  tradeoff (it warns against wrapping cheap content), so this isn't fighting
  the framework, it's applying Flutter's own best-practice systematically
  from the render-object layer down.
- **CanvasItem-tree equivalent** (chrome + one embedded document node): a
  fixed, explicit `enum CanvasLayer { pagesBg, drawing, pagesFg, grids,
  guides, sketch, temp, controls }` with one `Stack`/custom compositing
  `Layer` per entry in that literal order — port the named-layer-stack idea
  verbatim, it's simple and battle-tested; don't let layer order become
  implicit insertion-order state.
- **Tiled/incremental rendering**: Flutter's engine already does its own
  tiling/raster-cache/GPU compositing under the hood, so **do not**
  reimplement Inkscape's `Stores`/`Updaters`/thread-pool machinery wholesale
  — instead, apply the *ideas* where Flutter doesn't already cover them:
  - For genuinely large documents (thousands of items), do the `sd_render`
    tree's **layout pass** (bbox recompute, dirty-region accumulation) on a
    background `Isolate` (or a compute worker via `Isolate.run`), since that
    part — walking a large object graph and computing geometry — is pure,
    CPU-bound Dart work with no Flutter/`dart:ui` dependency, exactly like
    the routing package (§7). Keep the final `Canvas` paint calls on the UI
    isolate (required by the framework), but hand them pre-computed
    display-lists/paths so the UI-isolate work per frame is just "replay
    these already-resolved drawing commands," analogous to how Inkscape's
    worker threads do the expensive tree walk and the main thread only
    blits finished tiles.
  - Adopt the **distance-from-viewport-center / time-budget** prioritization
    idea if implementing any custom incremental refinement (e.g. progressive
    rendering of a very complex filter or a huge imported SVG): process the
    nearest-to-viewport dirty items first, checking a wall-clock budget
    (`Stopwatch`) each iteration and yielding via
    `SchedulerBinding.instance.scheduleFrameCallback` if exceeded, rather
    than blocking a whole frame.
  - The "decoupled snapshot during a live transform" trick maps directly onto
    Flutter's own `Transform` widget wrapping a cached `Picture`: during an
    interactive pan/zoom, paint a cached raster of the last-good frame
    through a `Transform` (cheap, GPU-composited) instead of re-issuing full
    vector paint commands every frame, and only re-issue real paint once the
    gesture ends or settles — this is a well-known Flutter performance
    pattern and is exactly what Inkscape's `Stores::Mode::Decoupled` does.
- **Filters**: model as a small pipeline of named-buffer operations
  (`Map<int, ui.Image>` slots, one `FilterPrimitive` per SVG filter
  primitive reading named inputs and writing a named output) mirroring
  `FilterSlot`/`FilterPrimitive` directly — implement each primitive against
  `dart:ui`'s `ImageFilter`/`ColorFilter` where a direct equivalent exists
  (blur, color matrix), and fall back to manual pixel manipulation via
  `ImageShader`/`Picture.toImage()` + isolate-side raw pixel loops (mirroring
  `dispatch_pool`'s per-primitive parallelism) only for primitives with no
  `dart:ui` equivalent (turbulence, displacement map, custom morphology).

---

## 7. Orthogonal connector routing (libavoid)

### 7a. The C++ architecture, precisely

This is Michael Wybrow's **libavoid**, bundled at
`src/3rdparty/adaptagrams/libavoid/`, implementing the Wybrow/Marriott/Stuckey
"Orthogonal Connector Routing" (Graph Drawing 2009) algorithm. Inkscape's
`src/ui/tools/connector-tool.cpp` and `src/object/sp-conn-end*.cpp` wire it to
the document. Key files (all read directly, not summarized secondhand):
`router.h/.cpp`, `connector.h/.cpp`, `connend.h/.cpp`, `connectionpin.h/.cpp`,
`obstacle.h/.cpp`, `shape.h/.cpp`, `junction.h/.cpp`, `visibility.cpp`,
`graph.cpp`, `vertices.cpp`, `scanline.h/.cpp`, `makepath.h/.cpp`,
`orthogonal.h/.cpp`, `vpsc.h/.cpp`, `hyperedge*.cpp`, `mtst.cpp`.

#### The `Router` facade and its public contract (verified from `router.h`)

`Avoid::Router` is constructed with a bitmask `RouterFlag`: `PolyLineRouting=1`,
`OrthogonalRouting=2` (a router can support either or both connector styles;
Inkscape's connector tool uses orthogonal). It owns everything: obstacles
(`ObstacleList m_obstacles`, which includes both plain `ShapeRef`s and
`JunctionRef`s), connectors (`ConnRefList connRefs`), and the graph state
(`EdgeList visGraph` for polyline mode, `visOrthogGraph` for orthogonal mode,
plus `VertInfList vertices`).

Two enums define the *entire tunable surface* a Dart port needs to reproduce
(both read verbatim from `router.h`):

- **`RoutingParameter`** (numeric knobs, `Router::setRoutingParameter`/`routingParameter`):
  `segmentPenalty` (cost per bend; **must be > 0 for orthogonal nudging to run
  at all**, since bendless routes give nudging nothing sensible to work with),
  `anglePenalty` (continuous bend-sharpness penalty, polyline routing only),
  `crossingPenalty` and `fixedSharedPathPenalty` (experimental, penalize
  crossing/sharing another connector's path), `clusterCrossingPenalty`
  (experimental), `portDirectionPenalty` (experimental), `shapeBufferDistance`
  (default 0 — clearance added around every obstacle), `idealNudgingDistance`
  (default 4 — desired gap between nudged parallel segments),
  `reverseDirectionPenalty` (default 0 — discourage routing away from target
  before turning back). Every parameter can also be set to a library-chosen
  "sensible" magnitude by passing a negative value (the constant
  `chooseSensibleParamValue = -1`) instead of an explicit number — verified
  exact constructor-defaults vs. sensible-auto-values:

  | parameter | ctor default | "sensible" auto value |
  |---|---|---|
  | `segmentPenalty` | 10 | 50 |
  | `anglePenalty` | 0 | 50 |
  | `crossingPenalty` | 0 | 200 |
  | `clusterCrossingPenalty` | 4000 | 4000 |
  | `fixedSharedPathPenalty` | 0 | 110 |
  | `portDirectionPenalty` | 0 | 100 |
  | `shapeBufferDistance` | 0 | 50 |
  | `idealNudgingDistance` | 4.0 | 4.0 |
  | `reverseDirectionPenalty` | 0 | 50 |

  **Inkscape itself only ever touches one of these**, at document
  construction (`src/document.cpp`): `router->setRoutingPenalty
  (Avoid::segmentPenalty)` with no explicit value, i.e. accepting the
  "sensible" default of 50 — every other parameter (including
  `shapeBufferDistance`, notably) is left at the library's built-in
  default. Inkscape implements shape clearance **itself**, separately (see
  the integration section below), rather than via `shapeBufferDistance`.
- **`RoutingOption`** (booleans, `Router::setRoutingOption`/`routingOption`):
  `nudgeOrthogonalSegmentsConnectedToShapes` (default **false**),
  `improveHyperedgeRoutesMovingJunctions` (default **true**),
  `penaliseOrthogonalSharedPathsAtConnEnds` (default false, experimental),
  `nudgeOrthogonalTouchingColinearSegments` (default false),
  `performUnifyingNudgingPreprocessingStep` (default **true**),
  `improveHyperedgeRoutesMovingAddingAndDeletingJunctions` (default false),
  `nudgeSharedPathsWithCommonEndPoint` (default **true**).

Mutations — `moveShape`, `deleteShape`, `moveJunction`, `deleteConnector`,
endpoint changes — are **queued**, not applied immediately: they land in an
internal `ActionInfoList` and are only actually processed when
`Router::processTransaction()` is called, which batches and dirty-tracks so
that N shape moves in a frame cost one graph rebuild + one reroute pass, not
N. `Router::TransactionPhases` (also in `router.h`) documents the exact
pipeline order, which is the single most useful artifact in the whole library
for a reimplementer:

```
TransactionPhaseOrthogonalVisibilityGraphScanX   // Stage 1, vertical sweep
TransactionPhaseOrthogonalVisibilityGraphScanY   // Stage 1, horizontal sweep
TransactionPhaseRouteSearch                      // Stage 2, first A* pass, all connectors
TransactionPhaseCrossingDetection                // find connectors whose routes actually cross
TransactionPhaseRerouteSearch                    // Stage 2 again, only for crossing connectors, now with crossingPenalty live
TransactionPhaseOrthogonalNudgingX               // Stage 3, X axis
TransactionPhaseOrthogonalNudgingY               // Stage 3, Y axis
TransactionPhaseCompleted
```

**`ConnRef`** (`connector.h/.cpp`) is one routable connector: an id, a
`ConnType` (`ConnType_PolyLine` vs `ConnType_Orthogonal`), two `ConnEnd`s, an
optional ordered list of checkpoints, and the computed result
(`displayRoute()` / `route()`, a `PolyLine` — an ordered point list). A
callback (`setCallback`) fires when its route changes so the owner (Inkscape's
connector-tool.cpp) can write the new geometry back to the SVG path.

**`ConnEnd`** (`connend.h/.cpp`) is a small sum type in spirit: a free-floating
point; a point attached to a `ShapeRef` with a set of allowed exit directions
(`ConnDirFlags`: `ConnDirUp/Down/Left/Right`, or `ConnDirAll`); or attached to
a named `ShapeConnectionPin` (`connectionpin.h/.cpp`) — a fixed attachment
point on a shape with its own allowed directions and priority, analogous to a
named "port."

**Obstacles** (`obstacle.h/.cpp`, `shape.h/.cpp`): a `ShapeRef`'s underlying
`m_polygon` may be an arbitrary (even concave) polygon — `Obstacle::
offsetPolygon()` computes a genuine per-edge-normal, miter/bevel-joined
buffer offset, not just an AABB expansion. **But for orthogonal routing
specifically, the graph-construction code always reduces every obstacle to
its axis-aligned bounding box regardless**: `Obstacle::routingBox()` =
`polygon.offsetBoundingBox(shapeBufferDistance)`, and it's this `Box` that
Stage 1 (below) actually consumes. This is a directly citable confirmation
that restricting obstacles to axis-aligned rectangles (7b) isn't a
simplification invented for the Dart port — it's exactly what libavoid's own
orthogonal mode does internally. `JunctionRef` is also an `Obstacle`
subtype (a tiny ~1px square centered on the junction point) but is excluded
from graph-building while free to move (only "pinned" junctions, or ones
mid-improvement, block routing).

**Endpoint attachment — two independent mechanisms, and Inkscape uses only
the simpler one.** `ConnEnd` (`connend.h/.cpp`) is a small sum type: a
free-floating point (`ConnEndPoint`, optionally with a `ConnDirFlags` mask —
`ConnDirUp=1/Down=2/Left=4/Right=8/All=15`, Y-axis-down convention), a point
attached to a **named** `ShapeConnectionPin` on a shape
(`ConnEndShapePin` — a pin carries its own proportional-or-absolute
offset within the shape's bbox, an "inside offset" nudging it off the exact
boundary, allowed directions, an optional exclusivity flag, and a
connection-cost bias), or attached to a `JunctionRef` (`ConnEndJunction`,
implicitly the junction's single always-present center pin). When an end
is attached to a pin *class* rather than one exact pin (e.g. "any pin of
class 3 on this shape"), Stage 2's search doesn't special-case multiple
goals at all — it reduces to an ordinary single-target search by
temporarily fanning the dummy endpoint vertex out to **every** currently
unclaimed matching pin via real, correctly-weighted edges (weight =
distance + the pin's own cost + a `portDirectionPenalty` if misaligned), letting
the A* cost function itself pick the cheapest pin as a side effect of normal
search (`ConnEnd::assignPinVisibilityTo`) — a clean "super-source with
weighted fan-out" reduction worth reusing directly in a Dart port for the
same multi-goal case. **Inkscape itself uses none of this**: its connectors'
`ConnEnd`s are always plain free-floating points sitting at the target
shape's visual-bbox midpoint (or the connector curve's own literal endpoint
if unattached) — `ShapeConnectionPin`, `JunctionRef`, `Checkpoint`, and
`setFixedRoute` are all confirmed unused anywhere in Inkscape's own code
(grep-verified), even though they're fully part of libavoid's public
contract and worth including in a complete Dart port.

**Hyperedges are an emergent structure, not a distinct core-data-model
class.** A hyperedge is simply whatever tree of `ConnRef`s ends up with
their `ConnEnd`s pointing at shared `JunctionRef`s (3+ connectors converging
on one junction). `ConnRef::splitAtSegment()` is the primitive that grows
one (insert a junction mid-route, spin off a new connector); a dedicated
`HyperedgeRerouter` (reached via `Router::hyperedgeRerouter()`) offers two
distinct improvement strengths, both run automatically inside
`processTransaction()` when enabled: a cheap **local nudge** (existing
topology fixed, only reposition junctions — the
`improveHyperedgeRoutesMovingJunctions` option, on by default) via the same
`ShiftSegment`/VPSC machinery as ordinary Stage-3 nudging, or a full
**re-topologize** (`improveHyperedgeRoutesMovingAddingAndDeletingJunctions`,
off by default, or explicit `registerHyperedgeForRerouting()`) that rebuilds
a minimum-terminal-spanning-tree-style Steiner topology from scratch via
`mtst.cpp`'s extended-Dijkstra/Kruskal-with-union-find construction.

**Obstacle registration is opt-in, not automatic — a real and important
correction to a natural first assumption.** Not every `SPItem` becomes a
`ShapeRef`; only items with the boolean XML attribute
`inkscape:connector-avoid="true"` do (`SPItem::avoidRef`/`SPAvoidRef`,
`src/conn-avoid-ref.cpp`). The polygon handed to `ShapeRef` is **not** a raw
bounding box either: `avoid_item_poly()` recursively samples points along
the item's actual outline (endpoints of line segments, 4 evenly-spaced
samples per cubic Bézier; recurses into group children), takes their 2-D
convex hull, then offsets every hull edge outward by a **document-level**
`inkscape:connector-spacing` setting (`SPNamedView::connector_spacing`,
default 3.0) and re-intersects consecutive offset edges — Inkscape's own
hand-rolled equivalent of `shapeBufferDistance`, applied at polygon
construction time instead of through the router parameter (which, per
above, Inkscape leaves at 0). Obstacle geometry is resynced on every
`connectTransformed` signal from the item (so it live-tracks moves/resizes),
via `Router::moveShape` — but there is a **documented, known limitation** in
Inkscape's own source (a TODO comment) that this resync is purely
signal-driven and **does not fire on undo/redo** (undo doesn't emit
transform-changed signals the same way), so obstacle geometry can silently
desync from the document after an undo until something next explicitly
moves the shape again. **Worth deliberately avoiding this class of bug in
the Dart port** — e.g. by doing a full obstacle-geometry resync from current
document state after any undo/redo, rather than relying solely on
incremental move signals.

Connectors themselves are identified by `inkscape:connector-type`
(`"polyline"` or `"orthogonal"`; anything else means "not a connector"),
with `inkscape:connection-start`/`inkscape:connection-end` (plus
`-start-point`/`-end-point`) recording what each end is attached to and
`inkscape:connector-curvature` controlling whether corners get rounded into
Bézier curves post-routing (`Polygon::curvedPolyline()`) — Inkscape runs
both `PolyLineRouting` and `OrthogonalRouting` simultaneously on **one
shared `Router` instance per document** (`SPDocument::_router`), picking
per-connector `ConnType` from this attribute.

**`processTransaction()` is called from exactly three places**, each for a
different reason: (1) automatically, from the document's own two-priority
idle-callback update cycle (an update pass, then a lower-priority "rerouting"
pass) — the default, "just works" path for any ordinary edit; (2)
synchronously, while interactively drawing a **new** connector, purely to
drive a live rubber-band preview on every mouse-move (deliberately without
writing to the XML repr, to avoid spamming undo/the XML editor during the
drag); (3) synchronously, while dragging an **existing** connector's
endpoint, for the same live-preview reason. In all cases, the actual route
→ `d`-attribute write-back (`SPConnEndPair::reroutePathFromLibavoid` →
`SPPath::setCurve` → normal repr serialization) is followed by an
**additional, connector-specific trimming step**: Inkscape computes the
real geometric intersection between the routed line and the target shape's
*actual* outline (not just its buffered bbox) and clips the visible
endpoint to that exact point — the libavoid route only needs to get you to
the shape's obstacle boundary/center; this separate step is what visually
snaps the drawn line to the real, possibly non-rectangular, edge. Undo
commits use plain `DocumentUndo::done()` (never `maybeDone`) at exactly
three gesture-end points: finishing a reroute drag, finishing drawing a new
connector, and toggling the `inkscape:connector-avoid` flag on a selection —
a reroute triggered only as a *side effect* of moving some unrelated shape
rides along inside whichever undo transaction the shape-moving action itself
commits, since the reroute-and-repr-update happens synchronously inside the
same `ensureUpToDate()` call before that transaction closes.

#### Stage 1 — building the orthogonal visibility graph

*(verified by directly reading `orthogonal.cpp:1730-1990`,
`generateStaticOrthogonalVisGraph`, plus `scanline.h`)*

Unlike a general visibility graph (which needs O(n²) all-pairs testing, or an
O(n log n) rotational sweep — that's what `visibility.cpp`'s Lee's-algorithm
sweep does, for **polyline** routing), the *orthogonal* visibility graph only
needs axis-aligned sightlines, which admits a cheaper, purpose-built
construction:

1. **Vertical sweep** produces every candidate **horizontal** visibility
   segment. Build an event list: an `Open` event at each obstacle's bbox
   top (`min.y`) and a `Close` event at its bottom (`max.y`), each carrying a
   `Node` keyed by the obstacle's mid-X; plus a `ConnPoint` event per
   connector endpoint/pin at its Y. Sort all events by Y position
   (`compare_events`). Sweep top-to-bottom maintaining a **scanline status
   structure** — a `std::set<Node*, CmpNodePos>` ordered by X — where each
   `Node` tracks `firstAbove`/`firstBelow` pointers to its neighbors in the
   active set, updated incrementally as obstacles open/close. At each
   `Open`/`Close` event, query the scanline for the nearest obstruction to
   the left and right of the shape at that Y (`findFirstPointAboveAndBelow`)
   and emit 1–3 horizontal segments: outer-obstruction → shape's left edge,
   across the shape's own top/bottom edge, shape's right edge → outer
   obstruction (fewer if overlapping shapes truncate visibility). At each
   `ConnPoint` event, emit segments extending left/right from the point as
   far as unobstructed, gated by that point's allowed `ConnDirLeft/Right`
   flags. All candidate segments accumulate in a `SegmentListWrapper` that
   **merges overlapping/collinear segments on insert**.
2. **Horizontal sweep** does the mirror-image pass to produce candidate
   **vertical** segments — but this time, every time a scanline position
   finishes, each newly-completed vertical segment is immediately
   intersected (`intersectSegments`) against the still-pending horizontal
   segments from pass 1. A real crossing where neither segment is blocked
   becomes an actual **graph vertex**, splitting both segments into graph
   **edges** at that point (`addEdgeHorizontal` /
   `generateVisibilityEdgesFromBreakpointSet`). Horizontal segments the sweep
   has moved past are finalized and evicted.

Net result: a sparse, roughly-O(n log n) planar graph whose vertices are
obstacle corners, connector endpoints/pins, and genuine sightline crossings,
and whose edges are exactly the horizontal/vertical line-of-sight
connections a path may travel along. This graph is **static** per
transaction (rebuilt whenever any obstacle moves, cached otherwise) — it does
not depend on which connector is being routed.

#### Stage 2 — min-bend A* search

*(verified by directly reading all of `makepath.cpp`)*

`AStarPath::search(connRef, src, tar, start)` runs one A* search per
connector (and per checkpoint-to-checkpoint leg, chained, for connectors with
intermediate checkpoints) over the Stage-1 graph:

- **State** is a graph vertex, but duplicate/dominance checks compare a
  node's *predecessor vertex* too (`node.prevNode->inf`), so two arrivals at
  the same vertex from different neighbors are correctly kept as distinct
  search states — this is how "direction of arrival" (needed to price bends
  correctly) is folded in without an explicit direction enum.
- **Edge cost** (`cost()`): segment length, plus a bend penalty from the
  actual turn angle between the previous and current segment
  (`angleBetween`): for orthogonal routing this is binary —
  `+segmentPenalty` for any turn, `+2×segmentPenalty` for a 180° reversal.
  Plus `reverseDirectionPenalty` (segment heads away from the src→dst
  direction) and, **only during the dedicated `RerouteSearch` phase**
  (`router->isInCrossingPenaltyReroutingStage()`), `crossingPenalty` /
  `fixedSharedPathPenalty` computed by testing the candidate segment for
  actual geometric crossings against every *other* connector's **current**
  `displayRoute()`. This is why crossing-avoidance is a distinct two-pass
  affair (`RouteSearch` then `CrossingDetection` then `RerouteSearch`) rather
  than folded into one pass: it makes crossing cost dependent on routing
  order/history by construction, not a joint global optimum.
- **Heuristic** (`estimatedCost`): `manhattanDist(curr, target) + bendCount ×
  segmentPenalty`, where `bendCount` is the *provably minimum* number of 90°
  turns needed to reach the target given the current direction of travel and
  the target's acceptable approach direction(s) — a small closed-form
  case table (`bends()`, 8 geometric cases) rather than a search. Because a
  target attachment may accept multiple sides/pins, the heuristic minimizes
  over every candidate attachment point (each corrected by its own
  displacement-to-the-true-target so comparisons stay admissible). This is
  what makes the search both fast *and* exactly bend-minimizing rather than
  merely shortest-path.
- **Main loop**: standard binary-heap A* (open list as a heap, closed
  list per-vertex), with a float-equality-tolerant tie-break that prefers
  continuing straight over turning (a `timeStamp` assigned so
  "forward" exploration sorts first). An orthogonal-only pruning rule skips
  expanding into a direction unless it hugs an obstacle edge
  (`orthogVisPropFlags`) or is coordinate-aligned with one of the
  connector's own valid endpoints — this avoids wastefully exploring the
  open interior of the visibility graph.
- **Output**: the raw ordered vertex list from source to target — a min-bend
  orthogonal polyline, *before* simplification or nudging.

#### Stage 3 — nudging and centering

*(verified by directly reading `ImproveOrthogonalRoutes::execute()` and
`nudgeOrthogonalRoutes()` in `orthogonal.cpp`, and `IncSolver`/`Block` in
`vpsc.cpp`)*

Two problems remain after Stage 2 runs independently per connector: (a)
multiple connectors' paths can legitimately run along the same corridor and
end up coincident or crossing awkwardly, and (b) a path segment may hug an
obstacle edge with zero clearance when free space was actually available to
center within. Both are fixed by a constraint-based 1-D positioning solve,
run once for all connectors together, **per axis, X fully before Y**:

`ImproveOrthogonalRoutes::execute()`:
1. `simplifyOrthogonalRoutes()` — drop collinear points from every raw
   A* route.
2. *If* `performUnifyingNudgingPreprocessingStep` (default on) and no
   `fixedSharedPathPenalty` is set: for each axis, run a **"unifying" pre-pass**
   — same machinery as step 3 below but in a mode that greedily snaps
   segments which *could* share a channel onto exactly the same coordinate
   (via 0-gap equality constraints), so the real pass sees a clean shared
   path with a well-defined order instead of near-miss coordinates.
3. For each axis: compute a **total order** of the segments in each
   overlapping region (`buildOrthogonalNudgingOrderInfo`); collect that
   axis's `ShiftSegment`s (`buildOrthogonalNudgingSegments` — each is
   flagged `fixed` / `zigzag` (a free S/Z-bend with no owner) / ordinary);
   compute each segment's free-space bounds — the nearest obstacle edges on
   either side, via the *same* scanline `Node` machinery as Stage 1
   (`buildOrthogonalChannelInfo`); then nudge (`nudgeOrthogonalRoutes`).
4. Re-simplify (nudging can split segments), run the optional hyperedge
   topology improver, clear caches.

`nudgeOrthogonalRoutes` processes one independent **region** at a time (a
maximal group of segments that transitively overlap along the shift axis —
found by a simple flood-fill via `overlapsWith`), which bounds each solve to
a small local problem instead of one global one:

- Sort the region into a line order (this pre-sort is what lets the code add
  only O(n) *adjacent-pair* constraints instead of O(n²) all-pairs
  constraints).
- Build one solver **Variable** per segment. Desired position and weight
  depend on the segment's role (exact constants, verified in `orthogonal.cpp`:
  `freeWeight=0.00001`, `strongWeight=0.001`, `strongerWeight=1.0`,
  `fixedWeight=100000`):
  - **zigzag** (free S/Z-bend) → desired position = **midpoint of its own
    free-space bounds**, `freeWeight`. This *is* "centering": the segment
    happily drifts anywhere but prefers the center of its channel.
  - segment attached to a shape → desired = current coordinate,
    `strongWeight` (or `strongerWeight` if it's the sole segment bridging two
    shapes — then it especially wants to stay centered rather than shift).
  - segment carrying a user checkpoint, or an ordinary internal segment →
    desired = current coordinate, `strongWeight`.
  - immovable segment → `fixedWeight` (pinned in place).
  - Two synthetic huge-weight boundary variables per segment encode its
    channel limits as one-sided constraints (`channelLeft ≤ seg ≤
    channelRight`, gap 0).
  - Each *adjacent* pair in sorted order gets a separation `Constraint(prev,
    next, gap=idealNudgingDistance)` (default gap 4px) meaning `prev.pos +
    gap ≤ next.pos` — collapsed to an **equality** (gap 0) when the two
    segments are really the same logical path continuing (shared path with a
    common endpoint, or one straight run only split by a kink in the other
    axis).
- Solve. If any fixed/boundary variable ends up away from its desired
  position (over-constrained — not enough room for full spacing), **shrink**
  `idealNudgingDistance` by 10% of its original value for just the affected
  sub-range and retry, up to 10 times, converging toward 0 gap (segments
  allowed to coincide) rather than failing outright — nudging distance is a
  soft preference with graceful degradation, never a hard requirement.
- Write solved coordinates back into each connector's route.

**The solver** (`vpsc.h`/`vpsc.cpp`) is the classic Dwyer/Marriott/Stuckey
**Variable Placement with Separation Constraints** active-set method: minimize
`Σ wᵢ(xᵢ − desiredᵢ)²` subject to `left + gap ≤ right` constraints, solved by
(1) starting every variable as its own singleton block at its desired
position; (2) repeatedly finding the most-violated constraint and, if its two
variables are in different blocks, **merging** the blocks — a merged block's
position is the closed-form weighted average of every member's
(offset-corrected) desired position, updated incrementally; if they're
already in the same block, checking whether an internal active constraint
should instead be relaxed, and **splitting** the block there (with cycle
detection for contradictory equality chains); (3) iterating merge/split to a
fixed point (total cost stops decreasing) — provably the *global* optimum for
this constraint shape.

**Structural fact that matters most for a port**: because segments are always
pre-sorted into one total order and only *adjacent* pairs get constrained,
the constraint graph handed to VPSC here is always a **simple chain**, never
a general DAG. A chain-constrained weighted-least-squares problem is exactly
**isotonic regression with gaps**, solvable by the much simpler **Pool
Adjacent Violators Algorithm (PAVA)** — see 7b.

(Hyperedge handling — a genuine nice-to-have, safely deferrable from an MVP
— is described above under "Router setup / public API.")

#### Top-level orchestration and dirty-tracking, precisely

`Router::processTransaction()` (verified by direct reading of `router.cpp`)
is a thin guard (no-op if nothing is queued and no settings changed) around
`processActions()` (apply every queued shape/junction/connector-endpoint
mutation to the graph) followed by `rerouteAndCallbackConnectors()`, which
runs the stages in exactly this order:

```
regenerateStaticBuiltGraph()        // Stage 1 — see dirty-tracking note below
for each ConnRef (skipping hyperedge members and fixed-route connectors):
    connector->generatePath()        // Stage 2 — but a no-op unless dirty (see below)
hyperedgeRerouter.performRerouting() // full hyperedge re-topologize, if any registered
improveCrossings()                   // crossing-penalty 2nd pass: detect actual crossings
                                      //   among just-routed connectors, then re-run Stage 2
                                      //   ONLY for those, now with crossingPenalty live —
                                      //   this is the literal TransactionPhaseCrossingDetection
                                      //   + TransactionPhaseRerouteSearch pair from the enum
if hyperedge-improvement options enabled: hyperedgeImprover.execute()
improveOrthogonalRoutes(router)      // Stage 3 — global, every orthogonal connector, every time
... fire callbacks for every connector whose route actually changed ...
```

**Three different dirty-tracking granularities, worth reproducing
deliberately rather than assuming uniform incrementality**:
- **Stage 1 is unconditionally rebuilt from scratch every single
  transaction.** `processTransaction()` sets `m_static_orthogonal_graph_
  invalidated = true` on every call regardless of what actually changed, so
  the entire orthogonal visibility graph (every obstacle, every connector
  endpoint) is torn down and rebuilt every time. There is no finer-grained
  "only rebuild the part of the graph near what moved" path anywhere in the
  library — **libavoid itself doesn't bother optimizing this**, which is a
  useful license for a Dart MVP to do the same (a full rebuild) rather than
  engineering incremental graph maintenance prematurely; revisit only if
  profiling on realistically large diagrams shows it matters.
- **Stage 2 is genuinely per-connector incremental**: `ConnRef::
  generatePath()` returns immediately, doing no search at all, unless that
  connector's own `m_needs_reroute_flag` is set — flagged directly on
  endpoint/type changes, or indirectly when an edge it used gets
  added/removed during Stage 1's rebuild (`EdgeInf::alertConns()` propagates
  through a small delegate object so edges can flag connectors without
  needing back-pointers to a possibly-already-deleted `ConnRef`).
- **Stage 3 is global and unconditional every transaction**: it iterates
  *every* orthogonal `ConnRef` in the router and re-derives `ShiftSegment`s
  from each one's current `displayRoute()` with no dirty-check at all — even
  a connector that wasn't rerouted this transaction still gets re-examined
  and potentially re-nudged, because it might now be sharing a corridor with
  something that *did* change.

### 7b. Dart translation proposal

**Package**: a standalone pure-Dart package (no Flutter/`dart:ui` import),
e.g. `packages/sd_router`, consumed by `sd_ui`'s canvas layer. Everything here
is deterministic geometry/graph computation on plain data — an ideal
isolate workload, and keeping it Flutter-free means it's independently
unit-testable and reusable outside the canvas.

**Data model** (immutable value types; Dart 3 records/sealed classes over
inheritance where they fit):

```dart
class RPoint { final double x, y; const RPoint(this.x, this.y); }
class RRect  { final double left, top, right, bottom; ... }

sealed class ConnEndSpec {}
class FreePoint extends ConnEndSpec { final RPoint point; }
class ShapeAttachment extends ConnEndSpec {
  final ObstacleId shape; final Set<CompassDir> allowedExits; // N/E/S/W
}
class PinAttachment extends ConnEndSpec {
  final ObstacleId shape; final String pinId;
}

class Obstacle {
  final ObstacleId id; final RRect bounds; final double bufferDistance;
}

enum ConnectorRouting { polyline, orthogonal }

class Connector {
  final ConnectorId id;
  final ConnEndSpec start, end;
  final List<RPoint> checkpoints;      // ordered waypoints, may be empty
  final ConnectorRouting routing;
}

class RoutingParameters {
  final double segmentPenalty, idealNudgingDistance, shapeBufferDistance;
  final double crossingPenalty, reverseDirectionPenalty;
  final bool performUnifyingNudgingPreprocessingStep;
  final bool nudgeSharedPathsWithCommonEndPoint;
  const RoutingParameters({ this.segmentPenalty = 50, this.idealNudgingDistance = 4, ... });
}
```

Mirror libavoid's obstacle model deliberately: **restrict obstacles to
axis-aligned rectangles** for v1 — this is not a simplification invented for
Dart, it's exactly what libavoid's own orthogonal mode does internally
(`Obstacle::routingBox()` reduces every obstacle, however-shaped its input
polygon, to its buffered bounding box before Stage 1 ever sees it). This
alone removes most of the implementation risk in Stage 1 versus a
general-polygon visibility graph, and covers the overwhelming majority of
diagram-editor use cases (boxes, groups, and cluster containers). For the
*buffer* itself, prefer Inkscape's own approach over the raw
`shapeBufferDistance` parameter: compute each obstacle's bounding rect from
a handful of sampled points along its actual outline (cheap — corners for a
rect/polygon, a few Bezier samples for a curved shape) inflated by a
document-level spacing setting, rather than the shape's raw layout bbox —
it gives visibly better clearance for non-rectangular shapes at negligible
cost. Also mirror the **opt-in obstacle flag**: don't make every canvas item
an obstacle by default (most diagram elements — text labels, decorations —
shouldn't deflect connectors); expose a per-item boolean (`avoidConnectors`)
defaulting to on only for shape-like nodes, exactly like `inkscape:
connector-avoid`. And explicitly guard against the one known bug class
found in Inkscape's own integration: **resync all obstacle geometry from
the live document after every undo/redo**, rather than relying solely on
incremental move notifications — Inkscape's own signal-only sync famously
does not fire on undo (a documented TODO in its source), which is exactly
the kind of state-desync bug a from-scratch design can avoid for free by
having `UndoManager` (§3) call `router.resyncAllObstacles(document)` once
after every `undo()`/`redo()`, rather than trusting incremental deltas to
have covered every code path.

**Stage 1 — visibility graph.** Recommend **not** transliterating libavoid's
dual-direction scanline verbatim for the first implementation. Instead, use
the well-known **Hanan-grid** construction, which produces a graph with the
same routing power (any orthogonal path a real diagram needs uses only
coordinates aligned with some obstacle edge or endpoint) for far less
implementation risk:

1. Collect the sorted set of distinct X coordinates (every obstacle
   left/right edge + every connector endpoint X) and distinct Y coordinates
   likewise.
2. For every pair of grid points that are adjacent in a shared row or column
   of that grid, test whether the straight segment between them is
   obstacle-free (a simple interval check against the obstacle list is fine
   up to several hundred shapes; upgrade to an interval tree / sorted sweep
   if profiling shows this is hot).
3. Add a graph edge for every clear pair. Store the graph as
   `Map<VertexId, List<Edge>>` (adjacency list), `Edge{to, orthogonalLength}`.

This is asymptotically worse than libavoid's true sweep for very dense
diagrams (cost scales with grid-line-count², not obstacle count), but is
dramatically simpler to implement correctly and to unit test — appropriate
for a first release. **Document the true two-sweep algorithm above as the
v2 performance upgrade path** if a profiler ever shows this stage is hot;
because it's an internal implementation swapped behind the same
`buildVisibilityGraph()` function signature, upgrading later requires no API
change.

**Stage 2 — A* search.** Port this one fairly faithfully — it's simple,
well-specified, and safe to transliterate *conceptually* (not
line-for-line):

- Search-state key: an explicit Dart record `(VertexId vertex, VertexId?
  arrivedFrom)` used as the map key for open/closed sets — make the
  "direction of arrival matters" property explicit rather than relying on
  incidental object identity as the C++ does.
- Priority queue: Dart has no builtin binary heap; use a small
  `PriorityQueue<AStarNode>` from `package:collection` ordered by `f =
  g + h` (ties broken to prefer continuing straight, mirroring libavoid's
  `timeStamp` trick — track `arrivedFrom` and prefer expanding the
  colinear neighbor first).
- Cost function: segment length + bend penalty (flat `segmentPenalty` per
  turn, `2×segmentPenalty` for a reversal) + optional crossing penalty
  against already-solved routes passed in as a parameter (`List<Polyline>
  existingRoutes`) — keep this a *pure function argument*, not global state,
  unlike the C++ (which reaches into `router->connRefs`), so the function
  stays trivially testable and thread/isolate-safe.
- Heuristic: port the `bends()` case table directly — it's pure geometry
  (given current direction + target's acceptable directions, minimum turns
  needed), an easy and valuable direct port since it's what keeps the search
  fast and exactly bend-minimizing.
- Two-phase crossing resolution: run Stage 2 once for all connectors
  (no crossing penalty), detect actual polyline-polyline crossings, then
  re-run Stage 2 *only* for connectors involved in a crossing with the
  penalty active — replicate this exactly, it's a deliberate design choice
  (order-dependent, not a joint optimum) worth preserving rather than
  "improving," since it's what keeps runtime bounded.

**Stage 3 — nudging/centering.** This is the one place to explicitly
**improve on** a literal port rather than reproduce the C++ machinery,
because the input this call site always produces is a special case with a
much simpler exact solution:

- Group segments into overlap regions (small flood-fill via pairwise
  `overlapsWith`, same as libavoid).
- Sort each region into a total order; build `(desiredPosition, weight,
  minLimit, maxLimit)` per segment using the exact same role table as
  libavoid (zigzag → channel midpoint, tiny weight; shape-attached/fixed →
  current position, large weight; etc.) so behavior matches.
- Solve the resulting **chain**-constrained weighted-least-squares problem
  with the **Pool Adjacent Violators Algorithm** instead of implementing
  libavoid's general `Block`/`Heap`/active-set engine:
  - Represent each segment as a "pool" of one element with
    `(weight, desiredPosition)`.
  - Scan pools left→right; whenever a pool's position would end up less than
    `previousPool.position + gap`, **merge** the two pools into one whose
    position is the gap-corrected weighted average of their members
    (exactly the same closed-form arithmetic as `Block::addVariable`'s
    running sums — just without the general graph/heap bookkeeping, because
    a chain never needs it).
  - Repeat until no adjacent pair violates its gap; expand pools back to
    individual segment positions, preserving each member's fixed offset
    within its pool.
  - This is a direct, ~50-line, O(n) algorithm with no cycle-detection edge
    cases, provably equivalent to VPSC's output whenever the constraint
    graph is a simple chain — which it always is for this call site (segments
    are pre-sorted and only adjacent pairs are constrained). Unit-test it
    directly against hand-computed isotonic-regression examples.
  - Reproduce the graceful-degradation retry (shrink `idealNudgingDistance`
    by 10% within an over-constrained sub-range, down to 0, up to 10 tries)
    exactly — it's what keeps nudging from ever hard-failing on a tight
    diagram.
- Keep the general VPSC engine as a documented "if a future feature needs
  non-chain constraints, implement full `Block`/active-set VPSC then" — don't
  build it speculatively.

**Concurrency and integration**:

- Expose a `RouterScene` facade whose mutators (`addObstacle`, `moveObstacle`,
  `updateConnectorEnd`, …) are synchronous, cheap, and only mark dirty state
  — mirroring `Router::processTransaction()`'s batching discipline exactly.
  A single `Future<Map<ConnectorId, List<RPoint>>> reroute()` performs the
  actual 3-stage compute.
- Make the 3-stage compute a **pure function** of an immutable snapshot
  (`RoutingSnapshot { obstacles, connectors, params }`) returning a result
  map, with no shared mutable state — this is what makes it safe to run via
  `Isolate.run(() => routeAll(snapshot))` for a one-off reroute, or via a
  long-lived worker isolate (a `SendPort`/`ReceivePort` request/response
  loop) if rerouting happens on every pointer-move during a drag, to avoid
  per-call isolate-spawn overhead. Either way, this keeps potentially
  expensive graph/A*/VPSC work off the UI isolate, which matters more in
  Flutter than in Inkscape's single-process GTK app since janking the UI
  isolate also stalls input handling.
- Debounce `reroute()` to once per animation frame during an interactive drag
  (e.g., trigger from `SchedulerBinding.instance.addPostFrameCallback`, or a
  micro-debounce `Timer`) rather than per pointer-move event — mirroring how
  Inkscape defers `processTransaction()` until a batch of moves completes.
- Publish results via a `ValueNotifier<Map<ConnectorId, List<Offset>>>` (or a
  Riverpod `NotifierProvider` if the rest of the app standardizes on Riverpod
  — match whatever §2/§3 settle on) that only the connector-layer
  `CustomPainter`/`CanvasItem` listens to, so a reroute repaints just the
  connector layer, not the whole document tree.
- Undo/redo: a route is **derived state**, recomputed deterministically from
  obstacle positions and connector endpoints — never push a reroute itself
  onto the undo stack (see §3); only the user-causing edits (move a shape,
  change a connector's endpoint) are undoable commands, and rerouting simply
  re-runs after any undo/redo/edit applies. Cache the last route per
  connector and skip recompute for connectors whose neighborhood didn't
  change.

**Suggested public surface**:

```dart
class Router {
  Router({RoutingParameters params = const RoutingParameters()});
  ObstacleId addObstacle(RRect bounds, {double bufferDistance = 0});
  void moveObstacle(ObstacleId id, RRect newBounds);
  void removeObstacle(ObstacleId id);
  ConnectorId addConnector(ConnEndSpec start, ConnEndSpec end,
      {ConnectorRouting routing = ConnectorRouting.orthogonal,
       List<RPoint> checkpoints = const []});
  void updateConnectorEnds(ConnectorId id, {ConnEndSpec? start, ConnEndSpec? end});
  void removeConnector(ConnectorId id);
  Future<Map<ConnectorId, List<RPoint>>> reroute(); // isolate-eligible
}
```

---

## 8. Live Path Effects (LPE)

### 8a. The C++ architecture, precisely

Files: `src/live_effects/effect.h/.cpp`, `effect-enum.h`,
`src/live_effects/lpeobject.h/.cpp`, `lpeobject-reference.h/.cpp`,
`src/live_effects/parameter/{parameter,path,point}.h/.cpp`,
`src/object/sp-lpe-item.h/.cpp`, `src/object/sp-shape.h/.cpp`,
representative effects `lpe-bendpath.h/.cpp` and `lpe-fillet-chamfer.h/.cpp`.
This is the most directly reusable inspiration in the whole codebase for a
"live parametric DSP-block" system — read it with that framing in mind.

**One public entry point, three overridable tiers of abstraction — a
template-method ladder, not a single interface.** The only method a host
calls is `doEffect(PathVector&)`. Its *default* implementation calls
`doEffect_path(PathVector const&) -> PathVector`, whose default splits the
input into subpaths, converts each to a continuous
`Piecewise<D2<SBasis>>` function ("pwd2"), calls `doEffect_pwd2(pwd2) ->
pwd2` per subpath (or once over the *whole* concatenated path, if the
effect sets `concatenate_before_pwd2 = true`), and converts back. So an
effect author picks the abstraction level that fits their algorithm:
override `doEffect_pwd2` for effects that are naturally continuous
reparametrizations/compositions of functions (bend-along-path, below);
override `doEffect_path` for effects that reason about discrete
segments/nodes (fillet/chamfer, which splices new corner geometry in per
node); override `doEffect` itself only for full control. Conceptually each
level is a pure function: `output = f(parameterValues, input)`.

**A consistent "privileged wrapper + virtual hook" idiom, the same pattern
seen in §2's `invoke_build`/`build`**: every lifecycle moment has a
*private, overridable* hook (`doOnApply`, `doBeforeEffect`, `doOnRemove`,
`doAfterEffect`, `doOnOpen`, `transform_multiply`) plus a *public,
non-virtual* `..._impl` wrapper that does fixed bookkeeping before/after
calling it — e.g. `doBeforeEffect_impl` detects "the shape's node/subpath
count changed since last time" and calls `adjustForNewPath()` before
invoking the effect's own `doBeforeEffect`; `doOnException` is the
fail-safe hook (default: silently revert to the pre-effect geometry rather
than propagate an exception into the render pipeline). **This same
"non-overridable entry point does bookkeeping, then dispatches to a
narrower virtual hook" shape recurs across the whole codebase** (§2's
`invoke_build`/`build`, §2's `invoke_show`/`show`, this section's
`do*_impl`/`do*`) — treat it as a general Inkscape idiom worth adopting
uniformly in the Dart port (a base class method does the invariant
bookkeeping and calls a protected method subclasses implement), not
something specific to LPEs.

**Parameters are self-describing and self-serializing.** `Parameter`'s
contract is six methods: parse from an SVG-attribute string, serialize back
to one, serialize the default, reset-to-default, "the default changed"
notification, and build a UI widget. Every concrete LPE registers each
parameter member via `registerParameter(&param)` in its constructor,
populating a plain `vector<Parameter*>` the base class uses generically for
UI panel generation, bulk save/load, and change dispatch — an LPE author
never writes serialization code, only a typed value + wire format for
genuinely new parameter kinds (concrete types: scalar, bool, path, point,
array, satellite-array, ...). **`PathParam` is the interesting one**: its
value can be literal inline path data *or* a live `href` reference to
another document object, in which case it subscribes to that object's
modified-signal and automatically re-reads its curve on change — this is
how e.g. "bend along this other path" parameters track edits to the
referenced path live.

**`LivePathEffectObject` is a distinct, addressable document node — not a
property bag on the shape it affects.** It's its own `SPObject` subclass
representing one `<inkscape:path-effect>` element (living in `<defs>`),
owning exactly **one** `Effect` instance, recreated whenever its own
`effect="..."` attribute changes (it is its own factory trigger — the
`effect=` value names which concrete C++ class to instantiate). A generic
"my own attribute changed" observer on this object dispatches to
`Effect::setParameter(key, value)` **which deliberately does not write back
to XML** (it's only ever reached *from* an XML-change notification, so
writing back would loop) — pure in-memory re-derivation, mirroring §2's
"repr is authoritative, object fields are a re-derived cache" rule exactly.
**Sharing vs. cloning is an explicit, deliberate operation**:
`fork_private_if_necessary()` duplicates an LPEObject's XML node (and thus
its whole parameter set) if it's referenced by more items than a policy
allows — so "apply the same effect type to two shapes" gives each shape
independently-tunable parameters rather than silently aliasing one shared
state, unless the code explicitly wants sharing.

**The stack, and the recompute trigger — no incremental recomputation,
ever.** `SPLPEItem` stores an ordered, `;`-joined list of LPEObject hrefs in
one XML attribute (`inkscape:path-effect="#id1;#id2;#id3"`) — directly
analogous to SVG filter primitive chaining. At stack-build time,
`SPLPEItem` subscribes to every referenced LPEObject's modified-signal;
a parameter write anywhere in the chain flows: LPEObject's repr-attribute-
changed → `Effect::setParameter` (in-memory only) → LPEObject's own
modified-signal → the subscribed `SPLPEItem` → **`SPShape::
update_patheffect(write)`**, the real recompute driver. This function
**always starts from `curveForEdit()`** — the pristine, pre-effect
"original" geometry (`inkscape:original-d` if the item has an effect stack,
else just `d`) — and calls `performPathEffect()`, which walks the **entire**
stack top to bottom, threading one `PathVector` by reference through each
stage's `doEffect()` in turn (`original → effect1(original) → effect2(...) →
... → final`), writing the final result to `d` only at the very end. **This
is confirmed to be a full recompute from the untouched source every single
time**, exactly like re-rendering an audio DSP graph from its source buffer
through a fixed effect chain on every parameter tweak — never an attempt to
incrementally patch one stage's output from a previous run. Each stage may
still cache internally (e.g. `LPEBendPath` only recomputes its skeleton's
arc-length parametrization when that specific parameter's own dirty flag is
set), but that's a private optimization invisible to the stack's contract.

**Original vs. displayed geometry — two attributes, one coherent design
that already connects §2, §4 and this section.** `inkscape:original-d`
(pre-effect) and `d` (post-effect, always the rendered result) are both
persisted; `SPShape::curveForEdit()` returns the *original* if present
— meaning **the node/pen tool (§4) always edits the pre-effect geometry**,
and the entire effect stack automatically re-runs on top of whatever the
user just edited. This is a clean, already-connected design across three
sections of this document, worth preserving as one coherent contract rather
than three separate features that happen to interact.

**Registration/factory**: a static `EffectType` enum, a parallel metadata
table (`LPETypeData[]`: label, key, icon, description, category, and
per-item-type applicability flags — on-path/on-shape/on-group/on-image/
on-text/experimental) driving UI menu generation and grouping, and a
big-switch factory `Effect::New(EffectType, LivePathEffectObject*)` reached
from exactly one call site — `LivePathEffectObject::set(PATH_EFFECT, value)`.
`Effect::createAndApply(name, doc, item)` is the "do both halves" UI-facing
entry point: create the `LivePathEffectObject` (which triggers construction)
*and* push its href onto the target item's stack.

**Concrete example (`LPEBendPath`)**: parameters are a `PathParam` (the
skeleton path to bend along — possibly a live reference), a `ScalarParam`
(width scale), and a couple of `BoolParam`s. Its `doEffect_pwd2` (cached
arc-length-reparametrized skeleton + unit-normal field; recomputed only
when the skeleton parameter's own `changed` flag fires) computes
`compose(skeleton, x) + y * compose(normal, x)` — "walk `x` distance along
the skeleton, then offset by `y` along its local normal" — a compact,
literal example of the continuous-function-composition tier.

### 8b. Dart translation proposal

This maps almost directly onto the "live DSP block chain" framing —
implement it as `packages/sd_effects` (or a submodule of `sd_document`),
consumed by `sd_render`.

```dart
abstract class GeometryEffect {
  List<EffectParameter> get parameters;          // ~ registerParameter list
  Path apply(Path input);                        // the one required tier —
                                                  // discrete PathVector in/out.
  // An optional second, narrower tier for effects that are naturally a
  // continuous reparametrization (bend/taper/offset-along-path): implement
  // against a small resampled polyline-as-function representation instead
  // of porting 2geom's symbolic Piecewise<SBasis> algebra wholesale — for
  // most practical effects, densely resampling the input path into short
  // segments and transforming each sample is numerically indistinguishable
  // from the true continuous composition, and is dramatically simpler to
  // implement correctly in Dart. Reserve a real symbolic pwd2-equivalent
  // for later only if a specific effect's quality demonstrably needs it.
}

abstract class EffectParameter<T> {
  String get key;                    // the persisted attribute/JSON key
  T value; T get defaultValue;
  T parse(String svgValue); String serialize(T value);   // wire format
  CanvasHandle? buildHandle(GeometryEffect owner)  => null; // ~ providesKnotHolderEntities
}
```

- **Keep the "privileged wrapper + narrow virtual hook" idiom** for
  lifecycle moments (`onApplied`, `beforeRecompute`, `onRemoved`,
  `onException`), implemented once on a base `GeometryEffect` class exactly
  like `invoke_build`/`build` in §2 — this is the same idiom in a third
  place in the codebase, which is a strong signal to name and reuse it as
  one convention across `sd_document`/`sd_effects` rather than
  reinventing it per subsystem.
- **`EffectStage` as its own addressable, referenceable document node**
  (mirroring `LivePathEffectObject`), not just a struct embedded in the
  shape it modifies — this is what buys you the sharing-vs-forking
  semantics: `List<EffectStageRef>` on a shape (a proper ordered array in
  the document model — no need for `;`-joined string encoding the way one
  XML attribute forced in C++) where each ref either **shares** a stage
  object (edits propagate to every shape using it) or **owns a private
  fork** (`stage.fork()` on duplicate, mirroring `fork_private_if_necessary`
  as an *explicit* operation your duplicate/copy `Command` calls, not
  something implicit).
- **Recompute is always a full, pure re-run from the untouched original —
  replicate this discipline exactly, it's the core good idea here**:
  ```dart
  Path recomputeDisplayGeometry(Path original, List<GeometryEffect> stack) {
    var curve = original;
    for (final effect in stack) { curve = effect.apply(curve); }
    return curve;
  }
  ```
  Never attempt incremental/delta recomputation across stages — it's not
  worth the complexity, and Inkscape itself doesn't do it. Memoize only
  the *whole-stack result*, keyed by `(original path version, stack
  parameter snapshot)` so an unrelated document change doesn't force a
  wasted recompute, and let any real change (input curve OR any parameter
  anywhere in the stack) invalidate and fully re-run — a plain equality/
  version-number check is enough, no fine-grained dependency tracking
  needed given the stack sizes involved (single digits to low tens of
  stages in practice).
- **`SdShape` should carry the same two-geometry contract**:
  `Path originalGeometry` (what the node tool edits, §4) and a derived,
  cached `Path displayGeometry` (what §6 renders) — recomputed by the
  function above whenever `originalGeometry` or the effect stack changes,
  never edited directly.
- **Registration**: a plain `Map<String, EffectDescriptor>` const registry
  (`label`, `category`, `applicableTo: Set<ShapeKind>`, `factory:
  (SdDocument) => GeometryEffect`) — no enum-plus-switch ceremony needed;
  Dart's first-class functions make the factory table itself the whole
  "registration," and `applicableTo` directly drives menu filtering.
- **On-canvas handles**: `EffectParameter.buildHandle()` returning a
  `CanvasHandle?` (§4's type) is a direct, natural bridge — the node/handle
  tool layer can generically collect handles from every parameter of every
  active effect on the current selection without knowing anything about
  specific effect types, exactly like `KnotHolderEntity`/`PointParam`.
- **Concurrency**: keep `apply()` a pure function of `(Path, parameter
  values)` with no side effects and no reference to the wider document —
  this makes the whole-stack recompute trivially shippable to an `Isolate`
  for expensive cases (long stacks, dense paths, a parameter being dragged
  every frame) via the same debounce-to-frame pattern as §§6-7, without any
  special-casing: serialize just the plain-data original path + parameter
  snapshot, run `recomputeDisplayGeometry` on a worker isolate, post the
  resulting `Path` back. For typical small stacks on typical paths, running
  synchronously on the main isolate is almost certainly fine — profile
  before reaching for the isolate.

---

## 9. Cairo vector renderer

### 9a. The C++ architecture, precisely

Files: `src/extension/internal/cairo-renderer.h/.cpp`,
`cairo-render-context.h/.cpp`, `cairo-ps-out.h/.cpp`,
`cairo-renderer-pdf-out.h/.cpp`, plus `src/display/cairo-utils.cpp`
(`feed_curve_to_cairo` et al.) and `src/path-chemistry.cpp`
(`convert_text_to_curves`).

**A second, independent tree-walking renderer — not a reuse of the display
tree from §6.** `CairoRenderer::renderItem()` recurses the **SPObject/SPItem
DOM tree directly** (not the `Drawing`/`DrawingItem` tree used for
interactive on-screen rendering), dispatching per concrete type via the
same hand-rolled tag-range RTTI as §2 (`cast<T>`), not virtual dispatch —
an if/else-if chain over `SPRoot`/`SPSymbol`/`SPAnchor`/`SPShape`/`SPUse`/
`SPText`/`SPFlowtext`/`SPImage`/`SPGroup`. **Inkscape maintains two separate,
independently-implemented paint-dispatch pipelines** — one for the
interactive canvas, one for export — a direct consequence of C++'s
concrete-surface-type coupling (an on-screen `Cairo::ImageSurface` vs. a
`cairo_pdf_surface_t` are different types requiring different setup, even
though most of the actual per-shape drawing calls are identical). **This
duplication is avoidable in a from-scratch Dart design** — see 9b.

**Confirmed: real vector output, not rasterization-then-embed.**
`CairoRenderContext::setupSurface()` creates a genuine
`cairo_pdf_surface_create_for_stream`/`cairo_ps_surface_create_for_stream`
(never an image surface for vector targets, and — notably —
`cairo_svg_surface_create` is never used anywhere in this code at all).
Fills, strokes, gradients, patterns, and (by default) text all become real
vector drawing operators in the output content stream. Only two things get
rasterized and embedded as bitmap data even in PDF/PS output: `<image>`
elements (unavoidably), and — only when an explicit "rasterize filter
effects" export option is checked (**on by default**) — any subtree that
has an SVG filter applied, since Inkscape makes no attempt to translate SVG
filter primitives into native PDF vector/soft-mask operators; if that
option is unchecked, a filtered item is instead rendered as plain
**unfiltered** vector content with the filter silently dropped (clip-path
contents are explicitly exempted from this rasterize-or-drop choice
regardless of the setting).

**Path emission — arcs are a real native primitive, not
pre-flattened.** `feed_curve_to_cairo()` dispatches by curve type: a line
segment → `cairo_line_to`; a quadratic is degree-elevated to a cubic then
emitted via `cairo_curve_to` (Cairo has no quadratic primitive); a cubic →
direct `cairo_curve_to`; and — the notable case — an `EllipticalArc` is
mapped to a real `cairo_arc`/`cairo_arc_negative` call under a temporary
affine that maps the unit circle onto the actual ellipse, **not** flattened
to Béziers by 2geom beforehand. Only genuinely unusual curve types (e.g.
some path-effect intermediate representations) fall back to a slow numeric
flatten-to-cubic-Béziers path. **Important nuance for a Dart port**: Cairo's
own PDF backend internally flattens `cairo_arc` calls to Béziers before
writing them into the actual PDF content stream, because **the PDF file
format itself has no native arc operator** (only `m`/`l`/`c`/`re`) — so
Inkscape gets arc convenience "for free" from Cairo hiding that flattening;
a Dart port targeting PDF bytes directly (via a PDF-generation library that
also only exposes line/cubic path construction, matching PDF's real
primitives) will need its **own** elliptical-arc-to-cubic-Bézier flattening
step (a small, well-known, easy piece of math — split into ≤90° segments,
each approximated by one cubic with the standard κ ≈ 0.5523 control-point
factor) rather than being able to lean on a "native arc" call the way the
C++ code appears to.

**Paint/style mapping** (all in `CairoRenderContext`, `cairo-render-
context.cpp`): solid fill/stroke color → `cairo_set_source_rgba`; linear/
radial gradients → `cairo_pattern_create_linear/radial` +
`cairo_pattern_add_color_stop_rgba` per stop, spread mode →
`cairo_pattern_set_extend`; **pattern fills are genuinely rasterized even
for vector output** — a `<pattern>`/`<hatch>` tile is rendered into a
separate offscreen similar-surface once, then wrapped as a repeating
`cairo_pattern_create_for_surface`/`CAIRO_EXTEND_REPEAT`, by recursively
calling the *same* generic `renderItem()` walker on the tile's content;
stroke width/cap/join/miter/dash map to the obvious `cairo_set_*` calls,
with a device-independent "hairline" special case. Group isolation (opacity
&lt; 1 forced into its own group when it can't be safely folded into paint
alpha directly, non-normal blend mode, clip, mask) uses
`cairo_push_group`/`cairo_pop_group_to_source` exactly like §6's
interactive renderer. **A real, important asymmetry**: a clip-path, when
not accompanied by a mask, stays **100% vector** (`cairo_clip` with a real
path, and clip content can itself be arbitrary nested shapes/text/groups
rendered through the same recursive walker) — but a **mask is always
rasterized to a bitmap regardless of output target**, via a hand-rolled
per-pixel RGB-luminance-to-alpha conversion loop and `cairo_mask_surface`
(not the more general `cairo_mask(pattern)`), because Cairo/PDF's vector
soft-mask facilities aren't used here. **Clip-paths are vector-preserved;
masks are not** — a non-obvious, worth-preserving asymmetry for a faithful
port, though see 9b for a pragmatic simplification.

**Text — real embedded glyphs by default, path-conversion as a deliberate
upfront document rewrite, not a per-glyph runtime choice.** The default
path uses `cairo_show_glyphs` with a `cairo_font_face_t` built via
FreeType, letting Cairo's own PDF/PS backend handle font subsetting/
embedding automatically — Inkscape does no manual font subsetting. The
"convert text to paths" export option does **not** rely on Cairo's own
glyph-to-path conversion at render time at all; instead, *before rendering
starts*, it calls `Inkscape::convert_text_to_curves(doc)`, which physically
rewrites every text element in the in-memory document into a `<g>` of real
`<path>` elements — a code comment explains why: "Cairo's text-to-path
method has numerical precision and font matching issues... we get better
results using Inkscape's own Object-to-Path method." By the time the
renderer runs in this mode, there are typically no text nodes left at all.
(A third, niche "omit text, emit a companion LaTeX overlay" mode also
exists — not relevant to the vector-export architecture question.)

**Transform stacking and multi-page**: ordinary `cairo_transform` calls
compose onto Cairo's own CTM inside nested `cairo_save`/`cairo_restore`
pairs at every recursion level (no manual matrix multiplication anywhere in
this code) — mirroring the same left-to-right accumulation as §2's
`i2doc_affine`. Multi-page PDF/PS output iterates the document's `SPPage`
objects, calling `cairo_pdf_surface_set_size`/`cairo_ps_surface_set_size`
(plus a PDF-only page-label call) between `cairo_show_page()`s — PS and PDF
share the identical renderer/context classes, differing only in a handful
of flag-driven choices (`cairo_ps_surface_restrict_to_level` vs.
`cairo_pdf_surface_restrict_to_version`, an EPS flag).

### 9b. Dart translation proposal

**Unify what Inkscape had to duplicate.** Design one shape-painting
implementation that walks the *same* `sd_render` tree used for on-screen
drawing (§6) and targets a small abstracted sink interface, rather than
writing a second, parallel tree-walker for export:

```dart
abstract class VectorSink {
  void save(); void restore(); void transform(Matrix4 m);
  void moveTo(Offset p); void lineTo(Offset p); void cubicTo(Offset c1, Offset c2, Offset p);
  void setFillPaint(Paint p); void setStrokePaint(Paint p);
  void fill({required bool evenOdd}); void stroke(StrokeStyle style);
  void clip({required bool evenOdd});                 // real vector clip
  void pushGroup(); void popGroup({double opacity = 1, BlendMode blend = BlendMode.srcOver});
  void drawImage(ui.Image image, Rect dst);
  void showText(TextLayoutResult t);                  // optional — see text note below
  void newPage(double width, double height);
}
class CanvasVectorSink implements VectorSink { /* wraps a dart:ui Canvas — used for on-screen paint */ }
class PdfVectorSink implements VectorSink { /* emits real PDF content-stream operators */ }
```

The exact same `paintTree(SdRenderObject root, VectorSink sink)` function
then serves both live rendering and PDF/PS/print export — eliminating the
architectural duplication Inkscape's C++ type system forced, and getting
"my export always matches what's on screen" for free (a class of bug this
sidesteps entirely).

- **Use an existing pure-Dart PDF-writing library for the actual PDF byte
  format** (object/xref/stream generation, page tree, font-embedding
  primitives — e.g. the `pdf` package) rather than hand-rolling PDF's file
  structure — mirror Inkscape's own division of labor exactly: Inkscape
  writes Cairo calls and lets Cairo emit PDF bytes; a Dart port should write
  calls against a chosen PDF library's drawing API and let *it* emit PDF
  bytes, focusing all custom effort on the "walk the render tree, translate
  SVG paint/geometry semantics into the sink's vocabulary" layer, which is
  where the actual design value is.
- **Arcs**: since neither the PDF format nor most PDF-drawing libraries
  expose a native arc primitive, implement elliptical-arc-to-cubic-Bézier
  flattening explicitly in the tree-walker (before calling `cubicTo` on the
  sink) rather than assuming a `arcTo` sink method will be handled
  transparently the way Cairo does internally — this is a small, standard,
  well-documented piece of math, safe to port directly rather than needing
  architectural translation.
- **Clip vs. mask asymmetry — replicate deliberately, and simplify masks
  pragmatically for v1**: implement clip-path as a genuine vector
  `clip()` call (PDF/most vector sinks support this natively — a real win
  for output quality and file size). For masks, mirror Inkscape's own
  choice rather than trying to invent a cleaner vector-mask path PDF
  doesn't straightforwardly offer either: render the mask subtree to an
  offscreen raster, convert to a luminance alpha channel, and apply it as
  an embedded soft-mask image (PDF's `SMask` graphics-state entry is the
  direct native equivalent of what Cairo does here) — don't over-invest in
  a "fully vector mask" path for v1.
- **Text — default to convert-to-path, not glyph embedding, for v1.**
  Real font subsetting/embedding in a hand-built (or library-assisted) PDF
  writer is a substantial, easy-to-get-subtly-wrong undertaking (glyph ID
  mapping, `ToUnicode` CMaps, subsetting tables). Converting every text
  element to its outline path before export (reusing whatever "object to
  path" conversion `sd_document`'s text layout already needs to support)
  sidesteps that complexity entirely and is *more* robust than Inkscape's
  own reasoning for preferring it over Cairo's built-in glyph path
  conversion — treat "embed real, selectable, subsetted glyphs" as a
  legitimate but strictly later optimization once basic export is solid,
  not a v1 requirement.
- **Transform/multi-page**: both map directly onto the sink interface's
  `save`/`restore`/`transform`/`newPage` — no special design needed, since
  both target models (Dart `Matrix4` composition, a PDF sink's own
  save/restore graphics-state stack) already provide these primitives
  natively.

---

## 10. CSS cascade + Schneider curve fitting

*(Deliberately brief, as scoped — pointers to where each lives and how it's
structured, not full derivations.)*

### 10a. CSS cascade

Files: `src/style.h/.cpp`, `src/style-internal.h/.cpp`,
`src/xml/croco-node-iface.h/.cpp`.

Every CSS property on `SPStyle` is a typed field (`SPIFloat`, `SPILength`
— specified value + resolved computed px + unit, `SPIScale24` — 24-bit
fixed point for opacity, `SPIPaint`, `SPIEnum<T>`, ...) all sharing a common
base carrying a `set` flag (explicitly set vs. still-inherited/default), an
`important` flag, and a `style_src` provenance tag. `SPStyle::read()`
applies four sources **in this order, using "first setter wins" semantics**
(a source only writes a property if it isn't already `set`, except
`!important` which forces an override regardless) — since the first source
applied effectively wins, the application order directly encodes CSS
precedence: inline `style=""` → author `<style>` stylesheet rules (matched
with **real CSS specificity** via a genuine selector engine, see below) →
plain presentation attributes (`fill="..."`) → inherited value from the
(already-cascaded) parent. **Selector matching is not a hand-rolled subset**
— it's the real **libcroco** CSS engine, bridged to Inkscape's own
`Inkscape::XML::Node` tree via a small vtable adapter
(`croco_node_iface.cpp`: `get_parent`/`get_first_child`/`get_next`/
`is_element_node`/`get_attr`), giving genuine type/class/id/attribute
selectors and descendant/child/sibling combinators (interactive
pseudo-classes — `:hover`/`:active`/`:focus`/`:link`/`:visited` — are
explicitly *not* wired up, so there's no parity bar being missed by
skipping them in a port). A style change triggers redisplay through the
exact same generic `requestModified(MODIFIED_FLAG|STYLE_MODIFIED_FLAG)`
mechanism as any other object mutation (§2) — nothing style-specific there.

**Dart translation**: port the layered-property-with-a-"set"-flag model and
the four-source, first-setter-wins-except-`!important` merge algorithm
faithfully — it's a clean, well-tested design independent of the host
language (`class StyleProperty<T> { T? value; bool isSet, isImportant; }`
per property on an `SdStyle`). For selector matching, don't attempt to
bind/port libcroco — either lean on an existing pure-Dart CSS parser (e.g.
`package:csslib`, which Dart's own tooling already uses) for the parsing
half and write a small matcher against the `sd_document` tree, or
deliberately scope down to the selectors real-world SVG actually uses
(type, class, id, descendant combinator cover the large majority) rather
than chasing full CSS2.1 parity — again, no worse than what Inkscape itself
supports.

### 10b. Schneider curve fitting (pencil tool)

Files: `src/ui/tools/pencil-tool.h/.cpp`; the actual fitting math is 2geom's
`bezier_fit_cubic_r`/`bezier_fit_cubic_full` (a Graphics-Gems-derived,
Schneider-algorithm port) — **not** `src/path/splinefit/bezier-fit.cpp`,
which is a red herring for this specific feature: that file primarily
delegates to a different, vendored FontForge spline-fitting engine and is
only reached from the node tool's unrelated "delete node, keep shape"
command, never from the pencil tool.

The pencil tool's freehand fitting **is** the classic algorithm: chord-length
parameterize the input point sequence, least-squares-fit a single cubic
from the parameterized points and estimated end tangents, scan for maximum
deviation, and if it exceeds tolerance either Newton-Raphson-reparameterize
and retry or split at the point of maximum error and recurse on both
halves — output is a flat control-point buffer, 4 points per cubic,
consecutive segments sharing an endpoint. **Two-level accumulation**,
worth preserving as a pattern: on every pointer-move,
`PencilTool::_addFreehandPoint()` (a) feeds a small fixed-size rolling
buffer into a cheap **single-segment** fit (`bezier_fit_cubic_full`,
explicit end-tangent continuity from the previous segment) purely to draw a
live rubber-band preview, while (b) simultaneously appending to an
unbounded whole-gesture point vector; on release, the **entire** gesture's
points are refit in one shot via the **multi-segment**
`bezier_fit_cubic_r` (tolerance + max-segment-count driven) for the final,
clean curve.

**Dart translation**: implement the classic Schneider/Graphics-Gems
algorithm directly and fairly literally in pure Dart — this is one of the
few places in this whole document where near-transliteration is the right
call rather than an architectural translation, since it's a compact (order
a few hundred lines), self-contained numerical algorithm with no
C++-specific structure to redesign around. Use the widely-available
Graphics Gems reference implementation (and 2geom's own `bezier-utils.cpp`,
itself a port of it) as the ground truth. Reuse the **same two-stage "cheap
live preview, one clean commit"** convention as §§2/4/8 for the pencil
tool's interaction: a small rolling-buffer single-segment fit recomputed
every pointer-move for live feedback, one full multi-segment refit of the
whole accumulated stroke committed as a single `Command` (§3) on release —
don't build a bespoke one-off interaction pattern for the pencil tool when
this exact shape already exists elsewhere in the design.
