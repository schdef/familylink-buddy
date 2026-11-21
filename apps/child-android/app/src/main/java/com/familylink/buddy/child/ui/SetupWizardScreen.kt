package com.familylink.buddy.child.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.familylink.buddy.child.BuildConfig
import com.familylink.buddy.child.R
import com.familylink.buddy.child.data.FamilyTimeRepository
import com.familylink.buddy.child.data.QrCodeGenerator
import com.familylink.buddy.child.data.SetupStateDetector
import com.familylink.buddy.child.data.UpdateManager
import com.familylink.buddy.child.service.LocalHttpServer
import com.familylink.buddy.child.service.WifiAccessibilityHelperService
import kotlinx.coroutines.launch

private const val PREFS_NAME = "setup_wizard_prefs"
private const val KEY_RESTRICTED_SETTINGS_CONFIRMED = "key_restricted_settings_confirmed"

/**
 * Intuitive, non-tech-friendly Setup Wizard Screen guiding parents through
 * Android 13/14/15 system permissions, anti-tamper protection, and QR code pairing.
 */
@Composable
fun SetupWizardScreen(
    repository: FamilyTimeRepository,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()

    val prefs = remember { context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE) }

    // Live States
    var isAccessibilityActive by remember {
        mutableStateOf(SetupGuideHelper.isAccessibilityServiceEnabled(context) || WifiAccessibilityHelperService.instance != null)
    }
    var isBatteryExempt by remember {
        mutableStateOf(SetupGuideHelper.isBatteryOptimizationIgnored(context))
    }
    var isRestrictedSettingsUnlocked by remember {
        val defaultVal = !SetupStateDetector.isAndroid13OrHigher()
        mutableStateOf(prefs.getBoolean(KEY_RESTRICTED_SETTINGS_CONFIRMED, defaultVal))
    }
    var isWifiActive by remember {
        mutableStateOf(isWifiConnected(context))
    }
    var isCameraGranted by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        )
    }

    val cameraPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        isCameraGranted = isGranted
    }

    var isCallLogGranted by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED
        )
    }

    val callLogPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        isCallLogGranted = permissions[Manifest.permission.READ_CALL_LOG] == true &&
                permissions[Manifest.permission.READ_CONTACTS] == true
    }

    var isNotificationListenerActive by remember {
        mutableStateOf(
            NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)
        )
    }

    // Refresh states when returning from Android system settings
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                isAccessibilityActive = SetupGuideHelper.isAccessibilityServiceEnabled(context) || WifiAccessibilityHelperService.instance != null
                isBatteryExempt = SetupGuideHelper.isBatteryOptimizationIgnored(context)
                isWifiActive = isWifiConnected(context)
                isCameraGranted = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
                isCallLogGranted = ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED &&
                        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED
                isNotificationListenerActive = NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)
                if (!SetupStateDetector.isAndroid13OrHigher()) {
                    isRestrictedSettingsUnlocked = true
                }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    // Pairing Info & QR Code
    var deviceToken by remember { mutableStateOf("") }
    var deviceId by remember { mutableStateOf("") }
    var deviceName by remember { mutableStateOf("") }
    var localIp by remember { mutableStateOf("127.0.0.1") }
    var qrBitmap by remember { mutableStateOf<android.graphics.Bitmap?>(null) }
    var pairingCode by remember { mutableStateOf("------") }

    LaunchedEffect(Unit) {
        LocalHttpServer.startServer(context, repository)
        val token = repository.getOrCreateDeviceToken()
        deviceToken = token
        deviceId = repository.getDeviceIdSync()
        deviceName = QrCodeGenerator.getDeviceName(context)
        localIp = QrCodeGenerator.getLocalIpAddress(context)
        pairingCode = if (token.length >= 6) token.take(6).uppercase() else "123456"

        val payload = QrCodeGenerator.createPairingPayload(
            deviceId = deviceId,
            deviceName = deviceName,
            ip = localIp,
            port = 8085,
            token = token
        )
        qrBitmap = QrCodeGenerator.generateQrCode(payload, size = 512)
    }

    // PIN State
    val parentPin by repository.parentPin.collectAsState(initial = null)
    var showPinChangeDialog by remember { mutableStateOf(false) }

    // App Updater State
    var isCheckingUpdate by remember { mutableStateOf(false) }
    var showUpdateDialog by remember { mutableStateOf(false) }
    var updateDownloadUrl by remember { mutableStateOf("") }
    var updateVersionName by remember { mutableStateOf("") }
    var downloadProgress by remember { mutableStateOf(-1f) }
    var showUpToDateDialog by remember { mutableStateOf(false) }
    var updateInfoMessage by remember { mutableStateOf("") }

    val completedStepsCount = (if (isRestrictedSettingsUnlocked) 1 else 0) +
            (if (isAccessibilityActive) 1 else 0) +
            (if (isBatteryExempt) 1 else 0) +
            (if (isCameraGranted) 1 else 0) +
            (if (isWifiActive) 1 else 0)

    val progressPercent = SetupStateDetector.calculateProgressPercentage(completedStepsCount, 5)
    val isAllStepsDone = completedStepsCount == 5

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = Color(0xFF0B0C10)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Top Navigation Bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp, bottom = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                OutlinedButton(
                    onClick = onDismiss,
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = Color(0xFF66FCF1))
                ) {
                    Text(stringResource(R.string.setup_wizard_back), fontSize = 13.sp)
                }

                Surface(
                    shape = RoundedCornerShape(12.dp),
                    color = Color(0xFF45A29E).copy(alpha = 0.25f),
                    border = androidx.compose.foundation.BorderStroke(1.dp, Color(0xFF66FCF1))
                ) {
                    Text(
                        text = stringResource(R.string.setup_wizard_parent_mode),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF66FCF1),
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp)
                    )
                }
            }

            // Title & Subtitle
            Text(
                text = stringResource(R.string.setup_wizard_title),
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF66FCF1),
                textAlign = TextAlign.Center
            )
            Text(
                text = stringResource(R.string.setup_wizard_subtitle),
                fontSize = 13.sp,
                color = Color(0xFFC5C6C7),
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 4.dp, bottom = 18.dp)
            )

            // Progress Banner
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 20.dp),
                shape = RoundedCornerShape(14.dp),
                color = if (isAllStepsDone) Color(0xFF064E3B).copy(alpha = 0.7f) else Color(0xFF1F2833)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column {
                        Text(
                            text = if (isAllStepsDone) {
                                stringResource(R.string.setup_wizard_complete)
                            } else {
                                stringResource(R.string.setup_wizard_progress, completedStepsCount, 5)
                            },
                            fontWeight = FontWeight.Bold,
                            fontSize = 14.sp,
                            color = if (isAllStepsDone) Color(0xFF10B981) else Color.White
                        )
                        Text(
                            text = if (isAllStepsDone) {
                                stringResource(R.string.setup_wizard_complete_desc)
                            } else {
                                stringResource(R.string.setup_wizard_steps_desc)
                            },
                            fontSize = 12.sp,
                            color = Color(0xFFC5C6C7)
                        )
                    }

                    Surface(
                        shape = RoundedCornerShape(12.dp),
                        color = if (isAllStepsDone) Color(0xFF10B981) else Color(0xFF45A29E).copy(alpha = 0.3f)
                    ) {
                        Text(
                            text = "$progressPercent%",
                            fontWeight = FontWeight.Bold,
                            fontSize = 13.sp,
                            color = if (isAllStepsDone) Color.Black else Color(0xFF66FCF1),
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)
                        )
                    }
                }
            }

            // ==========================================
            // STEP 1: Unlock Security Settings
            // ==========================================
            val isAndroid13Plus = SetupStateDetector.isAndroid13OrHigher()
            WizardStepCard(
                stepNumber = 1,
                title = stringResource(R.string.wizard_step1_title),
                subtitle = if (isAndroid13Plus) {
                    stringResource(R.string.wizard_step1_subtitle_a13)
                } else {
                    stringResource(R.string.wizard_step1_subtitle_legacy)
                },
                description = stringResource(R.string.wizard_step1_desc),
                isCompleted = isRestrictedSettingsUnlocked,
                primaryButtonText = stringResource(R.string.wizard_step1_btn),
                onPrimaryClick = {
                    WifiAccessibilityHelperService.unlockAntiTamper()
                    try {
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:${context.packageName}")
                        ).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        context.startActivity(intent)
                    } catch (e: Exception) {
                        Toast.makeText(context, context.getString(R.string.wizard_step1_toast_error), Toast.LENGTH_SHORT).show()
                    }
                },
                secondaryButtonText = if (isAndroid13Plus && !isRestrictedSettingsUnlocked) stringResource(R.string.wizard_step1_btn_done) else null,
                onSecondaryClick = {
                    isRestrictedSettingsUnlocked = true
                    prefs.edit().putBoolean(KEY_RESTRICTED_SETTINGS_CONFIRMED, true).apply()
                }
            )

            Spacer(modifier = Modifier.height(16.dp))

            // ==========================================
            // STEP 2: Enable Accessibility Service
            // ==========================================
            WizardStepCard(
                stepNumber = 2,
                title = stringResource(R.string.wizard_step2_title),
                subtitle = stringResource(R.string.wizard_step2_subtitle),
                description = stringResource(R.string.wizard_step2_desc),
                isCompleted = isAccessibilityActive,
                primaryButtonText = if (isAccessibilityActive) {
                    stringResource(R.string.wizard_step2_btn_active)
                } else {
                    stringResource(R.string.wizard_step2_btn_enable)
                },
                onPrimaryClick = {
                    if (!isAccessibilityActive) {
                        WifiAccessibilityHelperService.unlockAntiTamper()
                        try {
                            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            context.startActivity(intent)
                        } catch (e: Exception) {
                            Toast.makeText(context, context.getString(R.string.wizard_step2_toast_error), Toast.LENGTH_SHORT).show()
                        }
                    }
                }
            )

            Spacer(modifier = Modifier.height(16.dp))

            // ==========================================
            // STEP 3: Disable Battery Optimization
            // ==========================================
            WizardStepCard(
                stepNumber = 3,
                title = stringResource(R.string.wizard_step3_title),
                subtitle = stringResource(R.string.wizard_step3_subtitle),
                description = stringResource(R.string.wizard_step3_desc),
                isCompleted = isBatteryExempt,
                primaryButtonText = if (isBatteryExempt) {
                    stringResource(R.string.wizard_step3_btn_exempt)
                } else {
                    stringResource(R.string.wizard_step3_btn_disable)
                },
                onPrimaryClick = {
                    if (!isBatteryExempt) {
                        WifiAccessibilityHelperService.unlockAntiTamper()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            try {
                                val intent = Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:${context.packageName}")
                                ).apply {
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                }
                                context.startActivity(intent)
                            } catch (e: Exception) {
                                try {
                                    val fallbackIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                    }
                                    context.startActivity(fallbackIntent)
                                } catch (ex: Exception) {
                                    Toast.makeText(context, context.getString(R.string.wizard_step3_toast_error), Toast.LENGTH_SHORT).show()
                                }
                            }
                        }
                    }
                }
            )

            Spacer(modifier = Modifier.height(16.dp))

            // ==========================================
            // Camera Permission Card
            // ==========================================
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = Color(0xFF1F2833))
            ) {
                Column(modifier = Modifier.padding(18.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            modifier = Modifier
                                .size(32.dp)
                                .clip(CircleShape)
                                .background(if (isCameraGranted) Color(0xFF10B981) else Color(0xFF6366F1)),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = if (isCameraGranted) "✓" else "📷",
                                fontSize = 15.sp
                            )
                        }

                        Spacer(modifier = Modifier.width(12.dp))

                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = stringResource(R.string.wizard_camera_card_title),
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                            Text(
                                text = if (isCameraGranted) {
                                    stringResource(R.string.wizard_camera_active)
                                } else {
                                    stringResource(R.string.wizard_camera_inactive)
                                },
                                fontSize = 12.sp,
                                color = if (isCameraGranted) Color(0xFF10B981) else Color(0xFFF59E0B)
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(10.dp))

                    Text(
                        text = stringResource(R.string.wizard_camera_desc),
                        fontSize = 12.5.sp,
                        lineHeight = 17.sp,
                        color = Color(0xFFCBD5E1)
                    )

                    Spacer(modifier = Modifier.height(14.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Button(
                            onClick = {
                                if (!isCameraGranted) {
                                    cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
                                }
                            },
                            enabled = !isCameraGranted,
                            shape = RoundedCornerShape(8.dp),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = if (isCameraGranted) Color(0xFF10B981) else Color(0xFF45A29E),
                                disabledContainerColor = Color(0xFF10B981).copy(alpha = 0.85f),
                                disabledContentColor = Color.Black
                            )
                        ) {
                            Text(
                                text = if (isCameraGranted) {
                                    stringResource(R.string.wizard_camera_btn_granted)
                                } else {
                                    stringResource(R.string.wizard_camera_btn_grant)
                                },
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (isCameraGranted) Color.Black else Color.White
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // ==========================================
            // Call Log Monitoring Card
            // ==========================================
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = Color(0xFF1F2833))
            ) {
                Column(modifier = Modifier.padding(18.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            modifier = Modifier
                                .size(32.dp)
                                .clip(CircleShape)
                                .background(if (isCallLogGranted) Color(0xFF10B981) else Color(0xFF3B82F6)),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = if (isCallLogGranted) "✓" else "📞",
                                fontSize = 15.sp
                            )
                        }

                        Spacer(modifier = Modifier.width(12.dp))

                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = stringResource(R.string.wizard_call_log_title),
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                            Text(
                                text = if (isCallLogGranted) {
                                    stringResource(R.string.wizard_call_log_active)
                                } else {
                                    stringResource(R.string.wizard_call_log_inactive)
                                },
                                fontSize = 12.sp,
                                color = if (isCallLogGranted) Color(0xFF10B981) else Color(0xFFF59E0B)
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(10.dp))

                    Text(
                        text = stringResource(R.string.wizard_call_log_desc),
                        fontSize = 12.5.sp,
                        lineHeight = 17.sp,
                        color = Color(0xFFCBD5E1)
                    )

                    Spacer(modifier = Modifier.height(14.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Button(
                            onClick = {
                                if (!isCallLogGranted) {
                                    callLogPermissionLauncher.launch(
                                        arrayOf(
                                            Manifest.permission.READ_CALL_LOG,
                                            Manifest.permission.READ_CONTACTS
                                        )
                                    )
                                }
                            },
                            enabled = !isCallLogGranted,
                            shape = RoundedCornerShape(8.dp),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = if (isCallLogGranted) Color(0xFF10B981) else Color(0xFF45A29E),
                                disabledContainerColor = Color(0xFF10B981).copy(alpha = 0.85f),
                                disabledContentColor = Color.Black
                            )
                        ) {
                            Text(
                                text = if (isCallLogGranted) {
                                    stringResource(R.string.wizard_call_log_btn_granted)
                                } else {
                                    stringResource(R.string.wizard_call_log_btn_grant)
                                },
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (isCallLogGranted) Color.Black else Color.White
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // ==========================================
            // Chat & Notification Monitoring Card
            // ==========================================
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = Color(0xFF1F2833))
            ) {
                Column(modifier = Modifier.padding(18.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            modifier = Modifier
                                .size(32.dp)
                                .clip(CircleShape)
                                .background(if (isNotificationListenerActive) Color(0xFF10B981) else Color(0xFF8B5CF6)),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = if (isNotificationListenerActive) "✓" else "💬",
                                fontSize = 15.sp
                            )
                        }

                        Spacer(modifier = Modifier.width(12.dp))

                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = stringResource(R.string.wizard_notification_title),
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                            Text(
                                text = if (isNotificationListenerActive) {
                                    stringResource(R.string.wizard_notification_active)
                                } else {
                                    stringResource(R.string.wizard_notification_inactive)
                                },
                                fontSize = 12.sp,
                                color = if (isNotificationListenerActive) Color(0xFF10B981) else Color(0xFFF59E0B)
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(10.dp))

                    Text(
                        text = stringResource(R.string.wizard_notification_desc),
                        fontSize = 12.5.sp,
                        lineHeight = 17.sp,
                        color = Color(0xFFCBD5E1)
                    )

                    Spacer(modifier = Modifier.height(14.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Button(
                            onClick = {
                                if (!isNotificationListenerActive) {
                                    WifiAccessibilityHelperService.unlockAntiTamper()
                                    try {
                                        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                        }
                                        context.startActivity(intent)
                                    } catch (e: Exception) {
                                        Toast.makeText(context, "Could not open notification settings", Toast.LENGTH_SHORT).show()
                                    }
                                }
                            },
                            enabled = !isNotificationListenerActive,
                            shape = RoundedCornerShape(8.dp),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = if (isNotificationListenerActive) Color(0xFF10B981) else Color(0xFF45A29E),
                                disabledContainerColor = Color(0xFF10B981).copy(alpha = 0.85f),
                                disabledContentColor = Color.Black
                            )
                        ) {
                            Text(
                                text = if (isNotificationListenerActive) {
                                    stringResource(R.string.wizard_notification_btn_enabled)
                                } else {
                                    stringResource(R.string.wizard_notification_btn_enable)
                                },
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (isNotificationListenerActive) Color.Black else Color.White
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // ==========================================
            // STEP 4: Connect Parent Phone
            // ==========================================
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = Color(0xFF1F2833))
            ) {
                Column(modifier = Modifier.padding(18.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            modifier = Modifier
                                .size(32.dp)
                                .clip(CircleShape)
                                .background(if (isWifiActive) Color(0xFF10B981) else Color(0xFFF59E0B)),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = if (isWifiActive) "✓" else "4",
                                fontWeight = FontWeight.Bold,
                                color = Color.Black,
                                fontSize = 15.sp
                            )
                        }

                        Spacer(modifier = Modifier.width(12.dp))

                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = stringResource(R.string.wizard_step4_card_title),
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                            Text(
                                text = stringResource(R.string.wizard_step4_subtitle),
                                fontSize = 12.sp,
                                color = Color(0xFFC5C6C7)
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(12.dp))

                    Text(
                        text = stringResource(R.string.wizard_step4_desc),
                        fontSize = 13.sp,
                        color = Color(0xFFE2E8F0)
                    )

                    Spacer(modifier = Modifier.height(14.dp))

                    // Wi-Fi Status Indicator
                    Surface(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(10.dp),
                        color = if (isWifiActive) Color(0xFF064E3B).copy(alpha = 0.5f) else Color(0xFF3A1C20)
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = if (isWifiActive) "🟢" else "⚠️",
                                fontSize = 14.sp
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = if (isWifiActive) {
                                    stringResource(R.string.wizard_step4_wifi_connected, localIp, 8085)
                                } else {
                                    stringResource(R.string.wizard_step4_no_wifi)
                                },
                                fontSize = 12.5.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = if (isWifiActive) Color(0xFF10B981) else Color(0xFFEF4444)
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(16.dp))

                    // High-Contrast QR Code Display
                    if (qrBitmap != null) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .wrapContentHeight(),
                            contentAlignment = Alignment.Center
                        ) {
                            Surface(
                                shape = RoundedCornerShape(16.dp),
                                color = Color.White,
                                border = androidx.compose.foundation.BorderStroke(3.dp, Color(0xFF66FCF1)),
                                modifier = Modifier.padding(vertical = 4.dp)
                            ) {
                                Image(
                                    bitmap = qrBitmap!!.asImageBitmap(),
                                    contentDescription = stringResource(R.string.wizard_step4_qr_desc),
                                    modifier = Modifier
                                        .size(190.dp)
                                        .padding(12.dp)
                                )
                            }
                        }

                        Spacer(modifier = Modifier.height(12.dp))

                        // Numeric Pairing Code and Connection Details
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column {
                                Text(
                                    text = stringResource(R.string.wizard_step4_code_label),
                                    fontSize = 12.sp,
                                    color = Color(0xFFC5C6C7)
                                )
                                Text(
                                    text = pairingCode,
                                    fontSize = 22.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color(0xFF66FCF1)
                                )
                            }

                            Column(horizontalAlignment = Alignment.End) {
                                Text(
                                    text = stringResource(R.string.wizard_step4_port_label, 8085),
                                    fontSize = 12.sp,
                                    color = Color(0xFFC5C6C7)
                                )
                                Text(
                                    text = deviceName,
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color.White
                                )
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // ==========================================
            // STEP 5: Anti-Tamper & 4-Digit Parent PIN
            // ==========================================
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = Color(0xFF1F2833))
            ) {
                Column(modifier = Modifier.padding(18.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            modifier = Modifier
                                .size(32.dp)
                                .clip(CircleShape)
                                .background(if (!parentPin.isNullOrBlank()) Color(0xFF10B981) else Color(0xFF6366F1)),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = "🔒",
                                fontSize = 16.sp
                            )
                        }

                        Spacer(modifier = Modifier.width(12.dp))

                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = stringResource(R.string.wizard_pin_card_title),
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                            Text(
                                text = if (!parentPin.isNullOrBlank()) {
                                    stringResource(R.string.wizard_pin_active)
                                } else {
                                    stringResource(R.string.wizard_pin_inactive)
                                },
                                fontSize = 12.sp,
                                color = if (!parentPin.isNullOrBlank()) Color(0xFF10B981) else Color(0xFFF59E0B)
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(10.dp))

                    Text(
                        text = stringResource(R.string.wizard_pin_desc),
                        fontSize = 12.5.sp,
                        color = Color(0xFFCBD5E1)
                    )

                    Spacer(modifier = Modifier.height(14.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End
                    ) {
                        if (!parentPin.isNullOrBlank()) {
                            OutlinedButton(
                                onClick = {
                                    scope.launch {
                                        repository.setParentPin(null)
                                        Toast.makeText(context, context.getString(R.string.wizard_pin_removed_toast), Toast.LENGTH_SHORT).show()
                                    }
                                },
                                shape = RoundedCornerShape(8.dp),
                                colors = ButtonDefaults.outlinedButtonColors(contentColor = Color(0xFFEF4444)),
                                modifier = Modifier.padding(end = 8.dp)
                            ) {
                                Text(stringResource(R.string.wizard_pin_remove_btn), fontSize = 12.sp)
                            }
                        }

                        Button(
                            onClick = {
                                showPinChangeDialog = true
                            },
                            shape = RoundedCornerShape(8.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF45A29E))
                        ) {
                            Text(
                                text = if (parentPin.isNullOrBlank()) {
                                    stringResource(R.string.wizard_pin_setup_btn)
                                } else {
                                    stringResource(R.string.wizard_pin_change_btn)
                                },
                                color = Color.White,
                                fontWeight = FontWeight.Bold,
                                fontSize = 12.sp
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // ==========================================
            // Permanent Accessibility (Survive Updates) via ADB
            // ==========================================
            PermanentAccessibilityCard()

            Spacer(modifier = Modifier.height(16.dp))

            // ==========================================
            // In-App Updates Card
            // ==========================================
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = Color(0xFF1F2833))
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "FamilyLink Buddy v${BuildConfig.VERSION_NAME}",
                            fontWeight = FontWeight.Bold,
                            fontSize = 14.sp,
                            color = Color.White
                        )
                        Text(
                            text = stringResource(R.string.update_dialog_title),
                            fontSize = 12.sp,
                            color = Color(0xFFC5C6C7)
                        )
                    }
                    Button(
                        onClick = {
                            scope.launch {
                                isCheckingUpdate = true
                                val release = UpdateManager.checkLatestRelease()
                                isCheckingUpdate = false
                                if (release != null) {
                                    if (release.isNewer) {
                                        updateVersionName = release.tagName
                                        updateDownloadUrl = release.downloadUrl
                                        downloadProgress = -1f
                                        showUpdateDialog = true
                                    } else {
                                        updateInfoMessage = context.getString(R.string.update_latest_desc, BuildConfig.VERSION_NAME)
                                        showUpToDateDialog = true
                                    }
                                } else {
                                    updateInfoMessage = context.getString(R.string.update_error_desc)
                                    showUpToDateDialog = true
                                }
                            }
                        },
                        shape = RoundedCornerShape(8.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF45A29E))
                    ) {
                        if (isCheckingUpdate) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), color = Color.White, strokeWidth = 2.dp)
                        } else {
                            Text(
                                text = stringResource(R.string.btn_check_updates),
                                color = Color.White,
                                fontWeight = FontWeight.Bold,
                                fontSize = 12.sp
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(28.dp))

            // Bottom Done Button
            Button(
                onClick = {
                    if (isAllStepsDone) {
                        prefs.edit().putBoolean("setup_completed", true).apply()
                        scope.launch {
                            repository.setSetupCompleted(true)
                        }
                    }
                    onDismiss()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF66FCF1))
            ) {
                Text(
                    text = if (isAllStepsDone) {
                        stringResource(R.string.wizard_finish_done)
                    } else {
                        stringResource(R.string.wizard_finish_back)
                    },
                    color = Color.Black,
                    fontWeight = FontWeight.Bold,
                    fontSize = 15.sp
                )
            }

            Spacer(modifier = Modifier.height(24.dp))
        }
    }

    // PIN Configuration Dialog
    if (showPinChangeDialog) {
        ParentPinDialog(
            mode = ParentPinDialogMode.SET_PIN,
            onPinSet = { newPin ->
                scope.launch {
                    repository.setParentPin(newPin)
                    showPinChangeDialog = false
                    Toast.makeText(context, context.getString(R.string.wizard_pin_saved_toast), Toast.LENGTH_SHORT).show()
                }
            },
            onDismiss = {
                showPinChangeDialog = false
            }
        )
    }

    if (showUpdateDialog) {
        AlertDialog(
            onDismissRequest = { if (downloadProgress < 0f) showUpdateDialog = false },
            title = {
                Text(
                    text = stringResource(R.string.update_dialog_title),
                    fontWeight = FontWeight.Bold,
                    fontSize = 20.sp,
                    color = Color(0xFF66FCF1)
                )
            },
            text = {
                Column {
                    Text(
                        text = stringResource(R.string.update_dialog_desc, updateVersionName),
                        fontSize = 14.sp,
                        color = Color.White
                    )
                    if (downloadProgress >= 0f) {
                        Spacer(modifier = Modifier.height(16.dp))
                        LinearProgressIndicator(
                            progress = { downloadProgress },
                            modifier = Modifier.fillMaxWidth(),
                            color = Color(0xFF66FCF1)
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = stringResource(R.string.update_downloading, (downloadProgress * 100).toInt()),
                            fontSize = 12.sp,
                            color = Color(0xFF45A29E)
                        )
                    }
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        if (downloadProgress < 0f) {
                            downloadProgress = 0f
                            scope.launch {
                                val success = UpdateManager.downloadAndInstallApk(context, updateDownloadUrl) { progress ->
                                    downloadProgress = progress
                                }
                                if (!success) {
                                    downloadProgress = -1f
                                    Toast.makeText(context, context.getString(R.string.update_error_title), Toast.LENGTH_SHORT).show()
                                }
                            }
                        }
                    },
                    enabled = downloadProgress < 0f,
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF66FCF1))
                ) {
                    Text(text = stringResource(R.string.btn_download_install), color = Color.Black)
                }
            },
            dismissButton = {
                if (downloadProgress < 0f) {
                    TextButton(onClick = { showUpdateDialog = false }) {
                        Text(text = stringResource(R.string.btn_cancel), color = Color(0xFFC5C6C7))
                    }
                }
            }
        )
    }

    if (showUpToDateDialog) {
        AlertDialog(
            onDismissRequest = { showUpToDateDialog = false },
            title = {
                Text(
                    text = stringResource(R.string.update_latest_title),
                    fontWeight = FontWeight.Bold,
                    fontSize = 18.sp,
                    color = Color(0xFF66FCF1)
                )
            },
            text = {
                Text(
                    text = updateInfoMessage,
                    fontSize = 14.sp,
                    color = Color.White
                )
            },
            confirmButton = {
                Button(
                    onClick = { showUpToDateDialog = false },
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF45A29E))
                ) {
                    Text(text = stringResource(R.string.btn_close), color = Color.White)
                }
            }
        )
    }
}

