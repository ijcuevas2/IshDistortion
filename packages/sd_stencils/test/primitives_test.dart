import 'package:sd_document/sd_document.dart';
import 'package:sd_stencils/sd_stencils.dart';
import 'package:test/test.dart';

const _svgShapeTags = {'circle', 'rect', 'line', 'polygon', 'path', 'text'};

String? _textOf(SdElement e) {
  final direct = e.children.whereType<SdText>().map((t) => t.data).join();
  return direct.isEmpty ? null : direct;
}

void main() {
  group('every core primitive stencil', () {
    for (final stencil in corePrimitiveStencils) {
      test('${stencil.id}: instantiates a valid dual-representation block', () {
        final instance = stencil.instantiate(instanceId: 'blk1', x: 5, y: 7);

        expect(instance.name.local, 'g');
        expect(instance.blockType, stencil.id);
        expect(instance.blockId, 'blk1');
        expect(
          instance.getAttribute(const SdQName('transform')),
          'translate(5.0,7.0)',
        );
        expect(instance.blockPorts, hasLength(stencil.ports.length));

        // Every direct child must be a real, renderable SVG shape — never
        // an empty/unknown tag that would silently vanish on screen.
        expect(instance.children, isNotEmpty);
        for (final child in instance.childElements) {
          expect(
            _svgShapeTags,
            contains(child.name.local),
            reason: '${stencil.id} child ${child.name.local}',
          );
        }
      });
    }
  });

  test(
    'a delay-family stencil has directFeedthrough=false; everything else true',
    () {
      for (final s in corePrimitiveStencils) {
        final expected = s.id == 'delay' || s.id == 'continuous-delay'
            ? false
            : true;
        expect(s.directFeedthrough, expected, reason: s.id);
      }
    },
  );

  test(
    'instance params override the stencil defaults, merged not replaced',
    () {
      final instance = gain.instantiate(
        instanceId: 'g1',
        params: {'gain': 2.5},
      );
      expect(instance.blockParams['gain'], 2.5);

      final defaultInstance = gain.instantiate(instanceId: 'g2');
      expect(defaultInstance.blockParams['gain'], 1.0);
    },
  );

  test('gain renders its param value as the triangle label', () {
    final instance = gain.instantiate(instanceId: 'g1', params: {'gain': 'k'});
    final label = instance.childElements.firstWhere(
      (e) => e.name.local == 'text',
    );
    expect(_textOf(label), 'k');
  });

  test('delay renders z with a superscript-minus exponent from k', () {
    expect(
      _textOf(delay.instantiate(instanceId: 'd1').childElements.last),
      'z⁻¹',
    );
    expect(
      _textOf(
        delay
            .instantiate(instanceId: 'd2', params: {'k': 3})
            .childElements
            .last,
      ),
      'z⁻³',
    );
  });

  test('adder places one sign label per configured sign', () {
    final oneSign = adder.instantiate(
      instanceId: 'a1',
      params: {
        'signs': ['-'],
      },
    );
    expect(
      oneSign.childElements.where((e) => e.name.local == 'text'),
      hasLength(1),
    );

    final twoSigns = adder.instantiate(instanceId: 'a2');
    expect(
      twoSigns.childElements.where((e) => e.name.local == 'text'),
      hasLength(2),
    );
  });

  test('pickoff node switches shape fill based on the filled param', () {
    final filled = pickoffNode.instantiate(instanceId: 'p1');
    final circle1 = filled.childElements.single;
    expect(circle1.getAttribute(const SdQName('fill')), '#1a1a1a');

    final open = pickoffNode.instantiate(
      instanceId: 'p2',
      params: {'filled': false},
    );
    final circle2 = open.childElements.single;
    expect(circle2.getAttribute(const SdQName('fill')), '#ffffff');
  });

  test('port directions and ids round-trip through sd:ports JSON exactly', () {
    final instance = delay.instantiate(instanceId: 'd1');
    expect(instance.blockPorts, [
      {
        'id': 'in1',
        'dir': 'in',
        'dtype': 'real',
        'vlen': 1,
        'x': 0.0,
        'y': 40.0,
        'angle': 180.0,
      },
      {
        'id': 'out1',
        'dir': 'out',
        'dtype': 'real',
        'vlen': 1,
        'x': 80.0,
        'y': 40.0,
        'angle': 0.0,
      },
    ]);
  });
}
