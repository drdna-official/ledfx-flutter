import 'dart:math';

double binToFreq(int bin, int sampleRate, int fftSize) {
  return max(bin, 0) * sampleRate / fftSize;
}

bool isPowerOfTwo(int n) {
  return n > 0 && (n & (n - 1)) == 0;
}
