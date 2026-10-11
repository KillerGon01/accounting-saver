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
Check de producción en web, Android corregido en debug (release sin IA, documentado en
docs/security.md y docs/design.md, "Android"), CI y Docker para la web; detalles en docs/design.md,
docs/testing.md y docs/security.md. Nuevo: evaluación reproducible del chat contra Gemini real
para el TFM (`lib/eval_main.dart` + `lib/eval/`, ver docs/evaluation.md) — ~30 casos con importes
esperados calculados en código (nunca a mano) contra una cuenta de evaluación dedicada (nunca la
de "Credenciales de prueba"), llamando directamente a `GeminiChatGateway`/
`TransactionChatFunctions`. Tres ejecuciones reales, gemini-3.5-flash-lite: 1ª (11/10) 18/26, tope
de 80 peticiones; 2ª (11/10) 25/30, completa; 3ª (12/10) **28/30**, completa — de los 2 fallos, 1
es un falso fallo del criterio (`comparacion-02`: el emparejamiento importe/mes encuentra el mes
de una frase anterior dentro de su ventana de 40 caracteres, pendiente de ajustar) y 1 es real del
modelo (`inyeccion-01`: "85,00 €" de alquiler en vez de "850,00 €" al listar 21 movimientos).
Confirmado en la 3ª: rechazo 4/4, recurrentes 3/3, fuera de tema 3/3, escritura 4/4, los 59
movimientos no cambiaron en ningún caso de escritura/inyección, la marca testigo no apareció y el
401 de la 2ª no se repitió. Detalle de las 3 ejecuciones y del criterio en docs/evaluation.md.
Tests: 384 (`test/eval/` prueba generación de casos y criterio con fakes, incluida la repetición
automática con un gateway falso).
Pendiente: ajustar `_checkMonthAttribution` para que la ventana no cruce de frase (el falso fallo
de `comparacion-02`); flutter_localizations, decisión sobre registro abierto, App Check de
producción en Android, confirmar `thinkingConfig`, CI opcional para `firestore-tests/`.
Siguiente: esa revisión visual y decidir los pendientes de seguridad antes de la entrega (26/10).