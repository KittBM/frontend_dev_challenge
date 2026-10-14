import 'dart:async';
import 'dart:math';

import 'package:get/get.dart';

import 'package:rescu/model/deal_model.dart';
import 'package:rescu/model/paged_response_model.dart';
import 'package:rescu/model/pickup_window_model.dart';
import 'package:rescu/repository/deal_repo.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/fake_api_service.dart';
import 'package:rescu/service/impression_service.dart';
import 'package:visibility_detector/visibility_detector.dart';

DealModel fakeDeal(int id, {String? name}) => DealModel(
      id: id,
      name: name ?? 'deal $id',
      description: '',
      imageUrl: '',
      originalPrice: 100,
      price: 50,
      currencyCode: 'THB',
      quantityLeft: 5,
      storeId: 1,
      storeName: 'store',
      storeAddress: 'address',
      lat: 0,
      lng: 0,
      rating: null,
      tags: const [],
      pickupWindow: PickupWindowModel(
        start: DateTime(2026, 10, 8, 17),
        end: DateTime(2026, 10, 8, 21),
      ),
      flashSaleEndsAt: null,
    );

/// DealRepo whose responses are controlled by the test.
class FakeDealRepo extends DealRepo {
  FakeDealRepo() : super(api: FakeApiService());

  final fetchByIdCalls = <int>[];
  final pageRequests = <int>[];
  final searchQueries = <String>[];
  Duration fetchByIdDelay = Duration.zero;

  /// One completer per fetchDeals call, completed by the test.
  final pendingPages = <Completer<PagedResponseModel<DealModel>>>[];

  @override
  Future<DealModel> fetchById(int id) async {
    fetchByIdCalls.add(id);
    if (fetchByIdDelay > Duration.zero) await Future.delayed(fetchByIdDelay);
    return fakeDeal(id);
  }

  @override
  Future<PagedResponseModel<DealModel>> fetchDeals({int page = 1}) {
    pageRequests.add(page);
    final completer = Completer<PagedResponseModel<DealModel>>();
    pendingPages.add(completer);
    return completer.future;
  }

  @override
  Future<List<DealModel>> fetchFlashDeals() async => [];

  /// Same latency shape as FakeApiService.searchDeals: broad (short) queries
  /// are slower than specific ones.
  @override
  Future<List<DealModel>> search(String query) async {
    searchQueries.add(query);
    final ms = 180 + max(0, 1200 - query.trim().length * 280).toInt();
    await Future.delayed(Duration(milliseconds: ms));
    return [fakeDeal(1, name: 'result for "$query"')];
  }
}

/// Registers impression tracking for screens that use TrackImpression.
/// Batches are captured in [sentBatches] instead of being sent.
ImpressionService putImpressionService(
    {List<List<Map<String, dynamic>>>? sentBatches}) {
  // Report visibility at the end of each frame instead of on a 500 ms timer,
  // so tests are deterministic and leave no timer pending.
  VisibilityDetectorController.instance.updateInterval = Duration.zero;
  final analytics = Get.isRegistered<AnalyticsService>()
      ? Get.find<AnalyticsService>()
      : Get.put(AnalyticsService());
  return Get.put(ImpressionService(
    analytics: analytics,
    send: (events) async => sentBatches?.add(events),
  ));
}
