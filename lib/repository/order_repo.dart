import 'package:get/get.dart';

import '../model/cart_item_model.dart';
import '../model/order_model.dart';
import '../model/reservation_model.dart';
import '../service/fake_api_service.dart';

class OrderRepo extends GetxService {
  final FakeApiService api;

  OrderRepo({required this.api});

  Future<List<OrderModel>> fetchOrders() async {
    final json = await api.getOrders();
    return json.map(OrderModel.fromJson).toList();
  }

  Future<OrderModel> checkout(List<CartItemModel> items) async {
    final json = await api.checkout(checkoutItems(items));
    return OrderModel.fromJson(json);
  }

  /// One checkout item per held unit: the API takes one reservation id per
  /// item, and every unit in the bag has its own hold.
  static List<Map<String, dynamic>> checkoutItems(List<CartItemModel> items) =>
      [
        for (final item in items)
          for (final unit in item.units)
            {
              'dealId': item.deal.id,
              'quantity': 1,
              'reservationId': unit.reservation?.id,
            }
      ];

  Future<ReservationModel> reserve(int dealId, {int quantity = 1}) async {
    final json = await api.reserveDeal(dealId, quantity: quantity);
    return ReservationModel.fromJson(json);
  }

  Future<void> releaseReservation(String reservationId) =>
      api.releaseReservation(reservationId);
}
