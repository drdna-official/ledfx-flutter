import 'dart:math';
import 'dart:typed_data';

import 'package:ledfx/dsp/filterbank.dart';
import 'package:ledfx/dsp/types.dart';
import 'package:ledfx/src/core.dart';
import 'package:ledfx/src/audio/audio.dart';
import 'package:ledfx/src/audio/const.dart';
import 'package:ledfx/src/audio/mel_utils.dart';
import 'package:ledfx/utils/utils.dart';

class MelbankConfig {
  MelbankConfig({required this.name, this.maxFreq = MAX_FREQ, this.minFreq = MIN_FREQ});

  final String name;
  final int maxFreq;
  final int minFreq;
  late double peakIsolation;
  late MelbankFilterType filterType;
  late int samples;
  late List<int> maxFreqs;
}

enum MelbankFilterType { htk, slaney, custom }

// Creates a set of filterbanks to process FFT at different resolutions.
// A constant amount are used to ensure consistent performance.
// If each virtual had its own melbank, you could run into performance issues
// with a high number of virtuals.
class Melbanks {
  final LEDFx ledfx;
  final AudioAnalysisSource audio;

  final int samples;
  final double peakIsolation;
  final MelbankFilterType filterType;
  final List<int> maxFreqs;
  final int minFreq;

  late List<Map<String, dynamic>> melbankCollection;
  late List<Melbank> melbankProcessors;
  late MelbankConfig melbankConfig;

  late int melCount;
  late int melLength;

  late List<Float32List> melbanks;
  late List<Float32List> melbanksFiltered;
  late double minVolume;

  Melbanks({
    required this.ledfx,
    required this.audio,
    this.samples = 24,
    this.peakIsolation = 0.4,
    this.filterType = MelbankFilterType.custom,
    this.maxFreqs = MEL_MAX_FREQS,
    this.minFreq = MIN_FREQ,
  }) {
    melbankCollection = ledfx.config.melbankCollection ?? [];
    melbankProcessors = [];
    melbankConfig = MelbankConfig(name: "", maxFreq: MAX_FREQ)
      ..peakIsolation = peakIsolation
      ..filterType = filterType
      ..samples = (filterType == MelbankFilterType.slaney)
          ? 40 //Hard coded for slaney
          : samples
      ..maxFreqs = maxFreqs;

    if (melbankCollection.isEmpty) {
      for (var (i, freq) in maxFreqs.indexed) {
        melbankConfig = MelbankConfig(name: "Melbank $i", maxFreq: freq)
          ..peakIsolation = peakIsolation
          ..filterType = filterType
          ..samples = (filterType == MelbankFilterType.slaney)
              ? 40 //Hard coded for slaney
              : samples
          ..maxFreqs = maxFreqs;
        final melbank = Melbank(audio: audio, config: melbankConfig);
        melbankProcessors.add(melbank);
        melbankCollection.add({"id": generateId(melbank.config.name), "melbank_config": melbankConfig});
      }
    } else {
      for (var melbank in melbankCollection) {
        melbankConfig = (melbank["melbank_config"] as MelbankConfig)
          ..peakIsolation = peakIsolation
          ..filterType = filterType
          ..samples = (filterType == MelbankFilterType.slaney)
              ? 40 //Hard coded for slaney
              : samples
          ..maxFreqs = maxFreqs;
        melbankProcessors.add(Melbank(audio: audio, config: melbankConfig));
      }
    }

    ledfx.config.melbankConfig = melbankConfig;
    melCount = maxFreqs.length;
    melLength = melbankConfig.samples;

    melbanks = List<Float32List>.generate(melCount, (_) => Float32List(melLength));
    melbanksFiltered = List<Float32List>.generate(melCount, (_) => Float32List(melLength));

    minVolume = audio.minVolume;
  }

  execute() {
    final freqDomain = audio.freqDomain;
    final volumeThreshould = (audio.volume(filtered: true) > minVolume);

    if (volumeThreshould) {
      for (final (i, proc) in melbankProcessors.indexed) {
        proc.execute(freqDomain, melbanks[i], melbanksFiltered[i]);
      }
    } else {
      for (final melbank in melbanks) {
        melbank.fillRange(0, melbank.length, 0.0);
      }
      for (final melbank in melbanksFiltered) {
        melbank.fillRange(0, melbank.length, 0.0);
      }
    }
  }

  void dispose() {
    for (final proc in melbankProcessors) {
      proc.dispose();
    }
  }
}

// A single Melbank
class Melbank {
  final AudioAnalysisSource audio;
  final MelbankConfig config;

  late double powerFactor;
  late Filterbank filterBank;
  late Float32List melbankFreqsFloat;
  late Int32List melbankFreqs;

  late int lowsIndex;
  late int midsIndex;
  late int highsIndex;

  late NumExpFilter melGain;
  late ListExpFilter melSmoothing;
  late Float32ListExpFilter commonFilter;
  late ListExpFilter diffFilter;

