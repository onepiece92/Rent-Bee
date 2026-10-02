import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/app/theme.dart';
import 'package:unit_ledger/ui/widgets/glass_dialog.dart';

/// An alert must always keep its actions on screen: a long message — or the
/// keyboard — shrinks and scrolls the content instead of pushing the buttons
/// off the bottom edge. (buglog B16.) Its body text uses the full label
/// colour on a near-opaque surface. (buglog B31.)
void main() {
  Future<void> open(WidgetTester tester,
      {required Size size, double keyboard = 0, int lines = 60}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(viewInsets: EdgeInsets.only(bottom: keyboard)),
          child: GlassDialog(
            title: 'Restore backup?',
            content: Text(
                [for (var i = 0; i < lines; i++) 'Line $i of the warning.']
                    .join('\n')),
            actions: [
              GlassDialogAction('Cancel', onPressed: () {}),
              GlassDialogAction('Restore',
                  destructive: true, onPressed: () {}),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('a long message scrolls; the actions stay on screen',
      (tester) async {
    await open(tester, size: const Size(390, 640));
    expect(tester.takeException(), isNull, reason: 'used to overflow');
    final restore = tester.getRect(find.text('Restore'));
    expect(restore.bottom, lessThanOrEqualTo(640 - 24));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    // The content really is scrollable (taller than its viewport).
    final scrollable = tester.state<ScrollableState>(find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable)));
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('with the keyboard up the actions sit above it', (tester) async {
    await open(tester, size: const Size(390, 640), keyboard: 300);
    expect(tester.takeException(), isNull);
    final restore = tester.getRect(find.text('Restore'));
    expect(restore.bottom, lessThanOrEqualTo(640 - 300));
  });

  testWidgets('a short message keeps the alert compact', (tester) async {
    await open(tester, size: const Size(390, 844), lines: 2);
    final title = tester.getRect(find.text('Restore backup?'));
    final restore = tester.getRect(find.text('Restore'));
    expect(restore.bottom - title.top, lessThan(200));
  });

  testWidgets('body text uses the primary label colour', (tester) async {
    await open(tester, size: const Size(390, 844), lines: 2);
    final context = tester.element(find.textContaining('Line 0'));
    expect(DefaultTextStyle.of(context).style.color, Sys.of(context).label);
  });
}
