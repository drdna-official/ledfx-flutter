#include "recording_bridge.h"
#include <flutter/standard_method_codec.h>
#include <flutter/event_stream_handler_functions.h>
#include <iostream>
#include "flutter/generated_plugin_registrant.h"

RecordingBridge::RecordingBridge(HWND window_handle, const flutter::DartProject& project)
    : window_handle_(window_handle), project_(project) {
    recorder_ = std::make_unique<AudioRecorder>();
    
    recorder_->SetDataCallback([this](const auto& data) { OnAudioData(data); });
    recorder_->SetStateCallback([this](const auto& state) { OnStateChanged(state); });
    recorder_->SetErrorCallback([this](const auto& error) { OnError(error); });
}

RecordingBridge::~RecordingBridge() {
    recorder_.reset();
}

void RecordingBridge::RegisterChannels(flutter::BinaryMessenger* messenger) {
    auto method_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, "system_audio_recorder/methods", &flutter::StandardMethodCodec::GetInstance());

    method_channel->SetMethodCallHandler([this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
    });

    auto event_channel = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        messenger, "system_audio_recorder/events", &flutter::StandardMethodCodec::GetInstance());

    event_channel->SetStreamHandler(std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
        [this, messenger](auto arguments, auto events) -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            std::lock_guard<std::mutex> lock(event_sinks_mutex_);
            event_sinks_[messenger] = std::move(events);
            return nullptr;
        },
        [this, messenger](auto arguments) -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            std::lock_guard<std::mutex> lock(event_sinks_mutex_);
            event_sinks_.erase(messenger);
            return nullptr;
        }));

    method_channel.release();
    event_channel.release();
}

void RecordingBridge::HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& method_call,
                                      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const std::string& method_name = method_call.method_name();

    enum class Method {
        RequestDeviceList,
        StartRecording,
        StopRecording,
        SetupBackgroundExecution,
        Unknown
    };

    static const std::map<std::string, Method> method_map = {
        {"requestDeviceList", Method::RequestDeviceList},
        {"startRecording", Method::StartRecording},
        {"stopRecording", Method::StopRecording},
        {"setupBackgroundExecution", Method::SetupBackgroundExecution}
    };

    Method method = Method::Unknown;
    auto method_it = method_map.find(method_name);
    if (method_it != method_map.end()) {
        method = method_it->second;
    }

    switch (method) {
        case Method::RequestDeviceList: {
            auto devices = recorder_->EnumerateAudioDevices();
            PostDevices(devices);
            result->Success(flutter::EncodableValue(true));
            break;
        }
        case Method::StartRecording: {
            const auto* args = std::get_if<std::map<flutter::EncodableValue, flutter::EncodableValue>>(method_call.arguments());
            if (!args) {
                result->Error("INVALID_ARGUMENTS", "Expected argument map");
                return;
            }

            auto getString = [&](const char* key) -> std::string {
                auto it_val = args->find(flutter::EncodableValue(key));
                if (it_val != args->end()) {
                    if (auto val = std::get_if<std::string>(&it_val->second)) return *val;
                }
                return "";
            };

            auto getInt = [&](const char* key, int def) -> int {
                auto it_val = args->find(flutter::EncodableValue(key));
                if (it_val != args->end()) {
                    if (auto val = std::get_if<int>(&it_val->second)) return *val;
                }
                return def;
            };

            std::string deviceId = getString("deviceId");
            std::string captureType = getString("captureType");
            int sampleRate = getInt("sampleRate", 44100);
            int channels = getInt("channels", 1);
            int blockSize = getInt("blockSize", 0);

            recorder_->Start(deviceId, captureType, sampleRate, channels, blockSize);
            result->Success(flutter::EncodableValue(true));
            break;
        }
        case Method::StopRecording: {
            recorder_->Stop();
            result->Success(flutter::EncodableValue(true));
            break;
        }
        case Method::SetupBackgroundExecution: {
            int64_t handle = 0;
            const auto* args = std::get_if<std::map<flutter::EncodableValue, flutter::EncodableValue>>(method_call.arguments());
            if (args) {
                auto it_handle = args->find(flutter::EncodableValue("handle"));
                if (it_handle != args->end()) {
                    if (auto p_int = std::get_if<int64_t>(&it_handle->second)) handle = *p_int;
                    else if (auto p_int32 = std::get_if<int32_t>(&it_handle->second)) handle = *p_int32;
                }
            }
            StartBackgroundEngine(handle);
            result->Success(flutter::EncodableValue(true));
            break;
        }
        default:
            result->NotImplemented();
            break;
    }
}

