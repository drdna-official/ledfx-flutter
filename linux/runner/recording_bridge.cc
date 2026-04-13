#include "recording_bridge.h"

#include <flutter_linux/flutter_linux.h>
#include <glib.h>
#include <iostream>
#include <fstream>
#include <filesystem>
#include <unistd.h>
#include <pwd.h>

#include "flutter/generated_plugin_registrant.h"

struct BridgeEventData {
    RecordingBridge* bridge;
    std::string type;
    std::string string_val;
    std::vector<float> audio_val;
    std::vector<AudioDevice> devices_val;
};

RecordingBridge::RecordingBridge(FlView* view, FlDartProject* project) {
    recorder_ = std::make_unique<AudioRecorder>();
    
    recorder_->SetDataCallback([this](const auto& data) { OnAudioData(data); });
    recorder_->SetStateCallback([this](const auto& state) { OnStateChanged(state); });
    recorder_->SetErrorCallback([this](const auto& error) { OnError(error); });
}

RecordingBridge::~RecordingBridge() {
    recorder_.reset();
}

void RecordingBridge::RegisterChannels(FlBinaryMessenger* messenger) {
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    FlMethodChannel* method_channel = fl_method_channel_new(messenger, "system_audio_recorder/methods", FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(method_channel, handle_method_call, this, nullptr);
    if (!method_channel_) method_channel_ = method_channel;

    FlEventChannel* event_channel = fl_event_channel_new(messenger, "system_audio_recorder/events", FL_METHOD_CODEC(codec));
    fl_event_channel_set_stream_handlers(event_channel, handle_event_listen, handle_event_cancel, this, nullptr);
    if (!event_channel_) event_channel_ = event_channel;

    std::lock_guard<std::mutex> lock(event_sinks_mutex_);
    active_sinks_[messenger] = event_channel;
}

void RecordingBridge::handle_method_call(FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data) {
    RecordingBridge* self = static_cast<RecordingBridge*>(user_data);
    const gchar* method = fl_method_call_get_name(method_call);
    FlValue* args = fl_method_call_get_args(method_call);

    std::cout << "[RecordingBridge] Received method call: " << method << std::endl;

    g_autoptr(FlMethodResponse) response = nullptr;

    if (g_strcmp0(method, "requestDeviceList") == 0) {
        response = handle_request_device_list(self);
    } else if (g_strcmp0(method, "startRecording") == 0) {
        response = handle_start_recording(self, args);
    } else if (g_strcmp0(method, "stopRecording") == 0) {
        response = handle_stop_recording(self);
    } else if (g_strcmp0(method, "setupBackgroundExecution") == 0) {
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));

    } else if (g_strcmp0(method, "getRecordingState") == 0) {
        response = handle_get_recording_state(self);
    } else {
        response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    }

    g_autoptr(GError) error = nullptr;
    fl_method_call_respond(method_call, response, &error);
    if (error) {
        g_warning("Failed to respond to method call: %s", error->message);
    }
}

FlMethodResponse* RecordingBridge::handle_request_device_list(RecordingBridge* self) {
    auto devices = self->recorder_->EnumerateAudioDevices();
    self->PostDevices(devices);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
}

FlMethodResponse* RecordingBridge::handle_start_recording(RecordingBridge* self, FlValue* args) {
    if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
        return FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGUMENTS", "Expected argument map", nullptr));
    }

    std::string deviceId = "";
    std::string captureType = "";
    int sampleRate = 44100;
    int channels = 1;
    int blockSize = 0;

    FlValue* v_deviceId = fl_value_lookup_string(args, "deviceId");
    if (v_deviceId && fl_value_get_type(v_deviceId) == FL_VALUE_TYPE_STRING) {
        deviceId = fl_value_get_string(v_deviceId);
    }

    FlValue* v_captureType = fl_value_lookup_string(args, "captureType");
    if (v_captureType && fl_value_get_type(v_captureType) == FL_VALUE_TYPE_STRING) {
        captureType = fl_value_get_string(v_captureType);
    }

    FlValue* v_sampleRate = fl_value_lookup_string(args, "sampleRate");
    if (v_sampleRate && fl_value_get_type(v_sampleRate) == FL_VALUE_TYPE_INT) {
        sampleRate = fl_value_get_int(v_sampleRate);
    }

    FlValue* v_channels = fl_value_lookup_string(args, "channels");
    if (v_channels && fl_value_get_type(v_channels) == FL_VALUE_TYPE_INT) {
        channels = fl_value_get_int(v_channels);
    }

    FlValue* v_blockSize = fl_value_lookup_string(args, "blockSize");
    if (v_blockSize && fl_value_get_type(v_blockSize) == FL_VALUE_TYPE_INT) {
        blockSize = fl_value_get_int(v_blockSize);
    }

    self->recorder_->Start(deviceId, captureType, sampleRate, channels, blockSize);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
}

FlMethodResponse* RecordingBridge::handle_stop_recording(RecordingBridge* self) {
    self->recorder_->Stop();
    return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
}

