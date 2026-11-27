import 'dart:async';

import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/memory.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/sync_stream.repository.dart';
import 'package:immich_mobile/platform/keepsake_api.g.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';
import 'package:uuid/uuid.dart';

/// What one projection pass changed, so callers can mirror trash/deletes onto device media.
class KeepsakeLibrarySyncResult {
  final int changed;
  final List<String> trashedIds;
  final List<String> deletedIds;

  const KeepsakeLibrarySyncResult({required this.changed, required this.trashedIds, required this.deletedIds});

  static const empty = KeepsakeLibrarySyncResult(changed: 0, trashedIds: [], deletedIds: []);
}

/// Projects the on-device Telegram index (the source of truth for what is stored in the vault) into the
/// Drift `remote_asset` / `remote_exif` tables that the Immich timeline, viewer and backup screens read.
///
/// Changes are read incrementally by sequence number; deletions arrive as tombstones. Every write is an
/// idempotent upsert, so overlapping passes (for example the backup worker and the foreground app) are safe.
class KeepsakeLibrarySyncService {
  static const _pageSize = 500;

  /// Bump when [toSyncAsset] or [toSyncExif] change what they write. 2: EXIF time zone. 3: 0,0 is no location.
  static const _projectionVersion = 3;

  /// Passes in one isolate run one after another, so a pass requested after a write always sees that write.
  static Future<void> _tail = Future.value();

  /// While uploads keep changing the library, "On this day" is rebuilt at most this often (it scans every asset).
  static const _memoriesRefreshInterval = Duration(minutes: 15);
  static DateTime? _memoriesRefreshedAt;

  final KeepsakeLibraryApi _api;
  final SyncStreamRepository _repository;
  final MemoryRepository? _memoryRepository;
  final Logger _log = Logger('KeepsakeLibrarySync');

  KeepsakeLibrarySyncService({required this._api, required this._repository, this._memoryRepository});

  /// Runs one projection pass, after any pass already queued in this isolate.
  Future<KeepsakeLibrarySyncResult> sync({bool Function()? isCancelled}) {
    final pass = _tail.then((_) => _sync(isCancelled ?? () => false));
    _tail = pass.then((_) {}, onError: (_) {});
    return pass;
  }

  Future<KeepsakeLibrarySyncResult> _sync(bool Function() isCancelled) async {
    final user = Store.tryGet(StoreKey.currentUser);
    if (user == null) {
      _log.warning('No vault user yet; skipping library projection');
      return KeepsakeLibrarySyncResult.empty;
    }
    await _ensureOwner(user);

    // When the mapping itself changes (see [_projectionVersion]), project the whole index once more.
    final outdated = (Store.tryGet(StoreKey.keepsakeProjectionVersion) ?? 1) < _projectionVersion;
    var seq = outdated ? 0 : Store.tryGet(StoreKey.keepsakeIndexSeq) ?? 0;
    var changed = 0;
    var completed = false;
    final trashed = <String>[];
    final deleted = <String>[];
    while (!isCancelled()) {
      final changes = await _api.changesSince(seq, _pageSize);
      if (changes.assets.isNotEmpty) {
        await _repository.updateAssetsV2(changes.assets.map((asset) => toSyncAsset(asset, user.id)));
        await _repository.updateAssetsExifV1(changes.assets.map(toSyncExif));
        trashed.addAll(changes.assets.where((asset) => asset.deletedAtMs != null).map((asset) => asset.id));
      }
      if (changes.deletedIds.isNotEmpty) {
        await _repository.deleteAssetsV1(changes.deletedIds.map((id) => SyncAssetDeleteV1(assetId: id)));
        deleted.addAll(changes.deletedIds);
      }
      changed += changes.assets.length + changes.deletedIds.length;
      if (changes.nextSeq != seq) {
        seq = changes.nextSeq;
        await Store.put(StoreKey.keepsakeIndexSeq, seq);
      }
      if (!changes.hasMore) {
        completed = true;
        break;
      }
    }
    if (outdated && completed) {
      await Store.put(StoreKey.keepsakeProjectionVersion, _projectionVersion);
    }
    if (completed && !isCancelled()) {
      // Albums go after assets: every album link and cover then points at an asset that is already projected.
      changed += await _syncAlbums(user.id, untilSeq: seq);
    }
    if (changed > 0) {
      _log.info('Projected $changed library change(s) up to seq $seq');
    }
    try {
      final refreshedAt = _memoriesRefreshedAt;
      final due = refreshedAt == null || DateTime.now().difference(refreshedAt) >= _memoriesRefreshInterval;
      await _refreshOnThisDayMemories(user.id, force: changed > 0 && due);
    } catch (error, stackTrace) {
      _log.warning('Could not build On this day memories', error, stackTrace);
    }
    return KeepsakeLibrarySyncResult(changed: changed, trashedIds: trashed, deletedIds: deleted);
  }

