/// Fixed notice that always accompanies the glossary on screen: it's
/// general information in plain language, not tax or labor advice.
const payrollGlossaryDisclaimer =
    'Estas descripciones son solo informativas, en lenguaje sencillo: no son '
    'asesoramiento fiscal ni laboral.';

/// Text for a deduction concept whose name isn't in the glossary.
const payrollGlossaryUnknownDescription = 'sin descripción';

/// Fixed, plain-language descriptions of the deduction concepts that
/// have shown up so far in test payrolls. Deliberately without
/// specific contribution rates (they change over time and aren't this
/// screen's purpose): only what each concept is, not how much is paid
/// for it. The keys are normalized (see [normalizePayrollConcept]):
/// lowercase and without accents, so "IRPF", "Irpf" or "irpf" all find
/// the same entry.
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

/// Strips accents, lowercases, and collapses extra spaces, so the
/// glossary lookup doesn't depend on how the model copied accent marks,
/// capitalization, or spacing.
String normalizePayrollConcept(String concept) {
  var normalized = concept.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  // After `toLowerCase()`, only lowercase letters can remain, accented or not.
  const withAccents = 'áéíóúñ';
  const withoutAccents = 'aeioun';
  for (var i = 0; i < withAccents.length; i++) {
    normalized = normalized.replaceAll(withAccents[i], withoutAccents[i]);
  }
  return normalized;
}

/// `true` if [text] (already normalized) contains [key] as a whole
/// word or acronym: with a word boundary (`\b`) on both ends, so "mei"
/// matches "... (mei)" or "mei ..." but not "premeido" (where "mei" is
/// a substring with no word boundary on either side).
bool _containsWholeWord(String text, String key) {
  return RegExp('\\b${RegExp.escape(key)}\\b').hasMatch(text);
}

/// Plain-language description for [concept], or
/// [payrollGlossaryUnknownDescription] if no glossary key appears as a
/// whole word or acronym inside normalized [concept] (see
/// [normalizePayrollConcept] and [_containsWholeWord]): the model
/// often returns the full name with the acronym in parentheses (for
/// example "IRPF (retención a cuenta)"), which is no longer an exact
/// match with any key, but does contain it as a whole word.
String payrollGlossaryDescription(String concept) {
  final normalized = normalizePayrollConcept(concept);
  for (final entry in _glossary.entries) {
    if (_containsWholeWord(normalized, entry.key)) return entry.value;
  }
  return payrollGlossaryUnknownDescription;
}
