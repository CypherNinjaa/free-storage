import 'dart:async';

import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/sync_stream.repository.dart';
import 'package:immich_mobile/platform/keepsake_api.g.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';

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
  static Future<KeepsakeLibrarySyncResult>? _running;

  final KeepsakeLibraryApi _api;
  final SyncStreamRepository _repository;
  final Logger _log = Logger('KeepsakeLibrarySync');

  KeepsakeLibrarySyncService({required this._api, required this._repository});

  /// Runs one pass. Concurrent calls in the same isolate share the pass that is already running.
  Future<KeepsakeLibrarySyncResult> sync({bool Function()? isCancelled}) {
    final running = _running;
    if (running != null) {
      return running;
    }
    final pass = _sync(isCancelled ?? () => false);
    _running = pass;
    return pass.whenComplete(() => _running = null);
  }

  Future<KeepsakeLibrarySyncResult> _sync(bool Function() isCancelled) async {
    final user = Store.tryGet(StoreKey.currentUser);
    if (user == null) {
      _log.warning('No vault user yet; skipping library projection');
      return KeepsakeLibrarySyncResult.empty;
    }
    await _ensureOwner(user);

    var seq = Store.tryGet(StoreKey.keepsakeIndexSeq) ?? 0;
    var changed = 0;
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
        break;
      }
    }
    if (changed > 0) {
      _log.info('Projected $changed library change(s) up to seq $seq');
    }
    return KeepsakeLibrarySyncResult(changed: changed, trashedIds: trashed, deletedIds: deleted);
  }

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
      latitude: asset.latitude,
      lensModel: null,
      longitude: asset.longitude,
      make: asset.make,
      model: asset.model,
      modifyDate: DateTime.fromMillisecondsSinceEpoch(asset.modifiedAtMs, isUtc: true),
      orientation: asset.orientation?.toString(),
      profileDescription: null,
      projectionType: null,
      rating: asset.rating,
      state: null,
      timeZone: null,
    );
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
