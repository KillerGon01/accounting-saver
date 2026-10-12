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
- Pendiente: Dockerizar la web (nginx), CI con GitHub Actions y Husky.
- Una rama por funcionalidad (feature/...), PR hacia main. No commitear directamente en main.
- Al terminar cada tarea, actualiza la sección "Estado" de este archivo:
  qué se ha hecho y cuál es el siguiente paso. Mantenla en 4-5 líneas.
  Muéstrame el cambio, pero no hagas commit.
- Documentar el proceso en docs/ (analysis, design, testing, security). Al cerrar
    cada funcionalidad, actualizar el documento que corresponda.

## Estado
Hecho: MVP completo y, nuevo, la lectura de nóminas en PDF (solo web) a partir de la prueba de
viabilidad desechable (`trial/payroll-pdf-reading`): `PayrollGateway`/`GeminiPayrollGateway`
(`InlineDataPart` + `responseSchema`, mismo fallback/reintento/timeout que el resto de la IA),
`PayrollValidation` en código (nunca del modelo) y `PayrollScreen`, con selector de archivo por
import condicional (`package:web`, ahora dependencia directa) para no romper Android ni
`flutter test`. Reglas de Firestore con `payroll` como origen válido, probadas contra el
emulador real. Resultados de la prueba de viabilidad en docs/evaluation.md. Tests: 417.
Pendiente: lo de antes (ajustar `_checkMonthAttribution`, flutter_localizations, registro
abierto, App Check de producción en Android, `thinkingConfig`, CI para `firestore-tests/`,
repetir la evaluación del chat con `transactionLines`) más decidir si el límite de 5 lecturas
de nómina por sesión debe compartir algún tope con el chat/lenguaje natural (cuota compartida).
Siguiente: decidir los pendientes de seguridad antes de la entrega (26/10).