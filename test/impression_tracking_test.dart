import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/feature/shared_widget/track_impression.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/impression_service.dart';

import 'helpers.dart';

/// 100 px tall cards in a list, standing in for deal cards.
Widget trackedList(String source, List<int> dealIds,
        {ScrollController? controller}) =>
    ListView(
      controller: controller,
      children: [
        for (var i = 0; i < dealIds.length; i++)
          TrackImpression(
            dealId: dealIds[i],
            source: source,
            position: i,
            child: SizedBox(height: 100, child: Text('deal ${dealIds[i]}')),
          ),
      ],
    );

void main() {
  late List<List<Map<String, dynamic>>> sentBatches;
  late ImpressionService impressions;

  List<Map<String, dynamic>> impressionsLogged() => [
        for (final e in Get.find<AnalyticsService>().events)
          if (e.name == 'deal_impression') e.properties,
      ];

  setUp(() {
    sentBatches = [];
    impressions = putImpressionService(sentBatches: sentBatches);
  });

  tearDown(Get.reset);

  // Cancels the batch deadline. testWidgets fails on timers still pending
  // when the body ends, before tearDown runs.
  void stopBatching() => impressions.onClose();

  Future<void> pumpList(WidgetTester tester, Widget list,
      {double height = 250}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(height: height, child: list),
        ),
      ),
    ));
  }

  testWidgets('a card at least half visible for 1 s is reported once',
      (tester) async {
    // 250 px viewport: cards 1 and 2 fully visible, card 3 exactly half.
    await pumpList(tester, trackedList('home_feed', [1, 2, 3, 4]));

    await tester.pump(const Duration(milliseconds: 900));
    expect(impressionsLogged(), isEmpty, reason: 'not a full second yet');

    await tester.pump(const Duration(milliseconds: 100));
    expect(impressionsLogged(), [
      {'deal_id': 1, 'source': 'home_feed', 'position': 0},
      {'deal_id': 2, 'source': 'home_feed', 'position': 1},
      {'deal_id': 3, 'source': 'home_feed', 'position': 2},
    ]);

    await tester.pump(const Duration(seconds: 5));
    expect(impressionsLogged(), hasLength(3), reason: 'once per deal');
    stopBatching();
  });

  testWidgets('less than half visible never counts', (tester) async {
    // 240 px viewport: card 3 is 40% visible.
    await pumpList(tester, trackedList('home_feed', [1, 2, 3]), height: 240);
    await tester.pump(const Duration(seconds: 3));

    expect(impressionsLogged().map((e) => e['deal_id']), [1, 2]);
    stopBatching();
  });

  testWidgets('scrolling a card away before 1 s restarts its second',
      (tester) async {
    final scroll = ScrollController();
    await pumpList(tester, trackedList('home_feed', [1, 2, 3, 4, 5, 6],
        controller: scroll));

    await tester.pump(const Duration(milliseconds: 600));
    scroll.jumpTo(350); // cards 1-3 leave, 4-6 arrive
    await tester.pump(); // pump(d) moves the clock before drawing
    await tester.pump(const Duration(milliseconds: 600));
    scroll.jumpTo(0); // back: cards 1-3 start a fresh second
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(impressionsLogged(), isEmpty,
        reason: 'no card stayed visible for 1 continuous second');

    await tester.pump(const Duration(milliseconds: 400));
    expect(impressionsLogged().map((e) => e['deal_id']), [1, 2, 3]);
    stopBatching();
  });

  testWidgets('a deal is reported once per session across lists',
      (tester) async {
    // Deal 7 shows in both the rail and the feed at the same time.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          SizedBox(height: 200, child: trackedList('flash_rail', [7])),
          SizedBox(height: 200, child: trackedList('home_feed', [8, 7])),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));

    final logged = impressionsLogged();
    expect(logged.where((e) => e['deal_id'] == 7), hasLength(1));
    expect(logged.map((e) => e['deal_id']).toSet(), {7, 8});
    stopBatching();
  });

  testWidgets('a card covered by another route does not count',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: Scaffold(body: trackedList('home_feed', [1])),
    ));
    await tester.pump(const Duration(milliseconds: 500));

    navigator.currentState!
        .push(MaterialPageRoute(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(impressionsLogged(), isEmpty);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(impressionsLogged().map((e) => e['deal_id']), [1]);
    stopBatching();
  });

  testWidgets('impressions are delivered in batches of 10', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ids = [for (var i = 1; i <= 12; i++) i];
    await pumpList(tester, trackedList('search', ids), height: 1200);
    await tester.pump(const Duration(seconds: 1));

    expect(sentBatches, hasLength(1));
    expect(sentBatches.single, hasLength(10));
    expect(sentBatches.single.first['name'], 'deal_impression');
    expect(sentBatches.single.first['properties'],
        {'deal_id': 1, 'source': 'search', 'position': 0});

    await tester.pump(const Duration(seconds: 15)); // the other 2
    expect(sentBatches.map((b) => b.length), [10, 2]);
    stopBatching();
  });
}
