#include "include/flutter_cockpit/flutter_cockpit_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gst/app/gstappsrc.h>
#include <gst/gst.h>
#include <gtk/gtk.h>

#include <chrono>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#define FLUTTER_COCKPIT_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), flutter_cockpit_plugin_get_type(), \
                              FlutterCockpitPlugin))

namespace {
class CockpitLinuxRecorder;
}

struct _FlutterCockpitPlugin {
  GObject parent_instance;
  GWeakRef view_ref;
  CockpitLinuxRecorder* active_recorder;
  gint64 recording_started_at_us;
  enum class RecordingState {
    Idle,
    Starting,
    Recording,
    Stopping,
  } recording_state;
  guint64 session_token;
};

G_DEFINE_TYPE(FlutterCockpitPlugin,
              flutter_cockpit_plugin,
              g_object_get_type())

namespace {

constexpr char kCaptureChannelName[] = "dev.cockpit.flutter_cockpit/capture";
constexpr char kRecordingChannelName[] =
    "dev.cockpit.flutter_cockpit/recording";
constexpr char kViewportChannelName[] = "dev.cockpit.flutter_cockpit/viewport";
constexpr int kRecordingFrameRate = 15;
constexpr guint kRecordingFrameIntervalMs = 1000 / kRecordingFrameRate;
constexpr auto kRecordingStopTimeout = std::chrono::seconds(10);

template <typename T>
void UnrefGObject(T* object) {
  if (object != nullptr) {
    g_object_unref(object);
  }
}

template <typename T>
using GObjectHandle = std::unique_ptr<T, decltype(&UnrefGObject<T>)>;

template <typename T>
GObjectHandle<T> AdoptGObject(T* object) {
  return GObjectHandle<T>(object, &UnrefGObject<T>);
}

struct PixbufCapture {
  GObjectHandle<GdkPixbuf> pixbuf =
      AdoptGObject<GdkPixbuf>(nullptr);
  std::string failure_reason;
  bool success = false;
};

struct FrameCapture {
  int width = 0;
  int height = 0;
  std::vector<uint8_t> rgba;
  std::string failure_reason;
  bool success = false;
};

struct RecordingStopResult {
  bool success = false;
  std::string failure_reason;
  int captured_frame_count = 0;
};

std::once_flag gstreamer_once;

void EnsureGStreamerInitialized() {
  std::call_once(gstreamer_once, []() {
    gst_init(nullptr, nullptr);
  });
}

bool HasRecordingPipelineSupport() {
  EnsureGStreamerInitialized();
  const char* required_factories[] = {
      "appsrc",
      "videoconvert",
      "mp4mux",
      "filesink",
  };
  for (const char* factory : required_factories) {
    GstElementFactory* element_factory = gst_element_factory_find(factory);
    if (element_factory == nullptr) {
      if (std::strcmp(factory, "mp4mux") == 0) {
        element_factory = gst_element_factory_find("qtmux");
      }
    }
    if (element_factory == nullptr) {
      return false;
    }
    gst_object_unref(element_factory);
  }

  const char* encoders[] = {"x264enc", "openh264enc", "avenc_h264", "avenc_mpeg4"};
  for (const char* encoder : encoders) {
    GstElementFactory* element_factory = gst_element_factory_find(encoder);
    if (element_factory != nullptr) {
      gst_object_unref(element_factory);
      if (std::strcmp(encoder, "avenc_mpeg4") != 0) {
        GstElementFactory* parser = gst_element_factory_find("h264parse");
        if (parser == nullptr) {
          continue;
        }
        gst_object_unref(parser);
      }
      return true;
    }
  }
  return false;
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

  auto root = std::filesystem::temp_directory_path() /
              "flutter_cockpit_recordings";
  try {
    std::error_code error;
    std::filesystem::create_directories(root, error);
    if (error) {
      if (failure_reason != nullptr) {
        *failure_reason = "recordingInvalidPath";
      }
      return std::nullopt;
    }
    const auto canonical_root = std::filesystem::weakly_canonical(root, error);
    if (error) {
      if (failure_reason != nullptr) {
        *failure_reason = "recordingInvalidPath";
      }
      return std::nullopt;
    }
    const auto candidate = canonical_root /
                           std::filesystem::path(relative).lexically_normal();
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
    if (error || relative_parent == ".." ||
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

std::optional<std::string> GetStringArgument(FlMethodCall* method_call,
                                             const char* key) {
  FlValue* args = fl_method_call_get_args(method_call);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return std::nullopt;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return std::nullopt;
  }
  return std::string(fl_value_get_string(value));
}

std::optional<int> GetIntArgument(FlMethodCall* method_call, const char* key) {
  FlValue* args = fl_method_call_get_args(method_call);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return std::nullopt;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return std::nullopt;
  }
  const int64_t parsed = fl_value_get_int(value);
  if (parsed < 1 || parsed > 8192) {
    return std::nullopt;
  }
  return static_cast<int>(parsed);
}

GObjectHandle<FlView> GetActiveView(FlutterCockpitPlugin* self) {
  return AdoptGObject<FlView>(
      FL_VIEW(g_weak_ref_get(&self->view_ref)));
}

PixbufCapture CaptureViewPixbuf(FlView* view) {
  PixbufCapture capture;
  if (view == nullptr) {
    capture.failure_reason = "Native Linux capture requires an active FlView.";
    return capture;
  }

  GtkWidget* widget = GTK_WIDGET(view);
  if (!gtk_widget_get_realized(widget)) {
    capture.failure_reason =
        "Native Linux capture requires a realized GTK widget.";
    return capture;
  }

  GdkWindow* window = gtk_widget_get_window(widget);
  if (window == nullptr) {
    capture.failure_reason =
        "Native Linux capture requires a realized GdkWindow.";
    return capture;
  }

  gint width = 0;
  gint height = 0;
  gdk_window_get_geometry(window, nullptr, nullptr, &width, &height);
  if (width <= 0 || height <= 0) {
    const auto scale = gtk_widget_get_scale_factor(widget);
    width = gtk_widget_get_allocated_width(widget) * std::max(scale, 1);
    height = gtk_widget_get_allocated_height(widget) * std::max(scale, 1);
  }
  if (width <= 0 || height <= 0) {
    capture.failure_reason =
        "Native Linux capture requires a visible Flutter view.";
    return capture;
  }

  auto pixbuf =
      AdoptGObject<GdkPixbuf>(gdk_pixbuf_get_from_window(window, 0, 0, width, height));
  if (!pixbuf) {
    capture.failure_reason =
        "GDK could not snapshot the active Flutter window.";
    return capture;
  }

  capture.pixbuf = std::move(pixbuf);
  capture.success = true;
  return capture;
}

FrameCapture ConvertPixbufToRgba(GdkPixbuf* pixbuf) {
  FrameCapture frame;
  if (pixbuf == nullptr) {
    frame.failure_reason = "Pixbuf capture was null.";
    return frame;
  }

  const int width = gdk_pixbuf_get_width(pixbuf);
  const int height = gdk_pixbuf_get_height(pixbuf);
  const int channels = gdk_pixbuf_get_n_channels(pixbuf);
  const bool has_alpha = gdk_pixbuf_get_has_alpha(pixbuf);
  const int rowstride = gdk_pixbuf_get_rowstride(pixbuf);
  const guchar* pixels = gdk_pixbuf_get_pixels(pixbuf);
  if (width <= 0 || height <= 0 || pixels == nullptr || channels < 3) {
    frame.failure_reason = "Captured Linux pixbuf was invalid.";
    return frame;
  }

  frame.width = width;
  frame.height = height;
  frame.rgba.resize(static_cast<size_t>(width * height * 4));

  for (int y = 0; y < height; ++y) {
    const guchar* source_row = pixels + (y * rowstride);
    uint8_t* destination_row = frame.rgba.data() + (y * width * 4);
    for (int x = 0; x < width; ++x) {
      const guchar* source = source_row + (x * channels);
      uint8_t* destination = destination_row + (x * 4);
      destination[0] = source[0];
      destination[1] = source[1];
      destination[2] = source[2];
      destination[3] = (has_alpha && channels >= 4) ? source[3] : 0xFF;
    }
  }

  frame.success = true;
  return frame;
}

bool EncodePixbufPng(GdkPixbuf* pixbuf,
                     std::vector<uint8_t>* bytes,
                     std::string* failure_reason) {
  gchar* buffer = nullptr;
  gsize buffer_size = 0;
  GError* error = nullptr;
  const gboolean saved = gdk_pixbuf_save_to_buffer(
      pixbuf, &buffer, &buffer_size, "png", &error, nullptr);
  if (!saved || buffer == nullptr) {
    if (failure_reason != nullptr) {
      *failure_reason = error == nullptr
          ? "GDK failed to encode a PNG screenshot."
          : error->message;
    }
    if (error != nullptr) {
      g_error_free(error);
    }
    return false;
  }

  bytes->assign(reinterpret_cast<uint8_t*>(buffer),
                reinterpret_cast<uint8_t*>(buffer) + buffer_size);
  g_free(buffer);
  if (error != nullptr) {
    g_error_free(error);
  }
  return true;
}

gboolean HasGObjectProperty(gpointer instance, const char* property_name) {
  return g_object_class_find_property(
             G_OBJECT_GET_CLASS(instance), property_name) != nullptr;
}

class CockpitLinuxRecorder {
 public:
  CockpitLinuxRecorder(FlView* view, std::filesystem::path output_path)
      : output_path_(std::move(output_path)) {
    g_weak_ref_init(&view_ref_, G_OBJECT(view));
  }

  ~CockpitLinuxRecorder() {
    if (timer_id_ != 0) {
      g_source_remove(timer_id_);
      timer_id_ = 0;
    }
    if (pipeline_ != nullptr) {
      gst_element_set_state(pipeline_, GST_STATE_NULL);
      gst_object_unref(pipeline_);
      pipeline_ = nullptr;
    }
    g_weak_ref_clear(&view_ref_);
  }

  bool Start(std::string* failure_reason) {
    EnsureGStreamerInitialized();

    auto view = GetView();
    auto pixbuf_capture = CaptureViewPixbuf(view.get());
    if (!pixbuf_capture.success) {
      *failure_reason = pixbuf_capture.failure_reason;
      return false;
    }

    auto frame = ConvertPixbufToRgba(pixbuf_capture.pixbuf.get());
    if (!frame.success) {
      *failure_reason = frame.failure_reason;
      return false;
    }

    width_ = frame.width;
    height_ = frame.height;

    std::error_code error;
    std::filesystem::create_directories(output_path_.parent_path(), error);
    std::filesystem::remove(output_path_, error);

    if (!CreatePipeline(failure_reason)) {
      return false;
    }

    if (!PushFrame(frame, failure_reason)) {
      return false;
    }

    timer_id_ = g_timeout_add(kRecordingFrameIntervalMs,
                              &CockpitLinuxRecorder::OnFrameTimer, this);
    return true;
  }

  RecordingStopResult Stop() {
    RecordingStopResult result;

    if (timer_id_ != 0) {
      g_source_remove(timer_id_);
      timer_id_ = 0;
    }

    if (!encountered_error_) {
      auto view = GetView();
      auto pixbuf_capture = CaptureViewPixbuf(view.get());
      if (pixbuf_capture.success) {
        auto frame = ConvertPixbufToRgba(pixbuf_capture.pixbuf.get());
        if (frame.success) {
          std::string failure_reason;
          if (!PushFrame(frame, &failure_reason)) {
            encountered_error_ = true;
            failure_reason_ = failure_reason;
          }
        }
      }
    }

    if (pipeline_ == nullptr || appsrc_ == nullptr) {
      result.failure_reason =
          failure_reason_.empty() ? "recordingPipelineUnavailable"
                                  : failure_reason_;
      return result;
    }

    GstFlowReturn eos_result = gst_app_src_end_of_stream(GST_APP_SRC(appsrc_));
    if (eos_result != GST_FLOW_OK) {
      result.failure_reason = "recordingEndOfStreamFailed";
      return result;
    }

    std::string finalize_failure;
    if (!WaitForFinalize(&finalize_failure)) {
      result.failure_reason = finalize_failure;
      return result;
    }

    if (encountered_error_) {
      result.failure_reason = failure_reason_;
      return result;
    }
    if (captured_frame_count_ == 0) {
      result.failure_reason = "recordingCapturedNoFrames";
      return result;
    }
    if (!WaitForNonEmptyFile(output_path_, std::chrono::seconds(2))) {
      result.failure_reason = "recordingOutputMissing";
      return result;
    }

    result.success = true;
    result.captured_frame_count = captured_frame_count_;
    return result;
  }

  const std::filesystem::path& output_path() const { return output_path_; }

 private:
  static gboolean OnFrameTimer(gpointer user_data) {
    auto* recorder = static_cast<CockpitLinuxRecorder*>(user_data);
    return recorder->CaptureAndPushNextFrame() ? G_SOURCE_CONTINUE
                                               : G_SOURCE_REMOVE;
  }

  GObjectHandle<FlView> GetView() {
    return AdoptGObject<FlView>(FL_VIEW(g_weak_ref_get(&view_ref_)));
  }

  bool CaptureAndPushNextFrame() {
    auto view = GetView();
    auto pixbuf_capture = CaptureViewPixbuf(view.get());
    if (!pixbuf_capture.success) {
      encountered_error_ = true;
      failure_reason_ = pixbuf_capture.failure_reason;
      timer_id_ = 0;
      return false;
    }

    auto frame = ConvertPixbufToRgba(pixbuf_capture.pixbuf.get());
    if (!frame.success) {
      encountered_error_ = true;
      failure_reason_ = frame.failure_reason;
      timer_id_ = 0;
      return false;
    }

    if (frame.width != width_ || frame.height != height_) {
      encountered_error_ = true;
      failure_reason_ = "Flutter view size changed during Linux recording.";
      timer_id_ = 0;
      return false;
    }

    if (!PushFrame(frame, &failure_reason_)) {
      encountered_error_ = true;
      timer_id_ = 0;
      return false;
    }

    return true;
  }

  bool CreatePipeline(std::string* failure_reason) {
    GstElement* pipeline = gst_pipeline_new("flutter-cockpit-linux-recorder");
    GstElement* source = gst_element_factory_make("appsrc", "source");
    GstElement* convert = gst_element_factory_make("videoconvert", "convert");
    GstElement* encoder = nullptr;
    GstElement* parser = nullptr;
    GstElement* muxer = gst_element_factory_make("mp4mux", "muxer");
    GstElement* sink = gst_element_factory_make("filesink", "sink");

    if (muxer == nullptr) {
      muxer = gst_element_factory_make("qtmux", "muxer");
    }

    struct EncoderOption {
      const char* factory;
      bool needs_h264_parser;
    };
    const EncoderOption encoders[] = {
        {"x264enc", true},
        {"openh264enc", true},
        {"avenc_h264", true},
        {"avenc_mpeg4", false},
    };
    for (const auto& option : encoders) {
      encoder = gst_element_factory_make(option.factory, option.factory);
      if (encoder == nullptr) {
        continue;
      }
      if (option.needs_h264_parser) {
        parser = gst_element_factory_make("h264parse", "h264parse");
        if (parser == nullptr) {
          gst_object_unref(encoder);
          encoder = nullptr;
          continue;
        }
      }
      break;
    }

    if (pipeline == nullptr || source == nullptr || convert == nullptr ||
        encoder == nullptr || muxer == nullptr || sink == nullptr) {
      if (failure_reason != nullptr) {
        *failure_reason =
            "Linux native recording requires GTK and GStreamer encoder support.";
      }
      if (pipeline != nullptr) {
        gst_object_unref(pipeline);
      }
      if (source != nullptr) {
        gst_object_unref(source);
      }
      if (convert != nullptr) {
        gst_object_unref(convert);
      }
      if (encoder != nullptr) {
        gst_object_unref(encoder);
      }
      if (parser != nullptr) {
        gst_object_unref(parser);
      }
      if (muxer != nullptr) {
        gst_object_unref(muxer);
      }
      if (sink != nullptr) {
        gst_object_unref(sink);
      }
      return false;
    }

    GstCaps* caps = gst_caps_new_simple(
        "video/x-raw", "format", G_TYPE_STRING, "RGBA", "width", G_TYPE_INT,
        width_, "height", G_TYPE_INT, height_, "framerate",
        GST_TYPE_FRACTION, kRecordingFrameRate, 1, nullptr);
    g_object_set(source, "caps", caps, "format", GST_FORMAT_TIME, "is-live",
                 TRUE, "block", TRUE, nullptr);
    gst_caps_unref(caps);

    if (HasGObjectProperty(muxer, "faststart")) {
      g_object_set(muxer, "faststart", TRUE, nullptr);
    }
    g_object_set(sink, "location", output_path_.c_str(), "sync", FALSE,
                 nullptr);

    gst_bin_add_many(GST_BIN(pipeline), source, convert, encoder, nullptr);
    if (parser != nullptr) {
      gst_bin_add(GST_BIN(pipeline), parser);
    }
    gst_bin_add_many(GST_BIN(pipeline), muxer, sink, nullptr);

    gboolean linked = FALSE;
    if (parser != nullptr) {
      linked = gst_element_link_many(source, convert, encoder, parser, muxer,
                                     sink, nullptr);
    } else {
      linked = gst_element_link_many(source, convert, encoder, muxer, sink,
                                     nullptr);
    }
    if (!linked) {
      if (failure_reason != nullptr) {
        *failure_reason = "Linux recording pipeline could not be linked.";
      }
      gst_element_set_state(pipeline, GST_STATE_NULL);
      gst_object_unref(pipeline);
      return false;
    }

    const auto state_change = gst_element_set_state(pipeline, GST_STATE_PLAYING);
    if (state_change == GST_STATE_CHANGE_FAILURE) {
      if (failure_reason != nullptr) {
        *failure_reason =
            "Linux recording pipeline failed to enter PLAYING state.";
      }
      gst_element_set_state(pipeline, GST_STATE_NULL);
      gst_object_unref(pipeline);
      return false;
    }

    pipeline_ = pipeline;
    appsrc_ = source;
    return true;
  }

  bool PushFrame(const FrameCapture& frame, std::string* failure_reason) {
    if (appsrc_ == nullptr) {
      if (failure_reason != nullptr) {
        *failure_reason = "Linux recording appsrc is unavailable.";
      }
      return false;
    }

    GstBuffer* buffer =
        gst_buffer_new_allocate(nullptr, frame.rgba.size(), nullptr);
    if (buffer == nullptr) {
      if (failure_reason != nullptr) {
        *failure_reason = "GStreamer failed to allocate a video buffer.";
      }
      return false;
    }

    GstMapInfo map;
    if (!gst_buffer_map(buffer, &map, GST_MAP_WRITE)) {
      gst_buffer_unref(buffer);
      if (failure_reason != nullptr) {
        *failure_reason = "GStreamer could not map a Linux video buffer.";
      }
      return false;
    }

    memcpy(map.data, frame.rgba.data(), frame.rgba.size());
    gst_buffer_unmap(buffer, &map);

    const GstClockTime pts = captured_frame_count_ * (GST_SECOND / kRecordingFrameRate);
    GST_BUFFER_PTS(buffer) = pts;
    GST_BUFFER_DTS(buffer) = pts;
    GST_BUFFER_DURATION(buffer) = GST_SECOND / kRecordingFrameRate;

    const GstFlowReturn flow = gst_app_src_push_buffer(GST_APP_SRC(appsrc_), buffer);
    if (flow != GST_FLOW_OK) {
      if (failure_reason != nullptr) {
        *failure_reason = "GStreamer rejected a Linux recording frame.";
      }
      return false;
    }

    captured_frame_count_ += 1;
    return true;
  }

  bool WaitForFinalize(std::string* failure_reason) {
    GstBus* bus = gst_element_get_bus(pipeline_);
    if (bus == nullptr) {
      if (failure_reason != nullptr) {
        *failure_reason = "Linux recording bus was unavailable.";
      }
      return false;
    }

    const auto timeout_ns =
        static_cast<GstClockTime>(kRecordingStopTimeout.count()) * GST_SECOND;
    GstMessage* message = gst_bus_timed_pop_filtered(
        bus, timeout_ns,
        static_cast<GstMessageType>(GST_MESSAGE_EOS | GST_MESSAGE_ERROR));
    gst_object_unref(bus);

    if (message == nullptr) {
      if (failure_reason != nullptr) {
        *failure_reason = "recordingFinalizeTimeout";
      }
      return false;
    }

    bool success = true;
    if (GST_MESSAGE_TYPE(message) == GST_MESSAGE_ERROR) {
      GError* error = nullptr;
      gchar* debug = nullptr;
      gst_message_parse_error(message, &error, &debug);
      if (failure_reason != nullptr) {
        *failure_reason = error == nullptr ? "Linux recording pipeline error."
                                           : error->message;
      }
      if (error != nullptr) {
        g_error_free(error);
      }
      if (debug != nullptr) {
        g_free(debug);
      }
      success = false;
    }

    gst_message_unref(message);
    gst_element_set_state(pipeline_, GST_STATE_NULL);
    gst_object_unref(pipeline_);
    pipeline_ = nullptr;
    appsrc_ = nullptr;
    return success;
  }

  GWeakRef view_ref_;
  std::filesystem::path output_path_;
  GstElement* pipeline_ = nullptr;
  GstElement* appsrc_ = nullptr;
  guint timer_id_ = 0;
  int width_ = 0;
  int height_ = 0;
  int captured_frame_count_ = 0;
  bool encountered_error_ = false;
  std::string failure_reason_;
};

FlMethodResponse* SuccessResponse(FlValue* value) {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(value));
}

FlMethodResponse* ErrorResponse(const char* code, const std::string& message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message.c_str(), nullptr));
}

