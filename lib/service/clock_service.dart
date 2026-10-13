import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// App-wide time source.
///
/// [tick] is a single shared heartbeat for every live countdown on screen, so
/// 100 visible countdowns cost one timer instead of 100. Ticks are aligned to
/// wall-clock second boundaries, so all countdowns flip together and never
/// skip or repeat a second because of timer drift.
class ClockService extends GetxService with WidgetsBindingObserver {
  ClockService({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  late final Rx<DateTime> tick = _now().obs;

  /// Bumped each time the app returns to the foreground.
  ///
  /// Dart timers run on a monotonic clock, which on Android does not advance
  /// while the device is suspended (screen off). A one-shot timer waiting for
  /// a wall-clock instant can therefore fire long after it. Anything that
  /// waits like that must re-check against [now] when this changes.
  final resumed = 0.obs;

  Timer? _timer;

  DateTime now() => _now();

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _scheduleNextTick();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Catch up straight away instead of waiting for the next tick.
    _timer?.cancel();
    tick.value = _now();
    resumed.value++;
    _scheduleNextTick();
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
