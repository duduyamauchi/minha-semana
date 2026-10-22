import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_core/planner_core.dart';
import 'package:planner_ui/planner_ui.dart';

import 'package:planner_sarah/app.dart';
import 'package:planner_sarah/rotas.dart';

/// Monta o app completo em volta de uma fonte em memória.
Future<Repositorio> _montar(WidgetTester tester, {SessaoApi? cliente}) async {
  // Tela alta o bastante para a caixa de cômodos caber sem rolagem: os testes
  // medem conteúdo, não gesto de rolagem.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final rep = Repositorio(FonteMemoria());
  await rep.carregar();
  await tester.pumpWidget(Aplicativo(repositorio: rep, clienteSessao: cliente));
  await tester.pumpAndSettle();
  return rep;
}

void main() {
  testWidgets('abre no dia de hoje com o progresso da semana', (tester) async {
    await _montar(tester);

    expect(find.text('Minha Semana'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    final hoje = Semana.indiceDeHoje();
    expect(find.textContaining('· hoje'), findsOneWidget);
    expect(hoje, inInclusiveRange(0, 6));
  });

  testWidgets('marcar uma atividade atualiza o checkbox e o percentual', (tester) async {
    final rep = await _montar(tester);

    // Primeira atividade do dia visível: "Acordar".
    expect(find.text('Acordar'), findsOneWidget);
    await tester.tap(find.text('Acordar'));
    await tester.pumpAndSettle();

    final marcada = rep.dias[rep.indiceHoje].atividades.first.id;
    expect(rep.semana.marcadas, contains(marcada));
    // O percentual sobe acima de zero depois da primeira marcação.
    expect(rep.percentual, greaterThan(0));
    expect(find.text('${rep.percentual}%'), findsOneWidget);
  });

  testWidgets('trocar de aba mostra a timeline do outro dia', (tester) async {
    await _montar(tester);

    await tester.tap(find.text('Sáb').first);
    await tester.pumpAndSettle();

    expect(find.text('Limpeza completa'), findsOneWidget);
    expect(find.textContaining('Limpeza completa e reorganização'), findsOneWidget);
  });

  testWidgets('"Começar nova semana" pede confirmação e desmarca tudo', (tester) async {
    final rep = await _montar(tester);
    await tester.tap(find.text('Acordar'));
    await tester.pumpAndSettle();
    expect(rep.semana.marcadas, isNotEmpty);

    await tester.tap(find.text('Começar nova semana'));
    await tester.pumpAndSettle();
    expect(find.text('Cancelar'), findsOneWidget);

    await tester.tap(find.text('Desmarcar'));
    await tester.pumpAndSettle();

    expect(rep.semana.marcadas, isEmpty);
    expect(find.text('Cancelar'), findsNothing);
  });

  testWidgets('cancelar a nova semana não desmarca nada', (tester) async {
    final rep = await _montar(tester);
    await tester.tap(find.text('Acordar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Começar nova semana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(rep.semana.marcadas, isNotEmpty);
  });

  testWidgets('adicionar e remover cômodo', (tester) async {
    final rep = await _montar(tester);
    final antes = rep.comodos.length;

    await tester.enterText(find.byType(TextField).first, 'Escritório');
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();

    expect(rep.comodos.length, antes + 1);
    expect(find.text('Escritório'), findsOneWidget);

    await tester.tap(find.byTooltip('Remover Escritório'));
    await tester.pumpAndSettle();
    expect(rep.comodos.length, antes);
    expect(find.text('Escritório'), findsNothing);
  });

  testWidgets('cômodo repetido é recusado com mensagem', (tester) async {
    final rep = await _montar(tester);
    final antes = rep.comodos.length;

    await tester.enterText(find.byType(TextField).first, 'Cozinha');
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();

    expect(rep.comodos.length, antes);
    expect(find.textContaining('já está na lista'), findsOneWidget);
  });

  testWidgets('ajustes mostram a fonte ativa e o progresso', (tester) async {
    final rep = await _montar(tester);
    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();

    expect(find.text('Origem dos dados'), findsOneWidget);
    expect(find.text(rep.fonte.descricao), findsOneWidget);
    expect(find.text('Neste aparelho'), findsOneWidget);
  });

  _rotasTeste();

  testWidgets('link /dia/dom abre o domingo', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final rep = Repositorio(FonteMemoria());
    await rep.carregar();
    final rotas = Rotas(
      repositorio: rep,
      exigeLogin: false,
      sessao: ValueNotifier(null),
      aoEntrar: (_, _) async => throw StateError('sem servidor'),
      aoSair: () async {},
    ).criar();

    await tester.pumpWidget(
      EscopoUi(
        paleta: PaletaUi.clara,
        child: MaterialApp.router(routerConfig: rotas),
      ),
    );
    await tester.pumpAndSettle();

    // Navega pela URL como um link compartilhado faria.
    rotas.go('/dia/dom');
    await tester.pumpAndSettle();

    expect(find.textContaining('Domingo'), findsWidgets);
    expect(find.text('Descanso'), findsOneWidget);
  });
}

void _rotasTeste() {
  group('rota pedida antes do login', () {
    testWidgets('link profundo sem sessão volta para o dia pedido depois de entrar', (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final rep = Repositorio(FonteMemoria());
      await rep.carregar();
      final sessao = ValueNotifier<Sessao?>(null);
      final rotas = Rotas(
        repositorio: rep,
        exigeLogin: true,
        sessao: sessao,
        aoEntrar: (_, _) async => const Sessao(usuario: 'sarah', papel: 'proprietario'),
        aoSair: () async {},
      ).criar();

      await tester.pumpWidget(
        EscopoUi(
          paleta: PaletaUi.clara,
          child: MaterialApp.router(routerConfig: rotas),
        ),
      );
      await tester.pumpAndSettle();

      // Sem sessão: pede login, mas guarda o destino.
      rotas.go('/dia/dom');
      await tester.pumpAndSettle();
      expect(find.text('Entrar'), findsOneWidget);

      // Depois de entrar, o app retoma o dia pedido em vez de abrir /semana.
      sessao.value = const Sessao(usuario: 'sarah', papel: 'proprietario');
      await tester.pumpAndSettle();

      expect(rotas.routerDelegate.currentConfiguration.uri.path, '/dia/dom');
      expect(find.text('Descanso'), findsOneWidget);
    });
  });
}
