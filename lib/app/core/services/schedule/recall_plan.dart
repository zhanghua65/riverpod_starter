/// A reminder to open the app again before its alarms run out.
class RecallNotice {
  const RecallNotice({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
  });

  final int id;
  final DateTime at;
  final String title;
  final String body;

  @override
  bool operator ==(Object other) =>
      other is RecallNotice &&
      other.id == id &&
      other.at == at &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(id, at, title, body);
}

/// When to nudge the user to open the app so the alarms get topped up.
///
/// The alarm plugin has no recurring alarms, so the app registers a few
/// nights ahead on every start. A user who stays away longer than that
/// would silently lose the alarms. These notices are booked for just before
/// and just after the last registered alarm; opening the app registers
/// more alarms and books them again further out, so an active user never
/// sees them.
class RecallPlan {
  const RecallPlan._();

  static const warnId = 1;
  static const lapseId = 2;

  /// The warning comes the evening before the last registered alarm rings.
  static const warnAt = (hour: 20, minute: 30);

  /// The lapse notice comes this long after the last registered alarm.
  static const lapseDelay = Duration(hours: 12);

  /// Notices to book for alarms running out at [lastRing]. Those that would
  /// already be due at [now] are left out; none when there are no alarms.
  static List<RecallNotice> plan({
    required DateTime? lastRing,
    required DateTime now,
  }) {
    if (lastRing == null) return const [];
    final notices = [
      RecallNotice(
        id: warnId,
        at: DateTime(
          lastRing.year,
          lastRing.month,
          lastRing.day - 1,
          warnAt.hour,
          warnAt.minute,
        ),
        title: '闹钟快用完了',
        body: '闹钟只排到明早了，点开一下就能续上',
      ),
      RecallNotice(
        id: lapseId,
        at: lastRing.add(lapseDelay),
        title: '闹钟已经停了',
        body: '点开 App 恢复睡前提醒和起床闹钟',
      ),
    ];
    return [
      for (final n in notices)
        if (n.at.isAfter(now)) n,
    ];
  }
}
