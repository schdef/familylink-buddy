package com.familylink.buddy.child.ui

import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import android.widget.Toast
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver

/**
 * Helper object providing hardware and permission state checks and intent launchers
 * for the child companion setup checklist.
 */
object SetupGuideHelper {
    private const val TAG = "SetupGuideHelper"
    private const val PREFS_NAME = "setup_guide_prefs"
    private const val KEY_FAMILY_LINK_CONFIRMED = "key_family_link_always_allowed_confirmed"

    /**
     * Checks if the Accessibility Service is enabled in Android Settings.
     */
    fun isAccessibilityServiceEnabled(context: Context): Boolean {
        val targetService1 = "${context.packageName}/com.familylink.buddy.child.service.WifiAccessibilityHelperService"
        val targetService2 = "${context.packageName}/.service.WifiAccessibilityHelperService"

        val enabledServicesSetting = try {
            Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error checking accessibility services", e)
            null
        } ?: return false

        val colonSplitter = TextUtils.SimpleStringSplitter(':')
        colonSplitter.setString(enabledServicesSetting)

        while (colonSplitter.hasNext()) {
            val componentNameString = colonSplitter.next()
            if (componentNameString.equals(targetService1, ignoreCase = true) ||
                componentNameString.equals(targetService2, ignoreCase = true) ||
                (componentNameString.contains(context.packageName) && componentNameString.contains("WifiAccessibilityHelperService"))
            ) {
                return true
            }
        }
        return false
    }

    /**
     * Checks if battery optimization is disabled for this app.
     */
    fun isBatteryOptimizationIgnored(context: Context): Boolean {
        return try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                powerManager?.isIgnoringBatteryOptimizations(context.packageName) == true
            } else {
                true
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking battery optimization", e)
            false
        }
    }

    /**
     * Checks if Do Not Disturb (Notification Policy) access is granted.
     */
    fun isNotificationPolicyAccessGranted(context: Context): Boolean {
        return try {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                notificationManager?.isNotificationPolicyAccessGranted == true
            } else {
                true
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking notification policy access", e)
            false
        }
    }

    /**
     * Checks if the parent/user has acknowledged marking the app as "Always Allowed" in Google Family Link.
     */
    fun isFamilyLinkAlwaysAllowedAcknowledged(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_FAMILY_LINK_CONFIRMED, false)
    }

    /**
     * Persists the acknowledgment state for Google Family Link "Always Allowed".
     */
    fun setFamilyLinkAlwaysAllowedAcknowledged(context: Context, acknowledged: Boolean) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putBoolean(KEY_FAMILY_LINK_CONFIRMED, acknowledged).apply()
    }

    /**
     * Opens Android Accessibility Settings.
     */
    fun openAccessibilitySettings(context: Context) {
        try {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open accessibility settings", e)
            Toast.makeText(context, "Bedienungshilfen konnten nicht geöffnet werden.", Toast.LENGTH_SHORT).show()
        }
    }

    /**
     * Requests battery optimization exemption or opens battery settings.
     */
    fun requestIgnoreBatteryOptimization(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:${context.packageName}")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(intent)
            } catch (e: Exception) {
                Log.w(TAG, "Direct battery optimization request failed, falling back to general settings", e)
                try {
                    val fallbackIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    context.startActivity(fallbackIntent)
                } catch (fallbackEx: Exception) {
                    Log.e(TAG, "Failed to open battery optimization settings", fallbackEx)
                    Toast.makeText(context, "Akku-Einstellungen konnten nicht geöffnet werden.", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    /**
     * Opens Do Not Disturb / Notification Policy Access settings.
     */
    fun openNotificationPolicySettings(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to open notification policy access settings", e)
                Toast.makeText(context, "Nicht-Stören-Einstellungen konnten nicht geöffnet werden.", Toast.LENGTH_SHORT).show()
            }
        }
    }

    /**
     * Opens Android Application Details Settings.
     */
    fun openAppDetailsSettings(context: Context) {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open app details settings", e)
        }
    }
}

