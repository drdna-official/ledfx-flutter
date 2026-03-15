import 'dart:typed_data';

List<Float64List> fillRainbow(List<Float64List> pixels, double initialHue, double deltaHue) {
  // The input 'pixels' array is used only to determine the final size (pixelCount).
  final int pixelCount = pixels.length;

  const double sat = 0.95;
  const double val = 1.0;

  // --- Create Hue Values (Equivalent to np.arange(...) ) ---

  List<double> hues = [];
  double currentHue = initialHue;

  // The loop runs exactly 'pixelCount' times, generating the precise number of hues needed.
  // This replaces np.arange(...) and the subsequent array slicing.
  for (int i = 0; i < pixelCount; i++) {
    hues.add(currentHue);
    currentHue += deltaHue;
  }

  // --- Convert to RGB ---
  // The hsvToRgb function is expected to return the final List<Float64List>
  // with dimensions [pixelCount, 3].
  return hsvToRgb(hues, sat, val);
}

/// Converts an array of Hues using provided saturation and value properties to an RGB array.
///
/// Args:
///   hues (List`<double>`): Array of hue values (0 to 1).
///   saturation (double between 0 and 1): The saturation.
///   value (double between 0 and 1): The value.
///
/// Returns:
///   List`<Float64List>`: An array of RGB values where each RGB value is in the range 0 to 255.
List<Float64List> hsvToRgb(List<double> hues, double saturation, double value) {
  if (hues.isEmpty) {
    return [];
  }

  int pixelCount = hues.length;
  List<Float64List> rgbArray = List.generate(pixelCount, (_) => Float64List(3));

  // The six possible values for R, G, B channels based on intermediate calculation
  // final double p = value * (1.0 - saturation);
  // final double q = value * (1.0 - saturation * 0.0); // f is 0 for i=0, q=v*(1-s*0)=v*(1-s)
  // final double t = value * (1.0 - saturation * 1.0); // 1-f is 0 for i=0, t=v*(1-s*1)=v*(1-s*f)

  // Pre-calculate the six intermediate values, which are constant for a given S and V
  // The six possibilities for each channel (value, q, p, p, t, value)
  // We use this structure to simulate np.choose.
  const int hueSections = 6;
  // final List<double> sectionValues = [
  //   value,
  //   value * (1.0 - saturation * 0.0), // Placeholder for q or t logic
  //   p,
  //   p,
  //   value * (1.0 - saturation * 0.0), // Placeholder for q or t logic
  //   value,
  // ];

  for (int idx = 0; idx < pixelCount; idx++) {
    double hue = hues[idx];

    // --- Intermediate Calculations (Vectorized in Python) ---

    // 1. hue_i = hue * 6
    double hueI = hue * 6.0;

    // 2. i = np.floor(hue_i).astype(int)
    int i = hueI.floor().toInt();

    // 3. f = hue_i - i
    double f = hueI - i;

    // Intermediate values for RGB conversion based on the fractional part 'f'.
    // NOTE: These must be calculated per pixel because they depend on 'f'.
    final double pPixel = value * (1.0 - saturation);
    final double qPixel = value * (1.0 - saturation * f);
    final double tPixel = value * (1.0 - saturation * (1.0 - f));

    // 4. i = i % 6 (Ensure that i values are within the range [0, 5])
    int section = i % hueSections;

    // --- Assigning RGB components (Equivalent to np.choose) ---

    // Define the color component sequences for the current pixel's section.
    // This replaces the complex np.choose logic.
    late double R, G, B;

    switch (section) {
      case 0: // R = V, G = T, B = P
        R = value;
        G = tPixel;
        B = pPixel;
        break;
      case 1: // R = Q, G = V, B = P
        R = qPixel;
        G = value;
        B = pPixel;
        break;
      case 2: // R = P, G = V, B = T
        R = pPixel;
        G = value;
        B = tPixel;
        break;
      case 3: // R = P, G = Q, B = V
        R = pPixel;
        G = qPixel;
        B = value;
        break;
      case 4: // R = T, G = P, B = V
        R = tPixel;
        G = pPixel;
        B = value;
        break;
      case 5: // R = V, G = P, B = Q
        R = value;
        G = pPixel;
        B = qPixel;
        break;
      default:
        // This case should be covered by i % 6, but included for robustness.
        R = 0.0;
        G = 0.0;
        B = 0.0;
    }

    // 5. Scale to 0-255 range and store (Equivalent to return rgb * 255)
    rgbArray[idx][0] = R * 255.0;
    rgbArray[idx][1] = G * 255.0;
    rgbArray[idx][2] = B * 255.0;
  }

  return rgbArray;
}
