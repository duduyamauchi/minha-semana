import 'package:flutter_test/flutter_test.dart';
import 'package:planner_core/planner_core.dart';

/// Edição do plano: criar, editar (horário, duração, título, categoria) e
/// excluir. O que estes testes protegem é o que uma edição mal feita quebraria:
/// marcação perdida, id duplicado e ordem da timeline.
void main() {
  group('horário e duração', () {
    test('lê e formata HH:mm', () {
      expect(Horario.minutos('06:00'), 360);
      expect(Horario.minutos('6:5'), 365);
      expect(Horario.formatar(365), '06:05');
      expect(Horario.formatar(24 * 60), '00:00');
      expect(Horario.normalizar('7:05'), '07:05');
      // Forma sem dois-pontos: é o que o campo do editor permite digitar.
      expect(Horario.normalizar('745'), '07:45');
      expect(Horario.normalizar('0745'), '07:45');
      expect(Horario.normalizar('7450'), isNull);
    });

    test('recusa horário inválido', () {
      for (final texto in ['', 'x', '25:00', '10:60', '10', '10:00:00', '99999', null]) {
        expect(Horario.minutos(texto), isNull, reason: '$texto');
      }
    });

    test('soma duração e dá a volta no dia', () {
      expect(Horario.somar('06:00', 45), '06:45');
      expect(Horario.somar('23:30', 60), '00:30');
      expect(Horario.somar('06:00', null), '06:00');
    });

    test('atividade mostra faixa horária legível', () {
      final comDuracao = Atividade(
        id: 'seg-09:00',
        dia: 'seg',
        horario: '09:00',
        titulo: 'Reorganização',
        duracaoMinutos: 210,
        categoria: Categoria.casa,
      );
      expect(comDuracao.duracaoTexto, '3h30');
      expect(comDuracao.termino, '12:30');
      expect(comDuracao.faixaHoraria, '09:00 · 3h30');

      final pontual = Atividade(
        id: 'seg-06:00',
        dia: 'seg',
        horario: '06:00',
        titulo: 'Acordar',
        categoria: Categoria.bemEstar,
      );
      expect(pontual.duracaoTexto, '');
      expect(pontual.termino, isNull);
      expect(pontual.faixaHoraria, '06:00');
    });
  });

  group('edição no modelo', () {
    late Semana semana;

    setUp(() {
      semana = semanaInicial();
    });

    test('salvarAtividade insere nova e mantém o dia', () {
      final nova = Atividade(
        id: semana.idLivre('seg', '10:00'),
        dia: 'seg',
        horario: '10:00',
        titulo: 'Alongamento',
        duracaoMinutos: 20,
        categoria: Categoria.movimento,
      );
      final depois = semana.salvarAtividade(nova);

      expect(depois.dia('seg')!.atividade(nova.id)?.titulo, 'Alongamento');
      expect(depois.totalAtividades, semana.totalAtividades + 1);
      // Outros dias não são tocados.
      expect(depois.dia('ter'), same(semana.dia('ter')));
    });

    test('editar horário mantém o id e a marcação', () {
      final original = semana.dia('seg')!.atividades.first;
      final editada = original.copiarCom(horario: '07:00', duracaoMinutos: 15);
      final depois = semana
          .copiarCom(marcadas: {original.id})
          .salvarAtividade(editada);

      final relida = depois.dia('seg')!.atividade(original.id)!;
      expect(relida.horario, '07:00');
      expect(relida.duracaoMinutos, 15);
      // A marcação sobrevive à edição: o id é a identidade, não o horário.
      expect(depois.concluida(relida), isTrue);
      expect(depois.totalFeitas, 1);
    });

    test('editar categoria e detalhe persiste', () {
      final original = semana.dia('ter')!.atividades.first;
      final depois = semana.salvarAtividade(
        original.copiarCom(categoria: Categoria.estudo, detalhe: 'complemento'),
      );
      final relida = depois.dia('ter')!.atividade(original.id)!;
      expect(relida.categoria, Categoria.estudo);
      expect(relida.detalhe, 'complemento');
    });

    test('limpar duração devolve o item a pontual', () {
      final comDuracao = semana.dia('seg')!.atividades.firstWhere((a) => a.duracaoMinutos != null);
      final depois = semana.salvarAtividade(comDuracao.copiarCom(limparDuracao: true));
      expect(depois.dia('seg')!.atividade(comDuracao.id)!.duracaoMinutos, isNull);
    });

    test('removerAtividade tira a linha e a marcação', () {
      final alvo = semana.dia('qua')!.atividades.first;
      final depois = semana
          .copiarCom(marcadas: {alvo.id, 'seg-06:00'})
          .removerAtividade('qua', alvo.id);

      expect(depois.dia('qua')!.atividade(alvo.id), isNull);
      expect(depois.marcadas, isNot(contains(alvo.id)));
      expect(depois.marcadas, contains('seg-06:00'));
      expect(depois.totalFeitas, 1);
    });

    test('remover id inexistente não muda nada', () {
      expect(semana.removerAtividade('qua', 'nada-a-ver').totalAtividades, semana.totalAtividades);
    });

    test('dia vazio continua válido e não divide por zero', () {
      var vazia = semana;
      for (final a in semana.dia('dom')!.atividades) {
        vazia = vazia.removerAtividade('dom', a.id);
      }
      expect(vazia.dia('dom')!.atividades, isEmpty);
      expect(vazia.percentual, 0);
    });

    test('idLivre não reutiliza id existente', () {
      final primeiro = semana.idLivre('seg', '06:00');
      expect(primeiro, isNot('seg-06:00'));
      expect(semana.dia('seg')!.atividade(primeiro), isNull);
      // Segunda chamada devolve o mesmo (ainda livre).
      expect(semana.idLivre('seg', '06:00'), primeiro);
    });

    test('atividades ficam ordenadas por horário', () {
      final tarde = Atividade(
        id: 'seg-05:00',
        dia: 'seg',
        horario: '05:00',
        titulo: 'Cedo',
        categoria: Categoria.bemEstar,
      );
      final depois = semana.salvarAtividade(tarde);
      final horarios = depois.dia('seg')!.ordenadas.map((a) => a.horario).toList();
      expect(horarios.first, '05:00');
      final ordenados = [...horarios]..sort();
      expect(horarios, ordenados);
    });
  });

  group('serialização do plano', () {
    test('ida e volta preserva horário, duração e flags', () {
      final semana = semanaInicial();
      final lida = EstadoSemana.fromJson(semana.toJson());
      final relida = Semana.doJson(semana.toJson(), base: construirPlanoInicial());

      expect(lida.dias, isNotNull);
      expect(lida.dias!.length, 7);
      final original = semana.dia('ter')!;
      expect(relida.dia('ter')!.atividades.length, original.atividades.length);
      final editar = original.atividades.first;
      final depois = relida.dia('ter')!.atividade(editar.id)!;
      expect(depois.horario, editar.horario);
      expect(depois.duracaoMinutos, editar.duracaoMinutos);
      expect(depois.categoria, editar.categoria);
    });

    test('estado v2 (sem dias) é migrado para o plano inicial', () {
      final v2 = EstadoSemana.fromJson({
        'versao': 2,
        'marcadas': ['seg-06:00'],
        'comodos': [
          {'id': 'sala', 'nome': 'Sala'},
        ],
      });
      expect(v2.dias, isNull);
      final semana = Semana.doJson(v2.toJson(), base: construirPlanoInicial());
      expect(semana.dias, hasLength(7));
      expect(semana.marcadas, {'seg-06:00'});
    });

    test('atividade inválida no JSON não derruba o plano', () {
      final estado = EstadoSemana.fromJson({
        'dias': [
          {
            'chave': 'seg',
            'nome': 'Segunda',
            'atividades': [
              {'id': 'seg-09:00', 'horario': '9:00', 'titulo': 'Válida', 'duracaoMinutos': 30},
              {'id': 'seg-09:00', 'horario': '10:00', 'titulo': 'Duplicada'},
              {'id': 'seg-11:00', 'horario': '99:99', 'titulo': '  '},
              {'id': 'seg-12:00', 'horario': '12:00', 'titulo': 'Duração absurda', 'duracaoMinutos': 9999},
            ],
          },
        ],
      });
      final atividades = estado.dias!.single.atividades;
      // Duplicada descartada, horário inválido normalizado, título vazio ganha
      // rótulo e duração fora de faixa é ignorada.
      expect(atividades, hasLength(3));
      expect(atividades[0].horario, '09:00');
      expect(atividades[1].titulo, 'Sem título');
      expect(atividades[2].duracaoMinutos, isNull);
    });

    test('plano sem dias válidos cai no template', () {
      final estado = EstadoSemana.fromJson({'dias': [{'chave': ''}, 'lixo']});
      expect(estado.dias, isNull);
    });
  });
}
