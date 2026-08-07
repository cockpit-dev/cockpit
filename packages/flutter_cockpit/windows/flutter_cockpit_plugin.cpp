#include "flutter_cockpit_plugin.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <climits>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <future>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

namespace flutter_cockpit {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

constexpr char kCaptureChannelName[] = "dev.cockpit.flutter_cockpit/capture";
constexpr char kRecordingChannelName[] =
    "dev.cockpit.flutter_cockpit/recording";
constexpr char kViewportChannelName[] = "dev.cockpit.flutter_cockpit/viewport";
constexpr uint32_t kRecordingFrameRate = 15;
constexpr auto kRecordingStartupTimeout = std::chrono::seconds(20);
constexpr auto kRecordingStartupCancelTimeout = std::chrono::seconds(2);
constexpr auto kRecordingStopTimeout = std::chrono::seconds(10);

struct WindowFrame {
  int width = 0;
  int height = 0;
  std::vector<uint8_t> pixels;
};

struct RecordingStartStatus {
  bool success = false;
  std::string failure_reason;
};

struct RecordingRunResult {
  bool success = false;
  std::string failure_reason;
  int captured_frame_count = 0;
};

struct RecordingWorkerState {
  RecordingWorkerState(HWND window_handle,
                       std::filesystem::path artifact_path,
                       int frame_width,
                       int frame_height)
      : hwnd(window_handle),
        output_path(std::move(artifact_path)),
        width(frame_width),
        height(frame_height) {}

  HWND hwnd = nullptr;
  std::filesystem::path output_path;
  int width = 0;
  int height = 0;
  std::atomic<bool> stop_requested{false};
};

bool Utf8ToWide(const std::string& value, std::wstring* output) {
  if (output == nullptr) {
    return false;
  }
  output->clear();
  if (value.empty()) {
    return true;
  }
  const int source_length = static_cast<int>(value.size());
  const int length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), source_length, nullptr, 0);
  if (length <= 0) {
    return false;
  }
  output->resize(static_cast<size_t>(length));
  const int written = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), source_length,
      output->data(), length);
  if (written != length) {
    output->clear();
    return false;
  }
  return true;
}

bool WideToUtf8(const std::wstring& value, std::string* output) {
  if (output == nullptr) {
    return false;
  }
  output->clear();
  if (value.empty()) {
    return true;
  }
  const int source_length = static_cast<int>(value.size());
  const int length = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), source_length, nullptr, 0,
      nullptr, nullptr);
  if (length <= 0) {
    return false;
  }
  output->resize(static_cast<size_t>(length));
  const int written = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), source_length,
      output->data(), length, nullptr, nullptr);
  if (written != length) {
    output->clear();
    return false;
  }
  return true;
}

std::string HrToString(HRESULT hr) {
  std::ostringstream buffer;
  buffer << "HRESULT 0x" << std::hex << static_cast<unsigned long>(hr);
  return buffer.str();
}

std::string RecordingStartupTimeoutMessage() {
  const auto timeout_seconds = std::chrono::duration_cast<std::chrono::seconds>(
                                   kRecordingStartupTimeout)
                                   .count();
  return "Native Windows recorder startup timed out after " +
         std::to_string(timeout_seconds) +
         "s while initializing Media Foundation and the sink writer.";
}

std::optional<std::string> GetStringArgument(const EncodableValue* arguments,
                                             const char* key) {
  if (arguments == nullptr) {
    return std::nullopt;
  }
  const auto* map = std::get_if<EncodableMap>(arguments);
  if (map == nullptr) {
    return std::nullopt;
  }
  const auto iterator = map->find(EncodableValue(key));
  if (iterator == map->end()) {
    return std::nullopt;
  }
  if (const auto* value = std::get_if<std::string>(&iterator->second)) {
    return *value;
  }
  return std::nullopt;
}

std::optional<int> GetIntArgument(const EncodableValue* arguments,
                                  const char* key) {
  if (arguments == nullptr) {
    return std::nullopt;
  }
  const auto* map = std::get_if<EncodableMap>(arguments);
  if (map == nullptr) {
    return std::nullopt;
  }
  const auto iterator = map->find(EncodableValue(key));
  if (iterator == map->end()) {
    return std::nullopt;
  }
  if (const auto* value = std::get_if<int32_t>(&iterator->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&iterator->second)) {
    if (*value >= INT_MIN && *value <= INT_MAX) {
      return static_cast<int>(*value);
    }
  }
  return std::nullopt;
}

