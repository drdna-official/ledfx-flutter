import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ledfx/src/core.dart';
import 'package:ledfx/src/effects/effects/energy.dart';
import 'package:ledfx/src/effects/effects/temporal.dart';
import 'package:ledfx/src/effects/effects/wavelength.dart';
import 'package:ledfx/utils/utils.dart';
import 'package:ledfx/src/virtual.dart';

enum EffectType {
  wavelength,
  energy,
  rainbow,
  unknown;

  static EffectType fromName(String name) {
    return EffectType.values.firstWhere((e) => e.name == name, orElse: () => EffectType.unknown);
  }

  String get fullName => switch (name) {
    "wavelength" => "Wavelength",
    "energy" => "Energy",
    "rainbow" => "Rainbow",
    _ => name,
  };
}

class EffectConfig {
  String name;
  EffectType type;
  double blur;
  bool flip;
  bool mirror;
  double brightness;
  bool useBG;
  Color backgroudColor;
  double backgroundBrightness;
  bool diag;
  bool advanced;
  MixMode? mixMode;
  double? filterSensitiviy;
  Color? lowsColor;
  Color? midsColor;
  Color? highColor;

  EffectConfig({
    required this.name,
    required this.type,
    this.blur = 1.0,
    this.flip = false,
    this.mirror = false,
    this.brightness = 1.0,
    this.useBG = false,
    this.backgroudColor = Colors.black,
    this.backgroundBrightness = 1.0,
    this.diag = false,
    this.advanced = false,
    this.mixMode,
    this.filterSensitiviy,
    this.lowsColor,
    this.midsColor,
    this.highColor,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type.name,
      'blur': blur,
      'flip': flip,
      'mirror': mirror,
      'brightness': brightness,
      'useBG': useBG,
      'backgroudColor': backgroudColor.toARGB32(),
      'backgroundBrightness': backgroundBrightness,
      'diag': diag,
      'advanced': advanced,
      'mixMode': mixMode?.name,
      'decaySensitivity': filterSensitiviy,
      'lowsColor': lowsColor?.toARGB32(),
      'midsColor': midsColor?.toARGB32(),
      'highColor': highColor?.toARGB32(),
    };
  }

  factory EffectConfig.fromJson(Map<String, dynamic> json) {
    return EffectConfig(
      name: json['name'],
      type: EffectType.fromName(json['type']),
      blur: json['blur'] ?? 1.0,
      flip: json['flip'] ?? false,
      mirror: json['mirror'] ?? false,
      brightness: json['brightness'] ?? 1.0,
      useBG: json['useBG'] ?? false,
      backgroudColor: json['backgroudColor'] != null ? Color(json['backgroudColor']) : Colors.black,
      backgroundBrightness: json['backgroundBrightness'] ?? 1.0,
      diag: json['diag'] ?? false,
      advanced: json['advanced'] ?? false,
      mixMode: json['mixMode'] != null ? MixMode.values.firstWhere((e) => e.name == json['mixMode']) : null,
      filterSensitiviy: json['decaySensitivity'],
      lowsColor: json['lowsColor'] != null ? Color(json['lowsColor']) : null,
      midsColor: json['midsColor'] != null ? Color(json['midsColor']) : null,
      highColor: json['highColor'] != null ? Color(json['highColor']) : null,
    );
  }
}

abstract interface class EffectMixin {
  void onActivate(int pixelCount);
}

abstract class Effect {
  final LEDFx ledfx;
  final EffectConfig config;
  String get name => config.name;

  double passed = 0.0;

  bool _isActive = false;
  bool get isActive => _isActive;

  List<Float64List>? pixels;

  int get pixelCount => pixels?.length ?? 0;

  Virtual? _virtual;
  Virtual? get virtual => _virtual;

  Effect({required this.ledfx, required this.config});
  void activate(Virtual virtual) {
    _virtual = virtual;
    pixels = List.filled(virtual.effectivePixelCount, Float64List(3));

    if (this is EffectMixin) {
      (this as EffectMixin).onActivate(virtual.effectivePixelCount);
    }
    _isActive = true;
  }

  void del() {
    if (isActive) deactivate();
  }

  void deactivate() {
    pixels = null;
    _isActive = false;
  }

  void render();

