import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:ledfx/src/core.dart';
import 'package:ledfx/src/devices/dummy.dart';
import 'package:ledfx/src/devices/wled.dart';
import 'package:ledfx/src/virtual.dart';
import 'package:ledfx/utils/utils.dart';
import 'package:nanoid/nanoid.dart';

class DeviceConfig {
  String? address;
  String name;
  String type;
  int pixelCount;
  bool rgbwLED;
  WLEDSyncMode? syncMode;
  int? rows;

  DeviceConfig({
    required this.pixelCount,
    required this.rgbwLED,
    required this.name,
    required this.type,
    this.syncMode,
    this.address,
    this.rows,
  });

  Map<String, dynamic> toJson() {
    return {
      'pixelCount': pixelCount,
      'rgbwLED': rgbwLED,
      'name': name,
      'type': type,
      'syncMode': syncMode?.name,
      'address': address,
      'rows': rows,
    };
  }

  factory DeviceConfig.fromJson(Map<String, dynamic> json) {
    return DeviceConfig(
      pixelCount: json['pixelCount'],
      rgbwLED: json['rgbwLED'],
      name: json['name'],
      type: json['type'],
      syncMode: json['syncMode'] != null ? WLEDSyncMode.values.firstWhere((e) => e.name == json['syncMode']) : null,
      address: json['address'],
      rows: json['rows'],
    );
  }
}

class Devices extends Iterable<MapEntry<String, Device>> {
  final LEDFx ledfx;

  Map<String, Device> devices = {};
  @override
  Iterator<MapEntry<String, Device>> get iterator => devices.entries.iterator;

  Devices({required this.ledfx});

  deactivateDevices() {
    devices.forEach((_, v) {
      v.deactivate();
    });
  }

  Device? get(String id) => devices[id];

  void createFromConfig(List<Map<String, dynamic>> config) {
    if (config.isEmpty) return;

    for (final deviceData in config) {
      final deviceId = deviceData['id'];
      final configMap = deviceData['config'] as Map<String, dynamic>;
      final deviceConfig = DeviceConfig.fromJson(configMap);

      create(deviceId, deviceConfig, ledfx);
    }
  }

