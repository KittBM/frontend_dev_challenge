import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/feature/shared_widget/deal_card.dart';
import 'package:rescu/feature/shared_widget/flash_countdown.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/service/cart_service.dart';
import 'package:rescu/service/clock_service.dart';

import 'helpers.dart';

DealModel flashDeal(int id, DateTime endsAt) {
  final d = fakeDeal(id);
  return DealModel(
    id: d.id,
    name: d.name,
    description: d.description,
    imageUrl: d.imageUrl,
    originalPrice: d.originalPrice,
    price: d.price,
    currencyCode: d.currencyCode,
    quantityLeft: d.quantityLeft,
    storeId: d.storeId,
    storeName: d.storeName,
    storeAddress: d.storeAddress,
    lat: d.lat,
    lng: d.lng,
    rating: d.rating,
    tags: d.tags,
    pickupWindow: d.pickupWindow,
    flashSaleEndsAt: endsAt,
  );
}

void main() {
  // Whole second, so the clock's first tick is exactly one second away.
  late DateTime now;

  setUp(() => now = DateTime(2026, 10, 13, 12));
  tearDown(Get.reset);

  group('formatCountdown', () {
    test('mm:ss under an hour', () {
      expect(formatCountdown(const Duration(minutes: 7, seconds: 5)), '07:05');
    });

    test('hh:mm:ss from one hour up', () {
      expect(formatCountdown(const Duration(hours: 1)), '01:00:00');
      expect(formatCountdown(const Duration(hours: 1, minutes: 15, seconds: 3)),
          '01:15:03');
    });

    test('rounds up partial seconds and clamps at zero', () {
      expect(formatCountdown(const Duration(milliseconds: 200)), '00:01');
      expect(formatCountdown(Duration.zero), '00:00');
      expect(formatCountdown(const Duration(seconds: -5)), '00:00');
    });
  });

  group('CartService', () {
    test('refuses a flash deal whose sale has ended', () {
      final cart = CartService(clock: ClockService(now: () => now));
      final deal = flashDeal(1, now.subtract(const Duration(seconds: 1)));

      expect(cart.add(deal), AddToCartResult.flashSaleEnded);
      expect(cart.items, isEmpty);
    });

    testWidgets('removes a flash deal from the bag when its sale ends',
        (tester) async {
      await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
      final cart = CartService(clock: ClockService(now: () => now));
      cart.add(flashDeal(1, now.add(const Duration(seconds: 5))));
      cart.add(fakeDeal(2));

      await tester.pump(const Duration(seconds: 4));
      expect(cart.items.map((i) => i.deal.id), [1, 2]);

      await tester.pump(const Duration(seconds: 1));
      expect(cart.items.map((i) => i.deal.id), [2]);
      expect(cart.itemCount.value, 1);

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Flash sale ended'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    // testWidgets fails on any timer still pending when the test ends.
    testWidgets('removing a flash line cancels its expiry timer',
        (tester) async {
      final cart = CartService(clock: ClockService(now: () => now));
      cart.add(flashDeal(1, now.add(const Duration(minutes: 1))));
      cart.add(flashDeal(2, now.add(const Duration(minutes: 1))));
      cart.decrement(1);
      cart.clear();
      expect(cart.items, isEmpty);
    });
  });

  testWidgets('DealCard counts down live, then switches to Expired',
      (tester) async {
    final clock = Get.put(ClockService(now: () => now));
    final deal = flashDeal(1, now.add(const Duration(seconds: 3)));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DealCard(deal: deal)),
    ));
    expect(find.text('00:03'), findsOneWidget);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('00:02'), findsOneWidget);

    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('EXPIRED'), findsOneWidget);
    expect(find.textContaining('FLASH SALE'), findsNothing);

    // Stop the shared ticker so the test ends without pending timers.
    clock.onClose();
  });

  group('after the device slept', () {
    // While suspended, the monotonic clock behind Dart timers stops but the
    // wall clock keeps going. Simulate that: move `now` without pumping any
    // fake time, so no timer fires, then bring the app back to the foreground.
    Future<void> sleepAndResume(WidgetTester tester, Duration slept) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = now.add(slept);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    }

    testWidgets('cards re-check expiry and countdowns catch up on resume',
        (tester) async {
      final clock = Get.put(ClockService(now: () => now));
      final ending = flashDeal(1, now.add(const Duration(minutes: 5)));
      final running = flashDeal(2, now.add(const Duration(minutes: 30)));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(children: [
            DealCard(deal: ending),
            DealCard(deal: running),
          ]),
        ),
      ));
      expect(find.text('05:00'), findsOneWidget);

      await sleepAndResume(tester, const Duration(minutes: 10));

      expect(find.text('EXPIRED'), findsOneWidget);
      expect(find.text('20:00'), findsOneWidget);
      clock.onClose();
    });

    testWidgets('the bag drops ended lines and re-arms the rest on resume',
        (tester) async {
      await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
      final clock = Get.put(ClockService(now: () => now));
      final cart = Get.put(CartService(clock: clock));
      cart.add(flashDeal(1, now.add(const Duration(minutes: 5))));
      cart.add(flashDeal(2, now.add(const Duration(minutes: 30))));

      await sleepAndResume(tester, const Duration(minutes: 10));
      expect(cart.items.map((i) => i.deal.id), [2]);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('deal 1 was removed from your bag.'), findsOneWidget);

      // Deal 2's timer was re-armed for the 20 minutes actually left, not the
      // 30 it was originally set for.
      now = now.add(const Duration(minutes: 20));
      await tester.pump(const Duration(minutes: 20));
      expect(cart.items, isEmpty);

      await tester.pumpAndSettle(const Duration(seconds: 5));
      cart.onClose();
      clock.onClose();
    });
  });
}
