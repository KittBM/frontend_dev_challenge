import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../service/impression_service.dart';

/// Reports a `deal_impression` once [child] has been at least half visible
/// for one continuous second.
///
/// Wrap cards where they are placed in a list, since only the list knows the
/// card's [position]. Visibility callbacks only start or cancel a timer;
/// they never rebuild anything, so tracking adds no work to scrolling beyond
/// the visibility checks themselves.
///
/// A card on a route covered by another route counts as not visible: its
/// layer is detached, and the detector reports that as 0% visible.
class TrackImpression extends StatefulWidget {
  final int dealId;

  /// `home_feed`, `flash_rail` or `search`.
  final String source;
  final int position;
  final Widget child;

  const TrackImpression({
    super.key,
    required this.dealId,
    required this.source,
    required this.position,
    required this.child,
  });

  static const minVisibleFraction = 0.5;
  static const minVisibleDuration = Duration(seconds: 1);

  @override
  State<TrackImpression> createState() => _TrackImpressionState();
}

class _TrackImpressionState extends State<TrackImpression> {
  late final ImpressionService _impressions = Get.find();
  Timer? _timer;
  double _visibleFraction = 0;

  @override
  void didUpdateWidget(TrackImpression oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A recycled list item may now show a different deal: its visibility so
    // far says nothing about the new one, which reports afresh under its own
    // detector key.
    if (oldWidget.dealId != widget.dealId ||
        oldWidget.source != widget.source) {
      _visibleFraction = 0;
      _update();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // A method tear-off, so the detector gets an identical callback on every
  // rebuild; a new closure would make it repaint and re-check each time.
  void _onVisibilityChanged(VisibilityInfo info) {
    if (!mounted) return;
    _visibleFraction = info.visibleFraction;
    _update();
  }

  void _update() {
    final counting = _visibleFraction >= TrackImpression.minVisibleFraction &&
        !_impressions.hasSeen(widget.dealId);
    if (!counting) {
      // Dropping below the threshold, even briefly, restarts the second.
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer(TrackImpression.minVisibleDuration, _onSeen);
    }
  }

  void _onSeen() {
    _timer = null;
    _impressions.recordImpression(
      dealId: widget.dealId,
      source: widget.source,
      position: widget.position,
    );
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: ValueKey('impression-${widget.source}-${widget.dealId}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: widget.child,
    );
  }
}