  Future<void> initialiseDevices() async {
    List<Future<void>> asyncDevices = [];
    devices.forEach((k, v) {
      if (v is AsyncInitDevice) {
        asyncDevices.add((v as AsyncInitDevice).initialize());
      }
    });

    try {
      await Future.wait(asyncDevices);
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Device create(String id, DeviceConfig config, LEDFx ledfx) {
    Device d;
    switch (config.type) {
      case "wled":
        d = WLEDDevice(ipAddr: config.address!, syncMode: config.syncMode!, id: id, ledfx: ledfx, config: config);
      case "dummy":
        d = DummyDevice(id: id, ledfx: ledfx, config: config);
      default:
        d = WLEDDevice(ipAddr: config.address!, syncMode: config.syncMode!, id: id, ledfx: ledfx, config: config);
    }

    devices[id] = d;
    return d;
  }

  //Creates New Device
  Future<Device?> addNewDevice(String type, String name, String address) async {
    String resolvedDestination = "";
    final String deviceType = type;
    if (address != "" && deviceType != "dummy") {
      final ipAddr = cleanIPaddress(address);
      try {
        resolvedDestination = await resolveDestination(ipAddr, checkConnection: true, port: 80);
        if (resolvedDestination == "") throw Exception("could not be resolved");
      } catch (e) {
        throw Exception("device could not be resolved -- $ipAddr, skipping device");
      }

      if (resolvedDestination.isNotEmpty) {
        ledfx.devices.devices.forEach((k, v) {
          if ((v is NetworkedDevice) && (v.ipAddr == ipAddr || v.ipAddr == resolvedDestination)) {
            runDeviceIPtests(deviceType, ipAddr, v);
          }
        });
      }
    }

    String wledName = "";
    DeviceConfig? config;
    WLEDConfig? wledConfig;
    if (deviceType == "wled") {
      final wled = WLED(ipAddr: resolvedDestination);
      wledConfig = await wled.getConfig();
      if (wledConfig == null) {
        throw Exception("could not fetch config of wled device");
      }
      if (name.isNotEmpty) {
        wledName = name;
      } else if (wledConfig.name == "WLED") {
        wledName = "${wledConfig.name} - ${wledConfig.mac}".toUpperCase();
      } else {
        wledName = wledConfig.name;
      }
      WLEDSyncMode syncMode = WLEDSyncMode.udp;
      if (WLED.wledDDPsupport(wledConfig.build)) {
        syncMode = WLEDSyncMode.ddp;
      }

      config = DeviceConfig(
        type: deviceType,
        name: wledName,
        pixelCount: wledConfig.ledCount,
        rgbwLED: wledConfig.rgbwLED,
        syncMode: syncMode,
        address: resolvedDestination,
        rows: (wledConfig.rows == null) ? 1 : int.tryParse(wledConfig.rows!) ?? 1,
      );
    } else {
      config = DeviceConfig(
        type: deviceType,
        name: name,
        pixelCount: 300,
        rgbwLED: false,
        syncMode: null,
        address: resolvedDestination,
        rows: 1,
      );
    }

    final deviceID = nanoid(10);
    final device = ledfx.devices.create(deviceID, config, ledfx);
    if (device is AsyncInitDevice) {
      await (device as AsyncInitDevice).initialize();
    }
    config = device.config;
    if (deviceType == "wled") {
      config.name = wledName;
    }
    // Update Core Config - Device
    ledfx.updateCoreConfig();

    // Auto Generate Virtual for the Device and attach
    final virtualID = nanoid(10);
    int virtualConfigRows = 1;
    if (deviceType == "wled" && wledConfig != null && wledConfig.rows != null) {
      virtualConfigRows = int.tryParse(wledConfig.rows!) ?? 1;
    }
    final segments = [SegmentConfig(device.id, 0, config.pixelCount - 1, false)];

    final virtualConfig = VirtualConfig(
      name: "[virtual] ${device.name}",
      deviceID: deviceID,
      rows: virtualConfigRows,
      autoGenerated: true,
    );
    final virtual = ledfx.virtuals.create(virtualID, virtualConfig);
    virtual.updateSegments(segments);

    // Update Core Config - Virtual
    ledfx.updateCoreConfig();

    await device.postamble();

    return device;
  }

  void runDeviceIPtests(String deviceType, String ipAddr, Device v) {}

  void destroyDevice(String id) {
    if (!devices.keys.contains(id)) return;
    devices[id]!.del();
    devices.remove(id);
  }
}

abstract interface class AsyncInitDevice {
  Future<void> initialize();
}

abstract class Device {
  final String id;
  final LEDFx ledfx;
  final DeviceConfig config;
  String get name => config.name;
  int get pixelCount => config.pixelCount;
  String get type => config.type;

  final int centerOffset;
  late int _refreshRate;
  int get maxRefreshRate => _refreshRate;
  int get refreshRate => () {
    if (priorityVirtual != null) {
      return priorityVirtual!.refreshRate;
    } else {
      return 30;
    }
  }();
  Device({required this.id, required this.ledfx, required this.config, int? refreshRate, this.centerOffset = 0}) {
    _refreshRate = refreshRate ?? 60;
  }

  bool _isActive = false;
  bool get isActive => _isActive;

  bool _online = true;
  bool get isOnline => _online;

  List<Uint8List>? _devicePixels;

  List<Virtual>? _cachedVirtualsObjs;
  List<Virtual> get _virtualObjs => () {
    if (_cachedVirtualsObjs != null) return _cachedVirtualsObjs!;
    final vs = <Virtual>[];
    for (var id in virtuals) {
      if (ledfx.virtuals.virtuals.containsKey(id)) {
        vs.add(ledfx.virtuals.virtuals[id]!);
      }
    }
    _cachedVirtualsObjs = vs;
    return _cachedVirtualsObjs!;
  }();
  List<String> get activeVirtuals => _virtualObjs.where((v) => v.isActive).map((v) => v.id).toList();
  List<String>? _cachedVirtuals;
  List<String> get virtuals => () {
    if (_cachedVirtuals != null) return _cachedVirtuals!;
    _cachedVirtuals = _segments.map((s) => s.deviceID).toList();
    return _cachedVirtuals!;
  }();

  List<SegmentConfig> _segments = [];

  void activate() {
    _devicePixels = List.filled(pixelCount, Uint8List(3));
    _isActive = true;
  }

  void del() {
    if (isActive) deactivate();
  }

  void deactivate() {
    _devicePixels = null;
    _isActive = false;
  }

  void invalidateCache() {
    _cachedPriorityVirtual = null;
    _cachedVirtualsObjs = null;
    _cachedVirtuals = null;
  }

  void setOffline() {
    deactivate();
    _online = false;
    ledfx.updateCoreConfig();
  }

  ///Flushes the provided data to the device. This abstract method must be
  ///overwritten by the device implementation.
  void flush(List<Uint8List> pixelData) {
    return;
  }

  void configUpdated({
    required String id,
    required String name,
    required LEDFx ledfx,
    int? refreshRate,
    int centerOffset = 0,
    required int pixelCount,
  }) {
    return;
  }

  updateConfig({
    required String id,
    required String name,
    required LEDFx ledfx,
    int? refreshRate,
    int centerOffset = 0,
    required int pixelCount,
  }) {
    configUpdated(
      id: id,
      name: name,
      ledfx: ledfx,
      refreshRate: refreshRate,
      centerOffset: centerOffset,
      pixelCount: pixelCount,
    );

    for (var e in ledfx.virtuals) {
      if (e.value.deviceID == id) {
        final segments = [SegmentConfig(id, 0, pixelCount - 1, false)];
        e.value.updateSegments(segments);
        e.value.invalidateCache();
      }
    }

    for (var v in _virtualObjs) {
      v.deactivateSegments();
      v.activateSegments(v.segments);
    }
  }

  Future<void> postamble() async {
    return;
  }

  /// Updates the pixels of the device from Virtual data by segments.
  ///
  /// [virtualID] The ID of the virtual that is sending the data
  /// [data] A list of tuples containing the pixels, start index, and end index
  /// each Uint8List is a pixel with 3 bytes (R, G, B)
  void updatePixels(String virtualID, List<(List<Uint8List>, int, int)> data) {
    if (_isActive == false) {
      debugPrint("Can't update inactive device: $name");
      return;
    }

    for (final (pixels, start, end) in data) {
      if (pixels.isNotEmpty && _devicePixels != null && _devicePixels!.isNotEmpty) {
        if (pixels[0].length == 3 ||
            ((pixels.length < end && _devicePixels!.length < end) &&
                pixels[start].length == _devicePixels![start].length)) {
          for (int i = start; i < end + 1; i++) {
            _devicePixels![i] = pixels[i - start];
          }
        }
      }

      // final ndArr = NdArray.fromList(pixels);
      // if (ndArr.shape.isNotEmpty && ndArr.shape[0] != 0) {

      //   if (ndArr.shape.first == 3 ||
      //       (_pixels != null &&
      //           NdArray.fromList(_pixels!).shape == ndArr.shape)) {
      //     _pixels = pixels;
      //   }
      // }
    }

    if (priorityVirtual != null) {
      if (virtualID == priorityVirtual!.id) {
        final frame = assembleFrame();
        if (frame == null) return;
        flush(frame);
        // Send Device Rendered Frame to UI for Visualisation
        ledfx.sendAudioDataToUI(id, frame);
      }
    }
  }

  List<Uint8List>? assembleFrame() {
    if (_devicePixels == null) return null;
    List<Uint8List> frame = _devicePixels!;
    if (centerOffset > 0) frame.roll(centerOffset);
    return frame;
  }

  // Returns the first virtual that has the highest refresh rate of all virtuals
  // associated with this device
  Virtual? _cachedPriorityVirtual;
  Virtual? get priorityVirtual {
    if (_cachedPriorityVirtual != null) return _cachedPriorityVirtual;

    if (!_virtualObjs.any((v) => v.isActive)) return null;

    final refreshRate = _virtualObjs.where((v) => v.isActive).map((v) => v.refreshRate).reduce(max);

    final Virtual priority = _virtualObjs.firstWhere((virtual) => virtual.refreshRate == refreshRate);

    _cachedPriorityVirtual = priority;
    return _cachedPriorityVirtual;
  }

  void addSegment(SegmentConfig config, [bool force = false]) {
    for (var i in _segments) {
      if (i.deviceID == config.deviceID) continue;

      final overlap = (min(i.end, config.end) - max(i.start, config.start) + 1);

      if (overlap > 0) {
        final virtualName = ledfx.virtuals.virtuals[config.deviceID]?.name;
        final blockingVirtual = ledfx.virtuals.virtuals[i.deviceID];

        if (virtualName == null || blockingVirtual == null) {
          throw Exception("no device found");
        }

        if (force) {
          blockingVirtual.deactivate();
        } else {
          throw Exception(
            "failed to activate effect!. $virtualName overlaps with active virtual ${blockingVirtual.name}",
          );
        }
      }
    }

    // if the segment is from a new device, we need to recheck our priority virtual
    if (!_segments.any((seg) => seg.deviceID == config.deviceID)) {
      invalidateCache();
    }
    _segments.add(config);
    invalidateCache();
  }

  void clearVirtualSegments(String id) {
    final newSegments = <SegmentConfig>[];
    for (var segment in _segments) {
      if (segment.deviceID != id) {
        newSegments.add(segment);
      } else {
        if (_devicePixels != null && ledfx.config.flushOnDeactivate) {
          for (int i = segment.start; i <= segment.end; i++) {
            final Uint8List zeroRow = Uint8List(3);
            _devicePixels![i] = zeroRow;
          }
        }
      }
    }
    _segments = newSegments;
    if (priorityVirtual != null && priorityVirtual!.id == id) {
      invalidateCache();
    }
  }

  void clearSegments() {
    _segments = [];
    invalidateCache();
  }

  Future<void> removeFromVirtual(String virtualID) async {
    for (var v in ledfx.virtuals.virtuals.values) {
      if (!v.segments.any((seg) => seg.deviceID == id)) continue;
      final active = v.isActive;
      if (active) v.deactivate();
      v.segments.removeWhere((seg) => seg.deviceID == id);

      // if virtual is autogenerated, remove it
      if (v.segments.isEmpty && v.autoGenerated) {
        v.clearEffect();
        continue;
      }

      if (active) v.activate();
    }
  }
}

abstract class NetworkedDevice extends Device implements AsyncInitDevice {
  NetworkedDevice({
    super.refreshRate,
    required String ipAddr,
    required super.id,
    required super.ledfx,
    required super.config,
  }) {
    config.address = ipAddr;
  }

  String get ipAddr => config.address!;

  String? _destination;
  String? get destination => () {
    if (_destination == null) {
      resolveAddress();
      return null;
    } else {
      return _destination!;
    }
  }();
  set destination(String? dest) => _destination = dest;

  @override
  Future<void> initialize() async {
    _destination = null;
    await resolveAddress();
  }

  @override
  void activate() {
    if (_destination == null) {
      debugPrint("Error: Not Online");
      resolveAddress().then((_) {
        activate();
      });
    } else {
      _online = true;
      super.activate();
    }
  }

  Future<void> resolveAddress([VoidCallback? callback]) async {
    try {
      _destination = await resolveDestination(ipAddr);
      _online = true;
      if (callback != null) callback();
    } catch (e) {
      _online = false;
      debugPrint(e.toString());
    }
  }
}
