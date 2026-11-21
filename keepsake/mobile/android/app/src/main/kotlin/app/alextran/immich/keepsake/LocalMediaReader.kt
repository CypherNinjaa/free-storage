package app.alextran.immich.keepsake

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.media.MediaDataSource
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

data class LocalMediaInfo(
  val localId: String,
  val uri: Uri,
  val name: String,
  val mimeType: String,
  val isVideo: Boolean,
  val sizeBytes: Long,
  val dateTakenMs: Long?,
  val modifiedMs: Long?,
  val width: Int?,
  val height: Int?,
  val durationMs: Long?,
)

data class MediaDetails(
  val latitude: Double? = null,
  val longitude: Double? = null,
  val make: String? = null,
  val model: String? = null,
  val orientation: Int? = null,
  val width: Int? = null,
  val height: Int? = null,
  val durationMs: Long? = null,
)

class LocalMediaReader(private val context: Context) {
  private val resolver get() = context.contentResolver

  fun info(localId: String): LocalMediaInfo {
    val id = localId.toLong()
    val projection = arrayOf(
      MediaStore.Files.FileColumns.MEDIA_TYPE,
      MediaStore.MediaColumns.DISPLAY_NAME,
      MediaStore.MediaColumns.MIME_TYPE,
      MediaStore.MediaColumns.SIZE,
      MediaStore.MediaColumns.DATE_MODIFIED,
      MediaStore.MediaColumns.WIDTH,
      MediaStore.MediaColumns.HEIGHT,
      MediaStore.Images.ImageColumns.DATE_TAKEN,
      MediaStore.Video.VideoColumns.DURATION,
    )
    val filesUri = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
    resolver.query(filesUri, projection, "${MediaStore.MediaColumns._ID} = ?", arrayOf(localId), null)?.use { cursor ->
      if (!cursor.moveToFirst()) throw IOException("Asset $localId is no longer on this device")
      fun long(column: String) = cursor.getColumnIndex(column).takeIf { it >= 0 && !cursor.isNull(it) }?.let(cursor::getLong)
      fun int(column: String) = cursor.getColumnIndex(column).takeIf { it >= 0 && !cursor.isNull(it) }?.let(cursor::getInt)
      fun string(column: String) = cursor.getColumnIndex(column).takeIf { it >= 0 && !cursor.isNull(it) }?.let(cursor::getString)
      val isVideo = int(MediaStore.Files.FileColumns.MEDIA_TYPE) == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
      val collection = if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
      return LocalMediaInfo(
        localId = localId,
        uri = ContentUris.withAppendedId(collection, id),
        name = string(MediaStore.MediaColumns.DISPLAY_NAME) ?: "$localId",
        mimeType = string(MediaStore.MediaColumns.MIME_TYPE) ?: if (isVideo) "video/mp4" else "image/jpeg",
        isVideo = isVideo,
        sizeBytes = long(MediaStore.MediaColumns.SIZE) ?: 0L,
        dateTakenMs = long(MediaStore.Images.ImageColumns.DATE_TAKEN)?.takeIf { it > 0 },
        modifiedMs = long(MediaStore.MediaColumns.DATE_MODIFIED)?.times(1000),
        width = int(MediaStore.MediaColumns.WIDTH)?.takeIf { it > 0 },
        height = int(MediaStore.MediaColumns.HEIGHT)?.takeIf { it > 0 },
        durationMs = long(MediaStore.Video.VideoColumns.DURATION)?.takeIf { it > 0 },
      )
    }
    throw IOException("MediaStore query failed for asset $localId")
  }

