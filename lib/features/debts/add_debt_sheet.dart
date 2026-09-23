import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/amount_input.dart';
import '../../core/app_config.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import 'debt_labels.dart';
import 'debt_providers.dart';

/// Opens the add-debt form. Returns the new debt's id, or null if cancelled.
Future<String?> showAddDebtSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => const AddDebtSheet(),
  );
}

class AddDebtSheet extends ConsumerStatefulWidget {
  const AddDebtSheet({super.key});

  @override
  ConsumerState<AddDebtSheet> createState() => _AddDebtSheetState();
}

class _AddDebtSheetState extends ConsumerState<AddDebtSheet> {
  static String get _currency => kDefaultCurrency;

  final _name = TextEditingController();
  final _lender = TextEditingController();
  final _owed = TextEditingController();
  final _original = TextEditingController();
  final _monthly = TextEditingController();

  DebtType? _type;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _lender, _owed, _original, _monthly]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _owedMinor => parseAmountMinor(_owed.text, _currency);

  bool get _canSave =>
      !_saving &&
      _type != null &&
      _name.text.trim().isNotEmpty &&
      _owedMinor > 0;

  void _selectType(DebtType type) {
    setState(() {
      // Fill in the name automatically if the user hasn't typed one.
      final previousLabel = _type?.label;
      if (_name.text.trim().isEmpty || _name.text == previousLabel) {
        _name.text = type.label;
      }
      _type = type;
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    final navigator = Navigator.of(context);
    final original = parseAmountMinor(_original.text, _currency);
    final monthly = parseAmountMinor(_monthly.text, _currency);
    final lender = _lender.text.trim();

    try {
      final id = await ref.read(debtsRepositoryProvider).add(
            name: _name.text.trim(),
            type: _type!,
            owedNowMinor: _owedMinor,
            currency: _currency,
            lender: lender.isEmpty ? null : lender,
            originalMinor: original > 0 ? original : null,
            monthlyPaymentMinor: monthly > 0 ? monthly : null,
          );
      navigator.pop(id);
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the debt. ($e)')),
      );
    }
  }

  InputDecoration _decoration(
    String label, {
    String? hint,
    String? helper,
    bool money = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 3,
      prefixText: money ? '${Money.symbol(_currency)} ' : null,
      filled: true,
      fillColor: AppColors.foam,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final amountFormatter = amountInputFormatter(_currency);
    final amountKeyboard = TextInputType.numberWithOptions(
      decimal: Money.fractionDigits(_currency) > 0,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add a debt',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Text(
              'What kind of debt is it?',
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in DebtType.values)
                  ChoiceChip(
                    avatar: Icon(
                      type.icon,
                      size: 18,
                      color: _type == type ? AppColors.deepWater : AppColors.mist,
                    ),
                    label: Text(type.label),
                    selected: _type == type,
                    showCheckmark: false,
                    selectedColor: AppColors.shallows,
                    backgroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    side: BorderSide(
                      color: _type == type ? AppColors.tide : AppColors.line,
                    ),
                    onSelected: (_) => _selectType(type),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration('Name', hint: 'e.g. Toyota loan'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lender,
              textCapitalization: TextCapitalization.words,
              decoration: _decoration(
                'Who do you owe? (optional)',
                hint: 'A bank, a school, or a person',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _owed,
              keyboardType: amountKeyboard,
              inputFormatters: [amountFormatter],
              decoration: _decoration('How much do you owe now?', money: true),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _original,
              keyboardType: amountKeyboard,
              inputFormatters: [amountFormatter],
              decoration: _decoration(
                'Amount you first borrowed (optional)',
                money: true,
                helper:
                    'If you have already paid some off, enter the full amount you borrowed so that progress counts too.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _monthly,
              keyboardType: amountKeyboard,
              inputFormatters: [amountFormatter],
              decoration: _decoration(
                'Monthly payment (optional)',
                money: true,
                helper: 'Used to estimate when you will be debt-free.',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _canSave ? _save : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save debt'),
            ),
          ],
        ),
      ),
    );
  }
}
