import 'dart:math';

import 'types.dart';

/// Equalizer operating mode.
enum EqualizerType {
  /// Fixed-frequency bands at ISO 266 center frequencies.
  /// Each band is a peak filter with Q derived from the octave fraction.
  graphic,

  /// Fully configurable bands: lowShelf → peak(s) → highShelf.
  /// Bands can be added/removed at runtime.
  parametric,
}

/// Preset band counts for [EqualizerType.graphic].
enum GraphicBandCount {
  /// 10 bands – 1 octave spacing (Q ≈ 1.414).
  bands10(10),

  /// 15 bands – 2/3 octave spacing (Q ≈ 2.145).
  bands15(15),

  /// 31 bands – 1/3 octave spacing (Q ≈ 4.318).
  bands31(31);

  const GraphicBandCount(this.count);
  final int count;
}

/// ISO 266 preferred center frequencies (Hz) for graphic EQ presets.
///
/// 10-band (1 octave):      31.5  63  125  250  500  1k  2k  4k  8k  16k
/// 15-band (2/3 octave):    25  40  63  100  160  250  400  630  1k  1.6k  2.5k  4k  6.3k  10k  16k
/// 31-band (1/3 octave):    20  25  31.5  40  50  63  80  100  125  160  200  250  315  400  500
///                          630  800  1k  1.25k  1.6k  2k  2.5k  3.15k  4k  5k  6.3k  8k  10k  12.5k  16k  20k
const List<double> _iso266_10 = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

const List<double> _iso266_15 = [25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000];

const List<double> _iso266_31 = [
  20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500,
  // --
  630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000,
];

/// Returns the Q factor for a given octave-fraction bandwidth.
///
/// Q = 1 / (2 * sinh( ln(2)/2 * BW )) where BW is in octaves.
///   10-band → BW = 1    → Q ≈ 1.414
///   15-band → BW = 2/3  → Q ≈ 2.145
///   31-band → BW = 1/3  → Q ≈ 4.318
double _qForOctaveFraction(double bandwidthOctaves) {
  return 1.0 / (2.0 * _sinh(ln2 / 2.0 * bandwidthOctaves));
}

double _sinh(double x) => (exp(x) - exp(-x)) / 2.0;

/// A multi-band equalizer built from cascaded [BiquadDigitalFilter] stages.
///
/// Two modes of operation:
///
/// **Graphic** — Fixed center frequencies from ISO 266, fixed Q derived from
/// the octave fraction.  Only per-band gain (dB) is adjustable at runtime.
///
/// **Parametric** — Follows lowShelf → peak(s) → highShelf convention.
/// Each band's frequency, Q, gain, and (within convention) type is
/// configurable.  Bands can be added or removed dynamically.
class Equalizer {
  final EqualizerType type;
  final double sampleRate;

  final List<BiquadDigitalFilter> _filters = [];
  final List<double> _centerFreqs = [];
  final List<double> _gains = [];
  final List<double> _qs = [];
  final List<BiquadFilterType> _bandTypes = [];

  /// Intermediate buffers for cascaded processing.
  /// _intermediates[i] holds the output of filter i (and input to filter i+1).
  /// We keep one fewer buffer than filters — the first filter reads from the
  /// caller's input, and the last filter writes to the caller's output.
  final List<FloatVector> _intermediates = [];

  /// Length of the intermediate buffers (tracked so we can re-allocate on size change).
  int _bufferLength = 0;

  /// Creates a graphic equalizer with [bandCount] ISO 266 bands.
  ///
  /// All bands start at 0 dB gain (flat response).
  Equalizer.graphic({required this.sampleRate, GraphicBandCount bandCount = GraphicBandCount.bands10})
    : type = EqualizerType.graphic {
    final List<double> freqs;
    final double bwOctaves;

    switch (bandCount) {
      case GraphicBandCount.bands10:
        freqs = _iso266_10;
        bwOctaves = 1.0;
      case GraphicBandCount.bands15:
        freqs = _iso266_15;
        bwOctaves = 2.0 / 3.0;
      case GraphicBandCount.bands31:
        freqs = _iso266_31;
        bwOctaves = 1.0 / 3.0;
    }

    final double q = _qForOctaveFraction(bwOctaves);

    for (final freq in freqs) {
      _filters.add(
        BiquadDigitalFilter(type: BiquadFilterType.peak, centerFreq: freq, sampleRate: sampleRate, q: q, gainDB: 0),
      );
      _centerFreqs.add(freq);
      _gains.add(0);
      _qs.add(q);
      _bandTypes.add(BiquadFilterType.peak);
    }
  }

