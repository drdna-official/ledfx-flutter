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

  ReceivePort? _uiReceivePort;

  // State we want the UI to have access to
  ValueNotifier<List<Map<String, dynamic>>> devices = ValueNotifier([]);
  ValueNotifier<List<Map<String, dynamic>>> virtuals = ValueNotifier([]);

  // Per-device RGB notifiers for lower overhead vs streams
  final Map<String, ValueNotifier<List<int>>> _deviceRgbNotifiers = {};
  final Map<String, DateTime> _lastVizUpdate = {};
  static const _throttleDuration = Duration(milliseconds: 33); // ~30 FPS

  StreamSubscription? _audioSubscription;
  StreamSubscription? _uiPortSubscription;
  Completer<void>? _syncCompleter;

  ValueListenable<List<int>> getDeviceRgbNotifier(String deviceID) {
    return _deviceRgbNotifiers.putIfAbsent(deviceID, () => ValueNotifier<List<int>>([]));
  }

  // Audio state
  ValueNotifier<bool> isAudioCapturing = ValueNotifier(false);
  ValueNotifier<List<AudioDevice>> audioDevices = ValueNotifier([]);
  ValueNotifier<int> activeAudioDeviceIndex = ValueNotifier(0);

  // Info state
  ValueNotifier<String> infoSnackText = ValueNotifier("");

  Future<bool> init() async {
    debugPrint("LEDFxWorker: Initializing...");
    _uiReceivePort?.close(); // Close existing port if re-initializing
    _uiReceivePort = ReceivePort();
    _syncCompleter = Completer<void>();

    IsolateNameServer.removePortNameMapping("ledfx_ui_port");
    final registered = IsolateNameServer.registerPortWithName(_uiReceivePort!.sendPort, "ledfx_ui_port");
    debugPrint("LEDFxWorker: UI port registered: $registered");

    _uiPortSubscription = _uiReceivePort!.listen((message) {
      if (message is Map<String, dynamic>) {
        _handleBackgroundMessage(message);
      }
    });

    SendPort? bgPort;
    debugPrint("LEDFxWorker: Waiting for background port...");
    while (bgPort == null) {
      bgPort = IsolateNameServer.lookupPortByName("ledfx_bg_port");
      if (bgPort != null) {
        debugPrint("LEDFxWorker: Background port found during worker init, requesting state");
        requestState();
        break;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Synchronization retry loop
    int syncAttempts = 0;
    while (syncAttempts < 10) {
      debugPrint("LEDFxWorker: Waiting for state synchronization (attempt ${syncAttempts + 1})...");
      try {
        await _syncCompleter!.future.timeout(const Duration(milliseconds: 500));
        debugPrint("LEDFxWorker: State synchronized successfully.");
        break;
      } on TimeoutException {
        syncAttempts++;
        debugPrint("LEDFxWorker: Synchronization timed out, retrying requestState...");
        requestState();
      }
    }

    if (!_syncCompleter!.isCompleted) {
      debugPrint("LEDFxWorker: WARNING - Failed to synchronize state within 5 seconds.");
      // dispose instance initiation
      dispose();
      return false;
    } else {
      // Listen to local AudioBridge events for devices and state
      await _audioSubscription?.cancel();
      _audioSubscription = AudioBridge.instance.events.listen((event) {
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
      return true;
    }
  }

  void send(Map<String, dynamic> message) {
    final bgPort = IsolateNameServer.lookupPortByName("ledfx_bg_port");
    if (bgPort != null) {
      debugPrint("LEDFxWorker: Sending command: ${message["cmd"]}");
      bgPort.send(message);
    } else {
      debugPrint("LEDFxWorker: Cannot send command, background port is null.");
    }
  }

  void _handleBackgroundMessage(Map<String, dynamic> message) {
    final event = message["event"];
    if (event != "visualizer_update") {
      debugPrint("LEDFxWorker: Received background event: $event");
    }

    switch (event) {
      case "state_update":
        debugPrint("State update: ${message["state"]}");
        final state = message["state"] as Map<String, dynamic>;
        if (state.containsKey("devices")) {
          devices.value = List<Map<String, dynamic>>.from(state["devices"]);
        }
        if (state.containsKey("virtuals")) {
          virtuals.value = List<Map<String, dynamic>>.from(state["virtuals"]);
        }
        // Mark synchronization as complete
        if (_syncCompleter != null && !_syncCompleter!.isCompleted) {
          _syncCompleter!.complete();
        }
        break;
      case "visualizer_update":
        final deviceID = message["deviceID"];
        final data = message["data"];
        if (deviceID != null && data is List<int>) {
          final now = DateTime.now();
          final last = _lastVizUpdate[deviceID] ?? DateTime.fromMillisecondsSinceEpoch(0);
          if (now.difference(last) >= _throttleDuration) {
            _lastVizUpdate[deviceID] = now;
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
    _lastVizUpdate.remove(deviceId);
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

  void updateVirtualConfig(String virtualId, VirtualConfig config) {
    send({"cmd": "update_virtual_config", "virtualId": virtualId, "config": config.toJson()});
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
    debugPrint("LEDFxWorker: Disposing...");
    _uiPortSubscription?.cancel();
    _audioSubscription?.cancel();
    IsolateNameServer.removePortNameMapping("ledfx_ui_port");
    _uiReceivePort?.close();
    for (final notifier in _deviceRgbNotifiers.values) {
      notifier.dispose();
    }
    _deviceRgbNotifiers.clear();
    _lastVizUpdate.clear();
  }
}
