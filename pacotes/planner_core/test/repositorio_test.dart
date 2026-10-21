import 'package:flutter_test/flutter_test.dart';
import 'package:planner_core/planner_core.dart';

/// Fonte que falha na gravação, para provar que o estado local responde antes
/// da persistência e que o erro chega à tela.
class _FonteQuebrada with GravacaoGranular implements FonteDeDados {
  EstadoSemana _estado = EstadoSemana.inicial();
  int gravacoes = 0;

  @override
  String get descricao => 'quebrada';

  @override
  bool get permiteEscrita => true;

  @override
  EstadoSemana get estadoAtual => _estado;

  @override
  set estadoAtual(EstadoSemana valor) => _estado = valor;

  @override
  Future<EstadoSemana> carregar() async => _estado;

  @override
  Future<EstadoSemana> salvar(EstadoSemana estado) async {
    gravacoes++;
    throw const ErroFonte('O servidor recusou a gravação.');
  }
}

/// Fonte somente leitura, como um acervo publicado.
class _FonteLeitura with GravacaoGranular implements FonteDeDados {
  EstadoSemana _estado = EstadoSemana.inicial();

  @override
  String get descricao => 'somente leitura';

  @override
  bool get permiteEscrita => false;

  @override
  EstadoSemana get estadoAtual => _estado;

  @override
  set estadoAtual(EstadoSemana valor) => _estado = valor;

  @override
  Future<EstadoSemana> carregar() async => _estado;

  @override
  Future<EstadoSemana> salvar(EstadoSemana estado) async => throw const ErroFonte('sem escrita');
}

