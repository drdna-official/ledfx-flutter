import 'package:flutter/foundation.dart';
import 'package:ledfx/src/devices/device.dart';
import 'package:ledfx/utils/utils.dart';
import 'dart:async';
import 'dart:developer' show log;
import 'dart:io';
import 'dart:isolate';

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
      online = true;
      super.activate();
    }
  }

  Future<void> resolveAddress([VoidCallback? callback]) async {
    try {
      _destination = await resolveDestination(ipAddr);
      online = true;
      if (callback != null) callback();
    } catch (e) {
      online = false;
      debugPrint(e.toString());
    }
  }
}

class UDPSender {
  static final UDPSender _instance = UDPSender._internal();
  factory UDPSender() => _instance;
  UDPSender._internal();

  SendPort? _sendPort;
  Isolate? _isolate;
  int _referenceCount = 0;
  bool _isInit = false;
  Completer<void>? _initCompleter;

  Future<void> activate() async {
    _referenceCount++;
    if (_isInit) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();
    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_udpSenderIsolate, receivePort.sendPort);
    _sendPort = await receivePort.first as SendPort;
    _isInit = true;
    _initCompleter!.complete();
    _initCompleter = null;
  }

  void deactivate() {
    _referenceCount--;
    if (_referenceCount <= 0) {
      if (_sendPort != null) {
        _sendPort!.send(null); // Signal termination
      }
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _sendPort = null;
      _isInit = false;
      _referenceCount = 0;
    }
  }

  void sendPacket(String address, int port, Uint8List data) {
    if (_sendPort == null) return;
    try {
      _sendPort!.send({
        'address': address,
        'port': port,
        'data': TransferableTypedData.fromList([data]),
      });
    } catch (e) {
      log("Error sending to UdpSender isolate: $e");
    }
  }
}

void _udpSenderIsolate(SendPort initPort) async {
  final isolateReceivePort = ReceivePort();
  initPort.send(isolateReceivePort.sendPort);

  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    // We only send, discard any incoming packets
    socket.listen((RawSocketEvent e) {
      if (e == RawSocketEvent.read) {
        socket?.receive(); // Discard
      }
    });

    await for (final message in isolateReceivePort) {
      if (message == null) {
        break;
      }
      final addressStr = message['address'] as String;
      final port = message['port'] as int;
      final TransferableTypedData transferData = message['data'] as TransferableTypedData;

      try {
        final address = InternetAddress(addressStr);
        final data = transferData.materialize().asUint8List();
        socket.send(data, address, port);
      } catch (e) {
        // Ignore resolution or send errors
      }
    }
  } catch (e) {
    // Ignore bind errors
  } finally {
    socket?.close();
    isolateReceivePort.close();
  }
}

abstract class UDPDevice extends NetworkedDevice implements AsyncInitDevice {
  UDPDevice({
    required super.ipAddr,
    super.refreshRate,
    required this.port,
    required super.id,
    required super.ledfx,
    required super.config,
  });

  int port;

  @override
  Future<void> activate() async {
    await UDPSender().activate();
    super.activate();
  }

  @override
  void deactivate() {
    super.deactivate();
    UDPSender().deactivate();
  }
}
