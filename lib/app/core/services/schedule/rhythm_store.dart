import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'plan_config.dart';

/// One night in the sleep log: when the user planned to and actually went
/// to bed.
class SleepLogEntry {
  const SleepLogEntry({
    required this.night,
    required this.plannedBedtime,
    required this.actualBedtime,
  });

  final DateTime night;
  final DateTime plannedBedtime;
  final DateTime actualBedtime;

  Duration get lateBy => actualBedtime.difference(plannedBedtime);

  Map<String, Object> toJson() => {
    'night': night.toIso8601String(),
    'planned': plannedBedtime.toIso8601String(),
    'actual': actualBedtime.toIso8601String(),
  };

  factory SleepLogEntry.fromJson(Map<String, dynamic> json) => SleepLogEntry(
    night: DateTime.parse(json['night'] as String),
    plannedBedtime: DateTime.parse(json['planned'] as String),
    actualBedtime: DateTime.parse(json['actual'] as String),
  );
}

/// Local persistence for the plan and the sleep log (nothing leaves the
/// device).
class RhythmStore {
  RhythmStore(this._prefs);

  final SharedPreferences _prefs;

  static const _planKey = 'rhythm.plan';
  static const _logKey = 'rhythm.log';

  /// Older entries are dropped beyond this many nights.
  static const maxLogEntries = 30;

  PlanConfig? loadPlan() {
    final raw = _prefs.getString(_planKey);
    if (raw == null) return null;
    return PlanConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> savePlan(PlanConfig? plan) => plan == null
      ? _prefs.remove(_planKey)
      : _prefs.setString(_planKey, jsonEncode(plan.toJson()));

  /// Newest first.
  List<SleepLogEntry> loadLog() {
    final raw = _prefs.getString(_logKey);
    if (raw == null) return const [];
    return [
      for (final e in jsonDecode(raw) as List)
        SleepLogEntry.fromJson(e as Map<String, dynamic>),
    ];
  }

  /// Adds [entry], replacing any earlier entry for the same night.
  Future<List<SleepLogEntry>> addLog(SleepLogEntry entry) async {
    final log = [
      entry,
      for (final e in loadLog())
        if (e.night != entry.night) e,
    ]..sort((a, b) => b.night.compareTo(a.night));
    final kept = log.take(maxLogEntries).toList();
    await _prefs.setString(
      _logKey,
      jsonEncode([for (final e in kept) e.toJson()]),
    );
    return kept;
  }
}