  /// Creates a parametric equalizer.
  ///
  /// Starts with zero bands.  Use [addBand] to insert bands — the first band
  /// added becomes a lowShelf, the last a highShelf, and any in between are
  /// peaks.  Band types are automatically managed as bands are added/removed.
  Equalizer.parametric({required this.sampleRate}) : type = EqualizerType.parametric;

  /// Number of active bands.
  int get bandCount => _filters.length;

  /// Center frequency of band [index].
  double centerFreq(int index) => _centerFreqs[index];

  /// Current gain (dB) of band [index].
  double gain(int index) => _gains[index];

  /// Current Q of band [index].
  double q(int index) => _qs[index];

  /// Filter type of band [index].
  BiquadFilterType bandType(int index) => _bandTypes[index];

  // Graphic EQ controls -------------------------------------------
  /// Sets the gain (dB) of graphic EQ band [index].
  /// Only the affected [BiquadDigitalFilter] is reconfigured; all other
  /// filters retain their state.
  void setGain(int index, double gainDB) {
    _gains[index] = gainDB;
    _filters[index].configure(
      type: _bandTypes[index],
      centerFreq: _centerFreqs[index],
      sampleRate: sampleRate,
      q: _qs[index],
      gainDB: gainDB,
    );
  }

  /// Bulk-set all graphic EQ band gains from a list of dB values.
  /// [gains] must have length equal to [bandCount].
  void setAllGains(List<double> gains) {
    if (gains.length != _filters.length) {
      throw Exception('gains length (${gains.length}) must match band count (${_filters.length})');
    }
    for (int i = 0; i < gains.length; i++) {
      setGain(i, gains[i]);
    }
  }

  // Parametric EQ controls --------------------------------------
  /// Adds a band to the parametric EQ.
  /// The band type is automatically assigned based on its position:
  ///   - Single band → lowShelf
  ///   - First band → lowShelf, last → highShelf, middle → peak
  /// Returns the index of the newly added band.
  int addBand({required double centerFreq, double q = 0.707, double gainDB = 0}) {
    if (type != EqualizerType.parametric) {
      throw Exception('addBand is only supported for parametric EQ');
    }

    final int newIndex = _filters.length;

    // Determine type for the new band (which will be the last).
    final BiquadFilterType newType = (newIndex == 0) ? BiquadFilterType.lowShelf : BiquadFilterType.highShelf;

    _filters.add(
      BiquadDigitalFilter(type: newType, centerFreq: centerFreq, sampleRate: sampleRate, q: q, gainDB: gainDB),
    );
    _centerFreqs.add(centerFreq);
    _gains.add(gainDB);
    _qs.add(q);
    _bandTypes.add(newType);

    // Re-assign types: lowShelf → peak(s) → highShelf
    _reassignParametricTypes();

    // Allocate intermediate buffer if needed.
    _ensureIntermediates();

    return newIndex;
  }

  /// Removes the band at [index] from the parametric EQ.
  void removeBand(int index) {
    if (type != EqualizerType.parametric) {
      throw Exception('removeBand is only supported for parametric EQ');
    }
    if (index < 0 || index >= _filters.length) {
      throw RangeError.index(index, _filters, 'index');
    }

    _filters.removeAt(index);
    _centerFreqs.removeAt(index);
    _gains.removeAt(index);
    _qs.removeAt(index);
    _bandTypes.removeAt(index);

    _reassignParametricTypes();
    _ensureIntermediates();
  }

  /// Updates a single parametric band's parameters.
  ///
  /// Only the affected filter is reconfigured.
  void updateBand(int index, {double? centerFreq, double? q, double? gainDB}) {
    if (index < 0 || index >= _filters.length) {
      throw RangeError.index(index, _filters, 'index');
    }

    if (centerFreq != null) _centerFreqs[index] = centerFreq;
    if (q != null) _qs[index] = q;
    if (gainDB != null) _gains[index] = gainDB;

    _filters[index].configure(
      type: _bandTypes[index],
      centerFreq: _centerFreqs[index],
      sampleRate: sampleRate,
      q: _qs[index],
      gainDB: _gains[index],
    );
  }

