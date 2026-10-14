import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../model/cart_item_model.dart';
import '../model/deal_model.dart';
import '../repository/order_repo.dart';
import '../util/log_service.dart';
import 'api_exception.dart';
import 'clock_service.dart';

enum AddToCartResult { added, flashSaleEnded, noStockLeft }

/// App-wide bag. Lives for the whole session.
///
/// Every unit in the bag holds stock on the backend through its own
/// reservation (see [HeldUnit]). Adding is optimistic: the unit shows up at
/// once and its hold is placed in the background; if the backend refuses,
/// the unit is rolled back with a notice.
class CartService extends GetxService {
  CartService({ClockService? clock, required OrderRepo orders})
      : _clock = clock,
        _orders = orders,
        _now = clock?.now ?? DateTime.now;

  final ClockService? _clock;
  final OrderRepo _orders;
  final DateTime Function() _now;

  final items = <CartItemModel>[].obs;
  final itemCount = 0.obs;

  /// One-shot timer per flash-sale line, firing when its sale ends.
  final _expiryTimers = <int, Timer>{};

  Worker? _resumeWorker;

  @override
  void onInit() {
    super.onInit();
    final clock = _clock;
    // After the device slept, expiry timers may fire late (see
    // ClockService.resumed): re-check every flash line against the wall clock.
    if (clock != null) {
      _resumeWorker = ever(clock.resumed, (_) => _recheckFlashSales());
    }
  }

  /// True while any hold is still being placed. Checkout waits for them.
  bool get isReserving => items.any((i) => i.isReserving);

  AddToCartResult add(DealModel deal) {
    if (deal.isFlashSaleOver(_now())) {
      LogService.log('cart: flash sale for deal ${deal.id} has ended');
      return AddToCartResult.flashSaleEnded;
    }
    var line = items.firstWhereOrNull((i) => i.deal.id == deal.id);
    if ((line?.quantity ?? 0) >= deal.quantityLeft) {
      LogService.log('cart: cannot add more of deal ${deal.id}');
      return AddToCartResult.noStockLeft;
    }
    if (line == null) {
      line = CartItemModel(deal: deal);
      items.add(line);
      _watchFlashSale(deal);
    }
    final unit = HeldUnit();
    line.units.add(unit);
    items.refresh();
    _recount();
    _placeHold(line, unit);
    return AddToCartResult.added;
  }

  /// Removes one unit, choosing the one worth least: an expired hold first,
  /// then one still being placed, then the hold that runs out soonest.
  void decrement(int dealId) {
    final line = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (line == null || line.units.isEmpty) return;
    final now = _now();
    int rank(HeldUnit u) => u.isExpiredAt(now) ? 0 : (u.isReserving ? 1 : 2);
    final unit = line.units.reduce((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank < 0 ? a : b;
      final ea = a.reservation?.expiresAt, eb = b.reservation?.expiresAt;
      return (ea != null && eb != null && eb.isBefore(ea)) ? b : a;
    });
    _removeUnit(line, unit);
  }

  void remove(int dealId) {
    final line = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (line == null) return;
    for (final unit in List.of(line.units)) {
      _removeUnit(line, unit);
    }
  }

  /// Empties the bag after a successful checkout. The order used the holds,
  /// so they are not released.
  void clear() {
    for (final timer in _expiryTimers.values) {
      timer.cancel();
    }
    _expiryTimers.clear();
    items.clear();
    _recount();
  }

  num get total => items.fold(0, (sum, i) => sum + i.lineTotal);

  /// Places fresh holds before checkout: on expired units only, or with
  /// [all] on every held unit (after the backend rejected one we believed
  /// valid). A new hold is placed before the old one is released, so a unit
  /// is never left without one. Units that cannot be held again are removed
  /// from the bag; their deals are returned.
  Future<List<DealModel>> renewHolds({bool all = false}) async {
    final now = _now();
    final targets = [
      for (final line in items)
        for (final unit in line.units)
          if (all ? !unit.isReserving : unit.isExpiredAt(now)) (line, unit),
    ];
    final lost = await Future.wait(targets.map((t) => _renewHold(t.$1, t.$2)));
    return {
      for (var i = 0; i < targets.length; i++)
        if (lost[i]) targets[i].$1.deal,
    }.toList();
  }

