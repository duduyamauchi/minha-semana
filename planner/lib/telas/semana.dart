import 'package:flutter/material.dart';
import 'package:planner_core/planner_core.dart';
import 'package:planner_ui/planner_ui.dart';

import '../core/cores.dart';

import '../widgets/abas_dia.dart';
import '../widgets/editor_atividade.dart';
import '../widgets/linha_atividade.dart';
import '../widgets/secao_comodos.dart';

/// A tela do planejador: uma coluna calma, sete abas, a timeline do dia e a
/// reorganização da casa.
///
/// A composição segue o HTML original — cabeçalho com progresso da semana,
/// legenda das categorias, abas, timeline e a caixa de cômodos —, mas o estado
/// chega pelo [Repositorio]: a tela nunca fala com a fonte de dados.
class TelaSemana extends StatefulWidget {
  const TelaSemana({
    super.key,
    required this.repositorio,
    this.abaInicial,
    this.aoAbrirAjustes,
    this.usuario,
    this.aoSair,
  });

  final Repositorio repositorio;

  /// Rota `/dia/:chave` fixa o dia aberto; sem ela, abre no dia de hoje.
  final String? abaInicial;

  final VoidCallback? aoAbrirAjustes;

  /// Nome de quem entrou, quando há conta.
  final String? usuario;

  /// Encerra a sessão; `null` quando o app funciona só no aparelho.
  final Future<void> Function()? aoSair;

  @override
  State<TelaSemana> createState() => _TelaSemanaState();
}

class _TelaSemanaState extends State<TelaSemana> {
  late int _dia;
  bool _confirmandoReset = false;

  @override
  void initState() {
    super.initState();
    _dia = _diaInicial();
    widget.repositorio.addListener(_aoMudar);
    widget.repositorio.analytics.visitar('/semana');
  }