  /// Returns the pixels of the effect in the format of [R,G,B]
  /// each Uint8List is rgb values of a pixel clamped between 0 and 255
  List<Uint8List>? getPixels() {
    if (virtual == null) return null;
    List<Float64List> tmpPixels = List.filled(virtual!.effectivePixelCount, Float64List(3));
    if (pixels != null) {
      try {
        tmpPixels.copyFromList(pixels!);
      } on ArgumentError {
        return null;
      }
      if (config.flip) tmpPixels = tmpPixels.reversed.toList();

      if (config.mirror) {
        List<Float64List> reversedPixels = tmpPixels.reversed.toList();
        List<Float64List> mirroredPixels = [...reversedPixels, ...tmpPixels];
        int outputRows = mirroredPixels.length ~/ 2;
        List<Float64List> finalPixels = List<Float64List>.generate(outputRows, (i) {
          // Get the two corresponding rows: one from the even index, one from the odd index
          Float64List evenRow = mirroredPixels[2 * i]; // mirrored_pixels[::2] element
          Float64List oddRow = mirroredPixels[2 * i + 1]; // mirrored_pixels[1::2] element

          // Create the result row for the maximums
          Float64List maxRow = Float64List(3);

          // Element-wise maximum (loop through columns)
          for (int j = 0; j < 3; j++) {
            maxRow[j] = max(evenRow[j], oddRow[j]); // np.maximum equivalent
          }

          return maxRow;
        });

        tmpPixels = finalPixels;
      }

      if (config.useBG) {
        for (final row in tmpPixels) {
          for (int j = 0; j < 3; j++) {
            // TODO: change o into bgColor[j]
            row[j] += 0;
          }
        }
      }
      // Brightness
      for (final row in tmpPixels) {
        for (int j = 0; j < 3; j++) {
          row[j] *= config.brightness;
        }
      }

      // TODO: Blur

      if (config.blur != 0 && pixelCount > 3) {
        final List<double> kernel = gaussianKernel1d(config.blur, 0, tmpPixels.length);

        // R channel
        // Python: pixels[:, 0] = np.convolve(pixels[:, 0], kernel, mode="same")
        List<double> rValues = getPixelValueColumn(tmpPixels, 0);
        List<double> blurredR = convolveSame(rValues, kernel);
        setPixelValueColumn(tmpPixels, 0, blurredR);

        // G channel (Column 1)
        // Python: pixels[:, 1] = np.convolve(pixels[:, 1], kernel, mode="same")
        List<double> gValues = getPixelValueColumn(tmpPixels, 1);
        List<double> blurredG = convolveSame(gValues, kernel);
        setPixelValueColumn(tmpPixels, 1, blurredG);

        // B channel (Column 2)
        // Python: pixels[:, 2] = np.convolve(pixels[:, 2], kernel, mode="same")
        List<double> bValues = getPixelValueColumn(tmpPixels, 2);
        List<double> blurredB = convolveSame(bValues, kernel);
        setPixelValueColumn(tmpPixels, 2, blurredB);
      }

      return tmpPixels
          .map((pixelData) => Uint8List.fromList(pixelData.map((v) => v.toInt().clamp(0, 255)).toList()))
          .toList();
    }

    return null;
  }
}

class Effects {
  final LEDFx ledfx;
  Effects({required this.ledfx}) {
    ledfx.audioSource = null;
  }

  Effect create(Map<String, dynamic> effectData) {
    final effectConfig = EffectConfig.fromJson(effectData);

    Effect? effect;
    switch (effectConfig.type) {
      case EffectType.wavelength:
        effect = WavelengthEffect(ledfx: ledfx, config: effectConfig);
        break;
      case EffectType.energy:
        effect = EnergyEffect(ledfx: ledfx, config: effectConfig);
        break;
      case EffectType.rainbow:
        effect = RainbowEffect(ledfx: ledfx, config: effectConfig);
        break;
      case EffectType.unknown:
        effect = null;
        break;
    }

    if (effect != null) {
      return effect;
    }
    throw Exception('Unknown effect type: ${effectConfig.type}');
  }
}

// A helper function to extract a column (R=0, G=1, B=2)
List<double> getPixelValueColumn(List<Float64List> pixels, int colIndex) {
  return pixels.map((row) => row[colIndex]).toList();
}

// A helper function to update a column with convolved values
void setPixelValueColumn(List<Float64List> pixels, int colIndex, List<double> newValues) {
  for (int i = 0; i < pixels.length; i++) {
    pixels[i][colIndex] = newValues[i];
  }
}
