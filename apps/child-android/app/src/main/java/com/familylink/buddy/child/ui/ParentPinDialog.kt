package com.familylink.buddy.child.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.familylink.buddy.child.R
import com.familylink.buddy.child.data.ParentPinManager

enum class ParentPinDialogMode {
    ENTER_PIN,
    SET_PIN
}

/**
 * 4-digit Number Pad PIN Dialog for unlocking parent settings and configuring parent anti-tamper PIN.
 */
@Composable
fun ParentPinDialog(
    mode: ParentPinDialogMode = ParentPinDialogMode.ENTER_PIN,
    storedPin: String? = null,
    onSuccess: () -> Unit = {},
    onPinSet: (String) -> Unit = {},
    onDismiss: () -> Unit
) {
    var enteredPin by remember { mutableStateOf("") }
    var firstEnteredPin by remember { mutableStateOf<String?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val errorWrongPin = stringResource(R.string.pin_dialog_error_wrong)
    val errorMismatchPin = stringResource(R.string.pin_dialog_error_mismatch)

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.92f)
                .wrapContentHeight()
                .padding(vertical = 16.dp),
            shape = RoundedCornerShape(24.dp),
            color = Color(0xFF161F28),
            tonalElevation = 12.dp
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Header Icon
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .background(Color(0xFF66FCF1).copy(alpha = 0.15f)),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = if (mode == ParentPinDialogMode.ENTER_PIN) "🔒" else "🔑",
                        fontSize = 24.sp
                    )
                }

                Spacer(modifier = Modifier.height(12.dp))

                // Title
                val title = when {
                    mode == ParentPinDialogMode.ENTER_PIN -> stringResource(R.string.pin_dialog_title_enter)
                    firstEnteredPin == null -> stringResource(R.string.pin_dialog_title_set)
                    else -> stringResource(R.string.pin_dialog_title_confirm)
                }

                Text(
                    text = title,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFF66FCF1),
                    textAlign = TextAlign.Center
                )

                // Subtitle
                val subtitle = when {
                    mode == ParentPinDialogMode.ENTER_PIN -> stringResource(R.string.pin_dialog_subtitle_enter)
                    firstEnteredPin == null -> stringResource(R.string.pin_dialog_subtitle_set)
                    else -> stringResource(R.string.pin_dialog_subtitle_confirm)
                }

                Text(
                    text = subtitle,
                    fontSize = 13.sp,
                    color = Color(0xFFC5C6C7),
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 6.dp, bottom = 16.dp)
                )

                // PIN dots indicator (4 circles)
                Row(
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 8.dp)
                ) {
                    for (i in 0 until 4) {
                        val isFilled = i < enteredPin.length
                        Box(
                            modifier = Modifier
                                .padding(horizontal = 10.dp)
                                .size(20.dp)
                                .clip(CircleShape)
                                .background(
                                    if (isFilled) Color(0xFF66FCF1) else Color(0xFF1F2833)
                                )
                                .border(
                                    width = 2.dp,
                                    color = if (isFilled) Color(0xFF66FCF1) else Color(0xFF45A29E).copy(alpha = 0.5f),
                                    shape = CircleShape
                                )
                        )
                    }
                }

                // Error Message if any
                if (errorMessage != null) {
                    Text(
                        text = errorMessage ?: "",
                        fontSize = 13.sp,
                        color = Color(0xFFEF4444),
                        fontWeight = FontWeight.SemiBold,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(top = 8.dp)
                    )
                } else {
                    Spacer(modifier = Modifier.height(24.dp))
                }

                Spacer(modifier = Modifier.height(12.dp))

                // Custom 3x4 Number Pad
                val keyRows = listOf(
                    listOf("1", "2", "3"),
                    listOf("4", "5", "6"),
                    listOf("7", "8", "9"),
                    listOf("CANCEL", "0", "BACK")
                )

                val cancelText = stringResource(R.string.btn_cancel)

                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    for (row in keyRows) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceEvenly
                        ) {
                            for (key in row) {
                                KeypadButton(
                                    key = key,
                                    cancelLabel = cancelText,
                                    onClick = {
                                        errorMessage = null
                                        when (key) {
                                            "CANCEL" -> {
                                                onDismiss()
                                            }
                                            "BACK" -> {
                                                if (enteredPin.isNotEmpty()) {
                                                    enteredPin = enteredPin.dropLast(1)
                                                }
                                            }
                                            else -> {
                                                if (enteredPin.length < 4) {
                                                    val newPin = enteredPin + key
                                                    enteredPin = newPin

                                                    // When 4 digits reached, process
                                                    if (newPin.length == 4) {
                                                        if (mode == ParentPinDialogMode.ENTER_PIN) {
                                                            if (ParentPinManager.verifyPin(newPin, storedPin)) {
                                                                onSuccess()
                                                            } else {
                                                                errorMessage = errorWrongPin
                                                                enteredPin = ""
                                                            }
                                                        } else {
                                                            // SET_PIN mode
                                                            if (firstEnteredPin == null) {
                                                                firstEnteredPin = newPin
                                                                enteredPin = ""
                                                            } else {
                                                                if (newPin == firstEnteredPin) {
                                                                    onPinSet(newPin)
                                                                } else {
                                                                    errorMessage = errorMismatchPin
                                                                    firstEnteredPin = null
                                                                    enteredPin = ""
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun KeypadButton(
    key: String,
    cancelLabel: String = "Cancel",
    onClick: () -> Unit
) {
    val isAction = key == "CANCEL" || key == "BACK"
    val displayText = when (key) {
        "CANCEL" -> cancelLabel
        "BACK" -> "⌫"
        else -> key
    }

    Box(
        modifier = Modifier
            .size(width = if (key == "CANCEL") 84.dp else 72.dp, height = 54.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(
                if (isAction) Color(0xFF1F2833).copy(alpha = 0.6f) else Color(0xFF1F2833)
            )
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = displayText,
            fontSize = if (key == "CANCEL") 12.sp else if (key == "BACK") 20.sp else 22.sp,
            fontWeight = if (isAction) FontWeight.Normal else FontWeight.Bold,
            color = if (key == "CANCEL") Color(0xFFEF4444) else Color.White
        )
    }
}
