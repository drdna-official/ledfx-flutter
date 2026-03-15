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
class ExpFilter {
  // Constants for the smoothing factors
  final double alphaDecay;
  final double alphaRise;

  // The smoothed value (can hold a single number or a list/typed array)
  dynamic value;

  /// Constructor for ExpFilter.
  ///
  /// Throws an [ArgumentError] if the smoothing factors are out of the
  /// valid range (0.0 to 1.0, non-inclusive).
  ExpFilter({dynamic val, this.alphaDecay = 0.5, this.alphaRise = 0.5}) {
    if (alphaDecay <= 0.0 || alphaDecay >= 1.0) {
      throw ArgumentError("Invalid decay smoothing factor: must be between 0.0 and 1.0 (exclusive)");
    }
    if (alphaRise <= 0.0 || alphaRise >= 1.0) {
      throw ArgumentError("Invalid rise smoothing factor: must be between 0.0 and 1.0 (exclusive)");
    }
    value = val;
  }

  /// Updates the smoothed value with a new reading.
  ///
  /// The [value] parameter can be a single [double] or a [List<double>] (or a typed array).
  ///
  /// Returns the newly smoothed value.
  dynamic update(dynamic newValue) {
    // 1. Handle deferred initialization (if self.value is None)
    if (value == null) {
      value = newValue;
      return value;
    }

    // 2. Handle array/list update
    if (value is List<double> || value is Float64List || value is Float64List) {
      // Dart requires converting to a typed list for efficient element-wise operation
      final List<double> currentValueList = List<double>.from(value);
      final List<double> newValueList = List<double>.from(newValue);

      // Ensure lengths match to prevent errors
      if (currentValueList.length != newValueList.length) {
        throw ArgumentError("New value list must match the size of the current value list.");
      }

      final List<double> alphaList = [];

      for (int i = 0; i < currentValueList.length; i++) {
        // Calculate element-wise alpha
        if (newValueList[i] > currentValueList[i]) {
          alphaList.add(alphaRise); // rise smoothing
        } else {
          alphaList.add(alphaDecay); // decay smoothing
        }
      }

      // Perform element-wise exponential smoothing (value = alpha * value + (1.0 - alpha) * self.value)
      final List<double> smoothedList = List.generate(currentValueList.length, (i) {
        final double alpha = alphaList[i];
        final double current = currentValueList[i];
        final double new_ = newValueList[i];
        return alpha * new_ + (1.0 - alpha) * current;
      });

      // Update the internal value with the same type it started with
      if (value is Float64List) {
        value = Float64List.fromList(smoothedList);
      } else if (value is Float64List) {
        value = Float64List.fromList(smoothedList);
      } else {
        value = smoothedList;
      }

      return value;
    }
    // 3. Handle single number update (equivalent to the 'else' block)
    else if (value is num && newValue is num) {
      final double alpha;
      if (newValue > value) {
        alpha = alphaRise;
      } else {
        alpha = alphaDecay;
      }

      // Exponential smoothing formula
      value = alpha * newValue.toDouble() + (1.0 - alpha) * value.toDouble();
      return value;
    }

    // Handle unsupported type combinations
    throw ArgumentError(
      "Unsupported types for update: Current value is ${value.runtimeType}, New value is ${newValue.runtimeType}",
    );
  }
}
