import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:planner_core/planner_core.dart';
import 'package:planner_ui/planner_ui.dart';

import '../core/cores.dart';

/// Uma linha da timeline: horário (com duração), bloco colorido e checkbox.
///
/// O visual preserva as decisões do planejador original:
/// - a barra à esquerda é a cor da categoria;
/// - o bloco prioritário ganha fundo verde-claro;
/// - "compromisso fixo" aparece em maiúsculas pequenas;
/// - concluída: título riscado e esmaecido.
///
/// O que mudou com o plano editável: **tocar na linha abre o editor**, e o
/// checkbox (alvo separado) marca/desmarca. Antes a linha inteira alternava a
/// marcação — com edição, isso tornaria impossível abrir uma atividade sem
/// mexer no progresso.
class LinhaAtividade extends StatelessWidget {
  const LinhaAtividade({
    super.key,
    required this.atividade,
    required this.concluida,
    required this.onAlternar,
    required this.onEditar,
    required this.onExcluir,
    this.estreito = false,
    this.editavel = true,
  });

  final Atividade atividade;
  final bool concluida;
  final VoidCallback onAlternar;
  final VoidCallback onEditar;
  final VoidCallback onExcluir;
  final bool estreito;

  /// Falso quando a fonte é somente leitura.
  final bool editavel;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    final corCategoria = atividade.categoria.cor(context.cores);

    return Semantics(
      label: _descricao,
      customSemanticsActions: editavel
          ? {
              const CustomSemanticsAction(label: 'Editar'): onEditar,
              const CustomSemanticsAction(label: 'Excluir'): onExcluir,
            }
          : null,
      child: InkWell(
        onTap: editavel ? onEditar : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: paleta.borda)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: estreito ? 62 : 66,
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        atividade.horario,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: paleta.textoSecundario,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (atividade.duracaoMinutos != null)
                        Text(
                          '${atividade.duracaoTexto} · até ${atividade.termino}',
                          style: TextStyle(
                            fontSize: 11,
                            color: paleta.textoSecundario.withValues(
                              alpha: 0.9,
                            ),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  padding: atividade.prioridade
                      ? const EdgeInsets.fromLTRB(10, 6, 10, 6)
                      : const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(
                    color: atividade.prioridade ? paleta.destaqueSuave : null,
                    border: Border(
                      left: BorderSide(color: corCategoria, width: 3),
                    ),
                    borderRadius: atividade.prioridade
                        ? const BorderRadius.horizontal(
                            right: Radius.circular(8),
                          )
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              atividade.titulo,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: concluida
                                    ? paleta.textoSecundario
                                    : paleta.texto,
                                decoration: concluida
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: paleta.textoSecundario,
                              ),
                            ),
                          ),
                          if (atividade.fixo) ...[
                            const SizedBox(width: 8),
                            EtiquetaUi(
                              'COMPROMISSO FIXO',
                              cor: context.cores.movimento,
                            ),
                          ],
                        ],
                      ),
                      if (atividade.temDetalhe) ...[
                        const SizedBox(height: 2),
                        Text(
                          atividade.detalhe,
                          style: TextStyle(
                            fontSize: 13,
                            color: paleta.textoSecundario,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _CaixaMarcacao(
                key: ValueKey('marcar-${atividade.id}'),
                concluida: concluida,
                onTap: onAlternar,
                paleta: paleta,
                rotulo: atividade.titulo,
              ),
              if (editavel)
                SizedBox(
                  width: 32,
                  height: 30,
                  child: PopupMenuButton<String>(
                    tooltip: 'Opções de ${atividade.titulo}',
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: paleta.textoSecundario,
                    ),
                    color: paleta.superficie,
                    onSelected: (acao) =>
                        acao == 'excluir' ? onExcluir() : onEditar(),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'editar',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Editar'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'excluir',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: context.cores.movimento,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Excluir',
                              style: TextStyle(color: context.cores.movimento),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _descricao {
    final partes = [atividade.titulo, 'às ${atividade.horario}'];
    if (atividade.duracaoMinutos != null) {
      partes.add('duração ${atividade.duracaoTexto}');
    }
    if (concluida) partes.add('concluída');
    return partes.join(', ');
  }
}

/// Checkbox desenhado à mão: quadrado arredondado com tique, como no HTML.
class _CaixaMarcacao extends StatelessWidget {
  const _CaixaMarcacao({
    super.key,
    required this.concluida,
    required this.onTap,
    required this.paleta,
    required this.rotulo,
  });

  final bool concluida;
  final VoidCallback onTap;
  final PaletaUi paleta;
  final String rotulo;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: concluida ? 'Desmarcar $rotulo' : 'Marcar $rotulo como feito',
      checked: concluida,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(4),
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
                ? Icon(Icons.check, size: 15, color: paleta.fundo)
                : null,
          ),
        ),
      ),
    );
  }
}
