import 'package:get/get.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../util/log_service.dart';

class SearchDealsController extends GetxController {
  final DealRepo dealRepo;

  SearchDealsController({required this.dealRepo});

  final results = <DealModel>[].obs;
  final isLoading = false.obs;
  final hasSearched = false.obs;

  /// Id of the most recent search. Responses carrying an older id are stale:
  /// broad (short) queries are slower, so they routinely finish after the
  /// query the user actually ended up typing.
  int _latestSearchId = 0;

  void onQueryChanged(String query) {
    _search(query);
  }

  Future<void> _search(String query) async {
    final searchId = ++_latestSearchId;
    if (query.trim().isEmpty) {
      results.clear();
      hasSearched.value = false;
      isLoading.value = false;
      return;
    }
    isLoading.value = true;
    hasSearched.value = true;
    try {
      final found = await dealRepo.search(query);
      if (searchId != _latestSearchId) return;
      results.assignAll(found);
    } catch (e) {
      if (searchId != _latestSearchId) return;
      LogService.error('search failed', e);
    }
    isLoading.value = false;
  }
}
