import 'dart:math';
import 'fft.dart';
import 'types.dart';

class PhaseVocoder {
  final PVOCData pvoc;
  final FFTData fft;

  PhaseVocoder(int winSize, int hopSize) : pvoc = PVOCData.create(winSize, hopSize), fft = FFTData.create(winSize);

  void analyze(FloatVector dataNew, ComplexVector fftGrain) {
    // Slide
    slide(dataNew);
    // Windowing
    applyWeight();
    // Shift
    shift();
    // FFT
    processFFT(fftGrain);
  }

  void slide(FloatVector newData) {
    final int end = pvoc.end;
    final int hopSize = pvoc.hopSize;
    // copy dataOld to data
    for (int i = 0; i < end; i++) {
      pvoc.data.set(i, pvoc.dataOld.get(i));
    }
    // copy newData to dataOld
    for (int i = 0; i < hopSize; i++) {
      pvoc.data.set(end + i, newData.get(i));
    }
    // shift data
    for (int i = 0; i < end; i++) {
      pvoc.dataOld.set(i, pvoc.data.get(i + hopSize));
    }
  }

  void applyWeight() {
    final int len = pvoc.data.getLength();
    for (int i = 0; i < len; i++) {
      pvoc.data.set(i, pvoc.data.get(i) * pvoc.w.get(i));
    }
  }

  void shift() {
    final half = pvoc.winSize ~/ 2;
    int start = half;
    if (2 * half < pvoc.winSize) {
      start++;
    }
    for (int i = 0; i < half; i++) {
      final temp = pvoc.data.get(i);
      pvoc.data.set(i, pvoc.data.get(i + start));
      pvoc.data.set(i + start, temp);
    }

    if (start != half) {
      for (int i = 0; i < half; i++) {
        final temp = pvoc.data.get(i + start);
        pvoc.data.set(i + start, pvoc.data.get(i + start - 1));
        pvoc.data.set(i + start - 1, temp);
      }
    }
  }

  void processFFT(ComplexVector spectrumOut) {
    processFFTComplex();

    final int outLen = spectrumOut.getLength();
    final int specLen = fft.compSpec.getLength();

    // copy to output - phase
    if (fft.compSpec.get(0) < 0) {
      spectrumOut.setPhase(0, pi);
    } else {
      spectrumOut.setPhase(0, 0.0);
    }

    for (int i = 1; i < outLen - 1; i++) {
      spectrumOut.setPhase(i, atan2(fft.compSpec.get(specLen - i), fft.compSpec.get(i)));
    }

    if (fft.compSpec.get(specLen ~/ 2) < 0) {
      spectrumOut.setPhase(outLen - 1, pi);
    } else {
      spectrumOut.setPhase(outLen - 1, 0.0);
    }

    // copy to output - norm
    spectrumOut.setNorm(0, fft.compSpec.get(0).abs());
    for (int i = 1; i < outLen - 1; i++) {
      final double real = fft.compSpec.get(i);
      final double imag = fft.compSpec.get(specLen - i);
      spectrumOut.setNorm(i, sqrt(real * real + imag * imag));
    }
    spectrumOut.setNorm(outLen - 1, fft.compSpec.get(specLen ~/ 2).abs());
  }

  void processFFTComplex() {
    for (int i = 0; i < fft.winSize; i++) {
      fft.setIn(i, pvoc.data.get(i));
    }

    oouraRdft(fft.winSize, 1, fft.dIN, fft.ip, fft.w);

    fft.compSpec.set(0, fft.getIn(0));
    fft.compSpec.set(fft.winSize ~/ 2, fft.getIn(1));
    for (int i = 1; i < fft.fftSize - 1; i++) {
      fft.compSpec.set(i, fft.getIn(2 * i));
      fft.compSpec.set(fft.winSize - i, -fft.getIn(2 * i + 1));
    }
  }
}
