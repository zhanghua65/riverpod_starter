import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '/app/core/services/ai/ai_config.dart';
import 'plan_config.dart';
import 'rhythm_settings.dart';
import 'work_schedule.dart';

/// How the actual bedtime of a night was recorded.
enum BedtimeSource {
  /// The user tapped "我已躺下" or entered it by hand.
  manual,

  /// Inferred from when the screen went off for the night.
  screen,
}

/// One night in the sleep log: when the user planned to and actually went
/// to bed, and when they got up if known.
class SleepLogEntry {
  const SleepLogEntry({
    required this.night,
    required this.plannedBedtime,
    required this.actualBedtime,
    this.source = BedtimeSource.manual,
    this.actualWakeUp,
    this.wakeUpSource = BedtimeSource.screen,
  });

  final DateTime night;
  final DateTime plannedBedtime;
  final DateTime actualBedtime;
  final BedtimeSource source;

  /// When the user started using the phone in the morning; null until it
  /// is known.
  final DateTime? actualWakeUp;

  /// How [actualWakeUp] was recorded: from the morning's screen use or
  /// entered by the user.
  final BedtimeSource wakeUpSource;

  SleepLogEntry withWakeUp(
    DateTime at, {
    BedtimeSource source = BedtimeSource.screen,
  }) => SleepLogEntry(
    night: night,
    plannedBedtime: plannedBedtime,
    actualBedtime: actualBedtime,
    source: this.source,
    actualWakeUp: at,
    wakeUpSource: source,
  );

  /// The same night with the bedtime corrected by the user, or replaced by
  /// a better [source].
  SleepLogEntry withBedtime(
    DateTime at, {
    BedtimeSource source = BedtimeSource.manual,
  }) => SleepLogEntry(
    night: night,
    plannedBedtime: plannedBedtime,
    actualBedtime: at,
    source: source,
    actualWakeUp: actualWakeUp,
    wakeUpSource: wakeUpSource,
  );

  Duration get lateBy => actualBedtime.difference(plannedBedtime);

  /// Time in bed, from [actualBedtime] to [actualWakeUp]; null until the
  /// wake-up is known or when the two times are inconsistent.
  Duration? get sleepDuration {
    final wake = actualWakeUp;
    if (wake == null || !wake.isAfter(actualBedtime)) return null;
    return wake.difference(actualBedtime);
  }

  Map<String, Object> toJson() => {
    'night': night.toIso8601String(),
    'planned': plannedBedtime.toIso8601String(),
    'actual': actualBedtime.toIso8601String(),
    'source': source.name,
    if (actualWakeUp != null) 'wakeUp': actualWakeUp!.toIso8601String(),
    if (actualWakeUp != null) 'wakeUpSource': wakeUpSource.name,
  };

  factory SleepLogEntry.fromJson(Map<String, dynamic> json) => SleepLogEntry(
    night: DateTime.parse(json['night'] as String),
    plannedBedtime: DateTime.parse(json['planned'] as String),
    actualBedtime: DateTime.parse(json['actual'] as String),
    // Entries saved before sources existed were all entered by the user.
    source:
        BedtimeSource.values.asNameMap()[json['source']] ??
        BedtimeSource.manual,
    actualWakeUp: json['wakeUp'] is String
        ? DateTime.tryParse(json['wakeUp'] as String)
        : null,
    // Wake-ups saved before sources existed all came from the screen.
    wakeUpSource:
        BedtimeSource.values.asNameMap()[json['wakeUpSource']] ??
        BedtimeSource.screen,
  );
}

/// The advisor's kind words for a night the user went to bed late.
class Comfort {
  const Comfort({required this.night, required this.text});

  final DateTime night;
  final String text;

  Map<String, Object> toJson() => {
    'night': night.toIso8601String(),
    'text': text,
  };

  factory Comfort.fromJson(Map<String, dynamic> json) => Comfort(
    night: DateTime.parse(json['night'] as String),
    text: json['text'] as String,
  );
}

