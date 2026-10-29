package app.biload.biload

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private lateinit var outputStorage: AndroidOutputStorage
    private var exportResult: MethodChannel.Result? = null
    private var exportSource: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        outputStorage = AndroidOutputStorage(this)
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.biload/platform")
            .setMethodCallHandler { call, result ->
                if (outputStorage.handle(call, result)) return@setMethodCallHandler
                when (call.method) {
                    "biliCookies" -> result.success(
                        CookieManager.getInstance().getCookie("https://www.bilibili.com/") ?: "")
                    "clearBiliCookies" -> CookieManager.getInstance().removeAllCookies {
                        CookieManager.getInstance().flush()
                        result.success(null)
                    }
                    "openFile", "exportFile" -> {
                        val path = call.argument<String>("path")
                        val file = path?.let { File(it).canonicalFile }
                        val roots = listOfNotNull(filesDir.canonicalFile, getExternalFilesDir(null)?.canonicalFile)
                        if (file == null || !file.isFile || roots.none { file.path.startsWith(it.path + File.separator) }) {
                            result.error("FILE", "文件不可访问", null)
                        } else if (call.method == "openFile") {
                            try {
                                val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
                                startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime(file))
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                                result.success(null)
                            } catch (_: Exception) { result.error("OPEN", "没有可用的播放器", null) }
                        } else if (exportResult != null) {
                            result.error("BUSY", "已有导出操作", null)
                        } else {
                            exportResult = result
                            exportSource = file
                            try {
                                startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT)
                                    .addCategory(Intent.CATEGORY_OPENABLE).setType(mime(file))
                                    .putExtra(Intent.EXTRA_TITLE, file.name), 3101)
                            } catch (_: Exception) {
                                exportResult = null
                                exportSource = null
                                result.error("EXPORT", "无法打开系统文件选择器", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun mime(file: File): String = MimeTypeMap.getSingleton()
        .getMimeTypeFromExtension(file.extension.lowercase()) ?: "application/octet-stream"

    @Deprecated("Activity result compatibility with FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (outputStorage.onActivityResult(requestCode, resultCode, data)) return
        if (requestCode != 3101) return
        val callback = exportResult ?: return
        val source = exportSource
        exportResult = null
        exportSource = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || source == null) {
            callback.success(null)
            return
        }
        Thread {
            try {
                contentResolver.openOutputStream(uri, "w").use { target ->
                    requireNotNull(target)
                    source.inputStream().use { input -> input.copyTo(target) }
                }
                runOnUiThread { callback.success(source.name) }
            } catch (_: Exception) {
                runOnUiThread { callback.error("EXPORT", "导出失败，请检查剩余空间和文件权限", null) }
            }
        }.start()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        outputStorage.onRequestPermissionsResult(requestCode, grantResults)
    }
}
