import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/platform/keepsake_api.g.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:immich_mobile/repositories/api.repository.dart';
import 'package:logging/logging.dart';
// ignore: import_rule_openapi
import 'package:openapi/api.dart' hide AlbumUserRole;

final albumApiRepositoryProvider = Provider(
  (ref) => AlbumApiRepository(ref.watch(apiServiceProvider).albumsApi, keepsake: ref.watch(keepsakeLibraryApiProvider)),
);

/// Album mutations. In serverless Keepsake albums live in the on-device index ([_keepsake]); the calling service
/// writes the Drift tables, and the library sync re-projects them from the index. Sharing albums with other
/// people needs a server and is not available.
class AlbumApiRepository extends ApiRepository {
  static final _log = Logger('AlbumApiRepository');

  /// Album edits exist only in the index until the next index snapshot, so one is requested shortly after them.
  static Timer? _snapshotTimer;
  static const _snapshotDelay = Duration(seconds: 20);

  final AlbumsApi _api;
  final KeepsakeLibraryApi? _keepsake;

  AlbumApiRepository(this._api, {this._keepsake});

  void _scheduleSnapshot(KeepsakeLibraryApi keepsake) {
    _snapshotTimer?.cancel();
    _snapshotTimer = Timer(_snapshotDelay, () => unawaited(_snapshot(keepsake)));
  }

  static Future<void> _snapshot(KeepsakeLibraryApi keepsake) async {
    try {
      await keepsake.snapshotIndex(false);
    } catch (error) {
      _log.warning('Could not back up the library index after an album change', error);
    }
  }

  Future<RemoteAlbum> createDriftAlbum(
    String name,
    UserDto owner, {
    required Iterable<String> assetIds,
    String? description,
  }) async {
    final keepsake = _keepsake;
    if (keepsake != null) {
      final album = await keepsake.createAlbum(name, description, assetIds.toList());
      _scheduleSnapshot(keepsake);
      return album.toRemoteAlbum(owner);
    }
    final responseDto = await checkNull(
      _api.createAlbum(
        CreateAlbumDto(
          albumName: name,
          description: description == null
              ? const Optional.absent()
              : Optional.present(description.isEmpty ? null : description),
          assetIds: Optional.present(assetIds.toList()),
        ),
      ),
    );

    return responseDto.toRemoteAlbum(owner);
  }

  Future<({List<String> removed, List<String> failed})> removeAssets(String albumId, Iterable<String> assetIds) async {
    final keepsake = _keepsake;
    if (keepsake != null) {
      final requested = assetIds.toList();
      final removed = await keepsake.removeAlbumAssets(albumId, requested);
      _scheduleSnapshot(keepsake);
      final removedSet = removed.toSet();
      return (removed: removed, failed: requested.where((id) => !removedSet.contains(id)).toList());
    }
    final response = await checkNull(_api.removeAssetFromAlbum(albumId, BulkIdsDto(ids: assetIds.toList())));
    final List<String> removed = [];
    final List<String> failed = [];
    for (final dto in response) {
      if (dto.success) {
        removed.add(dto.id);
      } else {
        failed.add(dto.id);
      }
    }
    return (removed: removed, failed: failed);
  }

  Future<({List<String> added, List<String> failed})> addAssets(
    String albumId,
    Iterable<String> assetIds, {
    Future<void>? abortTrigger,
  }) async {
    final keepsake = _keepsake;
    if (keepsake != null) {
      // Ids already in the album are neither added nor failed, like the server's "duplicate" result.
      final added = await keepsake.addAlbumAssets(albumId, assetIds.toList());
      _scheduleSnapshot(keepsake);
      return (added: added, failed: const <String>[]);
    }
    final response = await checkNull(
      _api.addAssetsToAlbum(albumId, BulkIdsDto(ids: assetIds.toList()), abortTrigger: abortTrigger),
    );
    final List<String> added = [];
    final List<String> failed = [];
    for (final dto in response) {
      if (dto.success) {
        added.add(dto.id);
      } else if (dto.error.orElse(null) != BulkIdErrorReason.duplicate) {
        failed.add(dto.id);
      }
    }

    return (added: added, failed: failed);
  }

