import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/app/theme.dart';
import 'package:unit_ledger/ui/widgets/tap_target.dart';

/// Pins the HIG rules adopted from the Apple brand kit review (2026-09-22):
/// 44 pt hit areas, Reduce Motion collapsing animation, and the 11 pt text
/// floor — the last as a source scan, so a new `fontSize: 10` can't creep in.
void main() {
  group('HIG conformance', () {
    testWidgets('TapTarget gives a small control a 44 pt hit area',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: TapTarget(
            onTap: () => taps++,
            child: const SizedBox(width: 30, height: 30),
          ),
        ),
      ));
      expect(tester.getSize(find.byType(TapTarget)),
          const Size(Sys.minTapTarget, Sys.minTapTarget));
      // A tap in the padding, outside the 30 pt visual, still lands.
      final rect = tester.getRect(find.byType(TapTarget));
      await tester.tapAt(rect.topLeft + const Offset(3, 3));
      expect(taps, 1);
    });

    testWidgets('Motion.duration collapses to zero under Reduce Motion',
        (tester) async {
      Duration? normal, reduced;
      Widget probe(bool disable, void Function(Duration) sink) => MediaQuery(
            data: MediaQueryData(disableAnimations: disable),
            child: Builder(builder: (context) {
              sink(Motion.duration(context, Motion.moveDuration));
              return const SizedBox();
            }),
          );
      await tester.pumpWidget(probe(false, (d) => normal = d));
      await tester.pumpWidget(probe(true, (d) => reduced = d));
      expect(normal, Motion.moveDuration);
      expect(reduced, Duration.zero);
    });

    test('no UI text is set below the HIG minimum size', () {
      final re = RegExp(r'fontSize:\s*([0-9]+(?:\.[0-9]+)?)');
      final offenders = <String>[];
      for (final dir in ['lib/ui', 'lib/app']) {
        final files = Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'));
        for (final f in files) {
          final lines = f.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            for (final m in re.allMatches(lines[i])) {
              if (double.parse(m.group(1)!) < Sys.minFontSize) {
                offenders.add('${f.path}:${i + 1}: ${m.group(0)}');
              }
            }
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'HIG minimum text size is ${Sys.minFontSize} pt');
    });
  });
}
