import 'package:sd_document/sd_document.dart';

const _arrowMarkerId = 'sd-arrow';

/// Ensures [document] has a standard arrowhead `<marker>` definition (in
/// its first `<defs>`, creating one if absent) and returns its id, ready
/// to use as `marker-end="url(#<id>)"` on an edge's path — §5.1's
/// "directed edge + arrowhead". Idempotent: safe to call before placing
/// every edge.
String ensureArrowMarker(SdDocument document) {
  for (final e in document.root.descendantElements) {
    if (e.name.local == 'marker' &&
        e.getAttribute(const SdQName('id')) == _arrowMarkerId) {
      return _arrowMarkerId;
    }
  }

  SdElement? defs;
  for (final e in document.root.childElements) {
    if (e.name.local == 'defs') {
      defs = e;
      break;
    }
  }
  if (defs == null) {
    defs = SdElement(const SdQName('defs'));
    document.root.insertChildAt(0, defs);
  }

  defs.appendChild(
    SdElement(
      const SdQName('marker'),
      attributes: {
        const SdQName('id'): _arrowMarkerId,
        const SdQName('viewBox'): '0 0 10 10',
        const SdQName('refX'): '9',
        const SdQName('refY'): '5',
        const SdQName('markerWidth'): '7',
        const SdQName('markerHeight'): '7',
        const SdQName('orient'): 'auto',
      },
      children: [
        SdElement(
          const SdQName('path'),
          attributes: {
            const SdQName('d'): 'M0,0 L10,5 L0,10 Z',
            const SdQName('fill'): '#1a1a1a',
          },
        ),
      ],
    ),
  );
  return _arrowMarkerId;
}
