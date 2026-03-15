import 'package:flutter/material.dart';

class VisualizerPainter extends CustomPainter {
  final List<int> rgb; // flat RGB buffer
  final int ledCount;

  VisualizerPainter({required this.rgb, required this.ledCount});

  @override
  void paint(Canvas canvas, Size size) {
    if (rgb.isEmpty) return;
    
    final paint = Paint();
    final ledW = size.width / ledCount;
    final bufferLength = rgb.length;
    
    for (int i = 0; i < ledCount; i++) {
      final idx = i * 3;
      if (idx + 2 >= bufferLength) break;
      
      paint.color = Color.fromARGB(255, rgb[idx], rgb[idx+1], rgb[idx+2]);
      canvas.drawRect(Rect.fromLTWH(i * ledW, 0, ledW, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant VisualizerPainter old) {
    return old.rgb != rgb || old.ledCount != ledCount;
  }
}
