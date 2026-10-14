import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/binding/deal_details_binding.dart';
import 'package:rescu/feature/deal/deal_details_controller.dart';
import 'package:rescu/repository/deal_repo.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/cart_service.dart';

import 'helpers.dart';

/// Stand-in for DealDetailsScreen: same route binding and controller,
/// without the network image widgets.
class _DealPage extends GetView<DealDetailsController> {
  const _DealPage();

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Text(controller.deal?.name ?? 'loading'));
}

void main() {
  late FakeDealRepo repo;
  late CartService cart;

  Widget app() => GetMaterialApp(
        initialRoute: '/home',
        getPages: [
          GetPage(name: '/home', page: () => const Scaffold()),
          GetPage(
              name: '/deal',
              page: () => const _DealPage(),
              binding: DealDetailsBinding()),
        ],
      );

  setUp(() {
    repo = FakeDealRepo();
    Get.put<DealRepo>(repo);
    cart = Get.put(CartService(orders: FakeOrderRepo()));
    Get.put(AnalyticsService());
  });

  tearDown(Get.reset);

  testWidgets('RES-103: closed deal pages stop reacting to cart changes',
      (tester) async {
    await tester.pumpWidget(app());
    for (final id in [1, 2, 3]) {
      Get.toNamed('/deal?id=$id', arguments: fakeDeal(id));
      await tester.pumpAndSettle();
      Get.back();
      await tester.pumpAndSettle();
    }
    expect(Get.isRegistered<DealDetailsController>(), isFalse);

    cart.add(fakeDeal(99));
    await tester.pump();

    expect(repo.fetchByIdCalls, isEmpty);
  });

  testWidgets('RES-103: the open deal page still re-checks its stock',
      (tester) async {
    await tester.pumpWidget(app());
    Get.toNamed('/deal?id=1', arguments: fakeDeal(1));
    await tester.pumpAndSettle();

    cart.add(fakeDeal(1));
    await tester.pump();

    expect(repo.fetchByIdCalls, [1]);
  });
}