int EvenDimension(int value) {
  const int clamped = (std::max)(value, 2);
  return (clamped % 2 == 0) ? clamped : clamped + 1;
}

std::optional<std::filesystem::path> BuildTemporaryArtifactPath(
    const std::string& relative,
    std::string* failure_reason) {
  if (relative.empty() || relative.front() == '/' ||
      relative.find('\\') != std::string::npos) {
    if (failure_reason != nullptr) {
      *failure_reason = "recordingInvalidPath";
    }
    return std::nullopt;
  }

  std::wstring relative_wide;
  if (!Utf8ToWide(relative, &relative_wide)) {
    if (failure_reason != nullptr) {
      *failure_reason = "recordingInvalidPath";
    }
    return std::nullopt;
  }

  try {
    const auto root = std::filesystem::temp_directory_path() /
                      L"flutter_cockpit_recordings";
    std::error_code error;
    std::filesystem::create_directories(root, error);
    if (error) {
      if (failure_reason != nullptr) {
        *failure_reason = "recordingInvalidPath";
      }
      return std::nullopt;
    }
    const auto canonical_root = std::filesystem::weakly_canonical(root, error);
    const auto candidate = canonical_root /
                           std::filesystem::path(relative_wide).lexically_normal();
    const auto canonical_parent =
        std::filesystem::weakly_canonical(candidate.parent_path(), error);
    if (error) {
      if (failure_reason != nullptr) {
        *failure_reason = "recordingInvalidPath";
      }
      return std::nullopt;
    }
    const auto relative_parent =
        std::filesystem::relative(canonical_parent, canonical_root, error);
    const auto relative_parent_string = relative_parent.string();
    if (error || relative_parent == L".." ||
        relative_parent_string.rfind("..", 0) == 0) {
      if (failure_reason != nullptr) {
        *failure_reason = "recordingInvalidPath";
      }
      return std::nullopt;
    }
    std::filesystem::create_directories(canonical_parent, error);
    if (error) {
      if (failure_reason != nullptr) {
        *failure_reason = "recordingInvalidPath";
      }
      return std::nullopt;
    }
    return canonical_parent / candidate.filename();
  } catch (const std::filesystem::filesystem_error&) {
    if (failure_reason != nullptr) {
      *failure_reason = "recordingInvalidPath";
    }
    return std::nullopt;
  } catch (const std::exception&) {
    if (failure_reason != nullptr) {
      *failure_reason = "recordingInvalidPath";
    }
    return std::nullopt;
  }
}

