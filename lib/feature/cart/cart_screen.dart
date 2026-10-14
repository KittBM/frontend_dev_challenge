import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app_config.dart';
import '../../model/cart_item_model.dart';
import '../../service/clock_service.dart';
import '../shared_widget/flash_countdown.dart';
import '../shared_widget/the_network_image.dart';
import 'cart_controller.dart';

class CartScreen extends GetView<CartController> {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = controller.cartService;
    return Scaffold(
      appBar: AppBar(title: const Text('My bag')),
      body: Obx(() {
        // Read here, inside Obx: itemBuilder runs later, during layout,
        // where Obx would not see the read.
        final checkingOut = controller.isCheckingOut.value;
        if (cart.items.isEmpty) {
          return const Center(child: Text('Your bag is empty'));
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: cart.items.length,
          itemBuilder: (context, index) {
            final item = cart.items[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.white,
              elevation: 0.5,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    TheNetworkImage(
                      url: item.deal.imageUrl,
                      width: 64,
                      height: 64,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.deal.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14.5, fontWeight: FontWeight.w600)),
                          Text(item.deal.storeName,
                              style: TextStyle(
                                  fontSize: 12.5, color: Colors.grey.shade600)),
                          Text('฿${item.deal.price.toStringAsFixed(0)} each',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppConfig.primaryGreen,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          _HoldStatus(item: item),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: checkingOut
                              ? null
                              : () => cart.decrement(item.deal.id),
                        ),
                        Text('${item.quantity}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed:
                              checkingOut ? null : () => cart.add(item.deal),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }),
      bottomNavigationBar: Obx(() {
        if (cart.items.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          color: Colors.white,
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Total', style: TextStyle(fontSize: 13)),
                  Text('฿${cart.total.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                // Checkout waits until every unit's hold has landed.
                child: FilledButton(
                  onPressed: controller.isCheckingOut.value || cart.isReserving
                      ? null
                      : controller.checkout,
                  child: controller.isCheckingOut.value
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(cart.isReserving ? 'Reserving…' : 'Checkout'),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// How long this line's stock is held. Rebuilds every second, so it is kept
/// to this one line of text.
class _HoldStatus extends StatelessWidget {
  final CartItemModel item;

  const _HoldStatus({required this.item});

  static const _warnBelow = Duration(minutes: 1);

  @override
  Widget build(BuildContext context) {
    final clock = Get.find<ClockService>();
    return Obx(() {
      final now = clock.tick.value;
      final IconData icon;
      final String text;
      final Color color;
      final expiresAt = item.earliestExpiry;
      if (item.isReserving) {
        (icon, text, color) =
            (Icons.hourglass_top, 'Reserving…', Colors.grey.shade600);
      } else if (expiresAt == null || !now.isBefore(expiresAt)) {
        (icon, text, color) = (
          Icons.error_outline,
          "Hold expired — we'll try to reserve it again at checkout",
          Colors.orange.shade800,
        );
      } else {
        final left = expiresAt.difference(now);
        (icon, text, color) = (
          Icons.lock_clock,
          'Held for ${formatCountdown(left)}',
          left < _warnBelow ? Colors.orange.shade800 : Colors.grey.shade700,
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ],
      );
    });
  }
}
