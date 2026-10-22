import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_core/planner_core.dart';

import 'package:planner_sarah/app.dart';

/// Fluxo de edição do plano pela interface: criar, editar horário/duração,
/// excluir e desfazer. O que estes testes protegem é o que o usuário faz na
/// tela — o domínio e o repositório já têm testes próprios.
Future<Repositorio> _montar(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final rep = Repositorio(FonteMemoria());
  await rep.carregar();
  await tester.pumpWidget(Aplicativo(repositorio: rep));
  await tester.pumpAndSettle();
  return rep;
}

/// Digita em um campo do editor pelo seu rótulo.
Future<void> _digitar(WidgetTester tester, String chave, String texto) async {
  final campo = find.byKey(Key(chave));
  await tester.ensureVisible(campo);
  await tester.enterText(campo, texto);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'abrir o editor pela linha mostra horário e duração preenchidos',
    (tester) async {
      final rep = await _montar(tester);
      final dia = rep.dias[rep.indiceHoje];
      final alvo = dia.ordenadas.firstWhere((a) => a.duracaoMinutos != null);

      await tester.tap(find.text(alvo.titulo).first);
      await tester.pumpAndSettle();

      expect(find.text('Editar atividade'), findsOneWidget);
      expect(find.widgetWithText(TextField, alvo.horario), findsOneWidget);
      final horas = tester
          .widget<TextField>(find.byKey(const Key('campo-horas')))
          .controller!
          .text;
      final minutos = tester
          .widget<TextField>(find.byKey(const Key('campo-minutos')))
          .controller!
          .text;
      expect(
        (int.tryParse(horas) ?? 0) * 60 + (int.tryParse(minutos) ?? 0),
        alvo.duracaoMinutos,
      );
    },
  );

  testWidgets('editar horário e duração atualiza a timeline e persiste', (
    tester,
  ) async {
    final rep = await _montar(tester);
    final dia = rep.dias[rep.indiceHoje];
    final alvo = dia.ordenadas.first;

    await tester.tap(find.text(alvo.titulo).first);
    await tester.pumpAndSettle();

    await _digitar(tester, 'campo-horario', '05:30');
    await _digitar(tester, 'campo-horas', '1');
    await _digitar(tester, 'campo-minutos', '15');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    final relida = rep.semana.dia(alvo.dia)!.atividade(alvo.id)!;
    expect(relida.horario, '05:30');
    expect(relida.duracaoMinutos, 75);
    // A linha mostra a faixa com duração e término.
    expect(find.text('05:30'), findsOneWidget);
    expect(find.text('1h15 · até 06:45'), findsOneWidget);
  });

  testWidgets('horário inválido é recusado com mensagem, sem fechar o editor', (
    tester,
  ) async {
    final rep = await _montar(tester);
    final alvo = rep.dias[rep.indiceHoje].ordenadas.first;

    await tester.tap(find.text(alvo.titulo).first);
    await tester.pumpAndSettle();
    await _digitar(tester, 'campo-horario', '99:99');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Horário inválido'), findsOneWidget);
    expect(find.text('Editar atividade'), findsOneWidget);
    expect(rep.semana.dia(alvo.dia)!.atividade(alvo.id)!.horario, alvo.horario);
  });

  testWidgets('título vazio é recusado', (tester) async {
    final rep = await _montar(tester);
    final alvo = rep.dias[rep.indiceHoje].ordenadas.first;

    await tester.tap(find.text(alvo.titulo).first);
    await tester.pumpAndSettle();
    await _digitar(tester, 'campo-titulo', '   ');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Dê um nome à atividade.'), findsOneWidget);
  });

  testWidgets('criar atividade pelo botão do dia', (tester) async {
    final rep = await _montar(tester);
    final antes = rep.dias[rep.indiceHoje].atividades.length;

    await tester.tap(find.text('Adicionar atividade'));
    await tester.pumpAndSettle();
    // O cabeçalho é único; o campo de título nasce vazio.
    expect(find.text('Nova atividade'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('campo-titulo')))
          .controller!
          .text,
      isEmpty,
    );

    await _digitar(tester, 'campo-titulo', 'Caminhada');
    await _digitar(tester, 'campo-horario', '07:45');
    await _digitar(tester, 'campo-horas', '0');
    await _digitar(tester, 'campo-minutos', '30');
    await tester.tap(find.text('Adicionar ao dia'));
    await tester.pumpAndSettle();

    final dia = rep.dias[rep.indiceHoje];
    expect(dia.atividades.length, antes + 1);
    final criada = dia.atividades.firstWhere((a) => a.titulo == 'Caminhada');
    expect(criada.horario, '07:45');
    expect(criada.duracaoMinutos, 30);
    expect(find.text('Caminhada'), findsOneWidget);
    // Entrou na posição cronológica.
    final horarios = dia.ordenadas.map((a) => a.horario).toList();
    expect(horarios, [...horarios]..sort());
  });

  testWidgets('excluir pelo menu da linha remove e o desfazer recoloca', (
    tester,
  ) async {
    final rep = await _montar(tester);
    final dia = rep.dias[rep.indiceHoje];
    final alvo = dia.ordenadas.first;

    await tester.tap(find.byTooltip('Opções de ${alvo.titulo}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir').last);
    await tester.pumpAndSettle();

    expect(rep.semana.dia(alvo.dia)!.atividade(alvo.id), isNull);
    expect(find.text(alvo.titulo), findsNothing);

    await tester.tap(find.text('Desfazer'));
    await tester.pumpAndSettle();

    final voltou = rep.semana.dia(alvo.dia)!.atividade(alvo.id);
    expect(voltou, isNotNull);
    expect(voltou!.horario, alvo.horario);
    expect(voltou.duracaoMinutos, alvo.duracaoMinutos);
  });

  testWidgets('excluir pelo editor pede confirmação em dois toques', (
    tester,
  ) async {
    final rep = await _montar(tester);
    final dia = rep.dias[rep.indiceHoje];
    final alvo = dia.ordenadas.first;

    await tester.tap(find.text(alvo.titulo).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();

    // Primeiro toque só arma a confirmação: nada foi apagado ainda.
    expect(rep.semana.dia(alvo.dia)!.atividade(alvo.id), isNotNull);
    expect(find.text('Confirmar exclusão'), findsOneWidget);

    await tester.tap(find.text('Confirmar exclusão'));
    await tester.pumpAndSettle();

    expect(rep.semana.dia(alvo.dia)!.atividade(alvo.id), isNull);
  });

  testWidgets('editar categoria e detalhe aparece na linha', (tester) async {
    final rep = await _montar(tester);
    final dia = rep.dias[rep.indiceHoje];
    final alvo = dia.ordenadas.first;

    await tester.tap(find.text(alvo.titulo).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('categoria-estudo')));
    await tester.pumpAndSettle();
    await _digitar(tester, 'campo-detalhe', 'com música');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    final relida = rep.semana.dia(alvo.dia)!.atividade(alvo.id)!;
    expect(relida.categoria, Categoria.estudo);
    expect(relida.detalhe, 'com música');
    expect(find.text('com música'), findsOneWidget);
  });
}