bool WaitForNonEmptyFile(const std::filesystem::path& path,
                         std::chrono::milliseconds timeout) {
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  while (std::chrono::steady_clock::now() < deadline) {
    std::error_code error;
    if (std::filesystem::exists(path, error) &&
        std::filesystem::file_size(path, error) > 0) {
      return true;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }
  std::error_code error;
  return std::filesystem::exists(path, error) &&
         std::filesystem::file_size(path, error) > 0;
}

int GetEncoderClsid(const WCHAR* format, CLSID* clsid) {
  UINT encoder_count = 0;
  UINT encoder_bytes = 0;
  Gdiplus::GetImageEncodersSize(&encoder_count, &encoder_bytes);
  if (encoder_bytes == 0) {
    return -1;
  }

  auto image_codec_info = std::make_unique<uint8_t[]>(encoder_bytes);
  auto* codec_info = reinterpret_cast<Gdiplus::ImageCodecInfo*>(
      image_codec_info.get());
  if (Gdiplus::GetImageEncoders(encoder_count, encoder_bytes, codec_info) !=
      Gdiplus::Ok) {
    return -1;
  }

  for (UINT i = 0; i < encoder_count; ++i) {
    if (wcscmp(codec_info[i].MimeType, format) == 0) {
      *clsid = codec_info[i].Clsid;
      return static_cast<int>(i);
    }
  }
  return -1;
}

bool CaptureWindowFrame(HWND hwnd,
                        int target_width,
                        int target_height,
                        WindowFrame* frame,
                        std::string* failure_reason) {
  RECT rect{};
  if (!GetClientRect(hwnd, &rect)) {
    if (failure_reason != nullptr) {
      *failure_reason = "GetClientRect failed.";
    }
    return false;
  }

  const int source_width = rect.right - rect.left;
  const int source_height = rect.bottom - rect.top;
  if (source_width <= 0 || source_height <= 0) {
    if (failure_reason != nullptr) {
      *failure_reason = "Window client area is not visible.";
    }
    return false;
  }

  const int width = target_width > 0 ? target_width : source_width;
  const int height = target_height > 0 ? target_height : source_height;
  if (width <= 0 || height <= 0) {
    if (failure_reason != nullptr) {
      *failure_reason = "Invalid target dimensions.";
    }
    return false;
  }

  HDC window_dc = GetDC(hwnd);
  if (window_dc == nullptr) {
    if (failure_reason != nullptr) {
      *failure_reason = "GetDC failed.";
    }
    return false;
  }

  HDC memory_dc = CreateCompatibleDC(window_dc);
  if (memory_dc == nullptr) {
    ReleaseDC(hwnd, window_dc);
    if (failure_reason != nullptr) {
      *failure_reason = "CreateCompatibleDC failed.";
    }
    return false;
  }

  BITMAPINFO bitmap_info{};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = width;
  bitmap_info.bmiHeader.biHeight = -height;
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;

  void* dib_pixels = nullptr;
  HBITMAP dib = CreateDIBSection(window_dc, &bitmap_info, DIB_RGB_COLORS,
                                 &dib_pixels, nullptr, 0);
  if (dib == nullptr || dib_pixels == nullptr) {
    DeleteDC(memory_dc);
    ReleaseDC(hwnd, window_dc);
    if (failure_reason != nullptr) {
      *failure_reason = "CreateDIBSection failed.";
    }
    return false;
  }

  HGDIOBJ old_bitmap = SelectObject(memory_dc, dib);
  SetStretchBltMode(memory_dc, HALFTONE);

  BOOL copied = FALSE;
  if (width == source_width && height == source_height) {
    copied = BitBlt(memory_dc, 0, 0, width, height, window_dc, 0, 0,
                    SRCCOPY | CAPTUREBLT);
  } else {
    copied = StretchBlt(memory_dc, 0, 0, width, height, window_dc, 0, 0,
                        source_width, source_height, SRCCOPY | CAPTUREBLT);
  }

  if (!copied) {
    copied = PrintWindow(hwnd, memory_dc, PW_CLIENTONLY);
  }

  bool success = false;
  if (copied) {
    auto* pixels = static_cast<uint8_t*>(dib_pixels);
    const size_t byte_count = static_cast<size_t>(width) *
                              static_cast<size_t>(height) * 4;
    for (size_t offset = 3; offset < byte_count; offset += 4) {
      pixels[offset] = 0xFF;
    }
    frame->width = width;
    frame->height = height;
    frame->pixels.assign(pixels, pixels + byte_count);
    success = true;
  } else if (failure_reason != nullptr) {
    *failure_reason = "Window capture failed.";
  }

  SelectObject(memory_dc, old_bitmap);
  DeleteObject(dib);
  DeleteDC(memory_dc);
  ReleaseDC(hwnd, window_dc);
  return success;
}

bool EncodePng(const WindowFrame& frame,
               std::vector<uint8_t>* png_bytes,
               std::string* failure_reason) {
  CLSID png_clsid{};
  if (GetEncoderClsid(L"image/png", &png_clsid) < 0) {
    if (failure_reason != nullptr) {
      *failure_reason = "Unable to resolve the PNG encoder.";
    }
    return false;
  }

  Gdiplus::Bitmap bitmap(frame.width, frame.height, frame.width * 4,
                         PixelFormat32bppARGB,
                         const_cast<BYTE*>(frame.pixels.data()));
  if (bitmap.GetLastStatus() != Gdiplus::Ok) {
    if (failure_reason != nullptr) {
      *failure_reason = "Failed to construct a GDI+ bitmap.";
    }
    return false;
  }

  IStream* stream = nullptr;
  if (CreateStreamOnHGlobal(nullptr, TRUE, &stream) != S_OK) {
    if (failure_reason != nullptr) {
      *failure_reason = "CreateStreamOnHGlobal failed.";
    }
    return false;
  }

  const Gdiplus::Status save_status = bitmap.Save(stream, &png_clsid, nullptr);
  if (save_status != Gdiplus::Ok) {
    stream->Release();
    if (failure_reason != nullptr) {
      *failure_reason = "Bitmap::Save failed.";
    }
    return false;
  }

  STATSTG stat{};
  if (stream->Stat(&stat, STATFLAG_NONAME) != S_OK) {
    stream->Release();
    if (failure_reason != nullptr) {
      *failure_reason = "Failed to stat PNG stream.";
    }
    return false;
  }

  LARGE_INTEGER zero{};
  stream->Seek(zero, STREAM_SEEK_SET, nullptr);

  const size_t byte_count = static_cast<size_t>(stat.cbSize.QuadPart);
  png_bytes->assign(byte_count, 0);
  ULONG bytes_read = 0;
  const HRESULT read_result =
      stream->Read(png_bytes->data(), static_cast<ULONG>(byte_count), &bytes_read);
  stream->Release();

  if (FAILED(read_result) || bytes_read != byte_count) {
    if (failure_reason != nullptr) {
      *failure_reason = "Failed to read encoded PNG bytes.";
    }
    return false;
  }

  return true;
}

HRESULT CreateVideoWriter(const std::wstring& output_path,
                          uint32_t width,
                          uint32_t height,
                          ComPtr<IMFSinkWriter>* writer,
                          DWORD* stream_index) {
  ComPtr<IMFSinkWriter> sink_writer;
  HRESULT hr = MFCreateSinkWriterFromURL(output_path.c_str(), nullptr, nullptr,
                                         sink_writer.GetAddressOf());
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IMFMediaType> output_type;
  hr = MFCreateMediaType(output_type.GetAddressOf());
  if (FAILED(hr)) {
    return hr;
  }
  output_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  output_type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
  output_type->SetUINT32(MF_MT_AVG_BITRATE,
                         (std::max)(width * height * 8u, 2'000'000u));
  output_type->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  MFSetAttributeSize(output_type.Get(), MF_MT_FRAME_SIZE, width, height);
  MFSetAttributeRatio(output_type.Get(), MF_MT_FRAME_RATE, kRecordingFrameRate,
                      1);
  MFSetAttributeRatio(output_type.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);

  hr = sink_writer->AddStream(output_type.Get(), stream_index);
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IMFMediaType> input_type;
  hr = MFCreateMediaType(input_type.GetAddressOf());
  if (FAILED(hr)) {
    return hr;
  }
  input_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  input_type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
  input_type->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  MFSetAttributeSize(input_type.Get(), MF_MT_FRAME_SIZE, width, height);
  MFSetAttributeRatio(input_type.Get(), MF_MT_FRAME_RATE, kRecordingFrameRate,
                      1);
  MFSetAttributeRatio(input_type.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
  input_type->SetUINT32(MF_MT_SAMPLE_SIZE, width * height * 4);
  input_type->SetUINT32(MF_MT_FIXED_SIZE_SAMPLES, TRUE);
  input_type->SetUINT32(MF_MT_DEFAULT_STRIDE, width * 4);

  hr = sink_writer->SetInputMediaType(*stream_index, input_type.Get(), nullptr);
  if (FAILED(hr)) {
    return hr;
  }

  hr = sink_writer->BeginWriting();
  if (FAILED(hr)) {
    return hr;
  }

  *writer = std::move(sink_writer);
  return S_OK;
}

HRESULT WriteVideoFrame(IMFSinkWriter* writer,
                        DWORD stream_index,
                        const WindowFrame& frame,
                        int64_t frame_index) {
  const LONGLONG sample_duration = 10'000'000 / kRecordingFrameRate;
  const LONGLONG sample_time = frame_index * sample_duration;
  const DWORD buffer_length =
      static_cast<DWORD>(frame.width * frame.height * 4);

  ComPtr<IMFMediaBuffer> buffer;
  HRESULT hr = MFCreateMemoryBuffer(buffer_length, buffer.GetAddressOf());
  if (FAILED(hr)) {
    return hr;
  }

  BYTE* destination = nullptr;
  DWORD max_length = 0;
  DWORD current_length = 0;
  hr = buffer->Lock(&destination, &max_length, &current_length);
  if (FAILED(hr)) {
    return hr;
  }

  memcpy(destination, frame.pixels.data(), buffer_length);
  buffer->Unlock();
  buffer->SetCurrentLength(buffer_length);

  ComPtr<IMFSample> sample;
  hr = MFCreateSample(sample.GetAddressOf());
  if (FAILED(hr)) {
    return hr;
  }

  sample->AddBuffer(buffer.Get());
  sample->SetSampleTime(sample_time);
  sample->SetSampleDuration(sample_duration);
  return writer->WriteSample(stream_index, sample.Get());
}

}  // namespace

class FlutterCockpitWindowRecorder {
 public:
  FlutterCockpitWindowRecorder(HWND hwnd, std::filesystem::path output_path)
      : hwnd_(hwnd), output_path_(std::move(output_path)) {}

  ~FlutterCockpitWindowRecorder() {
    RequestStop();
    DetachRecordingThread();
  }

  bool Start(std::string* failure_reason) {
    RECT rect{};
    if (!GetClientRect(hwnd_, &rect)) {
      *failure_reason = "GetClientRect failed for the Flutter window.";
      return false;
    }

    const int width = EvenDimension(rect.right - rect.left);
    const int height = EvenDimension(rect.bottom - rect.top);
    if (width <= 0 || height <= 0) {
      *failure_reason = "The Flutter window is not ready for recording.";
      return false;
    }

    state_ = std::make_shared<RecordingWorkerState>(hwnd_, output_path_, width,
                                                    height);
    std::promise<RecordingStartStatus> ready_promise;
    auto ready_future = ready_promise.get_future();
    std::promise<RecordingRunResult> run_promise;
    run_future_ = run_promise.get_future();
    run_thread_ = std::thread(
        [state = state_, ready = std::move(ready_promise),
         done = std::move(run_promise)]() mutable {
          done.set_value(Run(state, std::move(ready)));
        });

    if (ready_future.wait_for(kRecordingStartupTimeout) !=
        std::future_status::ready) {
      RequestStop();
      if (run_future_.valid() &&
          run_future_.wait_for(kRecordingStartupCancelTimeout) ==
              std::future_status::ready) {
        JoinRecordingThread();
      } else {
        DetachRecordingThread();
      }
      *failure_reason = RecordingStartupTimeoutMessage();
      return false;
    }

    RecordingStartStatus ready = ready_future.get();
    if (!ready.success) {
      JoinRecordingThread();
      *failure_reason = ready.failure_reason;
      return false;
    }

    return true;
  }

  RecordingRunResult Stop() {
    RequestStop();
    if (!run_future_.valid()) {
      return RecordingRunResult{
          false, "recordingNotActive", 0,
      };
    }
    if (run_future_.wait_for(kRecordingStopTimeout) !=
        std::future_status::ready) {
      DetachRecordingThread();
      return RecordingRunResult{
          false, "recordingFinalizeTimeout", 0,
      };
    }
    JoinRecordingThread();
    return run_future_.get();
  }

  const std::filesystem::path& output_path() const { return output_path_; }

 private:
  void RequestStop() {
    if (state_ != nullptr) {
      state_->stop_requested.store(true);
    }
  }

  void JoinRecordingThread() {
    if (run_thread_.joinable()) {
      run_thread_.join();
    }
  }

  void DetachRecordingThread() {
    if (run_thread_.joinable()) {
      run_thread_.detach();
    }
  }

  static RecordingRunResult Run(
      std::shared_ptr<RecordingWorkerState> state,
      std::promise<RecordingStartStatus> ready_promise) {
    HRESULT coinit = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool must_uninitialize =
        SUCCEEDED(coinit) || coinit == RPC_E_CHANGED_MODE;
    HRESULT hr = MFStartup(MF_VERSION);
    if (FAILED(hr)) {
      ready_promise.set_value(
          RecordingStartStatus{false, "MFStartup failed: " + HrToString(hr)});
      if (must_uninitialize && coinit != RPC_E_CHANGED_MODE) {
        CoUninitialize();
      }
      return RecordingRunResult{false, "MFStartup failed", 0};
    }

    if (state->stop_requested.load()) {
      ready_promise.set_value(
          RecordingStartStatus{false, "recordingStartupCancelled"});
      MFShutdown();
      if (must_uninitialize && coinit != RPC_E_CHANGED_MODE) {
        CoUninitialize();
      }
      return RecordingRunResult{false, "recordingStartupCancelled", 0};
    }

    ComPtr<IMFSinkWriter> writer;
    DWORD stream_index = 0;
    hr = CreateVideoWriter(state->output_path.wstring(),
                           static_cast<uint32_t>(state->width),
                           static_cast<uint32_t>(state->height), &writer,
                           &stream_index);
    if (FAILED(hr)) {
      ready_promise.set_value(RecordingStartStatus{
          false, "CreateVideoWriter failed: " + HrToString(hr)});
      MFShutdown();
      if (must_uninitialize && coinit != RPC_E_CHANGED_MODE) {
        CoUninitialize();
      }
      return RecordingRunResult{false, "CreateVideoWriter failed", 0};
    }

    if (state->stop_requested.load()) {
      ready_promise.set_value(
          RecordingStartStatus{false, "recordingStartupCancelled"});
      MFShutdown();
      if (must_uninitialize && coinit != RPC_E_CHANGED_MODE) {
        CoUninitialize();
      }
      return RecordingRunResult{false, "recordingStartupCancelled", 0};
    }

    ready_promise.set_value(RecordingStartStatus{true, ""});

    RecordingRunResult run_result{true, "", 0};
    int64_t frame_index = 0;
    auto next_tick = std::chrono::steady_clock::now();

    while (!state->stop_requested.load()) {
      WindowFrame frame;
      if (CaptureWindowFrame(state->hwnd, state->width, state->height, &frame,
                             &run_result.failure_reason)) {
        hr = WriteVideoFrame(writer.Get(), stream_index, frame, frame_index++);
        if (FAILED(hr)) {
          run_result.success = false;
          run_result.failure_reason =
              "WriteSample failed: " + HrToString(hr);
          break;
        }
        run_result.captured_frame_count += 1;
      } else if (run_result.captured_frame_count == 0) {
        run_result.failure_reason = "Window frame capture never succeeded.";
      }

      next_tick += std::chrono::milliseconds(1000 / kRecordingFrameRate);
      std::this_thread::sleep_until(next_tick);
    }

    WindowFrame final_frame;
    if (run_result.success &&
        CaptureWindowFrame(state->hwnd, state->width, state->height,
                           &final_frame, nullptr)) {
      hr = WriteVideoFrame(writer.Get(), stream_index, final_frame, frame_index++);
      if (SUCCEEDED(hr)) {
        run_result.captured_frame_count += 1;
      }
    }

    HRESULT finalize_hr = writer->Finalize();
    if (run_result.success && FAILED(finalize_hr)) {
      run_result.success = false;
      run_result.failure_reason =
          "Finalize failed: " + HrToString(finalize_hr);
    }

    if (run_result.success && run_result.captured_frame_count == 0) {
      run_result.success = false;
      run_result.failure_reason = "recordingCapturedNoFrames";
    }

    if (run_result.success &&
        !WaitForNonEmptyFile(state->output_path, std::chrono::seconds(2))) {
      run_result.success = false;
      run_result.failure_reason = "recordingOutputMissing";
    }

    MFShutdown();
    if (must_uninitialize && coinit != RPC_E_CHANGED_MODE) {
      CoUninitialize();
    }
    return run_result;
  }

  HWND hwnd_;
  std::filesystem::path output_path_;
  std::shared_ptr<RecordingWorkerState> state_;
  std::future<RecordingRunResult> run_future_;
  std::thread run_thread_;
};

void FlutterCockpitPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<FlutterCockpitPlugin>(registrar);

  auto capture_channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar->messenger(), kCaptureChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  auto recording_channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar->messenger(), kRecordingChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  auto viewport_channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar->messenger(), kViewportChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  capture_channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleCaptureMethodCall(call, std::move(result));
      });
  recording_channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleRecordingMethodCall(call, std::move(result));
      });
  viewport_channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleViewportMethodCall(call, std::move(result));
      });

  plugin->capture_channel_ = std::move(capture_channel);
  plugin->recording_channel_ = std::move(recording_channel);
  plugin->viewport_channel_ = std::move(viewport_channel);
  registrar->AddPlugin(std::move(plugin));
}

