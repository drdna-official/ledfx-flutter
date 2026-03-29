// ignore_for_file: constant_identifier_names

import 'dart:ffi' as ffi;
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'aubio_bindings.dart'; // Updated import path

enum ResamplerType {
  SRC_SINC_BEST_QUALITY(0),
  SRC_SINC_MEDIUM_QUALITY(1),
  SRC_SINC_FASTEST(2),
  SRC_ZERO_ORDER_HOLD(3),
  SRC_LINEAR(4);

  final int value;
  const ResamplerType(this.value);
}

/// Main aubio library class for audio analysis
///
/// This class provides access to aubio's audio analysis capabilities through
/// a high-level Dart API using FFI.
class Aubio {
  static AubioBindings? _bindings;
  static ffi.DynamicLibrary? _dylib;

  /// Initialize the aubio library
  ///
  /// This must be called before using any aubio functionality.
  /// The library will be loaded automatically based on the platform.
  static AubioBindings get bindings {
    if (_bindings != null) return _bindings!;

    _dylib = _loadLibrary();
    _bindings = AubioBindings(_dylib!);
    return _bindings!;
  }

  /// Load the native aubio library for the current platform
  static ffi.DynamicLibrary _loadLibrary() {
    const libName = 'aubio';

    if (Platform.isMacOS || Platform.isIOS) {
      return ffi.DynamicLibrary.open('lib$libName.dylib');
    } else if (Platform.isAndroid || Platform.isLinux) {
      return ffi.DynamicLibrary.open('lib$libName.so');
    } else if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('$libName.dll');
    } else {
      throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
    }
  }

  /// Cleanup resources
  static void dispose() {
    _bindings = null;
    _dylib = null;
  }

  /// Get the version of the aubio library
  static String getVersion() {
    return '0.4.9';
  }

  static Pointer<aubio_filter_t> digitalFilter(int order) {
    return bindings.new_aubio_filter(order);
  }

  static Pointer<aubio_filterbank_t> createFilterBank(int filterNumber, int windowSize) {
    return bindings.new_aubio_filterbank(filterNumber, windowSize);
  }

  static Pointer<aubio_pvoc_t> createPhaseVocoder(int windowSize, int hopSize) {
    return bindings.new_aubio_pvoc(windowSize, hopSize);
  }

  static Pointer<aubio_resampler_t> createResampler(ResamplerType type, int inSampleRate, int outSampleRate) {
    return bindings.new_aubio_resampler(outSampleRate / inSampleRate, type.value);
  }

  static void deletePhaseVocoder(Pointer<aubio_pvoc_t> pvoc) {
    bindings.del_aubio_pvoc(pvoc);
  }

  static int getPhaseVocoderWindowSize(Pointer<aubio_pvoc_t> pvoc) {
    return bindings.aubio_pvoc_get_win(pvoc);
  }

  static int getPhaseVocoderHopSize(Pointer<aubio_pvoc_t> pvoc) {
    return bindings.aubio_pvoc_get_win(pvoc);
  }

  static bool setPhaseVocoderWindow(Pointer<aubio_pvoc_t> pvoc, String windowType) {
    final windowPtr = windowType.toNativeUtf8();
    final result = bindings.aubio_pvoc_set_window(pvoc, windowPtr.cast<Char>()) == 0;
    calloc.free(windowPtr);
    return result;
  }

  // Phase vocoder analysis (time -> frequency domain)
  static Pointer<cvec_t> phaseVocoderAnalysis(Pointer<aubio_pvoc_t> pvoc, Float32List audioInput, int windowSize) {
    final inputVec = createFvecFromFloat32List(audioInput);
    final fftGrain = bindings.new_cvec(windowSize);

    bindings.aubio_pvoc_do(pvoc, inputVec, fftGrain);

    bindings.del_fvec(inputVec);
    return fftGrain; // Caller must free this
  }

  /// Helper to copy between two native fvec_t buffers
  static void copyFvec(Pointer<fvec_t> src, Pointer<fvec_t> dst, int length) {
    final srcData = bindings.fvec_get_data(src);
    final dstData = bindings.fvec_get_data(dst);
    for (int i = 0; i < length; i++) {
      dstData[i] = srcData[i];
    }
  }

  /// Helper to zero a native fvec_t
  static void zeroFvec(Pointer<fvec_t> vec) {
    bindings.fvec_zeros(vec);
  }

  /// Helper to copy Float32List into an existing fvec_t
  static void copyToFvec(Float32List data, Pointer<fvec_t> vec) {
    final ptr = bindings.fvec_get_data(vec);
    for (int i = 0; i < data.length; i++) {
      ptr[i] = data[i];
    }
  }

  static void copyFromFvec(Pointer<fvec_t> vec, Float32List data) {
    final ptr = bindings.fvec_get_data(vec);
    for (int i = 0; i < data.length; i++) {
      data[i] = ptr[i];
    }
  }

  // Phase vocoder synthesis (frequency -> time domain)
  static Float32List phaseVocoderSynthesis(Pointer<aubio_pvoc_t> pvoc, Pointer<cvec_t> fftGrain, int hopSize) {
    final outputVec = bindings.new_fvec(hopSize);

    bindings.aubio_pvoc_rdo(pvoc, fftGrain, outputVec);

    // Convert to Dart Float32List
    final result = Float32List(hopSize);
    for (int i = 0; i < hopSize; i++) {
      result[i] = bindings.fvec_get_sample(outputVec, i);
    }

    bindings.del_fvec(outputVec);
    return result;
  }

  // Extract magnitude and phase from complex vector
  static (Float32List, Float32List) extractMagnitudePhase(Pointer<cvec_t> fftGrain, int windowSize) {
    final length = (windowSize ~/ 2) + 1;
    final magnitudes = Float32List(length);
    final phases = Float32List(length);

    for (int i = 0; i < length; i++) {
      magnitudes[i] = bindings.cvec_norm_get_sample(fftGrain, i);
      phases[i] = bindings.cvec_phas_get_sample(fftGrain, i);
    }

    return (magnitudes, phases);
  }

  // Set magnitude and phase in complex vector
  static void setMagnitudePhase(Pointer<cvec_t> fftGrain, Float32List magnitudes, Float32List phases) {
    final length = magnitudes.length;
    for (int i = 0; i < length; i++) {
      bindings.cvec_norm_set_sample(fftGrain, magnitudes[i], i);
      bindings.cvec_norm_set_sample(fftGrain, phases[i], i);
    }
  }

  // Create and manage complex vectors
  static Pointer<cvec_t> createComplexVector(int length) {
    return bindings.new_cvec(length);
  }

  static void deleteComplexVector(Pointer<cvec_t> cvec) {
    bindings.del_cvec(cvec);
  }

  // Onset detection functionality
  static Pointer<aubio_onset_t> createOnset(String method, int bufSize, int hopSize, int sampleRate) {
    final methodPtr = method.toNativeUtf8();
    final onset = bindings.new_aubio_onset(methodPtr.cast<Char>(), bufSize, hopSize, sampleRate);
    calloc.free(methodPtr);
    return onset;
  }

  static void deleteOnset(Pointer<aubio_onset_t> onset) {
    bindings.del_aubio_onset(onset);
  }

  static double detectOnset(Pointer<aubio_onset_t> onset, Float32List audioData) {
    final inputVec = createFvecFromFloat32List(audioData);
    final outputVec = bindings.new_fvec(1);

    bindings.aubio_onset_do(onset, inputVec, outputVec);
    final result = bindings.fvec_get_sample(outputVec, 0);

    bindings.del_fvec(inputVec);
    bindings.del_fvec(outputVec);

    return result;
  }

  // Pitch detection functionality
  static Pointer<aubio_pitch_t> createPitch(String method, int bufSize, int hopSize, int sampleRate) {
    final methodPtr = method.toNativeUtf8();
    final pitch = bindings.new_aubio_pitch(methodPtr.cast<Char>(), bufSize, hopSize, sampleRate);
    calloc.free(methodPtr);
    return pitch;
  }

  static void deletePitch(Pointer<aubio_pitch_t> pitch) {
    bindings.del_aubio_pitch(pitch);
  }

  static double detectPitch(Pointer<aubio_pitch_t> pitch, Float32List audioData) {
    final inputVec = createFvecFromFloat32List(audioData);
    final outputVec = bindings.new_fvec(1);

    bindings.aubio_pitch_do(pitch, inputVec, outputVec);
    final result = bindings.fvec_get_sample(outputVec, 0);

    bindings.del_fvec(inputVec);
    bindings.del_fvec(outputVec);

    return result;
  }

  // Helper method to create fvec from Flutter data
  static Pointer<fvec_t> createFvecFromFloat32List(Float32List data) {
    final vec = bindings.new_fvec(data.length);

    for (int i = 0; i < data.length; i++) {
      bindings.fvec_set_sample(vec, data[i], i);
    }

    return vec;
  }

  static double dbSPL(Float32List inputFrame) {
    final int n = inputFrame.length;
    final ffi.Pointer<fvec_t> inputVec = bindings.new_fvec(n);
    try {
      final ptrIn = bindings.fvec_get_data(inputVec);
      for (var i = 0; i < n; i++) {
        ptrIn[i] = inputFrame[i];
      }
      return bindings.aubio_db_spl(inputVec);
    } finally {
      bindings.del_fvec(inputVec);
    }
  }
}

