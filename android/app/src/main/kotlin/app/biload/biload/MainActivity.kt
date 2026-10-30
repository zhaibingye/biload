package app.biload.biload

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.view.WindowManager
import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var outputStorage: AndroidOutputStorage
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
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Activity result compatibility with FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        outputStorage.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        outputStorage.onRequestPermissionsResult(requestCode, grantResults)
    }
}
