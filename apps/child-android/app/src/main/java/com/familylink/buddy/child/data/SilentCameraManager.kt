package com.familylink.buddy.child.data

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Size
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean

data class CameraDimension(val width: Int, val height: Int)

object SilentCameraManager {
    private const val TAG = "SilentCameraManager"
    const val WATCHDOG_TIMEOUT_MS = 6000L

    /**
     * Maps user-facing string parameter to CameraCharacteristics lens facing constant.
     */
    fun mapFacing(facing: String?): Int {
        return if (facing?.equals("back", ignoreCase = true) == true) {
            CameraCharacteristics.LENS_FACING_BACK
        } else {
            CameraCharacteristics.LENS_FACING_FRONT
        }
    }

    /**
     * Parses flash parameter from query string, boolean or JSON value.
     */
    fun parseFlashParam(value: Any?): Boolean {
        return when (value) {
            is Boolean -> value
            is Number -> value.toInt() == 1
            is String -> value.equals("true", ignoreCase = true) || value == "1"
            else -> false
        }
    }

    /**
     * Selects optimal resolution given a list of candidate dimensions.
     */
    fun selectOptimalResolution(available: List<CameraDimension>): CameraDimension {
        if (available.isEmpty()) return CameraDimension(1280, 720)
        // Prefer exact 1280x720 if present
        available.firstOrNull { it.width == 1280 && it.height == 720 }?.let { return it }
        // Filter reasonable sizes (<= 1920x1080 or <= 1080x1920 for portrait sensors)
        val reasonable = available.filter {
            (it.width <= 1920 && it.height <= 1080) || (it.width <= 1080 && it.height <= 1920)
        }
        return reasonable.maxByOrNull { it.width * it.height } ?: available.first()
    }

    /**
     * Selects optimal JPEG resolution for remote camera capture (prefers 1280x720 or closest standard size <= 1080p).
     */
    fun chooseOptimalSize(sizes: Array<Size>?): Size {
        if (sizes.isNullOrEmpty()) return Size(1280, 720)
        val dimensions = sizes.map { CameraDimension(it.width, it.height) }
        val optimal = selectOptimalResolution(dimensions)
        return sizes.firstOrNull { it.width == optimal.width && it.height == optimal.height }
            ?: Size(optimal.width, optimal.height)
    }

    /**
     * Builds standard JSON payload for successful camera capture.
     */
    fun buildSuccessResponse(base64Image: String, facing: String, flash: Boolean, timestamp: Long = System.currentTimeMillis()): JSONObject {
        return JSONObject().apply {
            put("status", "success")
            put("base64Image", base64Image)
            put("facing", facing)
            put("flash", flash)
            put("timestamp", timestamp)
        }
    }

    /**
     * Builds standard JSON payload for error responses.
     */
    fun buildErrorResponse(message: String): JSONObject {
        return JSONObject().apply {
            put("status", "error")
            put("message", message)
        }
    }

    /**
     * Silently captures a photo using Camera2 API with flash OFF by default.
     * Cleanly manages device session, resources, and includes a 6-second timeout watchdog.
     */
    @SuppressLint("MissingPermission")
    fun capturePhoto(
        context: Context,
        facing: String = "front",
        flash: Boolean = false,
        callback: (Result<ByteArray>) -> Unit
    ) {
        // 1. Check camera permission
        val hasPermission = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasPermission) {
            callback(Result.failure(SecurityException("Camera permission not granted")))
            return
        }

        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
        if (cameraManager == null) {
            callback(Result.failure(IllegalStateException("CameraManager not available")))
            return
        }

        val targetFacing = mapFacing(facing)
        val cameraIdList = try {
            cameraManager.cameraIdList
        } catch (e: Exception) {
            callback(Result.failure(e))
            return
        }

        if (cameraIdList.isEmpty()) {
            callback(Result.failure(IllegalStateException("No camera available on device")))
            return
        }

