extension DoubleExtensions on double {
  /// Compare two double numbers accepting given error.
  bool isAlmostIdentical(double another, {double error = 1e-10}) {
    return (this - another).abs() < error;
  }

  /// Compare two double numbers based on ratio accepting given error.
  bool isAlmostIdenticalRationally(double another, {double error = 1e-10}) {
    assert(this > 0 && another > 0);
    final d = this > another ? this / another : another / this;
    return d - 1 < error;
  }

  /// Round the double to keep 10-bits of precision under the binary point.
  ///
  /// It's almost 3 decimal places (i.e. 1.23456789 => 1.234) but cleaner in binary representation.
  double round10BitFrac() => (this * 1024).round() / 1024;
}
