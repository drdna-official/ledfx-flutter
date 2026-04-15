#include "audio_recorder.h"
#include <iostream>
#include <spa/param/audio/format-utils.h>

const struct pw_stream_events stream_events = {
    .version = PW_VERSION_STREAM_EVENTS,
    .process = AudioRecorder::on_pw_process,
};

void AudioRecorder::on_pw_process(void *userdata) {
    AudioRecorder *self = static_cast<AudioRecorder*>(userdata);
    if (!self || !self->pw_stream_ || !self->is_capturing_) return;

    struct pw_buffer *b;
    struct spa_buffer *buf;

    if ((b = pw_stream_dequeue_buffer(self->pw_stream_)) == NULL) {
        return;
    }

    buf = b->buffer;
    if (buf->datas[0].data != NULL) {
        float *data = static_cast<float*>(buf->datas[0].data);
        uint32_t n_samples = buf->datas[0].chunk->size / sizeof(float);
        
        if (n_samples > 0) {
            self->RingBufferPush(data, n_samples * self->channels_);
            size_t frames_needed = (self->target_blocksize_ > 0) ? self->target_blocksize_ : n_samples;
            size_t samples_needed = frames_needed * self->channels_;
            
            while (self->RingBufferSize() >= samples_needed && self->is_capturing_) {
                std::vector<float> block = self->RingBufferPop(samples_needed);
                if (self->data_callback_) {
                    self->data_callback_(block);
                }
            }
        }
    }

    pw_stream_queue_buffer(self->pw_stream_, b);
}

AudioRecorder::AudioRecorder() {
    pw_init(nullptr, nullptr);
    
    pw_loop_ = pw_thread_loop_new("audio-capture", nullptr);
    if (pw_loop_) {
        pw_ctx_ = pw_context_new(pw_thread_loop_get_loop(pw_loop_), nullptr, 0);
        if (pw_ctx_) {
            pw_thread_loop_start(pw_loop_);
            pw_thread_loop_lock(pw_loop_);
            pw_core_ = pw_context_connect(pw_ctx_, nullptr, 0);
            if (!pw_core_) {
                pw_thread_loop_unlock(pw_loop_);
                pw_context_destroy(pw_ctx_);
                pw_ctx_ = nullptr;
                pw_thread_loop_destroy(pw_loop_);
                pw_loop_ = nullptr;
            } else {
                pw_thread_loop_unlock(pw_loop_);
            }
        } else {
            pw_thread_loop_destroy(pw_loop_);
            pw_loop_ = nullptr;
        }
    }
    
    if (pw_core_ != nullptr) {
        std::cout << "[AudioRecorder] PipeWire initialized and will be used for audio capture." << std::endl;
        use_pulseaudio_fallback_ = false;
    } else {
        std::cout << "[AudioRecorder] PipeWire not available. Falling back to PulseAudio." << std::endl;
        use_pulseaudio_fallback_ = true;
    }
}

AudioRecorder::~AudioRecorder() {
    Stop();
    if (pw_core_) {
        pw_thread_loop_lock(pw_loop_);
        pw_core_disconnect(pw_core_);
        pw_thread_loop_unlock(pw_loop_);
        
        pw_thread_loop_stop(pw_loop_);
        pw_context_destroy(pw_ctx_);
        pw_thread_loop_destroy(pw_loop_);
    }
    pw_deinit();
}

std::vector<AudioDevice> AudioRecorder::EnumerateAudioDevices() {
    std::vector<AudioDevice> devices;
    
    // We provide a generic "System Audio" device pointing to the PulseAudio default sink monitor.
    // @DEFAULT_MONITOR@ is a magic string in PulseAudio that resolves to the monitor of the default sink.
    AudioDevice defaultDevice;
    defaultDevice.id = "@DEFAULT_MONITOR@";
    defaultDevice.name = "System Audio";
    defaultDevice.description = "PulseAudio Default Monitor";
    defaultDevice.sampleRate = 48000;
    defaultDevice.isDefault = true;
    defaultDevice.type = "input";
    devices.push_back(defaultDevice);

    // We can also add default as microphone
    AudioDevice defaultMic;
    defaultMic.id = "@DEFAULT_SOURCE@";
    defaultMic.name = "Default Microphone";
    defaultMic.description = "PulseAudio Default Source";
    defaultMic.sampleRate = 48000;
    defaultMic.isDefault = false;
    defaultMic.type = "input";
    devices.push_back(defaultMic);

    return devices;
}