void Respond(FlMethodCall* method_call, FlMethodResponse* response) {
  fl_method_call_respond(method_call, response, nullptr);
}

void HandleCaptureMethodCall(FlutterCockpitPlugin* self,
                             FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  if (strcmp(method, "queryNativeCaptureAvailability") == 0) {
    auto view = GetActiveView(self);
    g_autoptr(FlValue) value =
        fl_value_new_bool(view != nullptr &&
                          gtk_widget_get_window(GTK_WIDGET(view.get())) != nullptr);
    Respond(method_call, SuccessResponse(value));
    return;
  }

  if (strcmp(method, "captureAcceptanceScreenshot") == 0) {
    auto view = GetActiveView(self);
    auto pixbuf_capture = CaptureViewPixbuf(view.get());
    if (!pixbuf_capture.success) {
      Respond(method_call,
              ErrorResponse("captureFailed", pixbuf_capture.failure_reason));
      return;
    }

    std::vector<uint8_t> png_bytes;
    std::string failure_reason;
    if (!EncodePixbufPng(pixbuf_capture.pixbuf.get(), &png_bytes,
                         &failure_reason)) {
      Respond(method_call, ErrorResponse("encodeFailed", failure_reason));
      return;
    }

    g_autoptr(FlValue) payload = fl_value_new_map();
    fl_value_set_string_take(
        payload, "bytes",
        fl_value_new_uint8_list(png_bytes.data(), png_bytes.size()));
    Respond(method_call, SuccessResponse(payload));
    return;
  }

  Respond(method_call,
          FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()));
}

