import 'dart:typed_data';

import 'sinc_fastest_coeffs.dart';

enum ResamplerType { linear, sincFastest }

class Resampler {
  final ResamplerType type;
  final int inLen;
  final int outLen;
  final double step;
  final double srcRatio; // outLen / inLen
  final double antiAlias;

  late final Float32List _buffer;
  late final int _historyLen;
  double _time = 0.0;

  static const double _sincHalfLen = 19.5; // 2463 / 128 is approx 19.25
  static final Float32List _paddedCoeffs = _initPaddedCoeffs();

  static Float32List _initPaddedCoeffs() {
    final list = Float32List(sincFastestCoeffs.length + 512);
    list.setAll(0, sincFastestCoeffs);
    return list;
  }

  static const int _shiftBits = 12;
  static const int _shiftMask = (1 << _shiftBits) - 1;
  static const double _fracScale = 1.0 / 4096.0;

  Resampler(this.type, this.inLen, this.outLen)
    : srcRatio = outLen / inLen,
      step = inLen / outLen,
      antiAlias = (outLen / inLen) < 1.0 ? (outLen / inLen) : 1.0 {
    if (type == ResamplerType.sincFastest) {
      _historyLen = (_sincHalfLen / antiAlias).ceil() + 2;
      _buffer = Float32List(_historyLen + inLen + _historyLen);
    } else {
      _historyLen = 2; // small padding for linear
      _buffer = Float32List(_historyLen + inLen + 2);
    }

    _time = _historyLen.toDouble();
  }

  Float32List process(Float32List input, [int? dummyOutLen]) {
    assert(input.length == inLen, '[Resampler] Input length mismatch');

    // 1. Shift existing buffer left by inLen to retain _historyLen past samples
    _buffer.setRange(0, _historyLen, _buffer, inLen);

    // 2. Append new input right after the history
    _buffer.setRange(_historyLen, _historyLen + inLen, input);

    final Float32List output = Float32List(outLen);


    if (type == ResamplerType.linear) {
      _processLinear(output);
    } else {
      _processSinc(output);
    }

    // Advance exact time and subtract physical shift
    _time = _time + (outLen * step) - inLen;

    return output;
  }

  void _processLinear(Float32List output) {
    final Float32List buffer = _buffer;
    for (int i = 0; i < outLen; i++) {
      final double t = _time + i * step;
      final int tInt = t.toInt();
      final double tFrac = t - tInt;

      final double sample0 = buffer[tInt];
      final double sample1 = buffer[tInt + 1];
      output[i] = sample0 + tFrac * (sample1 - sample0);
    }
  }

  void _processSinc(Float32List output) {
    final double floatInc = sincFastestIncrement * antiAlias;
    final int floatIncFixed = (floatInc * 4096.0).round();
    final int maxOffset = _historyLen - 1;
    final Float32List buffer = _buffer;
    final Float32List coeffs = _paddedCoeffs; // Boundless safely padded

    for (int i = 0; i < outLen; i++) {
      final double t = _time + i * step;
      final int tInt = t.toInt();
      final double tFrac = t - tInt;

      int cPosFixed = (tFrac * floatInc * 4096.0).round();
      int cNegFixed = floatIncFixed - cPosFixed;

      double sum = 0.0;

      // Backward loop (j <= 0)
      int idxPos = tInt;
      for (int k = 0; k <= maxOffset; k++) {
        final int coeffIndex = cPosFixed >> _shiftBits;
        final double coeffFrac = (cPosFixed & _shiftMask) * _fracScale;
        
        final double coeff0 = coeffs[coeffIndex];
        final double coeff = coeff0 + coeffFrac * (coeffs[coeffIndex + 1] - coeff0);
        sum += buffer[idxPos] * coeff;
        
        cPosFixed += floatIncFixed;
        idxPos--;
      }

      // Forward loop (j > 0)
      int idxNeg = tInt + 1;
      for (int k = 1; k <= maxOffset; k++) {
        final int coeffIndex = cNegFixed >> _shiftBits;
        final double coeffFrac = (cNegFixed & _shiftMask) * _fracScale;
        
        final double coeff0 = coeffs[coeffIndex];
        final double coeff = coeff0 + coeffFrac * (coeffs[coeffIndex + 1] - coeff0);
        sum += buffer[idxNeg] * coeff;
        
        cNegFixed += floatIncFixed;
        idxNeg++;
      }

      output[i] = sum * antiAlias;
    }
  }
}
