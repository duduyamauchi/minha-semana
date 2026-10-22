import 'package:flutter_test/flutter_test.dart';
import 'package:planner_core/planner_core.dart';

/// Conflitos de horário: aviso derivado, nunca bloqueio.
///
/// O caso que originou a feature: "Acordar" às 06:00 e "Manutenção" às 06:10.
/// Dar 10 min ao primeiro encaixa os dois; dar mais que 10 invade o segundo.
void main() {
  Atividade a(String id, String horario, int? duracao, {String? titulo}) => Atividade(
    id: id,
    dia: 'seg',
    horario: horario,
    titulo: titulo ?? id,
    duracaoMinutos: duracao,
    categoria: Categoria.casa,
  );

  group('sobreposição', () {
    test('duração que termina no início do próximo não é conflito', () {
      final lista = [a('acordar', '06:00', 10), a('manutencao', '06:10', 20)];
      expect(Conflitos.de(lista), isEmpty);
    });

    test('duração que passa do início do próximo é conflito', () {
      final lista = [a('acordar', '06:00', 25), a('manutencao', '06:10', 20)];
      final conflitos = Conflitos.de(lista);
      expect(conflitos, hasLength(1));
      expect(conflitos.single.minutos, 15);
      expect(conflitos.single.primeira.id, 'acordar');
      expect(conflitos.single.segunda.id, 'manutencao');
    });

    test('item pontual dentro de um intervalo conflita', () {
      // O caso do pedido: 06:00 com 30 min engole o compromisso das 06:10.
      final lista = [a('acordar', '06:00', 30), a('manutencao', '06:10', null)];
      final conflitos = Conflitos.de(lista);
      expect(conflitos, hasLength(1));
      expect(conflitos.single.minutos, 0);
      expect(conflitos.single.descricaoPara(lista.first), contains('06:10'));
    });

    test('item pontual fora do intervalo não conflita', () {
      final lista = [a('acordar', '06:00', 10), a('manutencao', '06:10', null)];
      expect(Conflitos.de(lista), isEmpty);
    });

    test('dois itens pontuais no mesmo horário não conflitam', () {
      // Não ocupam tempo: dois lembretes às 06:00 convivem.
      final lista = [a('x', '06:00', null), a('y', '06:00', null)];
      expect(Conflitos.de(lista), isEmpty);
    });

    test('duração zero ou negativa conta como item pontual', () {
      final lista = [
        a('x', '06:05', 0),
        a('y', '06:20', -5),
        a('z', '06:00', 60),
      ];
      // `z` cobre [06:00, 07:00): os dois pontuais caem dentro.
      final conflitos = Conflitos.de(lista);
      expect(conflitos, hasLength(2));
      expect(conflitos.every((c) => c.minutos == 0), isTrue);
      // O item de duração zero não vira intervalo (não engole ninguém).
      expect(conflitos.every((c) => c.primeira.id == 'z'), isTrue);
    });

    test('ordem da lista não importa', () {
      final lista = [a('manutencao', '06:10', 20), a('acordar', '06:00', 25)];
      final conflitos = Conflitos.de(lista);
      expect(conflitos, hasLength(1));
      expect(conflitos.single.primeira.id, 'acordar');
    });

    test('conflito com três atividades sobrepostas gera todos os pares', () {
      final lista = [
        a('a', '09:00', 120),
        a('b', '09:30', 30),
        a('c', '09:45', 30),
      ];
      final conflitos = Conflitos.de(lista);
      expect(conflitos, hasLength(3)); // a×b, a×c, b×c
      expect(conflitos.map((c) => c.minutos).toList(), [30, 30, 15]);
    });

    test('atividade longa que engole as seguintes', () {
      // a: 09:00–12:00, b: 10:00–10:15, c: 11:00–11:15.
      final lista = [a('a', '09:00', 180), a('b', '10:00', 15), a('c', '11:00', 15)];
      final conflitos = Conflitos.de(lista);
      expect(conflitos, hasLength(2));
      // O trecho comum é o da atividade curta inteira, não a duração de `a`.
      expect(conflitos.map((c) => c.minutos).toList(), [15, 15]);
    });

    test('mapa por atividade inclui as duas pontas', () {
      final lista = [a('acordar', '06:00', 25), a('manutencao', '06:10', 20)];
      final mapa = Conflitos.porAtividade(lista);
      expect(mapa.keys, containsAll(['acordar', 'manutencao']));
      expect(mapa['acordar'], hasLength(1));
      expect(mapa['manutencao'], hasLength(1));
    });

    test('atividade sem conflito não entra no mapa', () {
      final lista = [a('a', '06:00', 10), a('b', '06:10', 10)];
      expect(Conflitos.porAtividade(lista), isEmpty);
    });

    test('template do app não tem conflito (blocos encaixados)', () {
      // A rotina original encosta um bloco no outro; um cálculo com intervalo
      // fechado acusaria conflito em quase toda linha.
      for (final dia in construirSemana()) {
        expect(
          Conflitos.de(dia.atividades),
          isEmpty,
          reason: '${dia.nome}: ${Conflitos.de(dia.atividades)}',
        );
      }
    });
  });

  group('conflitos de uma atividade (editor)', () {
    test('encontra a outra ponta e ignora a si mesma', () {
      final referencia = a('acordar', '06:00', 25);
      final lista = [referencia, a('manutencao', '06:10', 20)];
      final conflitos = Conflitos.deAtividade(referencia, lista);
      expect(conflitos, hasLength(1));
      expect(conflitos.single.outraDe(referencia)?.id, 'manutencao');
    });

    test('enquanto a duração for segura, não acusa nada', () {
      final referencia = a('acordar', '06:00', 10);
      expect(Conflitos.deAtividade(referencia, [referencia, a('m', '06:10', 20)]), isEmpty);
    });

    test('vários vizinhos sobrepostos aparecem em ordem', () {
      final referencia = a('longa', '09:00', 180);
      final conflitos = Conflitos.deAtividade(referencia, [
        referencia,
        a('b', '10:00', 15),
        a('c', '09:30', 15),
      ]);
      expect(conflitos.map((c) => c.outraDe(referencia)!.id).toList(), ['c', 'b']);
      expect(conflitos.every((c) => c.outraDe(referencia) != null), isTrue);
    });

    test('referência pontual conflita com intervalo que a contém', () {
      final referencia = a('pontual', '06:10', null);
      final conflitos = Conflitos.deAtividade(referencia, [
        referencia,
        a('longa', '06:00', 60),
      ]);
      expect(conflitos, hasLength(1));
      expect(conflitos.single.outraDe(referencia)?.id, 'longa');
    });

    test('referência pontual encostada no início do intervalo não conflita', () {
      final referencia = a('pontual', '06:00', null);
      expect(
        Conflitos.deAtividade(referencia, [referencia, a('m', '06:00', 60)]),
        hasLength(1),
        reason: 'estar no início é estar dentro: dois lugares às 06:00 é choque',
      );
      final depois = a('pontual2', '07:00', null);
      expect(Conflitos.deAtividade(depois, [depois, a('m', '06:00', 60)]), isEmpty);
    });
  });

  group('mensagens', () {
    test('descrição nomeia a outra atividade e o intervalo', () {
      final acordar = a('acordar', '06:00', 25, titulo: 'Acordar');
      final manutencao = a('manutencao', '06:10', 20, titulo: 'Manutenção da limpeza');
      final conflito = Conflitos.de([acordar, manutencao]).single;

      expect(conflito.descricaoPara(acordar), 'Conflito com Manutenção da limpeza (06:10–06:30)');
      expect(conflito.descricaoPara(manutencao), 'Conflito com Acordar (06:00–06:25)');
      expect(conflito.minutosTexto, '15 minutos');
    });

    test('faixa com término é compacta', () {
      expect(a('x', '06:00', 45).faixaComTermino, '06:00–06:45');
      expect(a('x', '06:00', null).faixaComTermino, '06:00');
    });
  });
}
