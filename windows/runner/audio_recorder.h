#ifndef RUNNER_AUDIO_RECORDER_H_
#define RUNNER_AUDIO_RECORDER_H_

#include <initguid.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <audiopolicy.h>
#include <functiondiscoverykeys_devpkey.h>

#include <string>
#include <vector>
#include <thread>
#include <atomic>
#include <mutex>
#include <functional>
#include <memory>

// Forward declarations for Flutter types if needed, but we'll try to keep this pure C++ 
// or use simple structs to avoid heavy Flutter dependencies in the core recorder.

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

private:
    void AudioCaptureThread();
    void CaptureAudio(IMMDevice* device, bool loopback);
    REFERENCE_TIME CalculateBufferDuration(int device_sample_rate, int target_blocksize);

    // Ring buffer methods
    void EnsureRingCapacity(size_t required_capacity);
    void RingBufferPush(const float* samples, size_t count);
    size_t RingBufferSize();
    std::vector<float> RingBufferPop(size_t count);

    // Device helpers
    std::vector<AudioDevice> EnumerateDevices(EDataFlow dataFlow);
    std::string GetDeviceProperty(IMMDevice* device, const PROPERTYKEY& key);
    std::vector<uint8_t> GetDeviceFormatBlob(IMMDevice* device);

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

    // Ring buffer state
    std::vector<float> audio_ring_buffer_;
    size_t ring_head_ = 0;
    size_t ring_tail_ = 0;
    size_t ring_capacity_ = 0;
    std::mutex ring_mutex_;

    // WASAPI interfaces
    IMMDeviceEnumerator* device_enumerator_ = nullptr;
    IAudioClient* audio_client_ = nullptr;
    IAudioCaptureClient* capture_client_ = nullptr;
};

#endif // RUNNER_AUDIO_RECORDER_H_
