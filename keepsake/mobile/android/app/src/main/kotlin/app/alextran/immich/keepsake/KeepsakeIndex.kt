package app.alextran.immich.keepsake

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.io.File
import java.util.UUID

data class IndexRecord(
  val id: String,
  val checksum: String,
  val localId: String?,
  val name: String,
  val mimeType: String,
  val type: Int,
  val createdAtMs: Long,
  val modifiedAtMs: Long,
  val width: Int?,
  val height: Int?,
  val durationMs: Long?,
  val sizeBytes: Long,
  val latitude: Double?,
  val longitude: Double?,
  val make: String?,
  val model: String?,
  val orientation: Int?,
  val isFavorite: Boolean,
  val visibility: Int,
  val deletedAtMs: Long?,
  val uploadedAtMs: Long,
  val chatId: Long,
  val messageId: Long,
  val fileId: Int,
  val fileUniqueId: String,
  val encryptedSize: Long,
  val wrappedDek: ByteArray,
  val hasThumbnail: Boolean,
  val description: String? = null,
  val rating: Int? = null,
  /** [KeepsakeIndex.FORMAT_ENCRYPTED] (IMTG segments) or [KeepsakeIndex.FORMAT_PLAIN] (the original file as is). */
  val format: Int = KeepsakeIndex.FORMAT_ENCRYPTED,
  val seq: Long = 0,
  /**
   * Number of Telegram files holding the asset. Split assets (more than one) list every part in the parts table;
   * [chatId], [messageId] and [fileId] then name part 0 and [encryptedSize] is the size of all parts together.
   */
  val partCount: Int = 1,
  /** Original bytes per part of a split asset ([PartLayout.partPlainBytes]); 0 otherwise. */
  val partBytes: Long = 0,
) {
  val isEncrypted: Boolean get() = format == KeepsakeIndex.FORMAT_ENCRYPTED

  val layout: PartLayout? get() = if (partCount > 1) PartLayout(sizeBytes, partBytes, isEncrypted) else null
}

data class IndexChanges(val records: List<IndexRecord>, val deletedIds: List<String>, val nextSeq: Long, val hasMore: Boolean)

data class AlbumRecord(
  val id: String,
  val name: String,
  val description: String?,
  val thumbnailAssetId: String?,
  /** 0 = newest first, 1 = oldest first. */
  val order: Int,
  val createdAtMs: Long,
  val updatedAtMs: Long,
  val assetCount: Long,
  val seq: Long = 0,
)

data class AlbumLink(val albumId: String, val assetId: String)

data class IndexAlbumChanges(
  val albums: List<AlbumRecord>,
  val deletedAlbumIds: List<String>,
  val addedLinks: List<AlbumLink>,
  val removedLinks: List<AlbumLink>,
  val nextSeq: Long,
)

/**
 * The on-device index of everything stored in the vault: assets and albums.
 *
 * Every change gets its own, strictly increasing sequence number (`seq`), and deletions leave tombstones, so a
 * reader can page through "everything after N" without missing rows. Rows never share a sequence number; that
 * keeps page boundaries exact even for bulk writes such as a restore.
 */