FlMethodResponse* RecordingBridge::handle_get_recording_state(RecordingBridge* self) {
    bool capturing = self->recorder_->IsCapturing();
    self->PostState(capturing ? "recording_started" : "recording_stopped");
    return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(capturing)));
}

FlMethodErrorResponse* RecordingBridge::handle_event_listen(FlEventChannel* channel, FlValue* args, gpointer user_data) {
    // We already register channels locally, so listening is established.
    return nullptr;
}

FlMethodErrorResponse* RecordingBridge::handle_event_cancel(FlEventChannel* channel, FlValue* args, gpointer user_data) {
    return nullptr;
}

// Callbacks

void RecordingBridge::OnAudioData(const std::vector<float>& data) {
    PostAudioData(data);
}

void RecordingBridge::OnStateChanged(const std::string& state) {
    PostState(state);
}

void RecordingBridge::OnError(const std::string& error) {
    PostError(error);
}

// Post actions

void RecordingBridge::PostAudioData(const std::vector<float>& data) {
    auto eventData = new BridgeEventData{this, "audio", "", data, {}};
    g_idle_add(SendAudioDataIdle, eventData);
}

void RecordingBridge::PostState(const std::string& state) {
    auto eventData = new BridgeEventData{this, "state", state, {}, {}};
    g_idle_add(SendStateIdle, eventData);
}

void RecordingBridge::PostError(const std::string& error) {
    auto eventData = new BridgeEventData{this, "error", error, {}, {}};
    g_idle_add(SendErrorIdle, eventData);
}

void RecordingBridge::PostDevices(const std::vector<AudioDevice>& devices) {
    auto eventData = new BridgeEventData{this, "devicesInfo", "", {}, devices};
    g_idle_add(SendDevicesIdle, eventData);
}

// Main thread handlers

gboolean RecordingBridge::SendAudioDataIdle(gpointer data) {
    auto eventData = static_cast<BridgeEventData*>(data);
    RecordingBridge* self = eventData->bridge;

    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "type", fl_value_new_string("audio"));
    
    g_autoptr(FlValue) list = fl_value_new_list();
    for (float sample : eventData->audio_val) {
        fl_value_append_take(list, fl_value_new_float(sample));
    }
    fl_value_set_string(map, "data", list);

    std::lock_guard<std::mutex> lock(self->event_sinks_mutex_);
    for (auto& pair : self->active_sinks_) {
        fl_event_channel_send(pair.second, map, nullptr, nullptr);
    }


    delete eventData;
    return FALSE; // Remove idle source
}

gboolean RecordingBridge::SendStateIdle(gpointer data) {
    auto eventData = static_cast<BridgeEventData*>(data);
    RecordingBridge* self = eventData->bridge;

    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "type", fl_value_new_string("state"));
    fl_value_set_string_take(map, "value", fl_value_new_string(eventData->string_val.c_str()));

    std::lock_guard<std::mutex> lock(self->event_sinks_mutex_);
    for (auto& pair : self->active_sinks_) {
        fl_event_channel_send(pair.second, map, nullptr, nullptr);
    }

    delete eventData;
    return FALSE;
}

gboolean RecordingBridge::SendErrorIdle(gpointer data) {
    auto eventData = static_cast<BridgeEventData*>(data);
    RecordingBridge* self = eventData->bridge;

    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "type", fl_value_new_string("error"));
    fl_value_set_string_take(map, "message", fl_value_new_string(eventData->string_val.c_str()));

    std::lock_guard<std::mutex> lock(self->event_sinks_mutex_);
    for (auto& pair : self->active_sinks_) {
        fl_event_channel_send(pair.second, map, nullptr, nullptr);
    }

    delete eventData;
    return FALSE;
}

gboolean RecordingBridge::SendDevicesIdle(gpointer data) {
    auto eventData = static_cast<BridgeEventData*>(data);
    RecordingBridge* self = eventData->bridge;

    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "type", fl_value_new_string("devicesInfo"));

    g_autoptr(FlValue) list = fl_value_new_list();
    for (const auto& dev : eventData->devices_val) {
        g_autoptr(FlValue) dev_map = fl_value_new_map();
        fl_value_set_string_take(dev_map, "id", fl_value_new_string(dev.id.c_str()));
        fl_value_set_string_take(dev_map, "name", fl_value_new_string(dev.name.c_str()));
        fl_value_set_string_take(dev_map, "description", fl_value_new_string(dev.description.c_str()));
        fl_value_set_string_take(dev_map, "isActive", fl_value_new_bool(TRUE));
        fl_value_set_string_take(dev_map, "sampleRate", fl_value_new_int(dev.sampleRate));
        fl_value_set_string_take(dev_map, "isDefault", fl_value_new_bool(dev.isDefault));
        fl_value_set_string_take(dev_map, "type", fl_value_new_string(dev.type.c_str()));
        fl_value_append_take(list, fl_value_ref(dev_map));
    }
    
    fl_value_set_string(map, "devices", list);

    std::lock_guard<std::mutex> lock(self->event_sinks_mutex_);
    for (auto& pair : self->active_sinks_) {
        fl_event_channel_send(pair.second, map, nullptr, nullptr);
    }

    delete eventData;
    return FALSE;
}
