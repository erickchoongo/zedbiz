class Money {
  const Money._(this.minorUnits, this.currency);

  const Money.fromMinorUnits(this.minorUnits, this.currency);

  factory Money.parse(String value, String currency) {
    final match = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(value);
    if (match == null) throw const FormatException('Invalid money value');
    final sign = match.group(1) == '-' ? -1 : 1;
    final whole = int.parse(match.group(2)!);
    final fraction = (match.group(3) ?? '').padRight(2, '0');
    return Money._(sign * (whole * 100 + int.parse(fraction)), currency);
  }

  final int minorUnits;
  final String currency;

  String get decimal {
    final absolute = minorUnits.abs();
    final whole = absolute ~/ 100;
    final fraction = (absolute % 100).toString().padLeft(2, '0');
    return '${minorUnits < 0 ? '-' : ''}$whole.$fraction';
  }

  String get display => '$currency $decimal';

  Money operator +(Money other) {
    if (currency != other.currency) throw ArgumentError('Currency mismatch');
    return Money.fromMinorUnits(minorUnits + other.minorUnits, currency);
  }

  Money operator -(Money other) {
    if (currency != other.currency) throw ArgumentError('Currency mismatch');
    return Money.fromMinorUnits(minorUnits - other.minorUnits, currency);
  }

  Money multiplyThousandths(int quantity) =>
      Money.fromMinorUnits((minorUnits * quantity + 500) ~/ 1000, currency);
}
