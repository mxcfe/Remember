import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class Reminders {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(
        tz.getLocation(await FlutterTimezone.getLocalTimezone()));
    await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('ic_remember')));
  }

  Future<bool> requestPermission() async =>
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission() ??
      true;

  Future<void> cancel(int id) => _plugin.cancel(id);

  Future<void> schedule(int id, String title, DateTime date,
      {String body = '', String repeat = 'none'}) async {
    await cancel(id);
    if (!date.isAfter(DateTime.now())) {
      if (repeat == 'none') return;
      while (!date.isAfter(DateTime.now())) {
        if (repeat == 'monthly') {
          final next = DateTime(date.year, date.month + 1, 1);
          final last = DateTime(next.year, next.month + 1, 0).day;
          date = DateTime(next.year, next.month,
              date.day > last ? last : date.day, date.hour, date.minute);
        } else {
          date = DateTime(date.year, date.month,
              date.day + (repeat == 'weekly' ? 7 : 1), date.hour, date.minute);
        }
      }
    }
    await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(date, tz.local),
        const NotificationDetails(
            android: AndroidNotificationDetails('reminders', '事项提醒',
                channelDescription: '待办和物品提醒',
                importance: Importance.high,
                priority: Priority.high)),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: repeat == 'daily'
            ? DateTimeComponents.time
            : repeat == 'weekly'
                ? DateTimeComponents.dayOfWeekAndTime
                : repeat == 'monthly'
                    ? DateTimeComponents.dayOfMonthAndTime
                    : null);
  }
}
