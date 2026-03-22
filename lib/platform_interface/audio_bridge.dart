import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:ui';

/// Sealed union of all events from the native bridge
sealed class RecordingEvent {
  const RecordingEvent();
}

class AudioEvent extends RecordingEvent {
  final Float64List data;
  AudioEvent(List<Object?> adata)
    : data = Float64List.fromList(
        adata.map((e) {
          return (e == null) ? 0.0 : e as double;
        }).toList(),
      );
}

class DevicesInfoEvent extends RecordingEvent {
  final List<AudioDevice> audioDevices;
  DevicesInfoEvent(List data)
    : audioDevices = (data as List? ?? [])
          .map((device) => AudioDevice.fromMap(device.cast<String, dynamic>()))
          .toList();
}

// Audio device model
class AudioDevice extends Equatable {
  final String id;
  final String name;
  final String description;
  final int defaultSampleRate;
  final bool isActive;
  final bool isDefault;
  final AudioDeviceType type;

  const AudioDevice({
    required this.id,
    required this.name,
    required this.description,
    required this.defaultSampleRate,
    required this.isActive,
    required this.isDefault,
    required this.type,
  });

  factory AudioDevice.fromMap(Map<String, dynamic> map) {
    return AudioDevice(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      isActive: map['isActive'] ?? false,
      defaultSampleRate: map['sampleRate'] ?? 44100,
      isDefault: map['isDefault'] ?? false,
      type: AudioDeviceType.values.firstWhere((e) => e.name == map['type'], orElse: () => AudioDeviceType.input),
    );
  }

  @override
  List<Object?> get props => [id];
}

enum AudioDeviceType { input, output }

enum AudioCaptureType { microphone, systemAudio }

class StateEvent extends RecordingEvent {
  // value = "recording_started", "recording_stopped"
  final String value;
  const StateEvent(this.value);
}

class ErrorEvent extends RecordingEvent {
  final String message;
  const ErrorEvent(this.message);
}

class AudioBridge {
  AudioBridge._() {
    _event.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        switch (event["type"]) {
          case "audio":
            _controller.add(AudioEvent(event["data"]));
            break;
          case "state":
            _controller.add(StateEvent(event["value"]));
            break;
          case "error":
            _controller.add(ErrorEvent(event["message"]));
            break;
          case "devicesInfo":
            _controller.add(DevicesInfoEvent(List.from(event["devices"])));
        }
      }
    });
  }
  static final AudioBridge instance = AudioBridge._();

  final _method = MethodChannel("system_audio_recorder/methods");
  final _event = EventChannel("system_audio_recorder/events");

  static final _controller = StreamController<RecordingEvent>.broadcast();

  /// Only one stream to listen to
  Stream<RecordingEvent> get events => _controller.stream;

  /// Ask Android to show the MediaProjection dialog (returns bool success)
  Future<bool> requestProjection() async {
    try {
      final res = await _method.invokeMethod<bool?>('requestProjection');
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  // Convenience methods for native calls
  Future<bool> setupBackgroundExecution(Function callback) async {
    final callbackHandle = PluginUtilities.getCallbackHandle(callback as Function);
    if (callbackHandle == null) return false;
    try {
      final res = await _method.invokeMethod<bool>('setupBackgroundExecution', {
        'handle': callbackHandle.toRawHandle(),
      });
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool?> getDevices() async {
    if (Platform.isAndroid) {
      _controller.add(
        DevicesInfoEvent([
          {
            "id": "1",
            "name": "System Internal",
            "description": "System Internal",
            "isActive": true,
            "samplerate": 48000,
            "type": "output",
          },
          {
            "id": "2",
            "name": "Microphone",
            "description": "Microphone",
            "isActive": true,
            "samplerate": 48000,
            "type": "input",
          },
        ]),
      );
      return true;
    } else {
      try {
        return await _method.invokeMethod<bool?>('requestDeviceList');
      } catch (e) {
        return false;
      }
    }
  }

  Future<bool?> start(Map<String, dynamic> args) async {
    try {
      if (Platform.isAndroid) {
        final success = await androidPermissions(args["captureType"] == "loopback");
        if (success) {
          return await _method.invokeMethod<bool?>('startRecording', args);
        } else {
          return false;
        }
      } else {
        return await _method.invokeMethod<bool?>('startRecording', args);
      }
    } catch (e) {
      return false;
    }
  }

  Future<bool?> stop() async {
    try {
      return await _method.invokeMethod<bool?>('stopRecording');
    } catch (e) {
      return false;
    }
  }

  Future<bool?> getRecordingState() async {
    try {
      return await _method.invokeMethod<bool?>('getRecordingState');
    } catch (e) {
      return false;
    }
  }

  Future<bool> androidPermissions(bool requireMediaProjection) async {
    final p = await Permission.microphone.request();
    if (!p.isGranted) return false;

    final notif = await Permission.notification.request();
    if (!notif.isGranted) return false;

    if (requireMediaProjection) {
      final ok = await requestProjection();
      if (!ok) return false;
    }

    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    return true;
  }
}
