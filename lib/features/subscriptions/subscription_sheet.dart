import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/amount_input.dart';
import '../../core/app_config.dart';
import '../../core/category_icons.dart';
import '../../core/money.dart';
import '../../core/money_kinds.dart';
import '../../data/database.dart';
import '../categories/categories_repository.dart';
import 'subscriptions_providers.dart';

Future<void> showSubscriptionSheet(
  BuildContext context, {
  Subscription? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => SubscriptionSheet(existing: existing),
  );
}

class SubscriptionSheet extends ConsumerStatefulWidget {
  const SubscriptionSheet({super.key, this.existing});

  final Subscription? existing;

  @override
  ConsumerState<SubscriptionSheet> createState() => _SubscriptionSheetState();
}

class _SubscriptionSheetState extends ConsumerState<SubscriptionSheet> {
  static const _currency = kDefaultCurrency;

  final _name = TextEditingController();
  final _purpose = TextEditingController();
  final _amount = TextEditingController();

  SubscriptionFrequency _frequency = SubscriptionFrequency.monthly;
  DateTime _nextDue = DateTime.now();
  String? _categoryId;
  PaymentMethod? _method;
  int _remindDays = 3;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    if (s == null) return;
    _name.text = s.name;
    _purpose.text = s.purpose ?? '';
    final value = Money.fromMinor(s.amountMinor, _currency);
    _amount.text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(Money.fractionDigits(_currency));
    _frequency = s.frequency;
    _nextDue = s.nextDueDate;
    _categoryId = s.categoryId;
    _method = s.paymentMethod;
    _remindDays = s.remindDaysBefore;
  }

  @override
  void dispose() {
    for (final c in [_name, _purpose, _amount]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _amountMinor => parseAmountMinor(_amount.text, _currency);
  bool get _canSave =>
      !_saving && _name.text.trim().isNotEmpty && _amountMinor > 0;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextDue,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 10),
      helpText: 'When is the next payment due?',
    );
    if (picked != null) setState(() => _nextDue = picked);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final repo = ref.read(subscriptionsRepositoryProvider);
    final navigator = Navigator.of(context);
    final purpose = _purpose.text.trim();
    final due = DateTime(_nextDue.year, _nextDue.month, _nextDue.day, 9);

    final existing = widget.existing;
    if (existing != null) {
      await repo.update(
        existing.copyWith(
          name: _name.text.trim(),
          purpose: Value(purpose.isEmpty ? null : purpose),
          amountMinor: _amountMinor,
          frequency: _frequency,
          nextDueDate: due,
          categoryId: Value(_categoryId),
          paymentMethod: Value(_method),
          remindDaysBefore: _remindDays,
        ),
      );
    } else {
      await repo.add(
        name: _name.text.trim(),
        purpose: purpose.isEmpty ? null : purpose,
        amountMinor: _amountMinor,
        currency: _currency,
        frequency: _frequency,
        nextDueDate: due,
        categoryId: _categoryId,
        paymentMethod: _method,
        remindDaysBefore: _remindDays,
      );
    }
    navigator.pop();
  }

  Future<void> _delete() async {
    final s = widget.existing!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${s.name}?'),
        content: const Text(
          'Past payments stay in your history. Only the reminder is removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.buoyRed),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final navigator = Navigator.of(context);
    await ref.read(subscriptionsRepositoryProvider).delete(s.id);
    navigator.pop();
  }

  InputDecoration _decoration(String label, {String? hint, bool money = false}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: money ? '${Money.symbol(_currency)} ' : null,
      filled: true,
      fillColor: AppColors.foam,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _chip({
    required String label,
    IconData? icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      avatar: icon == null
          ? null
          : Icon(icon, size: 18, color: selected ? AppColors.deepWater : AppColors.mist),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppColors.shallows,
      backgroundColor: Colors.white,
      shape: const StadiumBorder(),
      side: BorderSide(color: selected ? AppColors.tide : AppColors.line),
      onSelected: (_) => onTap(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tree = ref.watch(categoryTreeProvider(CategoryKind.expense));
    Widget title(String t) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(t, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
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
              _isEditing ? 'Edit subscription or bill' : 'New subscription or bill',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration('Name', hint: 'e.g. Netflix, Rent, Gym'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _purpose,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration(
                'What is it for? (optional)',
                hint: 'e.g. Family streaming plan',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.numberWithOptions(
                decimal: Money.fractionDigits(_currency) > 0,
              ),
              inputFormatters: [amountInputFormatter(_currency)],
              decoration: _decoration('Amount each time', money: true),
              onChanged: (_) => setState(() {}),
            ),
            title('How often is it paid?'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in SubscriptionFrequency.values)
                  _chip(
                    label: f.label,
                    selected: _frequency == f,
                    onTap: () => setState(() => _frequency = f),
                  ),
              ],
            ),
            title('Next payment'),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(Icons.event_rounded, size: 18),
                label: Text('Due ${DateFormat.yMMMEd().format(_nextDue)}'),
                onPressed: _pickDate,
              ),
            ),
            title('Remind me'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final days in [1, 3, 7])
                  _chip(
                    label: days == 1 ? '1 day before' : '$days days before',
                    selected: _remindDays == days,
                    onTap: () => setState(() => _remindDays = days),
                  ),
              ],
            ),
            title('Category (optional)'),
            tree.when(
              loading: () => const SizedBox(height: 40),
              error: (e, _) => Text('$e'),
              data: (nodes) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final n in nodes)
                    _chip(
                      label: n.category.name,
                      icon: iconFor(n.category.iconKey),
                      selected: _categoryId == n.category.id,
                      onTap: () => setState(
                        () => _categoryId =
                            _categoryId == n.category.id ? null : n.category.id,
                      ),
                    ),
                ],
              ),
            ),
            title('Paid with (optional)'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in PaymentMethod.values)
                  _chip(
                    label: m.label,
                    icon: m.icon,
                    selected: _method == m,
                    onTap: () => setState(() => _method = _method == m ? null : m),
                  ),
              ],
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
              child: Text(_isEditing ? 'Save changes' : 'Save'),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _saving ? null : _delete,
                style: TextButton.styleFrom(foregroundColor: AppColors.buoyRed),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