  // Processing -----------------------------------------------
  /// Processes [input] through all cascaded EQ bands, writing the final
  /// result into [output].
  /// Both vectors must have the same length.  If there are zero bands the
  /// input is copied directly to the output.
  void process(FloatVector input, FloatVector output) {
    final int len = input.getLength();
    if (len != output.getLength()) {
      throw Exception('input and output must have the same length');
    }
    final int n = _filters.length;
    if (n == 0) {
      // Pass-through: copy input → output.
      for (int i = 0; i < len; i++) {
        output.set(i, input.get(i));
      }
      return;
    }

    // Ensure intermediate buffers match the current frame length.
    if (len != _bufferLength) {
      _reallocateIntermediates(len);
    }

    if (n == 1) {
      _filters[0].process(input, output);
      return;
    }

    // First filter:  input → intermediate[0]
    _filters[0].process(input, _intermediates[0]);

    // Middle filters: intermediate[i-1] → intermediate[i]
    for (int i = 1; i < n - 1; i++) {
      _filters[i].process(_intermediates[i - 1], _intermediates[i]);
    }

    // Last filter: intermediate[n-2] → output
    _filters[n - 1].process(_intermediates[n - 2], output);
  }

  /// Resets all filter states (delay elements) without changing coefficients.
  void reset() {
    for (final f in _filters) {
      f.reset();
    }
  }

  /// Re-assigns band types for parametric EQ following the lowShelf → peak → highShelf convention.
  void _reassignParametricTypes() {
    final int n = _filters.length;
    if (n == 0) return;

    for (int i = 0; i < n; i++) {
      final BiquadFilterType desired;
      if (n == 1) {
        desired = BiquadFilterType.lowShelf;
      } else if (i == 0) {
        desired = BiquadFilterType.lowShelf;
      } else if (i == n - 1) {
        desired = BiquadFilterType.highShelf;
      } else {
        desired = BiquadFilterType.peak;
      }

      if (_bandTypes[i] != desired) {
        _bandTypes[i] = desired;
        _filters[i].configure(
          type: desired,
          centerFreq: _centerFreqs[i],
          sampleRate: sampleRate,
          q: _qs[i],
          gainDB: _gains[i],
        );
      }
    }
  }

  /// Ensures the intermediate buffer list has the correct count (filters - 1).
  void _ensureIntermediates() {
    final int needed = (_filters.length > 1) ? _filters.length - 1 : 0;
    while (_intermediates.length > needed) {
      _intermediates.removeLast();
    }
    while (_intermediates.length < needed) {
      _intermediates.add(_bufferLength > 0 ? FloatVector.create(_bufferLength) : FloatVector.create(1));
    }
  }

  /// (Re-)allocates all intermediate buffers to match [length].
  void _reallocateIntermediates(int length) {
    _bufferLength = length;
    for (int i = 0; i < _intermediates.length; i++) {
      _intermediates[i] = FloatVector.create(length);
    }
  }
}

/// Filter types supported by [BiquadDigitalFilter].
///
/// Based on https://arachnoid.com/BiQuadDesigner/index.html
/// and the Audio EQ Cookbook (https://www.w3.org/2011/audio/audio-eq-cookbook.html).
enum BiquadFilterType { lowpass, highpass, highpassCustom, bandpass, peak, notch, lowShelf, highShelf }

/// A biquadratic (second-order IIR) digital filter.
///
/// Coefficients are computed from a [BiquadFilterType], center/corner frequency,
/// sample rate, Q factor, and optional gain (dB, used only by peak / shelf types).
///
/// Reference implementation:
///   https://arachnoid.com/BiQuadDesigner/source_files/BiQuadraticFilter.java
class BiquadDigitalFilter {
  // Pre-normalised coefficients (a0 is divided out during configure).
  double _b0 = 0, _b1 = 0, _b2 = 0;
  double _a1 = 0, _a2 = 0;

  // Filter state (delay elements).
  double _x1 = 0, _x2 = 0;
  double _y1 = 0, _y2 = 0;

  late BiquadFilterType _type;
  late double _sampleRate;
  late double _q;
  late double _gainDB;

