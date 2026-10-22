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
    required this.dias,
    required this.selecionado,
    required this.indiceHoje,
    required this.feitas,
    required this.onSelecionar,
    this.estreito = false,
  });

  final List<Dia> dias;
  final int selecionado;
  final int indiceHoje;

  /// Concluídas por dia, na mesma ordem de [dias].
  final List<int> feitas;

  final ValueChanged<int> onSelecionar;

  /// Layout compacto (tela pequena).
  final bool estreito;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    return Row(
      children: [
        for (var i = 0; i < dias.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == dias.length - 1 ? 0 : 6),
              child: _Aba(
                dia: dias[i],
                selecionada: i == selecionado,
                hoje: i == indiceHoje,
                feitas: feitas[i],
                total: dias[i].atividades.length,
                estreito: estreito,
                paleta: paleta,
                onTap: () => onSelecionar(i),
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
    required this.selecionada,
    required this.hoje,
    required this.feitas,
    required this.total,
    required this.estreito,
    required this.paleta,
    required this.onTap,
  });

  final Dia dia;
  final bool selecionada;
  final bool hoje;
  final int feitas;
  final int total;
  final bool estreito;
  final PaletaUi paleta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final corTexto = selecionada ? paleta.fundo : paleta.texto;
    final corSecundaria = selecionada
        ? paleta.fundo.withValues(alpha: 0.85)
        : paleta.textoSecundario;

    return Semantics(
      button: true,
      selected: selecionada,
      label: '${dia.nomeExibido}, $feitas de $total atividades',
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
                  Text(
                    '$feitas/$total',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: corSecundaria,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
