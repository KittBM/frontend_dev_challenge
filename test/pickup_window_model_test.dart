import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/model/pickup_window_model.dart';

// The expectations are built from local wall-clock times, so these tests hold
// in any device timezone (and fail on the old code in any non-UTC timezone).
PickupWindowModel windowFromLocal(DateTime start, DateTime end) =>
    PickupWindowModel.fromJson({
      'start': start.toUtc().toIso8601String(), // what the API sends
      'end': end.toUtc().toIso8601String(),
    });

void main() {
  test('RES-106: label shows local wall-clock time, not UTC', () {
    final w = windowFromLocal(
        DateTime(2026, 10, 8, 6, 0), DateTime(2026, 10, 8, 9, 30));
    expect(w.label, '06:00 – 09:30');
  });

  test('RES-106: overnight window keeps its local times', () {
    final w = windowFromLocal(
        DateTime(2026, 10, 8, 22, 0), DateTime(2026, 10, 9, 1, 0));
    expect(w.label, '22:00 – 01:00');
  });

  test('RES-106: "today" is the local calendar day of the window start', () {
    final w = windowFromLocal(
        DateTime(2026, 10, 8, 6, 0), DateTime(2026, 10, 8, 9, 30));
    expect(w.startsOnSameDayAs(DateTime(2026, 10, 8, 0, 5)), isTrue);
    expect(w.startsOnSameDayAs(DateTime(2026, 10, 8, 23, 55)), isTrue);
    expect(w.startsOnSameDayAs(DateTime(2026, 10, 7, 23, 55)), isFalse);
    // Same day-of-month in another month is not "today".
    expect(w.startsOnSameDayAs(DateTime(2026, 11, 8, 12)), isFalse);
  });
}
