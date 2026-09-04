import 'package:sd_document/sd_document.dart';
import 'package:sd_stencils/sd_stencils.dart';
import 'package:test/test.dart';

const _svgShapeTags = {'circle', 'rect', 'line', 'polygon', 'path', 'text'};

void main() {
  // Deduplicated by id: adaptiveStencils deliberately re-lists
  // correlator (comms.dart) — see that file's own doc comment — which
  // would otherwise register two identically-named tests below for the
  // exact same stencil.
  final allExtended = <String, StencilDefinition>{
    for (final s in [
      ...quantizationStencils,
      ...controlStencils,
      ...hardwareStencils,
      ...transformStencils,
      ...commsStencils,
      ...adaptiveStencils,
    ])
      s.id: s,
  }.values.toList();

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

  test('hybrid90 and iqDemodulator each have one input and two outputs '
      '(the same multi-output shape as the butterfly)', () {
    for (final s in [hybrid90, iqDemodulator]) {
      expect(
        s.ports.where((p) => p.direction == PortDirection.input),
        hasLength(1),
        reason: s.id,
      );
      expect(
        s.ports.where((p) => p.direction == PortDirection.output),
        hasLength(2),
        reason: s.id,
      );
    }
  });

  test('lms and rls each have a signal input, an error input, and one '
      'output', () {
    for (final s in [lms, rls]) {
      expect(s.ports.map((p) => p.id), containsAll(['in1', 'error', 'out1']));
      expect(
        s.ports.where((p) => p.direction == PortDirection.output),
        hasLength(1),
        reason: s.id,
      );
    }
  });

  test('every stateful §5.7/§5.8 block reports directFeedthrough: false', () {
    for (final s in [
      integrateAndDump,
      vco,
      costasLoop,
      agc,
      equalizer,
      interleaver,
      deinterleaver,
      correlator,
      lms,
      rls,
      estimator,
    ]) {
      expect(s.directFeedthrough, isFalse, reason: s.id);
    }
  });

  test('mixer has a signal input and a local-oscillator input', () {
    expect(mixer.ports.map((p) => p.id), containsAll(['in1', 'lo', 'out1']));
  });

  test('StencilRegistry.builtIn includes every Phase 7 stencil', () {
    final registry = StencilRegistry.builtIn();
    for (final stencil in allExtended) {
      expect(registry.byId(stencil.id), same(stencil));
    }
  });
}
