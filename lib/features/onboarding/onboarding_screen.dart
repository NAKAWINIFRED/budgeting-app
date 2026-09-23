import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/amount_input.dart';
import '../../core/app_config.dart';
import '../../core/currencies.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/key_values.dart';
import '../dashboard/tide_gauge.dart';
import '../debts/add_debt_sheet.dart';
import '../plan/plan_providers.dart';
import '../savings/goal_sheet.dart';
import '../subscriptions/subscription_sheet.dart';
import '../transactions/quick_add_sheet.dart';

/// How someone usually gets paid.
enum PayRhythm { monthly, twiceMonthly, biweekly, weekly, daily, irregular }

extension PayRhythmX on PayRhythm {
  String get title => switch (this) {
        PayRhythm.monthly => 'Once a month',
        PayRhythm.twiceMonthly => 'Twice a month',
        PayRhythm.biweekly => 'Every two weeks',
        PayRhythm.weekly => 'Every week',
        PayRhythm.daily => 'Every day',
        PayRhythm.irregular => 'It varies',
      };

  String get subtitle => switch (this) {
        PayRhythm.monthly => 'A monthly salary or allowance',
        PayRhythm.twiceMonthly => 'For example on the 15th and the 30th',
        PayRhythm.biweekly => 'A paycheck every other week',
        PayRhythm.weekly => 'Weekly wages',
        PayRhythm.daily => 'Daily work, sales or deliveries',
        PayRhythm.irregular => 'Freelance, business, farming, gigs or commission',
      };

  IconData get icon => switch (this) {
        PayRhythm.monthly => Icons.calendar_month_rounded,
        PayRhythm.twiceMonthly => Icons.date_range_rounded,
        PayRhythm.biweekly => Icons.event_repeat_rounded,
        PayRhythm.weekly => Icons.view_week_rounded,
        PayRhythm.daily => Icons.wb_sunny_rounded,
        PayRhythm.irregular => Icons.waves_rounded,
      };

  bool get isUneven => this == PayRhythm.daily || this == PayRhythm.irregular;
}

