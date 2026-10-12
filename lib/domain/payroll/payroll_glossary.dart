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

/// Quita acentos y pasa a minúsculas, para que la búsqueda en el glosario
/// no dependa de cómo haya copiado el modelo las tildes o las mayúsculas.
String normalizePayrollConcept(String concept) {
  var normalized = concept.trim().toLowerCase();
  // Tras `toLowerCase()` solo pueden quedar minúsculas, acentuadas o no.
  const withAccents = 'áéíóúñ';
  const withoutAccents = 'aeioun';
  for (var i = 0; i < withAccents.length; i++) {
    normalized = normalized.replaceAll(withAccents[i], withoutAccents[i]);
  }
  return normalized;
}

/// Descripción en lenguaje sencillo para [concept], o
/// [payrollGlossaryUnknownDescription] si no está en el glosario.
String payrollGlossaryDescription(String concept) {
  return _glossary[normalizePayrollConcept(concept)] ?? payrollGlossaryUnknownDescription;
}