  /// Creates and configures a biquad filter.
  ///
  /// [type]       – the filter type (lowpass, highpass, …).
  /// [centerFreq] – center or corner frequency in Hz.
  /// [sampleRate] – sampling rate in Hz.
  /// [q]          – quality factor (must be > 0; clamped to 1e-9 if zero).
  /// [gainDB]     – gain in dB (only used by [BiquadFilterType.peak],
  ///                [BiquadFilterType.lowShelf], and [BiquadFilterType.highShelf]).
  BiquadDigitalFilter({
    required BiquadFilterType type,
    required double centerFreq,
    required double sampleRate,
    double q = 0.707,
    double gainDB = 0,
  }) {
    configure(type: type, centerFreq: centerFreq, sampleRate: sampleRate, q: q, gainDB: gainDB);
  }

  /// Creates a biquad filter from pre-normalised coefficients.
  ///
  /// Use this when the coefficients don't originate from the standard
  /// Audio EQ Cookbook formulas (e.g. hand-tuned or externally computed).
  /// The coefficients are already divided by a0.
  BiquadDigitalFilter.raw({
    double b0 = 0,
    double b1 = 0,
    double b2 = 0,
    double a1 = 0,
    double a2 = 0,
  }) {
    _b0 = b0;
    _b1 = b1;
    _b2 = b2;
    _a1 = a1;
    _a2 = a2;
  }

  /// Resets the internal delay state without changing the coefficients.
  void reset() {
    _x1 = _x2 = _y1 = _y2 = 0;
  }

  /// Fully (re-)configures the filter, including a state reset.
  void configure({
    required BiquadFilterType type,
    required double centerFreq,
    required double sampleRate,
    double q = 0.707,
    double gainDB = 0,
  }) {
    reset();
    _type = type;
    _sampleRate = sampleRate;
    _q = (q == 0) ? 1e-9 : q;
    _gainDB = gainDB;
    reconfigure(centerFreq);
  }

  /// Reconfigures the center/corner frequency while the filter is running.
  ///
  /// This avoids a full state reset and can be called on every audio frame
  /// for dynamic frequency sweeps.
  void reconfigure(double centerFreq) {
    // Only used for peaking and shelving filters.
    final double gainAbs = pow(10, _gainDB / 40).toDouble();
    final double omega = 2 * pi * centerFreq / _sampleRate;
    final double sn = sin(omega);
    final double cs = cos(omega);
    final double alpha = sn / (2 * _q);
    final double beta = sqrt(gainAbs + gainAbs);

    double a0;
    double b0, b1, b2, a1, a2;

    switch (_type) {
      case BiquadFilterType.lowpass:
        b0 = (1 - cs) / 2;
        b1 = 1 - cs;
        b2 = (1 - cs) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cs;
        a2 = 1 - alpha;
      case BiquadFilterType.highpass:
        b0 = (1 + cs) / 2;
        b1 = -(1 + cs);
        b2 = (1 + cs) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cs;
        a2 = 1 - alpha;
      case BiquadFilterType.highpassCustom:
        b0 = (1 + cs) / 2;
        b1 = -(1 + cs);
        b2 = (1 + cs) / 2;
        a0 = 1 + alpha;
        a1 = -(1 + cs);
        a2 = cs - alpha;
      case BiquadFilterType.bandpass:
        b0 = alpha;
        b1 = 0;
        b2 = -alpha;
        a0 = 1 + alpha;
        a1 = -2 * cs;
        a2 = 1 - alpha;
      case BiquadFilterType.peak:
        b0 = 1 + (alpha * gainAbs);
        b1 = -2 * cs;
        b2 = 1 - (alpha * gainAbs);
        a0 = 1 + (alpha / gainAbs);
        a1 = -2 * cs;
        a2 = 1 - (alpha / gainAbs);
      case BiquadFilterType.notch:
        b0 = 1;
        b1 = -2 * cs;
        b2 = 1;
        a0 = 1 + alpha;
        a1 = -2 * cs;
        a2 = 1 - alpha;
      case BiquadFilterType.lowShelf:
        b0 = gainAbs * ((gainAbs + 1) - (gainAbs - 1) * cs + beta * sn);
        b1 = 2 * gainAbs * ((gainAbs - 1) - (gainAbs + 1) * cs);
        b2 = gainAbs * ((gainAbs + 1) - (gainAbs - 1) * cs - beta * sn);
        a0 = (gainAbs + 1) + (gainAbs - 1) * cs + beta * sn;
        a1 = -2 * ((gainAbs - 1) + (gainAbs + 1) * cs);
        a2 = (gainAbs + 1) + (gainAbs - 1) * cs - beta * sn;
      case BiquadFilterType.highShelf:
        b0 = gainAbs * ((gainAbs + 1) + (gainAbs - 1) * cs + beta * sn);
        b1 = -2 * gainAbs * ((gainAbs - 1) + (gainAbs + 1) * cs);
        b2 = gainAbs * ((gainAbs + 1) + (gainAbs - 1) * cs - beta * sn);
        a0 = (gainAbs + 1) - (gainAbs - 1) * cs + beta * sn;
        a1 = 2 * ((gainAbs - 1) - (gainAbs + 1) * cs);
        a2 = (gainAbs + 1) - (gainAbs - 1) * cs - beta * sn;
    }

    // Pre-scale (normalise) so a0 is eliminated from the difference equation.
    _b0 = b0 / a0;
    _b1 = b1 / a0;
    _b2 = b2 / a0;
    _a1 = a1 / a0;
    _a2 = a2 / a0;
  }

