package com.familylink.buddy.child

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.glance.appwidget.updateAll
import com.familylink.buddy.child.data.AppUsage
import com.familylink.buddy.child.data.FamilyTimeData
import com.familylink.buddy.child.data.FamilyTimeRepository
import com.familylink.buddy.child.service.WidgetUpdateService
import com.familylink.buddy.child.widget.FamilyBuddyWidget
import com.familylink.buddy.child.service.CommsActivity
import com.familylink.buddy.child.ui.SetupGuideCard
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first

import android.provider.Settings
import android.net.Uri
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.LocalContext
import android.content.Context
import android.media.AudioManager
import android.content.ClipboardManager
import android.content.ClipData
import android.widget.Toast
import com.familylink.buddy.child.data.VolumeState
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ktx.firestore
import com.google.firebase.functions.ktx.functions
import com.google.firebase.ktx.Firebase
import androidx.compose.ui.graphics.asImageBitmap
import com.familylink.buddy.child.data.QrCodeGenerator
import android.util.Log
import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import java.util.Calendar
import androidx.compose.ui.draw.rotate
import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.graphics.Brush
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import com.familylink.buddy.child.data.TimeBankState
import com.familylink.buddy.child.data.BonusTask
import com.familylink.buddy.child.data.RewardItem
import com.familylink.buddy.child.data.RewardClaim
import kotlinx.coroutines.delay
import java.net.URL
import java.net.HttpURLConnection
import java.io.FileOutputStream
import java.io.File
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers



class Particle(var x: Float, var y: Float, val vx: Float, val vy: Float, val size: Float, val color: Color) {
    fun update() {
        x += vx
        y += vy
    }
}

class MainActivity : ComponentActivity() {

    private lateinit var repository: FamilyTimeRepository
    private val canDrawOverlaysState = mutableStateOf(false)
    private val hasUsageAccessState = mutableStateOf(false)

    private fun playCoinSound() {
        try {
            val sampleRate = 8000
            val duration1 = 0.08
            val duration2 = 0.18
            val numSamples1 = (duration1 * sampleRate).toInt()
            val numSamples2 = (duration2 * sampleRate).toInt()
            val sample1 = DoubleArray(numSamples1)
            val sample2 = DoubleArray(numSamples2)
            val generatedSnd = ByteArray(2 * (numSamples1 + numSamples2))

            for (i in 0 until numSamples1) {
                sample1[i] = Math.sin(2 * Math.PI * i / (sampleRate / 1300.0))
            }
            for (i in 0 until numSamples2) {
                sample2[i] = Math.sin(2 * Math.PI * i / (sampleRate / 1800.0))
            }

            var idx = 0
            for (i in 0 until numSamples1) {
                val valSample = (sample1[i] * 32767).toInt()
                generatedSnd[idx++] = (valSample and 0x00ff).toByte()
                generatedSnd[idx++] = (valSample and 0xff00 ushr 8).toByte()
            }
            for (i in 0 until numSamples2) {
                val valSample = (sample2[i] * 32767).toInt()
                generatedSnd[idx++] = (valSample and 0x00ff).toByte()
                generatedSnd[idx++] = (valSample and 0xff00 ushr 8).toByte()
            }

            val audioTrack = android.media.AudioTrack(
                android.media.AudioManager.STREAM_MUSIC,
                sampleRate,
                android.media.AudioFormat.CHANNEL_OUT_MONO,
                android.media.AudioFormat.ENCODING_PCM_16BIT,
                generatedSnd.size,
                android.media.AudioTrack.MODE_STATIC
            )
            audioTrack.write(generatedSnd, 0, generatedSnd.size)
            audioTrack.play()
        } catch (e: Exception) {
            Log.e("MainActivity", "Error playing synth coin sound", e)
        }
    }

    private fun playJingleSound() {
        try {
            val sampleRate = 8000
            val duration = 0.12
            val numSamples = (duration * sampleRate).toInt()
            val generatedSnd = ByteArray(2 * numSamples * 3)

            val freqs = doubleArrayOf(523.25, 659.25, 783.99)
            var idx = 0
            for (f in freqs) {
                for (i in 0 until numSamples) {
                    val value = Math.sin(2 * Math.PI * i / (sampleRate / f))
                    val valSample = (value * 32767).toInt()
                    generatedSnd[idx++] = (valSample and 0x00ff).toByte()
                    generatedSnd[idx++] = (valSample and 0xff00 ushr 8).toByte()
                }
            }

            val audioTrack = android.media.AudioTrack(
                android.media.AudioManager.STREAM_MUSIC,
                sampleRate,
                android.media.AudioFormat.CHANNEL_OUT_MONO,
                android.media.AudioFormat.ENCODING_PCM_16BIT,
                generatedSnd.size,
                android.media.AudioTrack.MODE_STATIC
            )
            audioTrack.write(generatedSnd, 0, generatedSnd.size)
            audioTrack.play()
        } catch (e: Exception) {
            Log.e("MainActivity", "Error playing synth complete jingle", e)
        }
    }

    private fun isServiceRunning(): Boolean {
        return getSharedPreferences("widget_service_prefs", Context.MODE_PRIVATE)
            .getBoolean("service_running", false)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        repository = FamilyTimeRepository(applicationContext)

        // Firebase emulators are initialized globally in FamilyLinkBuddyApplication.java

        // Request notification permission if Android 13+
        requestNotificationPermission()

        // Fetch FCM token on launch and update it in database
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (task.isSuccessful) {
                val token = task.result
                lifecycleScopeLaunch {
                    repository.updateDeviceToken(token)
                }
            }
        }

        // Update local volume state on startup
        updateLocalVolumeState()

