import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:ledfx/src/devices/device.dart';
import 'package:ledfx/src/effects/effect.dart';
import 'package:ledfx/src/platform/audio_bridge.dart';

/// The proxy class that the UI uses to communicate with the background
/// `LEDFx` isolate.
class LEDFxWorker {
  SendPort? _bgPort;
  ReceivePort? _uiReceivePort;

  // State we want the UI to have access to
  ValueNotifier<List<Map<String, dynamic>>> devices = ValueNotifier([]);
  ValueNotifier<List<Map<String, dynamic>>> virtuals = ValueNotifier([]);
  ValueNotifier<List<int>> rgb = ValueNotifier([]);

  // Audio state
  ValueNotifier<bool> isAudioCapturing = ValueNotifier(false);
  ValueNotifier<List<AudioDevice>> audioDevices = ValueNotifier([]);
  ValueNotifier<int> activeAudioDeviceIndex = ValueNotifier(0);

  Future<void> init() async {
    _uiReceivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping("ledfx_ui_port");
    IsolateNameServer.registerPortWithName(_uiReceivePort!.sendPort, "ledfx_ui_port");

    _uiReceivePort!.listen((message) {
      if (message is Map<String, dynamic>) {
        _handleBackgroundMessage(message);
      }
    });

    // Wait for the background port to become available
    await _waitForBackground();

    // Listen to local AudioBridge events for devices and state
    AudioBridge.instance.events.listen((event) {
      if (event is DevicesInfoEvent) {
        audioDevices.value = event.audioDevices;
      } else if (event is StateEvent) {
        isAudioCapturing.value = event.state == "recordingStarted";
      }
    });
    AudioBridge.instance.getDevices();
  }

  void _connectToBackground() {
    _bgPort = IsolateNameServer.lookupPortByName("ledfx_bg_port");
    if (_bgPort != null) {
      // Background is alive! Request initial state.
      _bgPort!.send({"cmd": "request_state"});
    }
  }

  Future<void> _waitForBackground() async {
    while (_bgPort == null) {
      _bgPort = IsolateNameServer.lookupPortByName("ledfx_bg_port");
      if (_bgPort != null) {
        _bgPort!.send({"cmd": "request_state"});
        break;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  void _handleBackgroundMessage(Map<String, dynamic> message) {
    switch (message["event"]) {
      case "state_update":
        final state = message["state"] as Map<String, dynamic>;
        if (state.containsKey("devices")) {
          devices.value = List<Map<String, dynamic>>.from(state["devices"]);
        }
        if (state.containsKey("virtuals")) {
          virtuals.value = List<Map<String, dynamic>>.from(state["virtuals"]);
        }
        break;
      case "visualizer_update":
        // Efficient format to send Float64Lists back usually involves sending a flat list
        final data = message["data"];
        if (data is List<int>) {
          rgb.value = data;
        }
        break;
      case "audio_state":
        isAudioCapturing.value = message["isCapturing"] ?? false;
        break;
    }
  }

  // ===== Proxy Methods for UI -> Background =====

  void addDevice(DeviceConfig config) {
    _send({"cmd": "add_device", "payload": config.toJson()});
  }

  void removeDevice(String deviceId) {
    _send({"cmd": "remove_device", "deviceId": deviceId});
  }

  void setVirtualActive(String virtualId, bool active) {
    _send({"cmd": "set_virtual_active", "virtualId": virtualId, "active": active});
  }

  void setEffect(String virtualId, EffectConfig effectConfig) {
    _send({
      "cmd": "set_effect",
      "virtualId": virtualId,
      "effectType": "WavelengthEffect", // Hardcoded for now based on UI
      "config": effectConfig.toJson(),
    });
  }

  Future<void> startAudioCapture() async {
    if (audioDevices.value.isEmpty) {
      await AudioBridge.instance.getDevices();
    }
    // Need to yield to let the event loop process the getDevices callback if it was empty,
    // but in most cases it's already populated by init().
    if (audioDevices.value.isNotEmpty) {
      final activeDevice = audioDevices.value[activeAudioDeviceIndex.value];
      await AudioBridge.instance.start({
        "deviceId": activeDevice.id,
        "captureType": activeDevice.type == AudioDeviceType.input ? "capture" : "loopback",
        "sampleRate": activeDevice.defaultSampleRate,
        "channels": 1,
        "blockSize": activeDevice.defaultSampleRate ~/ 60,
      });
    }
  }

  Future<void> stopAudioCapture() async {
    await AudioBridge.instance.stop();
  }

  void _send(Map<String, dynamic> message) {
    if (_bgPort == null) _connectToBackground();
    _bgPort?.send(message);
  }

  void dispose() {
    IsolateNameServer.removePortNameMapping("ledfx_ui_port");
    _uiReceivePort?.close();
  }
}
