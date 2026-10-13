import 'dart:async';

import 'package:get/get.dart';

/// App-wide time source.
///
/// [tick] is a single shared heartbeat for every live countdown on screen, so
/// 100 visible countdowns cost one timer instead of 100. Ticks are aligned to
/// wall-clock second boundaries, so all countdowns flip together and never
/// skip or repeat a second because of timer drift.
class ClockService extends GetxService {
  ClockService({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  late final Rx<DateTime> tick = _now().obs;

  Timer? _timer;

  DateTime now() => _now();

  @override
  void onInit() {
    super.onInit();
    _scheduleNextTick();
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  void _scheduleNextTick() {
    final now = _now();
    final untilNextSecond = Duration(
      milliseconds: 1000 - now.millisecond,
      microseconds: -now.microsecond,
    );
    _timer = Timer(untilNextSecond, () {
      tick.value = _now();
      _scheduleNextTick();
    });
  }
}
