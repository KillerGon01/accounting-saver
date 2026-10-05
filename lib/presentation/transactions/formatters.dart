import '../../domain/transactions/category.dart';

const _monthNames = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

const _weekdayNames = [
  'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
];

String formatCents(int cents) {
  final sign = cents < 0 ? '-' : '';
  final absolute = cents.abs();
  final euros = _groupThousands(absolute ~/ 100);
  final decimals = (absolute % 100).toString().padLeft(2, '0');
  return '$sign$euros,$decimals €';
}

String formatEditableAmount(int absoluteCents) {
  final euros = absoluteCents ~/ 100;
  final decimals = (absoluteCents % 100).toString().padLeft(2, '0');
  return '$euros,$decimals';
}

String formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

String formatDayHeader(DateTime date) {
  final weekday = _weekdayNames[date.weekday - 1];
  final month = _monthNames[date.month - 1];
  return '${_capitalize(weekday)}, ${date.day} de $month';
}

String _capitalize(String text) => '${text[0].toUpperCase()}${text.substring(1)}';

String formatMonth(DateTime date) {
  final name = _monthNames[date.month - 1];
  return '${name[0].toUpperCase()}${name.substring(1)} de ${date.year}';
}

String _groupThousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    if (i > 0 && remaining % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

extension CategoryLabel on Category {
  String get label => switch (this) {
    Category.supermercado => 'Supermercado',
    Category.restaurantes => 'Restaurantes',
    Category.transporte => 'Transporte',
    Category.suscripciones => 'Suscripciones',
    Category.ocio => 'Ocio',
    Category.salud => 'Salud',
    Category.hogar => 'Hogar',
    Category.nomina => 'Nómina',
    Category.otros => 'Otros',
  };
}
