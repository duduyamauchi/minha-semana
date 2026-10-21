import 'package:flutter/material.dart';
import 'package:planner_core/planner_core.dart';
import 'package:planner_ui/planner_ui.dart';


import '../core/cores.dart';

/// Uma linha da timeline: horário, bloco colorido por categoria e checkbox.
///
/// O visual preserva as decisões do planejador original:
/// - a barra à esquerda é a cor da categoria;
/// - o bloco prioritário ganha fundo verde-claro;
/// - "compromisso fixo" aparece em maiúsculas pequenas;
/// - concluída: título riscado e esmaecido.
class LinhaAtividade extends StatelessWidget {
  const LinhaAtividade({
    super.key,
    required this.atividade,
    required this.concluida,
    required this.onAlternar,
    this.estreito = false,
  });

  final Atividade atividade;
  final bool concluida;
  final VoidCallback onAlternar;
  final bool estreito;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    final corCategoria = atividade.categoria.cor(context.cores);

    final titulo = Text(
      atividade.titulo,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: concluida ? paleta.textoSecundario : paleta.texto,
        decoration: concluida ? TextDecoration.lineThrough : null,
        decorationColor: paleta.textoSecundario,
      ),
    );

    return Semantics(
      checked: concluida,
      inMutuallyExclusiveGroup: false,
      label: '${atividade.titulo}, ${atividade.horario}',
      child: InkWell(
        onTap: onAlternar,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: paleta.borda)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: estreito ? 48 : 54,
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    atividade.horario,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: paleta.textoSecundario,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: atividade.prioridade
                      ? const EdgeInsets.fromLTRB(10, 6, 10, 6)
                      : const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(
                    color: atividade.prioridade ? paleta.destaqueSuave : null,
                    border: Border(left: BorderSide(color: corCategoria, width: 3)),
                    borderRadius: atividade.prioridade
                        ? const BorderRadius.horizontal(right: Radius.circular(8))
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(child: titulo),
                          if (atividade.fixo) ...[
                            const SizedBox(width: 8),
                            EtiquetaUi('COMPROMISSO FIXO', cor: context.cores.movimento),
                          ],
                        ],
                      ),
                      if (atividade.temDetalhe) ...[
                        const SizedBox(height: 2),
                        Text(
                          atividade.detalhe,
                          style: TextStyle(fontSize: 13, color: paleta.textoSecundario, height: 1.35),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _CaixaMarcacao(concluida: concluida, onTap: onAlternar, paleta: paleta),
            ],
          ),
        ),
      ),
    );
  }
}

/// Checkbox desenhado à mão: quadrado arredondado com tique, como no HTML.
class _CaixaMarcacao extends StatelessWidget {
  const _CaixaMarcacao({required this.concluida, required this.onTap, required this.paleta});

  final bool concluida;
  final VoidCallback onTap;
  final PaletaUi paleta;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: concluida ? 'desmarcar' : 'marcar como feito',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: concluida ? paleta.destaque : paleta.superficie,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: concluida ? paleta.destaque : paleta.borda,
                width: 2,
              ),
            ),
            child: concluida
                ? Icon(Icons.check, size: 15, color: paleta.fundo, weight: 700)
                : null,
          ),
        ),
      ),
    );
  }
}