final _hasTransactionsProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final row = await (db.select(db.transactions)..limit(1)).getSingleOrNull();
  return row != null;
});

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _pageCount = 6;

  final _pages = PageController();
  final _name = TextEditingController();
  final _search = TextEditingController();
  final _typical = TextEditingController();

  int _page = 0;
  late String _currency = deviceCurrency() ?? AppConfig.currency;
  PayRhythm? _rhythm;
  String? _strategyId;
  final Set<String> _started = {};

  @override
  void dispose() {
    for (final c in [_name, _search, _typical]) {
      c.dispose();
    }
    _pages.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Navigation
  // --------------------------------------------------------------------------

  bool get _canContinue => switch (_page) {
        3 => _rhythm != null,
        _ => true,
      };

  String get _buttonLabel => switch (_page) {
        0 => 'Get started',
        4 => 'Use this plan',
        5 => 'Go to my overview',
        _ => 'Continue',
      };

  Future<void> _next() async {
    FocusScope.of(context).unfocus();
    if (_page == 2) {
      // Use the chosen currency straight away (for amounts on later pages).
      AppConfig.currency = _currency;
    }
    if (_page == 4) await _saveSettings();
    if (_page == _pageCount - 1) return _finish();
    _goTo(_page + 1);
  }

  void _back() {
    FocusScope.of(context).unfocus();
    if (_page > 0) _goTo(_page - 1);
  }

  void _goTo(int page) {
    setState(() => _page = page);
    _pages.animateToPage(
      page,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  // --------------------------------------------------------------------------
  // Saving
  // --------------------------------------------------------------------------

  String? _recommendedId(List<StrategyOption> options) {
    final wanted = _rhythm?.isUneven == true ? 'Pay Yourself First' : '50/30/20';
    return options.where((o) => o.strategy.name == wanted).firstOrNull?.strategy.id ??
        options.firstOrNull?.strategy.id;
  }

  Future<void> _saveSettings() async {
    final store = ref.read(keyValueStoreProvider);

    AppConfig.currency = _currency;
    await store.set(SettingKeys.currency, _currency);

    final name = _name.text.trim();
    AppConfig.userName = name.isEmpty ? null : name;
    if (name.isNotEmpty) await store.set(SettingKeys.userName, name);

    if (_rhythm != null) {
      AppConfig.payRhythm = _rhythm!.name;
      await store.set(SettingKeys.payRhythm, _rhythm!.name);
    }

    final typical = parseAmountMinor(_typical.text, _currency);
    if (typical > 0) {
      AppConfig.typicalIncomeMinor = typical;
      await store.set(SettingKeys.typicalIncome, '$typical');
    }

    final options = ref.read(strategyOptionsProvider).value ?? const [];
    final id = _strategyId ?? _recommendedId(options);
    if (id != null) await ref.read(strategiesRepositoryProvider).setActive(id);
  }

  Future<void> _finish() async {
    await ref.read(keyValueStoreProvider).set(SettingKeys.onboardingDone, 'true');
    AppConfig.onboardingDone = true;
    if (mounted) context.go('/');
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.foam,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: _page == 0
                  ? null
                  : Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          icon: const Icon(Icons.arrow_back_rounded),
                          onPressed: _back,
                        ),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: _page / (_pageCount - 1),
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(6),
                            backgroundColor: AppColors.line,
                            color: AppColors.tide,
                          ),
                        ),
                        const SizedBox(width: 56),
                      ],
                    ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _welcomePage(),
                  _namePage(),
                  _currencyPage(),
                  _rhythmPage(),
                  _planPage(),
                  _donePage(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: FilledButton(
                onPressed: _canContinue ? _next : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(_buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scroll(List<Widget> children) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );

  Widget _heading(String title, String subtitle) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: text.bodyLarge?.copyWith(color: AppColors.mist)),
        ],
      ),
    );
  }

  Widget _option({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
    Widget? extra,
    String? badge,
  }) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? AppColors.shallows : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.tide : AppColors.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.deepWater),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.tide,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              badge,
                              style: text.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(subtitle, style: text.bodySmall?.copyWith(color: AppColors.mist)),
                    if (extra != null) ...[const SizedBox(height: 8), extra],
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded, color: AppColors.tide),
            ],
          ),
        ),
      ),
    );
  }

  // 1 -------------------------------------------------------------------------
  Widget _welcomePage() {
    final text = Theme.of(context).textTheme;
    Widget point(IconData icon, String line) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.shallows,
                child: Icon(icon, color: AppColors.deepWater, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(line, style: text.bodyLarge)),
            ],
          ),
        );

    return _scroll([
      const SizedBox(height: 8),
      TideGauge(
        level: 0.62,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.waves_rounded, color: Colors.white, size: 36),
            const SizedBox(height: 8),
            Text(
              'Tidewise',
              style: text.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              'Money comes in and goes out like the tide. '
              'Let us keep yours steady.',
              style: text.bodyLarge?.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      point(Icons.visibility_rounded, 'See where every bit of your money goes'),
      point(Icons.donut_large_rounded, 'A plan that fits how you earn, even if it varies'),
      point(Icons.trending_up_rounded, 'Watch debts shrink and savings grow'),
      const SizedBox(height: 4),
      Text(
        'Your data stays on your phone.',
        style: text.bodySmall?.copyWith(color: AppColors.mist),
      ),
    ]);
  }

  // 2 -------------------------------------------------------------------------
  Widget _namePage() {
    return _scroll([
      _heading(
        'What should we call you?',
        'Just for a friendly hello. You can leave it empty.',
      ),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _next(),
        style: Theme.of(context).textTheme.titleLarge,
        decoration: InputDecoration(
          hintText: 'Your first name',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.line),
          ),
        ),
      ),
    ]);
  }

  // 3 -------------------------------------------------------------------------
  Widget _currencyPage() {
    final text = Theme.of(context).textTheme;
    final query = _search.text.trim().toLowerCase();
    final suggested = deviceCurrency();
    final all = [
      if (suggested != null && !currencies.any((c) => c.$1 == suggested))
        (suggested, suggested),
      ...currencies,
    ];
    final filtered = all
        .where(
          (c) =>
              query.isEmpty ||
              c.$1.toLowerCase().contains(query) ||
              c.$2.toLowerCase().contains(query),
        )
        .toList();
    final hasData = ref.watch(_hasTransactionsProvider).value ?? false;

    Widget tile((String, String) c, {bool isSuggested = false}) {
      final selected = c.$1 == _currency;
      String symbol;
      try {
        symbol = Money.symbol(c.$1);
      } catch (_) {
        symbol = c.$1;
      }
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: selected ? AppColors.shallows : null,
        leading: CircleAvatar(
          backgroundColor: selected ? AppColors.tide : Colors.white,
          child: FittedBox(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                symbol,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.deepWater,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        title: Text(c.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(isSuggested ? '${c.$1}, suggested for your phone' : c.$1),
        trailing: selected
            ? const Icon(Icons.check_circle_rounded, color: AppColors.tide)
            : null,
        onTap: () => setState(() => _currency = c.$1),
      );
    }

    return _scroll([
      _heading(
        'Which currency do you use?',
        'All amounts in Tidewise will be shown in this currency.',
      ),
      TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded),
          hintText: 'Search, e.g. shilling or KES',
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.line),
          ),
        ),
      ),
      if (hasData && _currency != AppConfig.currency) ...[
        const SizedBox(height: 12),
        Text(
          'You already have entries recorded in ${AppConfig.currency}. '
          'Changing the currency does not convert them.',
          style: text.bodySmall?.copyWith(color: AppColors.amber),
        ),
      ],
      const SizedBox(height: 12),
      if (query.isEmpty && suggested != null)
        tile(all.firstWhere((c) => c.$1 == suggested), isSuggested: true),
      for (final c in filtered)
        if (!(query.isEmpty && c.$1 == suggested)) tile(c),
    ]);
  }

  // 4 -------------------------------------------------------------------------
  Widget _rhythmPage() {
    final text = Theme.of(context).textTheme;
    final uneven = _rhythm?.isUneven ?? false;

    return _scroll([
      _heading(
        'How do you usually get paid?',
        'Tidewise works with any rhythm, including when income changes '
            'from week to week.',
      ),
      for (final r in PayRhythm.values)
        _option(
          icon: r.icon,
          title: r.title,
          subtitle: r.subtitle,
          selected: _rhythm == r,
          onTap: () => setState(() => _rhythm = r),
        ),
      if (_rhythm != null) ...[
        const SizedBox(height: 12),
        if (uneven)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline_rounded, color: AppColors.tide),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Just add each payment when it arrives. Your plan splits it '
                    'right away, so you always know what is safe to spend.',
                    style: text.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        TextField(
          controller: _typical,
          keyboardType: TextInputType.numberWithOptions(
            decimal: Money.fractionDigits(_currency) > 0,
          ),
          inputFormatters: [amountInputFormatter(_currency)],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: uneven
                ? 'Roughly how much in a typical month? (optional)'
                : 'About how much comes in each month? (optional)',
            helperText: 'A rough number is fine. It helps show what your plan '
                'means in real money.',
            helperMaxLines: 2,
            prefixText: '${Money.symbol(_currency)} ',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.line),
            ),
          ),
        ),
      ],
    ]);
  }

  // 5 -------------------------------------------------------------------------
  Widget _planPage() {
    final text = Theme.of(context).textTheme;
    final options = ref.watch(strategyOptionsProvider);
    final typical = parseAmountMinor(_typical.text, _currency);

    return options.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) {
        final recommended = _recommendedId(list);
        final selectedId = _strategyId ?? recommended;
        return _scroll([
          _heading(
            'Pick a starting plan',
            typical > 0
                ? 'Here is what each plan means with about '
                    '${Money.format(typical, _currency)} a month. You can switch any time.'
                : 'A plan is a simple guide for splitting your money. You can '
                    'switch any time.',
          ),
          for (final o in list)
            _option(
              icon: Icons.donut_large_rounded,
              title: o.strategy.name,
              subtitle: o.strategy.description ?? '',
              badge: o.strategy.id == recommended ? 'Recommended' : null,
              selected: o.strategy.id == selectedId,
              onTap: () => setState(() => _strategyId = o.strategy.id),
              extra: Column(
                children: [
                  for (final b in o.buckets)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${(b.basisPoints / 100).round()}% ${b.name}',
                              style: text.bodySmall,
                            ),
                          ),
                          if (typical > 0)
                            Text(
                              Money.format(
                                Money.share(typical, b.basisPoints),
                                _currency,
                              ),
                              style: AppText.amount(13, weight: FontWeight.w600),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (_rhythm?.isUneven == true)
            Text(
              'Pay Yourself First is recommended because it works well when '
              'income changes: a fixed share goes to savings the moment money '
              'arrives, and the rest is yours to use.',
              style: text.bodySmall?.copyWith(color: AppColors.mist),
            ),
        ]);
      },
    );
  }

  // 6 -------------------------------------------------------------------------
  Widget _donePage() {
    final name = _name.text.trim();

    Widget action(
      String id,
      IconData icon,
      String title,
      String subtitle,
      Future<void> Function() open,
    ) {
      final done = _started.contains(id);
      return _option(
        icon: done ? Icons.check_rounded : icon,
        title: title,
        subtitle: done ? 'Added. You can add more any time.' : subtitle,
        selected: done,
        onTap: () async {
          await open();
          if (mounted) setState(() => _started.add(id));
        },
      );
    }

    return _scroll([
      _heading(
        name.isEmpty ? 'You are all set!' : 'You are all set, $name!',
        'Here is a good way to start. Each one takes a few seconds, or you '
            'can skip straight to your overview.',
      ),
      action(
        'income',
        Icons.south_west_rounded,
        'Add money you received',
        'Your latest salary, sales or any payment',
        () => showQuickAddSheet(context, kind: TransactionKind.income),
      ),
      action(
        'debt',
        Icons.payments_rounded,
        'Add a debt you are paying',
        'A loan, credit card, or money from family or a friend',
        () => showAddDebtSheet(context),
      ),
      action(
        'subscription',
        Icons.autorenew_rounded,
        'Add a bill or subscription',
        'Rent, phone, internet, streaming: get reminders before they are due',
        () => showSubscriptionSheet(context),
      ),
      action(
        'goal',
        Icons.savings_rounded,
        'Create a savings goal',
        'An emergency fund, school fees, a phone, a trip',
        () async {
          await showGoalSheet(context);
        },
      ),
    ]);
  }
}
