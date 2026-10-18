import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/auth/user_profile.dart';
import '../../domain/transactions/activity_summary.dart';
import '../auth/auth_error_messages.dart';
import '../auth/auth_providers.dart';
import '../common/firestore_error_messages.dart';
import '../common/session_feedback_providers.dart';
import '../help/help_sheet.dart';
import '../help/help_topic.dart';
import '../theme/app_theme.dart';
import '../transactions/formatters.dart';
import 'account_deletion_messages.dart';
import 'delete_account_dialog.dart';
import 'profile_providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isSigningOut = false;
  bool _isDeleting = false;
  bool _deleteFailed = false;
  String? _errorMessage;

  Future<void> _signOut() async {
    setState(() {
      _isSigningOut = true;
      _errorMessage = null;
    });
    try {
      // `SignOutWithFeedback` ya deja `signedOut` en `sessionFeedbackProvider`
      // si el cierre de sesión termina con éxito (ver docs/design.md,
      // "Avisos de sesión") — única función compartida por los tres
      // botones de cerrar sesión de la app, nunca `signOutProvider` a secas.
      await ref.read(signOutWithFeedbackProvider)();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) setState(() => _errorMessage = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  Future<void> _deleteAccount(UserProfile profile) async {
    final request = await showDialog<DeleteAccountRequest>(
      context: context,
      builder: (_) => DeleteAccountDialog(
        email: profile.email ?? '',
        requiresPassword: profile.provider == SignInProvider.password,
      ),
    );
    if (request == null || !mounted) return;

    setState(() {
      _isDeleting = true;
      _deleteFailed = false;
      _errorMessage = null;
    });
    try {
      await ref.read(deleteAccountProvider)(password: request.password);
      // Solo si los tres pasos terminaron (reautenticar, borrar
      // movimientos, borrar la cuenta de Auth): un borrado fallido o
      // parcial entra por el `catch` de abajo y nunca llega aquí.
      ref.read(sessionFeedbackProvider.notifier).set(SessionFeedbackKind.accountDeleted);
      // La cuenta ya no existe: AuthGate muestra el login y se cierra el perfil.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) {
        setState(() {
          _deleteFailed = true;
          _errorMessage = accountDeletionErrorMessage(error);
        });
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Se reconstruye al cambiar la sesión; el perfil sale de la sesión actual.
    ref.watch(authStateChangesProvider);
    final profile = ref.watch(getUserProfileProvider)();
    if (profile == null) return const Scaffold(body: SizedBox.shrink());

    final theme = Theme.of(context);
    final summary = ref.watch(activitySummaryProvider(profile.uid));

    return PopScope(
      canPop: !_isDeleting,
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title: const Text('Perfil'),
              actions: const [HelpButton(topic: HelpTopic.profile)],
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.m),
                  children: [
                    if (_errorMessage != null) ...[
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: theme.colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.m),
                    ],
                    _SectionCard(
                      title: 'Datos de cuenta',
                      children: _accountRows(profile),
                    ),
                    const SizedBox(height: AppSpacing.m),
                    _SectionCard(
                      title: 'Resumen de actividad',
                      children: [
                        summary.when(
                          loading: () => const Center(
                            child: Padding(
                              padding: EdgeInsets.all(AppSpacing.m),
                              child: CircularProgressIndicator(),
                            ),
                          ),
                          error: (error, _) => Text(
                            firestoreErrorMessage(
                              error,
                              fallback: 'No se pudo cargar el resumen. Inténtalo de nuevo más tarde.',
                            ),
                          ),
                          data: (value) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _activityRows(value),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.m),
                    OutlinedButton.icon(
                      onPressed: _isSigningOut || _isDeleting ? null : _signOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('Cerrar sesión'),
                    ),
                    const SizedBox(height: AppSpacing.m),
                    _SectionCard(
                      title: 'Zona de peligro',
                      titleColor: theme.colorScheme.error,
                      children: [
                        Text(
                          'Borra tu cuenta y todos tus movimientos. No se puede deshacer.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppSpacing.m),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.error,
                            foregroundColor: theme.colorScheme.onError,
                          ),
                          onPressed: _isDeleting ? null : () => _deleteAccount(profile),
                          child: Text(
                            _deleteFailed ? 'Reintentar eliminación' : 'Eliminar cuenta',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isDeleting) ...[
            const ModalBarrier(dismissible: false, color: Colors.black54),
            const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.l),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: AppSpacing.m),
                      Text('Eliminando tu cuenta…'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _accountRows(UserProfile profile) {
    final name = profile.displayName;
    return [
      _InfoRow(label: 'Correo', value: profile.email ?? '—'),
      if (name != null && name.isNotEmpty) _InfoRow(label: 'Nombre', value: name),
      _InfoRow(label: 'Proveedor', value: _providerLabel(profile.provider)),
      _InfoRow(label: 'Correo verificado', value: profile.emailVerified ? 'Sí' : 'No'),
      _InfoRow(label: 'Cuenta creada', value: _dateOrDash(profile.createdAt)),
      _InfoRow(label: 'Último acceso', value: _dateOrDash(profile.lastSignInAt)),
    ];
  }

  List<Widget> _activityRows(ActivitySummary summary) {
    return [
      _InfoRow(label: 'Movimientos', value: '${summary.totalCount}'),
      _InfoRow(label: 'Primer movimiento', value: _dateOrDash(summary.firstDate)),
      _InfoRow(label: 'Último movimiento', value: _dateOrDash(summary.lastDate)),
      _InfoRow(label: 'Datos de ejemplo', value: '${summary.demoCount}'),
      _InfoRow(label: 'Añadidos a mano', value: '${summary.manualCount}'),
      _InfoRow(label: 'Por lenguaje natural', value: '${summary.naturalLanguageCount}'),
      _InfoRow(label: 'Desde nómina en PDF', value: '${summary.payrollCount}'),
      _InfoRow(label: 'Ingresos totales', value: formatCents(summary.incomeCents)),
      _InfoRow(label: 'Gastos totales', value: formatCents(-summary.expenseCents)),
    ];
  }

  String _providerLabel(SignInProvider provider) => switch (provider) {
    SignInProvider.password => 'Correo y contraseña',
    SignInProvider.google => 'Google',
  };

  String _dateOrDash(DateTime? date) => date == null ? '—' : formatDate(date);
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children, this.titleColor});

  final String title;
  final List<Widget> children;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(color: titleColor),
            ),
            const SizedBox(height: AppSpacing.s),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