  @override
  void didUpdateWidget(TelaSemana antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.repositorio != widget.repositorio) {
      antigo.repositorio.removeListener(_aoMudar);
      widget.repositorio.addListener(_aoMudar);
    }
  }

  @override
  void dispose() {
    widget.repositorio.removeListener(_aoMudar);
    super.dispose();
  }

  void _aoMudar() {
    if (mounted) setState(() {});
  }

  int _diaInicial() {
    final chave = widget.abaInicial;
    if (chave != null) {
      final i = widget.repositorio.dias.indexWhere((d) => d.chave == chave);
      if (i >= 0) return i;
    }
    return widget.repositorio.indiceHoje;
  }

  @override
  Widget build(BuildContext context) {
    final rep = widget.repositorio;
    final paleta = EscopoUi.de(context);
    final largura = MediaQuery.sizeOf(context).width;
    final estreito = largura < 440;

    if (rep.carregando || rep.estado == EstadoCarga.inicial) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rep.estado == EstadoCarga.erro && rep.dias.isEmpty) {
      return _ErroCarga(
        mensagem: rep.erro ?? 'Falha ao carregar.',
        onTentar: rep.carregar,
      );
    }

    final indiceHoje = rep.indiceHoje;
    // O dia selecionado pode ter saído do template (mudança de versão); nesse
    // caso volta para hoje em vez de abrir uma lista vazia.
    final selecionado = _dia < rep.dias.length ? _dia : indiceHoje;
    final dia = rep.dias[selecionado];
    final feitas = [for (final d in rep.dias) rep.semana.feitasNoDia(d)];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: rep.carregar,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            largura > 760 ? 24 : 16,
            24,
            largura > 760 ? 24 : 16,
            56,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Cabecalho(
                    percentual: rep.percentual,
                    aoAbrirAjustes: widget.aoAbrirAjustes,
                    usuario: widget.usuario,
                    aoSair: widget.aoSair,
                  ),
                  const SizedBox(height: 16),
                  _Legenda(estreito: estreito),
                  const SizedBox(height: 20),
                  if (rep.erro != null) ...[
                    FaixaErroUi(mensagem: rep.erro!),
                    const SizedBox(height: 14),
                  ],
                  AbasDia(
                    dias: rep.dias,
                    selecionado: selecionado,
                    indiceHoje: indiceHoje,
                    feitas: feitas,
                    estreito: estreito,
                    onSelecionar: (i) {
                      setState(() => _dia = i);
                      rep.analytics.registrar(
                        'dia_visualizado',
                        propriedades: {
                          'dia': rep.dias[i].chave,
                          'hoje': i == indiceHoje,
                        },
                        entidade: 'dia',
                        entidadeId: rep.dias[i].chave,
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  _DiaSelecionado(
                    dia: dia,
                    hoje: selecionado == indiceHoje,
                    semana: rep.semana,
                    editavel: rep.permiteEscrita,
                    onAlternar: rep.alternar,
                    onEditar: (atividade) =>
                        _abrirEditor(atividade, nova: false),
                    onExcluir: (atividade) => _excluir(atividade),
                    onNova: () =>
                        _abrirEditor(rep.novaAtividade(dia.chave), nova: true),
                  ),
                  const SizedBox(height: 28),
                  SecaoComodos(
                    comodos: rep.comodos,
                    estreito: estreito,
                    onAlternar: (comodo) => rep.alternarComodo(comodo),
                    onAdicionar: rep.adicionarComodo,
                    onRemover: (comodo) => rep.removerComodo(comodo),
                  ),
                  const SizedBox(height: 20),
                  _Rodape(
                    confirmando: _confirmandoReset,
                    onPedir: () => setState(() => _confirmandoReset = true),
                    onCancelar: () => setState(() => _confirmandoReset = false),
                    onConfirmar: () async {
                      await rep.limparMarcacoes();
                      if (mounted) setState(() => _confirmandoReset = false);
                      if (!context.mounted) return;
                      _avisar(
                        context,
                        'Semana desmarcada. Os cômodos continuam como estavam.',
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Acordar às 6h, dormir às 22h. ${rep.fonte.descricao}.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: paleta.textoSecundario,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Abre o editor e aplica o resultado.
  ///
  /// O editor devolve a intenção (salvar/excluir) em vez de gravar sozinho: a
  /// escrita passa pelo repositório, que atualiza a tela, persiste e instrumenta.
  Future<void> _abrirEditor(Atividade atividade, {required bool nova}) async {
    final rep = widget.repositorio;
    final resultado = await abrirEditorAtividade(
      context,
      atividade: atividade,
      nova: nova,
    );
    if (!mounted || resultado == null) return;

    switch (resultado) {
      case SalvarAtividade(:final atividade):
        final ok = await rep.salvarAtividade(atividade);
        if (!mounted) return;
        if (ok) {
          _avisar(
            context,
            nova ? 'Atividade adicionada.' : 'Atividade atualizada.',
          );
        } else if (rep.erro != null) {
          _avisar(context, rep.erro!);
        }
      case ExcluirAtividade(:final atividade):
        final ok = await rep.removerAtividade(atividade);
        if (!mounted) return;
        if (ok) {
          _avisar(context, '“${atividade.titulo}” foi excluída.');
        } else if (rep.erro != null) {
          _avisar(context, rep.erro!);
        }
    }
  }

  /// Excluir pelo menu da linha, com desfazer.
  ///
  /// Diferente do editor (que já pede confirmação), aqui a ação é imediata e o
  /// desfazer recoloca a atividade com o mesmo id — e, se ela estava concluída,
  /// a marcação volta junto.
  Future<void> _excluir(Atividade atividade) async {
    final rep = widget.repositorio;
    final estavaFeita = rep.semana.concluida(atividade);
    final ok = await rep.removerAtividade(atividade);
    if (!mounted) return;
    if (!ok) {
      if (rep.erro != null) _avisar(context, rep.erro!);
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('“${atividade.titulo}” foi excluída.'),
          action: SnackBarAction(
            label: 'Desfazer',
            onPressed: () async {
              await rep.salvarAtividade(atividade);
              if (estavaFeita) await rep.marcar(atividade, concluida: true);
            },
          ),
        ),
      );
  }

  void _avisar(BuildContext context, String mensagem) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensagem)));
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({
    required this.percentual,
    this.aoAbrirAjustes,
    this.usuario,
    this.aoSair,
  });

  final int percentual;
  final VoidCallback? aoAbrirAjustes;
  final String? usuario;
  final Future<void> Function()? aoSair;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Minha Semana',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Marque o que fizer; o progresso fica salvo${aoSair != null ? ' na sua conta' : ' neste aparelho'}.',
                    style: TextStyle(
                      fontSize: 14,
                      color: paleta.textoSecundario,
                    ),
                  ),
                ],
              ),
            ),
            if (aoAbrirAjustes != null)
              IconButton(
                onPressed: aoAbrirAjustes,
                icon: const Icon(Icons.tune),
                color: paleta.textoSecundario,
                tooltip: 'Ajustes',
              ),
            if (usuario != null && aoSair != null)
              PopupMenuButton<String>(
                tooltip: 'Conta',
                color: paleta.superficie,
                onSelected: (acao) {
                  if (acao == 'sair') aoSair!();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    enabled: false,
                    child: Text('Entrou como $usuario'),
                  ),
                  const PopupMenuItem(value: 'sair', child: Text('Sair')),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: paleta.destaqueSuave,
                    child: Text(
                      usuario!.characters.first.toUpperCase(),
                      style: TextStyle(
                        color: paleta.destaque,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              'Semana',
              style: TextStyle(fontSize: 14, color: paleta.textoSecundario),
            ),
            const SizedBox(width: 12),
            Expanded(child: BarraProgressoUi(valor: percentual / 100)),
            const SizedBox(width: 12),
            SizedBox(
              width: 44,
              child: Text(
                '$percentual%',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: paleta.texto,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Legenda extends StatelessWidget {
  const _Legenda({required this.estreito});

  final bool estreito;

  @override
  Widget build(BuildContext context) {
    final cores = context.cores;
    final itens = [
      LegendaUi(cor: cores.estudo, rotulo: 'Estudo'),
      LegendaUi(cor: cores.movimento, rotulo: 'Movimento'),
      LegendaUi(cor: cores.casa, rotulo: 'Casa'),
      LegendaUi(cor: cores.bemEstar, rotulo: 'Bem-estar'),
    ];
    if (estreito) {
      return Wrap(spacing: 14, runSpacing: 6, children: itens);
    }
    return Row(
      children: [
        for (var i = 0; i < itens.length; i++) ...[
          if (i > 0) const SizedBox(width: 14),
          itens[i],
        ],
      ],
    );
  }
}

class _DiaSelecionado extends StatelessWidget {
  const _DiaSelecionado({
    required this.dia,
    required this.hoje,
    required this.semana,
    required this.onAlternar,
    required this.onEditar,
    required this.onExcluir,
    required this.onNova,
    required this.editavel,
  });

  final Dia dia;
  final bool hoje;
  final Semana semana;
  final void Function(Atividade atividade) onAlternar;
  final void Function(Atividade atividade) onEditar;
  final void Function(Atividade atividade) onExcluir;
  final VoidCallback onNova;
  final bool editavel;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    final estreito = MediaQuery.sizeOf(context).width < 440;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              hoje ? '${dia.nomeExibido} · hoje' : dia.nomeExibido,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              dia.nota,
              style: TextStyle(fontSize: 13.5, color: paleta.textoSecundario),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: paleta.borda)),
          ),
          child: Column(
            children: [
              if (dia.atividades.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Center(
                    child: Text(
                      'Nenhuma atividade neste dia ainda.',
                      style: TextStyle(
                        fontSize: 14,
                        color: paleta.textoSecundario,
                      ),
                    ),
                  ),
                ),
              // A ordem é sempre por horário: editar o horário reposiciona a
              // linha em vez de deixá-la fora de sequência.
              for (final atividade in dia.ordenadas)
                LinhaAtividade(
                  key: ValueKey(atividade.id),
                  atividade: atividade,
                  concluida: semana.concluida(atividade),
                  estreito: estreito,
                  editavel: editavel,
                  onAlternar: () => onAlternar(atividade),
                  onEditar: () => onEditar(atividade),
                  onExcluir: () => onExcluir(atividade),
                ),
            ],
          ),
        ),
        if (editavel) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: BotaoUi(
              rotulo: 'Adicionar atividade',
              icone: Icons.add,
              secundario: true,
              onPressed: onNova,
            ),
          ),
        ],
      ],
    );
  }
}

