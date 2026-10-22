import 'package:flutter/material.dart';
import 'package:planner_core/planner_core.dart';
import 'package:planner_ui/planner_ui.dart';

import '../core/cores.dart';

/// Visão de calendário: o mês inteiro e a semana aberta lado a lado.
///
/// Duas leituras que a tela da semana não dá:
///
/// * **o mês** — onde estão os dias com progresso, para navegar por semanas
///   distantes sem clicar em "anterior" várias vezes;
/// * **a semana inteira** — as sete colunas de uma vez, com as atividades de
///   cada dia. É a prancha que mostra a rotina como um todo, e não um dia por
///   vez.
///
/// A tela só lê do [Repositorio]; tocar num dia muda a data aberta e volta para
/// a timeline daquele dia.
class TelaCalendario extends StatefulWidget {
  const TelaCalendario({
    super.key,
    required this.repositorio,
    this.aoAbrirDia,
    this.aoVoltar,
    this.aoAbrirAjustes,
  });

  final Repositorio repositorio;

  /// Abre a timeline de uma data.
  final void Function(DateTime data)? aoAbrirDia;

  final VoidCallback? aoVoltar;
  final VoidCallback? aoAbrirAjustes;

  @override
  State<TelaCalendario> createState() => _TelaCalendarioState();
}

class _TelaCalendarioState extends State<TelaCalendario> {
  late DateTime _mes;

  Repositorio get _rep => widget.repositorio;

  @override
  void initState() {
    super.initState();
    _mes = Datas.inicioDoMes(_rep.selecionado);
    _rep.addListener(_aoMudar);
    _rep.analytics.visitar('/calendario');
  }

