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
    final textStyle = DefaultTextStyle.of(context)
        .style
        .merge(style)
        .copyWith(fontFeatures: _tabular);
    final textScaler = MediaQuery.textScalerOf(context);

    // Tabular digits make every `mm:ss` (and every `hh:mm:ss`) the same size,
    // so measure each shape once per build, not per tick. Giving the text a
    // fixed size makes it a relayout boundary: a new value re-lays out and
    // repaints only the text, instead of propagating up through the card.
    final short = _measure('00:00', textStyle, textScaler);
    final long = _measure('00:00:00', textStyle, textScaler);
    Widget sized(String value) => SizedBox.fromSize(
          size: value.length > 5 ? long : short,
          child: Text(value,
              style: textStyle,
              textScaler: textScaler,
              maxLines: 1,
              softWrap: false),
        );

    // Routes covered by another route (e.g. home under a deal page) are kept
    // alive with tickers disabled. Don't tick there: nobody can see it. This
    // widget depends on TickerMode, so it rebuilds — and resubscribes with the
    // current time — when its route is uncovered.
    final Widget text = TickerMode.of(context)
        ? Obx(() => sized(formatCountdown(endsAt.difference(clock.tick.value))))
        : sized(formatCountdown(endsAt.difference(clock.now())));
    return Semantics(
      // A label that changes every second would make screen readers chatter
      // and rebuild the semantics tree on every tick; announce the end time.
      label: 'Flash sale ends at ${_clockTime(endsAt.toLocal())}',
      excludeSemantics: true,
      // Own semantics node, so a tick's semantics update stops here instead
      // of recompiling the card's (or the screen's) semantics.
      container: true,
      // The digits repaint every second; keep that off the card's layer.
      child: RepaintBoundary(child: text),
    );
  }

  static Size _measure(String sample, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: sample, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final size = painter.size;
    painter.dispose();
    // Round up so sub-pixel differences never clip the last digit.
    return Size(size.width.ceilToDouble(), size.height.ceilToDouble());
  }

  static String _clockTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
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