class _Rodape extends StatelessWidget {
  const _Rodape({
    required this.confirmando,
    required this.onPedir,
    required this.onCancelar,
    required this.onConfirmar,
  });

  final bool confirmando;
  final VoidCallback onPedir;
  final VoidCallback onCancelar;
  final VoidCallback onConfirmar;

  @override
  Widget build(BuildContext context) {
    if (!confirmando) {
      return Align(
        alignment: Alignment.centerLeft,
        child: BotaoUi(
          rotulo: 'Começar nova semana',
          secundario: true,
          onPressed: onPedir,
        ),
      );
    }
    final paleta = EscopoUi.de(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Desmarcar todas as atividades da semana? A lista de cômodos continua como está.',
          style: TextStyle(fontSize: 13.5, color: paleta.textoSecundario),
        ),
        BotaoUi(rotulo: 'Desmarcar', onPressed: onConfirmar),
        BotaoUi(rotulo: 'Cancelar', secundario: true, onPressed: onCancelar),
      ],
    );
  }
}

class _ErroCarga extends StatelessWidget {
  const _ErroCarga({required this.mensagem, required this.onTentar});

  final String mensagem;
  final Future<void> Function() onTentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: VazioUi(
          icone: Icons.cloud_off,
          titulo: 'Não foi possível carregar a semana',
          descricao: mensagem,
          acao: BotaoUi(rotulo: 'Tentar de novo', onPressed: onTentar),
        ),
      ),
    );
  }
}
