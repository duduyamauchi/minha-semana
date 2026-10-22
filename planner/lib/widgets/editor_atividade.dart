import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:planner_core/planner_core.dart';
import 'package:planner_ui/planner_ui.dart';

import '../core/cores.dart';

/// O que o editor devolveu.
///
/// `null` significa "cancelou": a tela não distingue cancelamento de fechar por
/// fora, e não deve gravar nada nos dois casos.
sealed class ResultadoEdicao {
  const ResultadoEdicao();
}

/// Salvar a atividade (criada ou editada).
class SalvarAtividade extends ResultadoEdicao {
  const SalvarAtividade(this.atividade);

  final Atividade atividade;
}

/// Excluir a atividade.
class ExcluirAtividade extends ResultadoEdicao {
  const ExcluirAtividade(this.atividade);

  final Atividade atividade;
}

/// Abre o editor de uma atividade do dia.
///
/// Serve para criar e para editar: a diferença é só o estado inicial e o rótulo
/// do botão. Horário e duração são campos próprios — antes a duração morava no
/// texto do detalhe e não havia como alterá-la.
Future<ResultadoEdicao?> abrirEditorAtividade(
  BuildContext context, {
  required Atividade atividade,
  required bool nova,
}) => showModalBottomSheet<ResultadoEdicao>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _EditorAtividade(atividade: atividade, nova: nova),
);

class _EditorAtividade extends StatefulWidget {
  const _EditorAtividade({required this.atividade, required this.nova});

  final Atividade atividade;
  final bool nova;

  @override
  State<_EditorAtividade> createState() => _EditorAtividadeState();
}

class _EditorAtividadeState extends State<_EditorAtividade> {
  late final TextEditingController _titulo;
  late final TextEditingController _detalhe;
  late final TextEditingController _horario;
  late final TextEditingController _horas;
  late final TextEditingController _minutos;

  late Categoria _categoria;
  late bool _fixo;
  late bool _prioridade;
  String? _erro;
  bool _confirmandoExclusao = false;

  @override
  void initState() {
    super.initState();
    final a = widget.atividade;
    _titulo = TextEditingController(text: a.titulo);
    _detalhe = TextEditingController(text: a.detalhe);
    _horario = TextEditingController(text: a.horario);
    final duracao = a.duracaoMinutos ?? 0;
    _horas = TextEditingController(
      text: duracao >= 60 ? '${duracao ~/ 60}' : '',
    );
    _minutos = TextEditingController(
      text: duracao % 60 == 0 ? '' : '${duracao % 60}',
    );
    _categoria = a.categoria;
    _fixo = a.fixo;
    _prioridade = a.prioridade;

    // O resumo ("começa às X e termina às Y") é calculado no build a partir do
    // texto dos campos; sem isto ele só se atualizaria quando outra interação
    // reconstruísse a tela.
    for (final c in [_horario, _horas, _minutos]) {
      c.addListener(_aoEditarHorario);
    }
  }

