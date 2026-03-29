import 'dart:math' as math;
import 'dart:typed_data';

double levelLin(Float32List f) {
  double energy = 0.0;
  final int length = f.length;
  for (int j = 0; j < length; j++) {
    final double val = f[j];
    energy += val * val;
  }
  return energy / length;
}

double dbSPL(Float32List f) {
  return 10.0 * (math.log(levelLin(f)) / math.ln10);
}