/**
 * Reusable Card for Wizard Steps 1 to 3.
 */
@Composable
private fun WizardStepCard(
    stepNumber: Int,
    title: String,
    subtitle: String,
    description: String,
    isCompleted: Boolean,
    primaryButtonText: String,
    onPrimaryClick: () -> Unit,
    secondaryButtonText: String? = null,
    onSecondaryClick: (() -> Unit)? = null
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = Color(0xFF1F2833))
    ) {
        Column(modifier = Modifier.padding(18.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Step badge
                Box(
                    modifier = Modifier
                        .size(32.dp)
                        .clip(CircleShape)
                        .background(
                            if (isCompleted) Color(0xFF10B981) else Color(0xFFF59E0B)
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = if (isCompleted) "✓" else "$stepNumber",
                        fontWeight = FontWeight.Bold,
                        color = Color.Black,
                        fontSize = 15.sp
                    )
                }

                Spacer(modifier = Modifier.width(12.dp))

                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "$stepNumber. $title",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                    Text(
                        text = subtitle,
                        fontSize = 12.sp,
                        color = if (isCompleted) Color(0xFF10B981) else Color(0xFFC5C6C7)
                    )
                }
            }

            Spacer(modifier = Modifier.height(10.dp))

            Text(
                text = description,
                fontSize = 12.5.sp,
                lineHeight = 17.sp,
                color = Color(0xFFE2E8F0)
            )

            Spacer(modifier = Modifier.height(14.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (secondaryButtonText != null && onSecondaryClick != null) {
                    OutlinedButton(
                        onClick = onSecondaryClick,
                        shape = RoundedCornerShape(8.dp),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Color(0xFF66FCF1)),
                        modifier = Modifier.padding(end = 8.dp)
                    ) {
                        Text(text = secondaryButtonText, fontSize = 12.sp)
                    }
                }

                Button(
                    onClick = onPrimaryClick,
                    enabled = !isCompleted || stepNumber == 1,
                    shape = RoundedCornerShape(8.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (isCompleted) Color(0xFF10B981) else Color(0xFF45A29E),
                        disabledContainerColor = Color(0xFF10B981).copy(alpha = 0.85f),
                        disabledContentColor = Color.Black
                    )
                ) {
                    Text(
                        text = primaryButtonText,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (isCompleted) Color.Black else Color.White
                    )
                }
            }
        }
    }
}

/**
 * Checks if device is currently connected to a Wi-Fi network.
 */
private fun isWifiConnected(context: Context): Boolean {
    return try {
        val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
        val network = connectivityManager.activeNetwork ?: return false
        val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    } catch (e: Exception) {
        false
    }
}