/**
 * Clean Jetpack Compose Dialog that presents the complete child companion setup checklist.
 */
@Composable
fun SetupGuideDialog(
    onDismissRequest: () -> Unit
) {
    Dialog(
        onDismissRequest = onDismissRequest,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.95f)
                .fillMaxHeight(0.90f)
                .padding(vertical = 16.dp),
            shape = RoundedCornerShape(20.dp),
            color = Color(0xFF161F28),
            tonalElevation = 8.dp
        ) {
            SetupGuideContent(
                isDialog = true,
                onDismiss = onDismissRequest
            )
        }
    }
}

/**
 * Embedded Jetpack Compose Card representing the Setup Guide Checklist.
 * Can be embedded directly inside MainActivity or any settings screen.
 */
@Composable
fun SetupGuideCard(
    modifier: Modifier = Modifier,
    onOpenFullDialog: (() -> Unit)? = null
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = Color(0xFF1F2833))
    ) {
        SetupGuideContent(
            modifier = Modifier.padding(16.dp),
            isDialog = false,
            onOpenFullDialog = onOpenFullDialog
        )
    }
}

/**
 * Internal reusable content layout for the Setup Guide checklist.
 */
@Composable
fun SetupGuideContent(
    modifier: Modifier = Modifier,
    isDialog: Boolean = false,
    onDismiss: (() -> Unit)? = null,
    onOpenFullDialog: (() -> Unit)? = null
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    var isAccessibilityEnabled by remember { mutableStateOf(SetupGuideHelper.isAccessibilityServiceEnabled(context)) }
    var isBatteryOptIgnored by remember { mutableStateOf(SetupGuideHelper.isBatteryOptimizationIgnored(context)) }
    var isDndGranted by remember { mutableStateOf(SetupGuideHelper.isNotificationPolicyAccessGranted(context)) }
    var isFamilyLinkAcknowledged by remember { mutableStateOf(SetupGuideHelper.isFamilyLinkAlwaysAllowedAcknowledged(context)) }

    // Re-evaluate states automatically when returning from system settings
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                isAccessibilityEnabled = SetupGuideHelper.isAccessibilityServiceEnabled(context)
                isBatteryOptIgnored = SetupGuideHelper.isBatteryOptimizationIgnored(context)
                isDndGranted = SetupGuideHelper.isNotificationPolicyAccessGranted(context)
                isFamilyLinkAcknowledged = SetupGuideHelper.isFamilyLinkAlwaysAllowedAcknowledged(context)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    val completedCount = (if (isAccessibilityEnabled) 1 else 0) +
            (if (isFamilyLinkAcknowledged) 1 else 0) +
            (if (isBatteryOptIgnored) 1 else 0) +
            (if (isDndGranted) 1 else 0)

    val allCompleted = completedCount == 4
    val scrollState = rememberScrollState()

    Column(
        modifier = modifier
            .fillMaxWidth()
            .then(if (isDialog) Modifier.padding(20.dp).verticalScroll(scrollState) else Modifier)
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "🛠️ Einrichtungs-Assistent",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFF66FCF1)
                )
                Text(
                    text = "Wichtige Systemrechte für Nachtruhe & Hintergrund",
                    fontSize = 13.sp,
                    color = Color(0xFFC5C6C7)
                )
            }

            if (isDialog && onDismiss != null) {
                IconButton(onClick = onDismiss) {
                    Text(text = "✕", fontSize = 18.sp, color = Color.White, fontWeight = FontWeight.Bold)
                }
            }
        }

        Spacer(modifier = Modifier.height(14.dp))

        // Progress bar indicator
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(10.dp),
            color = if (allCompleted) Color(0xFF064E3B).copy(alpha = 0.6f) else Color(0xFF0B0C10)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = if (allCompleted) "🎉 Alles vollständig eingerichtet!" else "Fortschritt: $completedCount von 4 erledigt",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (allCompleted) Color(0xFF10B981) else Color(0xFFE2E8F0)
                )

                Surface(
                    shape = RoundedCornerShape(12.dp),
                    color = if (allCompleted) Color(0xFF10B981) else Color(0xFF45A29E).copy(alpha = 0.25f)
                ) {
                    Text(
                        text = "${(completedCount * 100) / 4}%",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (allCompleted) Color.Black else Color(0xFF66FCF1),
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp)
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // 1. WLAN-Nachtruhe Helfer (Accessibility Service)
        SetupItemCard(
            itemNumber = 1,
            title = "WLAN-Nachtruhe Helfer",
            subtitle = "Bedienungshilfen-Dienst (Accessibility)",
            description = "Ermöglicht das automatische Umschalten des WLAN-Schalters zur Nachtruhe in den Schnelleinstellungen ohne Root.\n\nFalls ausgegraut: Auf 'App-Info' tippen -> oben rechts auf die 3 Punkte (⋮) -> 'Eingeschränkte Einstellungen zulassen'. Danach hier 'Aktivieren' wählen.",
            isCompleted = isAccessibilityEnabled,
            actionButtonText = if (isAccessibilityEnabled) "Aktiviert" else "Aktivieren",
            onActionClick = {
                SetupGuideHelper.openAccessibilitySettings(context)
            },
            secondaryActionText = "App-Info (3 Punkte)",
            onSecondaryActionClick = {
                SetupGuideHelper.openAppDetailsSettings(context)
            }
        )

        Spacer(modifier = Modifier.height(12.dp))

        // 2. Google Family Link: 'Immer zulassen'
        SetupItemCard(
            itemNumber = 2,
            title = "Google Family Link: 'Immer zulassen'",
            subtitle = "Wichtig gegen Schlafenszeit-Pausierung",
            description = "In der Family Link Eltern-App unter 'App-Limits' -> 'FamilyLink Buddy' auf 'Immer zulassen' setzen. Sonst wird die App während der Nachtruhe von Google pausiert und kann das WLAN nicht schalten.",
            isCompleted = isFamilyLinkAcknowledged,
            actionButtonText = if (isFamilyLinkAcknowledged) "Bestätigt ✓" else "Als erledigt markieren",
            onActionClick = {
                val newState = !isFamilyLinkAcknowledged
                isFamilyLinkAcknowledged = newState
                SetupGuideHelper.setFamilyLinkAlwaysAllowedAcknowledged(context, newState)
            },
            secondaryActionText = "App-Details",
            onSecondaryActionClick = {
                SetupGuideHelper.openAppDetailsSettings(context)
            }
        )

        Spacer(modifier = Modifier.height(12.dp))

        // 3. Akku-Optimierung deaktiviert
        SetupItemCard(
            itemNumber = 3,
            title = "Akku-Optimierung deaktivieren",
            subtitle = "Ununterbrochene Hintergrund-Ausführung",
            description = "Stellt sicher, dass das Android-System die App und deren Zeit-Alarme nicht schlafen legt oder vorzeitig beendet.",
            isCompleted = isBatteryOptIgnored,
            actionButtonText = if (isBatteryOptIgnored) "Deaktiviert" else "Ausnehmen",
            onActionClick = {
                SetupGuideHelper.requestIgnoreBatteryOptimization(context)
            }
        )

        Spacer(modifier = Modifier.height(12.dp))

        // 4. Nicht-Stören-Zugriff (DND)
        SetupItemCard(
            itemNumber = 4,
            title = "Nicht-Stören-Zugriff (DND)",
            subtitle = "Benachrichtigungs-Richtlinie",
            description = "Erlaubt der App, Klingeltöne und Töne zur Nachtruhe stummzuschalten bzw. DND-Status zu verwalten.",
            isCompleted = isDndGranted,
            actionButtonText = if (isDndGranted) "Erteilt" else "Erlauben",
            onActionClick = {
                SetupGuideHelper.openNotificationPolicySettings(context)
            }
        )

        if (isDialog && onDismiss != null) {
            Spacer(modifier = Modifier.height(20.dp))
            Button(
                onClick = onDismiss,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF45A29E)),
                shape = RoundedCornerShape(10.dp)
            ) {
                Text(
                    text = if (allCompleted) "Schließen" else "Später fortsetzen",
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
            }
        } else if (!isDialog && onOpenFullDialog != null) {
            Spacer(modifier = Modifier.height(14.dp))
            OutlinedButton(
                onClick = onOpenFullDialog,
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(10.dp),
                colors = ButtonDefaults.outlinedButtonColors(
                    contentColor = Color(0xFF66FCF1)
                )
            ) {
                Text("Vollständigen Assistenten öffnen ↗", fontSize = 13.sp, color = Color(0xFF66FCF1))
            }
        }
    }
}

