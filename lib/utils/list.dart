import 'dart:math';
import 'dart:typed_data';

extension type NumListExtension<T extends num>(List<T> _) implements List<T> {
  /// Unified factory for both int and double lists
  factory NumListExtension.equallySpaced(T start, T end, int count) {
    if (count <= 0) return NumListExtension<T>([]);
    if (count == 1) return NumListExtension<T>([start]);

    final double step = (end.toDouble() - start.toDouble()) / (count - 1);

    return NumListExtension<T>(
      List<T>.generate(count, (i) {
        final val = start.toDouble() + (i * step);
        // Cast back to T (int or double) based on the generic type
        return (T == int ? val.toInt() : val) as T;
      }),
    );
  }
}

extension NumListExt<T extends num> on List<T> {
  /// Returns the maximum value, or 0 (as T) if the list is empty.
  T maxOrZero() {
    if (isEmpty) {
      // Returns 0 as an int or 0.0 as a double based on the list type
      return (T == double ? 0.0 : 0) as T;
    }
    return reduce(max);
  }
}

extension ListExtension<T> on List<T> {
  // in-place copy. the source and this(destination) must have same length
  void copyFromList(List<T> source) {
    if (length != source.length) {
      throw ArgumentError('Source and destination lists must have the same length for in-place copy.');
    }
    for (int i = 0; i < source.length; i++) {
      this[i] = source[i];
    }
  }

  /// Shifts elements in-place by [offset].
  /// Positive moves right, negative moves left.
  void roll(int offset) {
    if (isEmpty) return;

    // Normalize offset to stay within bounds [0, length)
    int shift = offset % length;
    if (shift < 0) shift += length;
    if (shift == 0) return;

    void reverseRange(int start, int end) {
      while (start < end) {
        T temp = this[start];
        this[start] = this[end];
        this[end] = temp;
        start++;
        end--;
      }
    }

    // Triple-reverse algorithm for in-place rotation:
    // 1. Reverse the entire list
    reverseRange(0, length - 1);
    // 2. Reverse the first part (up to shift)
    reverseRange(0, shift - 1);
    // 3. Reverse the remaining part
    reverseRange(shift, length - 1);
  }

  /// Returns a slice of the list from [start] to [stop] by [step].
  List<T> slice({int? start, int? stop, int? step = 1}) {
    if (step == 0) throw ArgumentError('Step cannot be zero.');

    final int n = length;
    final int s = step ?? 1;

    // 1. Handle defaults based on step direction
    int begin = start ?? (s > 0 ? 0 : n - 1);
    int end = stop ?? (s > 0 ? n : -1);

    // 2. Normalize negative indices
    if (begin < 0) begin += n;
    if (end < 0) end += n;

    // 3. Clamp bounds
    if (s > 0) {
      if (begin < 0) begin = 0;
      if (end > n) end = n;
      if (begin >= end) return <T>[];
    } else {
      if (begin >= n) begin = n - 1;
      if (end < -1) end = -1;
      if (begin <= end) return <T>[];
    }

    // 4. Generate result
    final List<T> result = <T>[];
    int i = begin;

    if (s > 0) {
      while (i < end) {
        result.add(this[i]);
        i += s;
      }
    } else {
      while (i > end) {
        result.add(this[i]);
        i += s;
      }
    }

    return result;
  }
}

extension type InterpList(List<double> _) implements List<double> {
  /// Factory for linear interpolation (equivalent to np.interp)
  /// [x] is the new coordinate sequence, [xp] is original coordinates, [fp] is original values.
  factory InterpList.linear(List<double> x, List<double> xp, List<double> fp) {
    if (fp.isEmpty) return InterpList([]);
    if (fp.length == 1) return InterpList(List.filled(x.length, fp[0]));

    final int nXp = xp.length;
    final double xpStart = xp[0];
    final double xpStep = nXp > 1 ? xp[1] - xp[0] : 1.0;

    final result = List<double>.generate(x.length, (index) {
      final double targetX = x[index];

      // Calculate fractional index
      final double indexF = (targetX - xpStart) / xpStep;
      final int i = indexF.floor();

      // Clamping bounds
      if (i < 0) return fp[0];
      if (i >= nXp - 1) return fp[nXp - 1];

      // Linear interpolation: y = y0 + (y1 - y0) * (x - x0) / (x1 - x0)
      final double x0 = xp[i];
      final double x1 = xp[i + 1];
      final double y0 = fp[i];
      final double y1 = fp[i + 1];

      return y0 + (y1 - y0) * (targetX - x0) / (x1 - x0);
    });

    return InterpList(result);
  }
}

List<Uint8List> repeatAndTruncatePixels(List<Uint8List> effectivePixels, int groupSize, int pixelCount) {
  if (effectivePixels.isEmpty || groupSize <= 0) {
    return [];
  }
  List<Uint8List> repeatedPixels = [];

  // Iterate through each row in the original array
  for (final Uint8List row in effectivePixels) {
    // Repeat the current row 'groupSize' times
    for (int i = 0; i < groupSize; i++) {
      repeatedPixels.add(row);
    }
  }

  // Truncation
  // Slice the resulting array to only keep the first 'pixelCount' rows.
  int actualLength = repeatedPixels.length;
  if (pixelCount >= actualLength) {
    // If pixelCount is larger than the repeated array size, return the full repeated array.
    return repeatedPixels;
  } else {
    // Return only the first 'pixelCount' rows.
    return repeatedPixels.sublist(0, pixelCount);
  }
}
