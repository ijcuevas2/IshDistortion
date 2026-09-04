import 'package:sd_document/sd_document.dart';
import 'package:sd_stencils/sd_stencils.dart';
import 'package:test/test.dart';

const _svgShapeTags = {'circle', 'rect', 'line', 'polygon', 'path', 'text'};

void main() {
  final allExtended = [
    ...quantizationStencils,
    ...controlStencils,
    ...hardwareStencils,
    ...transformStencils,
  ];

  group('every Phase 7 leaf stencil', () {
    for (final stencil in allExtended) {
      test('${stencil.id}: instantiates a valid dual-representation block', () {
        final instance = stencil.instantiate(instanceId: 'blk1');
        expect(instance.blockType, stencil.id);
        expect(instance.children, isNotEmpty);
        for (final child in instance.childElements) {
          expect(
            _svgShapeTags,
            contains(child.name.local),
            reason: '${stencil.id} child ${child.name.local}',
          );
        }
        // Every port position must lie within (or exactly on the edge of)
        // the stencil's own declared footprint — a basic sanity check that
        // ports weren't left over from copy-pasting a different stencil's
        // geometry (see the systolic-cell width/ports bug this caught).
        for (final port in stencil.ports) {
          expect(
            port.x,
            inInclusiveRange(0, stencil.width),
            reason: '${stencil.id}:${port.id} x',
          );
          expect(
            port.y,
            inInclusiveRange(0, stencil.height),
            reason: '${stencil.id}:${port.id} y',
          );
        }
      });
    }
  });

  test('accumulator and register have state (directFeedthrough: false)', () {
    expect(accumulator.directFeedthrough, isFalse);
    expect(register.directFeedthrough, isFalse);
  });

  test('the integrator has state; the differentiator does not', () {
    expect(integrator.directFeedthrough, isFalse);
    expect(differentiator.directFeedthrough, isTrue);
  });

  test('the butterfly has two inputs and two outputs', () {
    expect(
      butterfly.ports.where((p) => p.direction == PortDirection.input),
      hasLength(2),
    );
    expect(
      butterfly.ports.where((p) => p.direction == PortDirection.output),
      hasLength(2),
    );
  });

  test('StencilRegistry.builtIn includes every Phase 7 stencil', () {
    final registry = StencilRegistry.builtIn();
    for (final stencil in allExtended) {
      expect(registry.byId(stencil.id), same(stencil));
    }
  });
}