  /// Projects album changes recorded in the index up to [untilSeq] into the Drift remote album tables.
  /// When a write fails (for example an album link that points at an asset projected only by a later pass), the
  /// album cursor stays put and the same changes are tried again on the next pass.
  Future<int> _syncAlbums(String ownerId, {required int untilSeq}) async {
    final since = Store.tryGet(StoreKey.keepsakeAlbumSeq) ?? 0;
    if (since >= untilSeq) {
      return 0;
    }
    final changes = await _api.albumChangesSince(since, untilSeq);
    try {
      if (changes.albums.isNotEmpty) {
        await _repository.updateAlbumsV1(changes.albums.map((album) => toSyncAlbum(album, ownerId)));
      }
      if (changes.removedLinks.isNotEmpty) {
        await _repository.deleteAlbumToAssetsV1(
          changes.removedLinks.map((link) => SyncAlbumToAssetDeleteV1(albumId: link.albumId, assetId: link.assetId)),
        );
      }
      if (changes.addedLinks.isNotEmpty) {
        await _repository.updateAlbumToAssetsV1(
          changes.addedLinks.map((link) => SyncAlbumToAssetV1(albumId: link.albumId, assetId: link.assetId)),
        );
      }
      if (changes.deletedAlbumIds.isNotEmpty) {
        await _repository.deleteAlbumsV1(changes.deletedAlbumIds.map((id) => SyncAlbumDeleteV1(albumId: id)));
      }
    } catch (error, stackTrace) {
      _log.warning('Album projection failed; it will be retried on the next pass', error, stackTrace);
      return 0;
    }
    await Store.put(StoreKey.keepsakeAlbumSeq, changes.nextSeq);
    return changes.albums.length +
        changes.deletedAlbumIds.length +
        changes.addedLinks.length +
        changes.removedLinks.length;
  }

  static SyncAlbumV1 toSyncAlbum(LibraryAlbum album, String ownerId) => SyncAlbumV1(
    createdAt: DateTime.fromMillisecondsSinceEpoch(album.createdAtMs, isUtc: true),
    description: album.description ?? '',
    id: album.id,
    isActivityEnabled: false,
    name: album.name,
    order: album.order == 1 ? AssetOrder.asc : AssetOrder.desc,
    ownerId: ownerId,
    thumbnailAssetId: album.thumbnailAssetId,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(album.updatedAtMs, isUtc: true),
  );

