import 'package:flutter_test/flutter_test.dart';
import 'package:planner_core/planner_core.dart';

void main() {
  group('template da semana', () {
    test('tem sete dias, de segunda a domingo', () {
      final dias = construirSemana();
      expect(dias.map((d) => d.chave), ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom']);
      expect(dias.map((d) => d.nome), [
        'Segunda',
        'Terça',
        'Quarta',
        'Quinta',
        'Sexta',
        'Sábado',
        'Domingo',
      ]);
    });

    test('acorda às 6h e dorme às 22h em todos os dias', () {
      for (final dia in construirSemana()) {
        expect(dia.atividade('${dia.chave}-06:00')?.titulo, 'Acordar', reason: dia.nome);
        expect(dia.atividade('${dia.chave}-22:00')?.titulo, 'Dormir', reason: dia.nome);
      }
    });

    test('IDs são únicos e chaveados por dia e horário', () {
      final ids = <String>[];
      for (final dia in construirSemana()) {
        for (final a in dia.atividades) {
          expect(a.id, Atividade.chavear(dia.chave, a.horario));
          ids.add(a.id);
        }
      }
      expect(ids.toSet().length, ids.length);
    });

    test('atividades estão em ordem cronológica dentro do dia', () {
      for (final dia in construirSemana()) {
        final horarios = dia.atividades.map((a) => a.horario).toList();
        final ordenados = [...horarios]..sort();
        expect(horarios, ordenados, reason: dia.nome);
      }
    });

    test('segunda e quarta são dias inteiros de reorganização', () {
      for (final chave in ['seg', 'qua']) {
        final dia = construirSemana().firstWhere((d) => d.chave == chave);
        final blocos = dia.atividades.where((a) => a.titulo == 'Reorganização');
        expect(blocos.length, 2, reason: chave);
        // 3h30 + 4h de reorganização = a maior parte do dia.
        expect(blocos.every((a) => a.prioridade), isTrue);
      }
    });

    test('sábado troca o Inglês pela limpeza completa', () {
      final sabado = construirSemana().firstWhere((d) => d.chave == 'sab');
      expect(sabado.atividades.any((a) => a.titulo == 'Inglês'), isFalse);
      expect(sabado.atividades.any((a) => a.titulo == 'Limpeza completa'), isTrue);
    });

    test('academia e pilates são compromissos fixos', () {
      final semana = construirSemana();
      for (final chave in ['ter', 'qui', 'sex']) {
        final dia = semana.firstWhere((d) => d.chave == chave);
        expect(dia.atividades.firstWhere((a) => a.titulo == 'Academia').fixo, isTrue);
      }
      for (final chave in ['ter', 'qui']) {
        final dia = semana.firstWhere((d) => d.chave == chave);
        expect(dia.atividades.firstWhere((a) => a.titulo == 'Pilates').fixo, isTrue);
      }
    });

    test('domingo reserva a tarde para descanso e planejamento', () {
      final domingo = construirSemana().firstWhere((d) => d.chave == 'dom');
      expect(domingo.atividade('dom-13:30')?.titulo, 'Descanso');
      expect(domingo.atividade('dom-17:00')?.titulo, 'Planejar a semana');
    });

    test('toda categoria aparece na semana', () {
      final categorias = {
        for (final dia in construirSemana())
          for (final a in dia.atividades) a.categoria,
      };
      expect(categorias, Categoria.values.toSet());
    });
  });

  group('progresso', () {
    test('começa zerado e chega a 100% com tudo marcado', () {
      final inicial = semanaInicial();
      expect(inicial.percentual, 0);
      expect(inicial.totalAtividades, greaterThan(0));

      final tudo = Semana(
        dias: inicial.dias,
        marcadas: {
          for (final d in inicial.dias)
            for (final a in d.atividades) a.id,
        },
        comodos: inicial.comodos,
      );
      expect(tudo.totalFeitas, tudo.totalAtividades);
      expect(tudo.percentual, 100);
    });

    test('marcações de IDs inexistentes não contam no total', () {
      final semana = Semana(
        dias: construirSemana(),
        marcadas: const {'seg-06:00', 'fantasma-99:99'},
        comodos: comodosPadrao(),
      );
      expect(semana.totalFeitas, 1);
    });

    test('conta feitas por dia', () {
      final semana = Semana(
        dias: construirSemana(),
        marcadas: const {'seg-06:00', 'seg-06:40', 'ter-22:00'},
        comodos: comodosPadrao(),
      );
      final segunda = semana.dia('seg')!;
      expect(semana.feitasNoDia(segunda), 2);
      expect(semana.feitasNoDia(semana.dia('qua')!), 0);
    });

    test('indiceDeHoje usa segunda como zero', () {
      expect(Semana.indiceDeHoje(DateTime(2026, 10, 19)), 0); // segunda
      expect(Semana.indiceDeHoje(DateTime(2026, 10, 25)), 6); // domingo
      expect(Semana.chaveDe(DateTime(2026, 10, 21)), 'qua');
    });
  });

  group('serialização', () {
    test('ida e volta preserva marcações e cômodos', () {
      final estado = EstadoSemana(
        marcadas: const {'seg-06:00', 'dom-22:00'},
        comodos: [const Comodo(id: 'cozinha', nome: 'Cozinha', concluido: true)],
      );
      final lido = EstadoSemana.fromJson(estado.toJson());
      expect(lido.marcadas, estado.marcadas);
      expect(lido.comodos.single.nome, 'Cozinha');
      expect(lido.comodos.single.concluido, isTrue);
    });

    test('JSON vazio ou inválido cai no padrão, sem lançar', () {
      final lido = EstadoSemana.fromJson(const {});
      expect(lido.marcadas, isEmpty);
      expect(lido.comodos.map((c) => c.nome), contains('Guarda-roupa'));
    });

    test('entradas malformadas são descartadas, o resto sobrevive', () {
      final lido = EstadoSemana.fromJson(const {
        'marcadas': ['seg-06:00', 42, '', null],
        'comodos': [
          {'id': 'sala', 'nome': 'Sala'},
          {'nome': ''},
          {'id': 'sala', 'nome': 'Duplicado'},
        ],
      });
      expect(lido.marcadas, {'seg-06:00'});
      expect(lido.comodos.map((c) => c.nome), ['Sala']);
    });

    test('Semana.doJson junta o estado ao template compilado', () {
      final semana = Semana.doJson(const {
        'marcadas': ['qua-09:00'],
      }, base: construirSemana());
      expect(semana.dias, hasLength(7));
      expect(semana.totalFeitas, 1);
      expect(semana.dia('qua')!.atividade('qua-09:00')?.titulo, 'Reorganização');
    });
  });

  group('cômodos', () {
    test('id é determinístico e sem acento', () {
      expect(Comodo.idDe('Área de serviço'), 'area-de-servico');
      expect(Comodo.idDe('Papéis e documentos'), 'papeis-e-documentos');
      expect(Comodo.idDe('  Guarda-roupa  '), 'guarda-roupa');
      expect(Comodo.idDe('???'), 'comodo');
    });

    test('cômodos padrão do planejador original', () {
      expect(comodosPadrao().map((c) => c.nome), [
        'Guarda-roupa',
        'Cozinha',
        'Banheiro',
        'Papéis e documentos',
        'Sala',
        'Área de serviço',
      ]);
    });
  });

  group('formatos', () {
    test('inteiro usa ponto como separador de milhar', () {
      expect(Formatos.inteiro(1234), '1.234');
      expect(Formatos.inteiro(999), '999');
      expect(Formatos.inteiro(1000000), '1.000.000');
    });

    test('duração em texto curto', () {
      expect(Formatos.duracao(const Duration(seconds: 40)), '40 s');
      expect(Formatos.duracao(const Duration(minutes: 12)), '12 min');
      expect(Formatos.duracao(const Duration(hours: 1, minutes: 5)), '1 h 05 min');
      expect(Formatos.duracao(const Duration(hours: 2)), '2 h');
    });
  });
}
