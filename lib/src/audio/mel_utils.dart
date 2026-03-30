import 'dart:typed_data';
import 'package:ledfx/utils/polynominal.dart';

/// Applies fast Gaussian blur to a 1-dimensional array.
List<double> fastBlurArray(List<double> array, double sigma) {
  if (array.isEmpty) {
    throw ValueError("Cannot smooth an empty array");
  }
  List<double> kernel = gaussianKernel1d(sigma, 0, array.length);
  return convolveSame(array, kernel);
}

class ValueError implements Exception {
  final String message;
  ValueError(this.message);
  @override
  String toString() => 'ValueError: $message';
}

/// Simple exponential smoothing filter with separate rise and decay factors.
///
/// This filter is designed to smooth a numeric stream, applying a faster
/// smoothing factor (alpha_rise) when the new value is increasing, and a
/// slower factor (alpha_decay) when the new value is decreasing.

/// Abstract base class for type-safe, zero-allocation exponential smoothing.
abstract class ExpFilter<T> {
  final double alphaDecay;
  final double alphaRise;

  // Pre-calculated to save CPU cycles in the hot loop
  final double _invAlphaDecay;
  final double _invAlphaRise;

  T? _value;

  ExpFilter({T? initialValue, this.alphaDecay = 0.5, this.alphaRise = 0.5})
    : _invAlphaDecay = 1.0 - alphaDecay,
      _invAlphaRise = 1.0 - alphaRise {
    if (alphaDecay <= 0.0 || alphaDecay >= 1.0) {
      throw ArgumentError("Decay must be between 0.0 and 1.0 (exclusive)");
    }
    if (alphaRise <= 0.0 || alphaRise >= 1.0) {
      throw ArgumentError("Rise must be between 0.0 and 1.0 (exclusive)");
    }
    _value = initialValue;
  }

  /// Returns the current smoothed state.
  // ignore: unnecessary_getters_setters
  T? get value => _value;
  void reset() => _value = null;

  /// Updates the filter and returns the new smoothed value.
  T update(T newValue);
}

// ============================================================================
// 1. Single Number Implementation
// ============================================================================
class NumExpFilter extends ExpFilter<double> {
  NumExpFilter({num? initialValue, super.alphaDecay, super.alphaRise}) : super(initialValue: initialValue?.toDouble());

  @override
  double update(double newValue) {
    if (_value == null) {
      _value = newValue;
      return _value!;
    }

    final double current = _value!;
    if (newValue > current) {
      _value = alphaRise * newValue + _invAlphaRise * current;
    } else {
      _value = alphaDecay * newValue + _invAlphaDecay * current;
    }
    return _value!;
  }
}

// ============================================================================
// 2. Float32List Implementation (Highest Performance for 1D Arrays)
// ============================================================================
class Float32ListExpFilter extends ExpFilter<Float32List> {
  Float32ListExpFilter({super.initialValue, super.alphaDecay, super.alphaRise});

  @override
  Float32List update(Float32List newValue) {
    if (_value == null) {
      // Create a discrete copy so we don't accidentally mutate the user's input array
      _value = Float32List.fromList(newValue);
      return _value!;
    }

    final current = _value!;
    final int len = current.length;

    assert(len == newValue.length, "Lengths must match");

    // Hot loop: No memory allocation, pure math.
    for (int i = 0; i < len; i++) {
      final double c = current[i];
      final double n = newValue[i];

      if (n > c) {
        current[i] = alphaRise * n + _invAlphaRise * c;
      } else {
        current[i] = alphaDecay * n + _invAlphaDecay * c;
      }
    }

    return current;
  }
}

// ============================================================================
// 3. Standard List<double> Implementation
// ============================================================================
class ListExpFilter extends ExpFilter<List<double>> {
  ListExpFilter({super.initialValue, super.alphaDecay, super.alphaRise});

  @override
  List<double> update(List<double> newValue) {
    if (_value == null) {
      _value = List<double>.from(newValue); // Copy
      return _value!;
    }

    final current = _value!;
    final int len = current.length;

    assert(len == newValue.length, "Lengths must match");

    for (int i = 0; i < len; i++) {
      final double c = current[i];
      final double n = newValue[i];

      if (n > c) {
        current[i] = alphaRise * n + _invAlphaRise * c;
      } else {
        current[i] = alphaDecay * n + _invAlphaDecay * c;
      }
    }

    return current;
  }
}

// ============================================================================
// 4. Matrix (List<Float32List>) Implementation
// ============================================================================
class MatrixExpFilter extends ExpFilter<List<Float32List>> {
  MatrixExpFilter({super.initialValue, super.alphaDecay, super.alphaRise});

  @override
  List<Float32List> update(List<Float32List> newValue) {
    if (_value == null) {
      // Deep copy all rows
      _value = newValue.map((row) => Float32List.fromList(row)).toList();
      return _value!;
    }

    final currentMatrix = _value!;
    final int rows = currentMatrix.length;

    assert(rows == newValue.length, "Row counts must match");

    for (int r = 0; r < rows; r++) {
      final Float32List currentRow = currentMatrix[r];
      final Float32List newRow = newValue[r];
      final int cols = currentRow.length;

      // Nested hot loop
      for (int c = 0; c < cols; c++) {
        final double currVal = currentRow[c];
        final double newVal = newRow[c];

        if (newVal > currVal) {
          currentRow[c] = alphaRise * newVal + _invAlphaRise * currVal;
        } else {
          currentRow[c] = alphaDecay * newVal + _invAlphaDecay * currVal;
        }
      }
    }

    return currentMatrix;
  }
}
