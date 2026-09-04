import 'dart:io';

import 'package:sd_document/sd_document.dart';
import 'package:test/test.dart';

/// The fixture exercises, in one document: an XML declaration, a leading
/// comment (prolog), multiple declared namespaces (default SVG, xlink,
/// inkscape, sd, and one *foreign* namespace we've never heard of), a
/// `<defs>` with `<marker>`/`<symbol>`/`<use>` and a CDATA `<style>`, a
/// layer group, a block's dual representation (plain geometry + `sd:`
/// attributes with JSON params/ports), an edge's dual representation, a
/// stroke's dual representation, a `<text>` label (to exercise the
/// preserve-significant-whitespace path), and an entirely unrecognized
/// foreign element with a foreign attribute — see §3 and §13's "SVG
/// round-trip equality (incl. foreign content) is a first-class acceptance
/// test".
final _fixture = File('test/goldens/sample.svg').readAsStringSync();

const _foreignNs = 'https://example.org/foreign';

void main() {
  group('parse -> write round-trip', () {
    test('is structurally lossless, including foreign content', () {
      final once = parseSdDocument(_fixture);
      final reparsed = parseSdDocument(writeSdDocument(once));

      expect(reparsed.isEquivalentTo(once), isTrue);
    });

    test('re-serializing an already-serialized document is a fixed point', () {
      final first = writeSdDocument(parseSdDocument(_fixture));
      final second = writeSdDocument(parseSdDocument(first));

      expect(second, equals(first));
    });

    test('preserves the XML declaration', () {
      final doc = parseSdDocument(_fixture);

      expect(doc.xmlVersion, '1.0');
      expect(doc.xmlEncoding, 'UTF-8');
    });

    test('preserves a leading comment as prolog', () {
      final doc = parseSdDocument(_fixture);

      // The prolog may also carry insignificant whitespace-only text nodes
      // (the newlines between the declaration/comment/root in the source);
      // those are intentionally not part of round-trip *equivalence* (see
      // `_isSignificant` in document_tree.dart) but are still preserved
      // verbatim by a straight parse, so this only asserts on the comment.
      final comments = doc.prolog.whereType<SdComment>();
      expect(comments, hasLength(1));
      expect(comments.single.data.trim(), 'Created with SigmaDraw');
    });

    test('preserves an unrecognized foreign element and attribute', () {
      final doc = parseSdDocument(_fixture);

      final foreign = doc.root.childElements.firstWhere(
        (e) => e.name.local == 'annotation',
      );
      expect(foreign.name.namespaceUri, _foreignNs);
      expect(
        foreign.getAttribute(const SdQName('confidence', _foreignNs)),
        '0.9',
      );
    });

    test('preserves CDATA content inside <style>', () {
      final doc = parseSdDocument(_fixture);

      final defs = doc.root.childElements.firstWhere(
        (e) => e.name.local == 'defs',
      );
      final style = defs.childElements.firstWhere(
        (e) => e.name.local == 'style',
      );
      final cdata = style.children.whereType<SdCData>().single;
      expect(cdata.data, contains('.sd-wire'));
    });

    test('preserves <defs>/<symbol>/<use> and marker cross-references', () {
      final doc = parseSdDocument(_fixture);

      final defs = doc.root.childElements.firstWhere(
        (e) => e.name.local == 'defs',
      );
      expect(
        defs.childElements.map((e) => e.name.local),
        containsAll(['marker', 'symbol', 'style']),
      );

      final use = doc.root.descendantElements.firstWhere(
        (e) => e.name.local == 'use',
      );
      expect(
        use.getAttribute(const SdQName('href', SdNamespace.xlink)),
        '#gainTriangle',
      );
    });

    test('an unprefixed attribute is never resolved into a namespace', () {
      final doc = parseSdDocument(_fixture);
      // The root's plain `width` attribute must resolve with no namespace,
      // even though the default namespace (SVG) is in scope for elements.
      expect(doc.root.getAttribute(const SdQName('width')), '800');
      expect(
        doc.root.hasAttribute(const SdQName('width', SdNamespace.svg)),
        isFalse,
      );
    });
  });

  group('typed sd: accessors read the fixture correctly', () {
    test('document-level metadata', () {
      final doc = parseSdDocument(_fixture);

      expect(doc.schema, '1.0');
      expect(doc.sampleRate, '48000');
      expect(doc.defaultDtype, 'real');
    });

    test('layer compatibility attributes', () {
      final doc = parseSdDocument(_fixture);

      final layer = doc.root.descendantElements.firstWhere((e) => e.isLayer);
      expect(layer.layerName, 'Signal Flow');
      expect(layer.layerId, 'layer-1');
    });

    test('block dual representation', () {
      final doc = parseSdDocument(_fixture);

      final block = doc.root.descendantElements.firstWhere(
        (e) => e.blockId == 'blk1',
      );
      expect(block.blockType, 'gain');
      expect(block.blockLabel, 'k');
      expect(block.blockParams['gain'], 2.5);
      expect(block.blockPorts, hasLength(2));
      expect(block.blockPorts.first['id'], 'in1');
      expect(block.blockPorts.first['dir'], 'in');
    });

    test('edge dual representation', () {
      final doc = parseSdDocument(_fixture);

      final edge = doc.root.descendantElements.firstWhere(
        (e) => e.edgeId == 'e1',
      );
      expect(edge.edgeFrom, 'blk1:out1');
      expect(edge.edgeTo, 'blk2:in1');
      expect(edge.edgeRoute, 'orthogonal');
      expect(edge.edgeSignalLabel, 'x[n]');
      // The dual representation must still carry plain, renders-everywhere
      // SVG geometry alongside the sd: attributes.
      expect(edge.getAttribute(const SdQName('d')), isNotNull);
    });

    test('stroke dual representation', () {
      final doc = parseSdDocument(_fixture);

      final stroke = doc.root.descendantElements.firstWhere(
        (e) => e.strokeId == 's1',
      );
      expect(stroke.strokePressures, [0.2, 0.5, 0.8, 0.4]);
    });
  });

  group('SdSaveMode', () {
    test('plain strips every sd: attribute, declaration, and value', () {
      final doc = parseSdDocument(_fixture);

      final plain = writeSdDocument(doc, mode: SdSaveMode.plain);

      expect(plain, isNot(contains('sd:')));
      expect(plain, isNot(contains(SdNamespace.sd)));
      // The plain export must still be well-formed and keep the geometry
      // that makes the file render identically everywhere.
      final reparsed = parseSdDocument(plain);
      expect(reparsed.root.getAttribute(const SdQName('width')), '800');
      final block = reparsed.root.descendantElements.firstWhere(
        (e) =>
            e.name.local == 'g' && e.hasAttribute(const SdQName('transform')),
      );
      expect(block.blockType, isNull, reason: 'sd: semantics must be gone');
      expect(
        block.childElements.any((e) => e.name.local == 'use'),
        isTrue,
        reason: 'plain SVG geometry must survive',
      );
    });

    test('native keeps every sd: attribute', () {
      final doc = parseSdDocument(_fixture);

      final native = writeSdDocument(doc);

      expect(native, contains('sd:type="gain"'));
      expect(native, contains('sd:sampleRate="48000"'));
    });
  });

  group('createBlankSdDocument', () {
    test('produces a document that itself round-trips and reads back', () {
      final blank = createBlankSdDocument(
        sampleRate: '48000',
        defaultDtype: 'real',
      );

      final reparsed = parseSdDocument(writeSdDocument(blank));

      expect(reparsed.isEquivalentTo(blank), isTrue);
      expect(reparsed.sampleRate, '48000');
      expect(reparsed.defaultDtype, 'real');
      expect(reparsed.root.name, const SdQName('svg', SdNamespace.svg));
    });
  });

  group('SdDocument.changes', () {
    test('fires on attribute mutation anywhere in the tree', () {
      final doc = parseSdDocument(_fixture);
      var fired = 0;
      doc.changes.addListener(() => fired++);

      final block = doc.root.descendantElements.firstWhere(
        (e) => e.blockId == 'blk1',
      );
      block.blockLabel = 'k2';

      expect(fired, 1);
      expect(block.blockLabel, 'k2');
    });

    test('fires on child insertion and stops firing after detach', () {
      final doc = parseSdDocument(_fixture);
      var fired = 0;
      doc.changes.addListener(() => fired++);

      final newNode = SdElement(const SdQName('rect'));
      doc.root.appendChild(newNode);
      expect(fired, 1);

      newNode.detach();
      expect(fired, 2);

      // Now detached: further mutation must not reach the document anymore.
      newNode.setAttribute(const SdQName('x'), '1');
      expect(fired, 2);
    });
  });
}
