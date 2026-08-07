#ifndef FLUTTER_PLUGIN_FLUTTER_COCKPIT_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_COCKPIT_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <chrono>
#include <cstdint>
#include <future>
#include <memory>
#include <string>
#include <vector>

namespace flutter_cockpit {

class FlutterCockpitWindowRecorder;

class FlutterCockpitPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit FlutterCockpitPlugin(flutter::PluginRegistrarWindows* registrar);
  ~FlutterCockpitPlugin() override;

  FlutterCockpitPlugin(const FlutterCockpitPlugin&) = delete;
  FlutterCockpitPlugin& operator=(const FlutterCockpitPlugin&) = delete;

  void HandleCaptureMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleRecordingMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleViewportMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  enum class RecordingState {
    Idle,
    Starting,
    Recording,
    Stopping,
  };

  HWND ActiveWindowHandle() const;

  void QueryNativeCaptureAvailability(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void CaptureAcceptanceScreenshot(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void ResizeViewport(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void QueryRecordingCapabilities(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void StartRecording(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void StopRecording(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      capture_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      recording_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      viewport_channel_;
  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<FlutterCockpitWindowRecorder> active_recorder_;
  std::chrono::steady_clock::time_point recording_started_at_;
  RecordingState recording_state_ = RecordingState::Idle;
  uint64_t session_token_ = 0;
  ULONG_PTR gdiplus_token_ = 0;
};

}  // namespace flutter_cockpit

#endif  // FLUTTER_PLUGIN_FLUTTER_COCKPIT_PLUGIN_H_