  /// Builds today's "On this day" memories from the projected library, like the Immich server does nightly.
  /// Ids are derived from the day and year, so rebuilding the same day updates the same memories.
  Future<void> _refreshOnThisDayMemories(String ownerId, {required bool force}) async {
    final memories = _memoryRepository;
    if (memories == null) {
      return;
    }
    final now = DateTime.now();
    final today = '${now.year}-${_two(now.month)}-${_two(now.day)}';
    if (!force && Store.tryGet(StoreKey.keepsakeMemoriesDay) == today) {
      return;
    }
    _memoriesRefreshedAt = now;

    final byYear = await memories.getOnThisDayAssetIds(ownerId, month: now.month, day: now.day, beforeYear: now.year);
    final showAt = DateTime.utc(now.year, now.month, now.day);
    final hideAt = DateTime.utc(now.year, now.month, now.day, 23, 59, 59, 999);
    final created = DateTime.now().toUtc();
    final memoryRows = <SyncMemoryV2>[];
    final memoryAssets = <SyncMemoryAssetV1>[];
    for (final MapEntry(key: year, value: assetIds) in byYear.entries) {
      final id = const Uuid().v5(Namespace.url.value, 'keepsake:on-this-day:$today:$year');
      memoryRows.add(
        SyncMemoryV2(
          createdAt: created,
          data: {'year': year},
          deletedAt: null,
          hideAt: hideAt,
          id: id,
          isSaved: false,
          memoryAt: DateTime.utc(year, now.month, now.day),
          ownerId: ownerId,
          seenAt: null,
          showAt: showAt,
          type: MemoryType.onThisDay,
          updatedAt: created,
        ),
      );
      memoryAssets.addAll(assetIds.map((assetId) => SyncMemoryAssetV1(assetId: assetId, memoryId: id)));
    }
    if (memoryRows.isNotEmpty) {
      await _repository.updateMemoriesV2(memoryRows);
      await _repository.updateMemoryAssetsV1(memoryAssets);
    }
    await Store.put(StoreKey.keepsakeMemoriesDay, today);
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// Remote assets reference their owner, so the vault user must exist in the user tables first.
  Future<void> _ensureOwner(UserDto user) async {
    await _repository.updateUsersV1([
      SyncUserV1(
        deletedAt: null,
        email: user.email,
        hasProfileImage: false,
        id: user.id,
        name: user.name,
        profileChangedAt: user.profileChangedAt,
      ),
    ]);
    await _repository.updateAuthUsersV2([
      SyncAuthUserV2(
        deletedAt: null,
        email: user.email,
        hasProfileImage: false,
        id: user.id,
        isAdmin: true,
        name: user.name,
        oauthId: null,
        pinCode: null,
        profileChangedAt: user.profileChangedAt,
        quotaSizeInBytes: null,
        quotaUsageInBytes: 0,
        storageLabel: null,
      ),
    ]);
  }

  static SyncAssetV2 toSyncAsset(LibraryAsset asset, String ownerId) {
    final takenAt = DateTime.fromMillisecondsSinceEpoch(asset.createdAtMs, isUtc: true);
    final flipped = _isFlipped(asset.orientation);
    return SyncAssetV2(
      checksum: asset.checksum,
      createdAt: DateTime.fromMillisecondsSinceEpoch(asset.uploadedAtMs, isUtc: true),
      deletedAt: asset.deletedAtMs == null ? null : DateTime.fromMillisecondsSinceEpoch(asset.deletedAtMs!, isUtc: true),
      duration: asset.durationMs,
      fileCreatedAt: takenAt,
      fileModifiedAt: DateTime.fromMillisecondsSinceEpoch(asset.modifiedAtMs, isUtc: true),
      height: flipped ? asset.width : asset.height,
      id: asset.id,
      isEdited: false,
      isFavorite: asset.isFavorite,
      libraryId: null,
      livePhotoVideoId: null,
      localDateTime: _wallClock(takenAt),
      originalFileName: asset.name,
      ownerId: ownerId,
      stackId: null,
      thumbhash: null,
      type: asset.type == 2 ? AssetTypeEnum.VIDEO : AssetTypeEnum.IMAGE,
      visibility: visibilityFromIndex(asset.visibility),
      width: flipped ? asset.height : asset.width,
    );
  }

  static SyncAssetExifV1 toSyncExif(LibraryAsset asset) {
    final takenAt = DateTime.fromMillisecondsSinceEpoch(asset.createdAtMs, isUtc: true);
    // Cameras write 0,0 when they had no GPS fix; Immich treats that as no location, and so does the map.
    final hasLocation = asset.latitude != null && asset.longitude != null && !(asset.latitude == 0 && asset.longitude == 0);
    return SyncAssetExifV1(
      assetId: asset.id,
      city: null,
      country: null,
      dateTimeOriginal: takenAt,
      description: asset.description,
      exifImageHeight: asset.height,
      exifImageWidth: asset.width,
      exposureTime: null,
      fNumber: null,
      fileSizeInByte: asset.sizeBytes,
      focalLength: null,
      fps: null,
      iso: null,
      latitude: hasLocation ? asset.latitude : null,
      lensModel: null,
      longitude: hasLocation ? asset.longitude : null,
      make: asset.make,
      model: asset.model,
      modifyDate: DateTime.fromMillisecondsSinceEpoch(asset.modifiedAtMs, isUtc: true),
      orientation: asset.orientation?.toString(),
      profileDescription: null,
      projectionType: null,
      rating: asset.rating,
      state: null,
      // Immich shows dateTimeOriginal in this zone and falls back to plain UTC without one.
      timeZone: utcOffsetLabel(takenAt.toLocal().timeZoneOffset),
    );
  }

  /// Formats an offset the way Immich's timezone helper parses it, e.g. `UTC+05:30` or `UTC-04:00`.
  static String utcOffsetLabel(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final minutes = offset.inMinutes.abs();
    return 'UTC$sign${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
  }

  static AssetVisibility visibilityFromIndex(int value) => switch (value) {
    1 => AssetVisibility.archive,
    2 => AssetVisibility.hidden,
    3 => AssetVisibility.locked,
    _ => AssetVisibility.timeline,
  };

  static int visibilityToIndex(AssetVisibility value) => switch (value) {
    AssetVisibility.archive => 1,
    AssetVisibility.hidden => 2,
    AssetVisibility.locked => 3,
    _ => 0,
  };

  static bool _isFlipped(int? orientation) => orientation != null && orientation >= 5 && orientation <= 8;

  /// Immich stores `localDateTime` as the wall-clock time of capture expressed in UTC.
  static DateTime _wallClock(DateTime instant) {
    final local = instant.toLocal();
    return DateTime.utc(local.year, local.month, local.day, local.hour, local.minute, local.second, local.millisecond);
  }
}
