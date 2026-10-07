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

/// Busca la categoría cuyo nombre de enum coincida con [name], o `null` si
/// no existe. Útil para validar valores que llegan como texto (por ejemplo,
/// desde la IA).
Category? categoryFromName(String name) {
  for (final category in Category.values) {
    if (category.name == name) return category;
  }
  return null;
}
