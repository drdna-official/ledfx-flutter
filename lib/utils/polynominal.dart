import 'dart:math';

/// A minimal Polynomial class to mimic NumPy's np.polynomial.Polynomial.
class Polynomial {
  final List<double> coeffs; // Coefficients: [c0, c1, c2, ...] where c0 is constant

  const Polynomial(this.coeffs);

  /// Returns the polynomial evaluated at a given point x.
  double call(double x) {
    double result = 0.0;
    for (int i = 0; i < coeffs.length; i++) {
      result += coeffs[i] * pow(x, i);
    }
    return result;
  }

  /// Evaluates the polynomial over a list of x values.
  List<double> evaluate(List<double> x) {
    return x.map((val) => call(val)).toList();
  }

  /// Computes the derivative of the polynomial.
  Polynomial deriv() {
    if (coeffs.isEmpty || coeffs.length == 1) {
      return Polynomial([0.0]); // Derivative of constant is 0
    }
    List<double> dCoeffs = [];
    for (int i = 1; i < coeffs.length; i++) {
      dCoeffs.add(coeffs[i] * i.toDouble());
    }
    return Polynomial(dCoeffs);
  }

  /// Adds two polynomials.
  Polynomial operator +(Polynomial other) {
    int maxLen = max(coeffs.length, other.coeffs.length);
    List<double> newCoeffs = List.filled(maxLen, 0.0);

    for (int i = 0; i < maxLen; i++) {
      double c1 = i < coeffs.length ? coeffs[i] : 0.0;
      double c2 = i < other.coeffs.length ? other.coeffs[i] : 0.0;
      newCoeffs[i] = c1 + c2;
    }
    // Remove trailing zeros
    while (newCoeffs.isNotEmpty && newCoeffs.last == 0.0 && newCoeffs.length > 1) {
      newCoeffs.removeLast();
    }
    return Polynomial(newCoeffs);
  }

  /// Multiplies the polynomial by another polynomial.
  Polynomial operator *(Polynomial other) {
    int maxLen = coeffs.length + other.coeffs.length - 1;
    List<double> newCoeffs = List.filled(maxLen, 0.0);

    for (int i = 0; i < coeffs.length; i++) {
      for (int j = 0; j < other.coeffs.length; j++) {
        newCoeffs[i + j] += coeffs[i] * other.coeffs[j];
      }
    }
    return Polynomial(newCoeffs);
  }
}

/// Produces a 1D Gaussian or Gaussian-derivative filter kernel.
///
/// Args:
///   sigma (double): The standard deviation of the filter.
///   order (int): The derivative-order (0 for Gaussian, 1 for 1st order derivative, etc.).
///   arrayLen (int): The length of the array the kernel will be applied to.
///
/// Returns:
///   List`<double>` containing the filter kernel.
List<double> gaussianKernel1d(double sigma, int order, int arrayLen) {
  if (order < 0) {
    throw ArgumentError("Order must be non-negative");
  }

  // Trapping small sigma and calculating radius
  sigma = max(0.00001, sigma);

  // radius = max(1, int(round(4.0 * sigma)))
  int radius = max(1, (4.0 * sigma).round());

  // radius = min(int((array_len - 1) / 2), radius)
  radius = min(((arrayLen - 1) / 2).toInt(), radius);

  // radius = max(radius, 1)
  radius = max(radius, 1);

  // Error check (Radius will always be positive integer here)
  // if (!radius.isInteger || radius <= 0) { ... }

  // p = np.polynomial.Polynomial([0, 0, -0.5 / (sigma * sigma)])
  final double sigmaSq = sigma * sigma;
  final Polynomial p = Polynomial([0.0, 0.0, -0.5 / sigmaSq]);

  // x = np.arange(-radius, radius + 1)
  final kernelLen = 2 * radius + 1;
  final List<double> x = List.generate(kernelLen, (i) => (i - radius).toDouble());

  // phi_x = np.exp(p(x), dtype=np.double)
  final List<double> pX = p.evaluate(x);
  final List<double> phiX = pX.map((val) => exp(val)).toList();

  // phi_x /= phi_x.sum()
  final double sumPhiX = phiX.reduce((a, b) => a + b);
  if (sumPhiX == 0.0) {
    // Handle case where sum is zero (shouldn't happen with Gaussian)
    throw StateError("Normalization sum is zero.");
  }
  for (int i = 0; i < phiX.length; i++) {
    phiX[i] /= sumPhiX;
  }

  if (order > 0) {
    // q = np.polynomial.Polynomial([1])
    Polynomial q = const Polynomial([1.0]);

    // p_deriv = p.deriv()
    final Polynomial pDeriv = p.deriv();

    // Loop for derivative order
    for (int i = 0; i < order; i++) {
      // q = q.deriv() + q * p_deriv
      q = q.deriv() + (q * pDeriv);
    }

    // phi_x *= q(x)
    final List<double> qX = q.evaluate(x);
    for (int i = 0; i < phiX.length; i++) {
      phiX[i] *= qX[i];
    }
  }

  return phiX;
}

// 1D Convolution with mode="same"
List<double> convolveSame(List<double> array, List<double> kernel) {
  final int arrayLen = array.length;
  final int kernelLen = kernel.length;
  final int halfKernel = kernelLen ~/ 2;
  final List<double> result = List<double>.filled(arrayLen, 0.0);

  // Pad the array virtually for 'same' mode
  for (int i = 0; i < arrayLen; i++) {
    double sum = 0.0;
    for (int j = 0; j < kernelLen; j++) {
      // The array index to access, accounting for kernel offset
      final int arrayIndex = i - halfKernel + j;

      // Check bounds: equivalent to zero-padding outside the original array
      if (arrayIndex >= 0 && arrayIndex < arrayLen) {
        // Note: The kernel is typically flipped for standard mathematical convolution,
        // but NumPy's convolve handles this internally. For manual implementation,
        // we use the kernel in its calculated order.
        sum += array[arrayIndex] * kernel[kernelLen - 1 - j];
      }
    }
    result[i] = sum;
  }
  return result;
}

// Since the array length changes during padding, we need a separate
// convolveValid function to match the mode='valid' behavior.
List<double> convolveValid(List<double> array, List<double> kernel) {
  int arrayLen = array.length;
  int kernelLen = kernel.length;

  if (arrayLen < kernelLen) {
    // Valid mode requires the array to be at least as long as the kernel.
    return [];
  }

  int outputLen = arrayLen - kernelLen + 1;
  List<double> output = List<double>.filled(outputLen, 0.0);

  // Perform convolution in 'valid' mode
  for (int i = 0; i < outputLen; i++) {
    double sum = 0.0;
    // The kernel is often reversed in convolution.
    for (int j = 0; j < kernelLen; j++) {
      sum += array[i + j] * kernel[kernelLen - 1 - j];
    }
    output[i] = sum;
  }
  return output;
}
