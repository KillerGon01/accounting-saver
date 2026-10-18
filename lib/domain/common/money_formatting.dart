/// Euro cents, already in absolute value (unsigned), to text with a
/// decimal comma and two decimals (for example, 1299 → "12,99"). No
/// thousands separator or currency symbol: that's what `formatCents` in
/// `presentation/transactions/formatters.dart` is for, the only layer
/// allowed to decide how an amount looks on screen. This pure function
/// (no Firebase, no Flutter) is what the domain and application layers
/// (for example, the chat functions) use when they need an amount in
/// euros without depending on the presentation layer.
String formatEuroAmount(int amountCentsAbs) {
  final euros = amountCentsAbs ~/ 100;
  final decimals = (amountCentsAbs % 100).toString().padLeft(2, '0');
  return '$euros,$decimals';
}
