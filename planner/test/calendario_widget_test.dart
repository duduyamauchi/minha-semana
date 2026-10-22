import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_core/planner_core.dart';
import 'package:planner_ui/planner_ui.dart';

import 'package:planner_sarah/app.dart';
import 'package:planner_sarah/rotas.dart';

/// Calendário: semanas navegáveis, date picker e a prancha dos sete dias.
///
/// A data é fixa (quarta, 2026-10-21) para o teste não depender do dia em que
/// roda. O que se verifica aqui é o que a tela promete: cada semana tem seu
/// próprio progresso, e marcar hoje não marca a semana seguinte.
Future<Repositorio> _montar(WidgetTester tester, {Size tamanho = const Size(1200, 2600)}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final rep = Repositorio(FonteMemoria());
  rep.agora = () => DateTime(2026, 10, 21, 9);
  await rep.carregar();
  await tester.pumpWidget(Aplicativo(repositorio: rep));
  await tester.pumpAndSettle();
  return rep;
}

Future<void> _abrirCalendario(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Ver calendário'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cabeçalho mostra a semana da data e permite navegar', (tester) async {
    final rep = await _montar(tester);

    expect(find.text('19 a 25 de outubro'), findsOneWidget);
    expect(find.textContaining('Semana 43'), findsOneWidget);

    await tester.tap(find.byTooltip('Próxima semana'));
    await tester.pumpAndSettle();
    expect(find.text('26 de outubro a 1 de novembro'), findsOneWidget);
    expect(rep.selecionado, DateTime(2026, 10, 28));

    await tester.tap(find.byTooltip('Semana anterior'));
    await tester.pumpAndSettle();
    expect(rep.selecionado, DateTime(2026, 10, 21));

    // "Hoje" volta para a data de referência mesmo estando longe.
    await tester.tap(find.byTooltip('Próxima semana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hoje'));
    await tester.pumpAndSettle();
    expect(rep.selecionado, DateTime(2026, 10, 21));
    expect(find.textContaining('Quarta, 21/10 · hoje'), findsOneWidget);
  });

  testWidgets('date picker abre em português e troca a semana', (tester) async {
    final rep = await _montar(tester);

    await tester.tap(find.byTooltip('Escolher data'));
    await tester.pumpAndSettle();
    // O seletor abre em português: título e botões traduzidos.
    expect(find.text('Escolher dia'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('outubro de 2026'), findsOneWidget);

    // O modo de digitação é o lápis do cabeçalho do seletor.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '05/11/2026');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(rep.selecionado, DateTime(2026, 11, 5));
    expect(find.text('2 a 8 de novembro'), findsOneWidget);
    expect(find.textContaining('Quinta, 05/11'), findsOneWidget);
  });

  testWidgets('marcar numa semana não marca na outra', (tester) async {
    final rep = await _montar(tester);
    final atividade = rep.dias[rep.indiceHoje].atividades.first;

    await tester.tap(find.byKey(ValueKey('marcar-${atividade.id}')));
    await tester.pumpAndSettle();
    expect(rep.percentual, greaterThan(0));

    await tester.tap(find.byTooltip('Próxima semana'));
    await tester.pumpAndSettle();
    expect(rep.concluidaNaData(atividade), isFalse);
    expect(rep.percentual, 0);
    expect(find.text('0%'), findsOneWidget);

    await tester.tap(find.byTooltip('Semana anterior'));
    await tester.pumpAndSettle();
    expect(rep.concluidaNaData(atividade), isTrue);
  });

  testWidgets('tocar numa aba abre o dia daquela data', (tester) async {
    final rep = await _montar(tester);

    await tester.tap(find.text('Sáb').first);
    await tester.pumpAndSettle();

    expect(rep.selecionado, DateTime(2026, 10, 24));
    expect(find.textContaining('Sábado, 24/10'), findsOneWidget);
    expect(find.byKey(const ValueKey('marcar-sab-07:10')), findsOneWidget);
  });

  testWidgets('calendário mostra o mês e a prancha da semana', (tester) async {
    final rep = await _montar(tester);
    await _abrirCalendario(tester);

    expect(find.text('Calendário'), findsOneWidget);
    expect(find.text('outubro de 2026'), findsOneWidget);
    expect(find.text('Semana 43'), findsOneWidget);
    expect(find.text('19 a 25 de outubro'), findsOneWidget);

    // A prancha mostra os sete dias, com pelo menos uma atividade de cada.
    expect(find.text('Seg'), findsWidgets);
    expect(find.text('Dom'), findsWidgets);
    expect(find.text('Acordar'), findsWidgets);
    expect(find.text('Descanso'), findsWidgets);

    // Navegar mês e semana.
    await tester.tap(find.byTooltip('Próximo mês'));
    await tester.pumpAndSettle();
    expect(find.text('novembro de 2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Próxima semana'));
    await tester.pumpAndSettle();
    expect(rep.agenda.inicio, DateTime(2026, 10, 26));
    expect(find.text('Semana 44'), findsOneWidget);
  });

  testWidgets('calendário reflete progresso por dia e abre o dia tocado', (tester) async {
    final rep = await _montar(tester);

    // Marca duas atividades da quarta (data de referência).
    final quarta = rep.dias[rep.indiceHoje].atividades;
    for (final a in quarta.take(2)) {
      await tester.tap(find.byKey(ValueKey('marcar-${a.id}')));
      await tester.pumpAndSettle();
    }
    expect(rep.agenda.feitasEm(DateTime(2026, 10, 21)), 2);

    await _abrirCalendario(tester);
    // O resumo da semana soma o que foi marcado.
    expect(find.textContaining('2 de ${rep.agenda.totalDaSemana} feitas'), findsOneWidget);

    // Toca no dia 24 (sábado). O rótulo aparece na grade do mês e na prancha:
    // a grade é a primeira (o cartão do mês vem antes no layout largo).
    await tester.tap(find.bySemanticsLabel(RegExp(r'^sábado, 24 de outubro, nada feito')).first);
    await tester.pumpAndSettle();

    expect(rep.selecionado, DateTime(2026, 10, 24));
    expect(find.textContaining('Sábado, 24/10'), findsOneWidget);
  });

  testWidgets('calendário em tela estreita empilha mês e prancha', (tester) async {
    await _montar(tester, tamanho: const Size(400, 3000));
    await _abrirCalendario(tester);

    expect(find.text('outubro de 2026'), findsOneWidget);
    // A prancha vira lista: cada dia é uma linha com o nome curto.
    expect(find.text('Seg'), findsWidgets);
    expect(find.text('Calendário'), findsOneWidget);
  });

  testWidgets('data na URL abre a semana certa e volta ao trocar', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final rep = Repositorio(FonteMemoria());
    rep.agora = () => DateTime(2026, 10, 21, 9);
    await rep.carregar();
    final rotas = Rotas(
      repositorio: rep,
      exigeLogin: false,
      sessao: ValueNotifier(null),
      aoEntrar: (_, _) async => throw StateError('sem servidor'),
      aoSair: () async {},
    ).criar();

    await tester.pumpWidget(
      EscopoUi(paleta: PaletaUi.clara, child: MaterialApp.router(routerConfig: rotas)),
    );
    await tester.pumpAndSettle();

    rotas.go('/semana/2026-11-05');
    await tester.pumpAndSettle();
    expect(rep.selecionado, DateTime(2026, 11, 5));
    expect(find.text('2 a 8 de novembro'), findsOneWidget);

    // Navegar atualiza a rota: recarregar a página não perde a semana.
    await tester.tap(find.byTooltip('Próxima semana'));
    await tester.pumpAndSettle();
    expect(rotas.routerDelegate.currentConfiguration.uri.path, '/semana/2026-11-12');
  });

  testWidgets('link antigo /dia/dom abre o domingo da semana de hoje', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final rep = Repositorio(FonteMemoria());
    rep.agora = () => DateTime(2026, 10, 21, 9);
    await rep.carregar();
    final rotas = Rotas(
      repositorio: rep,
      exigeLogin: false,
      sessao: ValueNotifier(null),
      aoEntrar: (_, _) async => throw StateError('sem servidor'),
      aoSair: () async {},
    ).criar();

    await tester.pumpWidget(
      EscopoUi(paleta: PaletaUi.clara, child: MaterialApp.router(routerConfig: rotas)),
    );
    await tester.pumpAndSettle();

    rotas.go('/dia/dom');
    await tester.pumpAndSettle();

    expect(rep.selecionado, DateTime(2026, 10, 25));
    expect(find.textContaining('Domingo, 25/10'), findsOneWidget);
  });
}