void AudioRecorder::Start(const std::string& deviceId, const std::string& captureType, 
                           int sampleRate, int channels, int blockSize) {
    if (is_capturing_) {
        return;
    }

    current_device_id_ = deviceId;
    current_capture_type_ = captureType;
    sample_rate_ = sampleRate;
    channels_ = channels;
    target_blocksize_ = blockSize;

    is_capturing_ = true;
    capture_thread_ = std::thread(&AudioRecorder::AudioCaptureThread, this);
    
    if (state_callback_) {
        state_callback_("recording_started");
    }
}

void AudioRecorder::Stop() {
    if (!is_capturing_) {
        return;
    }
    
    is_capturing_ = false;
    if (capture_thread_.joinable()) {
        capture_thread_.join();
    }
    
    if (state_callback_) {
        state_callback_("recording_stopped");
    }
}

void AudioRecorder::AudioCaptureThread() {
    std::cout << "[AudioRecorder] Audio capture thread started. Using " 
              << (use_pulseaudio_fallback_ ? "PulseAudio" : "PipeWire") << std::endl;

    if (use_pulseaudio_fallback_) {
        pa_sample_spec ss;
        ss.format = PA_SAMPLE_FLOAT32LE;
        ss.rate = sample_rate_;
        ss.channels = channels_;

        int error;
        // If a specific device is targeted (like a monitor), use it. Otherwise, default.
        const char* source = (current_device_id_.empty() || current_device_id_ == "default") ? NULL : current_device_id_.c_str();

        pa_stream_ = pa_simple_new(NULL, "LEDFx", PA_STREAM_RECORD, source, "Record", &ss, NULL, NULL, &error);
        if (!pa_stream_) {
            std::cout << "[AudioRecorder] PulseAudio connection failed: " << pa_strerror(error) << std::endl;
            if (error_callback_) error_callback_("PulseAudio init failed");
            is_capturing_ = false;
        } else {
            std::cout << "[AudioRecorder] PulseAudio connection successful. Source: " << (source ? source : "default") << std::endl;
        }
    }

    size_t samples_per_block = target_blocksize_ > 0 ? target_blocksize_ : 1024;
    std::vector<float> buffer(samples_per_block * channels_);

    while (is_capturing_) {
        if (use_pulseaudio_fallback_ && pa_stream_) {
            int pa_error = 0;
            if (pa_simple_read(pa_stream_, buffer.data(), buffer.size() * sizeof(float), &pa_error) < 0) {
                std::cout << "[AudioRecorder] pa_simple_read() failed: " << pa_strerror(pa_error) << std::endl;
                if (error_callback_) error_callback_("PulseAudio read failed");
                break;
            }
            RingBufferPush(buffer.data(), buffer.size());
            size_t frames_needed = (target_blocksize_ > 0) ? target_blocksize_ : samples_per_block;
            size_t samples_needed = frames_needed * channels_;
            while (RingBufferSize() >= samples_needed && is_capturing_) {
                std::vector<float> block = RingBufferPop(samples_needed);
                if (data_callback_) {
                    data_callback_(block);
                }
            }
        } else {
            pw_thread_loop_lock(pw_loop_);
            
            const struct spa_pod *params[1];
            uint8_t pb[1024];
            struct spa_pod_builder b = SPA_POD_BUILDER_INIT(pb, sizeof(pb));

            struct pw_properties *props = pw_properties_new(
                PW_KEY_MEDIA_TYPE, "Audio",
                PW_KEY_MEDIA_CATEGORY, "Capture",
                PW_KEY_MEDIA_ROLE, "Music",
                nullptr);

            uint32_t target_node = PW_ID_ANY;
            if (current_device_id_ == "@DEFAULT_MONITOR@") {
                pw_properties_set(props, PW_KEY_STREAM_CAPTURE_SINK, "true");
            } else if (!current_device_id_.empty() && 
                       current_device_id_ != "default" && 
                       current_device_id_ != "@DEFAULT_SOURCE@") {
                pw_properties_set(props, PW_KEY_TARGET_OBJECT, current_device_id_.c_str());
            }
            
            pw_stream_ = pw_stream_new(pw_core_, "ledfx_capture", props);

            if (pw_stream_ != nullptr) {
                spa_zero(stream_listener_);
                pw_stream_add_listener(pw_stream_, &stream_listener_, &stream_events, this);
                
                struct spa_audio_info_raw info = {};
                info.format = SPA_AUDIO_FORMAT_F32;
                info.rate = sample_rate_;
                info.channels = channels_;

                params[0] = spa_format_audio_raw_build(&b, SPA_PARAM_EnumFormat, &info);
                
                pw_stream_connect(pw_stream_, PW_DIRECTION_INPUT, target_node,
                    (pw_stream_flags)(PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS),
                    params, 1);
            }
            
            pw_thread_loop_unlock(pw_loop_);
            
            while (is_capturing_) {
                std::this_thread::sleep_for(std::chrono::milliseconds(100)); 
            }
            
            pw_thread_loop_lock(pw_loop_);
            if (pw_stream_) {
                pw_stream_destroy(pw_stream_);
                pw_stream_ = nullptr;
            }
            pw_thread_loop_unlock(pw_loop_);
        }
    }
    
    if (pa_stream_) {
        pa_simple_free(pa_stream_);
        pa_stream_ = nullptr;
    }
    
    std::cout << "[AudioRecorder] Audio capture thread stopped." << std::endl;
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
            std::copy(audio_ring_buffer_.begin() + ring_tail_,
                      audio_ring_buffer_.begin() + ring_head_, new_buf.begin());
        } else {
            current_size = ring_capacity_ - ring_tail_ + ring_head_;
            size_t first_part = ring_capacity_ - ring_tail_;
            std::copy(audio_ring_buffer_.begin() + ring_tail_,
                      audio_ring_buffer_.end(), new_buf.begin());
            std::copy(audio_ring_buffer_.begin(),
                      audio_ring_buffer_.begin() + ring_head_,
                      new_buf.begin() + first_part);
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
    size_t current_size = (ring_head_ >= ring_tail_)
                              ? (ring_head_ - ring_tail_)
                              : (ring_capacity_ - ring_tail_ + ring_head_);
    if (current_size + count >= ring_capacity_) {
        EnsureRingCapacity(current_size + count + 1);
    }
    size_t first_write = std::min(count, ring_capacity_ - ring_head_);
    std::copy(samples, samples + first_write,
              audio_ring_buffer_.begin() + ring_head_);
    ring_head_ = (ring_head_ + first_write) % ring_capacity_;
    size_t remaining = count - first_write;
    if (remaining > 0) {
        std::copy(samples + first_write, samples + first_write + remaining,
                  audio_ring_buffer_.begin() + ring_head_);
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
    std::copy(audio_ring_buffer_.begin() + ring_tail_,
              audio_ring_buffer_.begin() + ring_tail_ + first_read, out.begin());
    ring_tail_ = (ring_tail_ + first_read) % ring_capacity_;
    size_t remaining = count - first_read;
    if (remaining > 0) {
        std::copy(audio_ring_buffer_.begin() + ring_tail_,
                  audio_ring_buffer_.begin() + ring_tail_ + remaining,
                  out.begin() + first_read);
        ring_tail_ = (ring_tail_ + remaining) % ring_capacity_;
    }
    return out;
}
