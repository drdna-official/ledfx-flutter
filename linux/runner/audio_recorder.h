#ifndef RUNNER_AUDIO_RECORDER_H_
#define RUNNER_AUDIO_RECORDER_H_

#include <string>
#include <vector>
#include <thread>
#include <atomic>
#include <mutex>
#include <functional>
#include <memory>
#include <iostream>
#include <pipewire/pipewire.h>
#include <pulse/simple.h>
#include <pulse/error.h>
#include <pulse/pulseaudio.h>

struct AudioDevice {
    std::string id;
    std::string name;
    std::string description;
    int32_t sampleRate;
    bool isDefault;
    std::string type; // "input" or "output"
};

class AudioRecorder {
public:
    using DataCallback = std::function<void(const std::vector<float>&)>;
    using StateCallback = std::function<void(const std::string&)>;
    using ErrorCallback = std::function<void(const std::string&)>;

    AudioRecorder();
    ~AudioRecorder();

    void SetDataCallback(DataCallback callback) { data_callback_ = callback; }
    void SetStateCallback(StateCallback callback) { state_callback_ = callback; }
    void SetErrorCallback(ErrorCallback callback) { error_callback_ = callback; }

    std::vector<AudioDevice> EnumerateAudioDevices();
    
    void Start(const std::string& deviceId, const std::string& captureType, 
               int sampleRate, int channels, int blockSize);
    void Stop();

    static void on_pw_process(void *userdata);

    bool IsCapturing() const { return is_capturing_; }

private:
    void AudioCaptureThread();

    DataCallback data_callback_;
    StateCallback state_callback_;
    ErrorCallback error_callback_;

    std::atomic<bool> is_capturing_{false};
    std::thread capture_thread_;
    std::string current_device_id_;
    std::string current_capture_type_;
    int sample_rate_ = 48000;
    int channels_ = 1;
    int target_blocksize_ = 0;

    // PipeWire state members
    bool use_pulseaudio_fallback_ = false;
    pa_simple* pa_stream_ = nullptr;

    struct pw_thread_loop* pw_loop_ = nullptr;
    struct pw_context* pw_ctx_ = nullptr;
    struct pw_core* pw_core_ = nullptr;
    struct pw_stream* pw_stream_ = nullptr;
    struct spa_hook stream_listener_;

    // Ring buffer state
    std::mutex ring_mutex_;
    std::vector<float> audio_ring_buffer_;
    size_t ring_capacity_ = 0;
    size_t ring_head_ = 0;
    size_t ring_tail_ = 0;

    void EnsureRingCapacity(size_t required_capacity);
    void RingBufferPush(const float* samples, size_t count);
    size_t RingBufferSize();
    std::vector<float> RingBufferPop(size_t count);
};

#endif // RUNNER_AUDIO_RECORDER_H_
