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
}
