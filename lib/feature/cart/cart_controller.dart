import 'package:get/get.dart';

import '../../model/deal_model.dart';
import '../../repository/order_repo.dart';
import '../../service/api_exception.dart';
import '../../service/cart_service.dart';
import '../../util/log_service.dart';

class CartController extends GetxController {
  final CartService cartService;
  final OrderRepo orderRepo;

  CartController({required this.cartService, required this.orderRepo});

  final isCheckingOut = false.obs;

  /// Expired holds are not dropped while the user browses; checkout is where
  /// they matter. It first places fresh holds on any that expired, and only
  /// charges if every unit is held. Nothing is charged without the user's
  /// tap on a bag whose contents they can see.
  Future<void> checkout() async {
    if (cartService.items.isEmpty ||
        isCheckingOut.value ||
        cartService.isReserving) {
      return;
    }
    isCheckingOut.value = true;
    try {
      final lost = await cartService.renewHolds();
      if (lost.isNotEmpty) {
        _notifyUnavailable(lost);
        return;
      }
      if (cartService.items.isEmpty) return;
      final order = await orderRepo.checkout(cartService.items.toList());
      cartService.clear();
      _snackbar('Order confirmed', 'Order #${order.id} — pick up soon!');
    } on ApiException catch (e) {
      LogService.error('checkout failed', e);
      await _handleCheckoutError(e);
    } finally {
      isCheckingOut.value = false;
    }
  }

  Future<void> _handleCheckoutError(ApiException e) async {
    switch (e.statusCode) {
      case 410:
        // A hold we believed valid was rejected (clock skew, or it ran out
        // while the request was in flight). Hold everything again, but let
        // the user confirm instead of charging behind their back.
        final lost = await cartService.renewHolds(all: true);
        if (lost.isNotEmpty) {
          _notifyUnavailable(lost);
        } else {
          _snackbar('Your hold ran out',
              "We've reserved your items again. Tap Checkout to confirm.");
        }
      case 502:
        _snackbar("Payment didn't go through",
            "You weren't charged and your bag is unchanged. Please try again.");
      default:
        _snackbar("Checkout didn't go through",
            'Your bag is unchanged. Please try again.');
    }
  }

  void _notifyUnavailable(List<DealModel> deals) {
    final names = deals.map((d) => d.name).join(', ');
    _snackbar(
      deals.length == 1
          ? 'An item is no longer available'
          : 'Some items are no longer available',
      "$names couldn't be reserved again and "
      '${deals.length == 1 ? 'was' : 'were'} removed from your bag. '
      'Nothing was charged — review your bag and tap Checkout again.',
    );
  }

  void _snackbar(String title, String message) {
    Get.closeAllSnackbars();
    Get.snackbar(title, message,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4));
  }
}
