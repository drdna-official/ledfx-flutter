import 'package:flutter/foundation.dart';
import 'types.dart';
import 'utils.dart';

class Filterbank {
  final FilterBankData filterBank;
  Filterbank(int noFilters, int winSize)
    : assert(noFilters > 0, "noFilters must be > 0"),
      assert(winSize > 0, "winSize must be > 0"),
      filterBank = FilterBankData.create(noFilters, winSize);

  void process(ComplexVector input, Float32List output) {
    final int len = input.getLength();
    final FloatVector temp = FloatVector.create(len);
    processNoAlloc(input, output, temp);
  }

  void processNoAlloc(ComplexVector input, Float32List output, FloatVector normBuffer) {
    final int len = input.getLength();
    // copy input to temp
    for (int i = 0; i < len; i++) {
      normBuffer.set(i, input.getNorm(i));
    }
    // adjust power
    if (filterBank.getPower() != 1.0) {
      normBuffer.setPower(filterBank.getPower());
    }
    filterBank.matrixMultiply(normBuffer, output);
  }

  int setTriangleBandsF32({required FloatVector freqs, required int sampleRate}) {
    final int nFilters = filterBank.getFilterRow();
    final int winSize = filterBank.getFilterCol();

    // freqs define the bands of triangular overlapping windows.
    //  throw a warning if filterbank object fb is too short.
    if (freqs.getLength() - 2 > nFilters) {
      debugPrint('WARN: not enough filters. allocated $nFilters but requested ${freqs.getLength() - 2}');
    }
    if (freqs.getLength() - 2 < nFilters) {
      debugPrint('WARN: too many filters. allocated $nFilters but requested ${freqs.getLength() - 2}');
    }

    for (int i = 0; i < freqs.getLength(); i++) {
      if (freqs.get(i) < 0) {
        debugPrint('ERROR: freqs must contain only positive values.');
        return -1;
      } else if (freqs.get(i) > sampleRate / 2) {
        debugPrint('WARN: freqs should contain only values < samplerate / 2.');
      } else if (i > 0 && freqs.get(i) < freqs.get(i - 1)) {
        debugPrint(
          'ERROR: freqs should be a list of frequencies sorted from low to high, but freq[${i}] < freq[${i - 1}]',
        );
        return -1;
      } else if (i > 0 && freqs.get(i) == freqs.get(i - 1)) {
        debugPrint('WARN: set_triangle_bands received a list with twice the frequency ${freqs.get(i)}');
      }
    }

    // lower/center/upper frequency for each triangle
    final FloatVector lowerFreqs = FloatVector.create(nFilters);
    final FloatVector upperFreqs = FloatVector.create(nFilters);
    final FloatVector centerFreqs = FloatVector.create(nFilters);

    // Height if each triangle
    final FloatVector triangleHeights = FloatVector.create(nFilters);

    // FFT frequencies
    final FloatVector fftFreqs = FloatVector.create(winSize);

    // fill lower/center/upper frequencies
    for (int i = 0; i < nFilters; i++) {
      lowerFreqs.set(i, freqs.get(i));
      centerFreqs.set(i, freqs.get(i + 1));
      upperFreqs.set(i, freqs.get(i + 2));
    }

    // Calculate height of each triangle so that each triangle has unit area
    if (filterBank.getNorm() == 1.0) {
      for (int i = 0; i < nFilters; i++) {
        triangleHeights.set(i, 2.0 / (upperFreqs.get(i) - lowerFreqs.get(i)));
      }
    } else {
      for (int i = 0; i < nFilters; i++) {
        triangleHeights.set(i, 1.0);
      }
    }
    // fill fft_freqs lookup table, which assigns the frequency in hz to each bin
    for (int i = 0; i < winSize; i++) {
      fftFreqs.set(i, binToFreq(i, sampleRate, (winSize - 1) * 2));
    }

    // reset filterbank
    filterBank.clear();

    // build filter table
    for (int i = 0; i < nFilters; i++) {
      // skip first
      int bin = 0;
      for (bin = 0; bin < winSize - 1; bin++) {
        if (fftFreqs.get(bin) <= lowerFreqs.get(i) && fftFreqs.get(bin + 1) > lowerFreqs.get(i)) {
          bin++;
          break;
        }
      }

      // compute positive slope
      final double riseInc = triangleHeights.get(i) / (centerFreqs.get(i) - lowerFreqs.get(i));

      // compute coeff for positive slope
      for (; bin < winSize - 1; bin++) {
        filterBank.set(i, bin, (fftFreqs.get(bin) - lowerFreqs.get(i)) * riseInc);

        if (fftFreqs.get(bin + 1) >= centerFreqs.get(i)) {
          bin++;
          break;
        }
      }

      // compute negative slope
      final double downInc = triangleHeights.get(i) / (upperFreqs.get(i) - centerFreqs.get(i));

      // compute coeff for negative slope
      for (; bin < winSize - 1; bin++) {
        filterBank.set(i, bin, filterBank.get(i, bin) + (upperFreqs.get(i) - fftFreqs.get(bin)) * downInc);
        if (filterBank.get(i, bin) < 0) {
          filterBank.set(i, bin, 0);
        }
        if (fftFreqs.get(bin + 1) >= upperFreqs.get(i)) {
          break;
        }
      }
    }

    return 0;
  }
}
