package dev.cockpit.flutter_cockpit

import android.app.Activity
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class FlutterCockpitPlugin : FlutterPlugin, ActivityAware {
    private lateinit var captureChannel: MethodChannel
    private lateinit var recordingChannel: MethodChannel
    private lateinit var viewportChannel: MethodChannel
    private lateinit var recordingCoordinator: FlutterCockpitRecordingCoordinator
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        recordingCoordinator = FlutterCockpitRecordingCoordinator(binding.applicationContext)
        captureChannel = MethodChannel(binding.binaryMessenger, CAPTURE_CHANNEL_NAME)
        captureChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "queryNativeCaptureAvailability" ->
                    result.success(activity != null && supportsWindowPixelCopy())
                "captureAcceptanceScreenshot" -> captureAcceptanceScreenshot(result)
                else -> result.notImplemented()
            }
        }
        recordingChannel = MethodChannel(binding.binaryMessenger, RECORDING_CHANNEL_NAME)
        recordingChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "queryRecordingCapabilities" -> recordingCoordinator.queryCapabilities(result)
                "startRecording" -> recordingCoordinator.startRecording(call, result)
                "cancelRecordingStart" -> recordingCoordinator.cancelStart(result)
                "stopRecording" -> recordingCoordinator.stopRecording(result)
                else -> result.notImplemented()
            }
        }
        viewportChannel = MethodChannel(binding.binaryMessenger, VIEWPORT_CHANNEL_NAME)
        viewportChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "queryViewportAvailability" ->
                    result.success(
                        mapOf(
                            "available" to false,
                            "reason" to "fixedMobileViewport",
                            "alternatives" to listOf("changeOrientation", "selectAnotherDevice"),
                        ),
                    )
                "resizeViewport" ->
                    result.error(
                        "fixedMobileViewport",
                        "Android viewport size is controlled by the selected device.",
                        mapOf("alternatives" to listOf("changeOrientation", "selectAnotherDevice")),
                    )
                else -> result.notImplemented()
            }
        }
    }

    private fun supportsWindowPixelCopy(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O

    private fun captureAcceptanceScreenshot(result: MethodChannel.Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("noActivity", "Native capture requires an attached Activity.", null)
            return
        }
        if (!supportsWindowPixelCopy()) {
            result.error(
                "captureUnavailable",
                "Window PixelCopy capture requires Android API 26 or newer.",
                null,
            )
            return
        }

        val decorView = currentActivity.window.decorView
        val width = decorView.width
        val height = decorView.height
        if (width <= 0 || height <= 0) {
            result.error("invalidDimensions", "Activity window is not ready for capture.", null)
            return
        }

        val bitmap =
            try {
                Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            } catch (error: Exception) {
                result.error(
                    "captureFailed",
                    error.message ?: "Unable to allocate a native screenshot bitmap.",
                    null,
                )
                return
            }

        val flutterSurface = findFlutterSurface(decorView)
        val surface = flutterSurface?.holder?.surface
        try {
            val callback = PixelCopy.OnPixelCopyFinishedListener { copyResult ->
                try {
                    if (copyResult != PixelCopy.SUCCESS) {
                        result.error(
                            "captureFailed",
                            "PixelCopy failed with code $copyResult.",
                            null,
                        )
                        return@OnPixelCopyFinishedListener
                    }

                    val stream = ByteArrayOutputStream()
                    val encoded = bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                    if (!encoded) {
                        result.error(
                            "encodeFailed",
                            "Failed to encode native screenshot as PNG.",
                            null,
                        )
                        return@OnPixelCopyFinishedListener
                    }

                    result.success(
                        mapOf<String, Any>(
                            "bytes" to stream.toByteArray(),
                        ),
                    )
                } catch (error: Exception) {
                    result.error(
                        "captureFailed",
                        error.message ?: "Native screenshot capture failed.",
                        null,
                    )
                } finally {
                    bitmap.recycle()
                }
            }
            if (surface?.isValid == true) {
                PixelCopy.request(surface, bitmap, callback, Handler(Looper.getMainLooper()))
            } else {
                PixelCopy.request(currentActivity.window, bitmap, callback, Handler(Looper.getMainLooper()))
            }
        } catch (error: Exception) {
            bitmap.recycle()
            result.error(
                "captureFailed",
                error.message ?: "Unable to schedule native screenshot capture.",
                null,
            )
        }
    }

    private fun findFlutterSurface(view: View): SurfaceView? {
        if (view is SurfaceView && view.holder.surface.isValid) {
            return view
        }
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findFlutterSurface(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        captureChannel.setMethodCallHandler(null)
        recordingChannel.setMethodCallHandler(null)
        viewportChannel.setMethodCallHandler(null)
        recordingCoordinator.detachFromEngine()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        recordingCoordinator.attachActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        recordingCoordinator.detachActivityForConfigChanges()
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        recordingCoordinator.attachActivity(binding)
    }

    override fun onDetachedFromActivity() {
        recordingCoordinator.detachActivityPermanently()
        activity = null
    }

    private companion object {
        const val CAPTURE_CHANNEL_NAME = "dev.cockpit.flutter_cockpit/capture"
        const val RECORDING_CHANNEL_NAME = "dev.cockpit.flutter_cockpit/recording"
        const val VIEWPORT_CHANNEL_NAME = "dev.cockpit.flutter_cockpit/viewport"
    }
}