        var selectedCameraId: String? = null
        for (id in cameraIdList) {
            try {
                val chars = cameraManager.getCameraCharacteristics(id)
                val lensFacing = chars.get(CameraCharacteristics.LENS_FACING)
                if (lensFacing == targetFacing) {
                    selectedCameraId = id
                    break
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error checking camera characteristics for id: $id", e)
            }
        }

        val cameraId = selectedCameraId ?: cameraIdList.first()

        // Setup background thread and watchdog
        val handlerThread = HandlerThread("SilentCamera-${System.currentTimeMillis()}").apply { start() }
        val backgroundHandler = Handler(handlerThread.looper)

        val hasResponded = AtomicBoolean(false)
        var cameraDevice: CameraDevice? = null
        var captureSession: CameraCaptureSession? = null
        var imageReader: ImageReader? = null

        fun cleanup() {
            try {
                captureSession?.close()
            } catch (e: Exception) {
                Log.w(TAG, "Error closing capture session", e)
            }
            try {
                cameraDevice?.close()
            } catch (e: Exception) {
                Log.w(TAG, "Error closing camera device", e)
            }
            try {
                imageReader?.close()
            } catch (e: Exception) {
                Log.w(TAG, "Error closing image reader", e)
            }
            try {
                handlerThread.quitSafely()
            } catch (e: Exception) {
                Log.w(TAG, "Error quitting handler thread", e)
            }
        }

        fun finishWith(result: Result<ByteArray>) {
            if (hasResponded.compareAndSet(false, true)) {
                backgroundHandler.removeCallbacksAndMessages(null)
                cleanup()
                callback(result)
            }
        }

        // 6-second timeout watchdog
        val watchdogRunnable = Runnable {
            Log.w(TAG, "Camera capture watchdog timed out after ${WATCHDOG_TIMEOUT_MS}ms")
            finishWith(Result.failure(TimeoutException("Camera capture timed out after 6 seconds")))
        }
        backgroundHandler.postDelayed(watchdogRunnable, WATCHDOG_TIMEOUT_MS)

        try {
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            val map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val jpegSizes = map?.getOutputSizes(ImageFormat.JPEG)

            val chosenSize = chooseOptimalSize(jpegSizes)
            Log.i(TAG, "Configuring SilentCamera: cameraId=$cameraId facing=$facing flash=$flash size=${chosenSize.width}x${chosenSize.height}")

            val reader = ImageReader.newInstance(
                chosenSize.width,
                chosenSize.height,
                ImageFormat.JPEG,
                2
            )
            imageReader = reader

            reader.setOnImageAvailableListener({ ir ->
                try {
                    val image = ir.acquireLatestImage() ?: ir.acquireNextImage()
                    if (image != null) {
                        try {
                            val planes = image.planes
                            if (planes.isNotEmpty()) {
                                val buffer = planes[0].buffer
                                val bytes = ByteArray(buffer.remaining())
                                buffer.get(bytes)
                                Log.i(TAG, "Captured image bytes: ${bytes.size}")
                                finishWith(Result.success(bytes))
                            } else {
                                finishWith(Result.failure(IllegalStateException("No image planes available")))
                            }
                        } finally {
                            image.close()
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error processing image from reader", e)
                    finishWith(Result.failure(e))
                }
            }, backgroundHandler)

            cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    try {
                        val surface = reader.surface
                        @Suppress("DEPRECATION")
                        camera.createCaptureSession(
                            listOf(surface),
                            object : CameraCaptureSession.StateCallback() {
                                override fun onConfigured(session: CameraCaptureSession) {
                                    captureSession = session
                                    try {
                                        val captureBuilder = camera.createCaptureRequest(
                                            CameraDevice.TEMPLATE_STILL_CAPTURE
                                        ).apply {
                                            addTarget(surface)
                                            if (flash) {
                                                set(
                                                    CaptureRequest.CONTROL_AE_MODE,
                                                    CaptureRequest.CONTROL_AE_MODE_ON_ALWAYS_FLASH
                                                )
                                                set(
                                                    CaptureRequest.FLASH_MODE,
                                                    CaptureRequest.FLASH_MODE_SINGLE
                                                )
                                            } else {
                                                set(
                                                    CaptureRequest.CONTROL_AE_MODE,
                                                    CaptureRequest.CONTROL_AE_MODE_ON
                                                )
                                                set(
                                                    CaptureRequest.FLASH_MODE,
                                                    CaptureRequest.FLASH_MODE_OFF
                                                )
                                            }
                                        }

                                        session.capture(
                                            captureBuilder.build(),
                                            object : CameraCaptureSession.CaptureCallback() {
                                                override fun onCaptureFailed(
                                                    session: CameraCaptureSession,
                                                    request: CaptureRequest,
                                                    failure: android.hardware.camera2.CaptureFailure
                                                ) {
                                                    super.onCaptureFailed(session, request, failure)
                                                    Log.e(TAG, "Camera capture failed, reason: ${failure.reason}")
                                                    finishWith(Result.failure(Exception("Camera capture failed with reason: ${failure.reason}")))
                                                }
                                            },
                                            backgroundHandler
                                        )
                                    } catch (e: Exception) {
                                        Log.e(TAG, "Error creating capture request", e)
                                        finishWith(Result.failure(e))
                                    }
                                }

                                override fun onConfigureFailed(session: CameraCaptureSession) {
                                    Log.e(TAG, "Failed to configure camera capture session")
                                    finishWith(Result.failure(Exception("Camera capture session configuration failed")))
                                }
                            },
                            backgroundHandler
                        )
                    } catch (e: Exception) {
                        Log.e(TAG, "Error creating capture session on opened camera", e)
                        finishWith(Result.failure(e))
                    }
                }

                override fun onDisconnected(camera: CameraDevice) {
                    Log.w(TAG, "Camera device disconnected")
                    finishWith(Result.failure(Exception("Camera device disconnected")))
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    Log.e(TAG, "Camera device error: $error")
                    finishWith(Result.failure(Exception("Camera device error: $error")))
                }
            }, backgroundHandler)

        } catch (e: Exception) {
            Log.e(TAG, "Failed to start camera capture flow", e)
            finishWith(Result.failure(e))
        }
    }
}
