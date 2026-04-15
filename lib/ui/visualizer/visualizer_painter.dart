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

    final paint = Paint()..isAntiAlias = false;
    final bufferLength = values.length;

    for (int i = 0; i < ledCount; i++) {
      final idx = i * 3;
      if (idx + 2 >= bufferLength) break;

      final left = i * size.width / ledCount;
      final right = (i + 1) * size.width / ledCount;

      paint.color = Color.fromARGB(255, values[idx], values[idx + 1], values[idx + 2]);
      canvas.drawRect(Rect.fromLTRB(left, 0, right, size.height), paint);
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
  final double topPadding;
  BarVisualizerPainter({
    required super.values,
    required super.ledCount,
    required this.valueType,
    this.singleValueColor,
    this.alpha = 1.0,
    this.topPadding = 10.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paint = Paint()..isAntiAlias = true;

    if (valueType == BarVisualizerValueType.rgb) {
      for (int i = 0; i < ledCount; i++) {
        final idx = i * 3;
        if (idx + 2 >= values.length) break;
        final v = values[idx];
        final barHeight = (size.height - topPadding) * v / 255;
        final left = i * size.width / ledCount;
        final right = (i + 1) * size.width / ledCount;

        paint.color = Color.fromARGB((255 * alpha).toInt(), values[idx], values[idx + 1], values[idx + 2]);
        final radius = Radius.circular((right - left) / 2);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(left, size.height - barHeight, right, size.height),
            topLeft: radius,
            topRight: radius,
          ),
          paint,
        );
      }
    } else if (valueType == BarVisualizerValueType.rgbBars) {
      for (int i = 0; i < ledCount; i++) {
        final idx = i * 3;
        if (idx + 2 >= values.length) break;
        final left = i * size.width / ledCount;
        final right = (i + 1) * size.width / ledCount;

        final radius = Radius.circular((right - left) / 2);

        int v = values[idx];
        double barHeight = (size.height - topPadding) * v / 255;
        paint.color = Color.fromARGB((255 * alpha).toInt(), v, 0, 0);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(left, size.height - barHeight, right, size.height),
            topLeft: radius,
            topRight: radius,
          ),
          paint,
        );

        v = values[idx + 1];
        barHeight = (size.height - topPadding) * v / 255;
        paint.color = Color.fromARGB((255 * alpha).toInt(), 0, v, 0);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(left, size.height - barHeight, right, size.height),
            topLeft: radius,
            topRight: radius,
          ),
          paint,
        );

        v = values[idx + 2];
        barHeight = (size.height - topPadding) * v / 255;
        paint.color = Color.fromARGB((255 * alpha).toInt(), 0, 0, v);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(left, size.height - barHeight, right, size.height),
            topLeft: radius,
            topRight: radius,
          ),
          paint,
        );
      }
    } else {
      for (int i = 0; i < ledCount; i++) {
        final v = values[i];
        final barHeight = (size.height - topPadding) * v / 255;
        final left = i * size.width / ledCount;
        final right = (i + 1) * size.width / ledCount;

        final radius = Radius.circular((right - left) / 2);
        paint.color =
            singleValueColor?.withValues(alpha: alpha) ?? Color.fromARGB((255 * alpha).toInt(), 255, 255, 255);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(left, size.height - barHeight, right, size.height),
            topLeft: radius,
            topRight: radius,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant BarVisualizerPainter old) {
    return old.values != values || old.ledCount != ledCount;
  }
}