FlutterCockpitPlugin::FlutterCockpitPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  Gdiplus::GdiplusStartupInput startup_input;
  Gdiplus::GdiplusStartup(&gdiplus_token_, &startup_input, nullptr);
}

FlutterCockpitPlugin::~FlutterCockpitPlugin() {
  if (recording_state_ != RecordingState::Idle && active_recorder_ != nullptr) {
    recording_state_ = RecordingState::Stopping;
    active_recorder_->Stop();
  }
  if (gdiplus_token_ != 0) {
    Gdiplus::GdiplusShutdown(gdiplus_token_);
  }
}

void FlutterCockpitPlugin::HandleCaptureMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (method_call.method_name() == "queryNativeCaptureAvailability") {
    QueryNativeCaptureAvailability(std::move(result));
    return;
  }
  if (method_call.method_name() == "captureAcceptanceScreenshot") {
    CaptureAcceptanceScreenshot(std::move(result));
    return;
  }
  result->NotImplemented();
}

void FlutterCockpitPlugin::HandleRecordingMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (method_call.method_name() == "queryRecordingCapabilities") {
    QueryRecordingCapabilities(std::move(result));
    return;
  }
  if (method_call.method_name() == "startRecording") {
    StartRecording(method_call, std::move(result));
    return;
  }
  if (method_call.method_name() == "stopRecording") {
    StopRecording(std::move(result));
    return;
  }
  result->NotImplemented();
}

