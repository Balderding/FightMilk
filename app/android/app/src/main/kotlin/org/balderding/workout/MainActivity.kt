package org.balderding.workout

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import android.app.Activity
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * One small native piece: hand text to a chat app (Claude, ChatGPT, Gemini) with Android's normal
 * "send text" intent, so people can use their own subscription there. Nothing goes over the network
 * from this app; the chat app shows the text and the person decides to send it.
 */
class MainActivity : FlutterActivity() {
    private var pickResult: MethodChannel.Result? = null
    private var pickDest: String = ""

    // "Import a model file": the person picks a file with Android's own file picker; we copy it into
    // the app's storage (to [pickDest]) and report the byte count. Nothing is read beyond that file.
    @Deprecated("FlutterActivity still routes results here")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_MODEL) return
        val r = pickResult ?: return
        pickResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            r.success(-1L)
            return
        }
        val dest = File(pickDest)
        Thread {
            try {
                dest.parentFile?.mkdirs()
                var n = 0L
                contentResolver.openInputStream(uri).use { inp ->
                    if (inp == null) throw Exception("could not open the file")
                    dest.outputStream().use { out -> n = inp.copyTo(out, 1 shl 20) }
                }
                runOnUiThread { r.success(n) }
            } catch (e: Exception) {
                dest.delete()
                runOnUiThread { r.error("copy_failed", e.message, null) }
            }
        }.start()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // App updates: which APK fits this phone, and handing a checked APK to Android's installer
        // (Android asks the person to confirm, and only accepts it if it is signed with our key).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "workout/system").setMethodCallHandler { call, result ->
            when (call.method) {
                "abi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull() ?: "")
                // Hide the app in the recent-apps view and block screenshots (Settings, off by default).
                "secure" -> {
                    if (call.argument<Boolean>("on") == true) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                "pickFile" -> {
                    if (pickResult != null) {
                        result.error("busy", "already picking", null)
                        return@setMethodCallHandler
                    }
                    pickResult = result
                    pickDest = call.argument<String>("dest") ?: ""
                    try {
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*"), PICK_MODEL)
                    } catch (e: Exception) {
                        pickResult = null
                        result.error("no_picker", e.message, null)
                    }
                }
                "install" -> {
                    val path = call.argument<String>("path") ?: ""
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                        startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success("need_permission")
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = FileProvider.getUriForFile(this, "$packageName.updates", File(path))
                        startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success("started")
                    } catch (e: Exception) {
                        result.error("install_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "workout/handoff").setMethodCallHandler { call, result ->
            if (call.method == "copy") {
                // Marked sensitive (keyboards' clipboard history and previews leave it out) and
                // cleared after a few minutes if it is still what this app put there.
                val text = call.argument<String>("text") ?: ""
                val cm = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                val clip = ClipData.newPlainText("FightMilk", text)
                if (Build.VERSION.SDK_INT >= 24) {
                    clip.description.extras = PersistableBundle().apply {
                        putBoolean(if (Build.VERSION.SDK_INT >= 33) ClipDescription.EXTRA_IS_SENSITIVE else "android.content.extra.IS_SENSITIVE", true)
                    }
                }
                cm.setPrimaryClip(clip)
                Handler(Looper.getMainLooper()).postDelayed({
                    try {
                        val now = cm.primaryClip
                        if (now != null && now.itemCount > 0 && now.getItemAt(0).text?.toString() == text) {
                            if (Build.VERSION.SDK_INT >= 28) cm.clearPrimaryClip() else cm.setPrimaryClip(ClipData.newPlainText("", ""))
                        }
                    } catch (e: Exception) {}
                }, 3 * 60 * 1000L)
                result.success(true)
                return@setMethodCallHandler
            }
            if (call.method != "send") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val text = call.argument<String>("text") ?: ""
            val pkg = call.argument<String>("package") ?: ""
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
            }
            if (pkg.isNotEmpty()) {
                try {
                    startActivity(Intent(send).setPackage(pkg).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success("app")
                    return@setMethodCallHandler
                } catch (e: ActivityNotFoundException) {
                    // that app isn't installed: fall through to the share menu
                }
            }
            try {
                startActivity(Intent.createChooser(send, "Send to…").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(if (pkg.isEmpty()) "chooser" else "missing")
            } catch (e: Exception) {
                result.error("no_app", "No app can receive text", null)
            }
        }
    }
}

private const val PICK_MODEL = 4711
