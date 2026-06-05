import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../data/database.dart';
import '../../domain/bs_calendar.dart';
import '../../domain/phone.dart';
import '../../domain/unit_code.dart';
import '../../state/ledger_provider.dart';
import '../../state/settings_provider.dart';
import '../widgets/sheet_scaffold.dart';
import '../widgets/toast.dart';

/// Bottom sheet to add a new unit or edit an existing one.
class EditUnitSheet extends StatefulWidget {
  final Unit? unit; // null = add
  const EditUnitSheet({super.key, this.unit});

  static Future<void> show(BuildContext context, {Unit? unit}) {
    return showGlassSheet(
      context,
      (_) => EditUnitSheet(unit: unit),
    );
  }

  @override
  State<EditUnitSheet> createState() => _EditUnitSheetState();
}

class _EditUnitSheetState extends State<EditUnitSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _tenant;
  late final TextEditingController _business;
  late final TextEditingController _rent;
  late final TextEditingController _phone;
  late final TextEditingController _deposit;
  late bool _active;
  // When the tenant joined / rent started — anchors the annual lease escalation.
  // New units default to today; existing units keep whatever was set (may null).
  DateTime? _startedOn;

  bool get _isEdit => widget.unit != null;

  @override
  void initState() {
    super.initState();
    final s = widget.unit;
    // For a new unit, suggest the next code (e.g. C-02 → C-03) so the owner
    // doesn't have to invent one. Editing keeps the existing code.
    final suggestedCode = s == null
        ? suggestUnitCode(context
            .read<LedgerProvider>()
            .allUnitsByCode
            .map((r) => r.unit.code))
        : s.code;
    _code = TextEditingController(text: suggestedCode);
    _tenant = TextEditingController(text: s?.tenantName ?? '');
    _business = TextEditingController(text: s?.businessType ?? '');
    _rent = TextEditingController(text: s?.monthlyRent.toString() ?? '');
    _phone = TextEditingController(text: s?.phone ?? '');
    _deposit = TextEditingController(
        text: (s == null || s.depositAmount == 0)
            ? ''
            : s.depositAmount.toString());
    _active = s?.isActive ?? true;
    _startedOn = s?.startedOn ?? (s == null ? DateTime.now() : null);
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startedOn ?? now,
      firstDate: DateTime(now.year - 30),
      lastDate: now,
      helpText: 'Rent start / tenant joined',
    );
    if (picked != null) setState(() => _startedOn = picked);
  }

  @override
  void dispose() {
    _code.dispose();
    _tenant.dispose();
    _business.dispose();
    _rent.dispose();
    _phone.dispose();
    _deposit.dispose();
    super.dispose();
  }

  /// Opens the OS contact picker (no permission needed) and fills the phone —
  /// and the tenant name too, if it's still blank — from the chosen contact.
  Future<void> _pickFromContacts() async {
    try {
      final contact = await FlutterNativeContactPicker().selectPhoneNumber();
      if (contact == null) return; // cancelled
      final number = contact.selectedPhoneNumber ??
          (contact.phoneNumbers?.isNotEmpty ?? false
              ? contact.phoneNumbers!.first
              : null);
      if (number != null) _phone.text = normalizePhone(number);
      final name = contact.fullName?.trim() ?? '';
      if (_tenant.text.trim().isEmpty && name.isNotEmpty) _tenant.text = name;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) showToast(context, 'Could not open contacts', error: true);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ledger = context.read<LedgerProvider>();
    final raisePct = context.read<SettingsProvider>().annualRaisePercent;
    final rent = int.tryParse(_rent.text.trim()) ?? 0;
    final cleanedPhone = normalizePhone(_phone.text);
    final phone = cleanedPhone.isEmpty ? null : cleanedPhone;
    final deposit = int.tryParse(_deposit.text.trim()) ?? 0;

    try {
      if (_isEdit) {
        // Editing rent must NOT alter recorded payment amounts — those are
        // captured per record, so updating the unit is safe.
        await ledger.updateUnit(widget.unit!.copyWith(
          code: _code.text.trim(),
          tenantName: _tenant.text.trim(),
          businessType: _business.text.trim(),
          monthlyRent: rent,
          phone: Value(phone),
          isActive: _active,
          startedOn: Value(_startedOn),
          depositAmount: deposit,
        ));
      } else {
        await ledger.createUnit(UnitsCompanion.insert(
          code: _code.text.trim(),
          tenantName: _tenant.text.trim(),
          businessType: Value(_business.text.trim()),
          monthlyRent: rent,
          phone: Value(phone),
          isActive: Value(_active),
          startedOn: Value(_startedOn),
          depositAmount: Value(deposit),
        ));
        // The entered rent is the rent at the start date — grow it to today by
        // applying any due anniversary increases now (not just on next launch).
        if (raisePct > 0) await ledger.applyDueRaises(raisePct);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        showToast(context,
            'Could not save — code "${_code.text.trim()}" may already exist.',
            error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<SettingsProvider>().calendar;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_isEdit ? 'Edit Unit' : 'New Unit',
                style: display(fontSize: 22, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 18),
          _Field(
            controller: _code,
            label: 'Unit no.',
            hint: 'A-05',
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          _Field(
            controller: _tenant,
            label: 'Tenant name',
            hint: 'Full name',
            // The code is pre-suggested, so land the cursor on the first thing
            // the owner actually types. Only on add — not when editing.
            autofocus: !_isEdit,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          _Field(controller: _business, label: 'Business', hint: 'e.g. Grocery'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Field(
                  controller: _rent,
                  label: 'Rent (Rs)',
                  hint: '18000',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null || n < 0) return 'Invalid';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Field(
                  controller: _phone,
                  label: 'Phone',
                  hint: '98…',
                  keyboardType: TextInputType.phone,
                  // Clean spaces/dashes on type or paste, then sanity-check.
                  inputFormatters: [_PhoneInputFormatter()],
                  validator: phoneError,
                  // Tap to pull a number straight from the OS contact picker.
                  suffixIcon: IconButton(
                    tooltip: 'Pick from contacts',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.contact_phone_outlined,
                        size: 18, color: Brand.orange),
                    onPressed: _pickFromContacts,
                  ),
                ),
              ),
            ],
          ),
          _DateField(
            label: 'Rent started',
            value: _startedOn == null ? null : dateLabel(_startedOn!, mode),
            onTap: _pickStartDate,
            onClear: _startedOn == null
                ? null
                : () => setState(() => _startedOn = null),
          ),
          _Field(
            controller: _deposit,
            label: 'Security deposit (Rs)',
            hint: 'e.g. 20000 — leave blank for none',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          SwitchListTile(
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            activeThumbColor: Brand.orange,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Active (counts toward expected)',
                style: TextStyle(fontSize: 13, color: Brand.muted)),
          ),
          const SizedBox(height: 6),
          _SaveButton(label: _isEdit ? 'Save changes' : 'Add Unit', onTap: _save),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SaveButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              gradient: Brand.orangeGradient,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: Brand.orange.withValues(alpha: 0.45),
                  blurRadius: 26,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled, tappable read-only field that opens a date picker. Mirrors the
/// look of [_Field]. A null [value] shows the "Not set" hint; an optional clear
/// affordance appears when a date is set.
class _DateField extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Brand.muted)),
          const SizedBox(height: 6),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: Brand.glassBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Brand.glassBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_outlined,
                      size: 16, color: Brand.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      value ?? 'Not set',
                      style: TextStyle(
                          fontSize: 15,
                          color: value == null
                              ? const Color(0x66FFFFFF)
                              : Colors.white),
                    ),
                  ),
                  if (onClear != null)
                    GestureDetector(
                      onTap: onClear,
                      behavior: HitTestBehavior.opaque,
                      child: const Icon(Icons.close,
                          size: 16, color: Brand.muted),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live-cleans a phone field: on every keystroke or paste it strips spaces,
/// dashes and parens down to digits (plus an optional leading `+`), so the
/// stored number is always tidy and SMS reminders work.
class _PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final cleaned = normalizePhone(newValue.text);
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final bool autofocus;
  final Widget? suffixIcon;

  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.autofocus = false,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Brand.muted)),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            autofocus: autofocus,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            validator: validator,
            style: const TextStyle(fontSize: 15, color: Colors.white),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0x66FFFFFF)),
              suffixIcon: suffixIcon,
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 40, minHeight: 40),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              filled: true,
              fillColor: Brand.glassBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Brand.glassBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Brand.glassBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Brand.orange),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
