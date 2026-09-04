import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';

/// SigmaDraw application entry point.
///
/// This is still an early scaffold: [SigmaDrawHome] wires up a real
/// [SigmaCanvas] (Phase 2 — rendering/pan/zoom/selection) over a small
/// hand-built demo document, standing in for real stencil placement
/// (Phase 3) and the ribbon UI (Phase 5) that will eventually replace it.
void main() {
  runApp(const SigmaDrawApp());
}

class SigmaDrawApp extends StatelessWidget {
  const SigmaDrawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SigmaDraw',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const SigmaDrawHome(),
    );
  }
}

/// A minimal two-block-and-a-wire diagram, just to exercise the Phase 2
/// canvas end to end until Phase 3 adds a real stencil palette.
SdDocument _demoDocument() {
  final doc = createBlankSdDocument(
    width: 400,
    height: 200,
    sampleRate: '48000',
  );
  doc.root.appendChild(
    SdElement(
      const SdQName('g'),
      attributes: {const SdQName('transform'): 'translate(40,70)'},
      children: [
        SdElement(
          const SdQName('circle'),
          attributes: {
            const SdQName('cx'): '30',
            const SdQName('cy'): '30',
            const SdQName('r'): '30',
            const SdQName('fill'): '#ffffff',
            const SdQName('stroke'): '#333333',
            const SdQName('stroke-width'): '2',
          },
        ),
        SdElement(
          const SdQName('text'),
          attributes: {
            const SdQName('x'): '18',
            const SdQName('y'): '36',
            const SdQName('font-size'): '20',
          },
          children: [SdText('+')],
        ),
      ],
    )..blockType = 'adder',
  );
  doc.root.appendChild(
    SdElement(
      const SdQName('path'),
      attributes: {
        const SdQName('d'): 'M100,100 L220,100',
        const SdQName('stroke'): '#333333',
        const SdQName('stroke-width'): '2',
        const SdQName('vector-effect'): 'non-scaling-stroke',
      },
    )..edgeId = 'e1',
  );
  doc.root.appendChild(
    SdElement(
      const SdQName('g'),
      attributes: {const SdQName('transform'): 'translate(220,70)'},
      children: [
        SdElement(
          const SdQName('rect'),
          attributes: {
            const SdQName('width'): '80',
            const SdQName('height'): '60',
            const SdQName('fill'): '#ffffff',
            const SdQName('stroke'): '#333333',
            const SdQName('stroke-width'): '2',
          },
        ),
        SdElement(
          const SdQName('text'),
          attributes: {
            const SdQName('x'): '20',
            const SdQName('y'): '36',
            const SdQName('font-size'): '16',
          },
          children: [SdText('z⁻¹')],
        ),
      ],
    )..blockType = 'delay',
  );
  return doc;
}

class SigmaDrawHome extends StatelessWidget {
  const SigmaDrawHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SigmaDraw')),
      body: SigmaCanvas(document: _demoDocument()),
    );
  }
}
