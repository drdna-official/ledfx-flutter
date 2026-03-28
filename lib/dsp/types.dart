import 'dart:math';
import 'dart:typed_data';

extension type ComplexVector(Float64List _data) {
  // _data = [length, ...norm, ...phase]
  static const int headerSize = 1;

  static ComplexVector create(int length) {
    assert(length > 0, "length must be > 0");
    return ComplexVector(Float64List(headerSize + (length ~/ 2 + 1) * 2))..setLength(length ~/ 2 + 1);
  }

  int getLength() => _data[0].toInt();
  void setLength(int val) => _data[0] = val.toDouble();

  double getNorm(int index) => _data[headerSize + index];
  void setNorm(int index, double val) => _data[headerSize + index] = val;

  double getPhase(int index) => _data[headerSize + getLength() + index];
  void setPhase(int index, double val) => _data[headerSize + getLength() + index] = val;
}

extension type FloatVector(Float64List _data) {
  // _data = [length, ...data]
  static const int headerSize = 1;

  static FloatVector create(int length) {
    return FloatVector(Float64List(headerSize + length))..setLength(length);
  }

  static FloatVector fromArray(Float64List list) {
    final FloatVector vec = FloatVector.create(list.length);
    vec._data.setRange(headerSize, headerSize + list.length, list);
    return vec;
  }

  int getLength() => _data[0].toInt();
  void setLength(int val) => _data[0] = val.toDouble();

  double get(int index) => _data[headerSize + index];
  void set(int index, double val) => _data[headerSize + index] = val;

  Float64List getData() => _data.sublist(headerSize);

  void setPower(double power) {
    for (int i = headerSize; i < getLength(); i++) {
      set(i, pow(get(i), power).toDouble());
    }
  }
}

extension type FilterBankData(Float64List _data) {
  // _data = [windowSize, noFilters, norm, power, filterCol, filterRow, ...filterCoeffs]
  // Offset math: Each filterbank has header of 5 values - (windowSize, noFilters, norm, power,filterCol, filterRow)
  static const int headerSize = 6;

  static FilterBankData create(int noFilters, int winSize) {
    return FilterBankData(Float64List(noFilters * (winSize ~/ 2 + 1) + headerSize))
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

  double get(int filterIndex, int index) => _data[headerSize + filterIndex * getFilterRow() + index];
  void set(int filterIndex, int index, double val) => _data[headerSize + filterIndex * getFilterRow() + index] = val;

  void clear() {
    for (int i = headerSize; i < _data.length; i++) {
      _data[i] = 0;
    }
  }

  void matrixMultiply(FloatVector input, Float64List output) {
    for (int j = 0; j < getFilterCol(); j++) {
      for (int k = 0; k < getFilterRow(); k++) {
        output[k] += input.get(j) * get(k, j);
      }
    }
  }
}
