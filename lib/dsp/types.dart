import 'dart:math';
import 'dart:typed_data';

import 'utils.dart';

extension type ComplexVector(Float32List _data) {
  // _data = [length, ...norm, ...phase]
  static const int headerSize = 1;

  static ComplexVector create(int length) {
    assert(length > 0, "length must be > 0");
    return ComplexVector(Float32List(headerSize + length * 2))..setLength(length);
  }

  void clear() {
    _data.fillRange(headerSize, _data.length, 0.0);
  }

  int getLength() => _data[0].toInt();
  void setLength(int val) => _data[0] = val.toDouble();

  double getNorm(int index) => _data[headerSize + index];
  void setNorm(int index, double val) => _data[headerSize + index] = val;

  double getPhase(int index) => _data[headerSize + getLength() + index];
  void setPhase(int index, double val) => _data[headerSize + getLength() + index] = val;
}

extension type FloatVector(Float32List _data) {
  // _data = [length, ...data]
  static const int headerSize = 1;

  static FloatVector create(int length) {
    return FloatVector(Float32List(headerSize + length))..setLength(length);
  }

  static FloatVector fromArray(Float32List list) {
    final FloatVector vec = FloatVector.create(list.length);
    vec._data.setRange(headerSize, headerSize + list.length, list);
    return vec;
  }

  void copyFrom(Float32List list) {
    assert(list.length == getLength(), "list length must match vector length");
    _data.setRange(headerSize, headerSize + list.length, list);
  }

  void copyTo(Float32List list) {
    assert(list.length == getLength(), "list length must match vector length");
    list.setRange(0, getLength(), _data, headerSize);
  }

  int getLength() => _data[0].toInt();
  void setLength(int val) => _data[0] = val.toDouble();

  double get(int index) => _data[headerSize + index];
  void set(int index, double val) => _data[headerSize + index] = val;

  Float32List getData() => Float32List.view(_data.buffer, _data.offsetInBytes + headerSize * 4);

  void setPower(double power) {
    for (int i = headerSize; i < getLength(); i++) {
      set(i, pow(get(i), power).toDouble());
    }
  }

  void clear() {
    _data.fillRange(headerSize, _data.length, 0.0);
  }

  static FloatVector newWindow(WindowType type, int length) {
    FloatVector w = FloatVector.create(length);
    switch (type) {
      case WindowType.hanning:
        for (int i = 0; i < length; i++) {
          w.set(i, 0.5 - 0.5 * cos(2.0 * pi * i / length));
        }
        break;
      case WindowType.hanningz:
        for (int i = 0; i < length; i++) {
          w.set(i, 0.5 * (1.0 - cos(2.0 * pi * i / length)));
        }
        break;
    }
    return w;
  }
}

enum WindowType { hanning, hanningz }

extension type FilterBankData(Float32List _data) {
  // _data = [windowSize, noFilters, norm, power, filterCol, filterRow, ...filterCoeffs]
  // Offset math: Each filterbank has header of 5 values - (windowSize, noFilters, norm, power,filterCol, filterRow)
  static const int headerSize = 6;

  static FilterBankData create(int noFilters, int winSize) {
    return FilterBankData(Float32List(noFilters * (winSize ~/ 2 + 1) + headerSize))
      ..setWinSize(winSize)
      ..setNFilters(noFilters)
      ..setNorm(1)
      ..setPower(1)
      ..setFilterCol(winSize ~/ 2 + 1)
      ..setFilterRow(noFilters);
  }

  // We cast the ints to floats to store them in the same contiguous block
  int getWinSize() => _data[0].toInt();
  int getNFilters() => _data[1].toInt();
  double getNorm() => _data[2];
  double getPower() => _data[3];
  int getFilterCol() => _data[4].toInt();
  int getFilterRow() => _data[5].toInt();

  setWinSize(int val) => _data[0] = val.toDouble();
  setNFilters(int val) => _data[1] = val.toDouble();
  setNorm(double val) => _data[2] = val;
  setPower(double val) => _data[3] = val;
  setFilterCol(int val) => _data[4] = val.toDouble();
  setFilterRow(int val) => _data[5] = val.toDouble();

  double get(int filterIndex, int index) => _data[headerSize + filterIndex * getFilterCol() + index];
  void set(int filterIndex, int index, double val) => _data[headerSize + filterIndex * getFilterCol() + index] = val;

  void clear() {
    for (int i = headerSize; i < _data.length; i++) {
      _data[i] = 0;
    }
  }

  void matrixMultiply(FloatVector input, Float32List output) {
    final int rows = getFilterRow();
    final int cols = getFilterCol();
    for (int k = 0; k < rows; k++) {
      double sum = 0.0;
      final int rowOffset = headerSize + k * cols;
      for (int j = 0; j < cols; j++) {
        final double weight = _data[rowOffset + j];
        if (weight > 0.0) {
          sum += input.get(j) * weight;
        }
      }
      output[k] = sum;
    }
  }
}

extension type DigitalFilterData(Float64List _data) {
  // _data = [order, samplerate, ...a, ...b, ...x, ...y]
  static const int headerSize = 2;

  static DigitalFilterData create(int order) {
    // validate order parameter to prevent unrealistic allocations
    if (order < 1) {
      throw Exception("order must be > 0");
    }
    // typical values are 3, 5, or 7; allow up to 512 as reasonable upper bound
    if (order > 512) {
      throw Exception("order must be <= 512");
    }

    return DigitalFilterData(Float64List(order * 4 + headerSize))
      ..setOrder(order)
      // by default samplerate is not set
      ..setSamplerate(0)
      // set default to identity
      ..setA(0, 1.0)
      ..setB(0, 1.0);
  }