void RecordingBridge::StartBackgroundEngine(int64_t callback_handle) {
    if (background_engine_) return;

    // Save handle to Registry for persistence (future-proofing)
    if (callback_handle != 0) {
        HKEY hKey;
        if (RegCreateKeyExA(HKEY_CURRENT_USER, "Software\\DrDNA\\LEDFx\\Background", 0, NULL, 
                            REG_OPTION_NON_VOLATILE, KEY_WRITE, NULL, &hKey, NULL) == ERROR_SUCCESS) {
            RegSetValueExA(hKey, "callbackHandle", 0, REG_QWORD, 
                           reinterpret_cast<const BYTE*>(&callback_handle), sizeof(callback_handle));
            RegCloseKey(hKey);
        }
    }

    flutter::DartProject background_project(L"data");
    background_project.set_dart_entrypoint("backgroundAudioProcessing");

    background_engine_ = std::make_unique<flutter::FlutterEngine>(background_project);
    RegisterChannels(background_engine_->messenger());
    RegisterPlugins(background_engine_.get());
    background_engine_->Run();
}

void RecordingBridge::OnAudioData(const std::vector<float>& data) {
    PostAudioData(data);
}

void RecordingBridge::OnStateChanged(const std::string& state) {
    PostState(state);
}

void RecordingBridge::OnError(const std::string& error) {
    PostError(error);
}

void RecordingBridge::PostAudioData(const std::vector<float>& data) {
    auto copy = std::make_shared<std::vector<float>>(data);
    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        posted_audio_events_.push_back(copy);
    }
    PostMessage(window_handle_, WM_FLUTTER_AUDIO_DATA, reinterpret_cast<WPARAM>(copy.get()), 0);
}

void RecordingBridge::PostState(const std::string& state) {
    auto copy = std::make_shared<std::string>(state);
    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        posted_state_events_.push_back(copy);
    }
    PostMessage(window_handle_, WM_FLUTTER_STATE_EVENT, reinterpret_cast<WPARAM>(copy.get()), 0);
}

void RecordingBridge::PostError(const std::string& error) {
    auto copy = std::make_shared<std::string>(error);
    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        posted_error_events_.push_back(copy);
    }
    PostMessage(window_handle_, WM_FLUTTER_ERROR_EVENT, reinterpret_cast<WPARAM>(copy.get()), 0);
}

void RecordingBridge::PostDevices(const std::vector<AudioDevice>& devices) {
    auto copy = std::make_shared<std::vector<AudioDevice>>(devices);
    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        posted_devices_events_.push_back(copy);
    }
    PostMessage(window_handle_, WM_FLUTTER_DEVICES_EVENT, reinterpret_cast<WPARAM>(copy.get()), 0);
}