void FlutterCockpitPlugin::HandleViewportMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (method_call.method_name() == "queryViewportAvailability") {
    EncodableMap payload;
    payload[EncodableValue("available")] =
        EncodableValue(ActiveWindowHandle() != nullptr);
    payload[EncodableValue("alternatives")] =
        EncodableValue(std::vector<EncodableValue>{});
    result->Success(EncodableValue(payload));
    return;
  }
  if (method_call.method_name() == "resizeViewport") {
    ResizeViewport(method_call, std::move(result));
    return;
  }
  result->NotImplemented();
}

HWND FlutterCockpitPlugin::ActiveWindowHandle() const {
  auto* view = registrar_ == nullptr ? nullptr : registrar_->GetView();
  return view == nullptr ? nullptr : view->GetNativeWindow();
}

void FlutterCockpitPlugin::QueryNativeCaptureAvailability(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  result->Success(EncodableValue(ActiveWindowHandle() != nullptr));
}

void FlutterCockpitPlugin::CaptureAcceptanceScreenshot(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  HWND hwnd = ActiveWindowHandle();
  if (hwnd == nullptr) {
    result->Error("noWindow",
                  "Native capture requires an active Flutter HWND.");
    return;
  }

  WindowFrame frame;
  std::string failure_reason;
  if (!CaptureWindowFrame(hwnd, 0, 0, &frame, &failure_reason)) {
    result->Error("captureFailed", failure_reason);
    return;
  }

  std::vector<uint8_t> png_bytes;
  if (!EncodePng(frame, &png_bytes, &failure_reason)) {
    result->Error("encodeFailed", failure_reason);
    return;
  }

  EncodableMap payload;
  payload[EncodableValue("bytes")] = EncodableValue(png_bytes);
  result->Success(EncodableValue(payload));
}

