import 'package:flutter/material.dart';
import 'package:planner_core/planner_core.dart';
import 'package:planner_ui/planner_ui.dart';

/// Bloco "Reorganização da casa": descrição, checklist de cômodos e formulário.
///
/// No original, marcar um cômodo é a única coisa da seção que persiste; aqui é
/// igual — e o cômodo ganha um botão de remover, que o HTML não tinha (era
/// preciso editar o `localStorage` na mão).
class SecaoComodos extends StatefulWidget {
  const SecaoComodos({
    super.key,
    required this.comodos,
    required this.onAlternar,
    required this.onAdicionar,
    required this.onRemover,
    required this.estreito,
  });

  final List<Comodo> comodos;
  final void Function(Comodo comodo) onAlternar;
  final Future<bool> Function(String nome) onAdicionar;
  final void Function(Comodo comodo) onRemover;
  final bool estreito;

  @override
  State<SecaoComodos> createState() => _SecaoComodosState();
}

class _SecaoComodosState extends State<SecaoComodos> {
  final _controle = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _controle.dispose();
    super.dispose();
  }

  Future<void> _adicionar() async {
    final nome = _controle.text.trim();
    if (nome.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    final ok = await widget.onAdicionar(nome);
    if (!mounted) return;
    setState(() => _enviando = false);
    if (ok) _controle.clear();
  }

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    return CaixaUi(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reorganização da casa',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Um cômodo ou categoria por sessão, com as técnicas que você aprendeu. '
            'Prioridade do momento: os blocos verdes marcados como reorganização ocupam '
            'a maior parte de cada dia até a casa toda estar pronta.',
            style: TextStyle(
              fontSize: 13.5,
              color: paleta.textoSecundario,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 8),
          _GradeComodos(
            comodos: widget.comodos,
            estreito: widget.estreito,
            onAlternar: widget.onAlternar,
            onRemover: widget.onRemover,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controle,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _adicionar(),
                  decoration: const InputDecoration(
                    hintText: 'Adicionar cômodo ou categoria',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              BotaoUi(
                rotulo: 'Adicionar',
                onPressed: _enviando ? null : _adicionar,
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _GradeComodos extends StatelessWidget {
  const _GradeComodos({
    required this.comodos,
    required this.estreito,
    required this.onAlternar,
    required this.onRemover,
  });

  final List<Comodo> comodos;
  final bool estreito;
  final void Function(Comodo comodo) onAlternar;
  final void Function(Comodo comodo) onRemover;

  @override
  Widget build(BuildContext context) {
    if (comodos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Nenhum cômodo na lista. Adicione o primeiro abaixo.',
          style: TextStyle(
            fontSize: 13.5,
            color: EscopoUi.de(context).textoSecundario,
          ),
        ),
      );
    }

    final colunas = estreito ? 1 : 2;
    // Não há grade de altura fixa: cada cômodo ocupa uma linha inteira em telas
    // estreitas e meia em telas largas, com o par dividindo a linha.
    final linhas = <Widget>[];
    for (var i = 0; i < comodos.length; i += colunas) {
      linhas.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < colunas; c++)
              Expanded(
                child: i + c < comodos.length
                    ? _ItemComodo(
                        comodo: comodos[i + c],
                        onAlternar: onAlternar,
                        onRemover: onRemover,
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      );
    }
    return Column(children: linhas);
  }
}

class _ItemComodo extends StatelessWidget {
  const _ItemComodo({
    required this.comodo,
    required this.onAlternar,
    required this.onRemover,
  });

  final Comodo comodo;
  final void Function(Comodo comodo) onAlternar;
  final void Function(Comodo comodo) onRemover;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    return Semantics(
      checked: comodo.concluido,
      label: comodo.nome,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: paleta.borda)),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => onAlternar(comodo),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      _Quadro(concluido: comodo.concluido, paleta: paleta),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          comodo.nome,
                          style: TextStyle(
                            fontSize: 14.5,
                            color: comodo.concluido
                                ? paleta.textoSecundario
                                : paleta.texto,
                            decoration: comodo.concluido
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: paleta.textoSecundario,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: () => onRemover(comodo),
              icon: const Icon(Icons.close, size: 15),
              color: paleta.textoSecundario,
              tooltip: 'Remover ${comodo.nome}',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _Quadro extends StatelessWidget {
  const _Quadro({required this.concluido, required this.paleta});

  final bool concluido;
  final PaletaUi paleta;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: concluido ? paleta.destaque : paleta.superficie,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: concluido ? paleta.destaque : paleta.borda,
          width: 2,
        ),
      ),
      child: concluido
          ? Icon(Icons.check, size: 15, color: paleta.fundo)
          : null,
    );
  }
}