extension DigitalFilterExt on Pointer<aubio_filter_t> {
  void delete() {
    Aubio.bindings.del_aubio_filter(cast());
  }

  int setBiquad(double b0, double b1, double b2, double a1, double a2) {
    return Aubio.bindings.aubio_filter_set_biquad(cast(), b0, b1, b2, a1, a2);
  }

  Float32List? processAudioFrame(Float32List inputFrame) {
    final frameSize = inputFrame.length;
    // Create aubio fvec_t for input
    final inputVec = Aubio.bindings.new_fvec(frameSize);
    if (inputVec == ffi.nullptr) {
      return null;
    }
    // Create aubio fvec_t for output
    final outputVec = Aubio.bindings.new_fvec(frameSize);
    if (outputVec == ffi.nullptr) {
      Aubio.bindings.del_fvec(inputVec);
      return null;
    }

    try {
      // Get data pointers from fvec_t structures
      final inputData = Aubio.bindings.fvec_get_data(inputVec);
      final outputData = Aubio.bindings.fvec_get_data(outputVec);

      // Copy Float32List data to aubio input vector
      for (int i = 0; i < frameSize; i++) {
        inputData[i] = inputFrame[i];
      }

      // Process audio through the filter (out-of-place processing)
      Aubio.bindings.aubio_filter_do_outplace(cast(), inputVec, outputVec);

      // Create output Float32List and copy processed data
      final outputFrame = Float32List(frameSize);
      for (int i = 0; i < frameSize; i++) {
        outputFrame[i] = outputData[i];
      }

      return outputFrame;
    } catch (e) {
      return null;
    } finally {
      // Clean up aubio vectors
      Aubio.bindings.del_fvec(inputVec);
      Aubio.bindings.del_fvec(outputVec);
    }
  }
}

