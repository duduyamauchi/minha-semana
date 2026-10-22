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
  _testesDeEdicao();

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

  group('marcar atividade por data', () {
    final segunda = DateTime(2026, 10, 19);
    final quarta = DateTime(2026, 10, 21);

    test('atualiza o estado local imediatamente e persiste na data', () async {
      rep.irPara(segunda);
      final atividade = rep.dias.first.atividades.first;
      final futuro = rep.marcar(atividade, concluida: true);

      // Antes da persistência terminar, o estado já reflete a marcação.
      expect(rep.concluidaNaData(atividade), isTrue);
      await futuro;

      final salvo = await fonte.carregar();
      expect(salvo.concluidas['2026-10-19'], contains(atividade.id));
      expect(rep.percentual, greaterThan(0));
    });

    test('a mesma atividade não fica marcada em outra semana', () async {
      rep.irPara(segunda);
      final atividade = rep.dias.first.atividades.first;
      await rep.marcar(atividade, concluida: true);

      rep.moverSemana(1);
      expect(rep.selecionado, DateTime(2026, 10, 26));
      expect(rep.concluidaNaData(atividade), isFalse);
      expect(rep.percentual, 0);

      final salvo = await fonte.carregar();
      expect(salvo.concluidas['2026-10-19'], contains(atividade.id));
      expect(salvo.concluidas['2026-10-26'], isNull);
    });

    test('desmarcar remove do estado e da fonte', () async {
      rep.irPara(segunda);
      final atividade = rep.dias.first.atividades.first;
      await rep.marcar(atividade, concluida: true);
      await rep.marcar(atividade, concluida: false);
      expect(rep.concluidaNaData(atividade), isFalse);
      expect((await fonte.carregar()).concluidas, isEmpty);
    });

    test('alternar inverte a marcação', () async {
      rep.irPara(segunda);
      final atividade = rep.dias.first.atividades.first;
      await rep.alternar(atividade);
      expect(rep.concluidaNaData(atividade), isTrue);
      await rep.alternar(atividade);
      expect(rep.concluidaNaData(atividade), isFalse);
    });

    test('marcar atividade de outro dia cai no dia dela dentro da semana', () async {
      rep.irPara(segunda);
      final terca = rep.dias[1].atividades.first;
      await rep.marcar(terca, concluida: true);

      final salvo = await fonte.carregar();
      expect(salvo.concluidas['2026-10-20'], contains(terca.id));
      expect(rep.agenda.feitasNaSemana, 1);
    });

    test('gravação falha mantém a marcação local e reporta erro', () async {
      final quebrada = Repositorio(_FonteQuebrada());
      await quebrada.carregar();
      quebrada.irPara(segunda);
      final atividade = quebrada.dias.first.atividades.first;

      final ok = await quebrada.marcar(atividade, concluida: true);

      expect(ok, isFalse);
      expect(quebrada.erro, 'O servidor recusou a gravação.');
      // O dado digitado não é revertido: perder a marcação seria pior.
      expect(quebrada.concluidaNaData(atividade), isTrue);
    });

    test('fonte somente leitura recusa a escrita sem alterar o estado', () async {
      final somenteLeitura = Repositorio(_FonteLeitura());
      await somenteLeitura.carregar();
      somenteLeitura.irPara(segunda);
      final atividade = somenteLeitura.dias.first.atividades.first;

      final ok = await somenteLeitura.marcar(atividade, concluida: true);

      expect(ok, isFalse);
      expect(somenteLeitura.concluidaNaData(atividade), isFalse);
      expect(somenteLeitura.erro, contains('não aceita alterações'));
    });

    test('agenda expõe a semana da data aberta', () async {
      rep.irPara(quarta);
      final agenda = rep.agenda;
      expect(agenda.inicio, segunda);
      expect(agenda.fim, DateTime(2026, 10, 25));
      expect(agenda.datas, hasLength(7));
      expect(agenda.chaveDoSelecionado(), 'qua');
      expect(agenda.diaSelecionado.nome, 'Quarta');
    });

    test('mover uma semana mantém o dia da semana aberto', () async {
      rep.irPara(quarta);
      rep.moverSemana(1);
      expect(rep.selecionado, DateTime(2026, 10, 28));
      expect(rep.agenda.chaveDoSelecionado(), 'qua');
      rep.moverSemana(-2);
      expect(rep.selecionado, DateTime(2026, 10, 14));
    });

    test('ir para hoje volta à data de referência', () async {
      rep.agora = () => DateTime(2026, 10, 21, 15, 30);
      rep.irPara(DateTime(2026, 12, 1));
      rep.irParaHoje();
      expect(rep.selecionado, DateTime(2026, 10, 21));
      expect(rep.hojeNaSemana, isTrue);
    });
  });

  group('gravação por entidade', () {
    test('dois aparelhos marcando atividades diferentes não se sobrescrevem', () async {
      // A mesma fonte, dois Repositorios: é o cenário de duas abas abertas.
      final data = DateTime(2026, 10, 19);
      final outro = Repositorio(fonte);
      await outro.carregar();
      rep.irPara(data);
      outro.irPara(data);

      await rep.marcar(rep.dias[0].atividades[0], concluida: true);
      await outro.marcar(outro.dias[1].atividades[0], concluida: true);

      final estado = await fonte.carregar();
      // Cada marcação cai no dia da própria atividade, na mesma semana.
      expect(estado.concluidas['2026-10-19'], contains(rep.dias[0].atividades[0].id));
      expect(estado.concluidas['2026-10-20'], contains(outro.dias[1].atividades[0].id));
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
    test('limpar a semana aberta preserva cômodos e histórico', () async {
      final anterior = DateTime(2026, 10, 12);
      final atual = DateTime(2026, 10, 19);

      rep.irPara(anterior);
      await rep.marcar(rep.dias.first.atividades.first, concluida: true);

      rep.irPara(atual);
      await rep.marcar(rep.dias.first.atividades.first, concluida: true);
      await rep.alternarComodo(rep.comodos.first);
      final comodosAntes = rep.comodos.map((c) => c.id).toList();

      await rep.limparMarcacoes();

      expect(rep.agenda.feitasNaSemana, 0);
      expect(rep.percentual, 0);
      expect(rep.comodos.map((c) => c.id), comodosAntes);

      final estado = await fonte.carregar();
      expect(estado.concluidas['2026-10-19'], isNull);
      // A semana anterior continua no histórico.
      expect(estado.concluidas['2026-10-12'], isNotEmpty);
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
      expect(evento.propriedades['data'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
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
        EstadoSemana(
          concluidas: const {
            '2026-10-23': {'sex-11:00'},
          },
          comodos: [const Comodo(id: 'adega', nome: 'Adega')],
        ),
      );
      expect(ok, isTrue);
      expect(rep.semana.concluidasEm(DateTime(2026, 10, 23)), {'sex-11:00'});
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

void _testesDeEdicao() {
  group('edição do plano pelo repositório', () {
    late Repositorio rep;
    late FonteMemoria fonte;

    setUp(() async {
      fonte = FonteMemoria();
      rep = Repositorio(fonte);
      await rep.carregar();
    });

    test('criar atividade persiste e aparece no dia', () async {
      final nova = rep.novaAtividade('ter', horario: '07:00', titulo: 'Corrida');
      final ok = await rep.salvarAtividade(nova);

      expect(ok, isTrue);
      expect(rep.semana.dia('ter')!.atividade(nova.id)!.titulo, 'Corrida');
      final salvo = await fonte.carregar();
      expect(salvo.dias!.firstWhere((d) => d.chave == 'ter').atividade(nova.id)!.titulo, 'Corrida');
    });

    test('editar horário e duração grava e mantém a marcação', () async {
      final data = DateTime(2026, 10, 19);
      rep.irPara(data);
      final original = rep.dias.first.atividades.first;
      await rep.alternar(original);

      final ok = await rep.salvarAtividade(
        original.copiarCom(horario: '05:45', duracaoMinutos: 25, titulo: 'Acordar cedo'),
      );

      expect(ok, isTrue);
      final relida = rep.semana.dia(original.dia)!.atividade(original.id)!;
      expect(relida.horario, '05:45');
      expect(relida.duracaoMinutos, 25);
      expect(rep.concluidaNaData(relida), isTrue);

      final salvo = await fonte.carregar();
      final gravada = salvo.dias!.firstWhere((d) => d.chave == original.dia).atividade(original.id)!;
      expect(gravada.horario, '05:45');
      expect(gravada.duracaoMinutos, 25);
    });

    test('excluir remove da tela, da fonte e das marcações', () async {
      final data = DateTime(2026, 10, 21);
      rep.irPara(data);
      final alvo = rep.dias[2].atividades.first;
      await rep.alternar(alvo);

      final ok = await rep.removerAtividade(alvo);

      expect(ok, isTrue);
      expect(rep.semana.dia(alvo.dia)!.atividade(alvo.id), isNull);
      final salvo = await fonte.carregar();
      expect(salvo.concluidas[Datas.iso(data)] ?? const <String>{}, isNot(contains(alvo.id)));
      expect(salvo.dias!.firstWhere((d) => d.chave == alvo.dia).atividade(alvo.id), isNull);
    });

    test('título vazio ou horário inválido não grava', () async {
      final nova = rep.novaAtividade('seg');
      expect(await rep.salvarAtividade(nova.copiarCom(titulo: '   ')), isFalse);
      expect(rep.erro, contains('título'));

      expect(
        await rep.salvarAtividade(nova.copiarCom(titulo: 'Válida', horario: '99:99')),
        isFalse,
      );
      expect(rep.erro, contains('Horário'));
      expect(rep.semana.dia('seg')!.atividade(nova.id), isNull);
    });

    test('horário é normalizado antes de gravar', () async {
      final nova = rep.novaAtividade('seg', horario: '7:5', titulo: 'Café');
      await rep.salvarAtividade(nova);
      expect(rep.semana.dia('seg')!.atividade(nova.id)!.horario, '07:05');
    });

    test('telemetria distingue criação de edição', () async {
      final nova = rep.novaAtividade('qua', horario: '06:20', titulo: 'Beber água');
      await rep.salvarAtividade(nova);
      await rep.salvarAtividade(nova.copiarCom(duracaoMinutos: 5));

      final nomes = rep.analytics.recentes.map((e) => e.nome).toList();
      expect(nomes, contains('atividade_criada'));
      expect(nomes, contains('atividade_editada'));
      final criada = rep.analytics.recentes.lastWhere((e) => e.nome == 'atividade_criada');
      expect(criada.propriedades['duracao'], isNull);
      final editada = rep.analytics.recentes.lastWhere((e) => e.nome == 'atividade_editada');
      expect(editada.propriedades['duracao'], 5);
    });

    test('plano editado sobrevive a um carregamento novo', () async {
      final nova = rep.novaAtividade('sex', horario: '21:30', titulo: 'Diário');
      await rep.salvarAtividade(nova);

      final outro = Repositorio(fonte);
      await outro.carregar();
      expect(outro.semana.dia('sex')!.atividade(nova.id)!.titulo, 'Diário');
    });

    test('edição falha mantém o estado local e reporta erro', () async {
      final quebrada = Repositorio(_FonteQuebrada());
      await quebrada.carregar();
      final nova = quebrada.novaAtividade('seg', horario: '10:10', titulo: 'Yoga');

      final ok = await quebrada.salvarAtividade(nova);

      expect(ok, isFalse);
      expect(quebrada.erro, isNotNull);
      expect(quebrada.semana.dia('seg')!.atividade(nova.id), isNotNull);
    });

    test('dois aparelhos editando dias diferentes não se sobrescrevem', () async {
      final outro = Repositorio(fonte);
      await outro.carregar();

      final a = rep.novaAtividade('seg', horario: '10:00', titulo: 'A');
      final b = outro.novaAtividade('ter', horario: '10:00', titulo: 'B');
      await rep.salvarAtividade(a);
      await outro.salvarAtividade(b);

      final salvo = await fonte.carregar();
      expect(salvo.dias!.firstWhere((d) => d.chave == 'seg').atividade(a.id), isNotNull);
      expect(salvo.dias!.firstWhere((d) => d.chave == 'ter').atividade(b.id), isNotNull);
    });
  });
}