/// Local persistence for the plan, the sleep log and the AI settings. Only
/// the AI advisor sends anything off the device, and only to the endpoint
/// the user entered.
class RhythmStore {
  RhythmStore(this._prefs);

  final SharedPreferences _prefs;

  static const _planKey = 'rhythm.plan';
  static const _logKey = 'rhythm.log';
  static const _settingsKey = 'rhythm.settings';
  static const _vendorTipKey = 'rhythm.vendorTipDone';
  static const _onboardingKey = 'rhythm.onboardingDone';
  static const _workKey = 'rhythm.work';
  static const _aiKey = 'rhythm.ai';
  static const _comfortKey = 'rhythm.aiComfort';
  static const _reviewedAtKey = 'rhythm.aiReviewedAt';

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

  bool get vendorTipDone => _prefs.getBool(_vendorTipKey) ?? false;

  Future<void> setVendorTipDone(bool done) =>
      _prefs.setBool(_vendorTipKey, done);

  bool get onboardingDone => _prefs.getBool(_onboardingKey) ?? false;

  Future<void> setOnboardingDone(bool done) =>
      _prefs.setBool(_onboardingKey, done);

  RhythmSettings loadSettings() {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null) return const RhythmSettings();
    return RhythmSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveSettings(RhythmSettings settings) =>
      _prefs.setString(_settingsKey, jsonEncode(settings.toJson()));

  /// Null until the user enters a work schedule.
  WorkSchedule? loadWork() {
    final raw = _prefs.getString(_workKey);
    if (raw == null) return null;
    return WorkSchedule.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveWork(WorkSchedule? work) => work == null
      ? _prefs.remove(_workKey)
      : _prefs.setString(_workKey, jsonEncode(work.toJson()));

  AiConfig loadAiConfig() {
    final raw = _prefs.getString(_aiKey);
    if (raw == null) return const AiConfig();
    return AiConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveAiConfig(AiConfig config) =>
      _prefs.setString(_aiKey, jsonEncode(config.toJson()));

  Comfort? loadComfort() {
    final raw = _prefs.getString(_comfortKey);
    if (raw == null) return null;
    return Comfort.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveComfort(Comfort? comfort) => comfort == null
      ? _prefs.remove(_comfortKey)
      : _prefs.setString(_comfortKey, jsonEncode(comfort.toJson()));

  /// When the last weekly review was applied or dismissed.
  DateTime? get reviewedAt {
    final raw = _prefs.getString(_reviewedAtKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setReviewedAt(DateTime at) =>
      _prefs.setString(_reviewedAtKey, at.toIso8601String());

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
    return _saveLog(log);
  }

  /// Records that the user got up at [at] after [night]. Nothing changes
  /// when that night has no entry.
  Future<List<SleepLogEntry>> setWakeUp(DateTime night, DateTime at) =>
      _saveLog([
        for (final e in loadLog()) e.night == night ? e.withWakeUp(at) : e,
      ]);

  /// Replaces the logged bedtime and/or wake-up of [night] with times the
  /// user entered. Nothing changes when that night has no entry.
  Future<List<SleepLogEntry>> editLog(
    DateTime night, {
    DateTime? bedtime,
    DateTime? wakeUp,
  }) => _saveLog([
    for (final e in loadLog())
      if (e.night != night) e else _edited(e, bedtime: bedtime, wakeUp: wakeUp),
  ]);

  static SleepLogEntry _edited(
    SleepLogEntry e, {
    DateTime? bedtime,
    DateTime? wakeUp,
    BedtimeSource source = BedtimeSource.manual,
  }) {
    var edited = bedtime == null ? e : e.withBedtime(bedtime, source: source);
    if (wakeUp != null) {
      edited = edited.withWakeUp(wakeUp, source: source);
    }
    return edited;
  }

  Future<List<SleepLogEntry>> _saveLog(List<SleepLogEntry> log) async {
    final kept = log.take(maxLogEntries).toList();
    await _prefs.setString(
      _logKey,
      jsonEncode([for (final e in kept) e.toJson()]),
    );
    return kept;
  }
}