void HandleRecordingMethodCall(FlutterCockpitPlugin* self,
                               FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  if (strcmp(method, "queryRecordingCapabilities") == 0) {
    auto view = GetActiveView(self);
    const bool supports_native =
        view != nullptr &&
        gtk_widget_get_window(GTK_WIDGET(view.get())) != nullptr &&
        HasRecordingPipelineSupport();
    g_autoptr(FlValue) payload = fl_value_new_map();
    fl_value_set_string_take(payload, "supportsNativeRecording",
                             fl_value_new_bool(supports_native));
    fl_value_set_string_take(payload, "preferredAcceptanceRecordingKind",
                             fl_value_new_string("nativeScreen"));
    g_autoptr(FlValue) supported_layers = fl_value_new_list();
    fl_value_append_take(supported_layers,
                         fl_value_new_string("app-window"));
    fl_value_set_string(payload, "supportedLayers", supported_layers);
    fl_value_set_string_take(payload, "preferredLayer",
                             fl_value_new_string("app-window"));
    g_autoptr(FlValue) limitations = fl_value_new_list();
    fl_value_append_take(
        limitations,
        fl_value_new_string(
            "Native Linux recording captures the Flutter app window content only."));
    fl_value_append_take(
        limitations,
        fl_value_new_string(
            "Window chrome and other desktop surfaces are not included."));
    fl_value_set_string(payload, "recordingLimitations", limitations);
    Respond(method_call, SuccessResponse(payload));
    return;
  }

  if (strcmp(method, "startRecording") == 0) {
    if (self->recording_state ==
            FlutterCockpitPlugin::RecordingState::Starting ||
        self->recording_state ==
            FlutterCockpitPlugin::RecordingState::Recording) {
      Respond(method_call, ErrorResponse("recordingAlreadyActive",
                                         "A recording session is already active."));
      return;
    }
    if (self->recording_state ==
        FlutterCockpitPlugin::RecordingState::Stopping) {
      Respond(method_call, ErrorResponse(
          "recordingAlreadyStopping",
          "The previous recording session is still finalizing."));
      return;
    }

    self->recording_state = FlutterCockpitPlugin::RecordingState::Starting;
    self->session_token += 1;

    auto view = GetActiveView(self);
    if (!view) {
      self->recording_state = FlutterCockpitPlugin::RecordingState::Idle;
      Respond(method_call, ErrorResponse("recordingNoWindow",
                                         "Native recording requires an active FlView."));
      return;
    }

    const auto relative_path = GetStringArgument(method_call, "relativePath")
                                   .value_or("recordings/flutter_cockpit.mp4");
    std::string path_failure;
    const auto output_path =
        BuildTemporaryArtifactPath(relative_path, &path_failure);
    if (!output_path.has_value()) {
      self->recording_state = FlutterCockpitPlugin::RecordingState::Idle;
      Respond(method_call,
              ErrorResponse("recordingInvalidPath", path_failure));
      return;
    }
    auto recorder = std::make_unique<CockpitLinuxRecorder>(view.get(), *output_path);
    std::string failure_reason;
    if (!recorder->Start(&failure_reason)) {
      self->recording_state = FlutterCockpitPlugin::RecordingState::Idle;
      Respond(method_call,
              ErrorResponse("recordingStartFailed", failure_reason));
      return;
    }

    self->active_recorder = recorder.release();
    self->recording_started_at_us = g_get_monotonic_time();
    self->recording_state = FlutterCockpitPlugin::RecordingState::Recording;

    g_autoptr(FlValue) payload = fl_value_new_map();
    fl_value_set_string_take(payload, "state",
                             fl_value_new_string("recording"));
    Respond(method_call, SuccessResponse(payload));
    return;
  }

  if (strcmp(method, "stopRecording") == 0) {
    if (self->recording_state ==
        FlutterCockpitPlugin::RecordingState::Stopping) {
      Respond(method_call, ErrorResponse(
          "recordingAlreadyStopping",
          "The previous recording session is still finalizing."));
      return;
    }
    if (self->recording_state !=
            FlutterCockpitPlugin::RecordingState::Recording ||
        self->active_recorder == nullptr) {
      g_autoptr(FlValue) payload = fl_value_new_map();
      fl_value_set_string_take(payload, "state",
                               fl_value_new_string("failed"));
      fl_value_set_string_take(payload, "failureReason",
                               fl_value_new_string("recordingNotActive"));
      Respond(method_call, SuccessResponse(payload));
      return;
    }

    auto* recorder = self->active_recorder;
    self->active_recorder = nullptr;
    self->recording_state = FlutterCockpitPlugin::RecordingState::Stopping;
    const guint64 token = self->session_token;

    const gint64 duration_ms =
        (g_get_monotonic_time() - self->recording_started_at_us) / 1000;
    struct LinuxStopOperation {
      FlutterCockpitPlugin* plugin;
      FlMethodCall* method_call;
      CockpitLinuxRecorder* recorder;
      guint64 token;
      gint64 duration_ms;
      RecordingStopResult stop_result;
    };
    auto* operation = new LinuxStopOperation{
        FLUTTER_COCKPIT_PLUGIN(g_object_ref(self)),
        static_cast<FlMethodCall*>(g_object_ref(method_call)),
        recorder,
        token,
        duration_ms,
        {},
    };
    std::thread([operation]() {
      operation->stop_result = operation->recorder->Stop();
      g_main_context_invoke(
          nullptr,
          [](gpointer user_data) -> gboolean {
            auto* operation = static_cast<LinuxStopOperation*>(user_data);
            auto* plugin = operation->plugin;
            if (plugin->recording_state ==
                    FlutterCockpitPlugin::RecordingState::Stopping &&
                plugin->session_token == operation->token) {
              g_autoptr(FlValue) payload = fl_value_new_map();
              if (!operation->stop_result.success) {
                fl_value_set_string_take(payload, "state",
                                         fl_value_new_string("failed"));
                fl_value_set_string_take(
                    payload, "failureReason",
                    fl_value_new_string(
                        operation->stop_result.failure_reason.c_str()));
              } else {
                fl_value_set_string_take(payload, "state",
                                         fl_value_new_string("completed"));
                fl_value_set_string_take(payload, "recordingKind",
                                         fl_value_new_string("nativeScreen"));
                fl_value_set_string_take(payload, "effectiveLayer",
                                         fl_value_new_string("app-window"));
                fl_value_set_string_take(payload, "durationMs",
                                         fl_value_new_int(operation->duration_ms));
                fl_value_set_string_take(
                    payload, "sourceFilePath",
                    fl_value_new_string(
                        operation->recorder->output_path().c_str()));
              }
              Respond(operation->method_call, SuccessResponse(payload));
              plugin->recording_state =
                  FlutterCockpitPlugin::RecordingState::Idle;
              plugin->recording_started_at_us = 0;
            }
            delete operation->recorder;
            g_object_unref(operation->method_call);
            g_object_unref(operation->plugin);
            delete operation;
            return G_SOURCE_REMOVE;
          },
          operation);
    }).detach();
    return;
  }

  Respond(method_call,
          FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()));
}

