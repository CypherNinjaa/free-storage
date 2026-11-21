import 'package:pigeon/pigeon.dart';

enum TelegramAuthStep { starting, waitPhoneNumber, waitCode, waitPassword, ready, loggingOut, closed }

class TelegramAuthStatus {
  TelegramAuthStatus({required this.step, this.passwordHint, this.accountName});

  TelegramAuthStep step;
  String? passwordHint;
  String? accountName;
}

class VaultChannels {
  VaultChannels({required this.libraryChatId, required this.systemChatId});

  int libraryChatId;
  int systemChatId;
}

class VaultStatus {
  VaultStatus({required this.exists, required this.unlocked, this.vaultId});

  bool exists;
  bool unlocked;
  String? vaultId;
}

class SelfTestReport {
  SelfTestReport({required this.success, required this.steps});

  bool success;
  List<String> steps;
}

/// One asset stored in the Telegram Library channel, as recorded in the on-device index.
class LibraryAsset {
  LibraryAsset({
    required this.id,
    required this.checksum,
    this.localId,
    required this.name,
    required this.mimeType,
    required this.type,
    required this.createdAtMs,
    required this.modifiedAtMs,
    this.width,
    this.height,
    this.durationMs,
    required this.sizeBytes,
    this.latitude,
    this.longitude,
    this.make,
    this.model,
    this.orientation,
    required this.isFavorite,
    required this.visibility,
    this.deletedAtMs,
    required this.uploadedAtMs,
    this.description,
    this.rating,
  });

  String id;

  /// Base64 SHA-1 of the original bytes (same format as the local asset hash).
  String checksum;
  String? localId;
  String name;
  String mimeType;

  /// 1 = image, 2 = video.
  int type;
  int createdAtMs;
  int modifiedAtMs;
  int? width;
  int? height;
  int? durationMs;
  int sizeBytes;
  double? latitude;
  double? longitude;
  String? make;
  String? model;
  int? orientation;
  bool isFavorite;

  /// 0 = timeline, 1 = archive, 2 = hidden, 3 = locked.
  int visibility;
  int? deletedAtMs;
  int uploadedAtMs;
  String? description;
  int? rating;
}

class LibraryChanges {
  LibraryChanges({required this.assets, required this.deletedIds, required this.nextSeq, required this.hasMore});

  List<LibraryAsset> assets;
  List<String> deletedIds;
  int nextSeq;
  bool hasMore;
}

class BackupAssetRequest {
  BackupAssetRequest({required this.localId, this.checksum, this.createdAtMs, this.modifiedAtMs, required this.isFavorite});

  String localId;
  String? checksum;
  int? createdAtMs;
  int? modifiedAtMs;
  bool isFavorite;
}

class LibraryAssetUpdate {
  LibraryAssetUpdate({
    required this.ids,
    this.isFavorite,
    this.visibility,
    this.createdAtMs,
    this.latitude,
    this.longitude,
  });

  List<String> ids;
  bool? isFavorite;
  int? visibility;
  int? createdAtMs;
  double? latitude;
  double? longitude;
}

/// An album kept in the on-device index (albums have no server in Keepsake).
class LibraryAlbum {
  LibraryAlbum({
    required this.id,
    required this.name,
    this.description,
    this.thumbnailAssetId,
    required this.order,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.assetCount,
  });

  String id;
  String name;
  String? description;
  String? thumbnailAssetId;

  /// 0 = newest first, 1 = oldest first.
  int order;
  int createdAtMs;
  int updatedAtMs;
  int assetCount;
}

class AlbumAssetLink {
  AlbumAssetLink({required this.albumId, required this.assetId});

  String albumId;
  String assetId;
}

class AlbumChanges {
  AlbumChanges({
    required this.albums,
    required this.deletedAlbumIds,
    required this.addedLinks,
    required this.removedLinks,
    required this.nextSeq,
  });

  List<LibraryAlbum> albums;
  List<String> deletedAlbumIds;
  List<AlbumAssetLink> addedLinks;
  List<AlbumAssetLink> removedLinks;
  int nextSeq;
}

class DiscoveredVault {
  DiscoveredVault({required this.vaultName, required this.libraryChatId, required this.systemChatId});

  String vaultName;
  int libraryChatId;
  int systemChatId;
}

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/keepsake_api.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/app/alextran/immich/keepsake/Keepsake.g.kt',
    kotlinOptions: KotlinOptions(package: 'app.alextran.immich.keepsake', includeErrorClass: true),
    dartOptions: DartOptions(),
    dartPackageName: 'immich_mobile',
  ),
)
@HostApi()
abstract class KeepsakeTelegramApi {
  @async
  TelegramAuthStatus getAuthStatus();

  @async
  TelegramAuthStatus submitPhoneNumber(String phoneNumber);

  @async
  TelegramAuthStatus submitCode(String code);

  @async
  TelegramAuthStatus submitPassword(String password);

  @async
  VaultChannels ensureVaultChannels(String vaultName);

  @async
  VaultChannels? getVaultChannels();

  @async
  SelfTestReport runSelfTest();

  @async
  void logOut();
}

@HostApi()
abstract class KeepsakeVaultApi {
  @async
  VaultStatus getStatus();

  @async
  VaultStatus createVault(String passphrase, Uint8List recoveryEntropy);

  @async
  VaultStatus unlockWithPassphrase(String passphrase);

  @async
  VaultStatus unlockWithRecoveryEntropy(Uint8List recoveryEntropy);

  @async
  void lock();
}

@HostApi()
abstract class KeepsakeLibraryApi {
  /// Starts (once) the loopback media server and returns its base URL, used as the app's server endpoint.
  @async
  String startMediaServer();

  @async
  LibraryChanges changesSince(int sinceSeq, int limit);

  /// Encrypts one local asset, uploads it to the Library channel, verifies it and records it in the index.
  @async
  LibraryAsset backupLocalAsset(BackupAssetRequest request);

  @async
  int trash(List<String> ids);

  @async
  int restoreFromTrash(List<String> ids);

  @async
  int restoreAllTrash();

  @async
  int deletePermanently(List<String> ids);

  @async
  int emptyTrash();

  @async
  int updateAssets(LibraryAssetUpdate update);

  @async
  int updateDescription(String id, String description);

  @async
  int updateRating(String id, int? rating);

  @async
  LibraryAsset? getAsset(String id);

  @async
  int assetCount();

  /// Uploads an encrypted index snapshot when [force] is set or one is due; returns -1 when skipped.
  @async
  int snapshotIndex(bool force);

  /// Looks for an existing vault in this Telegram account and, if found, adopts its descriptor and channels.
  @async
  DiscoveredVault? discoverAndAdoptVault();

  /// Rebuilds the on-device index from the newest snapshot plus the Library channel history.
  @async
  int restoreIndex();

  @async
  bool getEncryptUploads();

  @async
  void setEncryptUploads(bool enabled);

  @async
  LibraryAlbum createAlbum(String name, String? description, List<String> assetIds);

  /// Null fields stay unchanged; an empty description clears it.
  @async
  LibraryAlbum? updateAlbum(String id, String? name, String? description, String? thumbnailAssetId, int? order);

  @async
  bool deleteAlbum(String id);

  /// Returns the ids that were newly added.
  @async
  List<String> addAlbumAssets(String albumId, List<String> assetIds);

  /// Returns the ids that were removed.
  @async
  List<String> removeAlbumAssets(String albumId, List<String> assetIds);

  /// Album changes with a sequence number in (sinceSeq, untilSeq].
  @async
  AlbumChanges albumChangesSince(int sinceSeq, int untilSeq);
}
