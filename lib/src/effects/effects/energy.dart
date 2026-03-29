import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ledfx/src/audio/audio.dart';
import 'package:ledfx/src/audio/mel_utils.dart';
import 'package:ledfx/src/effects/audio_reactive.dart';
import 'package:ledfx/src/effects/effect.dart';

enum MixMode {
  add,
  overlap,
  overlapAlt,
  overlapAlt2;

  String get fullName {
    return switch (this) {
      MixMode.add => "Additive",
      MixMode.overlap => "Overlap - HML",
      MixMode.overlapAlt => "Overlap - MHL",
      MixMode.overlapAlt2 => "Overlap - LMH",
    };
  }
}

class EnergyEffect extends Effect with AudioReactiveEffect implements EffectMixin {
  EnergyEffect({required super.ledfx, required super.config}) {
    multiplier = 1.6 - config.blur / 17;
  }
  late double multiplier;
  int lowsIdx = 0;
  int midsIdx = 0;
  int highsIdx = 0;
  bool beatNow = false;
  late List<Float32List> p;
  late Float32List lowsColor;
  late Float32List midsColor;
  late Float32List highColor;
  MatrixExpFilter? filter;

  @override
  void onActivate(int pixelCount) {
    p = List.generate(pixelCount, (index) => Float32List(3));
    final lc = config.lowsColor ?? Colors.red;
    final mc = config.midsColor ?? Colors.green;
    final hc = config.highColor ?? Colors.blue;
    lowsColor = Float32List.fromList([lc.r * 255.0, lc.g * 255.0, lc.b * 255.0]);
    midsColor = Float32List.fromList([mc.r * 255.0, mc.g * 255.0, mc.b * 255.0]);
    highColor = Float32List.fromList([hc.r * 255.0, hc.g * 255.0, hc.b * 255.0]);

    // TODO: set the filter on config update, move from here
    final filterSensitivity = config.filterSensitiviy ?? 0.6;
    final decaySensitivity = (filterSensitivity - 0.1) * 0.7;
    filter = createFilter(decaySensitivity, filterSensitivity);

    if (filter != null) {
      filter!.reset();
    }
  }

  @override
  void audioDataUpdated(AudioAnalysisSource audio) {
    double mean(Iterable<double> values) => values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

    final indices = melbankThirds(filtered: false).map((i) {
      return (multiplier * pixelCount * mean(i)).toInt();
    }).toList();

    lowsIdx = indices[0];
    midsIdx = indices[1];
    highsIdx = indices[2];

    beatNow = audio.volumeBeatNow();
  }

  @override
  void render() {
    // fill with zeros
    setRows(p, p.length, Float32List(3));

    config.mixMode ??= MixMode.overlap;

    if (config.mixMode == MixMode.add) {
      //  Values are added to existing ones
      // Caps to 255 --> makes ovelaped regions whiter
      setRows(p, lowsIdx, lowsColor);
      addRows(p, midsIdx, midsColor);
      addRows(p, highsIdx, highColor);
    } else if (config.mixMode == MixMode.overlap) {
      // Overlap: Values simply overwrite each other
      setRows(p, highsIdx, highColor);
      setRows(p, midsIdx, midsColor);
      setRows(p, lowsIdx, lowsColor);
    } else if (config.mixMode == MixMode.overlapAlt) {
      // Overlap: Values simply overwrite each other
      // highs are generally sorter. this has better color dynamics
      setRows(p, midsIdx, midsColor);
      setRows(p, highsIdx, highColor);
      setRows(p, lowsIdx, lowsColor);
    } else if (config.mixMode == MixMode.overlapAlt2) {
      // Overlap: Values simply overwrite each other
      setRows(p, lowsIdx, lowsColor);
      setRows(p, midsIdx, midsColor);
      setRows(p, highsIdx, highColor);
    }

    // Filter and Update the pixel value
    if (filter != null) {
      pixels = filter!.update(p);
    }
  }

  void setRows(List<Float32List> p, int end, Float32List color) {
    for (int i = 0; i < min(end, p.length); i++) {
      p[i].setAll(0, color);
    }
  }

  void addRows(List<Float32List> p, int end, Float32List color) {
    for (int i = 0; i < min(end, p.length); i++) {
      p[i][0] += color[0];
      p[i][1] += color[1];
      p[i][2] += color[2];
    }
  }
}