  Future<RemoteAlbum> updateAlbum(
    String albumId,
    UserDto owner, {
    String? name,
    String? description,
    String? thumbnailAssetId,
    bool? isActivityEnabled,
    AlbumAssetOrder? order,
  }) async {
    final keepsake = _keepsake;
    if (keepsake != null) {
      final album = await keepsake.updateAlbum(
        albumId,
        name,
        description,
        thumbnailAssetId,
        order == null ? null : (order == AlbumAssetOrder.asc ? 1 : 0),
      );
      if (album == null) {
        throw StateError('Album $albumId no longer exists');
      }
      _scheduleSnapshot(keepsake);
      return album.toRemoteAlbum(owner);
    }
    AssetOrder? apiOrder;
    if (order != null) {
      apiOrder = order == AlbumAssetOrder.asc ? AssetOrder.asc : AssetOrder.desc;
    }

    final responseDto = await checkNull(
      _api.updateAlbumInfo(
        albumId,
        UpdateAlbumDto(
          albumName: name == null ? const Optional.absent() : Optional.present(name),
          description: description == null
              ? const Optional.absent()
              : Optional.present(description.isEmpty ? null : description),
          albumThumbnailAssetId: thumbnailAssetId == null
              ? const Optional.absent()
              : Optional.present(thumbnailAssetId),
          isActivityEnabled: isActivityEnabled == null ? const Optional.absent() : Optional.present(isActivityEnabled),
          order: apiOrder == null ? const Optional.absent() : Optional.present(apiOrder),
        ),
      ),
    );

    return responseDto.toRemoteAlbum(owner);
  }

  Future<void> deleteAlbum(String albumId) async {
    final keepsake = _keepsake;
    if (keepsake != null) {
      await keepsake.deleteAlbum(albumId);
      _scheduleSnapshot(keepsake);
      return;
    }
    return _api.deleteAlbum(albumId);
  }

  Future<void> addUsers(String albumId, Iterable<String> userIds) async {
    if (_keepsake != null) {
      throw UnsupportedError('Sharing albums with other people is not available in Ambry');
    }
    final albumUsers = userIds.map((userId) => AlbumUserAddDto(userId: userId)).toList();
    await checkNull(_api.addUsersToAlbum(albumId, AddUsersDto(albumUsers: albumUsers)));
  }

  Future<void> removeUser(String albumId, {required String userId}) async {
    if (_keepsake != null) {
      throw UnsupportedError('Sharing albums with other people is not available in Ambry');
    }
    await _api.removeUserFromAlbum(albumId, userId);
  }

  Future<bool> setActivityStatus(String albumId, bool isEnabled) async {
    if (_keepsake != null) {
      throw UnsupportedError('Comments and likes are not available in Ambry');
    }
    final response = await checkNull(
      _api.updateAlbumInfo(albumId, UpdateAlbumDto(isActivityEnabled: Optional.present(isEnabled))),
    );
    return response.isActivityEnabled;
  }
}

extension on LibraryAlbum {
  RemoteAlbum toRemoteAlbum(final UserDto user) {
    return RemoteAlbum(
      id: id,
      name: name,
      ownerId: user.id,
      ownerName: user.name,
      description: description ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs, isUtc: true),
      thumbnailAssetId: thumbnailAssetId,
      isActivityEnabled: false,
      order: order == 1 ? AlbumAssetOrder.asc : AlbumAssetOrder.desc,
      assetCount: assetCount,
      isShared: false,
    );
  }
}

extension on AlbumResponseDto {
  RemoteAlbum toRemoteAlbum(final UserDto user) {
    return RemoteAlbum(
      id: id,
      name: albumName,
      ownerId: user.id,
      ownerName: user.name,
      description: description,
      createdAt: createdAt,
      updatedAt: updatedAt,
      thumbnailAssetId: albumThumbnailAssetId,
      isActivityEnabled: isActivityEnabled,
      order: order.orElse(null) == AssetOrder.asc ? AlbumAssetOrder.asc : AlbumAssetOrder.desc,
      assetCount: assetCount,
      isShared: albumUsers.length > 2,
    );
  }
}
