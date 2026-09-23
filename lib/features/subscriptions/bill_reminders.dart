import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../app/router.dart';
import '../../core/app_config.dart';
import '../../core/money.dart';
import '../../data/database.dart';

/// Phone notifications before subscriptions and bills are due.
///
/// Every time the list of subscriptions changes, all reminders are
/// cancelled and scheduled again from scratch, so they are always in sync.
class BillReminders {
  BillReminders._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Reminders arrive at this hour of the day.
  static const _hour = 9;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'bill_reminders',
      'Bill reminders',
      channelDescription: 'Reminders before subscriptions and bills are due',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
      color: Color(0xFF1C7C7D), // Tidewise teal
    ),
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_notification'),
          iOS: DarwinInitializationSettings(
            // We ask later, when the user has bills to be reminded about.
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        // Tapping a reminder opens the Subscriptions page.
        onDidReceiveNotificationResponse: (_) =>
            appRouter.go('/expenses/subscriptions'),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  /// True if the app was opened by tapping one of our notifications.
  static Future<bool> openedFromReminder() async {
    if (!_ready) return false;
    final details = await _plugin.getNotificationAppLaunchDetails();
    return details?.didNotificationLaunchApp ?? false;
  }

  /// Asks the user for permission to show notifications (Android 13+, iOS).
  static Future<bool> requestPermission() async {
    if (!_ready) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  /// Replaces all scheduled reminders with fresh ones for [subscriptions].
  static Future<void> reschedule(List<Subscription> subscriptions) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAllPendingNotifications();
      if (!AppConfig.billReminders || subscriptions.isEmpty) return;

      await requestPermission();

      final now = DateTime.now();
      var id = 1000;
      for (final s in subscriptions) {
        final d = s.nextDueDate;
        final due = DateTime(d.year, d.month, d.day, _hour);
        final remind = DateTime(d.year, d.month, d.day - s.remindDaysBefore, _hour);
        final amount = Money.format(s.amountMinor, kDefaultCurrency);
        final when = s.remindDaysBefore == 1
            ? 'tomorrow'
            : 'in ${s.remindDaysBefore} days';

        // A heads-up a few days before...
        if (s.remindDaysBefore > 0 && remind.isAfter(now)) {
          await _schedule(
            id++,
            remind,
            '${s.name} is due $when',
            '$amount on ${DateFormat.MMMEd().format(due)}. '
                'Tap to see your bills.',
          );
        }
        // ...and a reminder on the day itself.
        if (due.isAfter(now)) {
          await _schedule(
            id++,
            due,
            '${s.name} is due today',
            '$amount. Once it is paid, mark it as paid in Tidewise.',
          );
        }
      }
    } catch (e) {
      debugPrint('Could not schedule bill reminders: $e');
    }
  }

  static Future<void> _schedule(int id, DateTime when, String title, String body) {
    return _plugin.zonedSchedule(
      id: id,
      // The exact moment in time, whatever the phone's time zone.
      scheduledDate: tz.TZDateTime.from(when, tz.UTC),
      notificationDetails: _details,
      // Inexact is fine for bills and needs no special alarm permission.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: title,
      body: body,
    );
  }

  /// Shows a sample reminder right away, so users can check it works.
  static Future<bool> showTest() async {
    if (!_ready) return false;
    final allowed = await requestPermission();
    await _plugin.show(
      id: 1,
      title: 'Bill reminders are on',
      body: 'This is how Tidewise will remind you before a bill is due.',
      notificationDetails: _details,
    );
    return allowed;
  }
}
