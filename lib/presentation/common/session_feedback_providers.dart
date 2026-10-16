import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Aviso transitorio que `LoginScreen` muestra una sola vez tras volver a
/// ella. Solo dos casos (ver `docs/design.md`, "Avisos de sesión"):
/// cerrar sesión desde el perfil y un borrado de cuenta que terminó
/// completo. Un borrado fallido o parcial nunca llega aquí: ese camino ya
/// tiene su propio mensaje de error en `ProfileScreen`.
enum SessionFeedbackKind { signedOut, accountDeleted }

/// En memoria, de nivel de aplicación (vive en la raíz del
/// `ProviderScope`, por eso sobrevive a que `ProfileScreen`/
/// `TransactionsScreen` se destruyan al volver al login) — nunca en
/// disco ni en Firestore. `ProfileScreen` lo escribe solo en la rama de
/// éxito de cerrar sesión o borrar la cuenta; `LoginScreen` lo lee una
/// vez y lo limpia a `null` inmediatamente, para que un rebuild
/// posterior (o un hot reload) no repita el aviso.
final sessionFeedbackProvider = NotifierProvider<SessionFeedbackNotifier, SessionFeedbackKind?>(
  SessionFeedbackNotifier.new,
);

class SessionFeedbackNotifier extends Notifier<SessionFeedbackKind?> {
  @override
  SessionFeedbackKind? build() => null;

  void set(SessionFeedbackKind kind) => state = kind;

  void clear() => state = null;
}
