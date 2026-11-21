import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/asset_edit.model.dart' hide AssetEditAction;
import 'package:immich_mobile/domain/models/stack.model.dart';
import 'package:immich_mobile/domain/models/tag.model.dart';
import 'package:immich_mobile/domain/services/keepsake_library_sync.service.dart';
import 'package:immich_mobile/platform/keepsake_api.g.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:immich_mobile/repositories/api.repository.dart';
import 'package:immich_mobile/utils/option.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:openapi/api.dart' as api show AssetVisibility;
import 'package:openapi/api.dart' hide AssetVisibility;

final assetApiRepositoryProvider = Provider(
  (ref) => AssetApiRepository(
    ref.watch(apiServiceProvider).assetsApi,
    ref.watch(apiServiceProvider).stacksApi,
    ref.watch(apiServiceProvider).trashApi,
    keepsake: ref.watch(keepsakeLibraryApiProvider),
  ),
);

/// Asset mutations. In serverless Keepsake every call goes to the on-device Telegram index ([_keepsake]),
/// which is the source of truth; the Drift tables are updated by the calling service and re-projected
/// from the index on the next library sync.
class AssetApiRepository extends ApiRepository {
  final AssetsApi _api;
  final StacksApi _stacksApi;
  final TrashApi _trashApi;
  final KeepsakeLibraryApi? _keepsake;

  AssetApiRepository(this._api, this._stacksApi, this._trashApi, {this._keepsake});

  Future<void> delete(List<String> ids, bool force) async {
    final keepsake = _keepsake;
    if (keepsake != null) {
      await (force ? keepsake.deletePermanently(ids) : keepsake.trash(ids));
      return;
    }
    return _api.deleteAssets(AssetBulkDeleteDto(ids: ids, force: Optional.present(force)));
  }

  Future<void> restoreTrash(List<String> ids) async {
    final keepsake = _keepsake;
    if (keepsake != null) {
      await keepsake.restoreFromTrash(ids);
      return;
    }
    await _trashApi.restoreAssets(BulkIdsDto(ids: ids));
  }

  Future<int> emptyTrash() async {
    final keepsake = _keepsake;
    if (keepsake != null) {
      return keepsake.emptyTrash();
    }
    final response = await _trashApi.emptyTrash();
    return response?.count ?? 0;
  }

  Future<int> restoreAllTrash() async {
    final keepsake = _keepsake;
    if (keepsake != null) {
      return keepsake.restoreAllTrash();
    }
    final response = await _trashApi.restoreTrash();
    return response?.count ?? 0;
  }

  Future<StackResponse> stack(List<String> ids) async {
    if (_keepsake != null) {
      throw UnsupportedError('Stacking photos is not available in Ambry yet');
    }
    final responseDto = await checkNull(_stacksApi.createStack(StackCreateDto(assetIds: ids)));

    return responseDto.toStack();
  }

  Future<void> unStack(List<String> ids) async {
    if (_keepsake != null) {
      throw UnsupportedError('Stacking photos is not available in Ambry yet');
    }
    return _stacksApi.deleteStacks(BulkIdsDto(ids: ids));
  }

  int _indexVisibility(AssetVisibility visibility) =>
      KeepsakeLibrarySyncService.visibilityToIndex(_mapVisibility(visibility));

  api.AssetVisibility _mapVisibility(AssetVisibility visibility) => switch (visibility) {
    AssetVisibility.timeline => api.AssetVisibility.timeline,
    AssetVisibility.hidden => api.AssetVisibility.hidden,
    AssetVisibility.locked => api.AssetVisibility.locked,
    AssetVisibility.archive => api.AssetVisibility.archive,
  };

  Future<String?> getAssetMIMEType(String assetId) async {
    final keepsake = _keepsake;
    if (keepsake != null) {
      return (await keepsake.getAsset(assetId))?.mimeType;
    }
    final response = await checkNull(_api.getAssetInfo(assetId));

    // we need to get the MIME of the thumbnail once that gets added to the API
    return response.originalMimeType.orElse(null);
  }

