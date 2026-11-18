package com.toposurvey.toposurvey

import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val createDocumentRequestCode = 7416
    private var pendingDocumentResult: MethodChannel.Result? = null
    private var pendingDocumentContent: ByteArray? = null
    private var pendingDocumentName: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.toposurvey.toposurvey/geojson",
        ).setMethodCallHandler { call, result ->
            val fileName = call.argument<String>("fileName") ?: "toposurvey_export.geojson"
            val content = call.argument<String>("content")
            if (content == null) {
                result.error("INVALID_ARGS", "Data GeoJSON tidak boleh kosong.", null)
                return@setMethodCallHandler
            }

            when (call.method) {
                "saveGeoJson" -> {
                    ioExecutor.execute {
                        try {
                            val (savedPath, _) = writeGeoJsonToDownloads(fileName, content)
                            runOnUiThread { result.success(savedPath) }
                        } catch (error: Exception) {
                            runOnUiThread {
                                result.error(
                                    "EXPORT_FAILED",
                                    error.message ?: "Gagal menyimpan file GeoJSON.",
                                    null,
                                )
                            }
                        }
                    }
                }
                "shareGeoJson" -> {
                    ioExecutor.execute {
                        try {
                            val (_, contentUri) = writeGeoJsonToDownloads(fileName, content)
                            runOnUiThread {
                                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                    type = "application/json"
                                    putExtra(Intent.EXTRA_SUBJECT, fileName)
                                    putExtra(Intent.EXTRA_TEXT, content)
                                    if (contentUri != null) {
                                        putExtra(Intent.EXTRA_STREAM, contentUri)
                                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        clipData = ClipData.newRawUri(fileName, contentUri)
                                    }
                                }
                                startActivity(
                                    Intent.createChooser(shareIntent, "Bagikan GeoJSON"),
                                )
                                result.success(null)
                            }
                        } catch (error: Exception) {
                            runOnUiThread {
                                result.error(
                                    "SHARE_FAILED",
                                    error.message ?: "Gagal membagikan file GeoJSON.",
                                    null,
                                )
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.toposurvey.toposurvey/export",
        ).setMethodCallHandler { call, result ->
            if (call.method != "createDocument") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (pendingDocumentResult != null) {
                result.error("EXPORT_BUSY", "Pilih lokasi untuk ekspor yang sedang berlangsung.", null)
                return@setMethodCallHandler
            }
            val fileName = call.argument<String>("fileName")
            val mimeType = call.argument<String>("mimeType")
            val content = call.argument<Any>("content")
            val bytes = when (content) {
                is ByteArray -> content
                is String -> content.toByteArray(StandardCharsets.UTF_8)
                else -> null
            }
            if (fileName.isNullOrBlank() || mimeType.isNullOrBlank() || bytes == null) {
                result.error("INVALID_ARGS", "Nama, format, dan konten file harus tersedia.", null)
                return@setMethodCallHandler
            }
            pendingDocumentResult = result
            pendingDocumentContent = bytes
            pendingDocumentName = fileName
            try {
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = mimeType
                    putExtra(Intent.EXTRA_TITLE, fileName)
                }
                startActivityForResult(intent, createDocumentRequestCode)
            } catch (error: Exception) {
                pendingDocumentResult = null
                pendingDocumentContent = null
                pendingDocumentName = null
                result.error("PICKER_FAILED", error.message ?: "Pemilih file tidak dapat dibuka.", null)
            }
        }
    }

    @Deprecated("Deprecated in Android, retained for FlutterActivity result compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != createDocumentRequestCode) return

        val result = pendingDocumentResult ?: return
        val bytes = pendingDocumentContent
        val fileName = pendingDocumentName ?: "toposurvey_export"
        pendingDocumentResult = null
        pendingDocumentContent = null
        pendingDocumentName = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null || bytes == null) {
            result.success(null)
            return
        }

        ioExecutor.execute {
            try {
                contentResolver.openOutputStream(uri, "w")?.use { stream ->
                    stream.write(bytes)
                } ?: throw IOException("Tidak dapat menulis file yang dipilih.")
                runOnUiThread { result.success(fileName) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "EXPORT_FAILED",
                        error.message ?: "Gagal menyimpan file ekspor.",
                        null,
                    )
                }
            }
        }
    }

    private fun writeGeoJsonToDownloads(
        fileName: String,
        content: String,
    ): Pair<String, Uri?> {
        val bytes = content.toByteArray(StandardCharsets.UTF_8)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("Tidak dapat membuat file di folder Download.")
            try {
                resolver.openOutputStream(uri)?.use { stream ->
                    stream.write(bytes)
                } ?: throw IOException("Tidak dapat menulis ke folder Download.")
                val completed = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                resolver.update(uri, completed, null, null)
                val actualName = resolveDisplayName(uri) ?: fileName
                return Pair("${Environment.DIRECTORY_DOWNLOADS}/$actualName", uri)
            } catch (error: Exception) {
                resolver.delete(uri, null, null)
                throw error
            }
        }

        val downloadsDir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: filesDir
        if (!downloadsDir.exists()) {
            downloadsDir.mkdirs()
        }
        val targetFile = File(downloadsDir, fileName)
        targetFile.writeBytes(bytes)
        return Pair(targetFile.absolutePath, null)
    }

    private fun resolveDisplayName(uri: Uri): String? {
        return applicationContext.contentResolver.query(
            uri,
            arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }

    override fun onDestroy() {
        ioExecutor.shutdown()
        super.onDestroy()
    }
}
