package org.balderding.workout

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
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
    companion object {
        /** A shortcut or the tile (batch 23, F352/F353): only opens a screen in the app. */
        const val SHORTCUT = "org.balderding.workout.SHORTCUT"
        private val SHORTCUT_GO = setOf("today", "weight", "last")

        /** The only names the app ever touches in the backup folder (review 7, P1-1); the same rule
         * as autoNamePattern in auto_backup.dart. */
        val AUTO_NAME = Regex("^fightmilk-auto-\\d{4}-\\d{2}-\\d{2}-\\d{6}(\\.locked)?( \\(\\d+\\))?\\.json$")
        val AUTO_PART = Regex("^fightmilk-auto-\\d{4}-\\d{2}-\\d{2}-\\d{6}(\\.locked)?\\.json\\.part$")
    }

    private var pickResult: MethodChannel.Result? = null
    private var folderResult: MethodChannel.Result? = null

    // ---- the backup folder (batch 22, F339): only the folder the person picked, through Android's
    // own documents access; nothing else on the phone is seen
    private fun treeParent(tree: Uri): Uri = android.provider.DocumentsContract.buildDocumentUriUsingTree(tree, android.provider.DocumentsContract.getTreeDocumentId(tree))

    private fun folderOk(tree: Uri): Boolean = contentResolver.persistedUriPermissions.any { it.uri == tree && it.isWritePermission }

    /** The backups in the folder: name, document id, last modified, size (-1 = not known). Only
     * files whose name is exactly ours (AUTO_NAME); never a folder, never anyone else's file
     * (review 7, P1-1). */
    private fun folderList(tree: Uri, parts: Boolean = false): List<Map<String, Any>> {
        val kids = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val out = mutableListOf<Map<String, Any>>()
        val cols = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_LAST_MODIFIED, DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_MIME_TYPE)
        contentResolver.query(kids, cols, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                val name = c.getString(1) ?: continue
                if (c.getString(4) == DocumentsContract.Document.MIME_TYPE_DIR) continue // a folder is never ours
                if (!(if (parts) AUTO_PART else AUTO_NAME).matches(name)) continue // only our own files are ever touched
                out.add(mapOf("id" to c.getString(0), "name" to name, "at" to (if (c.isNull(2)) 0L else c.getLong(2)), "size" to (if (c.isNull(3)) -1L else c.getLong(3))))
            }
        }
        return out
    }

    /** One document's name, type and size, read from the provider itself. */
    private fun docInfo(doc: Uri): Triple<String?, String?, Long> {
        contentResolver.query(doc, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_SIZE), null, null, null)?.use { c ->
            if (c.moveToFirst()) return Triple(c.getString(0), c.getString(1), if (c.isNull(2)) -1L else c.getLong(2))
        }
        return Triple(null, null, -1L)
    }

    /** Creates [name] in the folder with [bytes] and checks the size it holds; on any failure the
     * new document is removed again, so no empty or cut-short file is left (review 7, P1-2). */
    private fun writeChecked(tree: Uri, name: String, mime: String, bytes: ByteArray): Uri {
        val doc = DocumentsContract.createDocument(contentResolver, treeParent(tree), mime, name) ?: throw Exception("the folder did not take the file")
        try {
            contentResolver.openOutputStream(doc, "wt")?.use { it.write(bytes); it.flush() } ?: throw Exception("the file could not be written")
            val size = docInfo(doc).third
            if (size >= 0 && size != bytes.size.toLong()) throw Exception("the folder kept $size of ${bytes.size} bytes")
            return doc
        } catch (e: Exception) {
            try { DocumentsContract.deleteDocument(contentResolver, doc) } catch (_: Exception) {}
            throw e
        }
    }

    /** A backup is written as name.part, checked, then renamed; where the folder cannot rename,
     * it is written under its own name, checked, and removed again on failure. Answers the name
     * the folder gave it (it may add " (1)"). */
    private fun writeBackup(tree: Uri, name: String, bytes: ByteArray): String {
        if (bytes.isEmpty()) throw Exception("an empty backup")
        // part files an earlier, killed write left: ours by the strict rule, nothing else
        for (p in folderList(tree, parts = true)) {
            try { DocumentsContract.deleteDocument(contentResolver, DocumentsContract.buildDocumentUriUsingTree(tree, p["id"] as String)) } catch (_: Exception) {}
        }
        val part = writeChecked(tree, "$name.part", "application/octet-stream", bytes)
        val done: Uri? = try { DocumentsContract.renameDocument(contentResolver, part, name) } catch (_: Exception) { null }
        val final = if (done != null) done else {
            try { DocumentsContract.deleteDocument(contentResolver, part) } catch (_: Exception) {}
            writeChecked(tree, name, "application/json", bytes)
        }
        val n = docInfo(final).first ?: name
        if (!AUTO_NAME.matches(n)) { // the folder named it something else: not ours to keep
            try { DocumentsContract.deleteDocument(contentResolver, final) } catch (_: Exception) {}
            throw Exception("the folder renamed the file")
        }
        return n
    }

    private fun folderCall(method: String, args: Map<String, Any?>, result: MethodChannel.Result) {
        val tree = Uri.parse(args["tree"] as? String ?: "")
        Thread {
            try {
                val answer: Any? = when (method) {
                    "ok" -> folderOk(tree)
                    "list" -> if (folderOk(tree)) folderList(tree) else null
                    "write" -> {
                        if (!folderOk(tree)) null else {
                            val name = args["name"] as String
                            require(AUTO_NAME.matches(name)) { "bad name" }
                            writeBackup(tree, name, args["bytes"] as ByteArray)
                        }
                    }
                    // give the folder's access back (another folder picked, or all data deleted)
                    "release" -> {
                        try {
                            contentResolver.releasePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        } catch (_: SecurityException) {
                            // already gone
                        }
                        true
                    }
                    "head" -> {
                        // the first bytes of one of our own files, so a file whose size the folder
                        // does not say is only counted when it really is a backup (review 7, P1-2)
                        val doc = DocumentsContract.buildDocumentUriUsingTree(tree, args["id"] as String)
                        val (n, mime, _) = docInfo(doc)
                        if (!folderOk(tree) || n == null || !AUTO_NAME.matches(n) || mime == DocumentsContract.Document.MIME_TYPE_DIR) null
                        else contentResolver.openInputStream(doc)?.use { s ->
                            val want = ((args["n"] as? Int) ?: 64).coerceIn(1, 256)
                            val buf = ByteArray(want)
                            var got = 0
                            while (got < want) {
                                val k = s.read(buf, got, want - got)
                                if (k < 0) break
                                got += k
                            }
                            buf.copyOf(got)
                        }
                    }
                    "delete" -> {
                        val id = args["id"] as String
                        val name = args["name"] as String
                        val doc = android.provider.DocumentsContract.buildDocumentUriUsingTree(tree, id)
                        if (!folderOk(tree) || !AUTO_NAME.matches(name)) false
                        else {
                            // ask the folder itself what this is: only our own file, never a folder
                            val (n, mime, _) = docInfo(doc)
                            if (n != name || mime == android.provider.DocumentsContract.Document.MIME_TYPE_DIR) false
                            else android.provider.DocumentsContract.deleteDocument(contentResolver, doc)
                        }
                    }
                    else -> throw Exception("unknown")
                }
                runOnUiThread { result.success(answer) }
            } catch (e: Exception) {
                val full = (e.message ?: "").contains("ENOSPC") || (e.message ?: "").contains("No space")
                runOnUiThread { result.error(if (full) "full" else "folder", e.message, null) }
            }
        }.start()
    }
    private var pickDest: String = ""

    // A plan someone sent (batch 20): a fightmilk://plan link, or a shared .json / text. Kept here
    // until the app asks ("workout/incoming" take) and checks it; nothing is fetched from anywhere.
    private var incoming: Intent? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // only a fresh start opens what was sent: not a re-created activity or Recents (review 5, P3-N33)
        val fromRecents = (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        incoming = if (savedInstanceState == null && !fromRecents) intent else null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        incoming = intent
    }

    /**
     * Answers [result] with what was sent: a map of "kind" (ok / too_big / too_slow), "text" and
     * "type" (the MIME type, so Dart sends a CSV to the import and a plan to the plan reader), or
     * null when there is none. A CSV may be 8 MB, anything else 1 MB (review 6 P2-5). Another
     * app's file is read on a worker thread with a 10 s limit (review 5, P2-5), as UTF-8, or as
     * Windows-1252 when it is not (like the in-app picker); FightMilk's own provider is never read.
     */
    private fun takeIncoming(result: MethodChannel.Result) {
        val i = incoming
        incoming = null
        if (i == null) {
            result.success(null)
            return
        }
        fun answer(kind: String, text: String = "", type: String = "") = mapOf("kind" to kind, "text" to text, "type" to type)
        if (i.action == SHORTCUT) {
            // only the few known places; anything else another app sends opens nothing
            val go = i.getStringExtra("go")
            result.success(if (go != null && go in SHORTCUT_GO) answer("ok", go, "shortcut") else null)
            return
        }
        val small = 1 shl 20
        val uri: Uri? = when (i.action) {
            Intent.ACTION_VIEW, "android.nfc.action.NDEF_DISCOVERED" -> {
                val d = i.data
                if (d != null && d.scheme == "fightmilk") {
                    result.success(answer("ok", d.toString().take(small), "link"))
                    return
                }
                if (d != null && d.scheme == "content") d else null
            }
            Intent.ACTION_SEND -> {
                val t = i.getStringExtra(Intent.EXTRA_TEXT)
                val type = i.type ?: ""
                if (t != null) {
                    val max = if (type.contains("csv")) 8 * small else small
                    result.success(if (t.length > max) answer("too_big", type = type) else answer("ok", t, type))
                    return
                }
                @Suppress("DEPRECATION")
                val u = i.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                if (u != null && u.scheme == "content") u else null
            }
            else -> null
        }
        if (uri == null || uri.authority == "$packageName.updates") {
            result.success(null)
            return
        }
        val type = (try { contentResolver.getType(uri) } catch (e: Exception) { null }) ?: i.type ?: ""
        val name = uri.lastPathSegment ?: ""
        val max = if (type.contains("csv") || name.endsWith(".csv", ignoreCase = true)) 8 * small else small
        val done = java.util.concurrent.atomic.AtomicBoolean(false)
        val stream = java.util.concurrent.atomic.AtomicReference<java.io.InputStream?>(null) // seen by both threads (review 6 N46)
        val main = Handler(Looper.getMainLooper())
        main.postDelayed({
            if (done.compareAndSet(false, true)) {
                try {
                    stream.get()?.close() // unblocks the worker's read; if the provider blocks in open, the thread ends when it returns
                } catch (e: Exception) {}
                result.success(answer("too_slow", type = type))
            }
        }, 10_000L)
        Thread {
            val a: Map<String, String>? = try {
                contentResolver.openInputStream(uri).use { inp ->
                    stream.set(inp)
                    if (inp == null) null else {
                        val buf = inp.readNBytesCompat(max + 1)
                        if (buf.size > max) answer("too_big", type = type)
                        else answer("ok", decodeText(buf), if (type.isEmpty() && name.endsWith(".csv", ignoreCase = true)) "text/csv" else type)
                    }
                }
            } catch (e: Exception) {
                null
            }
            main.post { if (done.compareAndSet(false, true)) result.success(a) }
        }.start()
    }

    /** UTF-8 when the bytes are UTF-8, else Windows-1252 (older Windows exports). */
    private fun decodeText(b: ByteArray): String = try {
        java.nio.charset.StandardCharsets.UTF_8.newDecoder()
            .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
            .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
            .decode(java.nio.ByteBuffer.wrap(b)).toString()
    } catch (e: java.nio.charset.CharacterCodingException) {
        String(b, charset("windows-1252"))
    }

    private fun java.io.InputStream.readNBytesCompat(n: Int): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val b = ByteArray(8192)
        while (out.size() < n) {
            val k = read(b, 0, minOf(b.size, n - out.size()))
            if (k < 0) break
            out.write(b, 0, k)
        }
        return out.toByteArray()
    }

    // "Import a model file": the person picks a file with Android's own file picker; we copy it into
    // the app's storage (to [pickDest]) and report the byte count. Nothing is read beyond that file.
    @Deprecated("FlutterActivity still routes results here")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_FOLDER) {
            // the backup folder (batch 22, F339): picked once, kept with a lasting permission
            val r = folderResult ?: return
            folderResult = null
            val tree = data?.data
            if (resultCode != Activity.RESULT_OK || tree == null) {
                r.success(null)
                return
            }
            try {
                contentResolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                r.success(tree.toString())
            } catch (e: Exception) {
                r.error("no_permission", e.message, null)
            }
            return
        }
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
                // the home-screen widget's lines (batch 23, F351); kept only while a widget is placed
                "widget" -> result.success(FmWidget.save(this, call.argument<String>("next") ?: "", call.argument<String>("week") ?: ""))
                // Hide the app in the recent-apps view and block screenshots (Settings, off by default).
                "secure" -> {
                    if (call.argument<Boolean>("on") == true) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                "pickFolder" -> {
                    if (folderResult != null) {
                        result.error("busy", "already picking", null)
                        return@setMethodCallHandler
                    }
                    folderResult = result
                    try {
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION), PICK_FOLDER)
                    } catch (e: Exception) {
                        folderResult = null
                        result.error("no_picker", e.message, null)
                    }
                }
                "folder" -> {
                    @Suppress("UNCHECKED_CAST")
                    folderCall(call.argument<String>("op") ?: "", call.arguments as Map<String, Any?>, result)
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "workout/incoming").setMethodCallHandler { call, result ->
            if (call.method == "take") takeIncoming(result) else result.notImplemented()
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
            if (call.method == "shareFile") {
                // An export the person chose to send (batch 20). Only files under cache/exports/
                // can be handed out (res/xml/update_paths.xml).
                try {
                    val file = File(call.argument<String>("path") ?: "")
                    val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = call.argument<String>("mime") ?: "application/octet-stream"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(Intent.createChooser(send, call.argument<String>("title") ?: "Send to…").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success("chooser")
                } catch (e: Exception) {
                    result.error("share_failed", e.message, null)
                }
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
private const val PICK_FOLDER = 4712
