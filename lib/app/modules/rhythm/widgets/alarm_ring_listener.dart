import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/di/alarm_provider.dart';
import '/app/routes/app_pages.dart';
import '/app/routes/app_routes.dart';

/// Opens the ring page whenever an alarm starts ringing, including one that
/// was already ringing when the app was launched by it.
class AlarmRingListener extends ConsumerStatefulWidget {
  const AlarmRingListener({required this.child});

  final Widget child;

  @override
  ConsumerState<AlarmRingListener> createState() => _AlarmRingListenerState();
}

class _AlarmRingListenerState extends ConsumerState<AlarmRingListener> {
  /// Ids whose page is already open, so a ringing alarm opens one page.
  final _shown = <int>{};

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<AlarmSet>>(
      ringingAlarmsProvider,
      (_, next) => _onRinging(next.value?.alarms ?? const {}),
      fireImmediately: true,
    );
  }

  void _onRinging(Set<AlarmSettings> ringing) {
    final ids = {for (final a in ringing) a.id};
    // Forget alarms that stopped, so a snoozed one opens a page again.
    _shown.retainWhere(ids.contains);
    for (final alarm in ringing) {
      if (_shown.add(alarm.id)) {
        // The navigator may not be built yet when the app is launched by
        // the alarm.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => AppPages.router.push(Paths.RING, extra: alarm),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
