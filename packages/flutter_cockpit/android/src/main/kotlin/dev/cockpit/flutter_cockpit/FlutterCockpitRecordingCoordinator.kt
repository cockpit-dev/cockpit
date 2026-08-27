package dev.cockpit.flutter_cockpit

import android.app.Activity
import android.content.Context
import android.media.projection.MediaProjectionManager
import android.os.Build
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.concurrent.atomic.AtomicLong

internal object FlutterCockpitRecordingPathResolver {
    private const val RECORDING_ROOT_NAME = "flutter_cockpit_recordings"

    fun resolve(cacheDirectory: File, relativePath: String): File {
        val path = relativePath
        require(path.isNotBlank()) { "Recording path must not be blank." }
        require(!File(path).isAbsolute()) { "Recording path must be relative." }
        require(!path.startsWith('/') && !path.startsWith('\\')) {
            "Recording path must not be rooted."
        }
        require(!Regex("^[A-Za-z]:").containsMatchIn(path)) {
            "Recording path must not be drive-qualified."
        }
        require(path.split('/', '\\').none { it == ".." }) {
            "Recording path must not contain parent traversal."
        }

        val root = File(cacheDirectory, RECORDING_ROOT_NAME).canonicalFile
        val candidate = File(root, path).canonicalFile
        val rootPrefix = root.path + File.separator
        require(candidate != root && candidate.path.startsWith(rootPrefix)) {
            "Recording path is outside the owned recording directory."
        }
        return candidate
    }
}

internal object FlutterCockpitRecordingCapability {
    fun isAvailable(
        sdkInt: Int,
        hasActivity: Boolean,
        hasProjectionManager: Boolean,
    ): Boolean =
        sdkInt >= Build.VERSION_CODES.LOLLIPOP && hasActivity && hasProjectionManager
}

