import 'dart:async';

import 'package:get/get.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../util/log_service.dart';

class SearchDealsController extends GetxController {
  final DealRepo dealRepo;

  SearchDealsController({required this.dealRepo});

  /// Wait for a pause in typing before hitting the backend.
  static const debounceDuration = Duration(milliseconds: 300);

  final results = <DealModel>[].obs;
  final isLoading = false.obs;
  final hasSearched = false.obs;

  /// Id of the most recent search. Responses carrying an older id are stale:
  /// broad (short) queries are slower, so they routinely finish after the
  /// query the user actually ended up typing.
  int _latestSearchId = 0;
  Timer? _debounce;

  void onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      _search(query); // clear immediately
      return;
    }
    _debounce = Timer(debounceDuration, () => _search(query));
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

  @override
  void onClose() {
    _debounce?.cancel();
    super.onClose();
  }
}
