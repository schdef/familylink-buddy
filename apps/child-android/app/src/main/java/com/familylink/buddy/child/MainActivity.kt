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
import kotlinx.coroutines.launch

import android.provider.Settings
import android.net.Uri
import androidx.compose.ui.res.stringResource

class MainActivity : ComponentActivity() {

    private lateinit var repository: FamilyTimeRepository
    private val canDrawOverlaysState = mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        repository = FamilyTimeRepository(applicationContext)

        // Request notification permission if Android 13+
        requestNotificationPermission()

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
                    val familyData by repository.familyTimeData.collectAsState(initial = FamilyTimeData())
                    var serviceRunning by remember { mutableStateOf(true) }
                    val hasOverlayPermission by canDrawOverlaysState

                    // Auto-start service on app open for real-time widget testing
                    LaunchedEffect(Unit) {
                        startUpdateService()
                    }

                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(
                            text = stringResource(R.string.main_title),
                            fontSize = 28.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color(0xFF66FCF1),
                            modifier = Modifier.padding(vertical = 16.dp)
                        )

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

                                familyData.appUsages.forEach { app ->
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
                                    serviceRunning = running
                                    if (running) {
                                        startUpdateService()
                                    } else {
                                        stopUpdateService()
                                    }
                                },
                                colors = SwitchDefaults.colors(
                                    checkedThumbColor = Color(0xFF66FCF1),
                                    checkedTrackColor = Color(0xFF45A29E)
                                )
                            )
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

    override fun onResume() {
        super.onResume()
        canDrawOverlaysState.value = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
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
}
