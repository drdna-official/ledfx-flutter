import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:ledfx/src/core.dart';
import 'package:ledfx/src/devices/device.dart';
import 'package:ledfx/src/effects/effect.dart';
import 'package:ledfx/src/effects/wavelength.dart';
import 'package:ledfx/src/platform/audio_bridge.dart';
import 'package:ledfx/src/storage/storage.dart';

@pragma('vm:entry-point')
void backgroundAudioProcessing() async {
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
              final config = DeviceConfig.fromJson(message["payload"]);
              await ledfx.devices.addNewDevice(config);
            } catch (e) {
              debugPrint("Failed to add device: ${e.toString()}");
            } finally {
              _sendStateToUI(ledfx);
            }
            break;
          case "remove_device":
            try {
              final deviceId = message["deviceId"];
              final device = ledfx.devices.devices.remove(deviceId);
              if (device != null) {
                device.del();
                ledfx.config.devices.removeWhere((d) => d["id"] == deviceId);
                ledfx.storage?.saveDevices(ledfx.config.devices);
              }
              final virtualsToRemove = ledfx.virtuals.virtuals.entries
                  .where((e) => e.value.deviceID == deviceId)
                  .map((e) => e.key)
                  .toList();
              for (var vId in virtualsToRemove) {
                final v = ledfx.virtuals.virtuals.remove(vId);
                if (v != null) {
                  v.del();
                  ledfx.config.virtuals.removeWhere((vd) => vd["id"] == vId);
                }
              }
              if (virtualsToRemove.isNotEmpty) {
                ledfx.storage?.saveVirtuals(ledfx.config.virtuals);
              }
            } catch (e) {
              debugPrint("Failed to remove device: ${e.toString()}");
            } finally {
              _sendStateToUI(ledfx);
            }
            break;
          case "set_virtual_active":
            try {
              final vId = message["virtualId"];
              final bool active = message["active"];
              final virtual = ledfx.virtuals.virtuals[vId];
              if (virtual != null) {
                active ? virtual.activate() : virtual.deactivate();
                final configIndex = ledfx.config.virtuals.indexWhere((v) => v["id"] == vId);
                if (configIndex != -1) {
                  ledfx.config.virtuals[configIndex]["active"] = active;
                  ledfx.storage?.saveVirtuals(ledfx.config.virtuals);
                }
              }
            } catch (e) {
              debugPrint("Failed: ${e.toString()}");
            } finally {
              _sendStateToUI(ledfx);
            }
            break;
          case "set_effect":
            try {
              final vId = message["virtualId"];
              final eType = message["effectType"];
              final configMap = message["config"] as Map<String, dynamic>;
              final virtual = ledfx.virtuals.virtuals[vId];
              if (virtual != null) {
                if (eType == "WavelengthEffect") {
                  virtual.setEffect(WavelengthEffect(ledfx: ledfx, config: EffectConfig.fromJson(configMap)));
                  ledfx.storage?.saveActiveEffect(vId, {"type": eType, "config": configMap});
                }
              }
            } catch (e) {
              debugPrint("Failed: ${e.toString()}");
            } finally {
              _sendStateToUI(ledfx);
            }
            break;
          case "start_audio_capture":
            ledfx.audio?.startAudioCapture();
            break;
          case "stop_audio_capture":
            ledfx.audio?.stopAudioCapture();
            break;
        }
      }
    });

    AudioBridge.instance.events.listen((event) {
      if (event is StateEvent) {
        final uiPort = IsolateNameServer.lookupPortByName("ledfx_ui_port");
        uiPort?.send({"event": "audio_state", "isCapturing": event.state == "started"});
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
    uiPort.send({
      "event": "state_update",
      "state": {
        "devices": ledfx.config.devices,
        "virtuals": ledfx.virtuals.virtuals.values.map((v) {
          return {
            "id": v.id,
            "config": v.config.toJson(),
            "active": v.active,
            "activeEffect": v.activeEffect != null
                ? {"type": v.activeEffect.runtimeType.toString(), "name": v.activeEffect!.name}
                : null,
            "deviceID": v.deviceID,
            "segments": v.segments.map((s) => s.toJson()).toList(),
            "autoGenerated": v.autoGenerated,
          };
        }).toList(),
      },
    });
  }
}
