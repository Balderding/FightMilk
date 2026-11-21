import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The rest timer's "time's up" buzz, scheduled with the system so it fires with the screen off.
class Notifier {
  final _p = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _asked = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'rest_timer',
      'Rest timer',
      channelDescription: 'Buzzes when your rest between sets is over',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      category: AndroidNotificationCategory.alarm,
    ),
  );

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      await _p.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Asks once (Android 13+) for permission to show the buzz.
  Future<void> askOnce() async {
    if (!_ready || _asked) return;
    _asked = true;
    try {
      await _android?.requestNotificationsPermission();
    } catch (_) {}
  }

  Future<void> restDone(Duration after) async {
    if (!_ready) return;
    await cancel();
    final when = tz.TZDateTime.now(tz.UTC).add(after);
    try {
      await _p.zonedSchedule(id: 1, scheduledDate: when, notificationDetails: _details, androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, title: 'Rest over', body: 'Time for your next set');
    } catch (_) {
      try {
        await _p.zonedSchedule(id: 1, scheduledDate: when, notificationDetails: _details, androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, title: 'Rest over', body: 'Time for your next set');
      } catch (_) {}
    }
  }

  /// While resting with the app in the background: an ongoing notice with a live countdown
  /// (Android draws the clock itself; nothing runs in the app). Gone when the app comes back.
  Future<void> restOngoing(DateTime end, String next) async {
    if (!_ready) return;
    try {
      await _p.show(
        id: 2,
        title: 'Resting',
        body: next.isEmpty ? 'Your next set is up when the clock hits zero' : 'Next: $next',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'rest_live',
            'Rest countdown',
            channelDescription: 'A quiet countdown while you rest with the app closed',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            onlyAlertOnce: true,
            showWhen: true,
            when: end.millisecondsSinceEpoch,
            usesChronometer: true,
            chronometerCountDown: true,
            timeoutAfter: end.difference(DateTime.now()).inMilliseconds.clamp(1000, 3600000),
            visibility: NotificationVisibility.public,
            category: AndroidNotificationCategory.stopwatch,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> cancelOngoing() async {
    if (!_ready) return;
    try {
      await _p.cancel(id: 2);
    } catch (_) {}
  }

  static const _remind = NotificationDetails(
    android: AndroidNotificationDetails('reminders', 'Training reminders', channelDescription: 'Reminds you on your training days', importance: Importance.defaultImportance,
        visibility: NotificationVisibility.private), // lock screen shows only the app name
  );

  /// Reminders for the next 2 weeks on the chosen weekdays (1 = Monday) at [minutes] after midnight,
  /// local time. Re-made every time the app opens, so they keep rolling forward.
  Future<void> scheduleReminders(Set<int> weekdays, int minutes, String dayName) async {
    if (!_ready) return;
    for (var i = 0; i < 14; i++) {
      try {
        await _p.cancel(id: 100 + i);
      } catch (_) {}
    }
    if (weekdays.isEmpty) return;
    final now = DateTime.now();
    for (var i = 0; i < 14; i++) {
      final d = DateTime(now.year, now.month, now.day + i, minutes ~/ 60, minutes % 60);
      if (!weekdays.contains(d.weekday) || !d.isAfter(now)) continue;
      try {
        await _p.zonedSchedule(
          id: 100 + i,
          scheduledDate: tz.TZDateTime.from(d.toUtc(), tz.UTC),
          notificationDetails: _remind,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: 'Hey, time to train!',
          body: 'Next up: $dayName. Open the app and start the workout.',
        );
      } catch (_) {}
    }
  }

  /// Every notification and reminder this app has scheduled.
  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _p.cancelAll();
    } catch (_) {}
  }

  Future<void> cancel() async {
    if (!_ready) return;
    try {
      await _p.cancel(id: 1);
    } catch (_) {}
  }
}
