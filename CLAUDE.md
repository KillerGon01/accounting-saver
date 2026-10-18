# accounting-saver

TFM del Máster de Desarrollo con IA (Big School). Entrega: 26/10/2026.
Asistente financiero personal con IA (Gemini). Flutter + Firebase.

## Restricciones
- Coste cero: plan Spark de Firebase, sin Cloud Functions, sin facturación.
- Gemini vía Firebase AI Logic (nivel gratuito), llamado desde el cliente.
- Plataformas: web (prioritaria) y Android. Diseño responsive desde el principio.
- Respóndeme siempre en castellano (España).

## Arquitectura (Clean Architecture)
lib/domain (Dart puro, sin Firebase ni Flutter), lib/application (casos de uso),
lib/infrastructure (Firestore, Gemini, Auth), lib/presentation (Riverpod).
Gemini siempre detrás de la interfaz LlmGateway. Tests con fakes.

## Alcance MVP
Login (email/contraseña y Google), movimientos manuales, entrada en lenguaje
natural (JSON estructurado y validado), datos de demostración, chat con
function calling sobre Firestore, resumen mensual.
Fuera: CSV, foto de ticket (extra), presupuestos, multidivisa.
Extra implementado (fuera del MVP original): lectura de nóminas en PDF con IA,
solo web, con validación de bruto/deducciones/líquido en código (ver docs/design.md).

## Datos
users/{uid}/transactions/{id}: amountCents (int, negativo = gasto), date,
description, categoryId, source, createdAt. Categorías fijas en código.

## Convenciones
- Commits: "[ADDED|CHANGED|REMOVED] Resumen corto" (texto en inglés).
- google-services.json está en .gitignore.
- Sin secretos en el repo. Reglas de Firestore: cada usuario solo lee lo suyo.
- Hecho: Dockerizar la web (nginx) y CI con GitHub Actions. Mejora futura, no pendiente
  inminente: Husky (hooks de git locales); el CI ya cubre el mismo control (`flutter analyze`,
  `flutter test`) en cada PR, aunque no evita el commit en el equipo de quien lo hace.
- Una rama por funcionalidad (feature/...), PR hacia main. No commitear directamente en main.
- Al terminar cada tarea, actualiza la sección "Estado" de este archivo:
  qué se ha hecho y cuál es el siguiente paso. Mantenla en 4-5 líneas.
  Muéstrame el cambio, pero no hagas commit.
- Documentar el proceso en docs/ (analysis, design, testing, security). Al cerrar
    cada funcionalidad, actualizar el documento que corresponda.

## Estado
Hecho: todo lo anterior (MVP, nóminas en PDF, previsión de fin de mes, búsqueda y filtros,
gastos inusuales, metas de ahorro, sugerencias de ahorro con y sin IA) y, nuevo, un rediseño
visual y dos arreglos de autenticación en Android (detalle en docs/design.md/docs/security.md):
tema oscuro forzado (`ThemeMode.dark`, paleta propia con contraste AA comprobado), icono propio
en web y Android (adaptativo + monocromo, generado por `tool/generate_icons.dart`), avisos de
sesión (cierre de sesión y borrado de cuenta, en memoria vía `sessionFeedbackProvider`) y
animaciones con `AppMotion` (respeta `disableAnimations`); el login con Google en Android, que
usaba `signInWithProvider` y lo bloqueaba un 403 de `identitytoolkit`, sustituido por el SDK
nativo (`google_sign_in`, único paquete nuevo); ayuda contextual (`lib/presentation/help/`):
icono de ayuda en el `AppBar` de cada pantalla salvo login/crear cuenta/verificar correo (decisión
explícita, en Movimientos dentro de "Más opciones"), hoja modal con el título y los pasos en
castellano, límites numéricos leídos de las constantes reales del código (ver docs/design.md,
"Ayuda contextual"); y, nuevo, un aviso (`SnackBar`) estable al navegar desde Movimientos:
`hideCurrentSnackBar` antes de cada `Navigator.push` que sale de esa pantalla, para que no
salte de posición por el `FloatingActionButton` que tienen unas pantallas y no otras, más un
ancho máximo (560 px, centrado) y un margen fijos en el tema (ver docs/design.md, "Aviso
estable al navegar"). Tests: 705.
Pendiente: lo de antes (ajustar `_checkMonthAttribution`, flutter_localizations, registro
abierto, `thinkingConfig`, CI para `firestore-tests/`, cuota compartida entre nóminas, chat,
lenguaje natural, resumen mensual y sugerencias de ahorro) más los riesgos/límites ya
documentados en docs/design.md/docs/security.md (previsión de fin de mes, gastos inusuales,
metas de ahorro, sugerencias de ahorro con y sin IA: nivel gratuito de Gemini, Google puede usar
el contenido enviado) y, en Android, lo que sigue vigente: nombre de paquete por defecto
(`com.example.accounting_saver`), sin proveedor de App Check de producción (Play Integrity sin
vincular en Play Console) y `FirebaseAuthRepository` sin tests automatizados (verificado a mano
en móvil).
Siguiente: decidir los pendientes de seguridad antes de la entrega (26/10).