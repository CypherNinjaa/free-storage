import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/services/keepsake_library_sync.service.dart';
import 'package:immich_mobile/platform/keepsake_api.g.dart';
import 'package:openapi/api.dart';

LibraryAsset _asset({int type = 1, int? orientation, int visibility = 0, int? deletedAtMs}) => LibraryAsset(
  id: 'asset-1',
  checksum: 'c2hhMQ==',
  name: 'IMG_0001.HEIC',
  mimeType: 'image/heic',
  type: type,
  createdAtMs: DateTime.utc(2024, 3, 10, 18, 30).millisecondsSinceEpoch,
  modifiedAtMs: DateTime.utc(2024, 3, 11).millisecondsSinceEpoch,
  width: 4032,
  height: 3024,
  durationMs: type == 2 ? 12000 : null,
  sizeBytes: 2048,
  latitude: 12.5,
  longitude: 77.25,
  make: 'realme',
  model: 'RMX',
  orientation: orientation,
  isFavorite: true,
  visibility: visibility,
  deletedAtMs: deletedAtMs,
  uploadedAtMs: DateTime.utc(2024, 3, 12).millisecondsSinceEpoch,
  description: 'Beach day',
  rating: 4,
);

void main() {
  group('KeepsakeLibrarySyncService mapping', () {
    test('maps an image with its owner, dates and display size', () {
      final dto = KeepsakeLibrarySyncService.toSyncAsset(_asset(), 'user-1');

      expect(dto.id, 'asset-1');
      expect(dto.ownerId, 'user-1');
      expect(dto.checksum, 'c2hhMQ==');
      expect(dto.type, AssetTypeEnum.IMAGE);
      expect(dto.visibility, AssetVisibility.timeline);
      expect(dto.isFavorite, isTrue);
      expect(dto.fileCreatedAt, DateTime.utc(2024, 3, 10, 18, 30));
      expect(dto.createdAt, DateTime.utc(2024, 3, 12));
      expect(dto.deletedAt, isNull);
      expect((dto.width, dto.height), (4032, 3024));
    });

    test('swaps width and height for rotated EXIF orientations', () {
      for (final orientation in [5, 6, 7, 8]) {
        final dto = KeepsakeLibrarySyncService.toSyncAsset(_asset(orientation: orientation), 'user-1');
        expect((dto.width, dto.height), (3024, 4032), reason: 'orientation $orientation');
      }
      final upright = KeepsakeLibrarySyncService.toSyncAsset(_asset(orientation: 1), 'user-1');
      expect((upright.width, upright.height), (4032, 3024));
    });

    test('localDateTime is the capture wall-clock time expressed in UTC', () {
      final dto = KeepsakeLibrarySyncService.toSyncAsset(_asset(), 'user-1');
      final local = DateTime.utc(2024, 3, 10, 18, 30).toLocal();

      expect(dto.localDateTime!.isUtc, isTrue);
      expect(
        dto.localDateTime,
        DateTime.utc(local.year, local.month, local.day, local.hour, local.minute, local.second),
      );
    });

    test('maps videos, trash state and visibility', () {
      final dto = KeepsakeLibrarySyncService.toSyncAsset(
        _asset(type: 2, visibility: 1, deletedAtMs: DateTime.utc(2024, 4, 1).millisecondsSinceEpoch),
        'user-1',
      );

      expect(dto.type, AssetTypeEnum.VIDEO);
      expect(dto.duration, 12000);
      expect(dto.visibility, AssetVisibility.archive);
      expect(dto.deletedAt, DateTime.utc(2024, 4, 1));
    });

    test('visibility round-trips through the index encoding', () {
      for (final visibility in AssetVisibility.values) {
        final index = KeepsakeLibrarySyncService.visibilityToIndex(visibility);
        expect(KeepsakeLibrarySyncService.visibilityFromIndex(index), visibility);
      }
    });

    test('exif carries raw size, location, camera, description and rating', () {
      final exif = KeepsakeLibrarySyncService.toSyncExif(_asset(orientation: 6));

      expect(exif.assetId, 'asset-1');
      expect((exif.exifImageWidth, exif.exifImageHeight), (4032, 3024));
      expect(exif.orientation, '6');
      expect((exif.latitude, exif.longitude), (12.5, 77.25));
      expect((exif.make, exif.model), ('realme', 'RMX'));
      expect(exif.fileSizeInByte, 2048);
      expect(exif.description, 'Beach day');
      expect(exif.rating, 4);
      expect(exif.dateTimeOriginal, DateTime.utc(2024, 3, 10, 18, 30));
      expect(
        exif.timeZone,
        KeepsakeLibrarySyncService.utcOffsetLabel(DateTime.utc(2024, 3, 10, 18, 30).toLocal().timeZoneOffset),
      );
    });

    test('offset labels match the format Immich parses', () {
      expect(KeepsakeLibrarySyncService.utcOffsetLabel(const Duration(hours: 5, minutes: 30)), 'UTC+05:30');
      expect(KeepsakeLibrarySyncService.utcOffsetLabel(const Duration(hours: -4)), 'UTC-04:00');
      expect(KeepsakeLibrarySyncService.utcOffsetLabel(Duration.zero), 'UTC+00:00');
      expect(KeepsakeLibrarySyncService.utcOffsetLabel(const Duration(hours: -9, minutes: -30)), 'UTC-09:30');
    });

    test('0,0 coordinates (no GPS fix) project as no location', () {
      final noFix = LibraryAsset(
        id: 'video-1',
        checksum: 'dmlkZW8=',
        name: 'VID_0001.mp4',
        mimeType: 'video/mp4',
        type: 2,
        createdAtMs: 0,
        modifiedAtMs: 0,
        sizeBytes: 1,
        latitude: 0,
        longitude: 0,
        isFavorite: false,
        visibility: 0,
        uploadedAtMs: 0,
      );

      final exif = KeepsakeLibrarySyncService.toSyncExif(noFix);

      expect(exif.latitude, isNull);
      expect(exif.longitude, isNull);
      expect(KeepsakeLibrarySyncService.toSyncExif(_asset()).latitude, 12.5);
    });

    test('maps an index album to the sync album row Immich expects', () {
      final album = LibraryAlbum(
        id: 'album-1',
        name: 'Goa 2024',
        description: null,
        thumbnailAssetId: 'asset-1',
        order: 1,
        createdAtMs: DateTime.utc(2024, 3, 12, 9).millisecondsSinceEpoch,
        updatedAtMs: DateTime.utc(2024, 3, 13, 10).millisecondsSinceEpoch,
        assetCount: 12,
      );

      final dto = KeepsakeLibrarySyncService.toSyncAlbum(album, 'user-1');

      expect(dto.id, 'album-1');
      expect(dto.name, 'Goa 2024');
      expect(dto.ownerId, 'user-1');
      expect(dto.description, '');
      expect(dto.thumbnailAssetId, 'asset-1');
      expect(dto.order, AssetOrder.asc);
      expect(dto.isActivityEnabled, isFalse);
      expect(dto.createdAt, DateTime.utc(2024, 3, 12, 9));
      expect(dto.updatedAt, DateTime.utc(2024, 3, 13, 10));
    });

    test('albums default to newest first', () {
      final album = LibraryAlbum(
        id: 'album-2',
        name: 'Family',
        description: 'Weekend',
        order: 0,
        createdAtMs: 0,
        updatedAtMs: 0,
        assetCount: 0,
      );

      final dto = KeepsakeLibrarySyncService.toSyncAlbum(album, 'user-1');

      expect(dto.order, AssetOrder.desc);
      expect(dto.description, 'Weekend');
      expect(dto.thumbnailAssetId, isNull);
    });
  });
}
