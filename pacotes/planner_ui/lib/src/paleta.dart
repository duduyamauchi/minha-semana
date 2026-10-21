import 'package:flutter/material.dart';

/// Paleta que o app injeta nas primitivas compartilhadas.
///
/// O pacote define **estrutura**, não aparência: um segundo produto (um painel
/// administrativo, por exemplo) pode ter outra paleta sem tocar nos widgets.
/// As cores vêm do planejador HTML original — verde-petróleo sobre papel
/// esverdeado, com quatro cores de categoria.
class PaletaUi {
  const PaletaUi({
    required this.fundo,
    required this.superficie,
    required this.borda,
    required this.texto,
    required this.textoSecundario,
    required this.destaque,
    required this.destaqueSuave,
    required this.estudo,
    required this.movimento,
    required this.casa,
    required this.bemEstar,
    this.raioMedio = 12,
    this.raioGrande = 16,
  });

  final Color fundo;
  final Color superficie;
  final Color borda;
  final Color texto;
  final Color textoSecundario;

  /// Verde-petróleo: barra de progresso, aba selecionada, checkbox marcado.
  final Color destaque;

  /// Fundo do bloco prioritário e dos botões.
  final Color destaqueSuave;

  final Color estudo;
  final Color movimento;
  final Color casa;
  final Color bemEstar;

  final double raioMedio;
  final double raioGrande;

  /// Paleta clara padrão (a mesma do `:root` do HTML).
  static const clara = PaletaUi(
    fundo: Color(0xFFF3F5F2),
    superficie: Color(0xFFFFFFFF),
    borda: Color(0xFFDBE2DE),
    texto: Color(0xFF1D2A26),
    textoSecundario: Color(0xFF5D6B66),
    destaque: Color(0xFF2F6F62),
    destaqueSuave: Color(0xFFDCEBE6),
    estudo: Color(0xFF4B5FBF),
    movimento: Color(0xFFC4572E),
    casa: Color(0xFF2F8A63),
    bemEstar: Color(0xFF8A6A1F),
  );

  /// Paleta escura — o bloco `prefers-color-scheme: dark` do HTML.
  static const escura = PaletaUi(
    fundo: Color(0xFF141B19),
    superficie: Color(0xFF1C2522),
    borda: Color(0xFF2D3935),
    texto: Color(0xFFE7EEEB),
    textoSecundario: Color(0xFF9AA9A3),
    destaque: Color(0xFF6FC2AE),
    destaqueSuave: Color(0xFF22403A),
    estudo: Color(0xFF8D9BF0),
    movimento: Color(0xFFEE8A62),
    casa: Color(0xFF6DCF9F),
    bemEstar: Color(0xFFD7B25A),
  );
}

/// Disponibiliza a [PaletaUi] para as primitivas.
class EscopoUi extends InheritedWidget {
  const EscopoUi({super.key, required this.paleta, required super.child});

  final PaletaUi paleta;

  static PaletaUi de(BuildContext context) {
    final escopo = context.dependOnInheritedWidgetOfExactType<EscopoUi>();
    assert(escopo != null, 'EscopoUi ausente: envolva a árvore com EscopoUi.');
    return escopo!.paleta;
  }

  @override
  bool updateShouldNotify(EscopoUi antigo) => antigo.paleta != paleta;
}
