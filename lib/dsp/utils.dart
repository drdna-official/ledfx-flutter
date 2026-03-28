import 'dart:math';

double binToFreq(int bin, int sampleRate, int fftSize) {
  return max(bin, 0) * sampleRate / fftSize;
}
