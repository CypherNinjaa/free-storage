import 'package:drift/drift.dart';
import 'package:immich_mobile/data/db/main/database.dart';
import 'package:immich_mobile/data/db/main/table/memory/memory.drift.dart';
import 'package:immich_mobile/data/db/main/table/remote/asset.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/memory.model.dart';
import 'package:immich_mobile/infrastructure/repositories/memory.repository.drift.dart';

@DriftAccessor()
class MemoryRepository extends DatabaseAccessor<Drift> with $MemoryRepositoryMixin {
  MemoryRepository(super.attachedDatabase);

  Drift get _db => attachedDatabase;

  /// Timeline asset ids of [ownerId] captured on [month]/[day] of a year before [beforeYear], grouped by year.
  /// Used to build "On this day" memories on device (serverless Keepsake has no server to generate them).
  Future<Map<int, List<String>>> getOnThisDayAssetIds(
    String ownerId, {
    required int month,
    required int day,
    required int beforeYear,
  }) async {
    final asset = _db.remoteAssetEntity;
    final year = asset.localDateTime.year;
    final query = _db.selectOnly(asset)
      ..addColumns([asset.id, year])
      ..where(
        asset.ownerId.equals(ownerId) &
            asset.deletedAt.isNull() &
            asset.visibility.equalsValue(AssetVisibility.timeline) &
            asset.localDateTime.month.equals(month) &
            asset.localDateTime.day.equals(day) &
            year.isSmallerThanValue(beforeYear),
      )
      ..orderBy([OrderingTerm.asc(asset.createdAt)]);

    final result = <int, List<String>>{};
    for (final row in await query.get()) {
      final assetYear = row.read(year);
      final id = row.read(asset.id);
      if (assetYear != null && id != null) {
        (result[assetYear] ??= []).add(id);
      }
    }
    return result;
  }

  Future<List<Memory>> getAll(String ownerId, {bool onlyToday = true, bool onlyFavorites = false}) async {
    final query =
        _db.select(_db.memoryEntity).join([
            innerJoin(_db.memoryAssetEntity, _db.memoryAssetEntity.memoryId.equalsExp(_db.memoryEntity.id)),
            innerJoin(
              _db.remoteAssetEntity,
              _db.remoteAssetEntity.id.equalsExp(_db.memoryAssetEntity.assetId) &
                  _db.remoteAssetEntity.deletedAt.isNull() &
                  _db.remoteAssetEntity.visibility.equalsValue(AssetVisibility.timeline),
            ),
          ])
          ..where(_db.memoryEntity.ownerId.equals(ownerId))
          ..where(_db.memoryEntity.deletedAt.isNull());

    if (onlyFavorites) {
      query.where(_db.memoryEntity.isSaved.equals(true));
    }

    if (onlyToday) {
      final now = DateTime.now();
      final localUtc = DateTime.utc(now.year, now.month, now.day, 0, 0, 0);

      query.where(_db.memoryEntity.showAt.isNull() | _db.memoryEntity.showAt.isSmallerOrEqualValue(localUtc));
      query.where(_db.memoryEntity.hideAt.isNull() | _db.memoryEntity.hideAt.isBiggerOrEqualValue(localUtc));
    }

    query.orderBy([
      OrderingTerm.asc(_db.memoryEntity.showAt.isNull()),
      OrderingTerm.desc(_db.memoryEntity.showAt),
      OrderingTerm.desc(_db.memoryEntity.memoryAt),
      OrderingTerm.asc(_db.remoteAssetEntity.createdAt),
    ]);

    final rows = await query.get();
    if (rows.isEmpty) {
      return const [];
    }

    final memories = <String, ({MemoryEntityData memory, List<RemoteAsset> assets})>{};

    for (final row in rows) {
      final memory = row.readTable(_db.memoryEntity);
      final asset = row.readTable(_db.remoteAssetEntity);

      final entry = memories.putIfAbsent(memory.id, () => (memory: memory, assets: []));
      entry.assets.add(asset.toDto());
    }

    return memories.values.map((e) => e.memory.toDto().copyWith(assets: e.assets)).toList(growable: false);
  }

  Future<Memory?> get(String memoryId) async {
    final query =
        _db.select(_db.memoryEntity).join([
            leftOuterJoin(_db.memoryAssetEntity, _db.memoryAssetEntity.memoryId.equalsExp(_db.memoryEntity.id)),
            leftOuterJoin(
              _db.remoteAssetEntity,
              _db.remoteAssetEntity.id.equalsExp(_db.memoryAssetEntity.assetId) &
                  _db.remoteAssetEntity.deletedAt.isNull() &
                  _db.remoteAssetEntity.visibility.equalsValue(AssetVisibility.timeline),
            ),
          ])
          ..where(_db.memoryEntity.id.equals(memoryId))
          ..where(_db.memoryEntity.deletedAt.isNull())
          ..orderBy([OrderingTerm.desc(_db.memoryEntity.memoryAt), OrderingTerm.asc(_db.remoteAssetEntity.createdAt)]);

    final rows = await query.get();

    if (rows.isEmpty) {
      return null;
    }

    final memory = rows.first.readTable(_db.memoryEntity);
    final assets = <RemoteAsset>[];

    for (final row in rows) {
      final asset = row.readTable(_db.remoteAssetEntity);
      assets.add(asset.toDto());
    }

    return memory.toDto().copyWith(assets: assets);
  }

  Future<int> getCount() {
    return _db.managers.memoryEntity.count();
  }

  Stream<void> watchChanges() {
    return _db.tableUpdates(TableUpdateQuery.onAllTables([_db.memoryEntity, _db.memoryAssetEntity]));
  }
}

extension on MemoryEntityData {
  Memory toDto() {
    return Memory(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      ownerId: ownerId,
      type: type,
      data: MemoryData.fromJson(data),
      isSaved: isSaved,
      memoryAt: memoryAt,
      seenAt: seenAt,
      showAt: showAt,
      hideAt: hideAt,
      assets: [],
    );
  }
}
