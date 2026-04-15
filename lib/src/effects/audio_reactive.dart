import 'dart:typed_data';

import 'package:ledfx/src/audio/audio.dart';
import 'package:ledfx/src/effects/effect.dart';
import 'package:ledfx/src/virtual.dart';
import 'package:ledfx/utils/utils.dart';

import '../audio/mel_utils.dart';

mixin AudioReactiveEffect on Effect {
  AudioAnalysisSource? audio;

  @override
  void activate(Virtual virtual) {
    super.activate(virtual);
    ledfx.audioSource ??= AudioAnalysisSource(ledfx: ledfx);
    audio = ledfx.audioSource;
    ledfx.audioSource!.subscribe(_audioDataUpdated);
  }

  @override
  void deactivate() {
    if (audio != null) {
      audio!.unsubscribe(_audioDataUpdated);
    }
    super.deactivate();
  }

  MatrixExpFilter createFilter(double alphaDecay, double alphaRise) {
    return MatrixExpFilter(alphaDecay: alphaDecay, alphaRise: alphaRise);
  }

  void _audioDataUpdated() {
    if (isActive && audio != null) audioDataUpdated(audio!);
  }

  void audioDataUpdated(AudioAnalysisSource audio);

  void clearMelbankFreqCache() {
    _cachedSelectedMelbank = null;
    _cachedMelbankMinIdx = null;
    _cachedMelbankMaxIdx = null;
    _cachedInputMelLength = null;
  }

  int? _cachedSelectedMelbank;
  int get selectedMelbank => () {
    if (_cachedSelectedMelbank != null) return _cachedSelectedMelbank!;
    if (audio == null) throw Exception("AudioAnalysisSource not initiated");
    if (virtual == null) throw Exception("No Virtual set for the device");
    _cachedSelectedMelbank = audio!.melbanks.melbankConfig.maxFreqs.indexWhere((freq) => freq >= virtual!.freqRange.$2);
    if (_cachedSelectedMelbank == -1) {
      _cachedSelectedMelbank = audio!.melbanks.melbankConfig.maxFreqs.length;
    }
    return _cachedSelectedMelbank!;
  }();

  int? _cachedMelbankMinIdx;
  int get melbankMinIdx => () {
    if (_cachedMelbankMinIdx != null) return _cachedMelbankMinIdx!;
    if (audio == null) throw Exception("AudioAnalysisSource not initiated");
    if (virtual == null) throw Exception("No Virtual set for the device");
    _cachedMelbankMinIdx = audio!.melbanks.melbankProcessors[selectedMelbank].melbankFreqs.indexWhere(
      (freq) => freq >= virtual!.freqRange.$1,
    );
    return _cachedMelbankMinIdx!;
  }();

  int? _cachedMelbankMaxIdx;
  int get melbankMaxIdx => () {
    if (_cachedMelbankMaxIdx != null) return _cachedMelbankMaxIdx!;
    if (audio == null) throw Exception("AudioAnalysisSource not initiated");
    if (virtual == null) throw Exception("No Virtual set for the device");
    _cachedMelbankMaxIdx = audio!.melbanks.melbankProcessors[selectedMelbank].melbankFreqs.indexWhere(
      (freq) => freq >= virtual!.freqRange.$2,
    );
    if (_cachedMelbankMaxIdx == -1) {
      _cachedMelbankMaxIdx = audio!.melbanks.melbankProcessors[selectedMelbank].melbankFreqs.length;
    }
    return _cachedMelbankMaxIdx!;
  }();

  int? _cachedInputMelLength;
  int get inputMelLength => () {
    if (_cachedInputMelLength != null) return _cachedInputMelLength!;
    _cachedInputMelLength = melbankMaxIdx - melbankMinIdx;
    return _cachedInputMelLength!;
  }();

  static final Map<int, List<Float32List>> _linspaceCache = {};
  static const int _cacheMaxSize = 16;
  // Equivalent to Python's _melbank_interp_linspaces(self, size)
  List<Float32List> getMelbankInterpLinspaces(int size) {
    // Check the cache first (Memoization)
    if (_linspaceCache.containsKey(size)) {
      return _linspaceCache[size]!;
    }

    // 2. NumPy linspace conversion
    // old = np.linspace(0, 1, self._input_mel_length)
    final List<double> old = NumListExtension.equallySpaced(0.0, 1.0, inputMelLength);

    // new = np.linspace(0, 1, size)
    final List<double> newArr = NumListExtension.equallySpaced(0.0, 1.0, size);

    // 3. Store and Return
    // Return (new, old)
    final List<Float32List> result = [Float32List.fromList(newArr), Float32List.fromList(old)];

    // Add to cache (Basic LRU simulation: If size is exceeded, clear all for simplicity)
    if (_linspaceCache.length >= _cacheMaxSize) {
      _linspaceCache.clear();
    }
    _linspaceCache[size] = result;

    return result;
  }

  List<double> melbank({bool filtered = false, int? size}) {
    if (audio == null) throw Exception("AudioAnalysisSource not set");
    final melbank = (filtered)
        ? audio!.melbanks.melbanksFiltered[selectedMelbank].getRange(melbankMinIdx, melbankMaxIdx).toList()
        : audio!.melbanks.melbanks[selectedMelbank].getRange(melbankMinIdx, melbankMaxIdx).toList();

    if (size != null && inputMelLength != size) {
      List<List<double>> linspaces = getMelbankInterpLinspaces(size);
      List<double> newArr = linspaces[0];
      List<double> oldArr = linspaces[1];
      return InterpList.linear(newArr, oldArr, melbank);
    } else {
      return melbank;
    }
  }

  /// Returns the melbank in three parts: lows, mids, and highs.
  List<List<double>> melbankThirds({bool filtered = false, int? size}) {
    // melbank = self.melbank(**kwargs)
    final List<double> melbank = this.melbank(filtered: filtered, size: size);

    // mel_length = len(melbank)
    final int melLength = melbank.length;

    final List<int> splits = [
      (0.2 * melLength).toInt(), // End of Lows, Start of Mids
      (0.5 * melLength).toInt(), // End of Mids, Start of Highs
    ];

    final int split1 = splits[0]; // Index 0 to split1-1 is Lows
    final int split2 = splits[1]; // Index split1 to split2-1 is Mids

    // 1. Lows (0% to 20%)
    final List<double> lows = melbank.sublist(0, split1);

    // 2. Mids (20% to 50%)
    final List<double> mids = melbank.sublist(split1, split2);

    // 3. Highs (50% to 100%)
    final List<double> highs = melbank.sublist(split2, melLength);

    return [lows, mids, highs];
  }
}
