import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_core/planner_core.dart';

import 'package:planner_sarah/app.dart';

/// Conflito de horário na interface: aviso visível, gravação liberada.
///
/// O caso do pedido: "Acordar" 06:00 e "Manutenção" 06:10. Com 10 min no
/// primeiro, tudo encaixa; com mais, aparece o aviso — e salvar continua
/// funcionando.
Future<Repositorio> _montar(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final rep = Repositorio(FonteMemoria());
  rep.agora = () => DateTime(2026, 10, 21, 9);
  await rep.carregar();
  await tester.pumpWidget(Aplicativo(repositorio: rep));
  await tester.pumpAndSettle();
  return rep;
}

/// Abre o editor de uma atividade pela linha (tocando no título).
Future<void> _abrirEditor(WidgetTester tester, String titulo) async {
  await tester.tap(find.text(titulo).first);
  await tester.pumpAndSettle();
}

Future<void> _digitar(WidgetTester tester, String chave, String texto) async {
  final campo = find.byKey(Key(chave));
  await tester.ensureVisible(campo);
  await tester.enterText(campo, texto);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sem sobreposição, o editor não mostra aviso', (tester) async {
    await _montar(tester);
    await _abrirEditor(tester, 'Acordar');

    // 06:00 sem duração: item pontual, nada a sobrepor.
    expect(find.byKey(const Key('aviso-conflito-editor')), findsNothing);
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
  });

  testWidgets('duração que invade a próxima atividade mostra aviso no editor', (tester) async {
    await _montar(tester);
    await _abrirEditor(tester, 'Acordar');

    // 06:00 + 25 min = 06:25, invade "Manutenção da limpeza" (06:10).
    await _digitar(tester, 'campo-minutos', '25');

    expect(find.byKey(const Key('aviso-conflito-editor')), findsOneWidget);
    expect(find.text('Este horário sobrepõe outra atividade.'), findsOneWidget);
    expect(find.textContaining('Manutenção da limpeza'), findsWidgets);
    // A outra atividade é pontual (06:10, sem duração): o choque é o instante
    // ocupado, não uma fração de minutos.
    expect(find.textContaining('ocupa este horário'), findsOneWidget);
    // Deixa claro que não bloqueia.
    expect(find.text('Você pode salvar assim mesmo.'), findsOneWidget);
  });

  testWidgets('duração que termina exatamente no início da próxima não avisa', (tester) async {
    await _montar(tester);
    await _abrirEditor(tester, 'Acordar');

    // 06:00 + 10 min = 06:10: encosta, não invade.
    await _digitar(tester, 'campo-minutos', '10');
    expect(find.byKey(const Key('aviso-conflito-editor')), findsNothing);
  });

  testWidgets('o aviso acompanha a digitação e some ao corrigir', (tester) async {
    await _montar(tester);
    await _abrirEditor(tester, 'Acordar');

    await _digitar(tester, 'campo-minutos', '30');
    expect(find.byKey(const Key('aviso-conflito-editor')), findsOneWidget);

    await _digitar(tester, 'campo-minutos', '5');
    expect(find.byKey(const Key('aviso-conflito-editor')), findsNothing);
  });

  testWidgets('salvar com conflito funciona e o aviso aparece na lista', (tester) async {
    final rep = await _montar(tester);
    await _abrirEditor(tester, 'Acordar');
    await _digitar(tester, 'campo-minutos', '25');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    // Gravou, apesar do aviso.
    final acordar = rep.dias[rep.indiceHoje].atividade('qua-06:00')!;
    expect(acordar.duracaoMinutos, 25);

    // Resumo do dia + etiqueta na linha.
    expect(find.textContaining('sobreposição de horário'), findsOneWidget);
    expect(find.textContaining('Conflito com Manutenção da limpeza'), findsOneWidget);
  });

  testWidgets('limpar a duração remove o conflito da lista', (tester) async {
    final rep = await _montar(tester);
    await _abrirEditor(tester, 'Acordar');
    await _digitar(tester, 'campo-minutos', '25');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Conflito com Manutenção da limpeza'), findsOneWidget);

    await _abrirEditor(tester, 'Acordar');
    await _digitar(tester, 'campo-minutos', '');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(rep.dias[rep.indiceHoje].atividade('qua-06:00')!.duracaoMinutos, isNull);
    expect(find.textContaining('Conflito com Manutenção da limpeza'), findsNothing);
    expect(find.textContaining('sobreposição de horário'), findsNothing);
  });

  testWidgets('conflito não impede marcar como feito', (tester) async {
    final rep = await _montar(tester);
    await _abrirEditor(tester, 'Acordar');
    await _digitar(tester, 'campo-minutos', '25');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    final caixa = find.byKey(const ValueKey('marcar-qua-06:00'));
    await tester.tap(caixa);
    await tester.pumpAndSettle();

    expect(rep.concluidaNaData(rep.dias[rep.indiceHoje].atividades.first), isTrue);
    // O aviso continua na lista: conflito é do horário, não do progresso.
    expect(find.textContaining('Conflito com Manutenção da limpeza'), findsOneWidget);
  });

  testWidgets('o resumo do dia conta as sobreposições', (tester) async {
    final rep = await _montar(tester);

    // Faz a reorganização de 09:00 invadir o almoço das 12:30.
    final reorganizacao = rep.dias[rep.indiceHoje].atividade('qua-09:00')!;
    await rep.salvarAtividade(reorganizacao.copiarCom(duracaoMinutos: 240));
    await tester.pumpAndSettle();

    final conflitos = rep.conflitosDoDia('qua');
    expect(conflitos['qua-09:00'], isNotEmpty);
    expect(
      find.textContaining('1 sobreposição de horário'),
      findsOneWidget,
    );
  });
}
