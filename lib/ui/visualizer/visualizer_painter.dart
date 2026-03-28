import 'package:flutter/material.dart';

abstract class VisualizerPainter extends CustomPainter {
  final List<int> values; // flat RGB buffer / single value buffer
  final int ledCount;

  VisualizerPainter({required this.values, required this.ledCount});
}

class StripVisualizerPainter extends VisualizerPainter {
  StripVisualizerPainter({required super.values, required super.ledCount});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paint = Paint();
    final ledW = size.width / ledCount;
    final bufferLength = values.length;

    for (int i = 0; i < ledCount; i++) {
      final idx = i * 3;
      if (idx + 2 >= bufferLength) break;

      paint.color = Color.fromARGB(255, values[idx], values[idx + 1], values[idx + 2]);
      canvas.drawRect(Rect.fromLTWH(i * ledW, 0, ledW, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant StripVisualizerPainter old) {
    return old.values != values || old.ledCount != ledCount;
  }
}

enum BarVisualizerValueType { rgb, rgbBars, singleValue }

class BarVisualizerPainter extends VisualizerPainter {
  final BarVisualizerValueType valueType;
  final Color? singleValueColor;
  final double alpha;
  BarVisualizerPainter({
    required super.values,
    required super.ledCount,
    required this.valueType,
    this.singleValueColor,
    this.alpha = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paint = Paint();
    final barWidth = size.width / ledCount;

    if (valueType == BarVisualizerValueType.rgb) {
      for (int i = 0; i < ledCount; i++) {
        final idx = i * 3;
        if (idx + 2 >= values.length) break;
        final v = values[idx];
        final barHeight = size.height * v / 255;
        paint.color = Color.fromARGB((255 * alpha).toInt(), values[idx], values[idx + 1], values[idx + 2]);
        canvas.drawRect(Rect.fromLTWH(i * barWidth, size.height - barHeight, barWidth, barHeight), paint);
      }
    } else if (valueType == BarVisualizerValueType.rgbBars) {
      for (int i = 0; i < ledCount; i++) {
        final idx = i * 3;
        if (idx + 2 >= values.length) break;
        int v = values[idx];
        double barHeight = size.height * v / 255;
        paint.color = Color.fromARGB((255 * alpha).toInt(), v, 0, 0);
        canvas.drawRect(Rect.fromLTWH(i * barWidth, size.height - barHeight, barWidth, barHeight), paint);

        v = values[idx + 1];
        barHeight = size.height * v / 255;
        paint.color = Color.fromARGB((255 * alpha).toInt(), 0, v, 0);
        canvas.drawRect(Rect.fromLTWH(i * barWidth, size.height - barHeight, barWidth, barHeight), paint);

        v = values[idx + 2];
        barHeight = size.height * v / 255;
        paint.color = Color.fromARGB((255 * alpha).toInt(), 0, 0, v);
        canvas.drawRect(Rect.fromLTWH(i * barWidth, size.height - barHeight, barWidth, barHeight), paint);
      }
    } else {
      for (int i = 0; i < ledCount; i++) {
        final v = values[i];
        final barHeight = size.height * v / 255;
        paint.color =
            singleValueColor?.withValues(alpha: alpha) ?? Color.fromARGB((255 * alpha).toInt(), 255, 255, 255);
        canvas.drawRect(Rect.fromLTWH(i * barWidth, size.height - barHeight, barWidth, barHeight), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant BarVisualizerPainter old) {
    return old.values != values || old.ledCount != ledCount;
  }
}
