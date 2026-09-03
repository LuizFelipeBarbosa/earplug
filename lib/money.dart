/// An amount stored in integer minor units, such as cents.
class Money {
  final int amountMinor;
  final String currency;

  const Money(this.amountMinor, [this.currency = 'usd']);

  static const Money zero = Money(0);

  factory Money.fromJson(Map<String, dynamic>? json) {
    final amount = json?['amountMinor'];
    final currency = json?['currency'];
    return Money(
      amount is num ? amount.toInt() : 0,
      currency is String ? currency : 'usd',
    );
  }

  String get label {
    final negative = amountMinor < 0;
    final absoluteMinor = amountMinor.abs();
    final major = absoluteMinor ~/ 100;
    final minor = (absoluteMinor % 100).toString().padLeft(2, '0');
    final sign = negative ? '-' : '';

    if (currency == 'usd') {
      return '$sign\$${_withThousandsSeparators(major)}.$minor';
    }
    return '$sign${currency.toUpperCase()} $major.$minor';
  }

  /// Adds amounts with the same currency.
  ///
  /// Throws [ArgumentError] when the currencies differ.
  Money operator +(Money other) {
    _requireMatchingCurrency(other);
    return Money(amountMinor + other.amountMinor, currency);
  }

  /// Subtracts amounts with the same currency.
  ///
  /// Throws [ArgumentError] when the currencies differ.
  Money operator -(Money other) {
    _requireMatchingCurrency(other);
    return Money(amountMinor - other.amountMinor, currency);
  }

  bool get isNegative => amountMinor < 0;

  void _requireMatchingCurrency(Money other) {
    if (currency != other.currency) {
      throw ArgumentError(
        'Money operations require matching currencies: '
        '$currency and ${other.currency}.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Money &&
          amountMinor == other.amountMinor &&
          currency == other.currency;

  @override
  int get hashCode => Object.hash(amountMinor, currency);
}

String _withThousandsSeparators(int value) {
  final digits = value.toString();
  final firstGroupLength = digits.length % 3;
  final groups = <String>[];

  if (firstGroupLength > 0) {
    groups.add(digits.substring(0, firstGroupLength));
  }
  for (var index = firstGroupLength; index < digits.length; index += 3) {
    groups.add(digits.substring(index, index + 3));
  }
  return groups.join(',');
}
