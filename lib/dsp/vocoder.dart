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
    // copy dataOld to data
    for (int i = 0; i < pvoc.end; i++) {
      pvoc.data.set(i, pvoc.dataOld.get(i));
    }
    // copy newData to dataOld
    for (int i = 0; i < pvoc.hopSize; i++) {
      pvoc.data.set(pvoc.end + i, newData.get(i));
    }
    // shift data
    for (int i = 0; i < pvoc.end; i++) {
      pvoc.dataOld.set(i, pvoc.data.get(i + pvoc.hopSize));
    }
  }

  void applyWeight() {
    assert(pvoc.w.getLength() == pvoc.data.getLength(), "weight length must match data length");
    for (int i = 0; i < pvoc.data.getLength(); i++) {
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
    // copy to output - phase
    if (fft.compSpec.get(0) < 0) {
      spectrumOut.setPhase(0, pi);
    } else {
      spectrumOut.setPhase(0, 0.0);
    }

    for (int i = 1; i < spectrumOut.getLength() - 1; i++) {
      spectrumOut.setPhase(i, atan2(fft.compSpec.get(fft.compSpec.getLength() - i), fft.compSpec.get(i)));
    }

    if (fft.compSpec.get(fft.compSpec.getLength() ~/ 2) < 0) {
      spectrumOut.setPhase(spectrumOut.getLength() - 1, pi);
    } else {
      spectrumOut.setPhase(spectrumOut.getLength() - 1, 0.0);
    }

    // copy to output - norm
    spectrumOut.setNorm(0, fft.compSpec.get(0).abs());
    for (int i = 1; i < spectrumOut.getLength() - 1; i++) {
      spectrumOut.setNorm(
        i,
        sqrt(pow(fft.compSpec.get(i), 2) + pow(fft.compSpec.get(fft.compSpec.getLength() - i), 2)),
      );
    }
    spectrumOut.setNorm(spectrumOut.getLength() - 1, fft.compSpec.get(fft.compSpec.getLength() ~/ 2).abs());
  }

  void processFFTComplex() {
    for (int i = 0; i < fft.winSize; i++) {
      fft.setIn(i, pvoc.data.get(i));
    }

    ooura_rdft(fft.winSize, 1, fft.dIN, fft.ip, fft.w);
    fft.compSpec.set(0, fft.getIn(0));
    fft.compSpec.set(fft.winSize ~/ 2, fft.getIn(1));
    for (int i = 1; i < fft.fftSize - 1; i++) {
      fft.compSpec.set(i, fft.getIn(2 * i));
      fft.compSpec.set(fft.winSize - i, -fft.getIn(2 * i + 1));
    }
  }
}