void FlutterCockpitPlugin::ResizeViewport(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  HWND hwnd = ActiveWindowHandle();
  if (hwnd == nullptr) {
    result->Error("noWindow", "Viewport resize requires an active Flutter HWND.");
    return;
  }
  const auto width = GetIntArgument(method_call.arguments(), "width");
  const auto height = GetIntArgument(method_call.arguments(), "height");
  if (!width.has_value() || !height.has_value()) {
    result->Error("invalidViewport",
                  "Viewport width and height must be integers.");
    return;
  }

  const UINT dpi = GetDpiForWindow(hwnd);
  const double scale = static_cast<double>(dpi) / 96.0;
  RECT bounds = {0, 0, static_cast<LONG>(std::lround(*width * scale)),
                 static_cast<LONG>(std::lround(*height * scale))};
  const DWORD style = static_cast<DWORD>(GetWindowLongPtr(hwnd, GWL_STYLE));
  const DWORD extended_style =
      static_cast<DWORD>(GetWindowLongPtr(hwnd, GWL_EXSTYLE));
  if (!AdjustWindowRectExForDpi(&bounds, style, FALSE, extended_style, dpi)) {
    result->Error("viewportResizeFailed",
                  "Unable to calculate the DPI-aware window bounds.");
    return;
  }
  if (!SetWindowPos(hwnd, nullptr, 0, 0, bounds.right - bounds.left,
                    bounds.bottom - bounds.top,
                    SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE)) {
    result->Error("viewportResizeFailed", "Unable to resize the Flutter window.");
    return;
  }
  EncodableMap payload;
  payload[EncodableValue("accepted")] = EncodableValue(true);
  result->Success(EncodableValue(payload));
}

