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

      filter.setX(1, x1); filter.setX(2, x2);
      filter.setY(1, y1); filter.setY(2, y2);
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
