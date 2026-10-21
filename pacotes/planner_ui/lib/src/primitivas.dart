import 'package:flutter/material.dart';

import 'paleta.dart';

/// Caixa de superfície: o `section.box` do planejador original.
class CaixaUi extends StatelessWidget {
  const CaixaUi({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 8),
    this.cor,
    this.corBorda,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? cor;
  final Color? corBorda;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: cor ?? paleta.superficie,
        borderRadius: BorderRadius.circular(paleta.raioGrande),
        border: Border.all(color: corBorda ?? paleta.borda),
      ),
      child: child,
    );
  }
}

/// Botão com peso visual de ação principal.
class BotaoUi extends StatelessWidget {
  const BotaoUi({
    super.key,
    required this.rotulo,
    this.onPressed,
    this.secundario = false,
    this.icone,
  });

  final String rotulo;
  final VoidCallback? onPressed;

  /// Variante discreta (fundo transparente, borda neutra).
  final bool secundario;

  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    final desabilitado = onPressed == null;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: secundario ? Colors.transparent : paleta.destaqueSuave,
        foregroundColor: secundario ? paleta.textoSecundario : paleta.texto,
        disabledForegroundColor: paleta.textoSecundario.withValues(alpha: 0.6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(paleta.raioMedio - 2),
          side: BorderSide(color: secundario ? paleta.borda : paleta.destaque),
        ),
        // O estilo deriva do tema: um `TextStyle` criado do zero perde a
        // família tipográfica e o texto some no navegador (a fonte padrão do
        // motor não é servida pelo CSP).
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 18, color: desabilitado ? paleta.textoSecundario : null),
            const SizedBox(width: 6),
          ],
          Text(rotulo),
        ],
      ),
    );
  }
}

/// Etiqueta compacta de metadado (ex.: "compromisso fixo").
class EtiquetaUi extends StatelessWidget {
  const EtiquetaUi(this.texto, {super.key, required this.cor});

  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: TextStyle(
        fontSize: 10.5,
        letterSpacing: 0.7,
        fontWeight: FontWeight.w600,
        color: cor,
      ),
    );
  }
}

/// Legenda com um ponto de cor e um rótulo.
class LegendaUi extends StatelessWidget {
  const LegendaUi({super.key, required this.cor, required this.rotulo});

  final Color cor;
  final String rotulo;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(rotulo, style: TextStyle(fontSize: 13, color: paleta.textoSecundario)),
      ],
    );
  }
}

/// Estado vazio ou informativo, com ícone e ação opcional.
class VazioUi extends StatelessWidget {
  const VazioUi({super.key, required this.icone, required this.titulo, this.descricao, this.acao});

  final IconData icone;
  final String titulo;
  final String? descricao;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 36, color: paleta.textoSecundario),
          const SizedBox(height: 12),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: paleta.texto),
          ),
          if (descricao != null) ...[
            const SizedBox(height: 6),
            Text(
              descricao!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: paleta.textoSecundario),
            ),
          ],
          if (acao != null) ...[const SizedBox(height: 16), acao!],
        ],
      ),
    );
  }
}

/// Faixa de erro com ação de dispensar.
class FaixaErroUi extends StatelessWidget {
  const FaixaErroUi({super.key, required this.mensagem, this.onDispensar});

  final String mensagem;
  final VoidCallback? onDispensar;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: paleta.movimento.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(paleta.raioMedio),
        border: Border.all(color: paleta.movimento.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: paleta.movimento),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mensagem,
              style: TextStyle(fontSize: 13.5, color: paleta.texto),
            ),
          ),
          if (onDispensar != null)
            IconButton(
              onPressed: onDispensar,
              icon: const Icon(Icons.close, size: 16),
              color: paleta.textoSecundario,
              tooltip: 'Dispensar',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// Barra de progresso fina e arredondada.
class BarraProgressoUi extends StatelessWidget {
  const BarraProgressoUi({super.key, required this.valor, this.altura = 8});

  /// Fração de 0 a 1.
  final double valor;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: altura,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: paleta.borda),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: valor.clamp(0, 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  color: paleta.destaque,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
