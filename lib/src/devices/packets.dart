import 'dart:typed_data';

class Packets {
  static List<int> buidDRGBpacket(List<Uint8List> data, [int? timeout]) {
    // Generic DRGB packet encoding
    // Max LEDs: 490

    // Header: [2, timeout]
    // Byte 	Description
    // 2 + n*3 	Red Value
    // 3 + n*3 	Green Value
    // 4 + n*3 	Blue Value

    final int totalSize = 2 + (data.length * 3);
    final Uint8List buffer = Uint8List(totalSize);
    buffer[0] = 2;
    buffer[1] = timeout ?? 1;
    
    int offset = 2;
    for (int i = 0; i < data.length; i++) {
        buffer[offset++] = data[i][0];
        buffer[offset++] = data[i][1];
        buffer[offset++] = data[i][2];
    }
    
    return buffer;
  }

  static List<int> buidDNRGBpacket(List<Uint8List> data, int ledStartIndex, [int? timeout]) {
    // Generic DNRGB packet encoding
    // Max LEDs: 489 / packet

    // Header: [4, timeout, start index high byte, start index low byte]
    // Byte 	Description
    // 4 + n*3 	Red Value
    // 5 + n*3 	Green Value
    // 6 + n*3 	Blue Value
    
    final int totalSize = 4 + (data.length * 3);
    final Uint8List packetBuffer = Uint8List(totalSize);

    packetBuffer[0] = 4;
    packetBuffer[1] = timeout ?? 1;
    packetBuffer[2] = (ledStartIndex >> 8) & 0xFF;
    packetBuffer[3] = ledStartIndex & 0xFF;

    int offset = 4;
    for (int i = 0; i < data.length; i++) {
        packetBuffer[offset++] = data[i][0];
        packetBuffer[offset++] = data[i][1];
        packetBuffer[offset++] = data[i][2];
    }

    return packetBuffer;
  }

  // TODO: Implement
  static List<int> buildWARLSpacket(List<Uint8List> data, [int? timeout]) {
    //     Generic WARLS packet encoding
    // Max LEDs: 255

    // Header: [1, timeout]
    // Byte 	Description
    // 2 + n*4 	LED Index
    // 3 + n*4 	Red Value
    // 4 + n*4 	Green Value
    // 5 + n*4 	Blue Value
    List<int> header = [2, timeout ?? 1];

    return [...header];
  }
}
