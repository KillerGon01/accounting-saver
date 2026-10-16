import 'package:flutter/material.dart';

/// Duraciones y comprobación únicas de `MediaQuery.disableAnimations` para
/// todas las animaciones de la app: un solo sitio que decide si hay que
/// animar o saltar directamente al estado final, en vez de repetir la
/// comprobación en cada widget.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);

  /// [duration] si las animaciones están activas; [Duration.zero] si
  /// `MediaQuery.of(context).disableAnimations` es `true` (el usuario las
  /// ha desactivado en el sistema) — con cero, los widgets implícitos de
  /// Flutter (`TweenAnimationBuilder`, `AnimatedOpacity`...) saltan al
  /// valor final en el siguiente frame, sin ningún efecto visible.
  static Duration of(BuildContext context, Duration duration) {
    return MediaQuery.of(context).disableAnimations ? Duration.zero : duration;
  }
}
