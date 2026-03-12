import 'package:flutter/foundation.dart';
import 'package:ledfx/src/devices/device.dart';
import 'package:ledfx/src/effects/audio.dart';
import 'package:ledfx/src/effects/effect.dart';
import 'package:ledfx/src/effects/wavelength.dart';
import 'package:ledfx/src/effects/melbank.dart';
import 'package:ledfx/src/events.dart';
import 'package:ledfx/src/virtual.dart';
import 'package:ledfx/src/storage/storage.dart';
import 'package:n_dimensional_array/domain/models/nd_array.dart';

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
    setupVisualisationEvents();
  }

  setupVisualisationEvents() async {
    final minTimeSince = 1 / config.visualizationFPS * 1000_000;
    final timeSinceLast = {};
    final maxLen = config.visualisationMaxLen;

    void handleVisualisationUpdate(LEDFxEvent event) {
      final isDevice = event.eventType == LEDFxEvent.DEVICE_UPDATE;
      final timeNow = DateTime.now();
      final visID = isDevice ? (event as DeviceUpdateEvent).deviceID : (event as VirtualUpdateEvent).virtualID;
      if (timeSinceLast[visID] == null) {
        timeSinceLast[visID] == timeNow.microsecond;
        return;
      }
      final timeSince = timeNow.microsecond - timeSinceLast[visID];
      if (timeSince < minTimeSince) return;
      timeSinceLast[visID] == timeNow.microsecond;

      //TODO: implement virtuals
      final rows = 1;

      List<Float64List> pixels = isDevice ? (event as DeviceUpdateEvent).pixels : (event as VirtualUpdateEvent).pixels;
      final pixelsLen = pixels.length;
      List<int> shape = [rows, (pixelsLen / rows).toInt()];

      if (pixelsLen > maxLen) {}

      if (config.transmissionMode == Transmission.base64Compressed) {
      } else {
        if (pixels.isEmpty || pixels[0].isEmpty) {
          return;
        }

        final List<int> pixelsShape = NdArray.fromList(pixels).shape;

        List<List<double>> transposedAndCasted = List.generate(
          pixelsShape[1],
          (j) => List<double>.filled(pixelsShape[0], 0),
        );

        for (int i = 0; i < pixelsShape[0]; i++) {
          for (int j = 0; j < pixelsShape[1]; j++) {
            // Get the value, ensure it's clamped and converted to 0-255 integer (uint8)
            double val = pixels[i][j];

            // Clamp values between 0 and 255 and cast to int
            // int uint8Value = val.clamp(0.0, 255.0).round().toInt();
            double uint8Value = val.clamp(0.0, 255.0);

            // Place into the transposed position
            transposedAndCasted[j][i] = uint8Value;
          }
        }
        pixels = List.generate(transposedAndCasted.length, (i) => Float64List.fromList(transposedAndCasted[i]));
      }

      events.fireEvent(VisualisationUpdateEvent(visID, pixels, shape, isDevice));
    }

    visualisationUpdateListener = handleVisualisationUpdate;
    deviceListener = await events.addListener(visualisationUpdateListener, LEDFxEvent.DEVICE_UPDATE);
    virtualListener = await events.addListener(visualisationUpdateListener, LEDFxEvent.VIRTUAL_UPDATE);
  }

  Future<void> start([bool pauseAll = false]) async {
    debugPrint("starting LEDFx");

    devices = Devices(ledfx: this);
    effects = Effects(ledfx: this);
    virtuals = Virtuals(ledfx: this);

    if (storage != null) {
      await storage!.init();
      final loadedDevices = await storage!.loadDevices();
      if (loadedDevices != null && loadedDevices.isNotEmpty) {
        config.devices = loadedDevices;
      }
      final loadedVirtuals = await storage!.loadVirtuals();
      if (loadedVirtuals != null && loadedVirtuals.isNotEmpty) {
        config.virtuals = loadedVirtuals;
      }
    }

    virtuals.resetForCore(this);

    // Initialize Devices
    if (config.devices.isNotEmpty) {
      for (final deviceData in config.devices) {
        final deviceId = deviceData['id'];
        final deviceType = deviceData['type'];
        final configMap = deviceData['config'] as Map<String, dynamic>;
        final deviceConfig = DeviceConfig.fromJson(configMap);

        final device = devices.create(deviceId, deviceType, deviceConfig, this);
        if (device is AsyncInitDevice) {
          await (device as AsyncInitDevice).initialize();
        }
        await device.postamble();
      }
    }

    // Initialize Virtuals
    if (config.virtuals.isNotEmpty) {
      for (final virtualData in config.virtuals) {
        final virtualId = virtualData['id'];
        final configMap = virtualData['config'] as Map<String, dynamic>;
        final virtualConfig = VirtualConfig.fromJson(configMap);
        final virtual = virtuals.create(virtualId, virtualConfig);

        final segmentsList = virtualData['segments'] as List<dynamic>;
        final segments = segmentsList.map((s) => SegmentConfig.fromJson(s as Map<String, dynamic>)).toList();
        virtual.updateSegments(segments);
        virtual.virtualConfig = virtualData;

        if (storage != null) {
          final effectData = await storage!.loadActiveEffect(virtualId);
          if (effectData != null) {
            final effectType = effectData['type'];
            final effectConfigMap = effectData['config'] as Map<String, dynamic>;
            final effectConfig = EffectConfig.fromJson(effectConfigMap);

            Effect? effect;
            if (effectType == 'WavelengthEffect') {
              effect = WavelengthEffect(ledfx: this, config: effectConfig);
            }
            // Add other effects here as they are implemented

            if (effect != null) {
              virtual.setEffect(effect);
              if (virtualData["active"] == false) {
                virtual.active = false;
              }
            }
          }
        }
      }
    }
    if (pauseAll) virtuals.pauseAll();
  }

  Future<void> stop([int exitCode = 0]) async {
    print("stopping ...");
    try {} catch (e) {
    } finally {}
  }
}
