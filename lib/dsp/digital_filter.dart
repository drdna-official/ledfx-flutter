import 'types.dart';

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
    if (input.getLength() != output.getLength()) {
      throw Exception("input and output must have the same length");
    }

    for (int i = 0; i < input.getLength(); i++) {
      // from input
      filter.setX(0, input.get(i));
      filter.setY(0, filter.getB(0) * filter.getX(0));

      for (int j = 1; j < filter.getOrder(); j++) {
        filter.setY(0, filter.getY(0) + (filter.getB(j) * filter.getX(j)));
        filter.setY(0, filter.getY(0) - (filter.getA(j) * filter.getY(j)));
      }

      // set output
      output.set(i, filter.getY(0));
      // Store for next sample
      for (int j = filter.getOrder() - 1; j > 0; j--) {
        filter.setX(j, filter.getX(j - 1));
        filter.setY(j, filter.getY(j - 1));
      }
    }
  }
}