void main() {
  late Repositorio rep;
  late FonteMemoria fonte;

  setUp(() async {
    fonte = FonteMemoria();
    rep = Repositorio(fonte);
    await rep.carregar();
  });

  group('carregamento', () {
    test('pronto após carregar, com o template completo', () {
      expect(rep.estado, EstadoCarga.pronto);
      expect(rep.dias, hasLength(7));
      expect(rep.comodos, hasLength(6));
      expect(rep.erro, isNull);
      expect(rep.percentual, 0);
    });

    test('erro de gravação vira mensagem na tela', () async {
      final quebrada = Repositorio(_FonteQuebrada());
      await quebrada.carregar();
      expect(quebrada.estado, EstadoCarga.pronto);
      await quebrada.adicionarComodo('Adega');
      expect(quebrada.erro, isNotNull);
    });
  });

  group('marcar atividade', () {
    test('atualiza o estado local imediatamente e persiste', () async {
      final atividade = rep.dias.first.atividades.first;
      final futuro = rep.marcar(atividade, concluida: true);

      // Antes da persistência terminar, o estado já reflete a marcação.
      expect(rep.semana.concluida(atividade), isTrue);
      await futuro;

      expect(await fonte.carregar(), isA<EstadoSemana>());
      expect((await fonte.carregar()).marcadas, contains(atividade.id));
      expect(rep.percentual, greaterThan(0));
    });

    test('desmarcar remove do estado e da fonte', () async {
      final atividade = rep.dias.first.atividades.first;
      await rep.marcar(atividade, concluida: true);
      await rep.marcar(atividade, concluida: false);
      expect(rep.semana.concluida(atividade), isFalse);
      expect((await fonte.carregar()).marcadas, isEmpty);
    });

    test('alternar inverte a marcação', () async {
      final atividade = rep.dias[1].atividades.first;
      await rep.alternar(atividade);
      expect(rep.semana.concluida(atividade), isTrue);
      await rep.alternar(atividade);
      expect(rep.semana.concluida(atividade), isFalse);
    });

    test('gravação falha mantém a marcação local e reporta erro', () async {
      final quebrada = Repositorio(_FonteQuebrada());
      await quebrada.carregar();
      final atividade = quebrada.dias.first.atividades.first;

      final ok = await quebrada.marcar(atividade, concluida: true);

      expect(ok, isFalse);
      expect(quebrada.erro, 'O servidor recusou a gravação.');
      // O dado digitado não é revertido: perder a marcação seria pior.
      expect(quebrada.semana.concluida(atividade), isTrue);
    });

    test('fonte somente leitura recusa a escrita sem alterar o estado', () async {
      final somenteLeitura = Repositorio(_FonteLeitura());
      await somenteLeitura.carregar();
      final atividade = somenteLeitura.dias.first.atividades.first;

      final ok = await somenteLeitura.marcar(atividade, concluida: true);

      expect(ok, isFalse);
      expect(somenteLeitura.semana.concluida(atividade), isFalse);
      expect(somenteLeitura.erro, contains('não aceita alterações'));
    });
  });

  group('gravação por entidade', () {
    test('dois aparelhos marcando atividades diferentes não se sobrescrevem', () async {
      // A mesma fonte, dois Repositorios: é o cenário de duas abas abertas.
      final outro = Repositorio(fonte);
      await outro.carregar();

      await rep.marcar(rep.dias[0].atividades[0], concluida: true);
      await outro.marcar(outro.dias[1].atividades[0], concluida: true);

      final estado = await fonte.carregar();
      expect(estado.marcadas, containsAll([rep.dias[0].atividades[0].id, outro.dias[1].atividades[0].id]));
    });
  });

  group('cômodos', () {
    test('adiciona cômodo novo com id derivado do nome', () async {
      final ok = await rep.adicionarComodo('  Escritório  ');
      expect(ok, isTrue);
      expect(rep.comodos.last.nome, 'Escritório');
      expect(rep.comodos.last.id, 'escritorio');
      expect((await fonte.carregar()).comodos.last.id, 'escritorio');
    });

    test('recusa nome vazio e duplicado', () async {
      expect(await rep.adicionarComodo('   '), isFalse);
      expect(await rep.adicionarComodo('Cozinha'), isFalse);
      expect(rep.erro, contains('já está na lista'));
      expect(rep.comodos.where((c) => c.id == 'cozinha'), hasLength(1));
    });

    test('alternar conclui e reabre, persistindo', () async {
      final comodo = rep.comodos.first;
      await rep.alternarComodo(comodo);
      expect(rep.comodos.first.concluido, isTrue);
      expect((await fonte.carregar()).comodos.first.concluido, isTrue);
      await rep.alternarComodo(rep.comodos.first);
      expect(rep.comodos.first.concluido, isFalse);
    });

    test('remover cômodo tira da lista e da fonte', () async {
      final comodo = rep.comodos.first;
      await rep.removerComodo(comodo);
      expect(rep.comodos.any((c) => c.id == comodo.id), isFalse);
      expect((await fonte.carregar()).comodos.any((c) => c.id == comodo.id), isFalse);
    });
  });

  group('nova semana', () {
    test('limpar marcações preserva os cômodos', () async {
      await rep.marcar(rep.dias.first.atividades.first, concluida: true);
      await rep.alternarComodo(rep.comodos.first);
      final comodosAntes = rep.comodos.map((c) => c.id).toList();

      await rep.limparMarcacoes();

      expect(rep.semana.marcadas, isEmpty);
      expect(rep.percentual, 0);
      expect(rep.comodos.map((c) => c.id), comodosAntes);
      final estado = await fonte.carregar();
      expect(estado.marcadas, isEmpty);
      expect(estado.comodos.first.concluido, isTrue);
    });
  });

  group('telemetria', () {
    test('eventos são registrados após gravação bem-sucedida', () async {
      final atividade = rep.dias.first.atividades.first;
      await rep.marcar(atividade, concluida: true);

      final nomes = rep.analytics.recentes.map((e) => e.nome);
      expect(nomes, contains('atividade_concluida'));
      final evento = rep.analytics.recentes.lastWhere((e) => e.nome == 'atividade_concluida');
      expect(evento.entidadeId, atividade.id);
      expect(evento.propriedades['dia'], 'seg');
      expect(evento.propriedades['percentual'], greaterThan(0));
    });

    test('falha de gravação não gera evento de conclusão', () async {
      final quebrada = Repositorio(_FonteQuebrada());
      await quebrada.carregar();
      await quebrada.marcar(quebrada.dias.first.atividades.first, concluida: true);

      expect(quebrada.analytics.recentes.map((e) => e.nome), isNot(contains('atividade_concluida')));
      expect(quebrada.analytics.recentes.map((e) => e.nome), contains('erro'));
    });

    test('coletor que explode não derruba a ação', () async {
      final explosivo = Repositorio(FonteMemoria(), analytics: Analytics(_ColetorExplosivo()));
      await explosivo.carregar();
      final ok = await explosivo.marcar(explosivo.dias.first.atividades.first, concluida: true);
      expect(ok, isTrue);
    });
  });

  group('importação', () {
    test('substitui o estado inteiro', () async {
      final ok = await rep.importar(
        EstadoSemana(marcadas: const {'sex-11:00'}, comodos: [const Comodo(id: 'adega', nome: 'Adega')]),
      );
      expect(ok, isTrue);
      expect(rep.semana.marcadas, {'sex-11:00'});
      expect(rep.comodos.single.nome, 'Adega');
    });
  });
}

class _ColetorExplosivo implements ColetorAnalytics {
  @override
  String get descricao => 'explosivo';

  @override
  String? get ultimoErro => null;

  @override
  void registrar(EventoAnalitico evento) => throw StateError('boom');

  @override
  void registrarVarios(Iterable<EventoAnalitico> eventos) => throw StateError('boom');

  @override
  Future<void> encerrar() async {}
}
