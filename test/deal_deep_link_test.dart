import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/binding/deal_details_binding.dart';
import 'package:rescu/feature/deal/deal_details_controller.dart';
import 'package:rescu/feature/deal/deal_details_screen.dart';
import 'package:rescu/repository/deal_repo.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/cart_service.dart';

import 'helpers.dart';

void main() {
  late FakeDealRepo repo;
  late CartService cart;
  late AnalyticsService analytics;

  Widget app() => GetMaterialApp(
        initialRoute: '/home',
        getPages: [
          GetPage(name: '/home', page: () => const Scaffold()),
          GetPage(
              name: '/deal',
              page: () => const DealDetailsScreen(),
              binding: DealDetailsBinding()),
        ],
      );

  setUp(() {
    repo = FakeDealRepo();
    Get.put<DealRepo>(repo);
    cart = Get.put(CartService());
    analytics = Get.put(AnalyticsService());
  });

  tearDown(Get.reset);

  testWidgets('RES-107: deep link with only an id loads a working deal page',
      (tester) async {
    repo.fetchByIdDelay = const Duration(milliseconds: 600);
    await tester.pumpWidget(app());
    Get.toNamed('/deal?id=42&source=push'); // no arguments, like a push link
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // route transition

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(repo.fetchByIdCalls, [42]);
    expect(find.text('deal 42'), findsOneWidget);

    // The page is fully usable: add to bag works.
    Get.find<DealDetailsController>().addToCart();
    expect(cart.items.single.deal.id, 42);

    expect(analytics.events.first.properties,
        {'deal_id': 42, 'source': 'push'});
    await tester.pump(const Duration(seconds: 3)); // let the snackbar finish
  });

  testWidgets('RES-107: in-app navigation still uses the passed deal',
      (tester) async {
    await tester.pumpWidget(app());
    Get.toNamed('/deal?id=7&source=home', arguments: fakeDeal(7));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // route transition

    expect(find.text('deal 7'), findsOneWidget);
    expect(repo.fetchByIdCalls, isEmpty);
  });
}
