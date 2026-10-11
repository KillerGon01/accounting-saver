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

## Datos
users/{uid}/transactions/{id}: amountCents (int, negativo = gasto), date,
description, categoryId, source, createdAt. Categorías fijas en código.

## Convenciones
- Commits: "[ADDED|CHANGED|REMOVED] Resumen corto" (texto en inglés).
- google-services.json está en .gitignore.
- Sin secretos en el repo. Reglas de Firestore: cada usuario solo lee lo suyo.
- Pendiente: Dockerizar la web (nginx), CI con GitHub Actions y Husky.
- Una rama por funcionalidad (feature/...), PR hacia main. No commitear directamente en main.
- Al terminar cada tarea, actualiza la sección "Estado" de este archivo:
  qué se ha hecho y cuál es el siguiente paso. Mantenla en 4-5 líneas.
  Muéstrame el cambio, pero no hagas commit.
- Documentar el proceso en docs/ (analysis, design, testing, security). Al cerrar
    cada funcionalidad, actualizar el documento que corresponda.

## Estado
Hecho: MVP completo (login, movimientos, lenguaje natural, chat con function calling, datos
demo, resumen mensual con gráficos) tras `ENABLE_AI`, con protección de cuota de Gemini, App
Check de producción en web, CI y Docker para la web; detalles en docs/design.md, docs/testing.md
y docs/security.md. Android, en la rama `fix/android-layout`: corregidos dos desbordamientos de
layout en pantallas pequeñas (teclado abierto en los estados vacíos, y ancho estrecho en el
resumen mensual y el desplegable de categoría) y arreglado que un release de Android con clave de
reCAPTCHA mostrara la IA y fallara con 403 — `chooseAppCheckConfig` (`lib/app_check_config.dart`)
recibe ahora `isWeb` (`kIsWeb`): en release, `effectiveEnableAi` solo puede ser verdadero en web;
en cualquier otra plataforma se oculta igual que con `ENABLE_AI=false`, sin activar App Check.
Documentado en README ("Limitaciones conocidas"), docs/security.md (sección "Android", con tabla
de los 7 casos) y docs/design.md ("Android"), con el comando para generar el APK de depuración.
Nuevo: la clave de API de Android (`google-services.json`) está restringida en Google Cloud por
nombre de paquete y por la huella SHA-1 de depuración, comprobado el 11/10/2026 en un móvil
físico; corregida una tabla de App Check en docs/security.md que había quedado desactualizada
tras el cambio de `isWeb` (seguía diciendo que un release de Android con clave mostraba la IA).
Recontados los tests: 333 (antes decían 331 en README y docs/testing.md).
Pendiente: flutter_localizations, decisión sobre registro abierto, App Check de producción en
Android, revisión visual en navegador, confirmar `thinkingConfig`, CI opcional para
`firestore-tests/`.
Siguiente: esa revisión visual y decidir los pendientes de seguridad antes de la entrega (26/10).