import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/feature/home/home_controller.dart';
import 'package:rescu/feature/home/home_screen.dart';
import 'package:rescu/feature/shared_widget/deal_card.dart';
import 'package:rescu/model/paged_response_model.dart';

import 'helpers.dart';

void main() {
  tearDown(Get.reset);

  testWidgets('RES-105: scrolling the feed does not rebuild deal cards',
      (tester) async {
    final repo = FakeDealRepo();
    putImpressionService();
    final controller = Get.put(HomeController(dealRepo: repo));
    await tester.pumpWidget(const GetMaterialApp(home: HomeScreen()));
    repo.pendingPages.removeAt(0).complete(PagedResponseModel(
        items: [for (var i = 1; i <= 20; i++) fakeDeal(i)],
        page: 1,
        totalPages: 1));
    await tester.pump();
    await tester.pump();
    expect(find.byType(DealCard), findsWidgets);

    var cardBuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is DealCard) cardBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    // Small scroll steps: no new card comes into view, so nothing in the
    // feed should build. Before the fix every mounted card rebuilt per step.
    for (final offset in [10.0, 20.0, 30.0, 40.0]) {
      controller.scrollController.jumpTo(offset);
      await tester.pump();
    }
    expect(cardBuilds, 0);
    debugOnRebuildDirtyWidget = null;

    // Crossing the threshold still shows the scroll-to-top button.
    controller.scrollController.jumpTo(900);
    await tester.pump();
    expect(controller.showScrollToTop.value, isTrue);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // Card images have no real URL in tests; ignore those load errors.
    while (tester.takeException() != null) {}
  });
}