  int getOrder() => _data[0].toInt();
  int getSamplerate() => _data[1].toInt();

  setOrder(int val) => _data[0] = val.toDouble();
  setSamplerate(int val) => _data[1] = val.toDouble();

  getA(int index) => _data[headerSize + index];
  double getB(int index) => _data[headerSize + getOrder() + index];
  double getX(int index) => _data[headerSize + getOrder() * 2 + index];
  double getY(int index) => _data[headerSize + getOrder() * 3 + index];

  void setA(int index, double val) => _data[headerSize + index] = val;
  void setB(int index, double val) => _data[headerSize + getOrder() + index] = val;
  void setX(int index, double val) => _data[headerSize + getOrder() * 2 + index] = val;
  void setY(int index, double val) => _data[headerSize + getOrder() * 3 + index] = val;

  void clear() {
    for (int i = headerSize; i < _data.length; i++) {
      _data[i] = 0;
    }
  }
}

class FFTData {
  const FFTData._({
    required this.winSize,
    required this.fftSize,
    required this.dIN,
    required this.dOut,
    required this.w,
    required this.ip,
    required this.compSpec,
  });

  final Float32List dIN;
  final Float32List dOut;
  final Float32List w;
  final Int32List ip;
  final FloatVector compSpec;

  final int winSize;
  final int fftSize;

  static FFTData create(int winSize) {
    if (winSize < 2) {
      throw Exception("fft: got winSize $winSize, can not be <2");
    }
    if (!isPowerOfTwo(winSize)) {
      throw Exception("fft: got winSize $winSize, can not be odd");
    }
    final fftSize = winSize ~/ 2 + 1;

    return FFTData._(
      winSize: winSize,
      fftSize: fftSize,
      dIN: Float32List(winSize),
      dOut: Float32List(winSize),
      w: Float32List(fftSize),
      ip: Int32List(fftSize),
      compSpec: FloatVector.create(winSize),
    );
  }

  void setIn(int index, double data) => dIN[index] = data;
  double getIn(int index) => dIN[index];

  void setOut(int index, double data) => dOut[index] = data;
  double getOut(int index) => dOut[index];

  void setW(int index, double data) => w[index] = data;
  double getW(int index) => w[index];

  void setIp(int index, int data) => ip[index] = data;
  int getIp(int index) => ip[index];
}

class PVOCData {
  PVOCData._({
    required this.winSize,
    required this.hopSize,
    required this.start,
    required this.end,
    required this.scale,
    required this.endDataSize,
    required this.hopDataSize,
    required this.data,
    required this.dataOld,
    required this.synth,
    required this.synthOld,
    required this.w,
  });

  // winSize: grain length
  // hopSize: overlap step
  // start: start of the window
  // end: end of the window
  // scale: scaling factor for synthesis
  // end_datasize: size of the end data
  // hop_datasize: size of the hop data
  // data: current input grain, [winSize] frames
  // dataold: memory of past grain, [winSize-hopSize] frames
  // synth: current output grain, [winSize] frames
  // synthold: memory of past grain, [winSize-hopSize] frames
  // w: grain window [winSize]
  final int winSize;
  final int hopSize;
  final int start;
  final int end;
  final double scale;
  final int endDataSize;
  final int hopDataSize;
  final FloatVector data;
  final FloatVector dataOld;
  final FloatVector synth;
  final FloatVector synthOld;
  final FloatVector w;

  static const int headerSize = 12;

  static PVOCData create(int winSize, int hopSize) {
    if (winSize < 2) {
      throw Exception("pvoc: got winSize $winSize, can not be <2");
    }
    if (!isPowerOfTwo(winSize)) {
      throw Exception("pvoc: got winSize $winSize, can not be odd");
    }
    if (hopSize < 1) {
      throw Exception("pvoc: got hopSize $hopSize, can not be <1");
    }
    if (hopSize > winSize) {
      throw Exception("pvoc: got hopSize $hopSize, can not be >winSize");
    }

    final data = FloatVector.create(winSize);
    final synth = FloatVector.create(winSize);

    late FloatVector dataOld;
    late FloatVector synthOld;
    if (winSize > hopSize) {
      dataOld = FloatVector.create(winSize - hopSize);
      synthOld = FloatVector.create(winSize - hopSize);
    } else {
      dataOld = FloatVector.create(1);
      synthOld = FloatVector.create(1);
    }

    // Window
    final w = FloatVector.newWindow(WindowType.hanningz, winSize);
    // more than 50% overlap, overlap anyway else less than 50% overlap, reset latest grain trail
    final start = (winSize < 2 * hopSize) ? 0 : winSize - 2 * hopSize;
    final end = (winSize > hopSize) ? winSize - hopSize : 0;

    final endDataSize = end;
    final hopDataSize = hopSize;

    // for reconstruction with 75% overlap
    late double scale;
    if (winSize == 4 * hopSize) {
      scale = 2 / 3;
    } else if (winSize == 8 * hopSize) {
      scale = 1 / 3;
    } else if (winSize == 2 * hopSize) {
      scale = 1.0;
    } else {
      scale = 0.5;
    }

    return PVOCData._(
      winSize: winSize,
      hopSize: hopSize,
      start: start,
      end: end,
      scale: scale,
      endDataSize: endDataSize,
      hopDataSize: hopDataSize,
      data: data,
      dataOld: dataOld,
      synth: synth,
      synthOld: synthOld,
      w: w,
    );
  }
}
