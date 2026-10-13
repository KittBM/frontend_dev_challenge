import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../service/clock_service.dart';

/// `mm:ss`, or `hh:mm:ss` from one hour up. Rounds up, so the display only
/// reaches `00:00` when the sale has actually ended.
String formatCountdown(Duration remaining) {
  final totalSeconds = remaining <= Duration.zero
      ? 0
      : (remaining.inMilliseconds + 999) ~/ 1000;
  final h = totalSeconds ~/ 3600;
  final m = totalSeconds % 3600 ~/ 60;
  final s = totalSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// Live `mm:ss` text. The only widget that rebuilds on every [ClockService]
/// tick — keep it as small as possible and never wrap a card in it.
class FlashCountdownText extends StatelessWidget {
  final DateTime endsAt;
  final TextStyle? style;

  const FlashCountdownText({super.key, required this.endsAt, this.style});

  // Fixed-width digits so the text width (and its parent's layout) does not
  // change every second.
  static const _tabular = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    final clock = Get.find<ClockService>();
    final textStyle = (style ?? const TextStyle()).copyWith(
      fontFeatures: _tabular,
    );
    return Obx(() => Text(
          formatCountdown(endsAt.difference(clock.tick.value)),
          style: textStyle,
        ));
  }
}

/// Rebuilds [builder] exactly once, when the flash sale ending at [endsAt]
/// expires. Uses a one-shot timer rather than listening to the per-second
/// tick, so the cards it wraps cost nothing while the countdown runs.
class FlashExpiryBuilder extends StatefulWidget {
  final DateTime? endsAt;
  final Widget Function(BuildContext context, bool expired) builder;

  const FlashExpiryBuilder({
    super.key,
    required this.endsAt,
    required this.builder,
  });

  @override
  State<FlashExpiryBuilder> createState() => _FlashExpiryBuilderState();
}

class _FlashExpiryBuilderState extends State<FlashExpiryBuilder> {
  Timer? _timer;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(FlashExpiryBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // List items are recycled: the same State can be handed a different deal.
    if (oldWidget.endsAt != widget.endsAt) _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _arm() {
    _timer?.cancel();
    _timer = null;
    final endsAt = widget.endsAt;
    if (endsAt == null) {
      _expired = false;
      return;
    }
    final remaining = endsAt.difference(Get.find<ClockService>().now());
    _expired = remaining <= Duration.zero;
    if (!_expired) {
      _timer = Timer(remaining, () => setState(() => _expired = true));
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _expired);
}

/// Washes out an expired card without a saveLayer (unlike Opacity).
const expiredForeground = BoxDecoration(color: Color(0x99FFFFFF));
