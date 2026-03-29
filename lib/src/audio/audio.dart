import 'dart:async' show StreamSubscription, Timer;
import 'dart:math' show max, min;

import 'package:flutter/foundation.dart';
import 'package:ledfx/dsp/db.dart';
import 'package:ledfx/dsp/digital_filter.dart';
import 'package:ledfx/dsp/types.dart';
import 'package:ledfx/dsp/vocoder.dart';
import 'package:ledfx/dsp/resampler.dart';
import 'package:ledfx/platform_interface/audio_bridge.dart';
import 'package:ledfx/src/core.dart';
import 'package:ledfx/src/audio/const.dart';
import 'package:ledfx/src/audio/melbank.dart';
import 'package:ledfx/utils/utils.dart';

import 'mel_utils.dart';

abstract class AudioInputSource {
  final LEDFx ledfx;
  final int sampleRate;
  final int fftSize;
  final double minVolume;
  final Duration delay;

  AudioBridge? _audio;

  AudioInputSource({
    required this.ledfx,
    this.sampleRate = 60,
    this.fftSize = FFT_SIZE,
    this.minVolume = 0.2,
    this.delay = Duration.zero,
  });

  // List<AudioDevice>? audioDevices;
  int activeAudioDeviceIndex = 0;

  bool _audioStreamActive = false;
  StreamSubscription<RecordingEvent>? _streamSub;
  final List<VoidCallback> _callbacks = [];
  Timer? _timer;
  int _subscriberThreshould = 0;

  // Buffers
  late FloatVector _inputVec;
  late FloatVector _processedVec;
  late ComplexVector _freqDomain;
  ComplexVector get freqDomain => _freqDomain;

  late Float32List _rawAudioSample;
  late Float32List _processedAudioSample;
  Float32List audioSample({bool raw = false}) {
    return raw ? _rawAudioSample : _processedAudioSample;
  }

  double _volume = -90.0;
  final NumExpFilter _volumeFilter = NumExpFilter(initialValue: -90.0, alphaDecay: 0.99, alphaRise: 0.99);
  double volume({bool filtered = true}) {
    return filtered ? _volumeFilter.value! : _volume;
  }

  DigitalFilter? preEmphasis;
  PhaseVocoder? phaseVocoder;
  Resampler? resampler;
  FixedSizeBuffer? delayQueue;

  final List<double> _audioEventBuffer = [];
  void activate() {
    if (_streamSub != null) return;
    // setup audio bridge event stream
    _audio ??= AudioBridge.instance;
    _streamSub = _audio!.events.listen((event) {
      switch (event) {
        case StateEvent(:final value):
          switch (value) {
            case "recording_started":
              _audioStreamActive = true;
              debugPrint("AudioInputSource: recording started");
              break;
            case "recording_stopped":
              _audioStreamActive = false;
              debugPrint("AudioInputSource: recording stopped");
              break;
          }
          break;

        case ErrorEvent(:final String message):
          debugPrint(message);
          break;

        case AudioEvent(:final Float32List data):
          // Convert and accumulate into frames
          // final frames = processAudioByteChunk(data);
          // for (final frame in frames) {
          //   audioSampleCallback(frame);
          // }
          audioSampleCallback(data);
          break;
        case DevicesInfoEvent():
          // case DevicesInfoEvent(:final audioDevices):
          //   this.audioDevices = audioDevices;
          //   notifySubscribers();
          break;
      }
    });
    // get devices list
    // _audio!.getDevices();

    // Setup a pre-emphasis filter to balance the input volume of lows to highs
    preEmphasis = DigitalFilter(3);
    final selectedCoeff = ledfx.config.melbankConfig?.coeffType ?? CoeffType.mattmel;
    switch (selectedCoeff) {
      case CoeffType.mattmel:
        preEmphasis!.setBiquad(0.8268, -1.6536, 0.8268, -1.6536, 0.6536);
      // default:
      //   preEmphasis.setBiquad(0, 0.85870, -1.71740, 0.85870, -1.71605, 0.71874);
    }
    _rawAudioSample = Float32List.fromList(List.filled(MIC_RATE ~/ sampleRate, 0));
    phaseVocoder = PhaseVocoder(FFT_SIZE, MIC_RATE ~/ sampleRate);
    _inputVec = FloatVector.create(MIC_RATE ~/ sampleRate);
    _processedVec = FloatVector.create(MIC_RATE ~/ sampleRate);

    _freqDomain = ComplexVector.create(FFT_SIZE);

    _rawAudioSample = Float32List(MIC_RATE ~/ sampleRate);
    _processedAudioSample = Float32List(MIC_RATE ~/ sampleRate);

    final samplesToDelay = (0.001 * delay.inMilliseconds * sampleRate).toInt();
    if (samplesToDelay > 0) {
      delayQueue = FixedSizeBuffer(samplesToDelay);
    } else {
      delayQueue = null;
    }
  }