void FlutterCockpitPlugin::QueryRecordingCapabilities(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  EncodableMap payload;
  payload[EncodableValue("supportsNativeRecording")] =
      EncodableValue(ActiveWindowHandle() != nullptr);
  payload[EncodableValue("preferredAcceptanceRecordingKind")] =
      EncodableValue("nativeScreen");
  payload[EncodableValue("supportedLayers")] =
      EncodableValue(std::vector<EncodableValue>{EncodableValue("app-window")});
  payload[EncodableValue("preferredLayer")] = EncodableValue("app-window");
  payload[EncodableValue("recordingLimitations")] = EncodableValue(
      std::vector<EncodableValue>{
          EncodableValue(
              "Native Windows recording captures the Flutter app window content only."),
          EncodableValue(
              "Window chrome and other desktop surfaces are not included."),
      });
  result->Success(EncodableValue(payload));
}

void FlutterCockpitPlugin::StartRecording(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (recording_state_ == RecordingState::Starting ||
      recording_state_ == RecordingState::Recording) {
    result->Error("recordingAlreadyActive",
                  "A recording session is already active.");
    return;
  }
  if (recording_state_ == RecordingState::Stopping) {
    result->Error("recordingAlreadyStopping",
                  "The previous recording session is still finalizing.");
    return;
  }

  recording_state_ = RecordingState::Starting;
  session_token_ += 1;

  HWND hwnd = ActiveWindowHandle();
  if (hwnd == nullptr) {
    recording_state_ = RecordingState::Idle;
    result->Error("recordingNoWindow",
                  "Native recording requires an active Flutter HWND.");
    return;
  }

  const std::string relative_path =
      GetStringArgument(method_call.arguments(), "relativePath")
          .value_or("recordings/flutter_cockpit.mp4");
  std::string path_failure;
  const auto output_path =
      BuildTemporaryArtifactPath(relative_path, &path_failure);
  if (!output_path.has_value()) {
    recording_state_ = RecordingState::Idle;
    result->Error("recordingInvalidPath", path_failure);
    return;
  }
  std::error_code error;
  std::filesystem::remove(*output_path, error);
  if (error) {
    recording_state_ = RecordingState::Idle;
    result->Error("recordingInvalidPath", "Unable to prepare the recording output path.");
    return;
  }

  auto recorder =
      std::make_unique<FlutterCockpitWindowRecorder>(hwnd, *output_path);
  std::string failure_reason;
  if (!recorder->Start(&failure_reason)) {
    recording_state_ = RecordingState::Idle;
    result->Error("recordingStartFailed", failure_reason);
    return;
  }

  active_recorder_ = std::move(recorder);
  recording_started_at_ = std::chrono::steady_clock::now();
  recording_state_ = RecordingState::Recording;

  EncodableMap payload;
  payload[EncodableValue("state")] = EncodableValue("recording");
  result->Success(EncodableValue(payload));
}

