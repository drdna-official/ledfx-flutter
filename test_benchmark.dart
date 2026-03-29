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
import './lib/dsp/resampler.dart' as dsp_resampler;
import './lib/ffi/aubio/aubio.dart';
import './lib/ffi/aubio/aubio_bindings.dart';
import './lib/dsp/db.dart';

void main() {
  for (int run = 1; run <= 5; run++) {
    print('\n========================================================');
    print('RUN $run / 5');
    print('========================================================');
    
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
    dartFilterBank.setTriangleBandsF32(freqs: FloatVector.fromArray(Float32List.fromList(freqs)), sampleRate: 44100);

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
      if (run == 1 && i < 10) {
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
      if (run == 1 && i < 10) {
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

    // --- RESAMPLER PARITY TEST ---
    final int testInLen = 512;
    final int testOutLen = 470;
    final testInput = Float32List(testInLen);
    for (int i = 0; i < testInLen; i++) {
        testInput[i] = sin(2 * pi * i * 1000.0 / 48000.0);
    }
    
    final dartResamplerTest = dsp_resampler.Resampler(dsp_resampler.ResamplerType.sincFastest, testInLen, testOutLen);
    final aubioResamplerTest = Aubio.createResampler(ResamplerType.SRC_SINC_FASTEST, 48000, 44100);
    
    final dartResampled = dartResamplerTest.process(testInput);
    final aubioResampled = aubioResamplerTest.process(testInput, testOutLen);
    
    double maxResampleDiff = 0.0;
    int maxDiffIndex = -1;
    int comparisonLen = 450; // Aubio stops generating around 450 due to 22-sample filter delay requirement!
    for (int i = 0; i < comparisonLen; i++) {
        final diff = (dartResampled[i] - aubioResampled[i]).abs();
        if (diff > maxResampleDiff) {
            maxResampleDiff = diff;
            maxDiffIndex = i;
        }
    }
    
    print('========================================================');
    print('RESAMPLER NUMERICAL PARITY (Sinc Fastest):');
    print('Max Sample Diff: $maxResampleDiff at index $maxDiffIndex');
    print('Dart value: ${dartResampled[maxDiffIndex]} | Aubio value: ${aubioResampled[maxDiffIndex]}');
    
    print('First 3 samples -> Dart: [${dartResampled[0]}, ${dartResampled[1]}, ${dartResampled[2]}] | Aubio: [${aubioResampled[0]}, ${aubioResampled[1]}, ${aubioResampled[2]}]');
    int lastIdx = testOutLen - 1;
    print('Last 3 samples  -> Dart: [${dartResampled[lastIdx-2]}, ${dartResampled[lastIdx-1]}, ${dartResampled[lastIdx]}] | Aubio: [${aubioResampled[lastIdx-2]}, ${aubioResampled[lastIdx-1]}, ${aubioResampled[lastIdx]}]');
    
    if (maxResampleDiff < 1e-4) {
        print('STATUS: SUCCESS (High Parity)');
    } else {
        print('STATUS: WARNING (Significant Divergence)');
    }
    print('========================================================');
    
    aubioResamplerTest.delete();

    // --- BENCHMARK ---
    const int numFrames = 10000;
    print('\nBENCHMARKING: Processing $numFrames frames ($hopSize samples each)...');

    // Generate a long random signal
    final random = Random();
    final audioData = Float32List(numFrames * hopSize);
    for (int i = 0; i < audioData.length; i++) {
      audioData[i] = random.nextDouble() * 2.0 - 1.0;
    }

    // Pre-allocate resources
    Pointer<fvec_t> aubioOutVec = Aubio.bindings.new_fvec(24);
    final FloatVector normBuffer = FloatVector.create(winSize ~/ 2 + 1);

    // 1. DART BENCHMARK
    final dartStopwatch = Stopwatch()..start();
    for (int f = 0; f < numFrames; f++) {
      final int offset = f * hopSize;
      // Efficiently copy slice using copyFrom
      dartInput.copyFrom(Float32List.sublistView(audioData, offset, offset + hopSize));

      dartFilter.process(dartInput, dartFiltered);
      dartPvoc.analyze(dartFiltered, dartFftGrain);
      dartFilterBank.processNoAlloc(dartFftGrain, dartMelbank, normBuffer);
    }
    dartStopwatch.stop();
    final double dartTotalMs = dartStopwatch.elapsedMicroseconds / 1000.0;

    // 2. AUBIO BENCHMARK
    final aubioStopwatch = Stopwatch()..start();
    for (int f = 0; f < numFrames; f++) {
      final int offset = f * hopSize;
      // Native copy
      final dataPtr = Aubio.bindings.fvec_get_data(aubioInputVec);
      for (int i = 0; i < hopSize; i++) {
        dataPtr[i] = audioData[offset + i];
      }

      Aubio.bindings.aubio_filter_do(aubioFilter, aubioInputVec);
      Aubio.bindings.aubio_pvoc_do(aubioPvoc, aubioInputVec, aubioFftGrain);
      Aubio.bindings.aubio_filterbank_do(aubioFilterBank, aubioFftGrain, aubioOutVec);
    }
    aubioStopwatch.stop();
    final double aubioTotalMs = aubioStopwatch.elapsedMicroseconds / 1000.0;

    print('========================================================');
    print('PERFORMANCE RESULTS ($numFrames frames):');
    print('Dart total time : ${dartTotalMs.toStringAsFixed(2)} ms (${(dartTotalMs / numFrames).toStringAsFixed(4)} ms/frame) | FPS: ${(numFrames * 1000 / dartTotalMs).toStringAsFixed(0)}');
    print('Aubio total time: ${aubioTotalMs.toStringAsFixed(2)} ms (${(aubioTotalMs / numFrames).toStringAsFixed(4)} ms/frame) | FPS: ${(numFrames * 1000 / aubioTotalMs).toStringAsFixed(0)}');
    print('Ratio (D/A)     : ${(dartTotalMs / aubioTotalMs).toStringAsFixed(2)}x');
    print('========================================================');

    // --- RESAMPLER BENCHMARK ---
    print('\nBENCHMARKING RESAMPLER: Processing $numFrames frames (48000 -> 44100)...');
    final int inLenResample = 512;
    final int outLenResample = 470; // 512 * 44100 / 48000 is ~470.4
    final resampleInputBuffer = Float32List(inLenResample);
    for (int i = 0; i < inLenResample; i++) {
      resampleInputBuffer[i] = random.nextDouble() * 2.0 - 1.0;
    }
    
    // Dart Resampler
    final dartResampler = dsp_resampler.Resampler(dsp_resampler.ResamplerType.sincFastest, inLenResample, outLenResample);
    
    // Aubio Native Resampler
    final aubioResampler = Aubio.createResampler(ResamplerType.SRC_SINC_FASTEST, 48000, 44100);
    
    // 1. DART RESAMPLER BENCHMARK
    final dartResamplerStopwatch = Stopwatch()..start();
    for (int f = 0; f < numFrames; f++) {
      dartResampler.process(resampleInputBuffer, outLenResample);
    }
    dartResamplerStopwatch.stop();
    final double dartResamplerTotalMs = dartResamplerStopwatch.elapsedMicroseconds / 1000.0;
    
    // 2. AUBIO RESAMPLER BENCHMARK
    final aubioResamplerStopwatch = Stopwatch()..start();
    for (int f = 0; f < numFrames; f++) {
      aubioResampler.process(resampleInputBuffer, outLenResample);
    }
    aubioResamplerStopwatch.stop();
    final double aubioResamplerTotalMs = aubioResamplerStopwatch.elapsedMicroseconds / 1000.0;

    print('========================================================');
    print('RESAMPLER PERFORMANCE RESULTS ($numFrames frames):');
    print('Dart Resampler total time : ${dartResamplerTotalMs.toStringAsFixed(2)} ms');
    print('Aubio Resampler total time: ${aubioResamplerTotalMs.toStringAsFixed(2)} ms');
    print('Ratio (D/A)               : ${(dartResamplerTotalMs / aubioResamplerTotalMs).toStringAsFixed(2)}x');
    print('========================================================');

    // --- DBSPL BENCHMARK ---
    print('\nBENCHMARKING DBSPL: Processing $numFrames frames...');
    final dbSPLInputBuffer = Float32List(hopSize);
    for (int i = 0; i < hopSize; i++) {
      dbSPLInputBuffer[i] = random.nextDouble() * 2.0 - 1.0;
    }
    
    // 1. DART DBSPL BENCHMARK
    final dartDBSPLStopwatch = Stopwatch()..start();
    double dartLastDb = 0;
    for (int f = 0; f < numFrames; f++) {
      dartLastDb = dbSPL(dbSPLInputBuffer);
    }
    dartDBSPLStopwatch.stop();
    final double dartDBSPLTotalMs = dartDBSPLStopwatch.elapsedMicroseconds / 1000.0;
    
    // 2. AUBIO DBSPL BENCHMARK
    final aubioDBSPLStopwatch = Stopwatch()..start();
    double aubioLastDb = 0;
    for (int f = 0; f < numFrames; f++) {
      aubioLastDb = Aubio.dbSPL(dbSPLInputBuffer);
    }
    aubioDBSPLStopwatch.stop();
    final double aubioDBSPLTotalMs = aubioDBSPLStopwatch.elapsedMicroseconds / 1000.0;

    print('========================================================');
    print('DBSPL PERFORMANCE RESULTS ($numFrames frames):');
    print('Dart dbSPL total time : ${dartDBSPLTotalMs.toStringAsFixed(2)} ms');
    print('Aubio dbSPL total time: ${aubioDBSPLTotalMs.toStringAsFixed(2)} ms');
    print('Ratio (D/A)           : ${(dartDBSPLTotalMs / aubioDBSPLTotalMs).toStringAsFixed(2)}x');
    print('========================================================');

    print('DBSPL NUMERICAL PARITY:');
    print('Dart value: $dartLastDb | Aubio value: $aubioLastDb');
    print('Diff: ${(dartLastDb - aubioLastDb).abs()}');
    print('========================================================');

    // Cleanup native resources
    aubioResampler.delete();
    Aubio.bindings.del_aubio_filter(aubioFilter);
    Aubio.bindings.del_fvec(aubioInputVec);
    Aubio.bindings.del_fvec(aubioOutVec);
    Aubio.deleteComplexVector(aubioFftGrain);
    Aubio.deletePhaseVocoder(aubioPvoc);
    aubioFilterBank.delete();
  }
}

double hzTOmatt(double freq) {
  return 3700.0 * (log(1 + (freq / 230.0)) / log(12));
}

double mattTOhz(double matt) {
  return 230.0 * pow(12, (matt / 3700)).toDouble() - 230.0;
}
