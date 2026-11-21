import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/infrastructure/repositories/local_search.repository.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:openapi/api.dart';

part 'search_filter.provider.freezed.dart';

@freezed
abstract class SearchSuggestionArgs with _$SearchSuggestionArgs {
  const factory SearchSuggestionArgs({
    required SearchSuggestionType type,
    String? locationCountry,
    String? locationState,
    String? make,
    String? model,
  }) = _SearchSuggestionArgs;
}

final getSearchSuggestionsProvider = FutureProvider.autoDispose.family<List<String>, SearchSuggestionArgs>((
  ref,
  args,
) async {
  // Serverless: suggestions come from the vault library's EXIF in the local database, not the Immich server.
  return LocalSearchRepository(ref.read(driftProvider)).suggestions(
    args.type,
    country: args.locationCountry,
    state: args.locationState,
    make: args.make,
    model: args.model,
  );
});
