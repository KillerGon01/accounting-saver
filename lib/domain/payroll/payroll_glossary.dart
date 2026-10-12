/// Aviso fijo que acompaña siempre al glosario en pantalla: es información
/// general en lenguaje sencillo, no asesoramiento fiscal o laboral.
const payrollGlossaryDisclaimer =
    'Estas descripciones son solo informativas, en lenguaje sencillo: no son '
    'asesoramiento fiscal ni laboral.';

/// Texto para un concepto de deducción cuyo nombre no está en el glosario.
const payrollGlossaryUnknownDescription = 'sin descripción';

/// Descripciones fijas, en lenguaje sencillo, de los conceptos de deducción
/// que han aparecido hasta ahora en las nóminas de prueba. Deliberadamente
/// sin tipos de cotización concretos (cambian con el tiempo y no son el
/// objetivo de esta pantalla): solo qué es cada concepto, no cuánto se paga
/// por él. Las claves están normalizadas (ver [normalizePayrollConcept]):
/// minúsculas y sin acentos, para que "IRPF", "Irpf" o "irpf" encuentren la
/// misma entrada.
const _glossary = <String, String>{
  'contingencias comunes':
      'Parte de la cotización a la Seguridad Social que financia '
          'prestaciones como la baja por enfermedad o la jubilación.',
  'desempleo': 'Cotización que financia la prestación por desempleo.',
  'formacion profesional':
      'Cotización que financia la formación de las personas trabajadoras.',
  'mecanismo de equidad intergeneracional':
      'Cotización adicional a la Seguridad Social para reforzar el sistema '
          'de pensiones; su importe varía según el año.',
  'mei': 'Cotización adicional a la Seguridad Social para reforzar el '
      'sistema de pensiones; su importe varía según el año.',
  'irpf': 'Parte del Impuesto sobre la Renta que la empresa retiene de tu '
      'sueldo y paga a Hacienda en tu nombre; su porcentaje depende de tus '
      'circunstancias.',
};

/// Quita acentos, pasa a minúsculas y colapsa espacios de más, para que la
/// búsqueda en el glosario no dependa de cómo haya copiado el modelo las
/// tildes, las mayúsculas o los espacios.
String normalizePayrollConcept(String concept) {
  var normalized = concept.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  // Tras `toLowerCase()` solo pueden quedar minúsculas, acentuadas o no.
  const withAccents = 'áéíóúñ';
  const withoutAccents = 'aeioun';
  for (var i = 0; i < withAccents.length; i++) {
    normalized = normalized.replaceAll(withAccents[i], withoutAccents[i]);
  }
  return normalized;
}

/// `true` si [text] (ya normalizado) contiene [key] como palabra o sigla
/// completa: con un límite de palabra (`\b`) en los dos extremos, para que
/// "mei" encuentre "... (mei)" o "mei ..." pero no "premeido" (donde "mei"
/// es una subcadena sin límite de palabra a ningún lado).
bool _containsWholeWord(String text, String key) {
  return RegExp('\\b${RegExp.escape(key)}\\b').hasMatch(text);
}

/// Descripción en lenguaje sencillo para [concept], o
/// [payrollGlossaryUnknownDescription] si ninguna clave del glosario
/// aparece como palabra o sigla completa dentro de [concept] normalizado
/// (ver [normalizePayrollConcept] y [_containsWholeWord]): el modelo suele
/// devolver el nombre completo con la sigla entre paréntesis (por ejemplo
/// "IRPF (retención a cuenta)"), que ya no es una igualdad exacta con
/// ninguna clave, pero sí la contiene como palabra completa.
String payrollGlossaryDescription(String concept) {
  final normalized = normalizePayrollConcept(concept);
  for (final entry in _glossary.entries) {
    if (_containsWholeWord(normalized, entry.key)) return entry.value;
  }
  return payrollGlossaryUnknownDescription;
}
