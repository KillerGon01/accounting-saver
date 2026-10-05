/// Identificador del proveedor de correo y contraseña en Firebase Auth.
const passwordProviderId = 'password';

class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.emailVerified,
    required this.providerIds,
    this.displayName,
  });

  final String uid;
  final String? email;
  final bool emailVerified;
  final List<String> providerIds;
  final String? displayName;

  /// Las cuentas creadas con correo y contraseña deben verificar su correo
  /// antes de usar la app. Los usuarios de Google ya vienen verificados.
  bool get needsEmailVerification =>
      !emailVerified && providerIds.contains(passwordProviderId);
}
