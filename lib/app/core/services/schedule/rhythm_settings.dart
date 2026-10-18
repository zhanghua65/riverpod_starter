import 'stepping_plan.dart';

/// User-tunable values of the stepping plan and the anti-guilt recovery.
///
/// The defaults are the ones the design doc started with.
class RhythmSettings {
  const RhythmSettings({
    this.maxStepMinutes = 30,
    this.maxDays = 7,
    this.windDownLeadMinutes = 45,
    this.napTime = const ClockTime(13, 0),
    this.recallEnabled = true,
  });

  /// Largest shift of bedtime or wake-up from one night to the next.
  final int maxStepMinutes;

  /// Longest transition; larger steps are used when it would take longer.
  final int maxDays;

  /// How long before bedtime the wind-down alarm rings.
  final int windDownLeadMinutes;

  /// When the nap capsule is offered after a late night.
  final ClockTime napTime;

  /// Whether to remind the user to open the app before the registered
  /// alarms run out.
  final bool recallEnabled;

  static const stepRange = (min: 10, max: 60);
  static const daysRange = (min: 3, max: 14);
  static const windDownRange = (min: 30, max: 60);

  Duration get windDownLead => Duration(minutes: windDownLeadMinutes);

  RhythmSettings copyWith({
    int? maxStepMinutes,
    int? maxDays,
    int? windDownLeadMinutes,
    ClockTime? napTime,
    bool? recallEnabled,
  }) => RhythmSettings(
    maxStepMinutes: maxStepMinutes ?? this.maxStepMinutes,
    maxDays: maxDays ?? this.maxDays,
    windDownLeadMinutes: windDownLeadMinutes ?? this.windDownLeadMinutes,
    napTime: napTime ?? this.napTime,
    recallEnabled: recallEnabled ?? this.recallEnabled,
  );

  Map<String, Object> toJson() => {
    'maxStepMinutes': maxStepMinutes,
    'maxDays': maxDays,
    'windDownLeadMinutes': windDownLeadMinutes,
    'napTime': napTime.minutes,
    'recallEnabled': recallEnabled,
  };

  /// Missing or out-of-range values fall back to the defaults.
  factory RhythmSettings.fromJson(Map<String, dynamic> json) {
    const d = RhythmSettings();
    int pick(String key, int fallback, ({int min, int max}) range) {
      final v = json[key];
      return v is int && v >= range.min && v <= range.max ? v : fallback;
    }

    final nap = json['napTime'];
    return RhythmSettings(
      maxStepMinutes: pick('maxStepMinutes', d.maxStepMinutes, stepRange),
      maxDays: pick('maxDays', d.maxDays, daysRange),
      windDownLeadMinutes: pick(
        'windDownLeadMinutes',
        d.windDownLeadMinutes,
        windDownRange,
      ),
      napTime: nap is int && nap >= 0 && nap < 24 * 60
          ? ClockTime.fromMinutes(nap)
          : d.napTime,
      recallEnabled: json['recallEnabled'] is bool
          ? json['recallEnabled'] as bool
          : d.recallEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RhythmSettings &&
      other.maxStepMinutes == maxStepMinutes &&
      other.maxDays == maxDays &&
      other.windDownLeadMinutes == windDownLeadMinutes &&
      other.napTime == napTime &&
      other.recallEnabled == recallEnabled;

  @override
  int get hashCode =>
      Object.hash(
        maxStepMinutes,
        maxDays,
        windDownLeadMinutes,
        napTime,
        recallEnabled,
      );
}
