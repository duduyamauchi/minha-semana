import 'package:flutter/material.dart';
import 'package:planner_core/planner_core.dart';

/// Tradução da paleta de cores do domínio para as cores do tema.
///
/// Fica no app (e não no núcleo) porque `Color` é Flutter; o domínio só conhece
/// `Categoria`.
extension CoresCategoria on Categoria {
  Color cor(PaletaCores paleta) => switch (this) {
    Categoria.estudo => paleta.estudo,
    Categoria.movimento => paleta.movimento,
    Categoria.casa => paleta.casa,
    Categoria.bemEstar => paleta.bemEstar,
  };
}

/// As cores de categoria que o tema carrega.
class PaletaCores {
  const PaletaCores({
    required this.estudo,
    required this.movimento,
    required this.casa,
    required this.bemEstar,
  });

  final Color estudo;
  final Color movimento;
  final Color casa;
  final Color bemEstar;

  static const clara = PaletaCores(
    estudo: Color(0xFF4B5FBF),
    movimento: Color(0xFFC4572E),
    casa: Color(0xFF2F8A63),
    bemEstar: Color(0xFF8A6A1F),
  );

  static const escura = PaletaCores(
    estudo: Color(0xFF8D9BF0),
    movimento: Color(0xFFEE8A62),
    casa: Color(0xFF6DCF9F),
    bemEstar: Color(0xFFD7B25A),
  );
}

/// Atalho para as cores de categoria do tema atual.
///
/// Vive aqui, e não no tema, para que os widgets importem uma coisa só.
extension CoresDoContexto on BuildContext {
  PaletaCores get cores => Theme.of(this).brightness == Brightness.dark
      ? PaletaCores.escura
      : PaletaCores.clara;
}