  @override
  void onClose() {
    _resumeWorker?.dispose();
    for (final timer in _expiryTimers.values) {
      timer.cancel();
    }
    super.onClose();
  }

  void _recount() {
    itemCount.value = items.fold(0, (sum, i) => sum + i.quantity);
  }

  bool _isInBag(HeldUnit unit) => items.any((l) => l.units.contains(unit));

  Future<void> _placeHold(CartItemModel line, HeldUnit unit) async {
    try {
      final reservation = await _orders.reserve(line.deal.id);
      if (!_isInBag(unit)) {
        // Removed while the hold was being placed: don't keep stock from
        // other users for a unit nobody wants.
        _release(reservation.id);
        return;
      }
      unit.reservation = reservation;
      items.refresh();
    } catch (e) {
      LogService.error('reserving deal ${line.deal.id} failed', e);
      if (!_isInBag(unit)) return;
      _removeUnit(line, unit);
      _notify(
        "Couldn't add ${line.deal.name}",
        _isContention(e)
            ? 'Someone just took the last one, so it was taken out of your bag.'
            : "We couldn't hold it for you right now, so it was taken out of "
                'your bag. Please try again.',
      );
    }
  }

  /// Returns true if the unit could not be held again and was removed.
  Future<bool> _renewHold(CartItemModel line, HeldUnit unit) async {
    final old = unit.reservation;
    try {
      final fresh = await _orders.reserve(line.deal.id);
      if (!_isInBag(unit)) {
        _release(fresh.id);
        return false;
      }
      unit.reservation = fresh;
      items.refresh();
      return false;
    } catch (e) {
      LogService.error('renewing hold on deal ${line.deal.id} failed', e);
      if (!_isInBag(unit)) return false;
      _removeUnit(line, unit, release: false);
      return true;
    } finally {
      if (old != null) _release(old.id);
    }
  }

  void _removeUnit(CartItemModel line, HeldUnit unit, {bool release = true}) {
    line.units.remove(unit);
    // A unit still being placed is released by _placeHold when it lands.
    final reservation = unit.reservation;
    if (release && reservation != null) _release(reservation.id);
    if (line.units.isEmpty) {
      _expiryTimers.remove(line.deal.id)?.cancel();
      items.remove(line);
    } else {
      items.refresh();
    }
    _recount();
  }

  /// Fire and forget: if a release fails, the hold still expires on its own
  /// after 5 minutes.
  void _release(String reservationId) {
    _orders.releaseReservation(reservationId).catchError((Object e) {
      LogService.error('releasing $reservationId failed', e);
    });
  }

  static bool _isContention(Object e) =>
      e is ApiException && e.statusCode == 409;

  void _notify(String title, String message) {
    Get.closeAllSnackbars();
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 4),
    );
  }

  void _watchFlashSale(DealModel deal) {
    final endsAt = deal.flashSaleEndsAt;
    if (endsAt == null) return;
    _expiryTimers.remove(deal.id)?.cancel();
    _expiryTimers[deal.id] =
        Timer(endsAt.difference(_now()), () => _removeEnded([deal]));
  }

  void _recheckFlashSales() {
    final now = _now();
    final ended = <DealModel>[];
    for (final item in items) {
      if (!item.deal.isFlashSale) continue;
      if (item.deal.isFlashSaleOver(now)) {
        ended.add(item.deal);
      } else {
        _watchFlashSale(item.deal); // fresh duration from the wall clock
      }
    }
    _removeEnded(ended);
  }

  /// Removes lines whose flash sale ended, with one notice for all of them.
  void _removeEnded(List<DealModel> deals) {
    final removed = [
      for (final deal in deals)
        if (items.any((i) => i.deal.id == deal.id)) deal,
    ];
    if (removed.isEmpty) return;
    for (final deal in removed) {
      remove(deal.id);
      LogService.log('cart: removed deal ${deal.id}, flash sale ended');
    }
    Get.snackbar(
      'Flash sale ended',
      removed.length == 1
          ? '${removed.single.name} was removed from your bag.'
          : '${removed.length} deals were removed from your bag.',
      snackPosition: SnackPosition.BOTTOM,
      icon: const Icon(Icons.timer_off_outlined),
      duration: const Duration(seconds: 4),
    );
  }
}
