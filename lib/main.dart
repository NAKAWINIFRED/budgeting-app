import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/app_config.dart';
import 'data/key_values.dart';
import 'features/subscriptions/bill_reminders.dart';
import 'features/subscriptions/subscriptions_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved settings (currency, name, onboarding) before the first frame.
  final container = ProviderContainer();
  final store = container.read(keyValueStoreProvider);
  AppConfig.currency = await store.get(SettingKeys.currency) ?? AppConfig.currency;
  final name = await store.get(SettingKeys.userName);
  AppConfig.userName = name == null || name.isEmpty ? null : name;
  AppConfig.payRhythm = await store.get(SettingKeys.payRhythm);
  AppConfig.typicalIncomeMinor =
      int.tryParse(await store.get(SettingKeys.typicalIncome) ?? '');
  AppConfig.onboardingDone =
      await store.get(SettingKeys.onboardingDone) == 'true';
  AppConfig.billReminders =
      await store.get(SettingKeys.billReminders) != 'false';

  await BillReminders.init();

  runApp(
    UncontrolledProviderScope(container: container, child: const TidewiseApp()),
  );

  // Opened by tapping a bill reminder: go straight to the bills.
  if (AppConfig.onboardingDone && await BillReminders.openedFromReminder()) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => appRouter.go('/expenses/subscriptions'),
    );
  }
}

class TidewiseApp extends ConsumerWidget {
  const TidewiseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep phone reminders in sync whenever subscriptions change.
    ref.listen(subscriptionsProvider, (_, next) {
      next.whenData(BillReminders.reschedule);
    });

    return MaterialApp.router(
      title: 'Tidewise',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: appRouter,
    );
  }
}
