import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'analytics_batcher.dart';
import 'analytics_service.dart';

/// Records `deal_impression` events: at most once per deal per app session,
/// across every screen, delivered to the backend in batches.
///
/// Deciding *when* a card counts as seen is the job of `TrackImpression`;
/// this service only de-duplicates, logs and batches.
class ImpressionService extends GetxService with WidgetsBindingObserver {
  ImpressionService({
    required this.analytics,
    required SendAnalyticsBatch send,
  }) : batcher = AnalyticsBatcher(send: send);

  final AnalyticsService analytics;
  final AnalyticsBatcher batcher;

  /// Deals already reported this session. Lives as long as the app, so
  /// leaving and re-opening a screen does not report the same deal again.
  final _seen = <int>{};

  bool hasSeen(int dealId) => _seen.contains(dealId);

  void recordImpression({
    required int dealId,
    required String source,
    required int position,
  }) {
    if (!_seen.add(dealId)) return;
    final event = analytics.logEvent('deal_impression', {
      'deal_id': dealId,
      'source': source,
      'position': position,
    });
    batcher.add(event.toJson());
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    batcher.dispose();
    super.onClose();
  }

  /// The OS may kill a backgrounded app without warning; send what is queued
  /// instead of waiting up to 15 s for a deadline that may never come.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) batcher.flush();
  }
}
