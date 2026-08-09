import Cocoa
import FlutterMacOS

public final class FlutterCockpitPlugin: NSObject, FlutterPlugin {
  private static let captureChannelName = "dev.cockpit.flutter_cockpit/capture"
  private static let recordingChannelName = "dev.cockpit.flutter_cockpit/recording"
  private static let viewportChannelName = "dev.cockpit.flutter_cockpit/viewport"
  private static let accessibilityChannelName = "dev.cockpit.flutter_cockpit/accessibility"
  private weak var engine: FlutterEngine?
  private lazy var recordingManager = FlutterCockpitRecordingManager(
    windowProvider: { [weak self] in self?.activeWindow() }
  )

  private init(engine: FlutterEngine?) {
    self.engine = engine
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let captureChannel = FlutterMethodChannel(
      name: captureChannelName,
      binaryMessenger: registrar.messenger
    )
    let recordingChannel = FlutterMethodChannel(
      name: recordingChannelName,
      binaryMessenger: registrar.messenger
    )
    let viewportChannel = FlutterMethodChannel(
      name: viewportChannelName,
      binaryMessenger: registrar.messenger
    )
    let accessibilityChannel = FlutterMethodChannel(
      name: accessibilityChannelName,
      binaryMessenger: registrar.messenger
    )
    let engine = flutterViewController(for: registrar.view)?.engine
    if let engine {
      _ = enableEngineSemantics(engine)
    }
    let instance = FlutterCockpitPlugin(engine: engine)
    registrar.addMethodCallDelegate(instance, channel: captureChannel)
    registrar.addMethodCallDelegate(instance, channel: recordingChannel)
    registrar.addMethodCallDelegate(instance, channel: viewportChannel)
    registrar.addMethodCallDelegate(instance, channel: accessibilityChannel)
  }

  private static func flutterViewController(for view: NSView?) -> FlutterViewController? {
    var responder: NSResponder? = view
    while let current = responder {
      if let controller = current as? FlutterViewController {
        return controller
      }
      responder = current.nextResponder
    }
    return view?.window?.contentViewController as? FlutterViewController
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
        "available": activeWindow() != nil,
        "alternatives": [],
      ])
    case "resizeViewport":
      resizeViewport(arguments: call.arguments, result: result)
    case "enableSemantics":
      enableSemantics(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func enableSemantics(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard let engine = self.engine else {
        result(
          FlutterError(
            code: "engineUnavailable",
            message: "Flutter engine is unavailable for native semantics.",
            details: nil
          )
        )
        return
      }
      guard Self.enableEngineSemantics(engine) else {
        result(
          FlutterError(
            code: "semanticsUnavailable",
            message: "Flutter engine rejected native semantics activation.",
            details: nil
          )
        )
        return
      }
      result(["enabled": true])
    }
  }

  private static func enableEngineSemantics(_ engine: FlutterEngine) -> Bool {
    let setter = NSSelectorFromString("setSemanticsEnabled:")
    guard engine.responds(to: setter) else {
      return false
    }
    engine.setValue(true, forKey: "semanticsEnabled")
    return engine.value(forKey: "semanticsEnabled") as? Bool == true
  }

  private func resizeViewport(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let values = arguments as? [String: Any],
      let width = values["width"] as? NSNumber,
      let height = values["height"] as? NSNumber
    else {
      result(
        FlutterError(
          code: "invalidViewport",
          message: "Viewport width and height must be integers.",
          details: nil
        )
      )
      return
    }

    DispatchQueue.main.async {
      guard let window = self.activeWindow() else {
        result(
          FlutterError(
            code: "noWindow",
            message: "Viewport resize requires an active NSWindow.",
            details: nil
          )
        )
        return
      }
      let requestedContentSize = NSSize(
        width: width.doubleValue,
        height: height.doubleValue
      )
      if let visibleFrame = window.screen?.visibleFrame {
        let maximumContentSize = window.contentRect(forFrameRect: visibleFrame).size
        if requestedContentSize.width > maximumContentSize.width + 0.5 ||
          requestedContentSize.height > maximumContentSize.height + 0.5
        {
          result([
            "accepted": false,
            "reason": "viewportExceedsScreen",
            "alternatives": [
              "useViewportAtMost:\(Int(maximumContentSize.width))x\(Int(maximumContentSize.height))",
              "moveWindowToLargerDisplay",
            ],
          ])
          return
        }
      }
      window.setContentSize(requestedContentSize)
      window.displayIfNeeded()
      result(["accepted": true])
    }
  }

  private func captureAcceptanceScreenshot(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard let window = self.activeWindow() else {
        result(
          FlutterError(
            code: "noWindow",
            message: "Native capture requires an active NSWindow.",
            details: nil
          )
        )
        return
      }

      guard let pngData = self.captureWindowPNG(window: window) else {
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
        "bytes": FlutterStandardTypedData(bytes: pngData),
      ])
    }
  }

  private func activeWindow() -> NSWindow? {
    if let keyWindow = NSApp.keyWindow {
      return keyWindow
    }

    return NSApp.windows.first(where: { $0.isVisible })
  }

  private func captureWindowPNG(window: NSWindow) -> Data? {
    guard let contentView = window.contentView else {
      return nil
    }

    let bounds = contentView.bounds
    guard bounds.width > 0, bounds.height > 0 else {
      return nil
    }

    contentView.layoutSubtreeIfNeeded()
    let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds)
    guard let bitmap else {
      return nil
    }

    contentView.cacheDisplay(in: bounds, to: bitmap)
    return bitmap.representation(using: .png, properties: [:])
  }
}