  /// Processes [input] through the biquad filter, writing results into [output].
  ///
  /// Both vectors must have the same length.  The difference equation is:
  ///   y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
  void process(FloatVector input, FloatVector output) {
    final int len = input.getLength();
    if (len != output.getLength()) {
      throw Exception('input and output must have the same length');
    }

    final double b0 = _b0, b1 = _b1, b2 = _b2;
    final double a1 = _a1, a2 = _a2;
    double x1 = _x1, x2 = _x2;
    double y1 = _y1, y2 = _y2;

    for (int i = 0; i < len; i++) {
      final double x0 = input.get(i);
      final double y0 = (b0 * x0) + (b1 * x1) + (b2 * x2) - (a1 * y1) - (a2 * y2);
      output.set(i, y0);
      x2 = x1;
      x1 = x0;
      y2 = y1;
      y1 = y0;
    }

    _x1 = x1;
    _x2 = x2;
    _y1 = y1;
    _y2 = y2;
  }
}

class DigitalFilter {
  final DigitalFilterData filter;

  DigitalFilter(int order) : filter = DigitalFilterData.create(order);

  void setBiquad(double b0, double b1, double b2, double a1, double a2) {
    if (filter.getOrder() != 3) {
      throw Exception("digital filter order must be 3 for biquad");
    }
    // feed forward - B
    filter.setB(0, b0);
    filter.setB(1, b1);
    filter.setB(2, b2);
    // feedback - A
    filter.setA(0, 1.0);
    filter.setA(1, a1);
    filter.setA(2, a2);
  }

  void process(FloatVector input, FloatVector output) {
    final int len = input.getLength();
    if (len != output.getLength()) {
      throw Exception("input and output must have the same length");
    }

    final int order = filter.getOrder();

    // Fast-path for standard Biquad formulation (order == 3)
    if (order == 3) {
      final double b0 = filter.getB(0), b1 = filter.getB(1), b2 = filter.getB(2);
      final double a1 = filter.getA(1), a2 = filter.getA(2);
      double x1 = filter.getX(1), x2 = filter.getX(2);
      double y1 = filter.getY(1), y2 = filter.getY(2);

      for (int i = 0; i < len; i++) {
        final double x0 = input.get(i);
        final double y0 = (b0 * x0) + (b1 * x1) + (b2 * x2) - (a1 * y1) - (a2 * y2);
        output.set(i, y0);
        x2 = x1;
        x1 = x0;
        y2 = y1;
        y1 = y0;
      }

      filter.setX(1, x1);
      filter.setX(2, x2);
      filter.setY(1, y1);
      filter.setY(2, y2);
      return;
    }

    // Fallback for non-biquad arbitrary orders
    for (int i = 0; i < len; i++) {
      filter.setX(0, input.get(i));
      double y0 = filter.getB(0) * filter.getX(0);

      for (int j = 1; j < order; j++) {
        y0 += (filter.getB(j) * filter.getX(j));
        y0 -= (filter.getA(j) * filter.getY(j));
      }

      filter.setY(0, y0);
      output.set(i, y0);

      for (int j = order - 1; j > 0; j--) {
        filter.setX(j, filter.getX(j - 1));
        filter.setY(j, filter.getY(j - 1));
      }
    }
  }
}