  @override
  void didUpdateWidget(TelaCalendario antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.repositorio != widget.repositorio) {
      antigo.repositorio.removeListener(_aoMudar);
      widget.repositorio.addListener(_aoMudar);
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

  void _mudarMes(int meses) {
    setState(() {
      _mes = meses >= 0
          ? _avancarMeses(_mes, meses)
          : _avancarMeses(_mes, meses);
    });
    _rep.analytics.registrar(
      'calendario_mes',
      propriedades: {'mes': Datas.iso(_mes)},
    );
  }

  DateTime _avancarMeses(DateTime mes, int quantidade) {
    var alvo = mes;
    for (var i = 0; i < quantidade.abs(); i++) {
      alvo = quantidade > 0 ? Datas.mesSeguinte(alvo) : Datas.mesAnterior(alvo);
    }
    return alvo;
  }

  void _abrir(DateTime data) {
    _rep.irPara(data);
    final abrir = widget.aoAbrirDia;
    if (abrir != null) {
      abrir(data);
    } else {
      setState(() => _mes = Datas.inicioDoMes(data));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rep = _rep;
    final paleta = EscopoUi.de(context);
    final hoje = Datas.hoje(rep.agora());
    final agenda = rep.agenda;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: widget.aoVoltar,
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Voltar para o dia',
                      color: paleta.textoSecundario,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Calendário',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 26),
                      ),
                    ),
                    if (widget.aoAbrirAjustes != null)
                      IconButton(
                        onPressed: widget.aoAbrirAjustes,
                        icon: const Icon(Icons.tune),
                        tooltip: 'Ajustes',
                        color: paleta.textoSecundario,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Marque o que fizer em cada dia; o plano é o mesmo toda semana.',
                  style: TextStyle(fontSize: 13.5, color: paleta.textoSecundario),
                ),
                const SizedBox(height: 18),
                if (rep.erro != null) ...[
                  FaixaErroUi(mensagem: rep.erro!),
                  const SizedBox(height: 14),
                ],
                // Lado a lado só quando a prancha ainda cabe em 7 colunas
                // (700 px). Abaixo disso, empilhar é melhor que comprimir: o mês
                // em cima e a semana ocupando a largura toda.
                LayoutBuilder(
                  builder: (context, restricoes) {
                    final mes = _CartaoMes(
                      mes: _mes,
                      rep: rep,
                      hoje: hoje,
                      aoAnterior: () => _mudarMes(-1),
                      aoProximo: () => _mudarMes(1),
                      aoHoje: () => _abrir(hoje),
                      aoAbrir: _abrir,
                    );
                    final prancha = _PranchaSemana(
                      rep: rep,
                      agenda: agenda,
                      hoje: hoje,
                      aoAbrir: _abrir,
                      aoMoverSemana: (semanas) {
                        rep.moverSemana(semanas);
                        setState(() => _mes = Datas.inicioDoMes(rep.selecionado));
                      },
                      aoHoje: () => _abrir(hoje),
                    );

                    if (restricoes.maxWidth < 1100) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          mes,
                          const SizedBox(height: 16),
                          prancha,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 340, child: mes),
                        const SizedBox(width: 20),
                        Expanded(child: prancha),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'Dias com tudo feito aparecem marcados. Tocar num dia abre a timeline dele.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: paleta.textoSecundario),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Grade do mês, com progresso por dia.
class _CartaoMes extends StatelessWidget {
  const _CartaoMes({
    required this.mes,
    required this.rep,
    required this.hoje,
    required this.aoAnterior,
    required this.aoProximo,
    required this.aoHoje,
    required this.aoAbrir,
  });

  final DateTime mes;
  final Repositorio rep;
  final DateTime hoje;
  final VoidCallback aoAnterior;
  final VoidCallback aoProximo;
  final VoidCallback aoHoje;
  final void Function(DateTime data) aoAbrir;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    final inicio = Datas.primeiraSegundaDoMes(mes);
    // Seis linhas cobrem qualquer mês; as células sobrando ficam vazias.
    final totalCelulas = 42;
    final celulas = [
      for (var i = 0; i < totalCelulas; i++) Datas.somarDias(inicio, i),
    ];

    return CaixaUi(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: aoAnterior,
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Mês anterior',
                color: paleta.textoSecundario,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Text(
                  Datas.mesExtenso(mes),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                onPressed: aoProximo,
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Próximo mês',
                color: paleta.textoSecundario,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              for (final nome in Datas.nomesCurtos)
                Expanded(
                  child: Center(
                    child: Text(
                      nome,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: paleta.textoSecundario,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var linha = 0; linha < 6; linha++)
            Row(
              children: [
                for (var coluna = 0; coluna < 7; coluna++)
                  Expanded(
                    child: _CelulaDia(
                      data: celulas[linha * 7 + coluna],
                      mes: mes,
                      rep: rep,
                      hoje: hoje,
                      aoAbrir: aoAbrir,
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: aoHoje,
              style: TextButton.styleFrom(
                foregroundColor: paleta.destaque,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Ir para hoje'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CelulaDia extends StatelessWidget {
  const _CelulaDia({
    required this.data,
    required this.mes,
    required this.rep,
    required this.hoje,
    required this.aoAbrir,
  });

  final DateTime data;
  final DateTime mes;
  final Repositorio rep;
  final DateTime hoje;
  final void Function(DateTime data) aoAbrir;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    final doMes = data.month == mes.month && data.year == mes.year;
    final agenda = rep.agenda;
    final total = agenda.totalEm(data);
    final feitas = agenda.feitasEm(data);
    final completo = total > 0 && feitas == total;
    final algum = feitas > 0 && !completo;
    final selecionado = Datas.mesmoDia(data, agenda.selecionado);
    final ehHoje = Datas.mesmoDia(data, hoje);

    final corTexto = !doMes
        ? paleta.textoSecundario.withValues(alpha: 0.45)
        : selecionado
        ? paleta.fundo
        : paleta.texto;

    return Semantics(
      button: true,
      selected: selecionado,
      label:
          '${Datas.diaPorExtenso(data)}, '
          '${feitas == 0 ? 'nada feito' : '$feitas de $total feitas'}',
      child: InkWell(
        onTap: () => aoAbrir(data),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 46,
          margin: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: selecionado ? paleta.destaque : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selecionado
                  ? paleta.destaque
                  : ehHoje
                  ? paleta.destaque
                  : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${data.day}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: ehHoje || selecionado ? FontWeight.w700 : FontWeight.w500,
                  color: corTexto,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              if (total > 0)
                _Pontos(
                  feitas: feitas,
                  total: total,
                  completo: completo,
                  algum: algum,
                  sobreSelecionado: selecionado,
                )
              else
                const SizedBox(height: 5),
            ],
          ),
        ),
      ),
    );
  }
}

/// Indicador de progresso da célula: bolinha cheia quando tudo foi feito,
/// fração quando parte.
class _Pontos extends StatelessWidget {
  const _Pontos({
    required this.feitas,
    required this.total,
    required this.completo,
    required this.algum,
    required this.sobreSelecionado,
  });

  final int feitas;
  final int total;
  final bool completo;
  final bool algum;
  final bool sobreSelecionado;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    final corBase = sobreSelecionado ? paleta.fundo : paleta.destaque;
    final corFraca = corBase.withValues(alpha: 0.28);

    if (!algum && !completo) {
      return Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(color: corFraca, shape: BoxShape.circle),
      );
    }
    if (completo) {
      return Icon(
        Icons.check_circle,
        size: 10,
        color: sobreSelecionado ? paleta.fundo : paleta.destaque,
      );
    }
    // Fração: barrinha com a proporção feita.
    return SizedBox(
      width: 22,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: Stack(
          children: [
            Container(height: 3, color: corFraca),
            FractionallySizedBox(
              widthFactor: feitas / total,
              child: Container(height: 3, color: corBase),
            ),
          ],
        ),
      ),
    );
  }
}

/// Prancha da semana: as sete colunas de uma vez.
class _PranchaSemana extends StatelessWidget {
  const _PranchaSemana({
    required this.rep,
    required this.agenda,
    required this.hoje,
    required this.aoAbrir,
    required this.aoMoverSemana,
    required this.aoHoje,
  });

  final Repositorio rep;
  final Agenda agenda;
  final DateTime hoje;
  final void Function(DateTime data) aoAbrir;
  final void Function(int semanas) aoMoverSemana;
  final VoidCallback aoHoje;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    return CaixaUi(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => aoMoverSemana(-1),
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Semana anterior',
                color: paleta.textoSecundario,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Semana ${agenda.numeroDaSemana}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16),
                    ),
                    Text(
                      Datas.intervaloSemana(agenda.inicio),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: paleta.textoSecundario),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => aoMoverSemana(1),
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Próxima semana',
                color: paleta.textoSecundario,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${agenda.feitasNaSemana} de ${agenda.totalDaSemana} feitas',
                  style: TextStyle(fontSize: 12, color: paleta.textoSecundario),
                ),
              ),
              TextButton(
                onPressed: aoHoje,
                style: TextButton.styleFrom(
                  foregroundColor: paleta.destaque,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Esta semana'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _BarraProgresso(valor: agenda.progressoDaSemana),
          const SizedBox(height: 12),
          // A prancha cabe em 7 colunas apenas com largura suficiente; abaixo
          // disso ela vira lista (uma linha por dia).
          LayoutBuilder(
            builder: (context, restricoes) {
              // No celular a prancha vira lista: sete colunas não cabem em 360 px.
              if (restricoes.maxWidth < 700) {
                return Column(
                  children: [
                    for (final data in agenda.datas)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _DiaDaPrancha(
                          data: data,
                          rep: rep,
                          agenda: agenda,
                          hoje: hoje,
                          aoAbrir: aoAbrir,
                          horizontal: true,
                        ),
                      ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final data in agenda.datas)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _DiaDaPrancha(
                          data: data,
                          rep: rep,
                          agenda: agenda,
                          hoje: hoje,
                          aoAbrir: aoAbrir,
                          horizontal: false,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BarraProgresso extends StatelessWidget {
  const _BarraProgresso({required this.valor});

  final double valor;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 6,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: paleta.borda),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: valor.clamp(0, 1),
                child: ColoredBox(color: paleta.destaque),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uma coluna da prancha (ou uma linha, no celular).
class _DiaDaPrancha extends StatelessWidget {
  const _DiaDaPrancha({
    required this.data,
    required this.rep,
    required this.agenda,
    required this.hoje,
    required this.aoAbrir,
    required this.horizontal,
  });

  final DateTime data;
  final Repositorio rep;
  final Agenda agenda;
  final DateTime hoje;
  final void Function(DateTime data) aoAbrir;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    final dia = agenda.diaDaData(data);
    final selecionado = Datas.mesmoDia(data, agenda.selecionado);
    final ehHoje = Datas.mesmoDia(data, hoje);
    final feitas = agenda.feitasEm(data);
    final total = agenda.totalEm(data);

    final titulo = Row(
      children: [
        Text(
          Datas.nomesCurtos[Datas.indiceNaSemana(data)],
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: ehHoje ? paleta.destaque : paleta.texto,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '${data.day}',
          style: TextStyle(
            fontSize: 12,
            color: paleta.textoSecundario,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        // `Flexible` em vez de `Spacer`: numa coluna estreita (a prancha tem
        // 7 delas) o contador precisa encolher, não empurrar o layout.
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '$feitas/$total',
            textAlign: TextAlign.right,
            overflow: TextOverflow.clip,
            softWrap: false,
            style: TextStyle(
              fontSize: 10.5,
              color: paleta.textoSecundario,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );

    final lista = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final a in dia.ordenadas)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    width: 3,
                    height: 11,
                    decoration: BoxDecoration(
                      color: a.categoria.cor(context.cores),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.titulo,
                        maxLines: horizontal ? 2 : 4,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: horizontal ? 12.5 : 11,
                          height: 1.25,
                          color: rep.semana.concluidaEm(data, a)
                              ? paleta.textoSecundario
                              : paleta.texto,
                          decoration: rep.semana.concluidaEm(data, a)
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: paleta.textoSecundario,
                        ),
                      ),
                      if (!horizontal)
                        Text(
                          a.horario,
                          style: TextStyle(
                            fontSize: 10,
                            color: paleta.textoSecundario,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return Semantics(
      button: true,
      label:
          '${Datas.diaPorExtenso(data)}, ${dia.nomeExibido}, '
          '$feitas de $total feitas',
      child: InkWell(
        onTap: () => aoAbrir(data),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selecionado ? paleta.destaqueSuave : paleta.fundo,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selecionado
                  ? paleta.destaque
                  : ehHoje
                  ? paleta.destaque.withValues(alpha: 0.5)
                  : paleta.borda,
            ),
          ),
          child: horizontal
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 94, child: titulo),
                    const SizedBox(width: 8),
                    Expanded(child: lista),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    titulo,
                    const SizedBox(height: 6),
                    if (dia.atividades.isEmpty)
                      Text(
                        '—',
                        style: TextStyle(fontSize: 11, color: paleta.textoSecundario),
                      )
                    else
                      lista,
                  ],
                ),
        ),
      ),
    );
  }
}
