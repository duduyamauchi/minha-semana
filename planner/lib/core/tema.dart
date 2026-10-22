import 'package:flutter/material.dart';
import 'package:planner_ui/planner_ui.dart';

import 'cores.dart';

/// Tema do aplicativo.
///
/// As duas paletas são as do planejador HTML original — papel esverdeado no
/// claro, verde profundo no escuro —, e as tipografias também: Bricolage
/// Grotesque nos títulos, Figtree no corpo.
///
/// Os arquivos das fontes estão versionados no app para que o build não dependa
/// do Google Fonts em tempo de execução (o CSP não libera `fonts.gstatic.com`).
abstract final class Tema {
  static const familiaDisplay = 'BricolageGrotesque';
  static const familiaCorpo = 'Figtree';

  static ThemeData claro() => _montar(
    brightness: Brightness.light,
    paleta: PaletaUi.clara,
    scheme: const ColorScheme.light(
      primary: Color(0xFF2F6F62),
      onPrimary: Colors.white,
      secondary: Color(0xFF2F6F62),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF1D2A26),
      error: Color(0xFFC4572E),
    ),
  );

  static ThemeData escuro() => _montar(
    brightness: Brightness.dark,
    paleta: PaletaUi.escura,
    scheme: const ColorScheme.dark(
      primary: Color(0xFF6FC2AE),
      onPrimary: Color(0xFF141B19),
      secondary: Color(0xFF6FC2AE),
      surface: Color(0xFF1C2522),
      onSurface: Color(0xFFE7EEEB),
      error: Color(0xFFEE8A62),
    ),
  );

  /// Paleta de categorias correspondente ao brilho atual.
  static PaletaCores coresDe(Brightness brilho) =>
      brilho == Brightness.dark ? PaletaCores.escura : PaletaCores.clara;

  static ThemeData _montar({
    required Brightness brightness,
    required PaletaUi paleta,
    required ColorScheme scheme,
  }) {
    final base = ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: familiaCorpo,
      scaffoldBackgroundColor: paleta.fundo,
    );

    final display = TextStyle(
      fontFamily: familiaDisplay,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      color: paleta.texto,
    );

    // Todo estilo do `textTheme` precisa carregar a família: um `TextStyle`
    // novo, sem `fontFamily`, cai na fonte padrão do motor (Roboto), que o CSP
    // não carrega — o texto simplesmente não aparece no navegador. Por isso os
    // estilos abaixo derivam de `base.textTheme` em vez de serem criados do zero.
    final corpo = base.textTheme.bodyMedium!;
    final corpoPequeno = base.textTheme.bodySmall!;

    return base.copyWith(
      textTheme: base.textTheme
          .apply(bodyColor: paleta.texto, displayColor: paleta.texto)
          .copyWith(
            displaySmall: display.copyWith(fontSize: 33, height: 1.15),
            headlineSmall: display.copyWith(fontSize: 20, height: 1.25),
            titleMedium: display,
            bodyMedium: corpo.copyWith(
              fontSize: 15,
              height: 1.5,
              color: paleta.texto,
            ),
            bodySmall: corpoPequeno.copyWith(
              fontSize: 13,
              height: 1.45,
              color: paleta.textoSecundario,
            ),
          ),
      textSelectionTheme: TextSelectionThemeData(cursorColor: paleta.destaque),
      dividerTheme: DividerThemeData(
        color: paleta.borda,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: paleta.fundo,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        hintStyle: corpo.copyWith(color: paleta.textoSecundario, fontSize: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: paleta.borda),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: paleta.borda),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: paleta.destaque, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: paleta.texto,
        contentTextStyle: corpo.copyWith(
          color: paleta.superficie,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
