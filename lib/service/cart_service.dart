import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../model/cart_item_model.dart';
import '../model/deal_model.dart';
import '../util/log_service.dart';
import 'clock_service.dart';

enum AddToCartResult { added, flashSaleEnded, noStockLeft }

/// App-wide cart. Lives for the whole session.
///
/// NOTE: the starter cart is purely local — it does not reserve stock on the
/// backend. See the "Reservations" feature task in PROBLEM.md.
class CartService extends GetxService {
  CartService({ClockService? clock})
      : _clock = clock,
        _now = clock?.now ?? DateTime.now;

  final ClockService? _clock;
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

  AddToCartResult add(DealModel deal) {
    if (deal.isFlashSaleOver(_now())) {
      LogService.log('cart: flash sale for deal ${deal.id} has ended');
      return AddToCartResult.flashSaleEnded;
    }
    final existing = items.firstWhereOrNull((i) => i.deal.id == deal.id);
    if (existing != null) {
      if (existing.quantity >= deal.quantityLeft) {
        LogService.log('cart: cannot add more of deal ${deal.id}');
        return AddToCartResult.noStockLeft;
      }
      existing.quantity++;
      items.refresh();
    } else {
      items.add(CartItemModel(deal: deal));
      _watchFlashSale(deal);
    }
    _recount();
    return AddToCartResult.added;
  }

  void decrement(int dealId) {
    final existing = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (existing == null) return;
    existing.quantity--;
    if (existing.quantity <= 0) {
      remove(dealId);
    } else {
      items.refresh();
      _recount();
    }
  }

  void remove(int dealId) {
    _expiryTimers.remove(dealId)?.cancel();
    items.removeWhere((i) => i.deal.id == dealId);
    _recount();
  }

  void clear() {
    for (final timer in _expiryTimers.values) {
      timer.cancel();
    }
    _expiryTimers.clear();
    items.clear();
    _recount();
  }

  num get total => items.fold(0, (sum, i) => sum + i.lineTotal);

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
