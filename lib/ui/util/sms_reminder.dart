import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/database.dart';
import '../../domain/bs_calendar.dart';
import '../../domain/money.dart';
import '../widgets/toast.dart';

/// The SMS body for [unit]'s rent in BS [month]: a polite due-reminder when
/// unpaid, a thank-you when already collected. [amount] is the month's actual
/// cash due (rent less any deduction) — required, because the headline rent is
/// the wrong figure whenever a deduction exists. A zero amount (the deduction
/// covered the rent, or no rent is set) never quotes "Rs 0".
String rentReminderText(Unit unit, BsMonth month,
    {required bool paid, required int amount}) {
  final when = '${month.monthName} ${month.year}';
  if (paid) {
    return amount > 0
        ? 'Hi ${unit.tenantName}, thank you — we have received your $when '
            'rent of ${Money.format(amount)}.'
        : 'Hi ${unit.tenantName}, thank you — your $when rent is settled.';
  }
  return amount > 0
      ? 'Hi ${unit.tenantName}, gentle reminder: rent of '
          '${Money.format(amount)} for $when is due. Thank you!'
      : 'Hi ${unit.tenantName}, gentle reminder: your $when rent is due. '
          'Thank you!';
}

/// Opens the system Messages composer pre-addressed to [phone], with [body]
/// pre-filled when provided.
Future<void> sendSms(BuildContext context, String phone, {String? body}) async {
  // Strip spaces/dashes; keep digits and a leading '+'.
  final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
  final Uri uri;
  if (body == null || body.isEmpty) {
    uri = Uri(scheme: 'sms', path: cleaned);
  } else {
    // iOS expects the body after '&', Android/others after '?'.
    final sep = defaultTargetPlatform == TargetPlatform.iOS ? '&' : '?';
    uri = Uri.parse('sms:$cleaned${sep}body=${Uri.encodeComponent(body)}');
  }
  // launchUrl can also *throw* (e.g. no SMS handler on the device) — treat
  // that the same as a `false` return rather than crashing the tap.
  bool ok;
  try {
    ok = await launchUrl(uri);
  } on Exception {
    ok = false;
  }
  if (!ok && context.mounted) {
    showToast(context, 'Could not open Messages for $phone', error: true);
  }
}

/// One-tap rent reminder: opens Messages to [unit]'s phone (if on file) with the
/// reminder/thank-you text for BS [month] prefilled. No-op without a number.
Future<void> sendRentReminder(
  BuildContext context,
  Unit unit,
  BsMonth month, {
  required bool paid,
  required int amount,
}) async {
  final phone = unit.phone;
  if (phone == null || phone.isEmpty) return;
  await sendSms(context, phone,
      body: rentReminderText(unit, month, paid: paid, amount: amount));
}