void HandleViewportMethodCall(FlutterCockpitPlugin* self,
                              FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  auto view = GetActiveView(self);
  GtkWidget* top_level = view == nullptr
      ? nullptr
      : gtk_widget_get_toplevel(GTK_WIDGET(view.get()));
  const bool available = top_level != nullptr && GTK_IS_WINDOW(top_level);

  if (strcmp(method, "queryViewportAvailability") == 0) {
    g_autoptr(FlValue) payload = fl_value_new_map();
    fl_value_set_string_take(payload, "available", fl_value_new_bool(available));
    g_autoptr(FlValue) alternatives = fl_value_new_list();
    fl_value_set_string(payload, "alternatives", alternatives);
    Respond(method_call, SuccessResponse(payload));
    return;
  }
  if (strcmp(method, "resizeViewport") == 0) {
    if (!available) {
      Respond(method_call,
              ErrorResponse("noWindow",
                            "Viewport resize requires an active GtkWindow."));
      return;
    }
    const auto width = GetIntArgument(method_call, "width");
    const auto height = GetIntArgument(method_call, "height");
    if (!width.has_value() || !height.has_value()) {
      Respond(method_call,
              ErrorResponse("invalidViewport",
                            "Viewport width and height must be integers."));
      return;
    }
    gtk_window_resize(GTK_WINDOW(top_level), *width, *height);
    g_autoptr(FlValue) payload = fl_value_new_map();
    fl_value_set_string_take(payload, "accepted", fl_value_new_bool(true));
    Respond(method_call, SuccessResponse(payload));
    return;
  }
  Respond(method_call,
          FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()));
}

