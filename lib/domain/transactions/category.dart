enum Category {
  supermercado,
  restaurantes,
  transporte,
  suscripciones,
  ocio,
  salud,
  hogar,
  nomina,
  otros,
}

/// Looks up the category whose enum name matches [name], or `null` if
/// none exists. Useful for validating values that arrive as text (for
/// example, from the AI).
Category? categoryFromName(String name) {
  for (final category in Category.values) {
    if (category.name == name) return category;
  }
  return null;
}