  Future<List<Tag>> getAssetTags(String assetId) async {
    if (_keepsake != null) {
      return const [];
    }
    final response = await checkNull(_api.getAssetInfo(assetId));
    return response.tags.orElse(null)?.map((tag) => Tag(id: tag.id, value: tag.value)).toList() ?? const [];
  }

  Future<String> getChecksum(String id) async {
    final keepsake = _keepsake;
    if (keepsake != null) {
      final asset = await keepsake.getAsset(id);
      if (asset == null) {
        throw StateError('Asset $id is not in the vault');
      }
      return asset.checksum;
    }
    return (await checkNull(_api.getAssetInfo(id))).checksum;
  }

  Future<void> updateDescription(String assetId, String description) async {
    final keepsake = _keepsake;
    if (keepsake != null) {
      await keepsake.updateDescription(assetId, description);
      return;
    }
    await _api.updateAsset(assetId, UpdateAssetDto(description: Optional.present(description)));
  }

  Future<void> updateRating(String assetId, int? rating) async {
    final keepsake = _keepsake;
    if (keepsake != null) {
      await keepsake.updateRating(assetId, rating);
      return;
    }
    await _api.updateAsset(assetId, UpdateAssetDto(rating: Optional.present(rating)));
  }

  Future<AssetEditsResponseDto?> editAsset(String assetId, List<AssetEdit> edits) {
    if (_keepsake != null) {
      throw UnsupportedError('Editing vault photos is not available in Ambry yet');
    }
    return _api.editAsset(assetId, AssetEditsCreateDto(edits: edits.map((e) => e.toApi()).toList()));
  }

  Future<void> removeEdits(String assetId) async {
    if (_keepsake != null) {
      throw UnsupportedError('Editing vault photos is not available in Ambry yet');
    }
    return _api.removeAssetEdits(assetId);
  }

  Future<void> update(
    List<String> remoteIds, {
    Option<bool> isFavorite = const .none(),
    Option<AssetVisibility> visibility = const .none(),
    Option<String> dateTimeOriginal = const .none(),
    Option<LatLng> location = const .none(),
  }) async {
    final keepsake = _keepsake;
    if (keepsake != null) {
      await keepsake.updateAssets(
        LibraryAssetUpdate(
          ids: remoteIds,
          isFavorite: isFavorite.unwrapOrNull,
          visibility: visibility.map(_indexVisibility).unwrapOrNull,
          createdAtMs: dateTimeOriginal.map((value) => DateTime.parse(value).millisecondsSinceEpoch).unwrapOrNull,
          latitude: location.map((loc) => loc.latitude).unwrapOrNull,
          longitude: location.map((loc) => loc.longitude).unwrapOrNull,
        ),
      );
      return;
    }
    return _api.updateAssets(
      AssetBulkUpdateDto(
        ids: remoteIds,
        isFavorite: isFavorite.toOptional(),
        visibility: visibility.map(_mapVisibility).toOptional(),
        dateTimeOriginal: dateTimeOriginal.toOptional(),
        latitude: location.map((loc) => loc.latitude).toOptional(),
        longitude: location.map((loc) => loc.longitude).toOptional(),
      ),
    );
  }
}

extension on StackResponseDto {
  StackResponse toStack() {
    return StackResponse(id: id, primaryAssetId: primaryAssetId, assetIds: assets.map((asset) => asset.id).toList());
  }
}

extension on AssetEdit {
  AssetEditActionItemDto toApi() {
    return switch (this) {
      CropEdit(:final parameters) => AssetEditActionItemDto(
        action: AssetEditAction.crop,
        parameters: parameters.toJson(),
      ),
      RotateEdit(:final parameters) => AssetEditActionItemDto(
        action: AssetEditAction.rotate,
        parameters: parameters.toJson(),
      ),
      MirrorEdit(:final parameters) => AssetEditActionItemDto(
        action: AssetEditAction.mirror,
        parameters: parameters.toJson(),
      ),
    };
  }
}
