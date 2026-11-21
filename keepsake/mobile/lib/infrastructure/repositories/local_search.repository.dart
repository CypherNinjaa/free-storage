import 'package:drift/drift.dart';
import 'package:immich_mobile/data/db/main/database.dart';
import 'package:immich_mobile/data/db/main/table/remote/asset.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/search_result.model.dart';
import 'package:immich_mobile/models/search/search_filter.model.dart';
import 'package:immich_mobile/utils/option.dart';
// ignore: import_rule_openapi
import 'package:openapi/api.dart' show SearchSuggestionType;

/// Metadata search over the projected vault library in the local Drift database (serverless Keepsake).
///
/// Supports text (file name, description, camera), date range, media type, favorites, archive and rating.
/// Filters that need server-side processing (smart/CLIP search semantics, people, OCR, tags, reverse-geocoded
/// places) have no local data yet, so a search that depends on them returns no results.
class LocalSearchRepository {
  static const pageSize = 100;

  final Drift _db;

  const LocalSearchRepository(this._db);

  Future<SearchResult?> search(SearchFilter filter, int page, String ownerId) async {
    if (_needsServerData(filter)) {
      return null;
    }

    final asset = _db.remoteAssetEntity;
    final exif = _db.remoteExifEntity;
    final query = _db.select(asset).join([leftOuterJoin(exif, exif.assetId.equalsExp(asset.id))]);

    var where =
        asset.ownerId.equals(ownerId) &
        asset.deletedAt.isNull() &
        asset.visibility.equalsValue(filter.display.isArchive ? AssetVisibility.archive : AssetVisibility.timeline);

    if (filter.display.isFavorite) {
      where &= asset.isFavorite.equals(true);
    }
    if (filter.mediaType == AssetType.image || filter.mediaType == AssetType.video) {
      where &= asset.type.equalsValue(filter.mediaType);
    }

    final text = _firstNonBlank([filter.context, filter.filename]);
    if (text != null) {
      for (final term in text.split(RegExp(r'\s+'))) {
        final pattern = '%${_escapeLike(term)}%';
        where &=
            asset.name.like(pattern, escapeChar: r'\') |
            exif.description.like(pattern, escapeChar: r'\') |
            exif.make.like(pattern, escapeChar: r'\') |
            exif.model.like(pattern, escapeChar: r'\');
      }
    }
    final description = _firstNonBlank([filter.description]);
    if (description != null) {
      where &= exif.description.like('%${_escapeLike(description)}%', escapeChar: r'\');
    }

    if (filter.camera.make != null) {
      where &= exif.make.equals(filter.camera.make!);
    }
    if (filter.camera.model != null) {
      where &= exif.model.equals(filter.camera.model!);
    }

    final takenAfter = filter.date.takenAfter;
    if (takenAfter != null) {
      where &= asset.createdAt.isBiggerOrEqualValue(takenAfter.toUtc());
    }
    final takenBefore = filter.date.takenBefore;
    if (takenBefore != null) {
      where &= asset.createdAt.isSmallerOrEqualValue(takenBefore.toUtc());
    }

    if (filter.rating.rating case Some(:final value)) {
      where &= value == null ? exif.rating.isNull() : exif.rating.equals(value);
    }

    query
      ..where(where)
      ..orderBy([OrderingTerm.desc(asset.createdAt)])
      ..limit(pageSize, offset: (page - 1) * pageSize);

    final rows = await query.get();
    if (rows.isEmpty) {
      return null;
    }
    return SearchResult(
      assets: rows.map((row) => row.readTable(asset).toDto()).toList(),
      nextPage: rows.length == pageSize ? page + 1 : null,
    );
  }

  /// Distinct values for the camera and place pickers, read from the projected EXIF of the vault library.
  /// Parent choices narrow the list: a model list for a chosen make, a state list for a chosen country.
  Future<List<String>> suggestions(
    SearchSuggestionType type, {
    String? country,
    String? state,
    String? make,
    String? model,
  }) async {
    final exif = _db.remoteExifEntity;
    final asset = _db.remoteAssetEntity;
    final column = switch (type) {
      SearchSuggestionType.country => exif.country,
      SearchSuggestionType.state => exif.state,
      SearchSuggestionType.city => exif.city,
      SearchSuggestionType.cameraMake => exif.make,
      SearchSuggestionType.cameraModel => exif.model,
      SearchSuggestionType.cameraLensModel => exif.lens,
    };
    var where = column.isNotNull() & asset.deletedAt.isNull();
    if (country != null && type != SearchSuggestionType.country) {
      where &= exif.country.equals(country);
    }
    if (state != null && type == SearchSuggestionType.city) {
      where &= exif.state.equals(state);
    }
    if (make != null && type != SearchSuggestionType.cameraMake) {
      where &= exif.make.equals(make);
    }
    if (model != null && type == SearchSuggestionType.cameraLensModel) {
      where &= exif.model.equals(model);
    }
    final query = _db.selectOnly(exif, distinct: true)
      ..addColumns([column])
      ..join([innerJoin(asset, asset.id.equalsExp(exif.assetId), useColumns: false)])
      ..where(where)
      ..orderBy([OrderingTerm.asc(column)]);
    final rows = await query.get();
    return rows.map((row) => row.read(column)).whereType<String>().where((value) => value.trim().isNotEmpty).toList();
  }

  static bool _needsServerData(SearchFilter filter) =>
      (filter.assetId?.isNotEmpty ?? false) ||
      (filter.ocr?.isNotEmpty ?? false) ||
      filter.people.isNotEmpty ||
      (filter.tags?.isNotEmpty ?? false) ||
      filter.location.city != null ||
      filter.location.state != null ||
      filter.location.country != null;

  static String? _firstNonBlank(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  static String _escapeLike(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
}