  void deactivate() {
    _streamSub?.cancel();
    _streamSub = null;
    _audioStreamActive = false;

    // Clean Pointers
    resampler = null;
  }

  // void queryDevices() {
  //   if (_audio == null) {
  //     return;
  //   }
  //   _audio!.getDevices();
  // }

  // void setActiveDevice(int index) {
  //   activeAudioDeviceIndex = index;
  // }

  Future<void> startAudioCapture([int? deviceIndex]) async {
    if (_audio == null) return;
    if (_audioStreamActive) return;
    // if (audioDevices == null) queryDevices();
    // if (deviceIndex != null) setActiveDevice(deviceIndex);

    // if (audioDevices!.length > activeAudioDeviceIndex) {
    //   print("starting audio capture with device -- ${audioDevices![activeAudioDeviceIndex].name}");
    //   await _audio!.start({
    //     "deviceId": audioDevices![activeAudioDeviceIndex].id,
    //     "captureType": audioDevices![activeAudioDeviceIndex].type == AudioDeviceType.input ? "capture" : "loopback",
    //     "sampleRate": audioDevices![activeAudioDeviceIndex].defaultSampleRate,
    //     "channels": 1,
    //     "blockSize": audioDevices![activeAudioDeviceIndex].defaultSampleRate ~/ sampleRate,
    //   });
    //   return;
    // }
  }

  // Future<void> stopAudioCapture() async {
  //   if (_audioStreamActive && _audio != null) {
  //     await _audio!.stop();
  //   }
  // }

