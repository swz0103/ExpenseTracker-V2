package dev.expensetracker.preview

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var encrypted: ByteArray? = null
    private val maxBytes = 24 * 1024 * 1024

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "expense_preview/documents")
            .setMethodCallHandler { call, result ->
                if (pending != null) {
                    result.error("busy", "另一個檔案選擇尚未結束", null)
                } else if (call.method == "open" || call.method == "save") {
                    try {
                        val saving = call.method == "save"
                        val data = if (saving) (call.arguments as? String)?.toByteArray(Charsets.UTF_8) else null
                        if (saving && (data == null || data.size > maxBytes)) throw IllegalArgumentException()
                        pending = result
                        encrypted = data
                        val intent = Intent(if (saving) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType(if (saving) "application/octet-stream" else "*/*")
                        if (saving) intent.putExtra(Intent.EXTRA_TITLE, "ExpenseTracker-${System.currentTimeMillis()}.etv2")
                        startActivityForResult(intent, if (saving) 401 else 402)
                    } catch (_: Exception) {
                        pending = null
                        encrypted = null
                        result.error("document", "無法開啟檔案選擇器", null)
                    }
                } else result.notImplemented()
            }
    }

    private fun readBounded(uri: android.net.Uri): ByteArray {
        contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input)
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                if (output.size() + n > maxBytes) throw IllegalArgumentException()
                output.write(buffer, 0, n)
            }
            return output.toByteArray()
        }
    }

    @Deprecated("Android result bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 401 && requestCode != 402) return
        val result = pending ?: return
        val bytes = encrypted
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null
            encrypted = null
            result.success(null)
            return
        }
        Thread {
            try {
                val answer: Any = if (requestCode == 401) {
                    requireNotNull(bytes)
                    contentResolver.openOutputStream(uri, "wt").use { output ->
                        requireNotNull(output)
                        output.write(bytes)
                        output.flush()
                    }
                    check(readBounded(uri).contentEquals(bytes))
                    true
                } else readBounded(uri).toString(Charsets.UTF_8)
                runOnUiThread { pending = null; encrypted = null; result.success(answer) }
            } catch (_: Exception) {
                runOnUiThread {
                    pending = null
                    encrypted = null
                    result.error("document", "檔案讀寫或讀回驗證失敗；已建立的檔案可能不完整", null)
                }
            }
        }.apply { name = "encrypted-document"; isDaemon = true }.start()
    }
}
