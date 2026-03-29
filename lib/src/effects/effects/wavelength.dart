import 'dart:typed_data';
import 'package:ledfx/src/audio/audio.dart';
import 'package:ledfx/src/effects/audio_reactive.dart';
import 'package:ledfx/src/effects/effect.dart';
import 'package:ledfx/src/effects/effects/gradient.dart';

class WavelengthEffect extends Effect with AudioReactiveEffect, GradientAudioEffect implements EffectMixin {
  WavelengthEffect({required super.ledfx, required super.config});
  late Float32List r;

  @override
  void onActivate(int pixelCount) {
    r = Float32List(pixelCount);
  }

  @override
  void audioDataUpdated(AudioAnalysisSource audio) {
    r = Float32List.fromList(melbank(filtered: true, size: pixelCount));
  }

  @override
  void render() {
    pixels = applyGradient(r);
  }
}
