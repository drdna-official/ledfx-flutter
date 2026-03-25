import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:ledfx/src/devices/device.dart';
import 'package:ledfx/src/audio/audio.dart';
import 'package:ledfx/src/effects/effect.dart';
import 'package:ledfx/src/audio/melbank.dart';
import 'package:ledfx/src/virtual.dart';
import 'package:ledfx/src/storage/storage.dart';

enum Transmission { base64Compressed, uncompressed }

class LEDFxConfig extends ChangeNotifier {
  List<Map<String, dynamic>>? melbankCollection;
  MelbankConfig? melbankConfig;

  final int visualizationFPS;
  final int visualisationMaxLen;
  final Transmission transmissionMode;
  final bool flushOnDeactivate;

  List<Map<String, dynamic>> devices = [];
  List<Map<String, dynamic>> virtuals = [];

  LEDFxConfig({
    this.visualizationFPS = 24,
    this.visualisationMaxLen = 1,
    this.transmissionMode = Transmission.uncompressed,
    this.flushOnDeactivate = true,
  });

  Future<void> loadFromStorage(Storage storage) async {
    await storage.init();
    final loadedDevices = await storage.loadDevices();
    if (loadedDevices != null && loadedDevices.isNotEmpty) {
      devices = loadedDevices;
    }
    final loadedVirtuals = await storage.loadVirtuals();
    if (loadedVirtuals != null && loadedVirtuals.isNotEmpty) {
      virtuals = loadedVirtuals;
    }
  }

  notify() {
    super.notifyListeners();
  }
}

class LEDFx {
  final LEDFxConfig config;
  final Storage? storage;
  AudioAnalysisSource? audioSource;
  late Devices devices;
  late Virtuals virtuals;
  late Effects effects;

  late VoidCallback virtualListener;
  late VoidCallback deviceListener;

  LEDFx({required this.config, this.storage});

  Future<void> start([bool pauseAll = false]) async {
    debugPrint("starting LEDFx");

    devices = Devices(ledfx: this);
    effects = Effects(ledfx: this);
    virtuals = Virtuals(ledfx: this);

    if (storage != null) await config.loadFromStorage(storage!);

    // Ensure to start with fresh virtual registry when
    // Reusing virtuals singleton across core lifecycle
    virtuals.resetForCore(this);

    // Initialize Devices
    devices.createFromConfig(config.devices);
    await devices.initialiseDevices();

    // Initialize Virtuals
    virtuals.createFromConfig(config.virtuals, pauseAll);

    if (pauseAll) virtuals.pauseAll();

    updateCoreConfig();
  }

  Future<void> stop([int exitCode = 0]) async {
    debugPrint("stopping ...");
    await saveConfig();
  }

  // Needs to be called from functions that is called from core
  // like the functions defined below
  void updateCoreConfig() {
    config.devices = devices.map((e) => {"id": e.key, "config": e.value.config.toJson()}).toList();
    config.virtuals = virtuals
        .map(
          (e) => {
            "id": e.key,
            "config": e.value.config.toJson(),
            "active": e.value.isActive,
            "activeEffect": e.value.activeEffect?.config.toJson(),
            "segments": e.value.segments.map((s) => s.toJson()).toList(),
          },
        )
        .toList();
    config.notify();
  }

  Future<void> saveConfig() async {
    await storage?.saveDevices(config.devices);
    await storage?.saveVirtuals(config.virtuals);
  }

  void sendAudioDataToUI(String deviceID, List<Uint8List> pixelData) {
    final uiPort = IsolateNameServer.lookupPortByName("ledfx_ui_port");
    if (uiPort != null) {
      final builder = BytesBuilder(copy: false);
      for (final d in pixelData) {
        builder.add(d);
      }
      uiPort.send({"event": "visualizer_update", "deviceID": deviceID, "data": builder.toBytes()});
    }
  }

  // -- Devices --
  // Add New Device
  Future<void> addDevice(String type, String name, String address) async {
    try {
      await devices.addNewDevice(type, name, address);
      await saveConfig();
    } catch (e) {
      rethrow;
    }
  }

  // Remove Device
  Future<void> removeDevice(String deviceID) async {
    final device = devices.get(deviceID);
    if (device == null) {
      debugPrint("Device not found: $deviceID");
      return;
    }
    device.deactivate();
    devices.destroyDevice(deviceID);
    config.devices.removeWhere((v) => v["id"] == deviceID);

    final virtualsToRemove = virtuals.virtuals.entries
        .where((e) => e.value.deviceID == deviceID)
        .map((e) => e.key)
        .toList();
    for (var vId in virtualsToRemove) {
      await removeVirtual(vId);
    }

    updateCoreConfig();
    await saveConfig();
  }

  // -- Virtuals --
  // Create a Virtual Strip
  Future<void> addVirtual(String name) async {
    try {
      await virtuals.addNewVirtual(name);
      updateCoreConfig();
      await saveConfig();
    } catch (e) {
      debugPrint("Failed to Create Virtual Strip: $e");
      rethrow;
    }
  }

  Future<void> updateVirtualConfig(String virtualID, VirtualConfig config) async {
    final virtual = virtuals.get(virtualID);
    if (virtual == null) {
      debugPrint("Virtual not found: $virtualID");
      return;
    }
    try {
      virtual.updateConfig(config);
      updateCoreConfig();
      await saveConfig();
    } catch (e) {
      debugPrint("Failed to Create Virtual Strip: $e");
      rethrow;
    }
  }

  // Update This Virtual's Segments
  Future<void> updateVirtualSegments(String virtualID, List<SegmentConfig> segments) async {
    final virtual = virtuals.get(virtualID);
    if (virtual == null) {
      debugPrint("Virtual not found: $virtualID");
      return;
    }
    virtual.updateSegments(segments);
    updateCoreConfig();
    await saveConfig();
  }

  // Activate-Deactivate Virtual
  Future<void> toggleVirtual(String virtualID, bool active) async {
    final virtual = virtuals.get(virtualID);
    if (virtual == null) {
      debugPrint("Virtual not found: $virtualID");
      return;
    }
    virtual.isActive = active;
    updateCoreConfig();
    await saveConfig();
  }

  // Remove Virtual
  Future<void> removeVirtual(String virtualID) async {
    final virtual = virtuals.get(virtualID);
    if (virtual == null) {
      debugPrint("Virtual not found: $virtualID");
      return;
    }
    virtual.clearEffect();
    final deviceID = virtual.deviceID;
    final device = devices.get(deviceID);
    if (device != null) {
      await device.removeFromVirtual(virtualID);
      devices.destroyDevice(deviceID);
      config.devices.removeWhere((v) => v["id"] == deviceID);
    }

    virtuals.removeVirtual(virtualID);
    config.virtuals.removeWhere((v) => v["id"] == virtualID);
    updateCoreConfig();
    await saveConfig();
  }

  // Set Effect
  Future<void> setVirtualEffect(String virtualID, Map<String, dynamic> effectConfig) async {
    final virtual = virtuals.get(virtualID);
    if (virtual == null) {
      debugPrint("Virtual not found: $virtualID");
      return;
    }
    virtual.setEffect(effectConfig);
    updateCoreConfig();
    await saveConfig();
  }
}
