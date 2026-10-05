import 'amount_limits.dart';

int? parseEurosToCents(String input) {
  final match = RegExp(r'^(\d{1,9})(?:[.,](\d{1,2}))?$').firstMatch(input.trim());
  if (match == null) return null;

  final euros = int.parse(match.group(1)!);
  final cents = int.parse((match.group(2) ?? '').padRight(2, '0'));
  final total = euros * 100 + cents;
  return total <= maxAbsoluteAmountCents ? total : null;
}
