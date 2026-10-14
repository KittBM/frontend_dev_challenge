import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/feature/home/widget/flash_deals_section.dart';
import 'package:rescu/feature/shared_widget/deal_card.dart';
import 'package:rescu/feature/shared_widget/flash_countdown.dart';
import 'package:rescu/service/clock_service.dart';

import 'flash_countdown_test.dart' show flashDeal;
import 'helpers.dart';

/// F-1 performance budget: a clock tick may rebuild only the countdown text,
/// never the cards or the list around it.
void main() {
  late DateTime now;
  late List<String> rebuilt;

  setUp(() {
    now = DateTime(2026, 10, 13, 12);
    rebuilt = [];
    // Fires for every element rebuilt in a frame (debug builds only).
    debugOnRebuildDirtyWidget = (element, _) {
      rebuilt.add(element.widget.runtimeType.toString());
    };
  });

  tearDown(() {
    debugOnRebuildDirtyWidget = null;
    Get.reset();
  });

  Map<String, int> countByType(List<String> types) {
    final counts = <String, int>{};
    for (final t in types) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
    return counts;
  }

  testWidgets('one tick with 130 visible countdowns rebuilds only their text',
      (tester) async {
    // Tall surface so every card is laid out and visible at once.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 40000);
    addTearDown(tester.view.reset);

    final clock = Get.put(ClockService(now: () => now));
    final impressions = putImpressionService();
    final railDeals = [
      for (var i = 0; i < 10; i++)
        flashDeal(1000 + i, now.add(Duration(minutes: 30 + i))),
    ];
    final feedDeals = [
      for (var i = 0; i < 120; i++)
        flashDeal(i, now.add(Duration(minutes: 10 + i))),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: FlashDealsSection(deals: railDeals)),
          SliverList.builder(
            itemCount: feedDeals.length,
            itemBuilder: (_, i) => DealCard(deal: feedDeals[i]),
          ),
        ]),
      ),
    ));
    final visibleCountdowns = find.textContaining(RegExp(r'^\d\d:\d\d'));
    // 120 feed cards + the rail cards that fit in its 800px viewport.
    expect(visibleCountdowns.evaluate().length, greaterThanOrEqualTo(120));

    // Control frame with no tick (first tick is at t=1s). Image placeholders
    // shimmer every frame regardless of the clock; subtract what they cost.
    await tester.pump(const Duration(milliseconds: 500));
    rebuilt.clear();
    await tester.pump(const Duration(milliseconds: 400));
    final baseline = countByType(rebuilt);

    rebuilt.clear();
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100)); // crosses t=1s
    final tickFrame = countByType(rebuilt);

    final causedByTick = {
      for (final e in tickFrame.entries)
        if (e.value - (baseline[e.key] ?? 0) > 0)
          e.key: e.value - (baseline[e.key] ?? 0),
    };
    // ignore: avoid_print
    print('Baseline frame: $baseline');
    // ignore: avoid_print
    print('Rebuilt by one tick: $causedByTick');
    // Includes rail cards built in the list's cache extent, just off screen.
    final built = find
        .byType(FlashCountdownText, skipOffstage: false)
        .evaluate()
        .length;
    expect(causedByTick, {'Obx': built, 'Text': built},
        reason: 'a tick may rebuild only the countdown text');

    clock.onClose();
    impressions.onClose();
  });

  testWidgets('an expiring deal rebuilds its own card once, not its neighbours',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 4000);
    addTearDown(tester.view.reset);

    final clock = Get.put(ClockService(now: () => now));
    final impressions = putImpressionService();
    final deals = [
      flashDeal(1, now.add(const Duration(minutes: 5))),
      flashDeal(2, now.add(const Duration(seconds: 2))), // expires first
      flashDeal(3, now.add(const Duration(minutes: 5))),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [for (final d in deals) DealCard(deal: d)]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500)); // settle focus

    rebuilt.clear();
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    final counts = countByType(rebuilt);
    // ignore: avoid_print
    print('Rebuilt across expiry: $counts');
    expect(counts['FlashExpiryBuilder'], 1);
    expect(counts['Card'], 1, reason: 'only the expired card rebuilds');
    expect(find.text('EXPIRED'), findsOneWidget);

    clock.onClose();
    impressions.onClose();
  });

  testWidgets('countdowns on a covered route stop ticking until uncovered',
      (tester) async {
    final clock = Get.put(ClockService(now: () => now));
    final impressions = putImpressionService();
    final deal = flashDeal(1, now.add(const Duration(minutes: 5)));
    final navigator = GlobalKey<NavigatorState>();
    // Image placeholders shimmer forever, so pumpAndSettle never settles.
    const transition = Duration(milliseconds: 400);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: Scaffold(body: ListView(children: [DealCard(deal: deal)])),
    ));
    expect(find.text('05:00'), findsOneWidget);

    navigator.currentState!
        .push(MaterialPageRoute(builder: (_) => const Scaffold()));
    await tester.pump(transition);

    rebuilt.clear();
    for (var i = 0; i < 3; i++) {
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(rebuilt.where((t) => t == 'Obx'), isEmpty,
        reason: 'covered countdowns must not rebuild on ticks');

    navigator.currentState!.pop();
    await tester.pump();
    // Shows the current time straight away, not the time it was covered at.
    expect(find.text('04:57', skipOffstage: false), findsOneWidget);
    await tester.pump(transition);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('04:56'), findsOneWidget, reason: 'ticking again');

    clock.onClose();
    impressions.onClose();
  });
}
