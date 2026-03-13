#ifndef RUNNER_RECORDING_BRIDGE_H_
#define RUNNER_RECORDING_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>

#include <memory>
#include <map>
#include <mutex>
#include <vector>

#include "audio_recorder.h"

// Define the window messages for thread-safe UI updates
#define WM_FLUTTER_AUDIO_DATA (WM_APP + 236)
#define WM_FLUTTER_STATE_EVENT (WM_APP + 237)
#define WM_FLUTTER_ERROR_EVENT (WM_APP + 238)
#define WM_FLUTTER_DEVICES_EVENT (WM_APP + 239)

class RecordingBridge {
public:
    RecordingBridge(HWND window_handle, const flutter::DartProject& project);
    ~RecordingBridge();

    void RegisterChannels(flutter::BinaryMessenger* messenger);
    
    // Message handler to be called from FlutterWindow::MessageHandler
    std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

private:
    void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& method_call,
                         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    
    void StartBackgroundEngine(int64_t callback_handle);

    // Callbacks from AudioRecorder
    void OnAudioData(const std::vector<float>& data);
    void OnStateChanged(const std::string& state);
    void OnError(const std::string& error);

    // Thread-safe event emission (via PostMessage to UI thread)
    void PostAudioData(const std::vector<float>& data);
    void PostState(const std::string& state);
    void PostError(const std::string& error);
    void PostDevices(const std::vector<AudioDevice>& devices);

    HWND window_handle_;
    flutter::DartProject project_;
    std::unique_ptr<AudioRecorder> recorder_;
    std::unique_ptr<flutter::FlutterEngine> background_engine_;

    // Event sinks for broadcasting
    std::map<flutter::BinaryMessenger*, std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>> event_sinks_;
    std::mutex event_sinks_mutex_;

    // Queued events for the UI thread
    std::mutex queue_mutex_;
    std::vector<std::shared_ptr<std::vector<float>>> posted_audio_events_;
    std::vector<std::shared_ptr<std::string>> posted_state_events_;
    std::vector<std::shared_ptr<std::string>> posted_error_events_;
    std::vector<std::shared_ptr<std::vector<AudioDevice>>> posted_devices_events_;
};

#endif // RUNNER_RECORDING_BRIDGE_H_
