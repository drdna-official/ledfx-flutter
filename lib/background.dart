import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:ledfx/src/core.dart';
import 'package:ledfx/platform_interface/audio_bridge.dart';
import 'package:ledfx/src/storage/storage.dart';
import 'package:ledfx/src/virtual.dart';

@pragma('vm:entry-point')
void backgroundAudioProcessing() async {
  debugPrint("=================================================");
  debugPrint("BACKGROUND ISOLATE STARTING (Windows/Android)");
  debugPrint("=================================================");
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  // Setup receiving port for UI commands IMMEDIATELY so the UI doesn't hang
  final ReceivePort bgReceivePort = ReceivePort();
  IsolateNameServer.removePortNameMapping("ledfx_bg_port");
  IsolateNameServer.registerPortWithName(bgReceivePort.sendPort, "ledfx_bg_port");

  try {
    // Storage initialization
    final storage = SharedPreferencesStorage();
    await storage.init();

    // Create LEDFx instance
    final ledfx = LEDFx(config: LEDFxConfig(), storage: storage);
    await ledfx.start();
    ledfx.config.addListener(() {
      _sendStateToUI(ledfx);
    });

    // In the background isolate, AudioBridge will receive audio events from the Native ForegroundService
    // because the native service uses the background FlutterEngine's binaryMessenger to send those events.
    ledfx.audio?.activate(); // Subscribe to the background isolate's audio stream stream

    bgReceivePort.listen((message) async {
      if (message is Map<String, dynamic>) {
        final cmd = message["cmd"];
        switch (cmd) {
          case "request_state":
            _sendStateToUI(ledfx);
            break;
          case "add_device":
            try {
              final payload = message["payload"];
              await ledfx.addDevice(payload["type"], payload["name"], payload["address"]);
              _sendInfoToUI("Device added successfully");
            } catch (e) {
              _sendInfoToUI("Failed to add device: ${e.toString()}");
            }
            break;
          case "remove_device":
            try {
              final deviceId = message["deviceId"];
              await ledfx.removeDevice(deviceId);
            } catch (e) {
              debugPrint("Failed to remove device: ${e.toString()}");
            }
            break;
          case "add_virtual":
            try {
              final name = message["name"];
              await ledfx.addVirtual(name);
            } catch (e) {
              debugPrint("Failed to add virtual: ${e.toString()}");
            }
            break;
          case "remove_virtual":
            try {
              final vId = message["virtualId"];
              await ledfx.removeVirtual(vId);
            } catch (e) {
              debugPrint("Failed to remove virtual: ${e.toString()}");
            }
            break;
          case "set_virtual_active":
            try {
              final vId = message["virtualId"];
              final bool active = message["active"];
              await ledfx.toggleVirtual(vId, active);
            } catch (e) {
              debugPrint("Failed: ${e.toString()}");
            }
            break;
          case "update_virtual_segments":
            try {
              final vId = message["virtualId"];
              final segments = message["segments"] as List<Map<String, dynamic>>;
              await ledfx.updateVirtualSegments(vId, segments.map((e) => SegmentConfig.fromJson(e)).toList());
            } catch (e) {
              debugPrint("Failed: ${e.toString()}");
            }
            break;
          case "set_virtual_effect":
            try {
              final vId = message["virtualId"];
              final configMap = message["config"] as Map<String, dynamic>;
              await ledfx.setVirtualEffect(vId, configMap);
            } catch (e) {
              debugPrint("Failed: ${e.toString()}");
            }
            break;
          case "get_audio_devices":
            AudioBridge.instance.getDevices();
            break;
          case "start_audio_capture":
            break;
          case "stop_audio_capture":
            break;
        }
      }
    });

    AudioBridge.instance.events.listen((event) {
      if (event is StateEvent) {
        debugPrint("Background Worker: ${event.value}");
        final uiPort = IsolateNameServer.lookupPortByName("ledfx_ui_port");
        uiPort?.send({"event": "audio_state", "isCapturing": event.value == "recording_started"});
      }
    });
  } catch (e, stacktrace) {
    debugPrint("BACKGROUND ERROR: $e");
    debugPrint("$stacktrace");
  }
}

void _sendStateToUI(LEDFx ledfx) {
  final uiPort = IsolateNameServer.lookupPortByName("ledfx_ui_port");
  if (uiPort != null) {
    final state = {
      "event": "state_update",
      "state": {
        "devices": ledfx.config.devices,
        "virtuals": ledfx.virtuals.map((e) {
          return {
            "id": e.key,
            "config": e.value.config.toJson(),
            "active": e.value.active,
            "activeEffect": e.value.activeEffect?.config.toJson(),
            "segments": e.value.segments.map((s) => s.toJson()).toList(),
          };
        }).toList(),
      },
    };

    uiPort.send(state);
  }
}

void _sendInfoToUI(String message) {
  final uiPort = IsolateNameServer.lookupPortByName("ledfx_ui_port");
  if (uiPort != null) {
    uiPort.send({
      "event": "info",
      "info": {"message": message},
    });
  }
}
