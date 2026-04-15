#include "audio_recorder.h"
#include <iostream>
#include <algorithm>
#include <comdef.h>

AudioRecorder::AudioRecorder() {
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                     __uuidof(IMMDeviceEnumerator), (void**)&device_enumerator_);
}

AudioRecorder::~AudioRecorder() {
    Stop();
    if (device_enumerator_) {
        device_enumerator_->Release();
        device_enumerator_ = nullptr;
    }
    CoUninitialize();
}

std::vector<AudioDevice> AudioRecorder::EnumerateAudioDevices() {
    std::vector<AudioDevice> devices;
    auto inputDevices = EnumerateDevices(eCapture);
    auto outputDevices = EnumerateDevices(eRender);
    devices.insert(devices.end(), inputDevices.begin(), inputDevices.end());
    devices.insert(devices.end(), outputDevices.begin(), outputDevices.end());
    return devices;
}

std::vector<AudioDevice> AudioRecorder::EnumerateDevices(EDataFlow dataFlow) {
    std::vector<AudioDevice> devices;
    if (!device_enumerator_) return devices;

    IMMDeviceCollection* device_collection = nullptr;
    HRESULT hr = device_enumerator_->EnumAudioEndpoints(dataFlow, DEVICE_STATE_ACTIVE, &device_collection);

    if (SUCCEEDED(hr)) {
        UINT device_count = 0;
        device_collection->GetCount(&device_count);

        IMMDevice* default_device = nullptr;
        device_enumerator_->GetDefaultAudioEndpoint(dataFlow, eConsole, &default_device);
        LPWSTR default_id = nullptr;
        if (default_device) {
            default_device->GetId(&default_id);
        }

        for (UINT i = 0; i < device_count; i++) {
            IMMDevice* device = nullptr;
            hr = device_collection->Item(i, &device);
            if (SUCCEEDED(hr)) {
                LPWSTR device_id = nullptr;
                device->GetId(&device_id);

                AudioDevice info;
                info.id = _bstr_t(device_id);
                info.name = GetDeviceProperty(device, PKEY_Device_FriendlyName);
                info.description = GetDeviceProperty(device, PKEY_Device_DeviceDesc);
                info.isDefault = (default_id && wcscmp(device_id, default_id) == 0);
                info.type = (dataFlow == eCapture ? "input" : "output");

                int32_t sample_rate = 0;
                std::vector<uint8_t> format_blob = GetDeviceFormatBlob(device);
                if (format_blob.size() >= sizeof(WAVEFORMATEX)) {
                    WAVEFORMATEX* wfx = reinterpret_cast<WAVEFORMATEX*>(format_blob.data());
                    sample_rate = wfx->nSamplesPerSec;
                }
                info.sampleRate = sample_rate;

                devices.push_back(info);

                CoTaskMemFree(device_id);
                device->Release();
            }
        }

        if (default_device) {
            CoTaskMemFree(default_id);
            default_device->Release();
        }
        device_collection->Release();
    }
    return devices;
}

std::string AudioRecorder::GetDeviceProperty(IMMDevice* device, const PROPERTYKEY& key) {
    std::string result;
    IPropertyStore* property_store = nullptr;
    HRESULT hr = device->OpenPropertyStore(STGM_READ, &property_store);
    if (SUCCEEDED(hr)) {
        PROPVARIANT prop_variant;
        PropVariantInit(&prop_variant);
        hr = property_store->GetValue(key, &prop_variant);
        if (SUCCEEDED(hr) && prop_variant.vt == VT_LPWSTR) {
            result = _bstr_t(prop_variant.pwszVal);
        }
        PropVariantClear(&prop_variant);
        property_store->Release();
    }
    return result;
}

std::vector<uint8_t> AudioRecorder::GetDeviceFormatBlob(IMMDevice* device) {
    std::vector<uint8_t> format_data;
    IPropertyStore* property_store = nullptr;
    const PROPERTYKEY key = PKEY_AudioEngine_DeviceFormat;
    HRESULT hr = device->OpenPropertyStore(STGM_READ, &property_store);
    if (SUCCEEDED(hr)) {
        PROPVARIANT pv;
        PropVariantInit(&pv);
        hr = property_store->GetValue(key, &pv);
        if (SUCCEEDED(hr) && pv.vt == VT_BLOB && pv.blob.cbSize > 0) {
            format_data.assign(pv.blob.pBlobData, pv.blob.pBlobData + pv.blob.cbSize);
        }
        PropVariantClear(&pv);
        property_store->Release();
    }
    return format_data;
}

void AudioRecorder::Start(const std::string& deviceId, const std::string& captureType, 
                          int sampleRate, int channels, int blockSize) {
    Stop();
    current_device_id_ = deviceId;
    current_capture_type_ = captureType;
    sample_rate_ = sampleRate;
    channels_ = channels;
    target_blocksize_ = blockSize;

    is_capturing_ = true;
    capture_thread_ = std::thread(&AudioRecorder::AudioCaptureThread, this);
}

