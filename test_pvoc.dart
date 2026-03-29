import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:ledfx/src/audio/const.dart';
import 'package:ledfx/src/audio/melbank.dart';
import 'package:ledfx/utils/list.dart';

import './lib/dsp/filterbank.dart';

import './lib/dsp/digital_filter.dart';
import './lib/dsp/types.dart';
import './lib/dsp/vocoder.dart';
import './lib/ffi/aubio/aubio.dart';
import './lib/ffi/aubio/aubio_bindings.dart';

void main() {
  int winSize = 512;
  int hopSize = 256;
  final config = MelbankConfig(name: "Melbank", maxFreq: 350)
    ..peakIsolation = 0.4
    ..coeffType = CoeffType.mattmel
    ..samples = 24
    ..maxFreqs = MEL_MAX_FREQS;

  final List<double> melbankMatt = NumListExtension.equallySpaced(
    hzTOmatt(config.minFreq.toDouble()),
    hzTOmatt(config.maxFreq.toDouble()),
    config.samples + 2,
  );

  // Initialize Dart Phase Vocoder
  PhaseVocoder dartPvoc = PhaseVocoder(winSize, hopSize);
  ComplexVector dartFftGrain = ComplexVector.create(winSize ~/ 2 + 1);

  // Initialize Aubio Phase Vocoder
  Pointer<aubio_pvoc_t> aubioPvoc = Aubio.createPhaseVocoder(winSize, hopSize);

  // Create a dummy audio input of length hopSize (e.g., a simple sine wave + noise)
  Float32List inputData = Float32List(hopSize);
  for (int i = 0; i < hopSize; i++) {
    inputData[i] = sin(2 * pi * i * 440.0 / 44100.0) + (i / hopSize) * 0.1;
  }

  // 1. Process via Dart Phase Vocoder (With DigitalFilter)
  FloatVector dartInput = FloatVector.create(hopSize);
  for (int i = 0; i < hopSize; i++) {
    dartInput.set(i, inputData[i]);
  }

  // Dart Pre-Emphasis
  DigitalFilter dartFilter = DigitalFilter(3);
  dartFilter.setBiquad(0.8268, -1.6536, 0.8268, -1.6536, 0.6536);
  FloatVector dartFiltered = FloatVector.create(hopSize);
  dartFilter.process(dartInput, dartFiltered);

  Filterbank dartFilterBank = Filterbank(24, winSize);
  final List<double> freqs = melbankMatt.map((mel) => mattTOhz(mel)).toList();
  dartFilterBank.setTriangleBandsF32(
    freqs: FloatVector.fromArray(Float32List.fromList(freqs)),
    sampleRate: 44100,
  );

  dartPvoc.analyze(dartFiltered, dartFftGrain);

  Float32List dartMelbank = Float32List(24);
  dartFilterBank.process(dartFftGrain, dartMelbank);

  // 2. Process via Aubio Phase Vocoder (With Native DigitalFilter)
  Pointer<aubio_filter_t> aubioFilter = Aubio.bindings.new_aubio_filter(3);
  Aubio.bindings.aubio_filter_set_biquad(aubioFilter, 0.8268, -1.6536, 0.8268, -1.6536, 0.6536);

  Pointer<fvec_t> aubioInputVec = Aubio.bindings.new_fvec(hopSize);
  for (int i = 0; i < hopSize; i++) {
    Aubio.bindings.fvec_set_sample(aubioInputVec, inputData[i], i);
  }

  // Apply native filter in-place
  Aubio.bindings.aubio_filter_do(aubioFilter, aubioInputVec);

  Pointer<cvec_t> aubioFftGrain = Aubio.bindings.new_cvec(winSize);
  Aubio.bindings.aubio_pvoc_do(aubioPvoc, aubioInputVec, aubioFftGrain);

  // Native Filterbank
  Pointer<aubio_filterbank_t> aubioFilterBank = Aubio.createFilterBank(24, winSize);
  aubioFilterBank.setTriangleBandsF32(freqs: Float32List.fromList(freqs), sampleRate: 44100);
  Float32List aubioMelbank = aubioFilterBank.process(aubioFftGrain, 24);

  var (aubioMags, aubioPhases) = Aubio.extractMagnitudePhase(aubioFftGrain, winSize);

  // Output comparison
  print('========================================================');
  print('COMPARING PHASE VOCODER OUTPUTS (Win: $winSize, Hop: $hopSize)');
  print('========================================================');
  double maxMagDiff = 0.0;
  double maxPhaseDiff = 0.0;
  int maxMagBin = 0;
  int maxPhaseBin = 0;

  for (int i = 0; i < dartFftGrain.getLength(); i++) {
    double dartMag = dartFftGrain.getNorm(i);
    double aubioMag = aubioMags[i];
    double dartPhase = dartFftGrain.getPhase(i);
    double aubioPhase = aubioPhases[i];

    double magDiff = (dartMag - aubioMag).abs();

    // Wrapped phase difference
    double phaseDiff = dartPhase - aubioPhase;
    while (phaseDiff > pi) phaseDiff -= 2 * pi;
    while (phaseDiff < -pi) phaseDiff += 2 * pi;
    phaseDiff = phaseDiff.abs();

    if (magDiff > maxMagDiff) {
      maxMagDiff = magDiff;
      maxMagBin = i;
    }
    if (phaseDiff > maxPhaseDiff) {
      maxPhaseDiff = phaseDiff;
      maxPhaseBin = i;
    }

    // Print first 10 elements to visually inspect
    if (i < 10) {
      print('Bin $i:');
      print(
        '  [Norm]  Dart: ${dartMag.toStringAsFixed(6)} | Aubio: ${aubioMag.toStringAsFixed(6)} | Diff: ${magDiff.toStringAsFixed(6)}',
      );
      print(
        '  [Phase] Dart: ${dartPhase.toStringAsFixed(6)} | Aubio: ${aubioPhase.toStringAsFixed(6)} | Diff: ${phaseDiff.toStringAsFixed(6)}',
      );
    }
  }

  print('========================================================');
  print('COMPARING MELBANK OUTPUTS (Bands: 24)');
  print('========================================================');
  double maxMelDiff = 0.0;
  int maxMelBin = 0;
  for (int i = 0; i < 24; i++) {
    double melDiff = (dartMelbank[i] - aubioMelbank[i]).abs();
    if (melDiff > maxMelDiff) {
      maxMelDiff = melDiff;
      maxMelBin = i;
    }
    if (i < 10) {
      print(
        'Band $i: Dart: ${dartMelbank[i].toStringAsFixed(6)} | Aubio: ${aubioMelbank[i].toStringAsFixed(6)} | Diff: ${melDiff.toStringAsFixed(6)}',
      );
    }
  }

  print('========================================================');
  print('MAX DIFFERENCES ACROSS ALL BINS/BANDS:');
  print('Max Magnitude Diff: $maxMagDiff (at Bin $maxMagBin)');
  print('Max Phase Diff    : $maxPhaseDiff (at Bin $maxPhaseBin)');
  print('Max Melbank Diff  : $maxMelDiff (at Band $maxMelBin)');
  print('========================================================');

  // Cleanup native resources
  Aubio.bindings.del_aubio_filter(aubioFilter);
  Aubio.bindings.del_fvec(aubioInputVec);
  Aubio.deleteComplexVector(aubioFftGrain);
  Aubio.deletePhaseVocoder(aubioPvoc);
  aubioFilterBank.delete();
}

double hzTOmatt(double freq) {
  return 3700.0 * (log(1 + (freq / 230.0)) / log(12));
}

double mattTOhz(double matt) {
  return 230.0 * pow(12, (matt / 3700)).toDouble() - 230.0;
}
