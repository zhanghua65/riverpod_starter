import 'package:riverpod_starter/app/core/services/alarm/recall_notifier.dart';
import 'package:riverpod_starter/app/core/services/schedule/recall_plan.dart';

/// Keeps the booked notices in memory instead of calling the plugin.
class FakeRecallNotifier extends RecallNotifier {
  var booked = <RecallNotice>[];

  /// How many times [replace] ran.
  var replaceCalls = 0;

  @override
  Future<void> replace(List<RecallNotice> notices) async {
    replaceCalls++;
    booked = notices;
  }
}
