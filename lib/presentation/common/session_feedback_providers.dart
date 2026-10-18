import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Transient notice `LoginScreen` shows once after returning to it.
/// Only two cases (see `docs/design.md`, "Avisos de sesión"): signing
/// out from the profile and an account deletion that finished
/// completely. A failed or partial deletion never reaches here: that
/// path already has its own error message in `ProfileScreen`.
enum SessionFeedbackKind { signedOut, accountDeleted }

/// In memory, at the application level (lives at the
/// `ProviderScope`'s root, which is why it survives
/// `ProfileScreen`/`TransactionsScreen` being destroyed when
/// returning to login) — never on disk or in Firestore.
/// `ProfileScreen` only writes to it on the success path of signing
/// out or deleting the account; `LoginScreen` reads it once and
/// clears it to `null` immediately, so a later rebuild (or a hot
/// reload) doesn't repeat the notice.
final sessionFeedbackProvider = NotifierProvider<SessionFeedbackNotifier, SessionFeedbackKind?>(
  SessionFeedbackNotifier.new,
);

class SessionFeedbackNotifier extends Notifier<SessionFeedbackKind?> {
  @override
  SessionFeedbackKind? build() => null;

  void set(SessionFeedbackKind kind) => state = kind;

  void clear() => state = null;
}
