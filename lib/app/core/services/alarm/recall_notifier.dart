import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '/app/core/services/schedule/recall_plan.dart';
import '/app/core/utils/app_log.dart';

/// Books the plain notifications that bring the user back to the app before
/// its alarms run out (see [RecallPlan]).
///
/// Unlike the alarm chain these never ring or take over the screen. Failures
/// are logged and swallowed: a missing reminder must not break the plan.
class RecallNotifier {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Must run once before the first [replace], after
  /// `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<void> init() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
    } catch (e) {
      AppLog.add('recall', 'init failed: $e');
    }
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'recall',
      '闹钟续期提醒',
      channelDescription: '闹钟快用完时提醒你打开 App',
    ),
  );

  /// Replaces the booked notices with [notices]; an empty list cancels them.
  Future<void> replace(List<RecallNotice> notices) async {
    try {
      await _plugin.cancel(id: RecallPlan.warnId);
      await _plugin.cancel(id: RecallPlan.lapseId);
      for (final n in notices) {
        await _plugin.zonedSchedule(
          id: n.id,
          title: n.title,
          body: n.body,
          // The instant is what matters; UTC avoids needing the device zone.
          scheduledDate: tz.TZDateTime.from(n.at, tz.UTC),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
      AppLog.add(
        'recall',
        notices.isEmpty
            ? 'cancelled'
            : 'booked ${[for (final n in notices) '${n.id}@${n.at}'].join(' ')}',
      );
    } catch (e) {
      AppLog.add('recall', 'book failed: $e');
    }
  }
}
