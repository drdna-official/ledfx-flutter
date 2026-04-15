#ifndef RUNNER_RECORDING_BRIDGE_H_
#define RUNNER_RECORDING_BRIDGE_H_

#include <flutter_linux/flutter_linux.h>
#include <memory>
#include <map>
#include <mutex>
#include <vector>

#include "audio_recorder.h"

class RecordingBridge {
public:
    RecordingBridge(FlView* view, FlDartProject* project);
    ~RecordingBridge();

    void RegisterChannels(FlBinaryMessenger* messenger);

private:
    static void handle_method_call(FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data);
    static FlMethodResponse* handle_request_device_list(RecordingBridge* self);
    static FlMethodResponse* handle_start_recording(RecordingBridge* self, FlValue* args);
    static FlMethodResponse* handle_stop_recording(RecordingBridge* self);
    static FlMethodResponse* handle_setup_background_execution(RecordingBridge* self, FlValue* args);
    static FlMethodResponse* handle_get_recording_state(RecordingBridge* self);

    static FlMethodErrorResponse* handle_event_listen(FlEventChannel* channel, FlValue* args, gpointer user_data);
    static FlMethodErrorResponse* handle_event_cancel(FlEventChannel* channel, FlValue* args, gpointer user_data);

    void StartBackgroundEngine(int64_t callback_handle);

    // Callbacks from AudioRecorder
    void OnAudioData(const std::vector<float>& data);
    void OnStateChanged(const std::string& state);
    void OnError(const std::string& error);

    // Thread-safe event emission (via g_idle_add to UI thread)
    void PostAudioData(const std::vector<float>& data);
    void PostState(const std::string& state);
    void PostError(const std::string& error);
    void PostDevices(const std::vector<AudioDevice>& devices);

    // Idle handlers
    static gboolean SendAudioDataIdle(gpointer data);
    static gboolean SendStateIdle(gpointer data);
    static gboolean SendErrorIdle(gpointer data);
    static gboolean SendDevicesIdle(gpointer data);

    FlMethodChannel* method_channel_ = nullptr;
    FlEventChannel* event_channel_ = nullptr;
    std::unique_ptr<AudioRecorder> recorder_;
    FlView* background_view_ = nullptr;
    FlEngine* background_engine_ = nullptr;

    // Event sinks for broadcasting
    std::map<FlBinaryMessenger*, FlEventChannel*> active_sinks_;
    std::mutex event_sinks_mutex_;
};

#endif // RUNNER_RECORDING_BRIDGE_H_
