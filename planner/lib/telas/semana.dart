import 'package:flutter/material.dart';
import 'package:planner_core/planner_core.dart';
import 'package:planner_ui/planner_ui.dart';

import '../core/cores.dart';

import '../widgets/abas_dia.dart';
import '../widgets/editor_atividade.dart';
import '../widgets/linha_atividade.dart';
import '../widgets/secao_comodos.dart';

/// A tela do planejador: a semana de uma data, com sete abas, a timeline do dia
/// aberto e a reorganização da casa.
///
/// A semântica é de calendário: o plano (template) é o mesmo em todas as
/// semanas, mas as marcações são da **data**. Navegar por semanas ou escolher
/// uma data no seletor muda o que está marcado, não a rotina.
class TelaSemana extends StatefulWidget {
  const TelaSemana({
    super.key,
    required this.repositorio,
    this.dataInicial,
    this.aoAbrirAjustes,
    this.aoAbrirCalendario,
    this.aoMudarData,
    this.usuario,
    this.aoSair,
  });

  final Repositorio repositorio;

  /// Data aberta (`/semana/2026-10-21` ou `/dia/qua`); sem ela, hoje.
  final DateTime? dataInicial;

  final VoidCallback? aoAbrirAjustes;

  /// Abre a visão de calendário do mês.
  final VoidCallback? aoAbrirCalendario;

  /// Chamado quando a data muda, para a rota acompanhar
  /// (`/semana/AAAA-MM-DD`). Sem isto, recarregar a página perderia a semana.
  final void Function(DateTime data)? aoMudarData;

  /// Nome de quem entrou, quando há conta.
  final String? usuario;

  /// Encerra a sessão; `null` quando o app funciona só no aparelho.
  final Future<void> Function()? aoSair;

  @override
  State<TelaSemana> createState() => _TelaSemanaState();
}

class _TelaSemanaState extends State<TelaSemana> {
  bool _confirmandoReset = false;

  Repositorio get _rep => widget.repositorio;