  Melbank({required this.audio, required this.config}) {
    powerFactor = tan(0.5 * pi * (config.peakIsolation + 1) / 2);
    switch (config.filterType) {
      case MelbankFilterType.custom:
        final List<double> melbankMels = NumListExtension.equallySpaced(
          hzTOMel(config.minFreq.toDouble()),
          hzTOMel(config.maxFreq.toDouble()),
          config.samples + 2,
        );
        melbankFreqsFloat = Float32List.fromList(melbankMels.map((mel) => melTOhz(mel)).toList());

      case MelbankFilterType.htk:
        final List<double> melbankHTK = NumListExtension.equallySpaced(
          hzTOHTK(config.minFreq.toDouble()),
          hzTOHTK(config.maxFreq.toDouble()),
          config.samples + 2,
        );
        melbankFreqsFloat = Float32List.fromList(melbankHTK.map((mel) => hTKTOhz(mel)).toList());

      case MelbankFilterType.slaney:
        // Slaney frequencies are linear-log spaced where 133Hz to 1000Hz is linear
        // spaced and 1000Hz to 6000Hz is log spaced. It also produces a hardcoded
        // 40 samples.
        const double lowestFrequency = 133.33333333;
        const double linearSpacing = 66.66666666;
        const double logSpacing = 1.0711703;
        const int linearFilters = 13;
        const int logFilters = 27;

        final List<double> linearSpacedFreqs = List.generate(linearFilters, (i) => lowestFrequency + i * linearSpacing);

        final List<double> logSpacedFreqs = List.generate(
          logFilters,
          (i) => linearSpacedFreqs.last * pow(logSpacing, i + 1),
        );

        final List<double> centerFreqs = [...linearSpacedFreqs, ...logSpacedFreqs];

        // To create 40 triangle bands, we need 42 frequencies (start, centers, end)
        final double startFreq = lowestFrequency - linearSpacing;
        final double endFreq = centerFreqs.last * logSpacing;

        melbankFreqsFloat = Float32List.fromList([startFreq, ...centerFreqs, endFreq]);

        config.samples = 40;
    }

    filterBank = Filterbank(config.samples, FFT_SIZE);
    filterBank.setTriangleBandsF32(freqs: FloatVector.fromArray(melbankFreqsFloat), sampleRate: MIC_RATE);
    melbankFreqsFloat = melbankFreqsFloat.sublist(1, melbankFreqsFloat.length - 1);

    melbankFreqs = Int32List.fromList(melbankFreqsFloat.map((i) => i.toInt()).toList());

    //Find the indexes for each of the frequency ranges
    lowsIndex = midsIndex = highsIndex = 1;
    for (int i = 0; i < melbankFreqs.length; i++) {
      if (melbankFreqs.elementAt(i) < FREQ_RANGE_SIMPLE[LOWS_RANGE]!.$2) {
        lowsIndex = i + 1;
      }
      if (melbankFreqs.elementAt(i) < FREQ_RANGE_SIMPLE[MIDS_RANGE]!.$2) {
        midsIndex = i + 1;
      }
      if (melbankFreqs.elementAt(i) < FREQ_RANGE_SIMPLE[HIGHS_RANGE]!.$2) {
        highsIndex = i + 1;
      }
    }

    // setup some of the common filters
    melGain = NumExpFilter(alphaDecay: 0.01, alphaRise: 0.99);
    melSmoothing = ListExpFilter(alphaDecay: 0.7, alphaRise: 0.99);
    commonFilter = Float32ListExpFilter(alphaDecay: 0.99, alphaRise: 0.01);
    diffFilter = ListExpFilter(alphaDecay: 0.15, alphaRise: 0.99);
  }
  // computes the melbank curve for frequency domain .
  void execute(ComplexVector freqDomain, Float32List melbank, Float32List filteredMelbank) {
    // copyListContents(melbank, filterBank.process(freqDomain, melbank.length));
    filterBank.process(freqDomain, melbank);

    for (int i = 0; i < melbank.length; i++) {
      melbank[i] = pow(melbank[i], powerFactor).toDouble();
    }
    melGain.update(fastBlurArray(melbank, 1.0).maxOrZero());

    final double gainValue = melGain.value?.toDouble() ?? 0.0;
    for (int i = 0; i < melbank.length; i++) {
      // Check for near-zero division, which is crucial for stability
      if (gainValue.abs() > 1e-9) {
        melbank[i] /= gainValue;
      } else {
        melbank[i] = 0.0; // Prevent division by zero
      }
    }

    List<double> smoothedBanks = melSmoothing.update(melbank);
    melbank.copyFromList(smoothedBanks);

    commonFilter.update(melbank);

    List<double> differenceArray = List<double>.generate(melbank.length, (i) {
      return melbank[i] - commonFilter.value![i];
    });
    List<double> diffFiltered = diffFilter.update(differenceArray);
    filteredMelbank.copyFromList(diffFiltered);
  }

  void dispose() {
    // filterBank.delete();
  }
}

double hzTOMel(double freq) {
  return 3700.0 * (log(1 + (freq / 230.0)) / log(12));
}

double melTOhz(double mel) {
  return 230.0 * pow(12, (mel / 3700)).toDouble() - 230.0;
}

double hzTOHTK(double hz) {
  return 1127 * (log(1 + (hz / 700.0)));
}

double hTKTOhz(double mel) {
  return 700.0 * (pow(10, (mel / 1127)) - 1);
}

double hzTOSlaney(double hz) {
  if (hz < 0) return 0;
  const double linSpace = 3.0 / 200.0;
  const double splitHz = 1000.0;
  const double splitMel = splitHz * linSpace; // 15
  final double logSpace = 27.0 / log(6400.0 / 1000.0);

  if (hz < splitHz) {
    return hz * linSpace;
  } else {
    return splitMel + logSpace * log(hz / splitHz);
  }
}

double slaneyTOhz(double mel) {
  if (mel < 0) return 0;
  const double linSpace = 200.0 / 3.0;
  const double splitHz = 1000.0;
  const double splitMel = splitHz / linSpace; // 15
  final double logSpacing = pow(6400.0 / 1000.0, 1.0 / 27.0).toDouble();

  if (mel < splitMel) {
    return linSpace * mel;
  } else {
    return splitHz * pow(logSpacing, mel - splitMel);
  }
}
