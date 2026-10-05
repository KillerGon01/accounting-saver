import 'package:flutter/material.dart';

import '../../domain/transactions/category.dart';

extension CategoryStyle on Category {
  IconData get icon => switch (this) {
    Category.supermercado => Icons.shopping_cart_outlined,
    Category.restaurantes => Icons.restaurant_outlined,
    Category.transporte => Icons.directions_bus_outlined,
    Category.suscripciones => Icons.autorenew,
    Category.ocio => Icons.movie_outlined,
    Category.salud => Icons.favorite_outline,
    Category.hogar => Icons.home_outlined,
    Category.nomina => Icons.payments_outlined,
    Category.otros => Icons.category_outlined,
  };

  Color get color => switch (this) {
    Category.supermercado => const Color(0xFF43A047),
    Category.restaurantes => const Color(0xFFEF6C00),
    Category.transporte => const Color(0xFF1E88E5),
    Category.suscripciones => const Color(0xFF8E24AA),
    Category.ocio => const Color(0xFFD81B60),
    Category.salud => const Color(0xFFE53935),
    Category.hogar => const Color(0xFF6D4C41),
    Category.nomina => const Color(0xFF00897B),
    Category.otros => const Color(0xFF757575),
  };
}
