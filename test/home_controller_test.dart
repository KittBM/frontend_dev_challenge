import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/home/home_controller.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/model/paged_response_model.dart';

import 'helpers.dart';

/// Page p contains deals p1 and p2 (e.g. page 2 -> ids 21, 22).
PagedResponseModel<DealModel> page(int p) => PagedResponseModel(
      items: [fakeDeal(p * 10 + 1), fakeDeal(p * 10 + 2)],
      page: p,
      totalPages: 3,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // RefreshController needs it
  late FakeDealRepo repo;
  late HomeController controller;

  /// Completes the oldest pending fetchDeals call with [p].
  void respond(int p) => repo.pendingPages.removeAt(0).complete(page(p));

  setUp(() async {
    repo = FakeDealRepo();
    controller = HomeController(dealRepo: repo);
    final initial = controller.refreshDeals();
    respond(1);
    await initial;
  });

  List<int> ids() => controller.deals.map((d) => d.id).toList();

  test('RES-104: refresh while loadMore is in flight -> no duplicates',
      () async {
    final more = controller.loadMore(); // page 2 in flight
    final refresh = controller.refreshDeals(); // page 1 in flight
    final staleMore = repo.pendingPages.removeAt(0);
    respond(1);
    await refresh;
    staleMore.complete(page(2)); // arrives after the refresh
    await more;

    expect(ids(), [11, 12], reason: 'stale page 2 must not be appended');

    final next = controller.loadMore();
    respond(2);
    await next;
    expect(ids(), [11, 12, 21, 22]);
    expect(repo.pageRequests, [1, 2, 1, 2]);
  });

  test('RES-104: loadMore resolving before the refresh is overwritten',
      () async {
    final more = controller.loadMore();
    final refresh = controller.refreshDeals();
    final staleMore = repo.pendingPages.removeAt(0);
    staleMore.complete(page(2)); // arrives first this time
    await more;
    respond(1);
    await refresh;

    expect(ids(), [11, 12]);
    final next = controller.loadMore();
    expect(repo.pageRequests.last, 2);
    respond(2);
    await next;
    expect(ids(), [11, 12, 21, 22]);
  });

  test('RES-104: a failed loadMore retries the same page', () async {
    final failed = controller.loadMore();
    repo.pendingPages.removeAt(0).completeError(Exception('timeout'));
    await failed;

    final retry = controller.loadMore();
    respond(2);
    await retry;
    expect(repo.pageRequests, [1, 2, 2]);
    expect(ids(), [11, 12, 21, 22]);
  });
}
