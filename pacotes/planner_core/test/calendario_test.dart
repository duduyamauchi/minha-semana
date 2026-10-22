import 'package:flutter_test/flutter_test.dart';
import 'package:planner_core/planner_core.dart';

/// Datas e agenda: a base de "semanas no calendário".
///
/// O que estes testes protegem é o que uma semana mal calculada quebraria:
/// marcação caindo no dia errado, semana atravessando o mês ou o ano, e um dia
/// aberto fora da semana exibida.
void main() {
  group('Datas', () {
    test('iso ida e volta, com validação de data real', () {
      expect(Datas.iso(DateTime(2026, 10, 5)), '2026-10-05');
      expect(Datas.deIso('2026-10-05'), DateTime(2026, 10, 5));
      expect(Datas.deIso('2026-1-5'), DateTime(2026, 1, 5));
    });

    test('recusa texto e datas impossíveis', () {
      for (final texto in ['', 'ontem', '2026-13-01', '2026-02-31', '2026/10/05', null]) {
        expect(Datas.deIso(texto), isNull, reason: '$texto');
      }
    });

    test('segunda da semana e as sete datas', () {
      // 2026-10-21 é uma quarta.
      final quarta = DateTime(2026, 10, 21);
      expect(Datas.segundaDe(quarta), DateTime(2026, 10, 19));
      expect(Datas.semanaDe(quarta).first, DateTime(2026, 10, 19));
      expect(Datas.semanaDe(quarta).last, DateTime(2026, 10, 25));
      expect(Datas.semanaDe(quarta), hasLength(7));
      // Domingo pertence à semana que começou na segunda anterior.
      expect(Datas.segundaDe(DateTime(2026, 10, 25)), DateTime(2026, 10, 19));
      // Segunda é a própria segunda.
      expect(Datas.segundaDe(DateTime(2026, 10, 19)), DateTime(2026, 10, 19));
    });

    test('semana que atravessa meses e anos', () {
      // 2026-10-01 é quinta: a semana começa em 28 de setembro.
      expect(Datas.segundaDe(DateTime(2026, 10, 1)), DateTime(2026, 9, 28));
      expect(Datas.intervaloSemana(DateTime(2026, 10, 1)), '28 de setembro a 4 de outubro');
      // Virada de ano: 2027-01-01 é sexta.
      expect(Datas.segundaDe(DateTime(2027, 1, 1)), DateTime(2026, 12, 28));
      expect(Datas.intervaloSemana(DateTime(2026, 12, 30)), '28 de dezembro a 3 de janeiro');
    });

    test('intervalo dentro do mesmo mês', () {
      expect(Datas.intervaloSemana(DateTime(2026, 10, 21)), '19 a 25 de outubro');
    });

    test('mês: vizinhos, extenso e dias', () {
      final out = DateTime(2026, 10, 21);
      expect(Datas.inicioDoMes(out), DateTime(2026, 10, 1));
      expect(Datas.mesSeguinte(out), DateTime(2026, 11, 1));
      expect(Datas.mesAnterior(out), DateTime(2026, 9, 1));
      expect(Datas.mesExtenso(out), 'outubro de 2026');
      expect(Datas.diasNoMes(out), 31);
      expect(Datas.diasNoMes(DateTime(2028, 2, 10)), 29);
      expect(Datas.primeiraSegundaDoMes(out), DateTime(2026, 9, 28));
    });

    test('formatações curtas', () {
      final d = DateTime(2026, 10, 5);
      expect(Datas.diaMes(d), '05/10');
      expect(Datas.dataCurta(d), '05/10/2026');
      expect(Datas.diaPorExtenso(d), 'segunda, 5 de outubro');
      expect(Datas.nomesCurtos[0], 'Seg');
    });

    test('mesmoDia ignora a hora', () {
      expect(Datas.mesmoDia(DateTime(2026, 10, 21, 0, 1), DateTime(2026, 10, 21, 23, 59)), isTrue);
      expect(Datas.mesmoDia(DateTime(2026, 10, 21), DateTime(2026, 10, 22)), isFalse);
    });

    test('indiceNaSemana segue segunda = 0', () {
      expect(Datas.indiceNaSemana(DateTime(2026, 10, 19)), 0);
      expect(Datas.indiceNaSemana(DateTime(2026, 10, 25)), 6);
    });
  });

  group('Agenda', () {
    late Semana semana;
    final quarta = DateTime(2026, 10, 21);

    setUp(() => semana = semanaInicial());

    test('semana da data, seleção e dia do template', () {
      final agenda = Agenda.de(semana, quarta);
      expect(agenda.inicio, DateTime(2026, 10, 19));
      expect(agenda.selecionado, quarta);
      expect(agenda.chaveDoSelecionado(), 'qua');
      expect(agenda.diaSelecionado.nome, 'Quarta');
      expect(agenda.datas.map(Semana.chaveDaData), [
        'seg',
        'ter',
        'qua',
        'qui',
        'sex',
        'sab',
        'dom',
      ]);
    });

    test('progresso por dia e da semana', () {
      var s = semana.definirConcluida(quarta, 'qua-06:00', concluida: true);
      s = s.definirConcluida(DateTime(2026, 10, 19), 'seg-06:40', concluida: true);
      final agenda = Agenda.de(s, quarta);

      // `qua-06:00` já existe no template: a marcação de segunda usa outra
      // atividade para não somar na quarta.
      expect(agenda.feitasEm(quarta), 1);
      expect(agenda.percentualEm(quarta), greaterThan(0));
      expect(agenda.percentualEm(DateTime(2026, 10, 22)), 0);
      expect(agenda.feitasNaSemana, 2);
      expect(
        agenda.percentualDaSemana,
        (agenda.feitasNaSemana / agenda.totalDaSemana * 100).round(),
      );
    });

    test('marcação de outra semana não aparece', () {
      final s = semana.definirConcluida(DateTime(2026, 10, 28), 'qua-06:00', concluida: true);
      expect(Agenda.de(s, quarta).feitasNaSemana, 0);
      expect(Agenda.de(s, DateTime(2026, 10, 28)).feitasNaSemana, 1);
    });

    test('dia vazio não divide por zero', () {
      var s = semana;
      for (final a in semana.dia('dom')!.atividades) {
        s = s.removerAtividade('dom', a.id);
      }
      final domingo = DateTime(2026, 10, 25);
      final agenda = Agenda.de(s, domingo);
      expect(agenda.totalEm(domingo), 0);
      expect(agenda.percentualEm(domingo), 0);
      expect(agenda.feitasEm(domingo), 0);
    });

    test('comSelecionado troca de semana quando a data sai dela', () {
      final agenda = Agenda.de(semana, quarta);
      final proxima = agenda.comSelecionado(DateTime(2026, 10, 28));
      expect(proxima.inicio, DateTime(2026, 10, 26));
      expect(proxima.chaveDoSelecionado(), 'qua');
    });

    test('número ISO da semana', () {
      // 2026-10-19 é segunda da semana 43 (ISO).
      expect(Agenda.de(semana, DateTime(2026, 10, 19)).numeroDaSemana, 43);
      // 2027-01-01 (sexta) pertence à semana 53 de 2026.
      expect(Agenda.de(semana, DateTime(2027, 1, 1)).numeroDaSemana, 53);
    });
  });
}
