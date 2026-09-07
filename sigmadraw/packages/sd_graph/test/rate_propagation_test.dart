import 'package:sd_graph/sd_graph.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  test('a plain chain keeps the source rate all the way through', () {
    final graph = SignalGraph(
      blocks: {
        'src': block('src', 'source', ports: [outPort('out1')]),
        'g': block('g', 'gain', ports: [inPort('in1'), outPort('out1')]),
        'snk': block('snk', 'sink', ports: [inPort('in1')]),
      },
      edges: [edge('e1', 'src:out1', 'g:in1'), edge('e2', 'g:out1', 'snk:in1')],
    );
    final result = propagateRates(graph, baseRate: SampleRate.symbol('Fs'));
    expect(result.issues, isEmpty);
    expect(result.rates['g'], SampleRate.symbol('Fs'));
    expect(result.rates['snk'], SampleRate.symbol('Fs'));
  });

  test('an upsampler multiplies the rate by its L param', () {
    final graph = SignalGraph(
      blocks: {
        'src': block('src', 'source', ports: [outPort('out1')]),
        'up': block(
          'up',
          'upsampler',
          ports: [inPort('in1'), outPort('out1')],
          params: {'L': 3},
        ),
      },
      edges: [edge('e1', 'src:out1', 'up:in1')],
    );
    final result = propagateRates(graph, baseRate: SampleRate.symbol('Fs'));
    expect(
      result.rates['up'],
      const SampleRate(numerator: 3, denominator: 1, baseSymbol: 'Fs'),
    );
  });

  test('a downsampler divides the rate by its M param', () {
    final graph = SignalGraph(
      blocks: {
        'src': block('src', 'source', ports: [outPort('out1')]),
        'down': block(
          'down',
          'downsampler',
          ports: [inPort('in1'), outPort('out1')],
          params: {'M': 4},
        ),
      },
      edges: [edge('e1', 'src:out1', 'down:in1')],
    );
    final result = propagateRates(graph, baseRate: SampleRate.symbol('Fs'));
    expect(
      result.rates['down'],
      const SampleRate(numerator: 1, denominator: 4, baseSymbol: 'Fs'),
    );
  });

  test('merging two paths at different rates is flagged as a conflict', () {
    final graph = SignalGraph(
      blocks: {
        'src': block('src', 'source', ports: [outPort('out1')]),
        'up': block(
          'up',
          'upsampler',
          ports: [inPort('in1'), outPort('out1')],
          params: {'L': 2},
        ),
        'add': block(
          'add',
          'adder',
          ports: [inPort('in1'), inPort('in2'), outPort('out1')],
        ),
      },
      edges: [
        edge('e1', 'src:out1', 'up:in1'),
        edge('e2', 'up:out1', 'add:in1'),
        edge(
          'e3',
          'src:out1',
          'add:in2',
        ), // Fs directly, vs 2*Fs via the upsampler
      ],
    );
    final result = propagateRates(graph, baseRate: SampleRate.symbol('Fs'));
    expect(result.issues, isNotEmpty);
    expect(result.issues.single.message, contains('conflict'));
  });

  test(
    'an up then matching down returns to the original rate, no conflict',
    () {
      final graph = SignalGraph(
        blocks: {
          'src': block('src', 'source', ports: [outPort('out1')]),
          'up': block(
            'up',
            'upsampler',
            ports: [inPort('in1'), outPort('out1')],
            params: {'L': 2},
          ),
          'down': block(
            'down',
            'downsampler',
            ports: [inPort('in1'), outPort('out1')],
            params: {'M': 2},
          ),
        },
        edges: [
          edge('e1', 'src:out1', 'up:in1'),
          edge('e2', 'up:out1', 'down:in1'),
        ],
      );
      final result = propagateRates(graph, baseRate: SampleRate.symbol('Fs'));
      expect(result.issues, isEmpty);
      expect(result.rates['down'], SampleRate.symbol('Fs'));
    },
  );
}
