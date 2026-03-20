import 'package:flutter/foundation.dart';
import 'package:ledfx/src/devices/device.dart';
import 'package:ledfx/src/effects/audio_reactive/audio.dart';
import 'package:ledfx/src/effects/effect.dart';
import 'package:ledfx/src/effects/audio_reactive/melbank.dart';
import 'package:ledfx/src/events.dart';
import 'package:ledfx/src/virtual.dart';
import 'package:ledfx/src/storage/storage.dart';

enum Transmission { base64Compressed, uncompressed }

class LEDFxConfig {
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
    this.flushOnDeactivate = false,
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
}

class LEDFx {
  final LEDFxConfig config;
  final Storage? storage;
  AudioAnalysisSource? audio;
  late LEDFxEvents events;
  late Devices devices;
  late Virtuals virtuals;
  late Effects effects;

  late VoidCallback virtualListener;
  late VoidCallback deviceListener;
  late void Function(LEDFxEvent) visualisationUpdateListener;

  LEDFx({required this.config, this.storage}) {
    events = LEDFxEvents(this);
    // setupVisualisationEvents();
    events.addListener(handleBaseConfigUpdate, LEDFxEvent.BASE_CONFIG_UPDATE);
  }
  void handleBaseConfigUpdate(LEDFxEvent event) {
    // Handle specific updates -- setup visualisation events fresh
    // setupVisualisationEvents();
  }

  // setupVisualisationEvents() async {
  //   final minTimeSince = 1 / config.visualizationFPS * 1000_000;
  //   final timeSinceLast = {};
  //   final maxLen = config.visualisationMaxLen;

  //   void handleVisualisationUpdate(LEDFxEvent event) {
  //     final isDevice = event.eventType == LEDFxEvent.DEVICE_UPDATE;
  //     final timeNow = DateTime.now();
  //     final visID = isDevice ? (event as DeviceUpdateEvent).deviceID : (event as VirtualUpdateEvent).virtualID;
  //     if (timeSinceLast[visID] == null) {
  //       timeSinceLast[visID] == timeNow.microsecond;
  //       return;
  //     }
  //     final timeSince = timeNow.microsecond - timeSinceLast[visID];
  //     if (timeSince < minTimeSince) return;
  //     timeSinceLast[visID] == timeNow.microsecond;

  //     //TODO: implement virtuals
  //     final rows = 1;

  //     List<Uint8List> pixels = isDevice ? (event as DeviceUpdateEvent).pixels : (event as VirtualUpdateEvent).pixels;
  //     final pixelsLen = pixels.length;
  //     List<int> shape = [rows, (pixelsLen / rows).toInt()];

  //     if (pixelsLen > maxLen) {}

  //     if (config.transmissionMode == Transmission.base64Compressed) {
  //     } else {
  //       if (pixels.isEmpty || pixels[0].isEmpty) {
  //         return;
  //       }

  //       final List<int> pixelsShape = NdArray.fromList(pixels).shape;

  //       List<List<double>> transposedAndCasted = List.generate(
  //         pixelsShape[1],
  //         (j) => List<double>.filled(pixelsShape[0], 0),
  //       );

  //       for (int i = 0; i < pixelsShape[0]; i++) {
  //         for (int j = 0; j < pixelsShape[1]; j++) {
  //           // Get the value, ensure it's clamped and converted to 0-255 integer (uint8)
  //           int val = pixels[i][j];

  //           // Clamp values between 0 and 255 and cast to int
  //           // int uint8Value = val.clamp(0.0, 255.0).round().toInt();
  //           int uint8Value = val.clamp(0, 255);

  //           // Place into the transposed position
  //           transposedAndCasted[j][i] = uint8Value;
  //         }
  //       }
  //       pixels = List.generate(transposedAndCasted.length, (i) => Float64List.fromList(transposedAndCasted[i]));
  //     }

  //     events.fireEvent(VisualisationUpdateEvent(visID, pixels, shape, isDevice));
  //   }

  //   visualisationUpdateListener = handleVisualisationUpdate;
  //   deviceListener = await events.addListener(visualisationUpdateListener, LEDFxEvent.DEVICE_UPDATE);
  //   virtualListener = await events.addListener(visualisationUpdateListener, LEDFxEvent.VIRTUAL_UPDATE);
  // }

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

    debugPrint(events.toString());
  }

  Future<void> stop([int exitCode = 0]) async {
    debugPrint("stopping ...");
    events.fireEvent(LEDFxShutdownEvent());
    // TODO: Save Config before shutdown
  }

  // -- Devices --

  Future<void> addDevice(String type, String name, String address) async {
    devices.addNewDevice(type, name, address);

    storage?.saveDevices(config.devices);
    storage?.saveVirtuals(config.virtuals);
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
    await storage?.saveDevices(config.devices);
  }

  // -- Virtuals --
  // Update This Virtual's Segments
  Future<void> updateVirtual(String virtualID, List<SegmentConfig> segments) async {
    final virtual = virtuals.get(virtualID);
    if (virtual == null) {
      debugPrint("Virtual not found: $virtualID");
      return;
    }
    virtual.updateSegments(segments);
    await storage?.saveVirtuals(config.virtuals);
  }

  // Activate-Deactivate Virtual
  Future<void> toggleVirtual(String virtualID, bool active) async {
    final virtual = virtuals.get(virtualID);
    if (virtual == null) {
      debugPrint("Virtual not found: $virtualID");
      return;
    }
    virtual.active = active;
    virtual.virtualData["active"] = virtual.active;
    await storage?.saveVirtuals(config.virtuals);
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

    virtuals.destroyVirtual(virtualID);
    config.virtuals.removeWhere((v) => v["id"] == virtualID);
    await storage?.saveVirtuals(config.virtuals);
  }
}
