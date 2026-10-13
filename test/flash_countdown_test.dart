import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/feature/shared_widget/deal_card.dart';
import 'package:rescu/feature/shared_widget/flash_countdown.dart';
import 'package:rescu/model/deal_model.dart';
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

}
