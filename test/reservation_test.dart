import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/feature/cart/cart_controller.dart';
import 'package:rescu/feature/cart/cart_screen.dart';
import 'package:rescu/model/reservation_model.dart';
import 'package:rescu/service/api_exception.dart';
import 'package:rescu/service/cart_service.dart';
import 'package:rescu/service/clock_service.dart';

import 'helpers.dart';

void main() {
  late DateTime now;
  late FakeOrderRepo orders;
  late ClockService clock;
  late CartService cart;
  late CartController controller;

  const contention = ApiException('someone grabbed it', statusCode: 409);

  List<String?> heldIds(int dealId) => [
        for (final u in cart.items.firstWhere((i) => i.deal.id == dealId).units)
          u.reservation?.id
      ];

  setUp(() {
    now = DateTime(2026, 10, 14, 12); // whole second: ticks land on seconds
    orders = FakeOrderRepo(now: () => now);
  });

  tearDown(Get.reset);

  /// The bag screen in a GetMaterialApp, so snackbars have an overlay.
  Future<void> pumpBag(WidgetTester tester) async {
    clock = Get.put(ClockService(now: () => now));
    cart = Get.put(CartService(clock: clock, orders: orders));
    controller = Get.put(CartController(cartService: cart, orderRepo: orders));
    await tester.pumpWidget(const GetMaterialApp(home: CartScreen()));
  }

  /// Lets snackbars finish and stops the ticker, so no timer is left pending.
  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));
    clock.onClose();
    cart.onClose();
  }

  group('adding is optimistic', () {
    testWidgets('the unit is in the bag at once, held when the API answers',
        (tester) async {
      orders.holdReserves = true;
      await pumpBag(tester);

      expect(cart.add(fakeDeal(1)), AddToCartResult.added);
      await tester.pump();
      expect(cart.itemCount.value, 1);
      expect(find.text('Reserving…'), findsWidgets);

      orders.pendingReserves.single.complete(orders.newHold(1));
      await tester.pump();
      expect(heldIds(1), ['res_1']);
      expect(find.text('Held for 05:00'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a 409 rolls the unit back with a plain-language notice',
        (tester) async {
      orders.reserveErrors.add(contention);
      await pumpBag(tester);

      cart.add(fakeDeal(1, name: 'Sushi Box'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(cart.items, isEmpty);
      expect(cart.itemCount.value, 0);
      expect(find.text("Couldn't add Sushi Box"), findsOneWidget);
      expect(find.textContaining('Someone just took the last one'),
          findsOneWidget);
      expect(find.textContaining('409'), findsNothing);
      await finish(tester);
    });

    testWidgets('a rollback only removes the unit that failed', (tester) async {
      orders.reserveErrors.addAll([null, contention]);
      await pumpBag(tester);

      cart.add(fakeDeal(1));
      cart.add(fakeDeal(1));
      await tester.pump();

      expect(cart.itemCount.value, 1);
      expect(heldIds(1), ['res_1']);
      await finish(tester);
    });
  });

  group('removing releases holds', () {
    testWidgets(
        'a unit removed while its hold is placed releases it on '
        'arrival', (tester) async {
      orders.holdReserves = true;
      await pumpBag(tester);

      cart.add(fakeDeal(1));
      cart.remove(1);
      orders.pendingReserves.single.complete(orders.newHold(1));
      await tester.pump();

      expect(cart.items, isEmpty);
      expect(orders.released, ['res_1'],
          reason: 'no stock is kept for a unit nobody wants');
      await finish(tester);
    });

    testWidgets('decrement releases the hold that runs out soonest',
        (tester) async {
      // The soonest-expiring hold is deliberately not the first unit, so
      // "always drop the first one" would fail.
      orders.holdReserves = true;
      await pumpBag(tester);
      cart.add(fakeDeal(1));
      cart.add(fakeDeal(1));
      ReservationModel hold(String id, int minutes) => ReservationModel(
          id: id,
          dealId: 1,
          quantity: 1,
          expiresAt: now.add(Duration(minutes: minutes)));
      orders.pendingReserves[0].complete(hold('late', 5));
      orders.pendingReserves[1].complete(hold('soon', 2));
      await tester.pump();

      cart.decrement(1);
      await tester.pump();

      expect(heldIds(1), ['late']);
      expect(orders.released, ['soon']);
      await finish(tester);
    });

    testWidgets('removing a line releases every hold in it', (tester) async {
      await pumpBag(tester);
      cart.add(fakeDeal(1));
      cart.add(fakeDeal(1));
      await tester.pump();

      cart.remove(1);
      await tester.pump();

      expect(orders.released, unorderedEquals(['res_1', 'res_2']));
      await finish(tester);
    });
  });

  group('checkout', () {
    testWidgets('sends one item per unit with its reservation id',
        (tester) async {
      await pumpBag(tester);
      cart.add(fakeDeal(1));
      cart.add(fakeDeal(1));
      cart.add(fakeDeal(2));
      await tester.pump();

      await controller.checkout();
      await tester.pump();

      expect(orders.checkouts.single, [
        {'dealId': 1, 'quantity': 1, 'reservationId': 'res_1'},
        {'dealId': 1, 'quantity': 1, 'reservationId': 'res_2'},
        {'dealId': 2, 'quantity': 1, 'reservationId': 'res_3'},
      ]);
      expect(cart.items, isEmpty);
      expect(orders.released, isEmpty, reason: 'the order used the holds');
      await finish(tester);
    });

    testWidgets('an expired hold stays in the bag, marked, until checkout',
        (tester) async {
      await pumpBag(tester);
      cart.add(fakeDeal(1));
      await tester.pump();

      now = now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 1));

      expect(cart.itemCount.value, 1);
      expect(find.textContaining('Hold expired'), findsOneWidget);
      await finish(tester);
    });
  });

  test('a reservation is expired from its expiry instant on', () {
    final r = ReservationModel(
        id: 'r', dealId: 1, quantity: 1, expiresAt: DateTime(2026, 1, 1, 12));
    expect(r.isExpiredAt(DateTime(2026, 1, 1, 11, 59, 59)), isFalse);
    expect(r.isExpiredAt(DateTime(2026, 1, 1, 12)), isTrue);
  });
}
