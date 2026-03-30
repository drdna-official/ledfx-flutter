import 'dart:developer' show log;
import 'dart:math' hide log;
import 'dart:typed_data';

import 'network.dart';
import 'packets.dart';

class RealtimeUDPDevice extends UDPDevice {
  RealtimeUDPDevice({
    required super.ipAddr,
    required super.port,
    super.refreshRate,
    required this.udpPacketType,
    this.timeout = 1,
    this.minimizeTraffic = true,
    required super.id,
    required super.ledfx,
    required super.config,
  }) : lastFrame = List.filled(config.pixelCount, Uint8List.fromList(List.filled(3, 0))),
       lastFrameSendTime = DateTime.now().millisecondsSinceEpoch,
       deviceType = "UDP Device";

  String deviceType;
  String udpPacketType;
  int timeout;
  bool minimizeTraffic;

  late List<Uint8List> lastFrame;
  late int lastFrameSendTime;

  @override
  void flush(List<Uint8List> pixelData) {
    try {
      chooseAndSend(pixelData);
      lastFrame = pixelData;
    } catch (e) {
      log("Error: ${e.toString()}");
      activate();
    }
  }

  void chooseAndSend(List<Uint8List> pixelData) {
    final int frameSize = pixelData.length;
    final bool frameIsSame = minimizeTraffic && pixelData == lastFrame;

    switch ((udpPacketType, frameSize)) {
      case ("DRGB", <= 490):
        final udpData = Packets.buidDRGBpacket(pixelData, timeout);
        transmitPacket(udpData, frameIsSame);
        break;
      case ("WARLS", <= 255):
        final udpData = Packets.buildWARLSpacket(pixelData, timeout);
        transmitPacket(udpData, frameIsSame);
        break;
      case ("DNRGB", _):
        final numberOfPackets = (frameSize / 489).ceil();
        for (int i = 0; i < numberOfPackets; i++) {
          int start = i * 489;
          int end = start + 489;
          end = min(end, pixelData.length);
          final udpData = Packets.buidDNRGBpacket(pixelData.sublist(start, end), start, timeout);
          transmitPacket(udpData, frameIsSame);
        }
        break;
      default:
        log("""UDP packet is configured incorrectly (please choose a packet that supports $pixelCount LEDs): 
          https://kno.wled.ge/interfaces/udp-realtime/#udp-realtime \n Falling back to supported udp packet.""");

        if (frameSize < 255) {
          //DRGB
          final udpData = Packets.buidDRGBpacket(pixelData, timeout);
          transmitPacket(udpData, frameIsSame);
        } else {
          // DNRGB
          final numberOfPackets = (frameSize / 489).ceil();
          for (int i = 0; i < numberOfPackets; i++) {
            int start = i * 489;
            int end = start + 489;
            final udpData = Packets.buidDNRGBpacket(pixelData.getRange(start, end).toList(), start, timeout);
            transmitPacket(udpData, frameIsSame);
          }
        }
    }
  }

  void transmitPacket(List<int> packet, bool frameIsSame) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final uint8Packet = packet is Uint8List ? packet : Uint8List.fromList(packet);

    if (frameIsSame) {
      final halfTimeout = ((((timeout * refreshRate) - 1) ~/ 2) / refreshRate) * 1000;

      if (timestamp > lastFrameSendTime + halfTimeout) {
        if (destination != null) {
          UDPSender().sendPacket(destination!, port, uint8Packet);
          lastFrameSendTime = timestamp;
        }
      }
    } else {
      if (destination != null) {
        UDPSender().sendPacket(destination!, port, uint8Packet);
        lastFrameSendTime = timestamp;
      }
    }
  }
}
