import 'package:immich_mobile/domain/models/search_result.model.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/asset_extensions.dart';
import 'package:immich_mobile/extensions/string_extensions.dart';
import 'package:immich_mobile/infrastructure/repositories/local_search.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/search_api.repository.dart';
import 'package:immich_mobile/models/search/search_filter.model.dart';
import 'package:logging/logging.dart';

class SearchService {
  final _log = Logger("SearchService");
  final SearchApiRepository _searchApiRepository;

  /// Serverless Keepsake searches the projected vault library on device instead of the server.
  final LocalSearchRepository? _localSearch;

  SearchService(this._searchApiRepository, {this._localSearch});

  Future<SearchResult?> search(SearchFilter filter, int page) async {
    final localSearch = _localSearch;
    if (localSearch != null) {
      final ownerId = Store.tryGet(StoreKey.currentUser)?.id;
      if (ownerId == null) {
        return null;
      }
      try {
        return await localSearch.search(filter, page, ownerId);
      } catch (error, stackTrace) {
        _log.severe("Failed to search the vault library", error, stackTrace);
        return null;
      }
    }

    try {
      final response = await _searchApiRepository.search(filter, page);

      if (response == null || response.assets.items.isEmpty) {
        return null;
      }

      return SearchResult(
        assets: response.assets.items.map((e) => e.toDto()).toList(),
        nextPage: response.assets.nextPage?.toInt(),
      );
    } catch (error, stackTrace) {
      _log.severe("Failed to search for assets", error, stackTrace);
    }
    return null;
  }
}
