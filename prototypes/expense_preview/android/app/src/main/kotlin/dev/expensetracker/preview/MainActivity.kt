package dev.expensetracker.preview

import android.app.Activity
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.content.Intent
import android.os.Bundle
import android.net.Uri
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var reminderPermissionPending: MethodChannel.Result? = null
    private var encrypted: ByteArray? = null
    private var selectedSimple: Uri? = null
    private var selectedSimpleExport: Uri? = null
    private val maxBytes = 24 * 1024 * 1024

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "expense_preview/recurring_reminders")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(RecurringReminderScheduler.isEnabled(this))
                    "setEnabled" -> {
                        val enabled = call.arguments as? Boolean
                        if (enabled == null || reminderPermissionPending != null) {
                            result.error("reminder", "無法更新提醒設定", null)
                        } else if (enabled && Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                        ) {
                            reminderPermissionPending = result
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 502)
                        } else {
                            try {
                                result.success(RecurringReminderScheduler.setEnabled(this, enabled))
                            } catch (_: Exception) {
                                result.error("reminder", "無法更新提醒設定", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, "expense_preview/documents")
            .setMethodCallHandler { call, result ->
                if (pending != null) {
                    result.error("busy", "另一個檔案選擇尚未結束", null)
                } else if (call.method == "readSimpleImport") {
                    val uri = selectedSimple
                    selectedSimple = null
                    if (uri == null) {
                        result.error("document", "尚未選取匯入檔案", null)
                    } else Thread {
                        try {
                            val text = Charsets.UTF_8.newDecoder()
                                .onMalformedInput(CodingErrorAction.REPORT)
                                .onUnmappableCharacter(CodingErrorAction.REPORT)
                                .decode(ByteBuffer.wrap(readBounded(uri))).toString()
                            runOnUiThread { result.success(text) }
                        } catch (_: Exception) {
                            runOnUiThread { result.error("document", "匯入檔案無法讀取或不是 UTF-8", null) }
                        }
                    }.apply { name = "simple-import-document"; isDaemon = true }.start()
                } else if (call.method == "discardSimpleImport") {
                    selectedSimple = null
                    result.success(null)
                } else if (call.method == "writeSimpleExport") {
                    val uri = selectedSimpleExport
                    selectedSimpleExport = null
                    val bytes = (call.arguments as? String)?.toByteArray(Charsets.UTF_8)
                    if (uri == null || bytes == null || bytes.isEmpty() || bytes.size > maxBytes) {
                        result.error("simple_export", "尚未選擇匯出位置或內容超過上限", null)
                    } else {
                        pending = result
                        Thread {
                            try {
                                contentResolver.openOutputStream(uri, "wt").use { output ->
                                    requireNotNull(output)
                                    output.write(bytes)
                                    output.flush()
                                }
                                check(readBounded(uri).contentEquals(bytes))
                                runOnUiThread { pending = null; result.success(true) }
                            } catch (_: Exception) {
                                runOnUiThread {
                                    pending = null
                                    result.error("simple_export", "匯出檔案寫入或回讀核對失敗；檔案可能不完整", null)
                                }
                            }
                        }.apply { name = "simple-export-document"; isDaemon = true }.start()
                    }
                } else if (call.method == "discardSimpleExport") {
                    selectedSimpleExport = null
                    result.success(null)
                } else if (call.method == "open" || call.method == "save" || call.method == "chooseSimpleImport" || call.method == "chooseSimpleExport") {
                    try {
                        val saving = call.method == "save"
                        val simple = call.method == "chooseSimpleImport"
                        val simpleExport = call.method == "chooseSimpleExport"
                        val format = if (simpleExport) call.arguments as? String else null
                        if (simpleExport && format != "json" && format != "csv") throw IllegalArgumentException()
                        val data = if (saving) (call.arguments as? String)?.toByteArray(Charsets.UTF_8) else null
                        if (saving && (data == null || data.size > maxBytes)) throw IllegalArgumentException()
                        pending = result
                        encrypted = data
                        if (simple) selectedSimple = null
                        if (simpleExport) selectedSimpleExport = null
                        val intent = Intent(if (saving || simpleExport) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType(if (saving) "application/octet-stream" else if (simpleExport && format == "json") "application/json" else if (simpleExport) "text/csv" else "*/*")
                        if (saving) intent.putExtra(Intent.EXTRA_TITLE, "ExpenseTracker-${System.currentTimeMillis()}.etv2")
                        if (simpleExport) intent.putExtra(Intent.EXTRA_TITLE, "ExpenseTracker-simple-${System.currentTimeMillis()}.$format")
                        startActivityForResult(intent, if (saving) 401 else if (simple) 403 else if (simpleExport) 404 else 402)
                    } catch (_: Exception) {
                        pending = null
                        encrypted = null
                        result.error("document", "無法開啟檔案選擇器", null)
                    }
                } else result.notImplemented()
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 502) return
        val result = reminderPermissionPending ?: return
        reminderPermissionPending = null
        try {
            result.success(
                if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
                    RecurringReminderScheduler.setEnabled(this, true) else false,
            )
        } catch (_: Exception) {
            result.error("reminder", "無法啟用提醒", null)
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
        if (requestCode != 401 && requestCode != 402 && requestCode != 403 && requestCode != 404) return
        val result = pending ?: return
        val bytes = encrypted
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null
            encrypted = null
            result.success(null)
            return
        }
        if (requestCode == 403) {
            selectedSimple = uri
            pending = null
            encrypted = null
            result.success(true)
            return
        }
        if (requestCode == 404) {
            selectedSimpleExport = uri
            pending = null
            encrypted = null
            result.success(true)
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