static void CaptureMethodCallHandler(FlMethodChannel* channel,
                                     FlMethodCall* method_call,
                                     gpointer user_data) {
  auto* plugin = FLUTTER_COCKPIT_PLUGIN(user_data);
  HandleCaptureMethodCall(plugin, method_call);
}

static void RecordingMethodCallHandler(FlMethodChannel* channel,
                                       FlMethodCall* method_call,
                                       gpointer user_data) {
  auto* plugin = FLUTTER_COCKPIT_PLUGIN(user_data);
  HandleRecordingMethodCall(plugin, method_call);
}

static void ViewportMethodCallHandler(FlMethodChannel* channel,
                                      FlMethodCall* method_call,
                                      gpointer user_data) {
  auto* plugin = FLUTTER_COCKPIT_PLUGIN(user_data);
  HandleViewportMethodCall(plugin, method_call);
}

}  // namespace

static void flutter_cockpit_plugin_dispose(GObject* object) {
  auto* self = FLUTTER_COCKPIT_PLUGIN(object);
  delete self->active_recorder;
  self->active_recorder = nullptr;
  g_weak_ref_clear(&self->view_ref);
  G_OBJECT_CLASS(flutter_cockpit_plugin_parent_class)->dispose(object);
}

static void flutter_cockpit_plugin_class_init(FlutterCockpitPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = flutter_cockpit_plugin_dispose;
}

static void flutter_cockpit_plugin_init(FlutterCockpitPlugin* self) {
  g_weak_ref_init(&self->view_ref, nullptr);
  self->active_recorder = nullptr;
  self->recording_started_at_us = 0;
  self->recording_state = FlutterCockpitPlugin::RecordingState::Idle;
  self->session_token = 0;
}

void flutter_cockpit_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  auto* plugin = FLUTTER_COCKPIT_PLUGIN(
      g_object_new(flutter_cockpit_plugin_get_type(), nullptr));

  if (auto* view = fl_plugin_registrar_get_view(registrar); view != nullptr) {
    g_weak_ref_set(&plugin->view_ref, G_OBJECT(view));
  }

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) capture_channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), kCaptureChannelName,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      capture_channel, CaptureMethodCallHandler, g_object_ref(plugin),
      g_object_unref);

  g_autoptr(FlMethodChannel) recording_channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), kRecordingChannelName,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      recording_channel, RecordingMethodCallHandler, g_object_ref(plugin),
      g_object_unref);

  g_autoptr(FlMethodChannel) viewport_channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), kViewportChannelName,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      viewport_channel, ViewportMethodCallHandler, g_object_ref(plugin),
      g_object_unref);

  g_object_unref(plugin);
}
