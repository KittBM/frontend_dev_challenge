import 'dart:async';

import 'package:get/get.dart';

import '../util/log_service.dart';

typedef SendAnalyticsBatch = Future<void> Function(
    List<Map<String, dynamic>> events);

/// Queues analytics events and delivers them in batches: as soon as
/// [maxBatchSize] events are waiting, or [maxDelay] after the oldest event
/// that has not been sent yet — whichever comes first.
class AnalyticsBatcher {
  AnalyticsBatcher({
    required SendAnalyticsBatch send,
    this.maxBatchSize = 10,
    this.maxDelay = const Duration(seconds: 15),
  }) : _send = send;

  final SendAnalyticsBatch _send;
  final int maxBatchSize;
  final Duration maxDelay;

  /// Events not delivered yet, oldest first. Events of a batch in flight are
  /// not here; they come back to the front if the batch fails.
  final _queue = <Map<String, dynamic>>[];

  /// Counts the debug screen shows.
  final queued = 0.obs;
  final batchesSent = 0.obs;

  /// Fires [maxDelay] after the oldest queued event arrived. It is not
  /// restarted by newer events, or a steady trickle would never be sent.
  Timer? _deadline;

  void add(Map<String, dynamic> event) {
    _queue.add(event);
    queued.value = _queue.length;
    if (_queue.length >= maxBatchSize) {
      flush();
    } else {
      _deadline ??= Timer(maxDelay, flush);
    }
  }

  /// Sends what is queued right now, in batches of at most [maxBatchSize].
  ///
  /// Events that arrive while those batches are in flight are not swept in:
  /// they wait for their own trigger (the size limit, or their own deadline,
  /// which [add] starts because this clears the current one).
  Future<void> flush() async {
    _deadline?.cancel();
    _deadline = null;
    final pending = List.of(_queue);
    _queue.clear();
    queued.value = 0;
    for (var i = 0; i < pending.length; i += maxBatchSize) {
      final batch = pending.sublist(
          i, i + maxBatchSize > pending.length ? pending.length : i + maxBatchSize);
      try {
        await _send(batch);
        batchesSent.value++;
      } catch (e) {
        // Put this batch and the ones after it back in front, oldest first,
        // and retry after another full delay rather than hammering a failing
        // backend.
        LogService.error('analytics batch failed, will retry', e);
        _queue.insertAll(0, pending.sublist(i));
        queued.value = _queue.length;
        _deadline ??= Timer(maxDelay, flush);
        return;
      }
    }
  }

  void dispose() {
    _deadline?.cancel();
    _deadline = null;
  }
}