/**
 * Individual checklist row / card component.
 */
@Composable
private fun SetupItemCard(
    itemNumber: Int,
    title: String,
    subtitle: String,
    description: String,
    isCompleted: Boolean,
    actionButtonText: String,
    onActionClick: () -> Unit,
    secondaryActionText: String? = null,
    onSecondaryActionClick: (() -> Unit)? = null
) {
    var expanded by remember { mutableStateOf(!isCompleted) }

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .border(
                width = 1.dp,
                color = if (isCompleted) Color(0xFF10B981).copy(alpha = 0.35f) else Color(0xFFF59E0B).copy(alpha = 0.3f),
                shape = RoundedCornerShape(12.dp)
            ),
        color = if (isCompleted) Color(0xFF13221B) else Color(0xFF1F2229)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { expanded = !expanded },
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Status / Number badge
                Box(
                    modifier = Modifier
                        .size(30.dp)
                        .clip(CircleShape)
                        .background(
                            if (isCompleted) Color(0xFF10B981) else Color(0xFFF59E0B).copy(alpha = 0.2f)
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = if (isCompleted) "✓" else "$itemNumber",
                        fontWeight = FontWeight.Bold,
                        fontSize = 14.sp,
                        color = if (isCompleted) Color.Black else Color(0xFFF59E0B)
                    )
                }

                Spacer(modifier = Modifier.width(12.dp))

                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = title,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (isCompleted) Color(0xFFE2E8F0) else Color.White
                    )
                    Text(
                        text = subtitle,
                        fontSize = 12.sp,
                        color = if (isCompleted) Color(0xFF10B981) else Color(0xFFC5C6C7)
                    )
                }

                // Expand indicator
                Text(
                    text = if (expanded) "▲" else "▼",
                    fontSize = 12.sp,
                    color = Color(0xFFC5C6C7),
                    modifier = Modifier.padding(start = 6.dp)
                )
            }

            AnimatedVisibility(visible = expanded) {
                Column(modifier = Modifier.padding(top = 10.dp)) {
                    Text(
                        text = description,
                        fontSize = 12.5.sp,
                        lineHeight = 17.sp,
                        color = Color(0xFFCBD5E1),
                        modifier = Modifier.padding(bottom = 12.dp)
                    )

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (secondaryActionText != null && onSecondaryActionClick != null) {
                            OutlinedButton(
                                onClick = onSecondaryActionClick,
                                modifier = Modifier.padding(end = 8.dp),
                                shape = RoundedCornerShape(8.dp),
                                colors = ButtonDefaults.outlinedButtonColors(
                                    contentColor = Color(0xFF66FCF1)
                                )
                            ) {
                                Text(text = secondaryActionText, fontSize = 12.sp)
                            }
                        }

                        Button(
                            onClick = onActionClick,
                            shape = RoundedCornerShape(8.dp),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = if (isCompleted) Color(0xFF10B981) else Color(0xFFF59E0B)
                            )
                        ) {
                            Text(
                                text = actionButtonText,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (isCompleted) Color.Black else Color.Black
                            )
                        }
                    }
                }
            }
        }
    }
}
