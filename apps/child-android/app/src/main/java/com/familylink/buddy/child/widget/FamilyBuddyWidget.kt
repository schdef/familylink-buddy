package com.familylink.buddy.child.widget

import android.content.Context
import android.content.pm.PackageManager
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.*
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.*
import androidx.glance.text.*
import androidx.glance.unit.ColorProvider
import com.familylink.buddy.child.R
import com.familylink.buddy.child.data.AppUsage
import com.familylink.buddy.child.data.FamilyTimeData
import com.familylink.buddy.child.data.FamilyTimeRepository
import java.text.SimpleDateFormat
import java.util.*

import kotlinx.coroutines.flow.first

import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import com.familylink.buddy.child.data.TimeBankState
import com.familylink.buddy.child.MainActivity
import com.familylink.buddy.child.service.CommsActivity

class FamilyBuddyWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val repository = FamilyTimeRepository(context.applicationContext)
        val dataState = repository.familyTimeData.first()
        val timeBankState = repository.timeBankState.first()

        provideContent {
            // Build the widget UI
            WidgetContent(context, dataState, timeBankState)
        }
    }

    @Composable
    private fun WidgetContent(context: Context, data: FamilyTimeData, timeBankState: TimeBankState) {
        val remainingMinutes = data.totalRemainingMinutes
        val limitMinutes = data.totalLimitMinutes
        val lastUpdated = data.lastUpdatedMillis

        val remainingPercent = if (limitMinutes > 0) {
            (remainingMinutes.toFloat() / limitMinutes.toFloat()).coerceIn(0f, 1f)
        } else 0f

        val formattedTime = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(lastUpdated))

        // Root container (premium dark blue/black scheme)
        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(ColorProvider(Color(0xFF0F1016)))
                .padding(12.dp)
        ) {
            // Header
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Pulse Green Status Indicator
                Box(
                    modifier = GlanceModifier
                        .size(8.dp)
                        .background(ColorProvider(Color(0xFF22C55E)))
                ) {}
                Spacer(modifier = GlanceModifier.width(6.dp))
                Text(
                    text = context.getString(R.string.widget_header),
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF94A3B8)),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Medium
                    )
                )
                Spacer(modifier = GlanceModifier.width(8.dp))
                // 🎙️ Talk Action Button
                Text(
                    text = context.getString(R.string.widget_talk_action),
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF818CF8)),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold
                    ),
                    modifier = GlanceModifier
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                        .clickable(actionStartActivity<CommsActivity>())
                )
                Spacer(modifier = GlanceModifier.defaultWeight())
                Text(
                    text = context.getString(R.string.widget_sync, formattedTime),
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF64748B)),
                        fontSize = 10.sp
                    )
                )
            }

            Spacer(modifier = GlanceModifier.height(10.dp))

            // Large remaining time text
            Text(
                text = context.getString(R.string.widget_min_left, remainingMinutes),
                style = TextStyle(
                    color = ColorProvider(Color(0xFFF8FAFC)),
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold
                )
            )

            Spacer(modifier = GlanceModifier.height(8.dp))

            // Custom Progress Bar (Electric Indigo Accent)
            Box(
                modifier = GlanceModifier
                    .width(220.dp)
                    .height(6.dp)
                    .background(ColorProvider(Color(0xFF1E293B)))
            ) {
                if (remainingPercent > 0f) {
                    val progressWidth = (220 * remainingPercent).dp
                    Box(
                        modifier = GlanceModifier
                            .width(progressWidth)
                            .fillMaxHeight()
                            .background(ColorProvider(Color(0xFF6366F1)))
                    ) {}
                }
            }

            Spacer(modifier = GlanceModifier.height(12.dp))

            // App list breakdown
            Column(modifier = GlanceModifier.fillMaxWidth()) {
                if (data.appUsages.isEmpty()) {
                    Text(
                        text = context.getString(R.string.widget_no_limits),
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF64748B)),
                            fontSize = 11.sp
                        )
                    )
                } else {
                    val activeApps = data.appUsages
                        .filter { (it.usedMinutes > 0 || it.limitMinutes < 1440) && isPackageInstalled(context, it.packageName) }
                        .sortedWith(compareByDescending<AppUsage> { it.limitMinutes < 1440 }
                            .thenByDescending { it.usedMinutes })
                        .take(3)

                    if (activeApps.isEmpty()) {
                        Text(
                            text = context.getString(R.string.widget_no_limits),
                            style = TextStyle(
                                color = ColorProvider(Color(0xFF64748B)),
                                fontSize = 11.sp
                            )
                        )
                    } else {
                        activeApps.forEach { app ->
                            AppUsageRow(app, remainingMinutes, remainingPercent)
                            Spacer(modifier = GlanceModifier.height(6.dp))
                        }
                    }
                }
            }

            if (timeBankState.isChildVisible) {
                Spacer(modifier = GlanceModifier.height(10.dp))
                Row(
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        .background(ColorProvider(Color(0xFF1E293B)))
                        .padding(8.dp)
                        .clickable(actionStartActivity<MainActivity>()),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "⏳ ${timeBankState.balance} Coins",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFFFFD700)),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Text(
                        text = "Tippen zum Öffnen! 🎮",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF64748B)),
                            fontSize = 9.sp
                        )
                    )
                }
            }
        }
    }

    @Composable
    private fun AppUsageRow(app: AppUsage, deviceRemainingMinutes: Int, deviceRemainingPercent: Float) {
        val isUnlimited = app.limitMinutes >= 1440

        val actualRemaining = if (isUnlimited) {
            deviceRemainingMinutes
        } else {
            minOf(app.remainingMinutes, deviceRemainingMinutes)
        }

        val appPercent = if (isUnlimited) {
            deviceRemainingPercent
        } else {
            if (app.limitMinutes > 0) {
                ((app.limitMinutes - app.usedMinutes).toFloat() / app.limitMinutes.toFloat()).coerceIn(0f, 1f)
            } else 0f
        }

        val progressColor = when {
            actualRemaining <= 3 -> Color(0xFFEF4444)  // Red alert when under 3 mins
            actualRemaining <= 10 -> Color(0xFFF59E0B) // Orange warning
            else -> Color(0xFF10B981)                       // Green normal
        }

        Column(modifier = GlanceModifier.fillMaxWidth()) {
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = app.appName,
                    style = TextStyle(
                        color = ColorProvider(Color(0xFFE2E8F0)),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium
                    )
                )
                Spacer(modifier = GlanceModifier.defaultWeight())
                Text(
                    text = if (isUnlimited) {
                        LocalContext.current.getString(R.string.widget_app_unlimited, actualRemaining)
                    } else {
                        LocalContext.current.getString(R.string.widget_app_remaining, actualRemaining)
                    },
                    style = TextStyle(
                        color = ColorProvider(progressColor),
                        fontSize = 11.sp
                    )
                )
            }
            Spacer(modifier = GlanceModifier.height(4.dp))
            // Mini progress bar
            Box(
                modifier = GlanceModifier
                    .width(220.dp)
                    .height(3.dp)
                    .background(ColorProvider(Color(0xFF1E293B)))
            ) {
                if (appPercent > 0f) {
                    val progressWidth = (220 * appPercent).dp
                    Box(
                        modifier = GlanceModifier
                            .width(progressWidth)
                            .fillMaxHeight()
                            .background(ColorProvider(progressColor))
                    ) {}
                }
            }
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
