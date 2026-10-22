import 'package:flutter/material.dart';
import 'package:planner_core/planner_core.dart';
import 'package:planner_ui/planner_ui.dart';

/// Seletor de dia: as sete abas com contador de concluídas.
///
/// No celular o contador some (o original faz o mesmo em < 440 px); o nome
/// curto e o destaque do dia de hoje permanecem.
class AbasDia extends StatelessWidget {
  const AbasDia({
    super.key,
    required this.agenda,
    required this.onSelecionar,
    this.estreito = false,
    this.hoje,
  });

  /// A semana exibida, com as marcações daquelas datas.
  final Agenda agenda;

  /// Recebe a data tocada (não o índice): quem chama abre aquele dia.
  final ValueChanged<DateTime> onSelecionar;

  /// Layout compacto (tela pequena).
  final bool estreito;

  /// Data de hoje, para destacar a aba — `null` para não destacar nenhuma.
  final DateTime? hoje;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    final datas = agenda.datas;
    return Row(
      children: [
        for (var i = 0; i < datas.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == datas.length - 1 ? 0 : 6),
              child: _Aba(
                dia: agenda.diaDaData(datas[i]),
                data: datas[i],
                selecionada: Datas.mesmoDia(datas[i], agenda.selecionado),
                hoje: hoje != null && Datas.mesmoDia(datas[i], hoje!),
                feitas: agenda.feitasEm(datas[i]),
                total: agenda.totalEm(datas[i]),
                estrela: agenda.percentualEm(datas[i]) == 100 && agenda.totalEm(datas[i]) > 0,
                estreito: estreito,
                paleta: paleta,
                onTap: () => onSelecionar(datas[i]),
              ),
            ),
          ),
      ],
    );
  }
}

class _Aba extends StatelessWidget {
  const _Aba({
    required this.dia,
    required this.data,
    required this.selecionada,
    required this.hoje,
    required this.feitas,
    required this.total,
    required this.estreito,
    required this.paleta,
    required this.onTap,
    this.estrela = false,
  });

  final Dia dia;
  final DateTime data;
  final bool selecionada;
  final bool hoje;
  final int feitas;
  final int total;
  final bool estreito;
  final PaletaUi paleta;
  final VoidCallback onTap;

  /// Dia com tudo feito: ganha um marcador discreto.
  final bool estrela;

  @override
  Widget build(BuildContext context) {
    final corTexto = selecionada ? paleta.fundo : paleta.texto;
    final corSecundaria = selecionada
        ? paleta.fundo.withValues(alpha: 0.85)
        : paleta.textoSecundario;

    return Semantics(
      button: true,
      selected: selecionada,
      label:
          '${dia.nomeExibido}, ${Datas.dataCurta(data)}, '
          '$feitas de $total atividades',
      child: Material(
        color: selecionada ? paleta.destaque : paleta.superficie,
        borderRadius: BorderRadius.circular(paleta.raioMedio),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(paleta.raioMedio),
          child: Container(
            padding: EdgeInsets.symmetric(
              vertical: estreito ? 7 : 8,
              horizontal: 2,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(paleta.raioMedio),
              border: Border.all(
                color: selecionada
                    ? paleta.destaque
                    : hoje
                    ? paleta.destaque
                    : paleta.borda,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dia.nomeCurto,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 15,
                    color: corTexto,
                  ),
                ),
                if (!estreito) ...[
                  const SizedBox(height: 2),
                  // A data é o que liga a aba ao calendário: sem ela, duas
                  // quartas seguidas seriam visualmente idênticas.
                  Text(
                    '${data.day}',
                    style: TextStyle(
                      fontSize: 11,
                      color: corSecundaria,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    '$feitas/$total',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: corSecundaria,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                if (estrela) ...[
                  const SizedBox(height: 2),
                  Icon(Icons.check_circle, size: 11, color: corSecundaria),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