        // Write initial data if none exists
        lifecycleScopeLaunch {
            val initial = FamilyTimeData(
                totalRemainingMinutes = 60,
                totalLimitMinutes = 120,
                appUsages = listOf(
                    AppUsage("com.google.android.youtube", "YouTube", 15, 30),
                    AppUsage("com.mojang.minecraftpe", "Minecraft", 20, 60)
                )
            )
            repository.updateFamilyTimeData(initial)
            FamilyBuddyWidget().updateAll(applicationContext)
        }

        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    background = Color(0xFF0B0C10),
                    surface = Color(0xFF1F2833),
                    primary = Color(0xFF66FCF1),
                    secondary = Color(0xFF45A29E)
                )
            ) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    val scope = rememberCoroutineScope()

                    // In-App Auto-Updater State (Option A)
                    var showUpdateDialog by remember { mutableStateOf(false) }
                    var updateDownloadUrl by remember { mutableStateOf("") }
                    var updateVersionName by remember { mutableStateOf("") }
                    var downloadProgress by remember { mutableStateOf(-1f) }

                    LaunchedEffect(Unit) {
                        try {
                            val db = FirebaseFirestore.getInstance()
                            db.collection("app_metadata").document("releases")
                                .get()
                                .addOnSuccessListener { doc ->
                                    if (doc.exists()) {
                                        val childData = doc.get("child") as? Map<String, Any>
                                        if (childData != null) {
                                            val remoteVersionCode = (childData["versionCode"] as? Number)?.toLong() ?: 0L
                                            val remoteUrl = childData["downloadUrl"] as? String ?: ""
                                            val remoteName = childData["versionName"] as? String ?: ""
                                            
                                            val pInfo = packageManager.getPackageInfo(packageName, 0)
                                            val localVersionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                                pInfo.longVersionCode
                                            } else {
                                                pInfo.versionCode.toLong()
                                            }
                                            
                                            if (remoteVersionCode > localVersionCode && remoteUrl.isNotEmpty()) {
                                                updateDownloadUrl = remoteUrl
                                                updateVersionName = remoteName
                                                showUpdateDialog = true
                                            }
                                        }
                                    }
                                }
                        } catch (e: Exception) {
                            Log.e("MainActivity", "Update check failed", e)
                        }
                    }

                    if (showUpdateDialog) {
                        AlertDialog(
                            onDismissRequest = { },
                            title = {
                                Text(
                                    text = "Update Verfügbar 🚀",
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 20.sp,
                                    color = MaterialTheme.colorScheme.primary
                                )
                            },
                            text = {
                                Column {
                                    Text(
                                        text = "Eine neue Version von FamilyLink Buddy Child ($updateVersionName) ist verfügbar. Bitte installieren Sie das Update, um fortzufahren.",
                                        fontSize = 14.sp,
                                        color = Color.White
                                    )
                                    if (downloadProgress >= 0f) {
                                        Spacer(modifier = Modifier.height(16.dp))
                                        LinearProgressIndicator(
                                            progress = downloadProgress,
                                            modifier = Modifier.fillMaxWidth(),
                                            color = MaterialTheme.colorScheme.primary
                                        )
                                        Spacer(modifier = Modifier.height(8.dp))
                                        Text(
                                            text = "Herunterladen: ${(downloadProgress * 100).toInt()}%",
                                            fontSize = 12.sp,
                                            color = MaterialTheme.colorScheme.secondary
                                        )
                                    }
                                }
                            },
                            confirmButton = {
                                Button(
                                    onClick = {
                                        if (downloadProgress < 0f) {
                                            downloadProgress = 0f
                                            scope.launch(Dispatchers.IO) {
                                                try {
                                                    val urlConnection = URL(updateDownloadUrl).openConnection() as HttpURLConnection
                                                    urlConnection.connect()
                                                    if (urlConnection.responseCode == HttpURLConnection.HTTP_OK) {
                                                        val fileLength = urlConnection.contentLength
                                                        val inputStream = urlConnection.inputStream
                                                        val cacheFile = File(cacheDir, "update.apk")
                                                        val outputStream = FileOutputStream(cacheFile)
                                                        
                                                        val buffer = ByteArray(4096)
                                                        var totalBytesRead = 0L
                                                        var bytesRead: Int
                                                        while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                                                            totalBytesRead += bytesRead
                                                            if (fileLength > 0) {
                                                                downloadProgress = totalBytesRead.toFloat() / fileLength.toFloat()
                                                            }
                                                            outputStream.write(buffer, 0, bytesRead)
                                                        }
                                                        outputStream.flush()
                                                        outputStream.close()
                                                        inputStream.close()
                                                        
                                                        // Trigger installation
                                                        val apkUri = FileProvider.getUriForFile(
                                                            this@MainActivity,
                                                            "com.familylink.buddy.child.fileprovider",
                                                            cacheFile
                                                        )
                                                        val installIntent = Intent(Intent.ACTION_VIEW).apply {
                                                            setDataAndType(apkUri, "application/vnd.android.package-archive")
                                                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                                        }
                                                        startActivity(installIntent)
                                                    }
                                                } catch (e: Exception) {
                                                    Log.e("MainActivity", "Error downloading update", e)
                                                    downloadProgress = -1f
                                                }
                                            }
                                        }
                                    },
                                    enabled = downloadProgress < 0f,
                                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
                                ) {
                                    Text(text = "Download & Installieren", color = Color.Black)
                                }
                            },
                            dismissButton = null
                        )
                    }

                    val familyData by repository.familyTimeData.collectAsState(initial = FamilyTimeData())
                    val volumeState by repository.volumeState.collectAsState(initial = VolumeState())
                    val timeBankState by repository.timeBankState.collectAsState(initial = TimeBankState())
                    var timeBankTasks by remember { mutableStateOf<List<BonusTask>>(emptyList()) }
                    var timeBankRewards by remember { mutableStateOf<List<RewardItem>>(emptyList()) }
                    
                    val showConfetti = remember { mutableStateOf(false) }
                    val particles = remember { mutableStateListOf<Particle>() }

                    var serviceRunning by remember { mutableStateOf(isServiceRunning()) }
                    val hasOverlayPermission by canDrawOverlaysState

                    var pairingCode by remember { mutableStateOf("Lade...") }
                    var qrBitmap by remember { mutableStateOf<android.graphics.Bitmap?>(null) }

                    LaunchedEffect(volumeState.deviceToken) {
                        val token = volumeState.deviceToken
                        if (token.isNotEmpty()) {
                            qrBitmap = QrCodeGenerator.generateQrCode(token)
                            
                            val code = Math.floor(100000 + Math.random() * 900000).toInt().toString()
                            pairingCode = code

                            try {
                                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                                val volumeReport = hashMapOf(
                                    "mediaVolume" to audioManager.getStreamVolume(AudioManager.STREAM_MUSIC),
                                    "ringtoneVolume" to audioManager.getStreamVolume(AudioManager.STREAM_RING),
                                    "alarmVolume" to audioManager.getStreamVolume(AudioManager.STREAM_ALARM),
                                    "maxMediaVolume" to audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
                                    "maxRingtoneVolume" to audioManager.getStreamMaxVolume(AudioManager.STREAM_RING),
                                    "maxAlarmVolume" to audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                                )

                                val db = FirebaseFirestore.getInstance()
                                val docData = hashMapOf(
                                    "fcmToken" to token,
                                    "deviceName" to "Felix",
                                    "createdAt" to com.google.firebase.firestore.FieldValue.serverTimestamp(),
                                    "volumeReport" to volumeReport
                                )
                                db.collection("pairing_codes").document(code).set(docData)
                                    .addOnSuccessListener {
                                        Log.d("MainActivity", "Pairing code registered directly with initial volume: $code")
                                    }
                                    .addOnFailureListener { e ->
                                        pairingCode = "Fehler"
                                        Log.e("MainActivity", "Pairing registration failed", e)
                                    }

                                // Add snap listeners for Time Coins features
                                db.collection("pairings").document(token)
                                    .addSnapshotListener { snapshot, _ ->
                                        if (snapshot != null && snapshot.exists()) {
                                            val balance = (snapshot.getLong("timeBankBalance") ?: 0L).toInt()
                                            val enabled = snapshot.getBoolean("timeBankEnabled") ?: false
                                            val visible = snapshot.getBoolean("timeBankChildVisible") ?: false
                                            lifecycleScopeLaunch {
                                                repository.updateTimeBankState(TimeBankState(enabled, visible, balance))
                                            }
                                        }
                                    }

                                db.collection("pairings").document(token).collection("time_bank_tasks")
                                    .orderBy("sortOrder")
                                    .addSnapshotListener { snapshot, _ ->
                                        if (snapshot != null) {
                                            timeBankTasks = snapshot.documents.mapNotNull { doc ->
                                                doc.toObject(BonusTask::class.java)?.copy(id = doc.id)
                                            }
                                        }
                                    }

                                db.collection("pairings").document(token).collection("time_bank_rewards")
                                    .orderBy("sortOrder")
                                    .addSnapshotListener { snapshot, _ ->
                                        if (snapshot != null) {
                                            timeBankRewards = snapshot.documents.mapNotNull { doc ->
                                                doc.toObject(RewardItem::class.java)?.copy(id = doc.id)
                                            }
                                        }
                                    }
                            } catch (e: Exception) {
                                pairingCode = "Fehler"
                                Log.e("MainActivity", "Firestore write error", e)
                            }
                        }
                    }

                    // Auto-start service on app open for real-time widget testing
                    LaunchedEffect(Unit) {
                        startUpdateService()
                    }

                    val context = LocalContext.current
                    DisposableEffect(context) {
                        val receiver = object : android.content.BroadcastReceiver() {
                            override fun onReceive(ctx: Context, intent: Intent) {
                                if (intent.action == WidgetUpdateService.ACTION_COIN_AWARD) {
                                    showConfetti.value = true
                                    playCoinSound()
                                }
                            }
                        }
                        val filter = android.content.IntentFilter(WidgetUpdateService.ACTION_COIN_AWARD)
                        ContextCompat.registerReceiver(context, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
                        onDispose {
                            context.unregisterReceiver(receiver)
                        }
                    }

                    LaunchedEffect(showConfetti.value) {
                        if (showConfetti.value) {
                            particles.clear()
                            for (i in 0..100) {
                                particles.add(Particle(
                                    x = (100..900).random().toFloat(),
                                    y = -50f,
                                    vx = (-6..6).random().toFloat(),
                                    vy = (8..22).random().toFloat(),
                                    size = (15..35).random().toFloat(),
                                    color = listOf(Color(0xFFFFD700), Color(0xFFFFC000), Color(0xFFFFA500), Color(0xFFFFE082)).random()
                                ))
                            }
                            val startTime = System.currentTimeMillis()
                            while (System.currentTimeMillis() - startTime < 2500) {
                                delay(16)
                                particles.forEach { it.update() }
                            }
                            showConfetti.value = false
                        }
                    }

                    var wasVisibleBefore by remember { mutableStateOf(false) }
                    LaunchedEffect(timeBankState.isChildVisible) {
                        if (timeBankState.isChildVisible && !wasVisibleBefore) {
                            showConfetti.value = true
                            playCoinSound()
                            wasVisibleBefore = true
                        } else if (!timeBankState.isChildVisible) {
                            wasVisibleBefore = false
                        }
                    }

                    Box(modifier = Modifier.fillMaxSize()) {
                        Column(
                            modifier = Modifier
                                .fillMaxSize()
                                .verticalScroll(rememberScrollState())
                                .padding(24.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center,
                            modifier = Modifier.padding(top = 16.dp, bottom = 8.dp)
                        ) {
                            Text(
                                text = stringResource(R.string.main_title),
                                fontSize = 28.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color(0xFF66FCF1)
                            )
                            Spacer(modifier = Modifier.width(10.dp))
                            Surface(
                                shape = RoundedCornerShape(12.dp),
                                color = Color(0xFF45A29E).copy(alpha = 0.25f),
                                border = androidx.compose.foundation.BorderStroke(1.dp, Color(0xFF66FCF1))
                            ) {
                                Text(
                                    text = "v${BuildConfig.VERSION_NAME}",
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color(0xFF66FCF1),
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                                )
                            }
                        }

                        Text(
                            text = stringResource(R.string.main_subtitle),
                            fontSize = 14.sp,
                            color = Color(0xFFC5C6C7),
                            modifier = Modifier.padding(bottom = 24.dp)
                        )

                        // Overlay Permission Warning Card
                        if (!hasOverlayPermission) {
                            Card(
                                modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
                                shape = RoundedCornerShape(12.dp),
                                colors = CardDefaults.cardColors(containerColor = Color(0xFF3A1C20))
                            ) {
                                Column(modifier = Modifier.padding(16.dp)) {
                                    Text(
                                        text = stringResource(R.string.perm_title),
                                        fontSize = 16.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = Color(0xFFEF4444)
                                    )
                                    Text(
                                        text = stringResource(R.string.perm_desc),
                                        fontSize = 13.sp,
                                        color = Color(0xFFE2E8F0),
                                        modifier = Modifier.padding(top = 4.dp, bottom = 12.dp)
                                    )
                                    Button(
                                        onClick = {
                                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                                val intent = Intent(
                                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                                    Uri.parse("package:$packageName")
                                                )
                                                startActivity(intent)
                                            }
                                        },
                                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFEF4444))
                                    ) {
                                        Text(stringResource(R.string.perm_btn), color = Color.White)
                                    }
                                }
                            }
                        }

                        // Usage Access Permission Warning Card
                        val hasUsageAccess by hasUsageAccessState
                        if (!hasUsageAccess) {
                            Card(
                                modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
                                shape = RoundedCornerShape(12.dp),
                                colors = CardDefaults.cardColors(containerColor = Color(0xFF3A2D1C))
                            ) {
                                Column(modifier = Modifier.padding(16.dp)) {
                                    Text(
                                        text = "Nutzungsdaten-Zugriff benötigt",
                                        fontSize = 16.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = Color(0xFFF59E0B)
                                    )
                                    Text(
                                        text = "Diese App benötigt Zugriff auf die Nutzungsstatistiken, um installierte Apps und deren Nutzungszeiten im Widget anzuzeigen und Zeitlimits durchzusetzen.",
                                        fontSize = 13.sp,
                                        color = Color(0xFFE2E8F0),
                                        modifier = Modifier.padding(top = 4.dp, bottom = 12.dp)
                                    )
                                    Button(
                                        onClick = {
                                            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                                                data = Uri.parse("package:$packageName")
                                            }
                                            try {
                                                startActivity(intent)
                                            } catch (e: Exception) {
                                                startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                                            }
                                        },
                                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF59E0B))
                                    ) {
                                        Text("Zugriff erlauben", color = Color.White)
                                    }
                                }
                            }
                        }

                        // Info Card
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(12.dp),
                            colors = CardDefaults.cardColors(containerColor = Color(0xFF1F2833))
                        ) {
                            Column(modifier = Modifier.padding(16.dp)) {
                                Text(
                                    text = stringResource(R.string.main_remaining, familyData.totalRemainingMinutes),
                                    fontSize = 18.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color.White
                                )
                                Text(
                                    text = stringResource(R.string.main_limit, familyData.totalLimitMinutes),
                                    fontSize = 14.sp,
                                    color = Color(0xFFC5C6C7),
                                    modifier = Modifier.padding(top = 4.dp)
                                )

                                Spacer(modifier = Modifier.height(12.dp))

                                familyData.appUsages.filter { isPackageInstalled(applicationContext, it.packageName) }.forEach { app ->
                                    Row(
                                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                                        horizontalArrangement = Arrangement.SpaceBetween
                                    ) {
                                        Text(text = app.appName, color = Color(0xFF66FCF1))
                                        Text(
                                            text = stringResource(R.string.main_app_status, app.remainingMinutes.toString(), app.usedMinutes, app.limitMinutes),
                                            color = Color.White
                                        )
                                    }
                                }
                            }
                        }

                        // 1. Time Bank Card (only when timeBankState.isChildVisible is true)
                        if (timeBankState.isChildVisible) {
                            var coinRotation by remember { mutableStateOf(0f) }
                            val rotationAnim by animateFloatAsState(
                                targetValue = coinRotation,
                                animationSpec = tween(durationMillis = 600, easing = FastOutSlowInEasing)
                            )
                            var activeTimerTaskId by remember { mutableStateOf<String?>(null) }
                            var timerSecondsRemaining by remember { mutableStateOf(0) }

                            // Timer countdown execution
                            LaunchedEffect(activeTimerTaskId, timerSecondsRemaining) {
                                if (activeTimerTaskId != null && timerSecondsRemaining > 0) {
                                    delay(1000L)
                                    timerSecondsRemaining--
                                    if (timerSecondsRemaining == 0) {
                                        // Complete task
                                        val task = timeBankTasks.firstOrNull { it.id == activeTimerTaskId }
                                        if (task != null) {
                                            val db = FirebaseFirestore.getInstance()
                                            val token = volumeState.deviceToken
                                            if (token.isNotEmpty()) {
                                                val pairingDoc = db.collection("pairings").document(token)
                                                val txRef = pairingDoc.collection("time_bank_transactions").document()
                                                val batch = db.batch()
                                                batch.update(pairingDoc, "timeBankBalance", com.google.firebase.firestore.FieldValue.increment(task.reward.toLong()))
                                                batch.set(txRef, hashMapOf(
                                                    "timestamp" to com.google.firebase.firestore.FieldValue.serverTimestamp(),
                                                    "type" to "TASK_COMPLETE",
                                                    "amount" to task.reward,
                                                    "description" to task.title,
                                                    "emoji" to task.emoji,
                                                    "awardedBy" to "timer",
                                                    "date" to java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault()).format(java.util.Date())
                                                ))
                                                batch.commit()
                                                playJingleSound()
                                                showConfetti.value = true
                                            }
                                        }
                                        activeTimerTaskId = null
                                    }
                                }
                            }

                            Card(
                                modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
                                shape = RoundedCornerShape(12.dp),
                                colors = CardDefaults.cardColors(containerColor = Color(0xFF1F2833))
                            ) {
                                Column(modifier = Modifier.padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text(
                                        text = stringResource(R.string.time_bank_card_title),
                                        fontSize = 18.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        color = Color.White,
                                        modifier = Modifier.align(Alignment.Start)
                                    )
                                    Spacer(modifier = Modifier.height(16.dp))

                                    // Fidget Coin Balance Circle
                                    Box(
                                        modifier = Modifier
                                            .size(110.dp)
                                            .rotate(rotationAnim)
                                            .background(
                                                Brush.radialGradient(
                                                    colors = listOf(Color(0xFFF59E0B), Color(0xFFD97706))
                                                ),
                                                shape = CircleShape
                                            )
                                            .clickable {
                                                coinRotation += 360f
                                                playCoinSound()
                                            },
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                            Text(
                                                text = "${timeBankState.balance}",
                                                fontSize = 32.sp,
                                                fontWeight = FontWeight.Bold,
                                                color = Color.White
                                            )
                                            Text(
                                                text = "Coins ⏳",
                                                fontSize = 12.sp,
                                                color = Color.White.copy(alpha = 0.8f),
                                                fontWeight = FontWeight.SemiBold
                                            )
                                        }
                                    }

                                    // Low Coins pulsing warning indicator
                                    if (timeBankState.balance in 1..5) {
                                        Spacer(modifier = Modifier.height(8.dp))
                                        Text(
                                            text = "Noch ${timeBankState.balance} Coins übrig! ⏳ Wieder aufladen?",
                                            color = Color(0xFFEF4444),
                                            fontSize = 12.sp,
                                            fontWeight = FontWeight.Bold
                                        )
                                    }

                                    Spacer(modifier = Modifier.height(24.dp))

                                    // Tasks section (max 3)
                                    Text(
                                        text = stringResource(R.string.time_bank_tasks_section),
                                        fontSize = 14.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        color = Color(0xFF66FCF1),
                                        modifier = Modifier.align(Alignment.Start)
                                    )
                                    Spacer(modifier = Modifier.height(8.dp))

                                    val visibleTasks = timeBankTasks.take(3)
                                    if (visibleTasks.isEmpty()) {
                                        Text(
                                            text = stringResource(R.string.time_bank_zero_coins),
                                            fontSize = 12.sp,
                                            color = Color(0xFFC5C6C7),
                                            modifier = Modifier.align(Alignment.Start)
                                        )
                                    } else {
                                        visibleTasks.forEach { task ->
                                            val isRunning = activeTimerTaskId == task.id
                                            Row(
                                                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                                                horizontalArrangement = Arrangement.SpaceBetween,
                                                verticalAlignment = Alignment.CenterVertically
                                            ) {
                                                Row(verticalAlignment = Alignment.CenterVertically) {
                                                    Text(text = task.emoji, fontSize = 20.sp)
                                                    Spacer(modifier = Modifier.width(8.dp))
                                                    Text(text = task.title, color = Color.White, fontSize = 13.sp)
                                                }
                                                if (task.hasDuration) {
                                                    Button(
                                                        onClick = {
                                                            if (isRunning) {
                                                                activeTimerTaskId = null
                                                            } else {
                                                                activeTimerTaskId = task.id
                                                                timerSecondsRemaining = task.durationMinutes * 60
                                                            }
                                                        },
                                                        colors = ButtonDefaults.buttonColors(
                                                            containerColor = if (isRunning) Color(0xFFEF4444) else Color(0xFF45A29E)
                                                        ),
                                                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 2.dp),
                                                        modifier = Modifier.height(30.dp)
                                                    ) {
                                                        if (isRunning) {
                                                            val mins = timerSecondsRemaining / 60
                                                            val secs = timerSecondsRemaining % 60
                                                            Text(
                                                                text = String.format("%02d:%02d", mins, secs),
                                                                fontSize = 11.sp,
                                                                color = Color.White
                                                            )
                                                        } else {
                                                            Text(
                                                                text = "${task.durationMinutes} Min Start",
                                                                fontSize = 11.sp,
                                                                color = Color.White
                                                            )
                                                        }
                                                    }
                                                } else {
                                                    Button(
                                                        onClick = {
                                                            val db = FirebaseFirestore.getInstance()
                                                            val token = volumeState.deviceToken
                                                            if (token.isNotEmpty()) {
                                                                    val pairingDoc = db.collection("pairings").document(token)
                                                                    val txRef = pairingDoc.collection("time_bank_transactions").document()
                                                                    val batch = db.batch()
                                                                    batch.update(pairingDoc, "timeBankBalance", com.google.firebase.firestore.FieldValue.increment(task.reward.toLong()))
                                                                    batch.set(txRef, hashMapOf(
                                                                        "timestamp" to com.google.firebase.firestore.FieldValue.serverTimestamp(),
                                                                        "type" to "TASK_COMPLETE",
                                                                        "amount" to task.reward,
                                                                        "description" to task.title,
                                                                        "emoji" to task.emoji,
                                                                        "awardedBy" to "child",
                                                                        "date" to java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault()).format(java.util.Date())
                                                                    ))
                                                                    batch.commit()
                                                                    playJingleSound()
                                                                    showConfetti.value = true
                                                            }
                                                        },
                                                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF45A29E)),
                                                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 2.dp),
                                                        modifier = Modifier.height(30.dp)
                                                    ) {
                                                        Text(
                                                            text = "+${task.reward} Coins",
                                                            fontSize = 11.sp,
                                                            color = Color.White
                                                        )
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Spacer(modifier = Modifier.height(16.dp))

                                    // Rewards section (max 3)
                                    Text(
                                        text = stringResource(R.string.time_bank_rewards_section),
                                        fontSize = 14.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        color = Color(0xFF66FCF1),
                                        modifier = Modifier.align(Alignment.Start)
                                    )
                                    Spacer(modifier = Modifier.height(8.dp))

                                    val visibleRewards = timeBankRewards.take(3)
                                    if (visibleRewards.isEmpty()) {
                                        Text(
                                            text = "Keine Belohnungen vorhanden.",
                                            fontSize = 12.sp,
                                            color = Color(0xFFC5C6C7),
                                            modifier = Modifier.align(Alignment.Start)
                                        )
                                    } else {
                                        visibleRewards.forEach { reward ->
                                            val canAfford = timeBankState.balance >= reward.cost
                                            Row(
                                                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                                                horizontalArrangement = Arrangement.SpaceBetween,
                                                verticalAlignment = Alignment.CenterVertically
                                            ) {
                                                Row(verticalAlignment = Alignment.CenterVertically) {
                                                    Text(text = reward.emoji, fontSize = 20.sp)
                                                    Spacer(modifier = Modifier.width(8.dp))
                                                    Text(text = reward.title, color = Color.White, fontSize = 13.sp)
                                                }
                                                Button(
                                                    onClick = {
                                                        val db = FirebaseFirestore.getInstance()
                                                        val token = volumeState.deviceToken
                                                        if (token.isNotEmpty() && canAfford) {
                                                            val pairingDoc = db.collection("pairings").document(token)
                                                            val txRef = pairingDoc.collection("time_bank_transactions").document()
                                                            val claimRef = pairingDoc.collection("time_bank_claims").document()
                                                            
                                                            val batch = db.batch()
                                                            batch.update(pairingDoc, "timeBankBalance", com.google.firebase.firestore.FieldValue.increment(-reward.cost.toLong()))
                                                            batch.update(pairingDoc, "pendingClaimsCount", com.google.firebase.firestore.FieldValue.increment(1))
                                                            batch.set(txRef, hashMapOf(
                                                                "timestamp" to com.google.firebase.firestore.FieldValue.serverTimestamp(),
                                                                "type" to "SPEND",
                                                                "amount" to -reward.cost,
                                                                "description" to reward.title,
                                                                "emoji" to reward.emoji,
                                                                "awardedBy" to "child",
                                                                "date" to java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault()).format(java.util.Date())
                                                            ))
                                                            batch.set(claimRef, hashMapOf(
                                                                "rewardId" to reward.id,
                                                                "title" to reward.title,
                                                                "emoji" to reward.emoji,
                                                                "cost" to reward.cost,
                                                                "status" to "PENDING",
                                                                "claimedAt" to com.google.firebase.firestore.FieldValue.serverTimestamp()
                                                            ))
                                                            batch.commit()
                                                            playCoinSound()
                                                            showConfetti.value = true
                                                        }
                                                    },
                                                    enabled = canAfford,
                                                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFD97706)),
                                                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 2.dp),
                                                    modifier = Modifier.height(30.dp)
                                                ) {
                                                    Text(
                                                        text = "${reward.cost} Coins",
                                                        fontSize = 11.sp,
                                                        color = Color.White
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Spacer(modifier = Modifier.height(16.dp))

                        // Setup Guide Card: System Checklist (Accessibility, Family Link, Battery, DND)
                        SetupGuideCard(
                            modifier = Modifier.fillMaxWidth()
                        )

                        Spacer(modifier = Modifier.height(16.dp))

                        // Volume & Pairing Card
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(12.dp),
                            colors = CardDefaults.cardColors(containerColor = Color(0xFF1F2833))
                        ) {
                            Column(modifier = Modifier.padding(16.dp)) {
                                Text(
                                    text = stringResource(R.string.volume_card_title),
                                    fontSize = 18.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color.White
                                )
                                Spacer(modifier = Modifier.height(8.dp))
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text(text = stringResource(R.string.volume_media_label), color = Color(0xFFC5C6C7))
                                    Text(
                                        text = if (volumeState.mediaVolume >= 0) "${volumeState.mediaVolume}/${volumeState.maxMediaVolume}" else "N/A",
                                        color = Color.White
                                    )
                                }
                                Row(
                                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text(text = stringResource(R.string.volume_ringtone_label), color = Color(0xFFC5C6C7))
                                    Text(
                                        text = if (volumeState.ringtoneVolume >= 0) "${volumeState.ringtoneVolume}/${volumeState.maxRingtoneVolume}" else "N/A",
                                        color = Color.White
                                    )
                                }
                                Row(
                                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text(text = stringResource(R.string.volume_alarm_label), color = Color(0xFFC5C6C7))
                                    Text(
                                        text = if (volumeState.alarmVolume >= 0) "${volumeState.alarmVolume}/${volumeState.maxAlarmVolume}" else "N/A",
                                        color = Color.White
                                    )
                                }

                                Spacer(modifier = Modifier.height(16.dp))
                                Text(
                                    text = stringResource(R.string.volume_device_id_label),
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color(0xFF66FCF1)
                                )
                                Spacer(modifier = Modifier.height(4.dp))
                                val token = volumeState.deviceToken
                                val displayToken = if (token.isNotEmpty()) {
                                    if (token.length > 25) token.substring(0, 10) + "..." + token.substring(token.length - 10) else token
                                } else {
                                    "Lade Token..."
                                }
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text(
                                        text = displayToken,
                                        color = Color.White,
                                        fontSize = 13.sp,
                                        modifier = Modifier.weight(1f)
                                    )
                                    if (token.isNotEmpty()) {
                                        Button(
                                            onClick = {
                                                val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                                val clip = ClipData.newPlainText("FCM Device Token", token)
                                                clipboard.setPrimaryClip(clip)
                                                Toast.makeText(this@MainActivity, "Kopiert!", Toast.LENGTH_SHORT).show()
                                            },
                                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF45A29E)),
                                            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                                            modifier = Modifier.height(32.dp)
                                        ) {
                                            Text(stringResource(R.string.volume_copy_btn), fontSize = 11.sp, color = Color.White)
                                        }
                                    }
                                }

                                if (qrBitmap != null) {
                                    Spacer(modifier = Modifier.height(16.dp))
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.Center,
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        androidx.compose.foundation.Image(
                                            bitmap = qrBitmap!!.asImageBitmap(),
                                            contentDescription = "QR Code Pairing",
                                            modifier = Modifier.size(130.dp).background(Color.White).padding(8.dp)
                                        )
                                        Spacer(modifier = Modifier.width(16.dp))
                                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                            Text("6-stelliger Code:", color = Color(0xFFC5C6C7), fontSize = 13.sp)
                                            Text(
                                                text = pairingCode,
                                                color = Color(0xFF66FCF1),
                                                fontSize = 24.sp,
                                                fontWeight = FontWeight.Bold,
                                                modifier = Modifier.padding(top = 4.dp)
                                            )
                                        }
                                    }
                                }
                            }
                        }

                        Spacer(modifier = Modifier.height(16.dp))

                        // Walkie-Talkie Comms Card
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(12.dp),
                            colors = CardDefaults.cardColors(containerColor = Color(0xFF1F2833))
                        ) {
                            Column(modifier = Modifier.padding(16.dp)) {
                                Text(
                                    text = "📡 Walkie-Talkie",
                                    fontSize = 18.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color.White
                                )
                                Spacer(modifier = Modifier.height(8.dp))
                                Text(
                                    text = "Sende oder empfange hier Sprachnachrichten mit deinen Eltern.",
                                    fontSize = 13.sp,
                                    color = Color(0xFFC5C6C7)
                                )
                                Spacer(modifier = Modifier.height(12.dp))
                                Button(
                                    onClick = {
                                        val intent = Intent(applicationContext, CommsActivity::class.java)
                                        startActivity(intent)
                                    },
                                    modifier = Modifier.fillMaxWidth(),
                                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF6366F1))
                                ) {
                                    Text("Walkie-Talkie öffnen 🎙️", color = Color.White)
                                }
                            }
                        }

                        Spacer(modifier = Modifier.height(32.dp))

                        // Controls Block
                        Text(
                            text = stringResource(R.string.main_control_panel),
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                            modifier = Modifier.align(Alignment.Start)
                        )

                        Row(
                            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Button(
                                onClick = {
                                    scope.launch {
                                        val newData = familyData.copy(
                                            totalRemainingMinutes = (familyData.totalRemainingMinutes + 15).coerceAtMost(familyData.totalLimitMinutes)
                                        )
                                        repository.updateFamilyTimeData(newData)
                                        FamilyBuddyWidget().updateAll(applicationContext)
                                    }
                                },
                                modifier = Modifier.weight(1f),
                                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF45A29E))
                            ) {
                                Text(stringResource(R.string.btn_add_time))
                            }

                            Button(
                                onClick = {
                                    scope.launch {
                                        val newData = familyData.copy(
                                            totalRemainingMinutes = (familyData.totalRemainingMinutes - 15).coerceAtLeast(0)
                                        )
                                        repository.updateFamilyTimeData(newData)
                                        FamilyBuddyWidget().updateAll(applicationContext)
                                    }
                                },
                                modifier = Modifier.weight(1f),
                                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF45A29E))
                            ) {
                                Text(stringResource(R.string.btn_sub_time))
                            }
                        }

                        Row(
                            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Button(
                                onClick = {
                                    scope.launch {
                                        val newData = familyData.copy(
                                            totalRemainingMinutes = 3,
                                            appUsages = familyData.appUsages.map {
                                                it.copy(usedMinutes = it.limitMinutes - 3)
                                            }
                                        )
                                        repository.updateFamilyTimeData(newData)
                                        FamilyBuddyWidget().updateAll(applicationContext)
                                    }
                                },
                                modifier = Modifier.weight(1f),
                                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFE53935))
                            ) {
                                Text(stringResource(R.string.btn_mock_alert))
                            }

                            Button(
                                onClick = {
                                    val intent = Intent(applicationContext, WidgetUpdateService::class.java).apply {
                                        action = WidgetUpdateService.ACTION_MOCK_ROCKET
                                    }
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                        startForegroundService(intent)
                                    } else {
                                        startService(intent)
                                    }
                                },
                                modifier = Modifier.weight(1f),
                                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF6366F1))
                            ) {
                                Text(stringResource(R.string.btn_mock_rocket))
                            }
                        }

                        Row(
                            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Button(
                                onClick = {
                                    val intent = Intent(applicationContext, CommsActivity::class.java).apply {
                                        putExtra("action", "SIMULATE_RECEIVE")
                                    }
                                    startActivity(intent)
                                },
                                modifier = Modifier.fillMaxWidth(),
                                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF818CF8))
                            ) {
                                Text("Mock Walkie-Talkie Anruf 🎙️")
                            }
                        }

                        Spacer(modifier = Modifier.height(16.dp))

                        Button(
                            onClick = {
                                scope.launch {
                                    val reset = FamilyTimeData(
                                        totalRemainingMinutes = 60,
                                        totalLimitMinutes = 120,
                                        appUsages = listOf(
                                            AppUsage("com.google.android.youtube", "YouTube", 15, 30),
                                            AppUsage("com.mojang.minecraftpe", "Minecraft", 20, 60)
                                        )
                                    )
                                    repository.updateFamilyTimeData(reset)
                                    FamilyBuddyWidget().updateAll(applicationContext)
                                }
                            },
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF1F2833))
                        ) {
                            Text(stringResource(R.string.btn_reset_data), color = Color(0xFF66FCF1))
                        }

                        Spacer(modifier = Modifier.height(32.dp))

                        // Background Service Toggle
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column {
                                Text(stringResource(R.string.main_sync_title), color = Color.White, fontWeight = FontWeight.Bold)
                                Text(stringResource(R.string.main_sync_desc), fontSize = 11.sp, color = Color(0xFFC5C6C7))
                            }
                            Switch(
                                checked = serviceRunning,
                                onCheckedChange = { running ->
                                    if (running != serviceRunning) {
                                        serviceRunning = running
                                        if (running) {
                                            startUpdateService()
                                        } else {
                                            stopUpdateService()
                                        }
                                    }
                                },
                                colors = SwitchDefaults.colors(
                                    checkedThumbColor = Color(0xFF66FCF1),
                                    checkedTrackColor = Color(0xFF45A29E)
                                )
                            )
                        }

                        // Particle overlay Canvas
                        if (showConfetti.value) {
                            Canvas(modifier = Modifier.fillMaxSize()) {
                                particles.forEach { particle ->
                                    drawCircle(
                                        color = particle.color,
                                        radius = particle.size / 2f,
                                        center = androidx.compose.ui.geometry.Offset(particle.x, particle.y)
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    }

    private fun startUpdateService() {
        val intent = Intent(this, WidgetUpdateService::class.java).apply {
            action = WidgetUpdateService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun checkUsageAccessPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.noteOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            android.os.Process.myUid(),
            packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun refreshRealAppUsageData() {
        if (!checkUsageAccessPermission()) {
            return
        }

        lifecycleScopeLaunch {
            try {
                val currentData = repository.familyTimeData.first()
                val pm = packageManager
                
                val mainIntent = Intent(Intent.ACTION_MAIN, null).addCategory(Intent.CATEGORY_LAUNCHER)
                val resolvedInfos = pm.queryIntentActivities(mainIntent, 0)
                
                val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                val calendar = Calendar.getInstance()
                calendar.set(Calendar.HOUR_OF_DAY, 0)
                calendar.set(Calendar.MINUTE, 0)
                calendar.set(Calendar.SECOND, 0)
                val startTime = calendar.timeInMillis
                val endTime = System.currentTimeMillis()
                
                val usageStats = usageStatsManager.queryAndAggregateUsageStats(startTime, endTime)
                
                val excludedPackages = setOf(
                    "com.android.settings",
                    "com.android.vending",
                    "com.google.android.packageinstaller",
                    "com.android.contacts",
                    "com.google.android.contacts",
                    "com.android.dialer",
                    "com.google.android.dialer",
                    "com.android.deskclock",
                    "com.google.android.deskclock",
                    "com.android.calculator2",
                    "com.google.android.calculator",
                    "com.familylink.buddy.child",
                    "com.android.systemui",
                    "com.google.android.inputmethod.latin"
                )

                val filteredInfos = resolvedInfos.filter { resolveInfo ->
                    val pkgName = resolveInfo.activityInfo.packageName
                    if (excludedPackages.contains(pkgName)) return@filter false
                    
                    val appInfo = try {
                        pm.getApplicationInfo(pkgName, 0)
                    } catch (e: Exception) {
                        null
                    }
                    if (appInfo != null) {
                        val isSystemApp = (appInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                        if (isSystemApp) {
                            val allowedSystemPackages = listOf("youtube", "chrome", "gallery", "photos", "maps", "spotify", "anton")
                            return@filter allowedSystemPackages.any { pkgName.lowercase().contains(it) }
                        }
                    }
                    true
                }

                val updatedAppUsages = filteredInfos.map { resolveInfo ->
                    val pkgName = resolveInfo.activityInfo.packageName
                    val appLabel = resolveInfo.loadLabel(pm).toString()
                    
                    val timeInForegroundMs = usageStats[pkgName]?.totalTimeInForeground ?: 0L
                    val usedMin = (timeInForegroundMs / (1000 * 60)).toInt()
                    
                    val existing = currentData.appUsages.firstOrNull { it.packageName == pkgName }
                    val limitMin = existing?.limitMinutes ?: 1440
                    
                    AppUsage(
                        packageName = pkgName,
                        appName = appLabel,
                        usedMinutes = usedMin,
                        limitMinutes = limitMin
                    )
                }
                
                // Preserve existing app limits for apps that are not in the current launcher list (e.g. Minecraft or other configured limits)
                val updatedPackageNames = updatedAppUsages.map { it.packageName }.toSet()
                val preservedUsages = currentData.appUsages.filter { 
                    it.packageName !in updatedPackageNames && it.limitMinutes < 1440 
                }
                val finalAppUsages = updatedAppUsages + preservedUsages
                
                val newData = currentData.copy(appUsages = finalAppUsages)
                repository.updateFamilyTimeData(newData)
                FamilyBuddyWidget().updateAll(applicationContext)
                
                Log.d("MainActivity", "Successfully refreshed real app usages: ${updatedAppUsages.size} apps")
            } catch (e: Exception) {
                Log.e("MainActivity", "Error refreshing app usages", e)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        canDrawOverlaysState.value = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
        hasUsageAccessState.value = checkUsageAccessPermission()
        if (hasUsageAccessState.value) {
            refreshRealAppUsageData()
        }
    }

    private fun stopUpdateService() {
        val intent = Intent(this, WidgetUpdateService::class.java).apply {
            action = WidgetUpdateService.ACTION_STOP
        }
        startService(intent)
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val permission = Manifest.permission.POST_NOTIFICATIONS
            if (ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(permission), 1)
            }
        }
    }

    private fun lifecycleScopeLaunch(block: suspend () -> Unit) {
        // Run simple launch block scoped to activity helper
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main).launch {
            block()
        }
    }

    private fun updateLocalVolumeState() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val state = VolumeState(
            mediaVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC),
            ringtoneVolume = audioManager.getStreamVolume(AudioManager.STREAM_RING),
            alarmVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM),
            maxMediaVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
            maxRingtoneVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_RING),
            maxAlarmVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM),
            isMuted = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC) == 0
        )
        lifecycleScopeLaunch {
            repository.updateVolumeState(state)
        }
    }

    private fun isPackageInstalled(context: Context, packageName: String): Boolean {
        if (packageName.isEmpty()) return false
        return try {
            context.packageManager.getPackageInfo(packageName, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }
}
