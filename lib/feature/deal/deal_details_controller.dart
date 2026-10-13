import 'package:get/get.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../service/analytics_service.dart';
import '../../service/cart_service.dart';
import '../../util/log_service.dart';

/// Backs the deal page. It is opened two ways:
/// - in-app, with the already-loaded [DealModel] passed as `Get.arguments`;
/// - from a deep link (`/deal?id=42&source=push`), where only the `id` query
///   parameter is available and the deal must be fetched.
class DealDetailsController extends GetxController {
  final DealRepo dealRepo;
  final CartService cartService;
  final AnalyticsService analytics;

  DealDetailsController({
    required this.dealRepo,
    required this.cartService,
    required this.analytics,
  });

  /// Null while a deep-linked deal is still loading.
  final _deal = Rxn<DealModel>();
  DealModel? get deal => _deal.value;

  /// Null only for a malformed link without a numeric id.
  int? _dealId;

  /// Subscribes to the app-wide CartService, which outlives this controller,
  /// so it must be disposed explicitly in [onClose].
  late final Worker _cartWorker;

  final _quantityLeft = RxnInt();
  int? get quantityLeft => _quantityLeft.value;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args is DealModel) {
      _dealId = args.id;
      _showDeal(args);
    } else {
      // Query parameters always arrive as strings.
      _dealId = int.tryParse(Get.parameters['id'] ?? '');
      _loadDeal();
    }
    analytics.logEvent('deal_details_view', {
      'deal_id': _dealId,
      'source': Get.parameters['source'] ?? 'unknown',
    });
    // Whenever the cart changes, re-check this deal's remaining stock so the
    // details screen never shows stale availability.
    _cartWorker =
        ever(cartService.itemCount, (_) => _recheckAvailability());
  }

  @override
  void onClose() {
    _cartWorker.dispose();
    super.onClose();
  }

  void _showDeal(DealModel deal) {
    _deal.value = deal;
    _quantityLeft.value = deal.quantityLeft;
  }

  Future<void> _loadDeal() async {
    final id = _dealId;
    if (id == null) {
      LogService.error('deal link without a valid id: ${Get.parameters}');
      return;
    }
    try {
      _showDeal(await dealRepo.fetchById(id));
    } catch (e) {
      LogService.error('loading deal $id failed', e);
    }
  }

  Future<void> _recheckAvailability() async {
    final id = _dealId;
    if (id == null || deal == null) return;
    LogService.log('re-checking availability for deal $id');
    final fresh = await dealRepo.fetchById(id);
    _quantityLeft.value = fresh.quantityLeft;
  }

  void addToCart() {
    final deal = this.deal;
    if (deal == null) return;
    final result = cartService.add(deal);
    if (result != AddToCartResult.added) {
      Get.snackbar(
        "Can't add to bag",
        result == AddToCartResult.flashSaleEnded
            ? 'This flash sale has ended.'
            : 'No more of this deal is available.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      return;
    }
    Get.snackbar(
      'Added to bag',
      '${deal.name} — pick up ${deal.pickupWindow.label}',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }
}