internal class FlutterCockpitRecordingCoordinator(
    private val applicationContext: Context,
) : PluginRegistry.ActivityResultListener {
    private enum class RecordingState {
        Idle,
        Starting,
        Recording,
        Stopping,
    }

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var state = RecordingState.Idle
    private var currentSessionToken: Long? = null
    private var pendingStartResult: MethodChannel.Result? = null
    private var pendingStartRequest: PendingStartRequest? = null
    private var pendingStopResult: MethodChannel.Result? = null

    fun attachActivity(binding: ActivityPluginBinding) {
        if (activityBinding !== binding) {
            activityBinding?.removeActivityResultListener(this)
        }
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    fun detachActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    fun detachActivityPermanently() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
        detachPendingWork()
    }

    fun detachFromEngine() {
        detachActivityPermanently()
    }

    fun queryCapabilities(result: MethodChannel.Result) {
        val currentActivity = activity
        val projectionManager = currentActivity?.let(::projectionManager)
        val available =
            FlutterCockpitRecordingCapability.isAvailable(
                sdkInt = Build.VERSION.SDK_INT,
                hasActivity = currentActivity != null,
                hasProjectionManager = projectionManager != null,
            )
        result.success(
            mapOf<String, Any>(
                "supportsNativeRecording" to available,
                "preferredAcceptanceRecordingKind" to "nativeScreen",
                "supportedLayers" to listOf("system"),
                "preferredLayer" to "system",
                "recordingLimitations" to listOf(
                    "System recording consent is required.",
                    "Protected content may not be recorded.",
                ),
            ),
        )
    }

    fun startRecording(call: MethodCall, result: MethodChannel.Result) {
        if (state != RecordingState.Idle || FlutterCockpitRecordingService.hasActiveSession()) {
            result.error(
                "recordingAlreadyActive",
                "A recording session is already active.",
                null,
            )
            return
        }

        val currentActivity = activity
        if (currentActivity == null) {
            result.error("noActivity", "Recording requires an attached Activity.", null)
            return
        }

        val relativePath = call.argument<String>("relativePath")
        if (relativePath == null) {
            result.error("recordingInvalidPath", "Recording relativePath is required.", null)
            return
        }
        try {
            FlutterCockpitRecordingPathResolver.resolve(
                applicationContext.cacheDir,
                relativePath,
            )
        } catch (error: Exception) {
            result.error(
                "recordingInvalidPath",
                error.message ?: "Recording path is invalid.",
                null,
            )
            return
        }

        val projectionManager = projectionManager(currentActivity)
        if (!FlutterCockpitRecordingCapability.isAvailable(
                sdkInt = Build.VERSION.SDK_INT,
                hasActivity = true,
                hasProjectionManager = projectionManager != null,
            ) || projectionManager == null
        ) {
            result.error(
                "recordingStartFailed",
                "MediaProjection is unavailable on the attached Activity.",
                null,
            )
            return
        }

        val token = NEXT_SESSION_TOKEN.incrementAndGet()
        state = RecordingState.Starting
        currentSessionToken = token
        pendingStartRequest =
            PendingStartRequest(
                token = token,
                relativePath = relativePath,
            )
        pendingStartResult = result

        try {
            val consentIntent = projectionManager.createScreenCaptureIntent()
            currentActivity.startActivityForResult(consentIntent, REQUEST_CODE)
        } catch (error: Exception) {
            completeStartFailure(
                token = token,
                code = "recordingStartFailed",
                message = error.message ?: "Unable to launch recording consent.",
            )
        }
    }

    fun stopRecording(result: MethodChannel.Result) {
        when (state) {
            RecordingState.Idle ->
                result.success(
                    mapOf<String, Any>(
                        "state" to "failed",
                        "failureReason" to "recordingNotActive",
                    ),
                )
            RecordingState.Starting ->
                result.error(
                    "recordingNotReady",
                    "Recording consent or service startup is still pending.",
                    null,
                )
            RecordingState.Stopping ->
                result.error(
                    "recordingAlreadyStopping",
                    "Recording finalization is already in progress.",
                    null,
                )
            RecordingState.Recording -> stopActiveRecording(result)
        }
    }

    fun cancelStart(result: MethodChannel.Result) {
        val token = currentSessionToken
        if (state != RecordingState.Starting || token == null) {
            result.success(false)
            return
        }

        val startResult = pendingStartResult
        pendingStartResult = null
        pendingStartRequest = null
        currentSessionToken = null
        state = RecordingState.Idle
        FlutterCockpitRecordingService.cancelPendingStart(token)
        startResult?.error(
            "recordingCancelled",
            "Recording startup was cancelled after the caller timeout.",
            null,
        )
        result.success(true)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?): Boolean {
        if (requestCode != REQUEST_CODE) {
            return false
        }

        val startRequest = pendingStartRequest
        val startResult = pendingStartResult
        val token = currentSessionToken
        if (startRequest == null || startResult == null || token == null || token != startRequest.token) {
            return true
        }
        if (state != RecordingState.Starting || startRequest.consentResultHandled) {
            return true
        }
        startRequest.consentResultHandled = true

        if (resultCode != Activity.RESULT_OK || data == null) {
            completeStartFailure(
                token = token,
                code = "permissionDenied",
                message = "User denied screen recording consent.",
            )
            return true
        }

        try {
            FlutterCockpitRecordingService.requestStart(
                context = applicationContext,
                resultCode = resultCode,
                projectionData = data,
                relativePath = startRequest.relativePath,
                sessionToken = token,
                onStarted = { payload ->
                    completeStart(token, payload)
                },
                onTerminated = { payload ->
                    completeUnexpectedTermination(token, payload)
                },
            )
        } catch (error: Exception) {
            completeStartFailure(
                token = token,
                code = "recordingStartFailed",
                message = error.message ?: "Unable to start the recording service.",
            )
        }
        return true
    }

    private fun stopActiveRecording(result: MethodChannel.Result) {
        val token = currentSessionToken
        if (token == null) {
            result.success(
                mapOf<String, Any>(
                    "state" to "failed",
                    "failureReason" to "recordingNotActive",
                ),
            )
            return
        }
        state = RecordingState.Stopping
        pendingStopResult = result
        try {
            val stopped =
                FlutterCockpitRecordingService.stopActiveRecording(token) { payload ->
                    completeStop(token, payload)
                }
            if (!stopped) {
                completeStop(
                    token,
                    mapOf<String, Any?>(
                        "state" to "failed",
                        "failureReason" to "recordingNotActive",
                    ),
                )
            }
        } catch (error: Exception) {
            completeStop(
                token,
                mapOf<String, Any?>(
                    "state" to "failed",
                    "failureReason" to "recordingFinalizeFailed",
                ),
            )
        }
    }

    private fun projectionManager(currentActivity: Activity): MediaProjectionManager? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return null
        }
        return try {
            currentActivity.getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                as? MediaProjectionManager
        } catch (_: Exception) {
            null
        }
    }

    private fun completeStart(token: Long, payload: Map<String, Any?>) {
        if (token != currentSessionToken || state != RecordingState.Starting) {
            return
        }
        val result = pendingStartResult
        pendingStartResult = null
        pendingStartRequest = null
        if (payload["state"] == "recording") {
            state = RecordingState.Recording
        } else {
            state = RecordingState.Idle
            currentSessionToken = null
        }
        result?.success(payload)
    }

    private fun completeStartFailure(token: Long, code: String, message: String) {
        if (token != currentSessionToken || state != RecordingState.Starting) {
            return
        }
        val result = pendingStartResult
        pendingStartResult = null
        pendingStartRequest = null
        currentSessionToken = null
        state = RecordingState.Idle
        FlutterCockpitRecordingService.cancelPendingStart(token)
        result?.error(code, message, null)
    }

    private fun completeUnexpectedTermination(token: Long, payload: Map<String, Any?>) {
        if (token != currentSessionToken) {
            return
        }
        when (state) {
            RecordingState.Starting -> {
                val result = pendingStartResult
                pendingStartResult = null
                pendingStartRequest = null
                currentSessionToken = null
                state = RecordingState.Idle
                result?.success(payload)
            }
            RecordingState.Recording -> {
                currentSessionToken = null
                state = RecordingState.Idle
            }
            RecordingState.Stopping -> {
                val result = pendingStopResult
                pendingStopResult = null
                currentSessionToken = null
                state = RecordingState.Idle
                result?.error(
                    "recordingDetached",
                    "Recording ended before finalization completed.",
                    null,
                )
            }
            RecordingState.Idle -> Unit
        }
    }

    private fun completeStop(token: Long, payload: Map<String, Any?>) {
        if (token != currentSessionToken || state != RecordingState.Stopping) {
            return
        }
        val result = pendingStopResult
        pendingStopResult = null
        currentSessionToken = null
        state = RecordingState.Idle
        result?.success(payload)
    }

    private fun detachPendingWork() {
        val token = currentSessionToken
        if (token == null) {
            return
        }

        if (state == RecordingState.Starting) {
            val result = pendingStartResult
            pendingStartResult = null
            pendingStartRequest = null
            currentSessionToken = null
            state = RecordingState.Idle
            FlutterCockpitRecordingService.cancelPendingStart(token)
            result?.error("recordingDetached", "Recording detached before it started.", null)
            return
        }

        if (pendingStopResult != null) {
            val result = pendingStopResult
            pendingStopResult = null
            result?.error("recordingDetached", "Recording detached while stopping.", null)
        }
        if (state == RecordingState.Recording) {
            state = RecordingState.Stopping
            try {
                val stopped =
                    FlutterCockpitRecordingService.stopActiveRecording(token) { payload ->
                        completeStop(token, payload)
                    }
                if (!stopped) {
                    completeStop(
                        token,
                        mapOf<String, Any?>(
                            "state" to "failed",
                            "failureReason" to "recordingDetached",
                        ),
                    )
                }
            } catch (_: Exception) {
                completeStop(
                    token,
                    mapOf<String, Any?>(
                        "state" to "failed",
                        "failureReason" to "recordingDetached",
                    ),
                )
            }
        }
    }

    private data class PendingStartRequest(
        val token: Long,
        val relativePath: String,
        var consentResultHandled: Boolean = false,
    )

    private companion object {
        const val REQUEST_CODE = 8493
        val NEXT_SESSION_TOKEN = AtomicLong()
    }
}
