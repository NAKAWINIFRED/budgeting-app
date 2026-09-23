import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/main_scaffold.dart';
import '../../app/theme.dart';
import '../../core/amount_input.dart';
import '../../core/app_config.dart';
import '../../core/currencies.dart';
import '../../core/money.dart';
import '../../data/database_provider.dart';
import '../../data/key_values.dart';
import '../dashboard/dashboard_providers.dart';
import '../onboarding/onboarding_screen.dart' show PayRhythm, PayRhythmX;
import 'export_csv.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _exporting = false;

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  PayRhythm? get _rhythm => PayRhythm.values
      .where((r) => r.name == AppConfig.payRhythm)
      .firstOrNull;

  // --------------------------------------------------------------------------

  Future<void> _editName() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(
        title: 'Your name',
        initial: AppConfig.userName ?? '',
        hint: 'Your first name',
        capitalization: TextCapitalization.words,
      ),
    );
    if (result == null) return;
    AppConfig.userName = result.isEmpty ? null : result;
    await _store.set(SettingKeys.userName, result);
    setState(() {});
  }

  Future<void> _editCurrency() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => const _CurrencyPicker(),
    );
    if (code == null || code == AppConfig.currency) return;
    AppConfig.currency = code;
    await _store.set(SettingKeys.currency, code);
    // Recalculate screens that show money.
    ref.invalidate(dashboardSummaryProvider);
    ref.invalidate(monthSummaryProvider);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Now showing amounts in ${currencyName(code)}. Existing entries '
          'keep their numbers and are not converted.',
        ),
      ),
    );
  }

  Future<void> _editRhythm() async {
    final picked = await showModalBottomSheet<PayRhythm>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final r in PayRhythm.values)
              ListTile(
                leading: Icon(r.icon, color: AppColors.deepWater),
                title: Text(r.title),
                subtitle: Text(r.subtitle),
                trailing: r == _rhythm
                    ? const Icon(Icons.check_circle_rounded, color: AppColors.tide)
                    : null,
                onTap: () => Navigator.of(context).pop(r),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    AppConfig.payRhythm = picked.name;
    await _store.set(SettingKeys.payRhythm, picked.name);
    setState(() {});
  }

  Future<void> _editTypicalIncome() async {
    final currency = kDefaultCurrency;
    final current = AppConfig.typicalIncomeMinor;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(
        title: 'Typical monthly income',
        initial: current == null
            ? ''
            : Money.fromMinor(current, currency).round().toString(),
        keyboardType: TextInputType.numberWithOptions(
          decimal: Money.fractionDigits(currency) > 0,
        ),
        formatters: [amountInputFormatter(currency)],
        prefix: '${Money.symbol(currency)} ',
        helper: 'A rough number is fine.',
      ),
    );
    if (result == null) return;
    final minor = parseAmountMinor(result, currency);
    AppConfig.typicalIncomeMinor = minor > 0 ? minor : null;
    await _store.set(SettingKeys.typicalIncome, minor > 0 ? '$minor' : '');
    setState(() {});
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final path = await exportTransactionsCsv(ref.read(appDatabaseProvider));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'text/csv')],
          subject: 'My Tidewise transactions',
          text: 'My Tidewise transactions (opens in Excel or Google Sheets).',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export. ($e)')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _erase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _EraseDialog(),
    );
    if (confirmed != true) return;

    await ref.read(appDatabaseProvider).eraseEverything();
    AppConfig.userName = null;
    AppConfig.payRhythm = null;
    AppConfig.typicalIncomeMinor = null;
    AppConfig.onboardingDone = false;
    if (mounted) context.go('/welcome');
  }

  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final typical = AppConfig.typicalIncomeMinor;

    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 6),
          child: Text(
            title.toUpperCase(),
            style: text.labelSmall?.copyWith(
              color: AppColors.mist,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        );

    Widget tile({
      required IconData icon,
      required String title,
      String? value,
      VoidCallback? onTap,
      Color? color,
      Widget? trailing,
    }) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: Icon(icon, color: color ?? AppColors.deepWater),
        title: Text(
          title,
          style: text.bodyLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: value == null
            ? null
            : Text(value, style: text.bodyMedium?.copyWith(color: AppColors.mist)),
        trailing: trailing ??
            (onTap == null
                ? null
                : const Icon(Icons.chevron_right_rounded, color: AppColors.mist)),
        onTap: onTap,
      );
    }

    return MainScaffold(
      title: 'Settings',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 112),
        children: [
          section('You'),
          tile(
            icon: Icons.person_outline_rounded,
            title: 'Name',
            value: AppConfig.userName ?? 'Not set',
            onTap: _editName,
          ),
          section('Money'),
          tile(
            icon: Icons.currency_exchange_rounded,
            title: 'Currency',
            value: '${currencyName(AppConfig.currency)} (${AppConfig.currency})',
            onTap: _editCurrency,
          ),
          tile(
            icon: _rhythm?.icon ?? Icons.event_repeat_rounded,
            title: 'How you get paid',
            value: _rhythm?.title ?? 'Not set',
            onTap: _editRhythm,
          ),
          tile(
            icon: Icons.south_west_rounded,
            title: 'Typical monthly income',
            value: typical == null
                ? 'Not set'
                : Money.format(typical, AppConfig.currency),
            onTap: _editTypicalIncome,
          ),
          section('Planning'),
          tile(
            icon: Icons.donut_large_rounded,
            title: 'Budget plan',
            onTap: () => context.go('/plan'),
          ),
          tile(
            icon: Icons.tune_rounded,
            title: 'Categories',
            onTap: () => context.go('/categories'),
          ),
          tile(
            icon: Icons.autorenew_rounded,
            title: 'Subscriptions & bill reminders',
            onTap: () => context.go('/expenses/subscriptions'),
          ),
          section('Your data'),
          tile(
            icon: Icons.ios_share_rounded,
            title: 'Export transactions',
            value: 'A spreadsheet file (CSV) you can open in Excel or '
                'Google Sheets, or keep as a backup',
            onTap: _exporting ? null : _export,
            trailing: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          tile(
            icon: Icons.delete_forever_outlined,
            title: 'Erase everything and start over',
            color: AppColors.buoyRed,
            onTap: _erase,
          ),
          section('About'),
          tile(
            icon: Icons.lock_outline_rounded,
            title: 'Private by design',
            value: 'Your data is stored only on this phone. Tidewise does '
                'not send it anywhere.',
          ),
          tile(
            icon: Icons.waves_rounded,
            title: 'Tidewise',
            value: 'Version 1.0.0',
          ),
        ],
      ),
    );
  }
}

