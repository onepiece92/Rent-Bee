import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unit_ledger/ui/widgets/glass_dialog.dart';
import 'package:unit_ledger/ui/widgets/typed_confirm_dialog.dart';

/// The Erase-all confirmation must not be a single tap: the destructive
/// button only enables once the person has typed the word.
void main() {
  Future<bool?> open(WidgetTester tester) async {
    bool? result;
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        if (!opened) {
          opened = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            result = await showGlassDialog<bool>(
              context,
              (_) => const TypedConfirmDialog(
                title: 'Erase all data?',
                message: 'Everything goes.',
                word: 'ERASE',
                confirmLabel: 'Erase',
              ),
            );
          });
        }
        return const Scaffold();
      }),
    ));
    await tester.pumpAndSettle();
    return result;
  }

  TextButton eraseButton(WidgetTester tester) => tester.widget<TextButton>(
      find.ancestor(of: find.text('Erase'), matching: find.byType(TextButton)));

  testWidgets('Erase stays disabled until the word is typed', (tester) async {
    await open(tester);
    expect(eraseButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'eras');
    await tester.pump();
    expect(eraseButton(tester).onPressed, isNull);

    // Case and whitespace don't matter — a phone keyboard may add either.
    await tester.enterText(find.byType(TextField), ' erase ');
    await tester.pump();
    expect(eraseButton(tester).onPressed, isNotNull);
  });

  testWidgets('a typed confirmation resolves true; cancel resolves false',
      (tester) async {
    bool? result;
    Future<void> run(Future<void> Function() act) async {
      var opened = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          if (!opened) {
            opened = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              result = await showGlassDialog<bool>(
                context,
                (_) => const TypedConfirmDialog(
                  title: 'Erase all data?',
                  message: 'Everything goes.',
                  word: 'ERASE',
                  confirmLabel: 'Erase',
                ),
              );
            });
          }
          return const Scaffold();
        }),
      ));
      await tester.pumpAndSettle();
      await act();
      await tester.pumpAndSettle();
    }

    await run(() async {
      await tester.enterText(find.byType(TextField), 'ERASE');
      await tester.pump();
      await tester.tap(find.text('Erase'));
    });
    expect(result, isTrue);

    await run(() async => tester.tap(find.text('Cancel')));
    expect(result, isFalse);
  });
}
