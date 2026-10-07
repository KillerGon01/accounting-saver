/// La interfaz de IA (entrada en lenguaje natural, y lo que venga después)
/// solo se activa si se compila con `--dart-define=ENABLE_AI=true`. Por
/// defecto está desactivada, para no exigir que cada persona que clona el
/// repositorio configure Firebase AI Logic y App Check solo para poder
/// compilar la app.
///
/// `main.dart` la usa para decidir si activa Firebase App Check (necesario
/// para llamar a Gemini); las pantallas la usan para ocultar los controles
/// de IA.
const enableAi = bool.fromEnvironment('ENABLE_AI');
