import Flutter
import ReplayKit
import UIKit

public final class FlutterCockpitPlugin: NSObject, FlutterPlugin {
  private static let captureChannelName = "dev.cockpit.flutter_cockpit/capture"
  private static let recordingChannelName = "dev.cockpit.flutter_cockpit/recording"
  private static let viewportChannelName = "dev.cockpit.flutter_cockpit/viewport"

  private let recordingManager = FlutterCockpitRecordingManager()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let captureChannel = FlutterMethodChannel(
      name: captureChannelName,
      binaryMessenger: registrar.messenger()
    )
    let recordingChannel = FlutterMethodChannel(
      name: recordingChannelName,
      binaryMessenger: registrar.messenger()
    )
    let viewportChannel = FlutterMethodChannel(
      name: viewportChannelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = FlutterCockpitPlugin()
    registrar.addMethodCallDelegate(instance, channel: captureChannel)
    registrar.addMethodCallDelegate(instance, channel: recordingChannel)
    registrar.addMethodCallDelegate(instance, channel: viewportChannel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "queryNativeCaptureAvailability":
      result(activeWindow() != nil)
    case "captureAcceptanceScreenshot":
      captureAcceptanceScreenshot(result: result)
    case "queryRecordingCapabilities":
      result(recordingManager.queryCapabilities())
    case "startRecording":
      let arguments = call.arguments as? [String: Any] ?? [:]
      recordingManager.startRecording(arguments: arguments, result: result)
    case "stopRecording":
      recordingManager.stopRecording(result: result)
    case "queryViewportAvailability":
      result([
        "available": false,
        "reason": "fixedMobileViewport",
        "alternatives": ["changeOrientation", "selectAnotherDevice"],
      ])
    case "resizeViewport":
      result(
        FlutterError(
          code: "fixedMobileViewport",
          message: "iOS viewport size is controlled by the selected device.",
          details: ["alternatives": ["changeOrientation", "selectAnotherDevice"]]
        )
      )
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func captureAcceptanceScreenshot(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard let window = self.activeWindow() else {
        result(
          FlutterError(
            code: "noWindow",
            message: "Native capture requires an active UIWindow.",
            details: nil
          )
        )
        return
      }

      let bounds = window.bounds
      guard bounds.width > 0, bounds.height > 0 else {
        result(
          FlutterError(
            code: "invalidDimensions",
            message: "Active UIWindow is not ready for capture.",
            details: nil
          )
        )
        return
      }

      let renderer = UIGraphicsImageRenderer(bounds: bounds)
      var drawSucceeded = false
      let image = renderer.image { _ in
        drawSucceeded = window.drawHierarchy(in: bounds, afterScreenUpdates: true)
      }

      guard drawSucceeded else {
        result(
          FlutterError(
            code: "captureDrawFailed",
            message: "The active UIWindow could not be drawn for native capture.",
            details: nil
          )
        )
        return
      }

      guard let data = image.pngData() else {
        result(
          FlutterError(
            code: "encodeFailed",
            message: "Failed to encode native screenshot as PNG.",
            details: nil
          )
        )
        return
      }

      result([
        "bytes": FlutterStandardTypedData(bytes: data),
      ])
    }
  }

  private func activeWindow() -> UIWindow? {
    if #available(iOS 13.0, *) {
      let scenes = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .filter { $0.activationState == .foregroundActive }

      for scene in scenes {
        if let keyWindow = scene.windows.first(where: \.isKeyWindow) {
          return keyWindow
        }
        if let firstWindow = scene.windows.first {
          return firstWindow
        }
      }
      return nil
    }

    return UIApplication.shared.windows.first(where: \.isKeyWindow)
  }
}
