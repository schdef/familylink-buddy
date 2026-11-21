package com.familylink.buddy.parent

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.familylink.buddy.parent/updater"
    private val REQUEST_CODE_PICK_APK = 1001
    private var pendingPickerResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppVersionCode" -> {
                    try {
                        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
                        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            packageInfo.longVersionCode
                        } else {
                            @Suppress("DEPRECATION")
                            packageInfo.versionCode.toLong()
                        }
                        result.success(versionCode)
                    } catch (e: Exception) {
                        result.error("UNAVAILABLE", "Version code not available.", e.message)
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                if (!context.packageManager.canRequestPackageInstalls()) {
                                    val settingsIntent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                        data = Uri.parse("package:${context.packageName}")
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    context.startActivity(settingsIntent)
                                }
                            }
                            val file = File(filePath)
                            val apkUri = FileProvider.getUriForFile(context, "com.familylink.buddy.parent.fileprovider", file)
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(apkUri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            context.startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", "Failed to trigger apk install", e.message)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "File path is null", null)
                    }
                }
                "pickApkFile" -> {
                    if (pendingPickerResult != null) {
                        result.error("ALREADY_ACTIVE", "File picker is already active.", null)
                        return@setMethodCallHandler
                    }
                    pendingPickerResult = result
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            val mimeTypes = arrayOf(
                                "application/vnd.android.package-archive",
                                "application/octet-stream",
                                "*/*"
                            )
                            putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes)
                        }
                        startActivityForResult(intent, REQUEST_CODE_PICK_APK)
                    } catch (e: Exception) {
                        pendingPickerResult = null
                        result.error("PICK_ERROR", "Could not launch file picker: ${e.message}", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_PICK_APK) {
            val pickerResult = pendingPickerResult
            pendingPickerResult = null
            if (pickerResult == null) return

            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                pickerResult.success(null)
                return
            }

            val uri = data.data!!
            Thread {
                try {
                    var displayName = "child-update.apk"
                    var reportedSize: Long = -1L

                    context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                        val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                        if (cursor.moveToFirst()) {
                            if (nameIndex != -1 && !cursor.isNull(nameIndex)) {
                                val name = cursor.getString(nameIndex)
                                if (!name.isNullOrBlank()) {
                                    displayName = name
                                }
                            }
                            if (sizeIndex != -1 && !cursor.isNull(sizeIndex)) {
                                reportedSize = cursor.getLong(sizeIndex)
                            }
                        }
                    }

                    val safeName = displayName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                    val fileName = if (safeName.endsWith(".apk", ignoreCase = true)) safeName else "$safeName.apk"
                    val tempFile = File(context.cacheDir, "picked_$fileName")

                    context.contentResolver.openInputStream(uri)?.use { inputStream ->
                        FileOutputStream(tempFile).use { outputStream ->
                            inputStream.copyTo(outputStream)
                        }
                    } ?: throw IOException("Could not open input stream for selected file: $uri")

                    val fileSize = if (reportedSize > 0) reportedSize else tempFile.length()

                    runOnUiThread {
                        pickerResult.success(mapOf(
                            "path" to tempFile.absolutePath,
                            "name" to displayName,
                            "size" to fileSize
                        ))
                    }
                } catch (e: Exception) {
                    runOnUiThread {
                        pickerResult.error("READ_ERROR", "Failed to process selected file: ${e.message}", null)
                    }
                }
            }.start()
        }
    }
}