void AudioRecorder::Stop() {
    is_capturing_ = false;
    if (capture_thread_.joinable()) {
        capture_thread_.join();
    }

    if (capture_client_) {
        capture_client_->Release();
        capture_client_ = nullptr;
    }

    if (audio_client_) {
        audio_client_->Stop();
        audio_client_->Release();
        audio_client_ = nullptr;
    }

    if (state_callback_) {
        state_callback_("recording_stopped");
    }
}

void AudioRecorder::AudioCaptureThread() {
    if (!device_enumerator_) {
        if (error_callback_) error_callback_("Device enumerator not available");
        return;
    }

    IMMDevice* device = nullptr;
    std::wstring wide_id = _bstr_t(current_device_id_.c_str());
    HRESULT hr = device_enumerator_->GetDevice(wide_id.c_str(), &device);

    if (SUCCEEDED(hr)) {
        try {
            CaptureAudio(device, current_capture_type_ == "loopback");
        } catch (const std::exception& e) {
            if (error_callback_) error_callback_("Capture error: " + std::string(e.what()));
        }
        device->Release();
    } else {
        if (error_callback_) error_callback_("Failed to get audio device");
    }
}

void AudioRecorder::CaptureAudio(IMMDevice* device, bool loopback) {
    HRESULT hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, (void**)&audio_client_);
    if (FAILED(hr)) {
        if (error_callback_) error_callback_("Failed to activate audio client");
        return;
    }

    WAVEFORMATEX custom_format = {};
    custom_format.wFormatTag = WAVE_FORMAT_IEEE_FLOAT;
    custom_format.nChannels = static_cast<WORD>(channels_);
    custom_format.nSamplesPerSec = static_cast<DWORD>(sample_rate_);
    custom_format.wBitsPerSample = static_cast<WORD>(32);
    custom_format.nBlockAlign = static_cast<WORD>(channels_ * 32 / 8);
    custom_format.nAvgBytesPerSec = custom_format.nSamplesPerSec * custom_format.nBlockAlign;
    custom_format.cbSize = 0;

    WAVEFORMATEX* mix_format = &custom_format;
    WAVEFORMATEX* closest_supported = nullptr;
    hr = audio_client_->IsFormatSupported(AUDCLNT_SHAREMODE_SHARED, mix_format, &closest_supported);
    if (hr == S_FALSE && closest_supported) {
        mix_format = closest_supported;
    } else if (FAILED(hr)) {
        if (error_callback_) error_callback_("Requested audio format not supported");
        return;
    }

    HANDLE hEvent = CreateEvent(nullptr, FALSE, FALSE, nullptr);
    if (!hEvent) {
        if (closest_supported) CoTaskMemFree(closest_supported);
        if (error_callback_) error_callback_("Failed to create event handle");
        return;
    }

    DWORD streamFlags = loopback ? (AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK)
                                 : AUDCLNT_STREAMFLAGS_EVENTCALLBACK;

    int device_sample_rate = mix_format->nSamplesPerSec;
    REFERENCE_TIME buffer_duration = CalculateBufferDuration(device_sample_rate, target_blocksize_);

    hr = audio_client_->Initialize(AUDCLNT_SHAREMODE_SHARED, streamFlags, buffer_duration, 0, mix_format, nullptr);
    if (FAILED(hr)) {
        CloseHandle(hEvent);
        if (closest_supported) CoTaskMemFree(closest_supported);
        if (error_callback_) error_callback_("Failed to initialize audio client");
        return;
    }

    hr = audio_client_->SetEventHandle(hEvent);
    hr = audio_client_->GetService(__uuidof(IAudioCaptureClient), (void**)&capture_client_);

    // Reset ring buffer
    {
        std::lock_guard<std::mutex> lock(ring_mutex_);
        audio_ring_buffer_.clear();
        ring_capacity_ = 0;
        ring_head_ = ring_tail_ = 0;
    }

    audio_client_->Start();
    if (state_callback_) state_callback_("recording_started");

    while (is_capturing_) {
        DWORD waitResult = WaitForSingleObject(hEvent, INFINITE);
        if (waitResult == WAIT_OBJECT_0 && is_capturing_) {
            UINT32 packet_length = 0;
            capture_client_->GetNextPacketSize(&packet_length);

            while (packet_length != 0 && is_capturing_) {
                BYTE* data = nullptr;
                UINT32 frames_available = 0;
                DWORD flags = 0;

                hr = capture_client_->GetBuffer(&data, &frames_available, &flags, nullptr, nullptr);
                if (SUCCEEDED(hr)) {
                    float* float_data = reinterpret_cast<float*>(data);
                    UINT32 float_count = frames_available * mix_format->nChannels;

                    if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
                        std::vector<float> zero_buf(float_count, 0.0f);
                        RingBufferPush(zero_buf.data(), zero_buf.size());
                    } else if (float_count > 0) {
                        RingBufferPush(float_data, float_count);
                    }

                    capture_client_->ReleaseBuffer(frames_available);

                    size_t frames_needed = (target_blocksize_ > 0) ? target_blocksize_ : frames_available;
                    size_t samples_needed = frames_needed * mix_format->nChannels;

                    while (RingBufferSize() >= samples_needed && is_capturing_) {
                        std::vector<float> block = RingBufferPop(samples_needed);
                        if (mix_format->nChannels == 2) {
                            std::vector<float> mono_block;
                            mono_block.reserve(frames_needed);
                            for (size_t i = 0; i + 1 < block.size(); i += 2) {
                                mono_block.push_back((block[i] + block[i + 1]) * 0.5f);
                            }
                            if (data_callback_) data_callback_(mono_block);
                        } else {
                            if (data_callback_) data_callback_(block);
                        }
                    }
                }
                capture_client_->GetNextPacketSize(&packet_length);
            }
        }
    }

    audio_client_->Stop();
    CloseHandle(hEvent);
    if (closest_supported) CoTaskMemFree(closest_supported);
}

