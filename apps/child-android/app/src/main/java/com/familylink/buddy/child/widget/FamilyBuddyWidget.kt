package com.familylink.buddy.child.widget

import android.content.Context
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
import com.familylink.buddy.child.data.AppUsage
import com.familylink.buddy.child.data.FamilyTimeData
import com.familylink.buddy.child.data.FamilyTimeRepository
import java.text.SimpleDateFormat
import java.util.*

class FamilyBuddyWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            val prefs = currentState<androidx.datastore.preferences.core.Preferences>()
            val remaining = prefs[androidx.datastore.preferences.core.intPreferencesKey("remaining_minutes")] ?: 60
            val limit = prefs[androidx.datastore.preferences.core.intPreferencesKey("limit_minutes")] ?: 120
            val lastUpdated = prefs[androidx.datastore.preferences.core.longPreferencesKey("last_updated")] ?: System.currentTimeMillis()
            val usagesString = prefs[androidx.datastore.preferences.core.stringPreferencesKey("app_usages")] ?: ""

            val dataState = FamilyTimeData(
                totalRemainingMinutes = remaining,
                totalLimitMinutes = limit,
                lastUpdatedMillis = lastUpdated,
                appUsages = FamilyTimeRepository.deserializeAppUsages(usagesString)
            )

            // Build the widget UI
            WidgetContent(context, dataState)
        }
    }

    @Composable
    private fun WidgetContent(context: Context, data: FamilyTimeData) {
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
                    text = "FamilyLink Buddy",
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF94A3B8)),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Medium
                    )
                )
                Spacer(modifier = GlanceModifier.defaultWeight())
                Text(
                    text = "Sync: $formattedTime",
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF64748B)),
                        fontSize = 10.sp
                    )
                )
            }

            Spacer(modifier = GlanceModifier.height(10.dp))

            // Large remaining time text
            Text(
                text = "$remainingMinutes min left",
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
                        text = "No active app limits",
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF64748B)),
                            fontSize = 11.sp
                        )
                    )
                } else {
                    data.appUsages.take(2).forEach { app ->
                        AppUsageRow(app)
                        Spacer(modifier = GlanceModifier.height(6.dp))
                    }
                }
            }
        }
    }

    @Composable
    private fun AppUsageRow(app: AppUsage) {
        val appPercent = if (app.limitMinutes > 0) {
            ((app.limitMinutes - app.usedMinutes).toFloat() / app.limitMinutes.toFloat()).coerceIn(0f, 1f)
        } else 0f

        val progressColor = when {
            app.remainingMinutes <= 3 -> Color(0xFFEF4444)  // Red alert when under 3 mins
            app.remainingMinutes <= 10 -> Color(0xFFF59E0B) // Orange warning
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
                    text = "${app.remainingMinutes}m remaining",
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
}