/// Searchable currency list in a bottom sheet. Returns the chosen code.
class _CurrencyPicker extends StatefulWidget {
  const _CurrencyPicker();

  @override
  State<_CurrencyPicker> createState() => _CurrencyPickerState();
}

class _CurrencyPickerState extends State<_CurrencyPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final q = _search.text.trim().toLowerCase();
    final list = currencies
        .where(
          (c) =>
              q.isEmpty ||
              c.$1.toLowerCase().contains(q) ||
              c.$2.toLowerCase().contains(q),
        )
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Currency',
                    style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Changing it does not convert amounts you already recorded.',
                    style: text.bodySmall?.copyWith(color: AppColors.amber),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Search',
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.foam,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final (code, name) = list[i];
                  final selected = code == AppConfig.currency;
                  return ListTile(
                    title: Text(name),
                    subtitle: Text(code),
                    trailing: selected
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.tide)
                        : null,
                    onTap: () => Navigator.of(context).pop(code),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// DIALOGS
// Each dialog owns its text controller and disposes it only once the dialog
// has fully closed. (Disposing it right after showDialog returns crashes,
// because the closing animation is still using it.)
// ============================================================================

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.initial,
    this.hint,
    this.helper,
    this.prefix,
    this.keyboardType,
    this.formatters,
    this.capitalization = TextCapitalization.none,
  });

  final String title;
  final String initial;
  final String? hint;
  final String? helper;
  final String? prefix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? formatters;
  final TextCapitalization capitalization;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: widget.capitalization,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.formatters,
        decoration: InputDecoration(
          hintText: widget.hint,
          helperText: widget.helper,
          prefixText: widget.prefix,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _EraseDialog extends StatefulWidget {
  const _EraseDialog();

  @override
  State<_EraseDialog> createState() => _EraseDialogState();
}

class _EraseDialogState extends State<_EraseDialog> {
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(
        Icons.warning_amber_rounded,
        color: AppColors.buoyRed,
        size: 36,
      ),
      title: const Text('Erase everything?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently deletes all your income, expenses, savings, '
            'investments, debts, subscriptions and settings. It cannot be '
            'undone. Consider exporting your data first.',
          ),
          const SizedBox(height: 12),
          const Text('Type ERASE to confirm.'),
          TextField(
            controller: _confirm,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.buoyRed),
          onPressed: _confirm.text.trim() == 'ERASE'
              ? () => Navigator.of(context).pop(true)
              : null,
          child: const Text('Erase'),
        ),
      ],
    );
  }
}