  /// Convert PCM16 bytes → normalized float samples
  Float32List pcm16ToFloat32(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final samples = Float32List(bytes.lengthInBytes ~/ 2);
    for (int i = 0; i < samples.length; i++) {
      samples[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return samples;
  }

  /// Process new PCM chunk into fixed frames
  List<Float32List> processAudioByteChunk(Uint8List bytes) {
    final samples = pcm16ToFloat32(bytes);
    _audioEventBuffer.addAll(samples);
    final int frameSize = MIC_RATE ~/ sampleRate;

    final frames = <Float32List>[];
    while (_audioEventBuffer.length >= frameSize) {
      frames.add(Float32List.fromList(_audioEventBuffer.sublist(0, frameSize)));
      _audioEventBuffer.removeRange(0, frameSize);
    }
    return frames;
  }

  int inLen = 0;
  int outLen = 0;

  void audioSampleCallback(Float32List inRaw) {
    final int outLen = MIC_RATE ~/ sampleRate;
    Float32List processed = Float32List(outLen);
    if (inRaw.length != outLen) {
      resampler ??= Resampler(ResamplerType.sincFastest, inRaw.length, outLen);
      processed = resampler!.process(inRaw, outLen);
    } else {
      processed = inRaw;
    }

    if (processed.length != outLen) {
      debugPrint("Discarding malformed audio frame");
      return;
    }

    if (delayQueue != null && delayQueue!.length > 0) {
      try {
        final canput = delayQueue!.put(processed);
        if (!canput) throw Error();
      } catch (e) {
        _rawAudioSample = delayQueue!.get();
        delayQueue!.put(processed);
        preProcessAudio();
        invalidateCaches();
        notifySubscribers();
      }
    } else {
      _rawAudioSample = processed;
      preProcessAudio();
      invalidateCaches();
      notifySubscribers();
    }
  }

  void subscribe(VoidCallback callback) {
    _callbacks.add(callback);
    if (_callbacks.isNotEmpty && !_audioStreamActive) {
      activate();
    }
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  // NOtifies all subscribers
  void notifySubscribers() {
    for (final callback in _callbacks) {
      callback();
    }
  }

  void unsubscribe(VoidCallback callback) {
    _callbacks.removeWhere((c) => c == callback);

    if (_callbacks.length <= _subscriberThreshould && _audioStreamActive) {
      if (_timer != null) _timer!.cancel();
      _timer = Timer(Duration(seconds: 5), checkAndDeactivate);
    }
  }

  void checkAndDeactivate() {
    if (_timer != null) {
      _timer!.cancel();
    }
    _timer = null;
    if (_callbacks.length <= _subscriberThreshould && _audioStreamActive) {
      deactivate();
    }
  }

  void invalidateCaches();

  // Pre-processing stage that will run on every sample, only
  // core functionality that will be used for every audio effect
  // should be done here. Everything else should be deferred until
  // queried by an effect.
  void preProcessAudio() {
    //Calculate the current volume for silence detection
    final db = dbSPL(_rawAudioSample);

    _volume = 1 + db / 100;
    _volume = max(0, min(1, _volume));
    _volumeFilter.update(_volume);

    // print("db: $db, vol: ${_volumeFilter.value}");

    // Calculate the frequency domain from the filtered data and
    // force all zeros when below the volume threshold
    if ((_volumeFilter.value as double) > minVolume) {
      _processedAudioSample = _rawAudioSample;

      // Copy to native input buffer
      _inputVec.copyFrom(_rawAudioSample);

      if (preEmphasis != null) {
        // Pre-emphasis filter
        preEmphasis!.process(_inputVec, _processedVec);
        _processedVec.copyTo(_processedAudioSample);

        // Pass into the phase vocoder to get a windowed FFT
        phaseVocoder!.analyze(_processedVec, _freqDomain);
      } else {
        // Pass into the phase vocoder to get a windowed FFT
        phaseVocoder!.analyze(_inputVec, _freqDomain);
      }
    } else {
      _freqDomain.clear();
    }
  }
}

enum PitchMethod { yinfft }

enum OnsetMethod { energy, hfc, complex }

enum TempoMethod { simple }

class AudioAnalysisSource extends AudioInputSource {
  // # some frequency constants
  // # beat, bass, mids, high
  static const freqMaxMels = [100, 250, 3000, 10000];

  final PitchMethod pitchMethod;
  final TempoMethod tempoMethod;
  final OnsetMethod onsetMethod;
  final double pitchTolerance;

  late Melbanks melbanks;
  //bar oscillator
  late int beatCounter;
  //beat oscillator
  late DateTime beatTimestamp;
  late int beatPeriod;
  // freq power
  late List<double> freqPowerRaw;
  late ListExpFilter freqPowerFilter;
  late List<int> freqMelIndexs;
  // volume based beat detection
  late int beatMaxMelIndex;
  final double beatMinPercentDiff = 0.5;
  final double beatMinAmplitude = 0.5;
  final int beatMinTimeScince = 100;
  late int beatPowerHistoryLen;
  late int beatPreviousTime;
  late CircularBuffer<double> beatPowerHistory;

  AudioAnalysisSource({
    required super.ledfx,
    this.pitchMethod = PitchMethod.yinfft,
    this.tempoMethod = TempoMethod.simple,
    this.onsetMethod = OnsetMethod.hfc,
    this.pitchTolerance = 0.8,
  }) {
    initialiseAnalysis();

    subscribe(melbanks.execute);
    // subscribe(setPitch);
    // subscribe(setOnset);
    // subscribe(barOscillator);
    // subscribe(volumeBeatNow);
    // subscribe(freqPower);

    _subscriberThreshould = _callbacks.length;
  }

  @override
  void deactivate() {
    super.deactivate();
    // Clean Pointers
    melbanks.dispose();
  }

  void initialiseAnalysis() {
    melbanks = Melbanks(ledfx: ledfx, audio: this);

    //bar oscillator
    beatCounter = 0;
    //beat oscillator
    beatTimestamp = DateTime.now();
    beatPeriod = 2;
    //freq power
    freqPowerRaw = List.filled(freqMaxMels.length, 0.0, growable: false);
    freqPowerFilter = ListExpFilter(
      initialValue: List.filled(freqMaxMels.length, 0.0, growable: false),
      alphaDecay: 0.2,
      alphaRise: 0.97,
    );
    freqMelIndexs = [];
    for (final freq in freqMelIndexs) {
      assert(melbanks.melbankConfig.maxFreqs[2] >= freq);
      final index = melbanks.melbankProcessors[2].melbankFreqs.indexWhere((f) => f > freq);
      freqMelIndexs.add((index == -1) ? melbanks.melbankProcessors[2].melbankFreqs.length : index);
    }

    //volume based beat detection
    final tmpIndex = melbanks.melbankProcessors[0].melbankFreqs.indexWhere((f) => f > freqMaxMels[0]);
    beatMaxMelIndex = (tmpIndex == -1) ? melbanks.melbankProcessors[0].melbankFreqs.last : tmpIndex - 1;
    beatPowerHistoryLen = beatPowerHistoryLen = (sampleRate * 0.2).toInt();
    beatPowerHistory = CircularBuffer(beatPowerHistoryLen);
    beatPreviousTime = DateTime.now().millisecondsSinceEpoch;
  }

  @override
  void invalidateCaches() {
    // _pitch = null;
    // _onset = null;
  }

  // double? _pitch;
  // double? get pitch => _pitch;
  // void setPitch() {
  //   try {
  //     _pitch = dsp.detectPitch(audioSample(raw: true));
  //   } catch (e) {
  //     debugPrint(e.toString());
  //     _pitch = null;
  //   }
  // }

  // bool? _onset;
  // bool? get onset => _onset;
  // void setOnset() {
  //   try {
  //     _onset = dsp.detectOnset(audioSample(raw: true));
  //   } catch (e) {
  //     debugPrint(e.toString());
  //     _onset = null;
  //   }
  // }

  // void barOscillator() {}

  bool volumeBeatNow() {
    final timeNow = DateTime.now().millisecondsSinceEpoch;
    final melbank = melbanks.melbanks[0].getRange(0, beatMaxMelIndex + 1).toList();
    final beatPower = (melbank.isEmpty) ? 0.0 : melbank.reduce((a, b) => a + b);
    final melbankMax = melbank.maxOrZero();

    late double difference;
    final beatPowerHistorySum = (beatPowerHistory.toList().isEmpty)
        ? 0.0
        : beatPowerHistory.toList().reduce((a, b) => a + b);
    if (beatPowerHistorySum > 0) {
      difference = (beatPower * beatPowerHistoryLen) / beatPowerHistorySum - 1;
    } else {
      difference = 0;
    }

    beatPowerHistory.appendLeft(beatPower);

    if (difference >= beatMinPercentDiff &&
        melbankMax >= beatMinAmplitude &&
        timeNow - beatPreviousTime > beatMinTimeScince) {
      beatPreviousTime = timeNow;
      return true;
    } else {
      return false;
    }
  }

  // void freqPower() {}
}
