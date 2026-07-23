package com.songs.fantextviewer

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.charset.Charset
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val fileExecutor = Executors.newSingleThreadExecutor()
    private val importer = TextFileImporter(MAX_IMPORTED_TEXT_BYTES)
    private var pendingImportResult: MethodChannel.Result? = null
    private var pendingExport: PendingExport? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.songs.fantextviewer/text-file",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "decode" -> decodeTextFile(call.arguments as? Map<*, *>, result)
                "importTextFile" -> openTextDocument(result)
                "exportRecoveryFile" -> {
                    val path = call.argument<String>("path")
                    val suggestedName = call.argument<String>("suggestedName")
                    if (path == null || suggestedName == null) {
                        result.error(
                            "invalid_argument",
                            "path and suggestedName are required",
                            null,
                        )
                    } else {
                        createRecoveryDocument(path, suggestedName, result)
                    }
                }
                "promoteLegacyImport" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("invalid_argument", "path is required", null)
                    } else {
                        promoteLegacyImport(path, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun decodeTextFile(
        arguments: Map<*, *>?,
        result: MethodChannel.Result,
    ) {
        val path = arguments?.get("path") as? String
        val encoding = arguments?.get("encoding") as? String
        if (path == null || encoding == null) {
            result.error("invalid_argument", "path and encoding are required", null)
            return
        }
        fileExecutor.execute {
            try {
                val file = File(path)
                if (file.length() > MAX_CP949_DECODE_BYTES) {
                    throw TextFileTooLargeException(MAX_CP949_DECODE_BYTES)
                }
                val text =
                    file.bufferedReader(Charset.forName(encoding)).use { it.readText() }
                runOnUiThread { result.success(text) }
            } catch (error: Throwable) {
                runOnUiThread {
                    val code =
                        if (error is TextFileTooLargeException) {
                            "file_too_large"
                        } else {
                            "decode_failed"
                        }
                    result.error(code, error.message, error.toString())
                }
            }
        }
    }

    private fun openTextDocument(result: MethodChannel.Result) {
        if (documentActionActive()) {
            result.error("picker_active", "A text file picker is already open", null)
            return
        }
        pendingImportResult = result
        val intent =
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "text/plain"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        try {
            startActivityForResult(intent, IMPORT_TEXT_REQUEST_CODE)
        } catch (error: Throwable) {
            pendingImportResult = null
            result.error("picker_failed", error.message, error.toString())
        }
    }

    private fun createRecoveryDocument(
        path: String,
        suggestedName: String,
        result: MethodChannel.Result,
    ) {
        if (documentActionActive()) {
            result.error("picker_active", "A document picker is already open", null)
            return
        }
        val source =
            try {
                File(path).canonicalFile
            } catch (error: Throwable) {
                result.error("invalid_path", error.message, error.toString())
                return
            }
        val filesRoot = filesDir.canonicalFile
        val insideFiles =
            source.path == filesRoot.path ||
                source.path.startsWith(filesRoot.path + File.separator)
        if (!insideFiles || !source.isFile) {
            result.error(
                "invalid_path",
                "Recovery files must be inside the application files directory",
                null,
            )
            return
        }
        pendingExport = PendingExport(result, source)
        val intent =
            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
                putExtra(Intent.EXTRA_TITLE, suggestedName)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
        try {
            startActivityForResult(intent, EXPORT_RECOVERY_REQUEST_CODE)
        } catch (error: Throwable) {
            pendingExport = null
            result.error("picker_failed", error.message, error.toString())
        }
    }

    private fun documentActionActive(): Boolean =
        pendingImportResult != null || pendingExport != null

    @Deprecated("Deprecated by Android; retained for FlutterActivity compatibility")
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == EXPORT_RECOVERY_REQUEST_CODE) {
            val pending = pendingExport ?: return
            pendingExport = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                pending.result.success(false)
                return
            }
            exportRecoveryFile(pending, uri)
            return
        }
        if (requestCode != IMPORT_TEXT_REQUEST_CODE) return
        val result = pendingImportResult ?: return
        pendingImportResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        importUri(uri, result)
    }

    private fun exportRecoveryFile(
        pending: PendingExport,
        uri: Uri,
    ) {
        fileExecutor.execute {
            try {
                val output =
                    contentResolver.openOutputStream(uri, "w")
                        ?: error("The selected destination could not be opened")
                pending.source.inputStream().buffered().use { input ->
                    output.buffered().use { destination ->
                        input.copyTo(destination)
                        destination.flush()
                    }
                }
                runOnUiThread { pending.result.success(true) }
            } catch (error: Throwable) {
                runOnUiThread {
                    pending.result.error(
                        "export_failed",
                        error.message,
                        error.toString(),
                    )
                }
            }
        }
    }

    private fun importUri(
        uri: Uri,
        result: MethodChannel.Result,
    ) {
        val metadata = documentMetadata(uri)
        if (metadata.size != null && metadata.size > MAX_IMPORTED_TEXT_BYTES) {
            result.error(
                "file_too_large",
                "Text file exceeds the $MAX_IMPORTED_TEXT_BYTES byte import limit",
                null,
            )
            return
        }
        fileExecutor.execute {
            try {
                val input =
                    contentResolver.openInputStream(uri)
                        ?: error("The selected document could not be opened")
                val target =
                    importer.copy(
                        input,
                        File(filesDir, IMPORTED_TEXT_DIRECTORY),
                        sha256(uri.toString()),
                        metadata.name,
                    )
                runOnUiThread { result.success(target.path) }
            } catch (error: Throwable) {
                runOnUiThread {
                    val code =
                        if (error is TextFileTooLargeException) {
                            "file_too_large"
                        } else {
                            "import_failed"
                        }
                    result.error(code, error.message, error.toString())
                }
            }
        }
    }

    private fun promoteLegacyImport(
        path: String,
        result: MethodChannel.Result,
    ) {
        fileExecutor.execute {
            try {
                val source = File(path).canonicalFile
                val cacheRoot = cacheDir.canonicalFile
                val insideCache =
                    source.path == cacheRoot.path ||
                        source.path.startsWith(cacheRoot.path + File.separator)
                if (!insideCache || !source.isFile) {
                    runOnUiThread { result.success(null) }
                    return@execute
                }
                if (source.length() > MAX_IMPORTED_TEXT_BYTES) {
                    throw TextFileTooLargeException(MAX_IMPORTED_TEXT_BYTES)
                }
                val target =
                    importer.copy(
                        source.inputStream(),
                        File(filesDir, IMPORTED_TEXT_DIRECTORY),
                        "legacy-${sha256(source.path)}",
                        source.name,
                    )
                runOnUiThread { result.success(target.path) }
            } catch (error: Throwable) {
                runOnUiThread {
                    val code =
                        if (error is TextFileTooLargeException) {
                            "file_too_large"
                        } else {
                            "promotion_failed"
                        }
                    result.error(code, error.message, error.toString())
                }
            }
        }
    }

    private fun documentMetadata(uri: Uri): DocumentMetadata {
        var name = "imported.txt"
        var size: Long? = null
        val cursor: Cursor? =
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null,
            )
        cursor?.use {
            if (it.moveToFirst()) {
                val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = it.getColumnIndex(OpenableColumns.SIZE)
                if (nameIndex >= 0 && !it.isNull(nameIndex)) name = it.getString(nameIndex)
                if (sizeIndex >= 0 && !it.isNull(sizeIndex)) size = it.getLong(sizeIndex)
            }
        }
        return DocumentMetadata(name, size)
    }

    private fun sha256(value: String): String =
        MessageDigest
            .getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte) }

    override fun onResume() {
        super.onResume()
        val display = window.decorView.display ?: return
        val currentMode = display.mode
        val maximumRefreshRate = display.supportedModes
            .asSequence()
            .filter {
                it.physicalWidth == currentMode.physicalWidth &&
                    it.physicalHeight == currentMode.physicalHeight
            }
            .maxOfOrNull { it.refreshRate }
            ?: return
        window.attributes = window.attributes.apply {
            preferredRefreshRate = maximumRefreshRate
        }
    }

    override fun onDestroy() {
        pendingImportResult = null
        pendingExport = null
        fileExecutor.shutdown()
        super.onDestroy()
    }

    private data class DocumentMetadata(
        val name: String,
        val size: Long?,
    )

    private data class PendingExport(
        val result: MethodChannel.Result,
        val source: File,
    )

    companion object {
        private const val IMPORT_TEXT_REQUEST_CODE = 7314
        private const val EXPORT_RECOVERY_REQUEST_CODE = 7315
        private const val IMPORTED_TEXT_DIRECTORY = "imported_texts"
        private const val MAX_IMPORTED_TEXT_BYTES = 64L * 1024L * 1024L
        private const val MAX_CP949_DECODE_BYTES = 32L * 1024L * 1024L
    }
}
