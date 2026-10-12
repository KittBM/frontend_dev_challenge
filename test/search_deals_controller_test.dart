import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/search/search_deals_controller.dart';

import 'helpers.dart';

void main() {
  testWidgets('RES-101: a slow response for an older query is discarded',
      (tester) async {
    final controller = SearchDealsController(dealRepo: FakeDealRepo());

    controller.onQueryChanged('s'); // broad query: ~1.1s
    await tester.pump(const Duration(milliseconds: 400));
    controller.onQueryChanged('sushi'); // specific query: ~0.2s
    await tester.pump(const Duration(seconds: 3)); // let both finish

    expect(controller.results.single.name, 'result for "sushi"');
    expect(controller.isLoading.value, isFalse);
  });

  testWidgets('RES-101: clearing the box drops in-flight results',
      (tester) async {
    final controller = SearchDealsController(dealRepo: FakeDealRepo());

    controller.onQueryChanged('b'); // slow, still in flight when cleared
    await tester.pump(const Duration(milliseconds: 400));
    controller.onQueryChanged('');
    await tester.pump(const Duration(seconds: 3));

    expect(controller.results, isEmpty);
    expect(controller.hasSearched.value, isFalse);
    expect(controller.isLoading.value, isFalse);
  });
}