void FlutterCockpitPlugin::StopRecording(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (recording_state_ == RecordingState::Stopping) {
    result->Error("recordingAlreadyStopping",
                  "The previous recording session is still finalizing.");
    return;
  }
  if (recording_state_ != RecordingState::Recording ||
      active_recorder_ == nullptr) {
    EncodableMap payload;
    payload[EncodableValue("state")] = EncodableValue("failed");
    payload[EncodableValue("failureReason")] =
        EncodableValue("recordingNotActive");
    result->Success(EncodableValue(payload));
    return;
  }

  const auto duration_ms = static_cast<int64_t>(
      std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now() - recording_started_at_)
          .count());

  recording_state_ = RecordingState::Stopping;
  const uint64_t token = session_token_;
  RecordingRunResult stop_result = active_recorder_->Stop();
  std::string source_file_path;
  if (!WideToUtf8(active_recorder_->output_path().wstring(), &source_file_path)) {
    active_recorder_.reset();
    recording_state_ = RecordingState::Idle;
    result->Error("recordingPathConversionFailed",
                  "Unable to convert the recording output path to UTF-8.");
    return;
  }
  active_recorder_.reset();
  recording_state_ = RecordingState::Idle;

  if (token != session_token_) {
    result->Error("recordingStaleSession", "The recording session was superseded.");
    return;
  }

  EncodableMap payload;
  if (!stop_result.success) {
    payload[EncodableValue("state")] = EncodableValue("failed");
    payload[EncodableValue("failureReason")] =
        EncodableValue(stop_result.failure_reason);
    result->Success(EncodableValue(payload));
    return;
  }

  payload[EncodableValue("state")] = EncodableValue("completed");
  payload[EncodableValue("recordingKind")] = EncodableValue("nativeScreen");
  payload[EncodableValue("effectiveLayer")] = EncodableValue("app-window");
  payload[EncodableValue("durationMs")] = EncodableValue(duration_ms);
  payload[EncodableValue("sourceFilePath")] = EncodableValue(source_file_path);
  result->Success(EncodableValue(payload));
}

}  // namespace flutter_cockpit