extension PhaseVocoderExt on Pointer<aubio_pvoc_t> {
  void delete() {
    Aubio.bindings.del_aubio_pvoc(cast());
  }

  int getWindowSize() {
    return Aubio.bindings.aubio_pvoc_get_win(cast());
  }

  int getHopSize() {
    return Aubio.bindings.aubio_pvoc_get_win(cast());
  }

  bool setWindow(String windowType) {
    final windowPtr = windowType.toNativeUtf8();
    final result = Aubio.bindings.aubio_pvoc_set_window(cast(), windowPtr.cast<Char>()) == 0;
    calloc.free(windowPtr);
    return result;
  }

  // Phase vocoder analysis (time -> frequency domain)
  Pointer<cvec_t> analyse(Float32List audioInput) {
    final inputVec = Aubio.createFvecFromFloat32List(audioInput);
    final fftGrain = Aubio.bindings.new_cvec(getWindowSize());
    Aubio.bindings.aubio_pvoc_do(cast(), inputVec, fftGrain);
    Aubio.bindings.del_fvec(inputVec);
    return fftGrain; // Caller must free this
  }

  /// Phase vocoder analysis using existing buffers (recommended for performance)
  void doAnalyse(Pointer<fvec_t> input, Pointer<cvec_t> output) {
    Aubio.bindings.aubio_pvoc_do(cast(), input, output);
  }

