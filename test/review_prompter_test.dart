import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unit_ledger/data/review_prompter.dart';

void main() {
  late SharedPreferences prefs;
  late int asks;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    asks = 0;
    now = DateTime(2026, 1, 1);
  });

  ReviewPrompter prompter({Future<void> Function()? request}) => ReviewPrompter(
      prefs,
      request: request ?? () async => asks++,
      now: () => now);

  Future<void> record(ReviewPrompter p, int times) async {
    for (var i = 0; i < times; i++) {
      await p.paymentRecorded();
    }
  }

  test('asks once, on the fifth recorded payment', () async {
    final p = prompter();
    await record(p, 4);
    expect(asks, 0);
    await record(p, 1);
    expect(asks, 1);
    await record(p, 10);
    expect(asks, 1);
  });

  test('the count survives a restart', () async {
    await record(prompter(), 3);
    await record(prompter(), 2);
    expect(asks, 1);
  });

  test('asks again only after 30 more payments and 120 days', () async {
    final p = prompter();
    await record(p, 5);
    // Enough payments, too soon.
    await record(p, 30);
    expect(asks, 1);
    // Enough time has passed: the next payment asks.
    now = now.add(const Duration(days: 121));
    await record(p, 1);
    expect(asks, 2);
    // Enough time, too few payments since the last ask.
    now = now.add(const Duration(days: 200));
    await record(p, 29);
    expect(asks, 2);
    await record(p, 1);
    expect(asks, 3);
  });

  test('a failing store request never throws into the payment flow', () async {
    final p = prompter(request: () async => throw StateError('no store'));
    await record(p, 5);
    // Marked as asked, so the failure is not retried on every payment.
    await record(prompter(), 5);
    expect(asks, 0);
  });
}