std::optional<LRESULT> RecordingBridge::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
    switch (message) {
        case WM_FLUTTER_AUDIO_DATA: {
            auto data_ptr = reinterpret_cast<std::vector<float>*>(wparam);
            if (data_ptr) {
                flutter::EncodableList audio_data;
                audio_data.reserve(data_ptr->size());
                for (float sample : *data_ptr) audio_data.push_back(flutter::EncodableValue(static_cast<double>(sample)));

                std::map<flutter::EncodableValue, flutter::EncodableValue> event_map;
                event_map[flutter::EncodableValue("type")] = flutter::EncodableValue("audio");
                event_map[flutter::EncodableValue("data")] = flutter::EncodableValue(audio_data);
                flutter::EncodableValue event(event_map);

                std::lock_guard<std::mutex> lock(event_sinks_mutex_);
                for (auto& pair : event_sinks_) {
                    // Only send audio data to the background isolate
                    if (background_engine_ && pair.first == background_engine_->messenger()) {
                        pair.second->Success(event);
                    }
                }
            }
            {
                std::lock_guard<std::mutex> lock(queue_mutex_);
                posted_audio_events_.erase(std::remove_if(posted_audio_events_.begin(), posted_audio_events_.end(),
                    [data_ptr](const auto& p) { return p.get() == data_ptr; }), posted_audio_events_.end());
            }
            return 0;
        }
        case WM_FLUTTER_STATE_EVENT: {
            auto state_ptr = reinterpret_cast<std::string*>(wparam);
            if (state_ptr) {
                std::map<flutter::EncodableValue, flutter::EncodableValue> map{
                    {flutter::EncodableValue("type"), flutter::EncodableValue("state")},
                    {flutter::EncodableValue("value"), flutter::EncodableValue(*state_ptr)}};
                flutter::EncodableValue event(map);
                std::lock_guard<std::mutex> lock(event_sinks_mutex_);
                for (auto& pair : event_sinks_) pair.second->Success(event);
            }
            {
                std::lock_guard<std::mutex> lock(queue_mutex_);
                posted_state_events_.erase(std::remove_if(posted_state_events_.begin(), posted_state_events_.end(),
                    [state_ptr](const auto& p) { return p.get() == state_ptr; }), posted_state_events_.end());
            }
            return 0;
        }
        case WM_FLUTTER_ERROR_EVENT: {
            auto error_ptr = reinterpret_cast<std::string*>(wparam);
            if (error_ptr) {
                std::map<flutter::EncodableValue, flutter::EncodableValue> map{
                    {flutter::EncodableValue("type"), flutter::EncodableValue("error")},
                    {flutter::EncodableValue("message"), flutter::EncodableValue(*error_ptr)}};
                flutter::EncodableValue event(map);
                std::lock_guard<std::mutex> lock(event_sinks_mutex_);
                for (auto& pair : event_sinks_) pair.second->Success(event);
            }
            {
                std::lock_guard<std::mutex> lock(queue_mutex_);
                posted_error_events_.erase(std::remove_if(posted_error_events_.begin(), posted_error_events_.end(),
                    [error_ptr](const auto& p) { return p.get() == error_ptr; }), posted_error_events_.end());
            }
            return 0;
        }
        case WM_FLUTTER_DEVICES_EVENT: {
            auto devices_ptr = reinterpret_cast<std::vector<AudioDevice>*>(wparam);
            if (devices_ptr) {
                flutter::EncodableList list;
                for (const auto& dev : *devices_ptr) {
                    std::map<flutter::EncodableValue, flutter::EncodableValue> m;
                    m[flutter::EncodableValue("id")] = flutter::EncodableValue(dev.id);
                    m[flutter::EncodableValue("name")] = flutter::EncodableValue(dev.name);
                    m[flutter::EncodableValue("description")] = flutter::EncodableValue(dev.description);
                    m[flutter::EncodableValue("isActive")] = flutter::EncodableValue(true);
                    m[flutter::EncodableValue("sampleRate")] = flutter::EncodableValue(dev.sampleRate);
                    m[flutter::EncodableValue("isDefault")] = flutter::EncodableValue(dev.isDefault);
                    m[flutter::EncodableValue("type")] = flutter::EncodableValue(dev.type);
                    list.push_back(flutter::EncodableValue(m));
                }
                std::map<flutter::EncodableValue, flutter::EncodableValue> map{
                    {flutter::EncodableValue("type"), flutter::EncodableValue("devicesInfo")},
                    {flutter::EncodableValue("devices"), flutter::EncodableValue(list)}};
                flutter::EncodableValue event(map);
                std::lock_guard<std::mutex> lock(event_sinks_mutex_);
                for (auto& pair : event_sinks_) pair.second->Success(event);
            }
            {
                std::lock_guard<std::mutex> lock(queue_mutex_);
                posted_devices_events_.erase(std::remove_if(posted_devices_events_.begin(), posted_devices_events_.end(),
                    [devices_ptr](const auto& p) { return p.get() == devices_ptr; }), posted_devices_events_.end());
            }
            return 0;
        }
    }
    return std::nullopt;
}
