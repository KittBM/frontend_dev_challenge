import 'package:intl/intl.dart';

/// A store's pickup window. The API sends instants as ISO-8601 UTC strings;
/// they are converted to the device's local time once, here, so every
/// consumer (labels, "today" checks) works in the user's wall-clock time.
class PickupWindowModel {
  final DateTime start;
  final DateTime end;

  const PickupWindowModel({required this.start, required this.end});

  factory PickupWindowModel.fromJson(Map<String, dynamic> json) {
    return PickupWindowModel(
      start: DateTime.parse(json['start'] as String? ?? '').toLocal(),
      end: DateTime.parse(json['end'] as String? ?? '').toLocal(),
    );
  }

  /// Human readable label, e.g. "17:30 – 21:00".
  String get label =>
      '${DateFormat('HH:mm').format(start)} – ${DateFormat('HH:mm').format(end)}';

  /// Whether pickup starts today.
  bool get isToday => startsOnSameDayAs(DateTime.now());

  /// Whether pickup starts on the same local calendar day as [moment].
  bool startsOnSameDayAs(DateTime moment) {
    final day = moment.toLocal();
    return start.year == day.year &&
        start.month == day.month &&
        start.day == day.day;
  }

  /// Whether the store is currently accepting pickups.
  bool get isOpenNow {
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(end);
  }

  Duration get untilStart => start.difference(DateTime.now());
}