  void _aoEditarHorario() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_horario, _horas, _minutos]) {
      c.removeListener(_aoEditarHorario);
    }
    for (final c in [_titulo, _detalhe, _horario, _horas, _minutos]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Soma horas e minutos digitados; `null` quando os dois estão vazios.
  int? get _duracao {
    final h = int.tryParse(_horas.text.trim()) ?? 0;
    final m = int.tryParse(_minutos.text.trim()) ?? 0;
    if (h == 0 && m == 0) return null;
    return h * 60 + m;
  }

  Future<void> _escolherHorario() async {
    final atual = Horario.minutos(_horario.text);
    final escolhido = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (atual ?? 8 * 60) ~/ 60,
        minute: (atual ?? 8 * 60) % 60,
      ),
      helpText: 'Início da atividade',
      cancelText: 'Cancelar',
      confirmText: 'OK',
    );
    if (escolhido == null) return;
    setState(() {
      _horario.text = Horario.formatar(escolhido.hour * 60 + escolhido.minute);
      _erro = null;
    });
  }

  void _salvar() {
    final titulo = _titulo.text.trim();
    if (titulo.isEmpty) {
      setState(() => _erro = 'Dê um nome à atividade.');
      return;
    }
    final inicio = Horario.normalizar(_horario.text);
    if (inicio == null) {
      setState(
        () => _erro = 'Horário inválido. Use HH:mm, entre 00:00 e 23:59.',
      );
      return;
    }
    final h = int.tryParse(_horas.text.trim()) ?? 0;
    final m = int.tryParse(_minutos.text.trim()) ?? 0;
    if (h > 23 || m > 59) {
      setState(() => _erro = 'Duração inválida: use até 23 h e 59 min.');
      return;
    }
    final duracao = _duracao;
    if (duracao != null && duracao > 24 * 60) {
      setState(() => _erro = 'A duração não pode passar de 24 h.');
      return;
    }

    Navigator.of(context).pop(
      SalvarAtividade(
        widget.atividade.copiarCom(
          horario: inicio,
          titulo: titulo,
          detalhe: _detalhe.text.trim(),
          duracaoMinutos: duracao,
          limparDuracao: duracao == null,
          categoria: _categoria,
          fixo: _fixo,
          prioridade: _prioridade,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    final largura = MediaQuery.sizeOf(context).width;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      // `Material` (e não só `Container`) porque os switches são `ListTile`:
      // eles pintam o fundo e o splash no Material mais próximo, e um
      // `DecoratedBox` no meio esconderia os dois.
      child: Material(
        color: paleta.superficie,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: paleta.borda,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.nova ? 'Nova atividade' : 'Editar atividade',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _rotuloDia(widget.atividade.dia),
                      style: TextStyle(
                        fontSize: 13,
                        color: paleta.textoSecundario,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      key: const Key('campo-titulo'),
                      controller: _titulo,
                      autofocus: widget.nova,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Título'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('campo-detalhe'),
                      controller: _detalhe,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Detalhe (opcional)',
                        hintText: 'O que fazer, como fazer…',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            key: const Key('campo-horario'),
                            controller: _horario,
                            keyboardType: TextInputType.datetime,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9:]'),
                              ),
                              LengthLimitingTextInputFormatter(5),
                            ],
                            decoration: InputDecoration(
                              labelText: 'Horário',
                              hintText: 'HH:mm',
                              suffixIcon: IconButton(
                                tooltip: 'Escolher horário',
                                onPressed: _escolherHorario,
                                icon: const Icon(Icons.schedule, size: 19),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            key: const Key('campo-horas'),
                            controller: _horas,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Duração (h)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            key: const Key('campo-minutos'),
                            controller: _minutos,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(labelText: 'min'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _resumoHorario(),
                      style: TextStyle(
                        fontSize: 12,
                        color: paleta.textoSecundario,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Categoria',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: paleta.texto,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in Categoria.values)
                          _ChipCategoria(
                            key: Key('categoria-${c.chave}'),
                            categoria: c,
                            selecionada: c == _categoria,
                            onTap: () => setState(() => _categoria = c),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: _fixo,
                      onChanged: (v) => setState(() => _fixo = v),
                      title: const Text(
                        'Compromisso fixo',
                        style: TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        'Hora marcada, como academia ou pilates',
                        style: TextStyle(
                          fontSize: 12,
                          color: paleta.textoSecundario,
                        ),
                      ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: _prioridade,
                      onChanged: (v) => setState(() => _prioridade = v),
                      title: const Text(
                        'Bloco prioritário',
                        style: TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        'Destacado como a reorganização da casa',
                        style: TextStyle(
                          fontSize: 12,
                          color: paleta.textoSecundario,
                        ),
                      ),
                    ),
                    if (_erro != null) ...[
                      const SizedBox(height: 8),
                      FaixaErroUi(mensagem: _erro!),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (!widget.nova) ...[
                          _BotaoExcluir(
                            confirmando: _confirmandoExclusao,
                            onPressed: () {
                              if (_confirmandoExclusao) {
                                Navigator.of(
                                  context,
                                ).pop(ExcluirAtividade(widget.atividade));
                              } else {
                                setState(() => _confirmandoExclusao = true);
                              }
                            },
                            onCancelar: () =>
                                setState(() => _confirmandoExclusao = false),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: BotaoUi(
                            rotulo: widget.nova ? 'Adicionar ao dia' : 'Salvar',
                            onPressed: _salvar,
                          ),
                        ),
                      ],
                    ),
                    if (largura < 380) const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _resumoHorario() {
    final inicio = Horario.normalizar(_horario.text);
    if (inicio == null) return 'Informe o início no formato HH:mm.';
    final duracao = _duracao;
    if (duracao == null) return 'Sem duração: item pontual às $inicio.';
    if (duracao > 24 * 60) return 'A duração não pode passar de 24 h.';
    return 'Começa às $inicio e termina às ${Horario.somar(inicio, duracao)}.';
  }

  static String _rotuloDia(String chave) {
    const nomes = {
      'seg': 'Segunda-feira',
      'ter': 'Terça-feira',
      'qua': 'Quarta-feira',
      'qui': 'Quinta-feira',
      'sex': 'Sexta-feira',
      'sab': 'Sábado',
      'dom': 'Domingo',
    };
    return nomes[chave] ?? chave;
  }
}

class _ChipCategoria extends StatelessWidget {
  const _ChipCategoria({
    super.key,
    required this.categoria,
    required this.selecionada,
    required this.onTap,
  });

  final Categoria categoria;
  final bool selecionada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cor = categoria.cor(context.cores);
    final paleta = EscopoUi.de(context);
    return Semantics(
      selected: selecionada,
      button: true,
      label: categoria.rotulo,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selecionada
                ? cor.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selecionada ? cor : paleta.borda,
              width: selecionada ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(
                categoria.rotulo,
                style: TextStyle(
                  fontSize: 13.5,
                  color: paleta.texto,
                  fontWeight: selecionada ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Excluir em dois toques: o primeiro pede confirmação, o segundo apaga.
class _BotaoExcluir extends StatelessWidget {
  const _BotaoExcluir({
    required this.confirmando,
    required this.onPressed,
    required this.onCancelar,
  });

  final bool confirmando;
  final VoidCallback onPressed;
  final VoidCallback onCancelar;

  @override
  Widget build(BuildContext context) {
    final cor = context.cores.movimento;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: cor,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(confirmando ? 'Confirmar exclusão' : 'Excluir'),
        ),
        if (confirmando)
          IconButton(
            tooltip: 'Cancelar exclusão',
            onPressed: onCancelar,
            icon: const Icon(Icons.close, size: 18),
            color: EscopoUi.de(context).textoSecundario,
          ),
      ],
    );
  }
}