class KeepsakeIndex(context: Context, val file: File) :
  SQLiteOpenHelper(context, file.absolutePath, null, SCHEMA_VERSION) {

  override fun onCreate(db: SQLiteDatabase) {
    db.execSQL(
      """
      CREATE TABLE assets (
        id TEXT PRIMARY KEY,
        checksum TEXT NOT NULL UNIQUE,
        local_id TEXT,
        name TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        type INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        modified_at INTEGER NOT NULL,
        width INTEGER,
        height INTEGER,
        duration_ms INTEGER,
        size_bytes INTEGER NOT NULL,
        latitude REAL,
        longitude REAL,
        make TEXT,
        model TEXT,
        orientation INTEGER,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        visibility INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER,
        uploaded_at INTEGER NOT NULL,
        chat_id INTEGER NOT NULL,
        message_id INTEGER NOT NULL,
        file_id INTEGER NOT NULL,
        file_unique_id TEXT NOT NULL,
        encrypted_size INTEGER NOT NULL,
        wrapped_dek BLOB NOT NULL,
        has_thumbnail INTEGER NOT NULL DEFAULT 0,
        seq INTEGER NOT NULL,
        description TEXT,
        rating INTEGER,
        format INTEGER NOT NULL DEFAULT $FORMAT_ENCRYPTED,
        part_count INTEGER NOT NULL DEFAULT 1,
        part_bytes INTEGER NOT NULL DEFAULT 0
      )
      """.trimIndent()
    )
    db.execSQL("CREATE INDEX assets_seq_idx ON assets (seq)")
    db.execSQL("CREATE INDEX assets_local_id_idx ON assets (local_id)")
    db.execSQL("CREATE TABLE tombstones (id TEXT PRIMARY KEY, seq INTEGER NOT NULL)")
    db.execSQL("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    db.execSQL("INSERT INTO meta (key, value) VALUES ('seq', '0')")
    createAlbumTables(db)
    createPartTable(db)
  }

  override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
    if (oldVersion < 2) {
      db.execSQL("ALTER TABLE assets ADD COLUMN description TEXT")
      db.execSQL("ALTER TABLE assets ADD COLUMN rating INTEGER")
    }
    if (oldVersion < 3) {
      db.execSQL("ALTER TABLE assets ADD COLUMN format INTEGER NOT NULL DEFAULT $FORMAT_ENCRYPTED")
      createAlbumTables(db)
      // Version 2 gave every row of one write the same sequence number; renumber so each row has its own.
      val head = readSeq(db)
      db.execSQL("UPDATE assets SET seq = ? + rowid", arrayOf(head))
      val maxRowId = db.rawQuery("SELECT COALESCE(MAX(rowid), 0) FROM assets", null).use { it.moveToFirst(); it.getLong(0) }
      db.execSQL("UPDATE meta SET value = ? WHERE key = 'seq'", arrayOf((head + maxRowId).toString()))
    }
    if (oldVersion < 4) {
      db.execSQL("ALTER TABLE assets ADD COLUMN part_count INTEGER NOT NULL DEFAULT 1")
      db.execSQL("ALTER TABLE assets ADD COLUMN part_bytes INTEGER NOT NULL DEFAULT 0")
      createPartTable(db)
    }
  }

  /** The Telegram messages of split assets, part 0 included. Assets stored in one file have no rows here. */
  private fun createPartTable(db: SQLiteDatabase) {
    db.execSQL(
      """
      CREATE TABLE asset_parts (
        asset_id TEXT NOT NULL,
        part_index INTEGER NOT NULL,
        chat_id INTEGER NOT NULL,
        message_id INTEGER NOT NULL,
        file_id INTEGER NOT NULL,
        stored_size INTEGER NOT NULL,
        PRIMARY KEY (asset_id, part_index)
      )
      """.trimIndent()
    )
  }

  private fun createAlbumTables(db: SQLiteDatabase) {
    db.execSQL(
      """
      CREATE TABLE albums (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        thumbnail_asset_id TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        seq INTEGER NOT NULL
      )
      """.trimIndent()
    )
    db.execSQL(
      """
      CREATE TABLE album_assets (
        album_id TEXT NOT NULL,
        asset_id TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        seq INTEGER NOT NULL,
        PRIMARY KEY (album_id, asset_id)
      )
      """.trimIndent()
    )
    db.execSQL("CREATE INDEX albums_seq_idx ON albums (seq)")
    db.execSQL("CREATE INDEX album_assets_seq_idx ON album_assets (seq)")
    db.execSQL("CREATE INDEX album_assets_asset_idx ON album_assets (asset_id)")
    db.execSQL("CREATE TABLE album_tombstones (id TEXT PRIMARY KEY, seq INTEGER NOT NULL)")
    db.execSQL(
      "CREATE TABLE album_asset_tombstones (album_id TEXT NOT NULL, asset_id TEXT NOT NULL, seq INTEGER NOT NULL, " +
        "PRIMARY KEY (album_id, asset_id))"
    )
  }

  // ---------------------------------------------------------------------------------------------------------
  // Assets

  fun findByChecksum(checksum: String): IndexRecord? =
    readableDatabase.query("assets", null, "checksum = ?", arrayOf(checksum), null, null, null).use { it.firstRecord() }

  fun find(id: String): IndexRecord? =
    readableDatabase.query("assets", null, "id = ?", arrayOf(id), null, null, null).use { it.firstRecord() }

  fun findAll(ids: List<String>): List<IndexRecord> = ids.mapNotNull(::find)

  fun trashedIds(): List<String> =
    readableDatabase.rawQuery("SELECT id FROM assets WHERE deleted_at IS NOT NULL", null).use { cursor ->
      buildList { while (cursor.moveToNext()) add(cursor.getString(0)) }
    }

  fun trashedBefore(cutoffMs: Long): List<String> =
    readableDatabase.rawQuery(
      "SELECT id FROM assets WHERE deleted_at IS NOT NULL AND deleted_at < ?",
      arrayOf(cutoffMs.toString()),
    ).use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.getString(0)) } }

  fun count(): Long = readableDatabase.rawQuery("SELECT COUNT(*) FROM assets", null).use {
    it.moveToFirst()
    it.getLong(0)
  }

  /** Adds or replaces an asset; [parts] lists every Telegram message of a split asset (empty otherwise). */
  fun upsert(record: IndexRecord, parts: List<PartRef> = emptyList()) = upsertAll(listOf(record to parts))

  /** [upsert] for many assets in one transaction (a restore adds thousands). */
  fun upsertAll(entries: List<Pair<IndexRecord, List<PartRef>>>) {
    if (entries.isEmpty()) return
    write { db, seqs ->
      for ((record, parts) in entries) {
        db.insertWithOnConflict("assets", null, record.toValues(seqs.next()), SQLiteDatabase.CONFLICT_REPLACE)
        db.delete("tombstones", "id = ?", arrayOf(record.id))
        db.delete("asset_parts", "asset_id = ?", arrayOf(record.id))
        for (part in parts) {
          db.insertOrThrow("asset_parts", null, ContentValues().apply {
            put("asset_id", record.id)
            put("part_index", part.index)
            put("chat_id", part.chatId)
            put("message_id", part.messageId)
            put("file_id", part.fileId)
            put("stored_size", part.storedSize)
          })
        }
      }
    }
  }

  /** The Telegram messages of a split asset, in order; empty for an asset stored in one file. */
  fun parts(assetId: String): List<PartRef> =
    readableDatabase.rawQuery(
      "SELECT part_index, chat_id, message_id, file_id, stored_size FROM asset_parts WHERE asset_id = ? ORDER BY part_index",
      arrayOf(assetId),
    ).use { cursor ->
      buildList {
        while (cursor.moveToNext()) {
          add(PartRef(cursor.getInt(0), cursor.getLong(1), cursor.getLong(2), cursor.getInt(3), cursor.getLong(4)))
        }
      }
    }

  fun update(ids: List<String>, values: ContentValues): Int = write { db, seqs ->
    ids.sumOf { id ->
      val row = ContentValues(values).apply { put("seq", seqs.next()) }
      db.update("assets", row, "id = ?", arrayOf(id))
    }
  }

  @Synchronized
  fun updateFileId(id: String, fileId: Int) {
    writableDatabase.update("assets", ContentValues().apply { put("file_id", fileId) }, "id = ?", arrayOf(id))
  }

  /** [updateFileId] for many assets in one transaction. Like it, this does not advance the change sequence. */
  @Synchronized
  fun updateFileIds(updates: Map<String, Int>) {
    if (updates.isEmpty()) return
    val db = writableDatabase
    db.beginTransaction()
    try {
      for ((id, fileId) in updates) {
        db.update("assets", ContentValues().apply { put("file_id", fileId) }, "id = ?", arrayOf(id))
      }
      db.setTransactionSuccessful()
    } finally {
      db.endTransaction()
    }
  }

  @Synchronized
  fun markThumbnail(id: String) {
    writableDatabase.update("assets", ContentValues().apply { put("has_thumbnail", 1) }, "id = ?", arrayOf(id))
  }

  /** Message references of every asset stored in [chatId], used to reconcile the index with the channel. */
  fun messageRefs(chatId: Long): List<Pair<String, Long>> =
    readableDatabase.rawQuery("SELECT id, message_id FROM assets WHERE chat_id = ?", arrayOf(chatId.toString())).use { cursor ->
      buildList { while (cursor.moveToNext()) add(cursor.getString(0) to cursor.getLong(1)) }
    }

  /** Writes a consistent copy of the index to [target]; writers are held off while the file is copied. */
  @Synchronized
  fun exportTo(target: File) {
    checkpoint()
    file.copyTo(target, overwrite = true)
  }

  /** Removes assets (leaving tombstones) and takes them out of every album they were in. */
  fun delete(ids: List<String>): Int = write { db, seqs ->
    ids.sumOf { id ->
      val removed = db.delete("assets", "id = ?", arrayOf(id))
      db.delete("asset_parts", "asset_id = ?", arrayOf(id))
      db.insertWithOnConflict("tombstones", null, ContentValues().apply {
        put("id", id)
        put("seq", seqs.next())
      }, SQLiteDatabase.CONFLICT_REPLACE)
      val albums = db.rawQuery("SELECT album_id FROM album_assets WHERE asset_id = ?", arrayOf(id)).use { cursor ->
        buildList { while (cursor.moveToNext()) add(cursor.getString(0)) }
      }
      for (albumId in albums) {
        db.delete("album_assets", "album_id = ? AND asset_id = ?", arrayOf(albumId, id))
        tombstoneLink(db, seqs, albumId, id)
        refreshCover(db, albumId)
        touchAlbum(db, seqs, albumId)
      }
      removed
    }
  }

  /**
   * Asset changes after [sinceSeq], oldest first. When [IndexChanges.hasMore] is false the reader is up to date
   * with every change (assets and albums) made before this call, and [IndexChanges.nextSeq] is the index head.
   */
  fun changesSince(sinceSeq: Long, limit: Int): IndexChanges {
    val db = readableDatabase
    // Read the head first: every row with seq <= head was committed together with that head value.
    val head = currentSeq()
    val records = db.query(
      "assets", null, "seq > ? AND seq <= ?", arrayOf(sinceSeq.toString(), head.toString()), null, null, "seq ASC",
      (limit + 1).toString(),
    ).use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.toRecord()) } }
    val hasMore = records.size > limit
    val page = records.take(limit)
    val upper = if (hasMore) page.last().seq else head
    val deleted = db.rawQuery(
      "SELECT id FROM tombstones WHERE seq > ? AND seq <= ? ORDER BY seq",
      arrayOf(sinceSeq.toString(), upper.toString()),
    ).use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.getString(0)) } }
    return IndexChanges(page, deleted, maxOf(sinceSeq, upper), hasMore)
  }

  @Synchronized
  fun replaceWith(source: File) {
    close()
    listOf("-wal", "-shm", "-journal").forEach { File(file.path + it).delete() }
    source.copyTo(file, overwrite = true)
    // Opening the copy upgrades an older snapshot first; then every row is renumbered so it projects again.
    write { db, seqs ->
      db.execSQL("UPDATE assets SET file_id = -1, local_id = NULL, has_thumbnail = 0")
      db.execSQL("UPDATE asset_parts SET file_id = -1")
      renumber(db, seqs, "assets")
      renumber(db, seqs, "albums")
      renumber(db, seqs, "album_assets")
    }
  }

  private fun renumber(db: SQLiteDatabase, seqs: SeqAllocator, table: String) {
    val base = seqs.current
    db.execSQL("UPDATE $table SET seq = ? + rowid", arrayOf(base))
    val maxRowId = db.rawQuery("SELECT COALESCE(MAX(rowid), 0) FROM $table", null).use { it.moveToFirst(); it.getLong(0) }
    seqs.advanceTo(base + maxRowId)
  }

  fun currentSeq(): Long = readSeq(readableDatabase)

  fun meta(key: String): String? =
    readableDatabase.rawQuery("SELECT value FROM meta WHERE key = ?", arrayOf(key)).use { if (it.moveToFirst()) it.getString(0) else null }

  /** Bookkeeping values; deliberately does not advance the change sequence. */
  @Synchronized
  fun putMeta(key: String, value: String) {
    writableDatabase.insertWithOnConflict(
      "meta",
      null,
      ContentValues().apply {
        put("key", key)
        put("value", value)
      },
      SQLiteDatabase.CONFLICT_REPLACE,
    )
  }

  @Synchronized
  fun deleteMeta(key: String) {
    writableDatabase.delete("meta", "key = ?", arrayOf(key))
  }

  /** Bookkeeping values whose key starts with [prefix], by key. */
  fun metaWithPrefix(prefix: String): Map<String, String> =
    readableDatabase.rawQuery(
      "SELECT key, value FROM meta WHERE substr(key, 1, ?) = ?",
      arrayOf(prefix.length.toString(), prefix),
    ).use { cursor -> buildMap { while (cursor.moveToNext()) put(cursor.getString(0), cursor.getString(1)) } }

  fun checkpoint() {
    writableDatabase.rawQuery("PRAGMA wal_checkpoint(TRUNCATE)", null).use { it.moveToFirst() }
  }

  // ---------------------------------------------------------------------------------------------------------
  // Albums

  fun findAlbum(id: String): AlbumRecord? =
    readableDatabase.rawQuery("$ALBUM_SELECT WHERE a.id = ?", arrayOf(id)).use { if (it.moveToFirst()) it.toAlbum() else null }

  fun albumCount(): Long = readableDatabase.rawQuery("SELECT COUNT(*) FROM albums", null).use {
    it.moveToFirst()
    it.getLong(0)
  }

  /** Whether any album, album membership or album deletion was recorded after [seq]. */
  fun albumsChangedSince(seq: Long): Boolean {
    val value = seq.toString()
    return exists(
      readableDatabase,
      "SELECT 1 WHERE EXISTS (SELECT 1 FROM albums WHERE seq > ?) OR EXISTS (SELECT 1 FROM album_assets WHERE seq > ?) " +
        "OR EXISTS (SELECT 1 FROM album_tombstones WHERE seq > ?) OR EXISTS (SELECT 1 FROM album_asset_tombstones WHERE seq > ?)",
      value, value, value, value,
    )
  }

  /** Creates an album holding the given assets (unknown ids are skipped). */
  fun createAlbum(name: String, description: String?, assetIds: List<String>): AlbumRecord {
    val id = UUID.randomUUID().toString()
    write { db, seqs ->
      val now = System.currentTimeMillis()
      db.insertOrThrow("albums", null, ContentValues().apply {
        put("id", id)
        put("name", name)
        put("description", description?.ifBlank { null })
        putNull("thumbnail_asset_id")
        put("sort_order", ORDER_DESC)
        put("created_at", now)
        put("updated_at", now)
        put("seq", seqs.next())
      })
      linkAssets(db, seqs, id, assetIds, now)
    }
    return checkNotNull(findAlbum(id))
  }

  /** Null arguments leave a field unchanged; an empty [description] clears it. */
  fun updateAlbum(id: String, name: String?, description: String?, thumbnailAssetId: String?, order: Int?): AlbumRecord? {
    val updated = write { db, seqs ->
      val values = ContentValues()
      name?.let { values.put("name", it) }
      description?.let { values.put("description", it.ifBlank { null }) }
      thumbnailAssetId?.takeIf { isLinked(db, id, it) }?.let { values.put("thumbnail_asset_id", it) }
      order?.let { values.put("sort_order", it) }
      values.put("updated_at", System.currentTimeMillis())
      values.put("seq", seqs.next())
      db.update("albums", values, "id = ?", arrayOf(id))
    }
    return if (updated > 0) findAlbum(id) else null
  }

  fun deleteAlbum(id: String): Boolean = write { db, seqs ->
    val removed = db.delete("albums", "id = ?", arrayOf(id))
    db.delete("album_assets", "album_id = ?", arrayOf(id))
    db.delete("album_asset_tombstones", "album_id = ?", arrayOf(id))
    db.insertWithOnConflict("album_tombstones", null, ContentValues().apply {
      put("id", id)
      put("seq", seqs.next())
    }, SQLiteDatabase.CONFLICT_REPLACE)
    removed > 0
  }

  /** Adds assets to an album; returns the ids that were newly added (already present or unknown ids are not). */
  fun addAlbumAssets(albumId: String, assetIds: List<String>): List<String> = write { db, seqs ->
    if (!exists(db, "SELECT 1 FROM albums WHERE id = ?", albumId)) return@write emptyList()
    linkAssets(db, seqs, albumId, assetIds, System.currentTimeMillis())
  }

  /** Removes assets from an album; returns the ids that were in it. */
  fun removeAlbumAssets(albumId: String, assetIds: List<String>): List<String> = write { db, seqs ->
    val removed = assetIds.distinct().filter { assetId ->
      db.delete("album_assets", "album_id = ? AND asset_id = ?", arrayOf(albumId, assetId)) > 0
    }
    removed.forEach { tombstoneLink(db, seqs, albumId, it) }
    if (removed.isNotEmpty()) {
      refreshCover(db, albumId)
      touchAlbum(db, seqs, albumId)
    }
    removed
  }

  /**
   * Album changes with a sequence number in (sinceSeq, untilSeq]. Callers pass the head they have projected
   * assets up to as [untilSeq], so every asset an album link points at is already known to them.
   */
  fun albumChangesSince(sinceSeq: Long, untilSeq: Long): IndexAlbumChanges {
    val db = readableDatabase
    val range = arrayOf(sinceSeq.toString(), untilSeq.toString())
    val albums = db.rawQuery("$ALBUM_SELECT WHERE a.seq > ? AND a.seq <= ? ORDER BY a.seq", range).use { cursor ->
      buildList { while (cursor.moveToNext()) add(cursor.toAlbum()) }
    }
    val deleted = db.rawQuery("SELECT id FROM album_tombstones WHERE seq > ? AND seq <= ?", range).use { cursor ->
      buildList { while (cursor.moveToNext()) add(cursor.getString(0)) }
    }
    val added = db.rawQuery(
      "SELECT l.album_id, l.asset_id FROM album_assets l JOIN assets s ON s.id = l.asset_id WHERE l.seq > ? AND l.seq <= ?",
      range,
    ).use { cursor -> buildList { while (cursor.moveToNext()) add(AlbumLink(cursor.getString(0), cursor.getString(1))) } }
    val removed = db.rawQuery("SELECT album_id, asset_id FROM album_asset_tombstones WHERE seq > ? AND seq <= ?", range)
      .use { cursor -> buildList { while (cursor.moveToNext()) add(AlbumLink(cursor.getString(0), cursor.getString(1))) } }
    return IndexAlbumChanges(albums, deleted, added, removed, maxOf(sinceSeq, untilSeq))
  }

  private fun linkAssets(db: SQLiteDatabase, seqs: SeqAllocator, albumId: String, assetIds: List<String>, now: Long): List<String> {
    val added = mutableListOf<String>()
    for (assetId in assetIds.distinct()) {
      if (!exists(db, "SELECT 1 FROM assets WHERE id = ?", assetId) || isLinked(db, albumId, assetId)) continue
      db.insertOrThrow("album_assets", null, ContentValues().apply {
        put("album_id", albumId)
        put("asset_id", assetId)
        put("added_at", now)
        put("seq", seqs.next())
      })
      db.delete("album_asset_tombstones", "album_id = ? AND asset_id = ?", arrayOf(albumId, assetId))
      added += assetId
    }
    if (added.isNotEmpty()) {
      // Like the Immich server, an album without a cover takes the first asset added to it.
      db.execSQL(
        "UPDATE albums SET thumbnail_asset_id = COALESCE(thumbnail_asset_id, ?) WHERE id = ?",
        arrayOf(added.first(), albumId),
      )
      touchAlbum(db, seqs, albumId)
    }
    return added
  }

  private fun isLinked(db: SQLiteDatabase, albumId: String, assetId: String) =
    exists(db, "SELECT 1 FROM album_assets WHERE album_id = ? AND asset_id = ?", albumId, assetId)

  private fun tombstoneLink(db: SQLiteDatabase, seqs: SeqAllocator, albumId: String, assetId: String) {
    db.insertWithOnConflict("album_asset_tombstones", null, ContentValues().apply {
      put("album_id", albumId)
      put("asset_id", assetId)
      put("seq", seqs.next())
    }, SQLiteDatabase.CONFLICT_REPLACE)
  }

  /** Keeps the cover pointing at an asset that is still in the album (the most recently added one). */
  private fun refreshCover(db: SQLiteDatabase, albumId: String) {
    db.execSQL(
      """
      UPDATE albums SET thumbnail_asset_id =
        (SELECT asset_id FROM album_assets WHERE album_id = ? ORDER BY added_at DESC, rowid DESC LIMIT 1)
      WHERE id = ? AND (thumbnail_asset_id IS NULL OR thumbnail_asset_id NOT IN (SELECT asset_id FROM album_assets WHERE album_id = ?))
      """.trimIndent(),
      arrayOf(albumId, albumId, albumId),
    )
  }

  private fun touchAlbum(db: SQLiteDatabase, seqs: SeqAllocator, albumId: String) {
    db.execSQL(
      "UPDATE albums SET updated_at = ?, seq = ? WHERE id = ?",
      arrayOf<Any>(System.currentTimeMillis(), seqs.next(), albumId),
    )
  }

  private fun exists(db: SQLiteDatabase, sql: String, vararg args: String): Boolean =
    db.rawQuery(sql, args).use { it.moveToFirst() }

  // ---------------------------------------------------------------------------------------------------------

  /** Hands out the sequence numbers of one write transaction. */
  private class SeqAllocator(var current: Long) {
    fun next(): Long = ++current

    fun advanceTo(value: Long) {
      if (value > current) current = value
    }
  }

  @Synchronized
  private fun <T> write(block: (SQLiteDatabase, SeqAllocator) -> T): T {
    val db = writableDatabase
    db.beginTransaction()
    try {
      val seqs = SeqAllocator(readSeq(db))
      val result = block(db, seqs)
      db.execSQL("UPDATE meta SET value = ? WHERE key = 'seq'", arrayOf(seqs.current.toString()))
      db.setTransactionSuccessful()
      return result
    } finally {
      db.endTransaction()
    }
  }

  private fun readSeq(db: SQLiteDatabase): Long = db.rawQuery("SELECT value FROM meta WHERE key = 'seq'", null).use {
    it.moveToFirst()
    it.getString(0).toLong()
  }

  private fun IndexRecord.toValues(seq: Long) = ContentValues().apply {
    put("id", id)
    put("checksum", checksum)
    put("local_id", localId)
    put("name", name)
    put("mime_type", mimeType)
    put("type", type)
    put("created_at", createdAtMs)
    put("modified_at", modifiedAtMs)
    put("width", width)
    put("height", height)
    put("duration_ms", durationMs)
    put("size_bytes", sizeBytes)
    put("latitude", latitude)
    put("longitude", longitude)
    put("make", make)
    put("model", model)
    put("orientation", orientation)
    put("is_favorite", if (isFavorite) 1 else 0)
    put("visibility", visibility)
    put("deleted_at", deletedAtMs)
    put("uploaded_at", uploadedAtMs)
    put("chat_id", chatId)
    put("message_id", messageId)
    put("file_id", fileId)
    put("file_unique_id", fileUniqueId)
    put("encrypted_size", encryptedSize)
    put("wrapped_dek", wrappedDek)
    put("has_thumbnail", if (hasThumbnail) 1 else 0)
    put("description", description)
    put("rating", rating)
    put("format", format)
    put("part_count", partCount)
    put("part_bytes", partBytes)
    put("seq", seq)
  }

  private fun Cursor.firstRecord(): IndexRecord? = if (moveToFirst()) toRecord() else null

  private fun Cursor.toRecord(): IndexRecord = IndexRecord(
    id = string("id")!!,
    checksum = string("checksum")!!,
    localId = string("local_id"),
    name = string("name")!!,
    mimeType = string("mime_type")!!,
    type = int("type")!!,
    createdAtMs = long("created_at")!!,
    modifiedAtMs = long("modified_at")!!,
    width = int("width"),
    height = int("height"),
    durationMs = long("duration_ms"),
    sizeBytes = long("size_bytes")!!,
    latitude = double("latitude"),
    longitude = double("longitude"),
    make = string("make"),
    model = string("model"),
    orientation = int("orientation"),
    isFavorite = int("is_favorite") == 1,
    visibility = int("visibility")!!,
    deletedAtMs = long("deleted_at"),
    uploadedAtMs = long("uploaded_at")!!,
    chatId = long("chat_id")!!,
    messageId = long("message_id")!!,
    fileId = int("file_id")!!,
    fileUniqueId = string("file_unique_id")!!,
    encryptedSize = long("encrypted_size")!!,
    wrappedDek = getBlob(getColumnIndexOrThrow("wrapped_dek")),
    hasThumbnail = int("has_thumbnail") == 1,
    description = string("description"),
    rating = int("rating"),
    format = int("format") ?: FORMAT_ENCRYPTED,
    seq = long("seq")!!,
    partCount = int("part_count") ?: 1,
    partBytes = long("part_bytes") ?: 0,
  )

  private fun Cursor.toAlbum(): AlbumRecord = AlbumRecord(
    id = string("id")!!,
    name = string("name")!!,
    description = string("description"),
    thumbnailAssetId = string("thumbnail_asset_id"),
    order = int("sort_order") ?: ORDER_DESC,
    createdAtMs = long("created_at")!!,
    updatedAtMs = long("updated_at")!!,
    assetCount = long("asset_count") ?: 0,
    seq = long("seq")!!,
  )

  private fun Cursor.string(column: String): String? = getColumnIndexOrThrow(column).let { if (isNull(it)) null else getString(it) }

  private fun Cursor.int(column: String): Int? = getColumnIndexOrThrow(column).let { if (isNull(it)) null else getInt(it) }

  private fun Cursor.long(column: String): Long? = getColumnIndexOrThrow(column).let { if (isNull(it)) null else getLong(it) }

  private fun Cursor.double(column: String): Double? = getColumnIndexOrThrow(column).let { if (isNull(it)) null else getDouble(it) }

  companion object {
    const val SCHEMA_VERSION = 4
    const val TYPE_IMAGE = 1
    const val TYPE_VIDEO = 2
    const val FORMAT_PLAIN = 0
    const val FORMAT_ENCRYPTED = 1
    const val ORDER_DESC = 0
    const val ORDER_ASC = 1

    private const val ALBUM_SELECT =
      "SELECT a.*, (SELECT COUNT(*) FROM album_assets l JOIN assets s ON s.id = l.asset_id WHERE l.album_id = a.id) " +
        "AS asset_count FROM albums a"
  }
}
