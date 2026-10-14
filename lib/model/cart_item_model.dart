import 'deal_model.dart';
import 'reservation_model.dart';

/// One unit in the bag and its stock hold.
///
/// Every unit has its own reservation: the API cannot change a hold's
/// quantity, so adding one more is one more hold, and removing one releases
/// exactly that hold — which cannot fail the way re-reserving a smaller
/// quantity could.
class HeldUnit {
  /// Null while the hold is being placed (the bag shows the unit at once,
  /// optimistically).
  ReservationModel? reservation;

  HeldUnit([this.reservation]);

  bool get isReserving => reservation == null;

  bool isExpiredAt(DateTime now) => reservation?.isExpiredAt(now) ?? false;
}

class CartItemModel {
  final DealModel deal;
  final List<HeldUnit> units;

  CartItemModel({required this.deal, List<HeldUnit>? units})
      : units = units ?? [];

  int get quantity => units.length;

  num get lineTotal => deal.price * quantity;

  bool get isReserving => units.any((u) => u.isReserving);

  /// When the first of this line's holds runs out; null while none is held.
  DateTime? get earliestExpiry {
    DateTime? earliest;
    for (final unit in units) {
      final expiresAt = unit.reservation?.expiresAt;
      if (expiresAt != null &&
          (earliest == null || expiresAt.isBefore(earliest))) {
        earliest = expiresAt;
      }
    }
    return earliest;
  }
}
