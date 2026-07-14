import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Thin wrapper around flutter_local_notifications for scheduling note reminders.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'reminders';
  static const String _channelName = 'Reminders';
  static const String _channelDesc = 'Note reminder notifications';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      tz.initializeTimeZones();

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
      );
      await _plugin.initialize(settings: initSettings);

      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
        ),
      );
      await androidImpl?.requestNotificationsPermission();
      _initialized = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NotificationService] init error: $e');
      }
    }
  }

  /// Schedules a reminder. [id] should be stable per note so it can be updated
  /// or cancelled later (we use the local note id).
  Future<bool> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
    String repeat = 'none',
    int leadMinutes = 0,
  }) async {
    await init();
    final notificationAt = scheduledAt.subtract(
      Duration(minutes: leadMinutes.clamp(0, 24 * 60) as int),
    );
    if (notificationAt.isBefore(DateTime.now())) return false;
    try {
      final when = tz.TZDateTime.from(notificationAt, tz.local);
      await _plugin.zonedSchedule(
        id: id,
        title: title.isEmpty ? 'Note reminder' : title,
        body: body,
        scheduledDate: when,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: switch (repeat) {
          'daily' => DateTimeComponents.time,
          'weekly' => DateTimeComponents.dayOfWeekAndTime,
          _ => null,
        },
      );
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NotificationService] schedule error: $e');
      }
      return false;
    }
  }

  Future<void> cancel(int id) async {
    await init();
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }
}
