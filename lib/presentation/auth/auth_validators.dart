const minPasswordLength = 8;

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validateEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return 'Introduce tu correo electrónico';
  if (!_emailPattern.hasMatch(email)) {
    return 'El correo electrónico no tiene un formato válido';
  }
  return null;
}

/// At login, only something being typed is required: older accounts
/// may have passwords shorter than the current minimum.
String? validateLoginPassword(String? value) {
  if (value == null || value.isEmpty) return 'Introduce tu contraseña';
  return null;
}

String? validateNewPassword(String? value) {
  if ((value ?? '').length < minPasswordLength) {
    return 'La contraseña debe tener al menos $minPasswordLength caracteres';
  }
  return null;
}

String? validateConfirmPassword(String? value, String password) {
  if ((value ?? '') != password) return 'Las contraseñas no coinciden';
  return null;
}