REFERENCE_TIME AudioRecorder::CalculateBufferDuration(int device_sample_rate, int target_blocksize) {
    if (target_blocksize <= 0) return 10000000; // 1s
    double duration_seconds = static_cast<double>(target_blocksize) / static_cast<double>(device_sample_rate);
    REFERENCE_TIME buffer_duration = static_cast<REFERENCE_TIME>(duration_seconds * 10000000.0);
    if (buffer_duration < 30000) buffer_duration = 30000;
    return buffer_duration;
}

void AudioRecorder::EnsureRingCapacity(size_t required_capacity) {
    std::lock_guard<std::mutex> lock(ring_mutex_);
    if (ring_capacity_ >= required_capacity) return;
    size_t new_capacity = required_capacity * 2;
    std::vector<float> new_buf(new_capacity);
    size_t current_size = 0;
    if (ring_capacity_ > 0) {
        if (ring_head_ >= ring_tail_) {
            current_size = ring_head_ - ring_tail_;
            std::copy(audio_ring_buffer_.begin() + ring_tail_, audio_ring_buffer_.begin() + ring_head_, new_buf.begin());
        } else {
            current_size = ring_capacity_ - ring_tail_ + ring_head_;
            size_t first_part = ring_capacity_ - ring_tail_;
            std::copy(audio_ring_buffer_.begin() + ring_tail_, audio_ring_buffer_.end(), new_buf.begin());
            std::copy(audio_ring_buffer_.begin(), audio_ring_buffer_.begin() + ring_head_, new_buf.begin() + first_part);
        }
    }
    audio_ring_buffer_.swap(new_buf);
    ring_capacity_ = new_capacity;
    ring_tail_ = 0;
    ring_head_ = current_size;
}

void AudioRecorder::RingBufferPush(const float* samples, size_t count) {
    std::lock_guard<std::mutex> lock(ring_mutex_);
    if (ring_capacity_ == 0) {
        size_t desired = std::max<size_t>(count * 8, count * 2);
        audio_ring_buffer_.assign(desired, 0.0f);
        ring_capacity_ = desired;
        ring_head_ = 0;
        ring_tail_ = 0;
    }
    size_t current_size = (ring_head_ >= ring_tail_) ? (ring_head_ - ring_tail_) : (ring_capacity_ - ring_tail_ + ring_head_);
    if (current_size + count >= ring_capacity_) {
        EnsureRingCapacity(current_size + count + 1);
    }
    size_t first_write = std::min(count, ring_capacity_ - ring_head_);
    std::copy(samples, samples + first_write, audio_ring_buffer_.begin() + ring_head_);
    ring_head_ = (ring_head_ + first_write) % ring_capacity_;
    size_t remaining = count - first_write;
    if (remaining > 0) {
        std::copy(samples + first_write, samples + first_write + remaining, audio_ring_buffer_.begin() + ring_head_);
        ring_head_ = (ring_head_ + remaining) % ring_capacity_;
    }
}

size_t AudioRecorder::RingBufferSize() {
    std::lock_guard<std::mutex> lock(ring_mutex_);
    if (ring_capacity_ == 0) return 0;
    if (ring_head_ >= ring_tail_) return ring_head_ - ring_tail_;
    return ring_capacity_ - ring_tail_ + ring_head_;
}

std::vector<float> AudioRecorder::RingBufferPop(size_t count) {
    std::lock_guard<std::mutex> lock(ring_mutex_);
    std::vector<float> out(count);
    if (count == 0 || ring_capacity_ == 0) return out;
    size_t first_read = std::min(count, ring_capacity_ - ring_tail_);
    std::copy(audio_ring_buffer_.begin() + ring_tail_, audio_ring_buffer_.begin() + ring_tail_ + first_read, out.begin());
    ring_tail_ = (ring_tail_ + first_read) % ring_capacity_;
    size_t remaining = count - first_read;
    if (remaining > 0) {
        std::copy(audio_ring_buffer_.begin() + ring_tail_, audio_ring_buffer_.begin() + ring_tail_ + remaining, out.begin() + first_read);
        ring_tail_ = (ring_tail_ + remaining) % ring_capacity_;
    }
    return out;
}
