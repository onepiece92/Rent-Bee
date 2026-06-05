import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/database.dart';
import '../../domain/bs_calendar.dart';
import '../../domain/money.dart';
import '../widgets/toast.dart';

/// The SMS body for [unit]'s rent in BS [month]: a polite due-reminder when
/// unpaid, a thank-you when already collected.
String rentReminderText(Unit unit, BsMonth month, {required bool paid}) {
  final amount = Money.format(unit.monthlyRent);
  if (paid) {
    return 'Hi ${unit.tenantName}, thank you — we have received your '
        '${month.monthName} ${month.year} rent of $amount.';
  }
  return 'Hi ${unit.tenantName}, gentle reminder: rent of $amount for '
      '${month.monthName} ${month.year} is due. Thank you!';
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
  final ok = await launchUrl(uri);
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
}) async {
  final phone = unit.phone;
  if (phone == null || phone.isEmpty) return;
  await sendSms(context, phone,
      body: rentReminderText(unit, month, paid: paid));
}
