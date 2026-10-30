package app.biload.biload

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException

class AndroidOutputStorage(private val activity: Activity) {
    companion object {
        const val DEFAULT_DIRECTORY = "android-downloads://biload"
        const val PICK_DIRECTORY = 3102
        const val WRITE_PERMISSION = 3103
    }
    private val resolver get() = activity.contentResolver
    private var directoryResult: MethodChannel.Result? = null
    private var permissionResult: MethodChannel.Result? = null

    private fun background(result: MethodChannel.Result, action: () -> Any?) {
        Thread {
            try {
                val value = action()
                activity.runOnUiThread { result.success(value) }
            } catch (_: SecurityException) {
                activity.runOnUiThread { result.error("STORAGE_PERMISSION", "目录授权已失效，请在设置中重新选择下载目录。", null) }
            } catch (error: Exception) {
                activity.runOnUiThread { result.error("STORAGE", error.message ?: "保存文件失败，请检查目录权限和剩余空间。", null) }
            }
        }.start()
    }

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "storageChooseDirectory" -> {
                if (directoryResult != null) {
                    result.error("BUSY", "请先完成当前目录选择。", null)
                } else {
                    directoryResult = result
                    try {
                        activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                            .putExtra(DocumentsContract.EXTRA_INITIAL_URI, DocumentsContract.buildDocumentUri(
                                "com.android.externalstorage.documents", "primary:Download/biload")), PICK_DIRECTORY)
                    } catch (_: Exception) {
                        directoryResult = null
                        result.error("STORAGE", "无法打开系统目录选择器。", null)
                    }
                }
            }
            "storagePrepare" -> {
                val directory = call.argument<String>("directory") ?: ""
                if (directory == DEFAULT_DIRECTORY && Build.VERSION.SDK_INT <= 28 &&
                    activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                    if (permissionResult != null) result.error("BUSY", "请先完成存储授权。", null)
                    else {
                        permissionResult = result
                        activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), WRITE_PERMISSION)
                    }
                } else background(result) { prepare(directory); null }
            }
            "storagePublish" -> background(result) {
                val source = privateFile(call.argument<String>("source") ?: "")
                require(source.isFile) { "待保存的文件不存在。" }
                val name = call.argument<String>("name") ?: ""
                require(name.isNotBlank() && name != "." && name != ".." && !name.contains('/') && !name.contains('\\')) { "输出文件名无效。" }
                val directory = call.argument<String>("directory") ?: ""
                prepare(directory)
                when {
                    directory != DEFAULT_DIRECTORY -> publishTree(source, Uri.parse(directory), name).toString()
                    Build.VERSION.SDK_INT >= 29 -> publishDownloads(source, name).toString()
                    else -> publishLegacy(source, name)
                }
            }
            "storageExists" -> background(result) {
                val output = call.argument<String>("output") ?: ""
                if (output.isEmpty()) false else if (output.startsWith("content://")) {
                    try { resolver.openFileDescriptor(outputUri(output), "r")?.use { true } ?: false }
                    catch (_: FileNotFoundException) { false }
                } else readableFile(output).isFile
            }
            "storageDelete" -> background(result) {
                val output = call.argument<String>("output") ?: ""
                if (output.startsWith("content://")) {
                    val uri = outputUri(output)
                    if (uri.authority == MediaStore.AUTHORITY) resolver.delete(uri, null, null)
                    else DocumentsContract.deleteDocument(resolver, uri)
                } else {
                    val file = readableFile(output)
                    if (file.exists() && !file.delete()) throw IOException("文件删除失败。")
                }
                null
            }
            "storageOpen" -> {
                try {
                    val output = call.argument<String>("output") ?: ""
                    val uri = if (output.startsWith("content://")) outputUri(output) else {
                        val file = readableFile(output)
                        require(file.isFile) { "文件已被移动或删除。" }
                        FileProvider.getUriForFile(activity, "${activity.packageName}.files", file)
                    }
                    activity.startActivity(Intent(Intent.ACTION_VIEW)
                        .setDataAndType(uri, resolver.getType(uri) ?: mime(output))
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                    result.success(null)
                } catch (_: android.content.ActivityNotFoundException) {
                    result.error("OPEN", "没有可用的播放器。", null)
                } catch (_: Exception) { result.error("OPEN", "文件不可访问，请检查文件是否已删除或目录授权是否有效。", null) }
            }
            else -> return false
        }
        return true
    }

    private fun prepare(directory: String) {
        if (directory == DEFAULT_DIRECTORY) {
            if (Build.VERSION.SDK_INT <= 28) {
                if (activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) throw SecurityException()
                check(legacyDirectory().isDirectory || legacyDirectory().mkdirs()) { "无法创建公共下载目录。" }
            }
        } else {
            val tree = checkedTree(Uri.parse(directory))
            val document = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            resolver.query(document, arrayOf(DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)?.use {
                check(it.moveToFirst() && it.getString(0) == DocumentsContract.Document.MIME_TYPE_DIR) { "下载目录已被移动或删除，请重新选择。" }
            } ?: throw IOException("无法访问下载目录。")
        }
    }

    private fun privateFile(path: String): File {
        val file = File(path).canonicalFile
        val roots = listOfNotNull(activity.filesDir, activity.cacheDir,
            activity.getExternalFilesDir(null), activity.externalCacheDir).map { it.canonicalFile }
        if (roots.none { file.path.startsWith(it.path + File.separator) }) throw SecurityException()
        return file
    }

    @Suppress("DEPRECATION")
    private fun legacyDirectory() = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "biload").canonicalFile

    private fun readableFile(path: String): File {
        val file = File(path).canonicalFile
        if (Build.VERSION.SDK_INT <= 28 && file.path.startsWith(legacyDirectory().path + File.separator)) return file
        return privateFile(path)
    }

    private fun checkedTree(uri: Uri): Uri {
        if (uri.scheme != "content" || !DocumentsContract.isTreeUri(uri)) throw SecurityException()
        val id = DocumentsContract.getTreeDocumentId(uri)
        val granted = resolver.persistedUriPermissions.any {
            it.isReadPermission && it.isWritePermission && it.uri.authority == uri.authority &&
                DocumentsContract.isTreeUri(it.uri) && DocumentsContract.getTreeDocumentId(it.uri) == id
        }
        if (!granted) throw SecurityException()
        return uri
    }

    private fun outputUri(value: String): Uri {
        val uri = Uri.parse(value)
        if (uri.scheme != "content") throw SecurityException()
        if (uri.authority == MediaStore.AUTHORITY && Build.VERSION.SDK_INT >= 29 && uri.pathSegments.getOrNull(1) == "downloads") {
            resolver.query(uri, arrayOf(MediaStore.MediaColumns.OWNER_PACKAGE_NAME), null, null, null)?.use {
                if (it.moveToFirst() && it.getString(0) != activity.packageName) throw SecurityException()
            }
        } else checkedTree(uri)
        return uri
    }

    private fun mime(name: String) = MimeTypeMap.getSingleton()
        .getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase()) ?: "application/octet-stream"

    private fun write(source: File, uri: Uri) {
        val length = resolver.openOutputStream(uri, "w").use { target ->
            requireNotNull(target) { "无法写入下载目录。" }
            source.inputStream().use { it.copyTo(target, 64 * 1024) }
        }
        check(length == source.length()) { "写入文件长度不一致，原文件已保留。" }
        resolver.openFileDescriptor(uri, "r")?.use {
            if (it.statSize >= 0) check(it.statSize == length) { "保存后的文件长度不一致，原文件已保留。" }
        }
    }

    @android.annotation.TargetApi(29)
    private fun publishDownloads(source: File, name: String): Uri {
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val relative = "${Environment.DIRECTORY_DOWNLOADS}/biload/"
        resolver.query(collection, arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.IS_PENDING, MediaStore.MediaColumns.OWNER_PACKAGE_NAME),
            "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?",
            arrayOf(name, relative), null)?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(3) != activity.packageName) continue
                val existing = ContentUris.withAppendedId(collection, cursor.getLong(0))
                if (cursor.getInt(2) == 0) {
                    check(cursor.getLong(1) == source.length()) { "下载目录中有同名文件，请先检查该文件。" }
                    return existing
                }
                resolver.delete(existing, null, null)
            }
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime(name))
            put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: throw IOException("无法创建下载文件。")
        try {
            write(source, uri)
            check(resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null) == 1)
            return uri
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    private fun findChild(tree: Uri, name: String): Pair<Uri, Long>? {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        resolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_SIZE), null, null, null)?.use {
            while (it.moveToNext()) if (it.getString(1) == name) {
                return DocumentsContract.buildDocumentUriUsingTree(tree, it.getString(0)) to if (it.isNull(2)) -1 else it.getLong(2)
            }
        }
        return null
    }

    private fun publishTree(source: File, tree: Uri, name: String): Uri {
        findChild(tree, name)?.let {
            check(it.second == source.length()) { "下载目录中有同名文件，请先检查该文件。" }
            return it.first
        }
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val partialName = ".biload-part-$name"
        findChild(tree, partialName)?.let { DocumentsContract.deleteDocument(resolver, it.first) }
        var created = DocumentsContract.createDocument(resolver, parent, mime(name), partialName)
            ?: throw IOException("所选目录不允许创建文件，请重新授权。")
        try {
            write(source, created)
            created = DocumentsContract.renameDocument(resolver, created, name)
                ?: throw IOException("所选目录无法完成文件保存，请选择其他本地文件夹。")
            return created
        } catch (error: Exception) {
            DocumentsContract.deleteDocument(resolver, created)
            throw error
        }
    }

    private fun publishLegacy(source: File, name: String): String {
        val output = File(legacyDirectory(), name)
        if (output.exists()) {
            check(output.length() == source.length()) { "下载目录中有同名文件，请先检查该文件。" }
            return output.path
        }
        val staging = File(legacyDirectory(), "$name.biload-part")
        try {
            source.copyTo(staging, overwrite = true)
            check(staging.length() == source.length())
            check(staging.renameTo(output)) { "无法完成文件保存。" }
        } finally { staging.delete() }
        MediaScannerConnection.scanFile(activity, arrayOf(output.path), arrayOf(mime(name)), null)
        return output.path
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_DIRECTORY) return false
        val callback = directoryResult ?: return true
        directoryResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) callback.success(null)
        else try {
            val flags = (data?.flags ?: 0) and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            resolver.takePersistableUriPermission(uri, flags)
            checkedTree(uri)
            val id = DocumentsContract.getTreeDocumentId(uri)
            callback.success(mapOf("directory" to uri.toString(), "label" to id.replace("primary:", "内部存储/")))
        } catch (_: Exception) { callback.error("STORAGE_PERMISSION", "未取得文件夹的持久读写授权，请重新选择。", null) }
        return true
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != WRITE_PERMISSION) return false
        val callback = permissionResult ?: return true
        permissionResult = null
        if (grantResults.firstOrNull() != PackageManager.PERMISSION_GRANTED) {
            callback.error("STORAGE_PERMISSION", "请允许存储权限，以便保存到公共下载目录。", null)
        } else background(callback) { prepare(DEFAULT_DIRECTORY); null }
        return true
    }
}
