import 'package:flutter_test/flutter_test.dart';
import 'package:planner_core/planner_core.dart';

EventoAnalitico _e(
  String nome,
  DateTime quando, {
  String sessao = 's1',
  Map<String, Object?> propriedades = const {},
  num? valor,
}) => EventoAnalitico(
  nome: nome,
  quando: quando,
  sessao: sessao,
  propriedades: propriedades,
  valor: valor,
);

void main() {
  group('Analise.porDia', () {
    test('preenche dias sem evento com zero', () {
      final eventos = [
        _e('a', DateTime(2026, 10, 19, 8)),
        _e('b', DateTime(2026, 10, 21, 8)),
        _e('c', DateTime(2026, 10, 21, 9)),
      ];
      final serie = Analise.porDia(eventos);
      expect(serie.map((p) => p.dia), ['2026-10-19', '2026-10-20', '2026-10-21']);
      expect(serie.map((p) => p.quantidade), [1, 0, 2]);
    });

    test('lista vazia devolve série vazia', () {
      expect(Analise.porDia(const []), isEmpty);
    });
  });

  group('Analise.agregados', () {
    test('conta sessões distintas e duração média', () {
      final eventos = [
        _e('a', DateTime(2026, 10, 21, 8, 0), sessao: 's1'),
        _e('b', DateTime(2026, 10, 21, 8, 30), sessao: 's1'),
        _e('c', DateTime(2026, 10, 21, 9, 0), sessao: 's2'),
      ];
      expect(Analise.sessoes(eventos), {'s1', 's2'});
      // s1 dura 30 min; s2 dura 0. Média = 15 min.
      expect(Analise.duracaoMedia(eventos), const Duration(minutes: 15));
    });

    test('porNome ordena do mais frequente ao menos', () {
      final eventos = [
        _e('raro', DateTime(2026, 10, 21)),
        _e('comum', DateTime(2026, 10, 21)),
        _e('comum', DateTime(2026, 10, 21)),
      ];
      expect(Analise.porNome(eventos).keys.toList(), ['comum', 'raro']);
    });

    test('soma e maior valor ignoram eventos sem valor', () {
      final eventos = [
        _e('a', DateTime(2026, 10, 21), valor: 3),
        _e('b', DateTime(2026, 10, 21)),
        _e('c', DateTime(2026, 10, 21), valor: 7.5),
      ];
      expect(Analise.somarValores(eventos), 10.5);
      expect(Analise.maiorValor(eventos), 7.5);
      expect(Analise.maiorValor(const []), 0);
    });

    test('percentual não divide por zero', () {
      expect(Analise.percentual(3, 4), 75);
      expect(Analise.percentual(0, 0), 0);
    });
  });

  group('eventos', () {
    test('JSON ida e volta preserva campos', () {
      final original = _e(
        'atividade_concluida',
        DateTime.utc(2026, 10, 21, 11, 2),
        propriedades: const {'atividade': 'Acordar', 'percentual': 3},
        valor: 1,
      );
      final lido = EventoAnalitico.fromJson(original.toJson());
      expect(lido.nome, original.nome);
      expect(lido.sessao, original.sessao);
      expect(lido.propriedades['atividade'], 'Acordar');
      expect(lido.valor, 1);
      expect(lido.quando.toUtc(), DateTime.utc(2026, 10, 21, 11, 2));
    });

    test('campos ausentes não quebram a leitura', () {
      final lido = EventoAnalitico.fromJson(const {});
      expect(lido.nome, 'desconhecido');
      expect(lido.sessao, 'sem-sessao');
      expect(lido.dia, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });
  });

  group('coletores', () {
    test('memória respeita o limite, descartando os mais antigos', () {
      final coletor = ColetorMemoria(limite: 2);
      coletor.registrar(_e('a', DateTime(2026, 10, 21)));
      coletor.registrar(_e('b', DateTime(2026, 10, 21)));
      coletor.registrar(_e('c', DateTime(2026, 10, 21)));
      expect(coletor.eventos.map((e) => e.nome), ['b', 'c']);
    });

    test('composto entrega para todos e agrega o último erro', () {
      final memoria = ColetorMemoria();
      final composto = ColetorComposto([memoria, const ColetorNulo()]);
      composto.registrar(_e('a', DateTime(2026, 10, 21)));
      expect(memoria.eventos, hasLength(1));
      expect(composto.ultimoErro, isNull);
    });

    test('nulo não guarda nada e nunca falha', () {
      const nulo = ColetorNulo();
      nulo.registrar(_e('a', DateTime(2026, 10, 21)));
      expect(nulo.ultimoErro, isNull);
      expect(nulo.descricao, 'desligado');
    });
  });

  group('Analytics', () {
    test('anexa sessão, tela e usuário aos eventos', () {
      final memoria = ColetorMemoria();
      final analytics = Analytics(memoria);
      analytics.identificar('sarah');
      analytics.visitar('/semana');
      analytics.registrar('atividade_concluida');

      final evento = memoria.eventos.last;
      expect(evento.usuario, 'sarah');
      expect(evento.tela, '/semana');
      expect(evento.sessao, analytics.sessao);
    });
  });
}