  // Phase vocoder synthesis (frequency -> time domain)
  Float32List synthesise(Pointer<cvec_t> fftGrain, int hopSize) {
    final outputVec = Aubio.bindings.new_fvec(hopSize);

    Aubio.bindings.aubio_pvoc_rdo(cast(), fftGrain, outputVec);

    // Convert to Dart Float32List
    final result = Float32List(hopSize);
    for (int i = 0; i < hopSize; i++) {
      result[i] = Aubio.bindings.fvec_get_sample(outputVec, i);
    }

    Aubio.bindings.del_fvec(outputVec);
    return result;
  }
}

extension CVecExt on Pointer<cvec_t> {
  void delete() {
    Aubio.bindings.del_cvec(cast());
  }
}

extension FilterbankExt on Pointer<aubio_filterbank_t> {
  void delete() {
    Aubio.bindings.del_aubio_filterbank(cast());
  }

  bool setTriangleBandsF32({required Float32List freqs, required int sampleRate}) {
    final int n = freqs.length;
    final ptrFreqs = Aubio.bindings.new_fvec(n);
    if (ptrFreqs == ffi.nullptr) {
      throw StateError('Could not allocate freq vector');
    }
    try {
      final data = Aubio.bindings.fvec_get_data(ptrFreqs);
      for (var i = 0; i < n; i++) {
        data[i] = freqs[i];
      }
      final res = Aubio.bindings.aubio_filterbank_set_triangle_bands(cast(), ptrFreqs, sampleRate.toDouble());
      return res == 0;
    } finally {
      Aubio.bindings.del_fvec(ptrFreqs);
    }
  }

  /// Process one FFT-magnitude frame (length fftSize/2+1) and returns
  /// a Float32List of length [nBands] with mel-energies.
  Float32List process(Pointer<cvec_t> freqDomain, int outLen) {
    final outVec = Aubio.bindings.new_fvec(outLen);
    // Run mel-filterbank
    Aubio.bindings.aubio_filterbank_do(cast(), freqDomain, outVec);
    // Read out mel-band energies
    final ptrOut = Aubio.bindings.fvec_get_data(outVec);
    final out = Float32List(outLen);
    for (var i = 0; i < outLen; i++) {
      out[i] = ptrOut[i];
    }
    Aubio.bindings.del_fvec(outVec);
    return out;
  }

  /// Mel-filterbank processing using existing buffer
  void doProcess(Pointer<cvec_t> freqDomain, Pointer<fvec_t> outVec) {
    Aubio.bindings.aubio_filterbank_do(cast(), freqDomain, outVec);
  }
}

extension ResamplerExt on Pointer<aubio_resampler_t> {
  void delete() {
    Aubio.bindings.del_aubio_resampler(cast());
  }

  Float32List process(Float32List frame, int outLen) {
    final outVec = Aubio.bindings.new_fvec(outLen);
    final inVec = Aubio.bindings.new_fvec(frame.length);

    // Get data pointers from fvec_t structures
    final inData = Aubio.bindings.fvec_get_data(inVec);
    final outData = Aubio.bindings.fvec_get_data(outVec);
    // Copy Float32List data to aubio input vector
    for (int i = 0; i < frame.length; i++) {
      inData[i] = frame[i];
    }

    // Process audio through the filter (out-of-place processing)
    Aubio.bindings.aubio_resampler_do(cast(), inVec, outVec);

    // Create output Float32List and copy processed data
    final outputFrame = Float32List(outLen);
    for (int i = 0; i < outLen; i++) {
      outputFrame[i] = outData[i];
    }

    Aubio.bindings.del_fvec(inVec);
    Aubio.bindings.del_fvec(outVec);

    return outputFrame;
  }

  /// Resample using existing buffers
  void doResample(Pointer<fvec_t> input, Pointer<fvec_t> output) {
    Aubio.bindings.aubio_resampler_do(cast(), input, output);
  }
}