  fun openOriginal(info: LocalMediaInfo): InputStream {
    val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) MediaStore.setRequireOriginal(info.uri) else info.uri
    return resolver.openInputStream(uri) ?: throw IOException("Cannot open original stream for asset ${info.localId}")
  }

  fun originalSize(info: LocalMediaInfo): Long {
    val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) MediaStore.setRequireOriginal(info.uri) else info.uri
    val statSize = runCatching { resolver.openFileDescriptor(uri, "r")?.use { it.statSize } }.getOrNull()
    return statSize?.takeIf { it >= 0 } ?: info.sizeBytes
  }

  fun details(info: LocalMediaInfo): MediaDetails = runCatching {
    if (info.isVideo) videoDetails(info) else imageDetails(info)
  }.getOrDefault(MediaDetails())

  fun renderPreviews(info: LocalMediaInfo, details: MediaDetails): RenderedPreviews? = runCatching {
    val bitmap = if (info.isVideo) {
      MediaMetadataRetriever().useRetriever { retriever ->
        retriever.setDataSource(context, info.uri)
        retriever.frameAt(0)
      }
    } else {
      decodeSampled(PREVIEW_LONG_SIDE) { openOriginal(info) }?.let { rotate(it, details.orientation) }
    } ?: return null
    render(bitmap)
  }.getOrNull()

  private fun imageDetails(info: LocalMediaInfo): MediaDetails = openOriginal(info).use { stream ->
    val exif = ExifInterface(stream)
    val latLong = FloatArray(2)
    val hasLocation = exif.getLatLong(latLong)
    MediaDetails(
      latitude = if (hasLocation && !isNullIsland(latLong[0].toDouble(), latLong[1].toDouble())) latLong[0].toDouble() else null,
      longitude = if (hasLocation && !isNullIsland(latLong[0].toDouble(), latLong[1].toDouble())) latLong[1].toDouble() else null,
      make = exif.getAttribute(ExifInterface.TAG_MAKE)?.trim()?.ifBlank { null },
      model = exif.getAttribute(ExifInterface.TAG_MODEL)?.trim()?.ifBlank { null },
      orientation = exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL),
      width = exif.getAttributeInt(ExifInterface.TAG_IMAGE_WIDTH, 0).takeIf { it > 0 },
      height = exif.getAttributeInt(ExifInterface.TAG_IMAGE_LENGTH, 0).takeIf { it > 0 },
    )
  }

  private fun videoDetails(info: LocalMediaInfo): MediaDetails = MediaMetadataRetriever().useRetriever { retriever ->
    retriever.setDataSource(context, info.uri)
    val location = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_LOCATION)?.let(::parseIso6709)
    val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
    val rawWidth = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
    val rawHeight = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
    val swap = rotation == 90 || rotation == 270
    MediaDetails(
      latitude = location?.first,
      longitude = location?.second,
      width = if (swap) rawHeight else rawWidth,
      height = if (swap) rawWidth else rawHeight,
      durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull(),
    )
  }

  companion object {
    const val THUMBNAIL_SHORT_SIDE = 320
    const val PREVIEW_LONG_SIDE = 1440

    fun renderFromFile(file: File, isVideo: Boolean): RenderedPreviews? = runCatching {
      val bitmap = if (isVideo) {
        MediaMetadataRetriever().useRetriever { retriever ->
          retriever.setDataSource(file.absolutePath)
          retriever.frameAt(0)
        }
      } else {
        val orientation = runCatching {
          ExifInterface(file.absolutePath).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        }.getOrNull()
        decodeSampled(PREVIEW_LONG_SIDE) { file.inputStream() }?.let { rotate(it, orientation) }
      } ?: return null
      render(bitmap)
    }.getOrNull()

    fun renderFromVideoSource(source: MediaDataSource): RenderedPreviews? = runCatching {
      val bitmap = MediaMetadataRetriever().useRetriever { retriever ->
        retriever.setDataSource(source)
        retriever.frameAt(0)
      } ?: return null
      render(bitmap)
    }.getOrNull()

    private fun MediaMetadataRetriever.frameAt(timeUs: Long): Bitmap? =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
        getScaledFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, PREVIEW_LONG_SIDE, PREVIEW_LONG_SIDE)
      } else {
        getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
      }

    private inline fun <T> MediaMetadataRetriever.useRetriever(block: (MediaMetadataRetriever) -> T): T =
      try {
        block(this)
      } finally {
        release()
      }

    private fun decodeSampled(maxLongSide: Int, open: () -> InputStream): Bitmap? {
      val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
      open().use { BitmapFactory.decodeStream(it, null, bounds) }
      if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
      var sample = 1
      while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxLongSide) sample *= 2
      val options = BitmapFactory.Options().apply { inSampleSize = sample }
      return open().use { BitmapFactory.decodeStream(it, null, options) }
    }

    private fun rotate(bitmap: Bitmap, orientation: Int?): Bitmap {
      val matrix = Matrix()
      when (orientation) {
        ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
        ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
        ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
        ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
        ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
        ExifInterface.ORIENTATION_TRANSPOSE -> {
          matrix.postRotate(90f)
          matrix.preScale(-1f, 1f)
        }
        ExifInterface.ORIENTATION_TRANSVERSE -> {
          matrix.postRotate(270f)
          matrix.preScale(-1f, 1f)
        }
        else -> return bitmap
      }
      return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true).also {
        if (it != bitmap) bitmap.recycle()
      }
    }

    private fun render(source: Bitmap): RenderedPreviews {
      val preview = scale(source, PREVIEW_LONG_SIDE.toFloat() / max(source.width, source.height))
      val thumbnail = scale(preview, THUMBNAIL_SHORT_SIDE.toFloat() / min(preview.width, preview.height))
      val result = RenderedPreviews(thumbnail.toJpeg(80), preview.toJpeg(82))
      if (thumbnail != preview) thumbnail.recycle()
      if (preview != source) preview.recycle()
      source.recycle()
      return result
    }

    private fun scale(bitmap: Bitmap, factor: Float): Bitmap {
      if (factor >= 1f) return bitmap
      val width = max(1, (bitmap.width * factor).roundToInt())
      val height = max(1, (bitmap.height * factor).roundToInt())
      return Bitmap.createScaledBitmap(bitmap, width, height, true)
    }

    private fun Bitmap.toJpeg(quality: Int): ByteArray =
      ByteArrayOutputStream().also { compress(Bitmap.CompressFormat.JPEG, quality, it) }.toByteArray()

    /**
     * Scales a rendered preview to the thumbnail Telegram apps show next to a file: JPEG, at most 320x320 px
     * and under 200 kB. Returns the bytes with their width and height.
     */
    fun telegramThumbnail(jpeg: ByteArray): Triple<ByteArray, Int, Int>? = runCatching {
      val source = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size) ?: return null
      val fitted = scale(source, TELEGRAM_THUMBNAIL_SIDE.toFloat() / max(source.width, source.height))
      var quality = 85
      var bytes = fitted.toJpeg(quality)
      while (bytes.size > TELEGRAM_THUMBNAIL_BYTES && quality > 40) {
        quality -= 15
        bytes = fitted.toJpeg(quality)
      }
      val result = Triple(bytes, fitted.width, fitted.height)
      if (fitted != source) fitted.recycle()
      source.recycle()
      result.takeIf { bytes.size <= TELEGRAM_THUMBNAIL_BYTES }
    }.getOrNull()

    private const val TELEGRAM_THUMBNAIL_SIDE = 320
    private const val TELEGRAM_THUMBNAIL_BYTES = 200 * 1024

    fun isNullIsland(latitude: Double, longitude: Double) = latitude == 0.0 && longitude == 0.0

    private fun parseIso6709(value: String): Pair<Double, Double>? {
      val match = Regex("([+-]\\d+(?:\\.\\d+)?)([+-]\\d+(?:\\.\\d+)?)").find(value) ?: return null
      val latitude = match.groupValues[1].toDoubleOrNull() ?: return null
      val longitude = match.groupValues[2].toDoubleOrNull() ?: return null
      // Cameras write +00.0000+000.0000 when they had no GPS fix; like Immich, treat it as "no location".
      return if (isNullIsland(latitude, longitude)) null else latitude to longitude
    }
  }
}

class RenderedPreviews(val thumbnail: ByteArray, val preview: ByteArray)
