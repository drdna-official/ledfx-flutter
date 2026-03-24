import 'dart:math';
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

/// Applies a fast blur effect to the given pixel data (R, G, B channels).
/// for values like -> [[r,g,b], [r,g,b], ...]
List<List<double>> fastBlurPixels(List<List<double>> pixels, double sigma) {
  if (pixels.isEmpty) {
    throw ValueError("Cannot smooth an empty array");
  }

  // Assuming pixels is structured as [[R_data], [G_data], [B_data]]
  // where each inner list is a channel (matching the Python pixels[:, 0] structure)
  if (pixels.length < 3) {
    throw ArgumentError("Input pixels must have at least 3 channels (R, G, B)");
  }

  final List<double> rChannel = pixels[0];
  final List<double> gChannel = pixels[1];
  final List<double> bChannel = pixels[2];

  final int arrayLen = rChannel.length;
  List<double> kernel = gaussianKernel1d(sigma, 0, arrayLen);

  // pixels[:, 0] = np.convolve(pixels[:, 0], kernel, mode="same")
  List<double> rBlurred = convolveSame(rChannel, kernel);

  // pixels[:, 1] = np.convolve(pixels[:, 1], kernel, mode="same")
  List<double> gBlurred = convolveSame(gChannel, kernel);

  // pixels[:, 2] = np.convolve(pixels[:, 2], kernel, mode="same")
  List<double> bBlurred = convolveSame(bChannel, kernel);

  // Return the modified/newly created array structure
  return [rBlurred, gBlurred, bBlurred];
}

class ValueError implements Exception {
  final String message;
  ValueError(this.message);
  @override
  String toString() => 'ValueError: $message';
}

/// Smooths a 1D array via a Gaussian filter using reflection padding
/// and 'valid' convolution mode.
List<double> smooth(List<double> x, double sigma) {
  if (x.isEmpty) {
    throw ValueError("Cannot smooth an empty array");
  }

  // 1. Determine Kernel and Radius
  // kernel_radius = max(1, int(round(4.0 * sigma)))
  int kernelRadius = max(1, (4.0 * sigma).round());

  // filter_kernel = _gaussian_kernel1d(sigma, 0, kernel_radius)
  // NOTE: The Python code uses kernel_radius for array_len here, but
  // the definition of _gaussian_kernel1d uses it to limit the final
  // kernel size (radius). The radius determines the length: 2*radius + 1.
  List<double> filterKernel = gaussianKernel1d(sigma, 0, kernelRadius);
  int kernelLen = filterKernel.length;

  // 2. Determine Required Extended Length (len(x) + len(filter_kernel) - 1)
  int extendedInputLen = x.length + kernelLen - 1;
  List<double> xMirrored = List.from(x); // Start with a copy

  // 3. Mirror Padding Loop (Equivalent to np.r_ and the while loop)
  // This logic is complex because it mirrors iteratively to avoid crashing
  // if len(x) is tiny compared to the required padding.
  while (xMirrored.length < extendedInputLen) {
    // mirror_len = min(len(x_mirrored), (extended_input_len - len(x_mirrored)) // 2)
    int remainingPadding = extendedInputLen - xMirrored.length;
    int mirrorLen = min(xMirrored.length, (remainingPadding / 2).floor());

    // Build the new mirrored array: [Start Mirror] + [x_mirrored] + [End Mirror]
    List<double> newMirrored = [];

    // Start Mirror: x_mirrored[mirror_len - 1 :: -1] (Reversed slice from index mirror_len - 1 down to 0)
    // The slice x_mirrored[:mirror_len] reversed
    for (int i = mirrorLen - 1; i >= 0; i--) {
      newMirrored.add(xMirrored[i]);
    }

    // Original array
    newMirrored.addAll(xMirrored);

    // End Mirror: x_mirrored[-1 : -(mirror_len + 1) : -1] (Reversed slice from last element back for mirror_len items)
    // The slice x_mirrored[-mirror_len:] reversed
    for (int i = xMirrored.length - 1; i >= xMirrored.length - mirrorLen; i--) {
      newMirrored.add(xMirrored[i]);
    }

    xMirrored = newMirrored;
  }

  // 4. Convolve
  // y = np.convolve(x_mirrored, filter_kernel, mode="valid")
  List<double> y = convolveValid(xMirrored, filterKernel);

  // 5. Assertion and Return
  // assert len(y) == len(x)
  if (y.length != x.length) {
    throw StateError("Convolution output length ${y.length} does not match input length ${x.length}.");
  }

  return y;
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
// 2. Float64List Implementation (Highest Performance for 1D Arrays)
// ============================================================================
class Float64ListExpFilter extends ExpFilter<Float64List> {
  Float64ListExpFilter({super.initialValue, super.alphaDecay, super.alphaRise});

  @override
  Float64List update(Float64List newValue) {
    if (_value == null) {
      // Create a discrete copy so we don't accidentally mutate the user's input array
      _value = Float64List.fromList(newValue);
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
// 4. Matrix (List<Float64List>) Implementation
// ============================================================================
class MatrixExpFilter extends ExpFilter<List<Float64List>> {
  MatrixExpFilter({super.initialValue, super.alphaDecay, super.alphaRise});

  @override
  List<Float64List> update(List<Float64List> newValue) {
    if (_value == null) {
      // Deep copy all rows
      _value = newValue.map((row) => Float64List.fromList(row)).toList();
      return _value!;
    }

    final currentMatrix = _value!;
    final int rows = currentMatrix.length;

    assert(rows == newValue.length, "Row counts must match");

    for (int r = 0; r < rows; r++) {
      final Float64List currentRow = currentMatrix[r];
      final Float64List newRow = newValue[r];
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
