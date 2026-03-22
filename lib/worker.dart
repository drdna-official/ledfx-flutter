import 'dart:async';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:ledfx/src/effects/effect.dart';
import 'package:ledfx/platform_interface/audio_bridge.dart';
import 'package:ledfx/src/virtual.dart';

/// The proxy class that the UI uses to communicate with the background
/// `LEDFx` isolate.
class LEDFxWorker {
  LEDFxWorker._();
  static final LEDFxWorker instance = LEDFxWorker._();

  SendPort? _bgPort;
  ReceivePort? _uiReceivePort;

  // State we want the UI to have access to
  ValueNotifier<List<Map<String, dynamic>>> devices = ValueNotifier([]);
  ValueNotifier<List<Map<String, dynamic>>> virtuals = ValueNotifier([]);

  // Per-device RGB notifiers for lower overhead vs streams
  final Map<String, ValueNotifier<List<int>>> _deviceRgbNotifiers = {};
  final Map<String, DateTime> _lastUpdate = {};
  static const _throttleDuration = Duration(milliseconds: 33); // ~30 FPS

  ValueListenable<List<int>> getDeviceRgbNotifier(String deviceID) {
    return _deviceRgbNotifiers.putIfAbsent(deviceID, () => ValueNotifier<List<int>>([]));
  }

  // Audio state
  ValueNotifier<bool> isAudioCapturing = ValueNotifier(false);
  ValueNotifier<List<AudioDevice>> audioDevices = ValueNotifier([]);
  ValueNotifier<int> activeAudioDeviceIndex = ValueNotifier(0);

  // Info state
  ValueNotifier<String> infoSnackText = ValueNotifier("");

  Future<void> init() async {
    _uiReceivePort?.close(); // Close existing port if re-initializing
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
        isAudioCapturing.value = event.value == "recording_started";
      }
    });
    AudioBridge.instance.getDevices();

    // Fetch the initial recording state directly to sync UI
    final bool? isCapturing = await AudioBridge.instance.getRecordingState();
    if (isCapturing != null) {
      isAudioCapturing.value = isCapturing;
    }
  }

  void _connectToBackground() {
    _bgPort = IsolateNameServer.lookupPortByName("ledfx_bg_port");
    if (_bgPort != null) {
      // Background is alive! Request initial state.
      requestState();
    }
  }

  void send(Map<String, dynamic> message) {
    if (_bgPort == null) _connectToBackground();
    _bgPort?.send(message);
  }

  Future<void> _waitForBackground() async {
    while (_bgPort == null) {
      _bgPort = IsolateNameServer.lookupPortByName("ledfx_bg_port");
      if (_bgPort != null) {
        requestState();
        break;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  void _handleBackgroundMessage(Map<String, dynamic> message) {
    switch (message["event"]) {
      case "state_update":
        debugPrint("State update: ${message["state"]}");
        final state = message["state"] as Map<String, dynamic>;
        if (state.containsKey("devices")) {
          devices.value = List<Map<String, dynamic>>.from(state["devices"]);
        }
        if (state.containsKey("virtuals")) {
          virtuals.value = List<Map<String, dynamic>>.from(state["virtuals"]);
        }
        break;
      case "visualizer_update":
        final deviceID = message["deviceID"];
        final data = message["data"];
        if (deviceID != null && data is List<int>) {
          final now = DateTime.now();
          final last = _lastUpdate[deviceID] ?? DateTime.fromMillisecondsSinceEpoch(0);
          if (now.difference(last) >= _throttleDuration) {
            _lastUpdate[deviceID] = now;
            _deviceRgbNotifiers[deviceID]?.value = data;
          }
        }
        break;
      case "audio_state":
        isAudioCapturing.value = message["isCapturing"] ?? false;
        break;
      case "info":
        infoSnackText.value = message["info"]["message"];
        break;
    }
  }

  // ===== Proxy Methods for UI -> Background =====

  void requestState() {
    send({"cmd": "request_state"});
  }

  void addDevice(String name, String type, String address) {
    send({
      "cmd": "add_device",
      "payload": {"type": type, "name": name, "address": address},
    });
  }

  void removeDevice(String deviceId) {
    send({"cmd": "remove_device", "deviceId": deviceId});
    _deviceRgbNotifiers[deviceId]?.dispose();
    _deviceRgbNotifiers.remove(deviceId);
    _lastUpdate.remove(deviceId);
  }

  void addNewVirtual(String name) {
    send({"cmd": "add_virtual", "name": name});
  }

  void removeVirtual(String virtualId) {
    send({"cmd": "remove_virtual", "virtualId": virtualId});
  }

  void updateVirtualSegments(String virtualId, List<SegmentConfig> segments) {
    send({
      "cmd": "update_virtual_segments",
      "virtualId": virtualId,
      "segments": segments.map((s) => s.toJson()).toList(),
    });
  }

  void toggleVirtual(String virtualId, bool active) {
    send({"cmd": "set_virtual_active", "virtualId": virtualId, "active": active});
  }

  void setVirtualEffect(String virtualId, EffectConfig effectConfig) {
    send({
      "cmd": "set_virtual_effect",
      "virtualId": virtualId,
      "effectType": effectConfig.name,
      "config": effectConfig.toJson(),
    });
  }

  Future<void> startAudioCapture() async {
    send({"cmd": "start_audio_capture"});
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
    send({"cmd": "stop_audio_capture"});
    await AudioBridge.instance.stop();
  }

  void dispose() {
    IsolateNameServer.removePortNameMapping("ledfx_ui_port");
    _uiReceivePort?.close();
    for (final notifier in _deviceRgbNotifiers.values) {
      notifier.dispose();
    }
    _deviceRgbNotifiers.clear();
    _lastUpdate.clear();
  }
}
