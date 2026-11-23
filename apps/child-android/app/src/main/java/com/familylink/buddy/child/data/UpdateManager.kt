package com.familylink.buddy.child.data

import android.content.Context
import android.util.Log
import com.familylink.buddy.child.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

data class ReleaseInfo(
    val tagName: String,
    val name: String,
    val body: String,
    val downloadUrl: String,
    val isNewer: Boolean
)

/**
 * Handles checking GitHub releases and downloading/installing latest child APK.
 */
object UpdateManager {
    private const val TAG = "UpdateManager"
    const val GITHUB_RELEASES_API_URL = "https://api.github.com/repos/schdef/familylink-buddy/releases/latest"
    const val FALLBACK_DOWNLOAD_URL = "https://raw.githubusercontent.com/schdef/familylink-buddy/main/build/child-app-release.apk"

    /**
     * Pure semver comparison helper.
     * Returns true if latestVersion is strictly greater than currentVersion.
     */
    fun isVersionNewer(latestVersion: String, currentVersion: String): Boolean {
        val cleanLatest = latestVersion.trimStart('v', 'V').trim()
        val cleanCurrent = currentVersion.trimStart('v', 'V').trim()
        if (cleanLatest.isEmpty() || cleanCurrent.isEmpty()) return false

        val latestParts = cleanLatest.split(".").mapNotNull { it.toIntOrNull() }
        val currentParts = cleanCurrent.split(".").mapNotNull { it.toIntOrNull() }
        if (latestParts.isEmpty() || currentParts.isEmpty()) return false

        val maxLen = maxOf(latestParts.size, currentParts.size)
        for (i in 0 until maxLen) {
            val lat = if (i < latestParts.size) latestParts[i] else 0
            val cur = if (i < currentParts.size) currentParts[i] else 0
            if (lat > cur) return true
            if (lat < cur) return false
        }
        return false
    }

    /**
     * Queries GitHub Releases API for the latest release.
     */
    suspend fun checkLatestRelease(
        apiUrl: String = GITHUB_RELEASES_API_URL,
        currentVersion: String = BuildConfig.VERSION_NAME
    ): ReleaseInfo? = withContext(Dispatchers.IO) {
        try {
            val url = URL(apiUrl)
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "GET"
            connection.setRequestProperty("User-Agent", "FamilyLinkBuddy-Child")
            connection.setRequestProperty("Accept", "application/vnd.github.v3+json")
            connection.connectTimeout = 8000
            connection.readTimeout = 8000

            val responseCode = connection.responseCode
            if (responseCode != HttpURLConnection.HTTP_OK) {
                Log.w(TAG, "GitHub API returned status $responseCode")
                connection.disconnect()
                return@withContext null
            }

            val jsonString = connection.inputStream.bufferedReader().use { it.readText() }
            connection.disconnect()

            val json = JSONObject(jsonString)
            val tagName = json.optString("tag_name", "")
            val name = json.optString("name", tagName)
            val body = json.optString("body", "")

            var downloadUrl = ""
            val assets = json.optJSONArray("assets")
            if (assets != null) {
                for (i in 0 until assets.length()) {
                    val asset = assets.getJSONObject(i)
                    val assetName = asset.optString("name", "")
                    if (assetName.equals("child-app-release.apk", ignoreCase = true) ||
                        (assetName.contains("child", ignoreCase = true) && assetName.endsWith(".apk", ignoreCase = true))
                    ) {
                        downloadUrl = asset.optString("browser_download_url", "")
                        break
                    }
                }
            }

            if (downloadUrl.isBlank()) {
                downloadUrl = FALLBACK_DOWNLOAD_URL
            }

            val isNewer = isVersionNewer(tagName, currentVersion)
            return@withContext ReleaseInfo(
                tagName = tagName,
                name = name,
                body = body,
                downloadUrl = downloadUrl,
                isNewer = isNewer
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error checking latest release from GitHub", e)
            null
        }
    }

    /**
     * Downloads the APK file from downloadUrl to cacheDir and installs it via PackageInstallerHelper.
     */
    suspend fun downloadAndInstallApk(
        context: Context,
        downloadUrl: String,
        onProgress: (Float) -> Unit = {}
    ): Boolean = withContext(Dispatchers.IO) {
        val cacheFile = File(context.cacheDir, "update.apk")
        if (cacheFile.exists()) {
            cacheFile.delete()
        }

        try {
            var currentUrl = downloadUrl
            var connection: HttpURLConnection? = null
            var redirectCount = 0
            val maxRedirects = 5

            // Follow HTTP redirects (GitHub releases redirect to AWS S3/CDN)
            while (redirectCount < maxRedirects) {
                val url = URL(currentUrl)
                connection = (url.openConnection() as HttpURLConnection).apply {
                    instanceFollowRedirects = true
                    setRequestProperty("User-Agent", "FamilyLinkBuddy-Child")
                    connectTimeout = 15000
                    readTimeout = 30000
                }
                connection.connect()

                val code = connection.responseCode
                if (code == HttpURLConnection.HTTP_MOVED_PERM ||
                    code == HttpURLConnection.HTTP_MOVED_TEMP ||
                    code == 307 || code == 308
                ) {
                    val location = connection.getHeaderField("Location")
                    connection.disconnect()
                    if (!location.isNullOrBlank()) {
                        currentUrl = location
                        redirectCount++
                        continue
                    }
                }
                break
            }

            if (connection == null || connection.responseCode != HttpURLConnection.HTTP_OK) {
                Log.e(TAG, "Failed downloading update, HTTP status: ${connection?.responseCode}")
                connection?.disconnect()
                return@withContext false
            }

            val fileLength = connection.contentLengthLong.let { if (it > 0) it else connection.contentLength.toLong() }
            val inputStream = connection.inputStream
            val outputStream = FileOutputStream(cacheFile)

            val buffer = ByteArray(8192)
            var totalBytesRead = 0L
            var bytesRead: Int

            while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                outputStream.write(buffer, 0, bytesRead)
                totalBytesRead += bytesRead
                if (fileLength > 0) {
                    val progress = (totalBytesRead.toFloat() / fileLength.toFloat()).coerceIn(0f, 1f)
                    withContext(Dispatchers.Main) {
                        onProgress(progress)
                    }
                }
            }

            outputStream.flush()
            outputStream.close()
            inputStream.close()
            connection.disconnect()

            withContext(Dispatchers.Main) {
                onProgress(1.0f)
            }

            Log.i(TAG, "Downloaded update APK successfully: ${cacheFile.length()} bytes. Triggering installation.")
            return@withContext PackageInstallerHelper.installApk(context, cacheFile)
        } catch (e: Exception) {
            Log.e(TAG, "Exception downloading APK from $downloadUrl", e)
            if (cacheFile.exists()) {
                cacheFile.delete()
            }
            return@withContext false
        }
    }
}