  @override
  void initState() {
    super.initState();
    // A rota manda: `/semana/2026-10-21` abre aquela semana; `/dia/qua` abre a
    // primeira quarta da semana de hoje. O `irPara` notifica ouvintes, então
    // não pode rodar durante o build do primeiro frame.
    final inicial = widget.dataInicial;
    if (inicial != null && !Datas.mesmoDia(inicial, _rep.selecionado)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rep.irPara(inicial);
      });
    }
    _rep.addListener(_aoMudar);
    _rep.analytics.visitar('/semana');
  }

  @override
  void didUpdateWidget(TelaSemana antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.repositorio != widget.repositorio) {
      antigo.repositorio.removeListener(_aoMudar);
      widget.repositorio.addListener(_aoMudar);
    }
    final nova = widget.dataInicial;
    if (nova != null && !Datas.mesmoDia(nova, _rep.selecionado)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rep.irPara(nova);
      });
    }
  }

  @override
  void dispose() {
    _rep.removeListener(_aoMudar);
    super.dispose();
  }

  void _aoMudar() {
    if (mounted) setState(() {});
  }

  /// Move a data aberta e avisa o roteador.
  void _irPara(DateTime data) {
    if (Datas.mesmoDia(data, _rep.selecionado)) return;
    _rep.irPara(data);
    widget.aoMudarData?.call(_rep.selecionado);
    _rep.analytics.registrar(
      'dia_visualizado',
      propriedades: {
        'data': Datas.iso(_rep.selecionado),
        'dia': Semana.chaveDaData(_rep.selecionado),
        'hoje': Datas.mesmoDia(_rep.selecionado, Datas.hoje(_rep.agora())),
      },
      entidade: 'dia',
      entidadeId: Datas.iso(_rep.selecionado),
    );
  }

  void _moverSemana(int semanas) {
    _rep.moverSemana(semanas);
    widget.aoMudarData?.call(_rep.selecionado);
    _rep.analytics.registrar(
      'semana_navegada',
      propriedades: {'semanas': semanas, 'data': Datas.iso(_rep.selecionado)},
    );
  }

  /// Abre o seletor de data do Material, em português.
  Future<void> _escolherData() async {
    final rep = _rep;
    final escolhida = await showDatePicker(
      context: context,
      initialDate: rep.selecionado,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Escolher dia',
      cancelText: 'Cancelar',
      confirmText: 'Abrir',
      fieldLabelText: 'Data',
      fieldHintText: 'dd/mm/aaaa',
      // A data pedida pode cair em qualquer semana: `_irPara` troca a semana.
    );
    if (escolhida == null || !mounted) return;
    _irPara(escolhida);
  }

  @override
  Widget build(BuildContext context) {
    final rep = _rep;
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

    final hoje = Datas.hoje(rep.agora());
    final agenda = rep.agenda;
    final diaAberto = agenda.diaSelecionado;

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
                  _NavegacaoSemana(
                    agenda: agenda,
                    hoje: hoje,
                    aoAnterior: () => _moverSemana(-1),
                    aoProximo: () => _moverSemana(1),
                    aoHoje: () => _irPara(hoje),
                    aoEscolherData: _escolherData,
                    aoAbrirCalendario: widget.aoAbrirCalendario,
                  ),
                  const SizedBox(height: 16),
                  _Legenda(estreito: estreito),
                  const SizedBox(height: 20),
                  if (rep.erro != null) ...[
                    FaixaErroUi(mensagem: rep.erro!),
                    const SizedBox(height: 14),
                  ],
                  AbasDia(
                    agenda: agenda,
                    hoje: hoje,
                    estreito: estreito,
                    onSelecionar: _irPara,
                  ),
                  const SizedBox(height: 20),
                  _DiaSelecionado(
                    dia: diaAberto,
                    data: agenda.selecionado,
                    hoje: Datas.mesmoDia(agenda.selecionado, hoje),
                    semana: rep.semana,
                    editavel: rep.permiteEscrita,
                    conflitos: rep.conflitosDoDia(diaAberto.chave),
                    onAlternar: rep.alternar,
                    onEditar: (atividade) =>
                        _abrirEditor(atividade, nova: false),
                    onExcluir: (atividade) => _excluir(atividade),
                    onNova: () =>
                        _abrirEditor(rep.novaAtividade(diaAberto.chave), nova: true),
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
                    semana: agenda,
                    onPedir: () => setState(() => _confirmandoReset = true),
                    onCancelar: () => setState(() => _confirmandoReset = false),
                    onConfirmar: () async {
                      final inicio = agenda.inicio;
                      await rep.limparMarcacoes();
                      if (mounted) setState(() => _confirmandoReset = false);
                      if (!context.mounted) return;
                      _avisar(
                        context,
                        'Semana de ${Datas.intervaloSemana(inicio)} desmarcada. '
                        'O plano e os cômodos continuam como estavam.',
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
    final rep = _rep;
    final resultado = await abrirEditorAtividade(
      context,
      atividade: atividade,
      nova: nova,
      // O editor recalcula os choques a cada digitação contra o dia inteiro.
      doDia: rep.dias
          .firstWhere(
            (d) => d.chave == atividade.dia,
            orElse: () => Dia(
              chave: atividade.dia,
              nome: Dia.nomeDe(atividade.dia),
              nota: '',
              atividades: const [],
            ),
          )
          .atividades,
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
  /// desfazer recoloca a atividade com o mesmo id — e, se ela estava concluída
  /// naquele dia, a marcação volta junto.
  Future<void> _excluir(Atividade atividade) async {
    final rep = _rep;
    final data = rep.dataDaAtividade(atividade);
    final estavaFeita = rep.semana.concluidaEm(data, atividade);
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
              if (estavaFeita) {
                await rep.marcar(atividade, concluida: true, data: data);
              }
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

/// Navegação da semana: setas, "hoje", seletor de data e atalho do calendário.
class _NavegacaoSemana extends StatelessWidget {
  const _NavegacaoSemana({
    required this.agenda,
    required this.hoje,
    required this.aoAnterior,
    required this.aoProximo,
    required this.aoHoje,
    required this.aoEscolherData,
    required this.aoAbrirCalendario,
  });

  final Agenda agenda;
  final DateTime hoje;
  final VoidCallback aoAnterior;
  final VoidCallback aoProximo;
  final VoidCallback aoHoje;
  final VoidCallback aoEscolherData;
  final VoidCallback? aoAbrirCalendario;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    final estreito = MediaQuery.sizeOf(context).width < 520;
    final naSemanaAtual = agenda.datas.any((d) => Datas.mesmoDia(d, hoje));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: paleta.superficie,
        borderRadius: BorderRadius.circular(paleta.raioMedio),
        border: Border.all(color: paleta.borda),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: aoAnterior,
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Semana anterior',
            color: paleta.textoSecundario,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: InkWell(
              onTap: aoEscolherData,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Datas.intervaloSemana(agenda.inicio),
                      style: TextStyle(
                        fontSize: estreito ? 14 : 15,
                        fontWeight: FontWeight.w600,
                        color: paleta.texto,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Semana ${agenda.numeroDaSemana} · ${agenda.percentualDaSemana}%'
                      '${naSemanaAtual ? ' · esta semana' : ''}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: paleta.textoSecundario,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: aoHoje,
            icon: const Icon(Icons.today, size: 16),
            label: const Text('Hoje'),
            style: TextButton.styleFrom(
              foregroundColor: naSemanaAtual ? paleta.textoSecundario : paleta.destaque,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
          IconButton(
            onPressed: aoEscolherData,
            icon: const Icon(Icons.calendar_month, size: 20),
            tooltip: 'Escolher data',
            color: paleta.textoSecundario,
            visualDensity: VisualDensity.compact,
          ),
          if (aoAbrirCalendario != null)
            IconButton(
              onPressed: aoAbrirCalendario,
              icon: const Icon(Icons.grid_view, size: 19),
              tooltip: 'Ver calendário',
              color: paleta.textoSecundario,
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            onPressed: aoProximo,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Próxima semana',
            color: paleta.textoSecundario,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
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
    required this.data,
    required this.hoje,
    required this.semana,
    required this.onAlternar,
    required this.onEditar,
    required this.onExcluir,
    required this.onNova,
    required this.editavel,
    this.conflitos = const {},
  });

  final Dia dia;

  /// Data aberta: é a chave das marcações exibidas.
  final DateTime data;
  final bool hoje;
  final Semana semana;
  final void Function(Atividade atividade) onAlternar;
  final void Function(Atividade atividade) onEditar;
  final void Function(Atividade atividade) onExcluir;
  final VoidCallback onNova;
  final bool editavel;

  /// Conflitos do dia, indexados por id de atividade.
  final Map<String, List<Conflito>> conflitos;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    final estreito = MediaQuery.sizeOf(context).width < 440;
    final doDia = dia.ordenadas
        .expand((a) => conflitos[a.id] ?? const <Conflito>[])
        .toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              hoje
                  ? '${dia.nomeExibido}, ${Datas.diaMes(data)} · hoje'
                  : '${dia.nomeExibido}, ${Datas.diaMes(data)}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              dia.nota,
              style: TextStyle(fontSize: 13.5, color: paleta.textoSecundario),
            ),
          ],
        ),
        if (doDia.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ResumoConflitos(conflitos: doDia.toList(), paleta: paleta),
        ],
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
                  concluida: semana.concluidaEm(data, atividade),
                  estreito: estreito,
                  editavel: editavel,
                  conflitos: conflitos[atividade.id] ?? const [],
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

/// Faixa acima da timeline quando o dia tem sobreposições.
///
/// Resume o que a lista já mostra linha a linha: quantos choques e entre quem.
/// Não é um erro — a rotina pode ter sobreposição de propósito —, então o tom é
/// informativo.
class _ResumoConflitos extends StatelessWidget {
  const _ResumoConflitos({required this.conflitos, required this.paleta});

  final List<Conflito> conflitos;
  final PaletaUi paleta;

  @override
  Widget build(BuildContext context) {
    final titulos = <String>{};
    for (final c in conflitos) {
      titulos
        ..add(c.primeira.titulo)
        ..add(c.segunda.titulo);
    }
    final texto = conflitos.length == 1
        ? '1 sobreposição de horário: ${conflitos.single.primeira.titulo} e '
              '${conflitos.single.segunda.titulo} se cruzam por '
              '${conflitos.single.minutosTexto}.'
        : '${conflitos.length} sobreposições de horário entre '
              '${titulos.length} atividades neste dia.';

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: paleta.avisoSuave.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(paleta.raioMedio),
        border: Border.all(color: paleta.aviso.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 15, color: paleta.aviso),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(fontSize: 12, height: 1.3, color: paleta.aviso),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rodape extends StatelessWidget {
  const _Rodape({
    required this.confirmando,
    required this.semana,
    required this.onPedir,
    required this.onCancelar,
    required this.onConfirmar,
  });

  final bool confirmando;

  /// Semana que será desmarcada: o texto deixa claro que só ela é afetada.
  final Agenda semana;

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
          'Desmarcar as atividades de ${Datas.intervaloSemana(semana.inicio)}? '
          'O plano, os cômodos e as outras semanas continuam como estão.',
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
