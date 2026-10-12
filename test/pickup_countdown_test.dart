import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/order/widget/pickup_countdown.dart';

void main() {
  testWidgets('RES-102: countdown stops ticking once removed from the tree',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PickupCountdown(
          pickupStart: DateTime.now().add(const Duration(minutes: 10))),
    ));
    await tester.pump(const Duration(seconds: 2)); // ticks while mounted

    await tester.pumpWidget(const SizedBox()); // leave the screen
    await tester.pump(const Duration(seconds: 3));

    // The old code threw "setState() called after dispose()" here, and the
    // test binding would also fail on the still-pending periodic timer.
    expect(tester.takeException(), isNull);
  });
}
