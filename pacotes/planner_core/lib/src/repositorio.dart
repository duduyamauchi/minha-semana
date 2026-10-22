import 'package:flutter/foundation.dart';

import 'analytics/analytics.dart';
import 'analytics/coletor.dart';
import 'dados_semana.dart';
import 'conflitos.dart';
import 'datas.dart';
import 'fonte_dados.dart';
import 'horario.dart';
import 'modelos.dart';

/// Estado de carregamento da semana.
enum EstadoCarga { inicial, carregando, pronto, erro }

/// Fachada única entre a interface e qualquer fonte de dados.
///
/// A tela lê daqui e nunca fala com a fonte. Toda escrita atualiza o estado
/// local **na hora** (o checkbox responde no mesmo frame) e depois persiste; se
/// a gravação falhar, [erro] é preenchido e a tela mostra a mensagem.
class Repositorio extends ChangeNotifier {
  Repositorio(this.fonte, {Analytics? analytics, List<Dia>? template})
    : analytics = analytics ?? Analytics(const ColetorNulo()),
      _base = template ?? construirPlanoInicial(),
      _semana = Semana(
        dias: template ?? construirPlanoInicial(),
        concluidas: const {},
        comodos: comodosPadrao(),
      );

  /// Plano de partida: usado só enquanto a fonte não devolve dias (estado v2).
  final List<Dia> _base;

  final FonteDeDados fonte;

  /// Telemetria do app. Toda escrita relevante gera evento aqui, sem que as
  /// telas precisem instrumentar nada manualmente.
  final Analytics analytics;

  Semana _semana;
  EstadoCarga _estado = EstadoCarga.inicial;
  String? _erro;

  /// Data de referência do "hoje" — fixável nos testes.
  DateTime Function() agora = DateTime.now;

  /// Data aberta na timeline. Navegar por semanas muda esta data, não o plano.
  /// Data escolhida explicitamente. `null` significa "hoje", resolvido a cada
  /// leitura contra [agora].
  ///
  /// Guardar `DateTime.now()` no construtor congelava o dia da criação: um teste
  /// que injeta `agora` via continuava abrindo a data real, e o app aberto à
  /// meia-noite ficaria no dia anterior.
  DateTime? _selecionadoFixo;

  /// Data aberta na timeline (sem hora).
  /// Data aberta: a escolhida ou, sem escolha, hoje (segundo [agora]).
  DateTime get selecionado => _selecionadoFixo ?? Datas.hoje(agora());

  /// A semana da data aberta, com progresso por dia.
  Agenda get agenda => Agenda.de(_semana, selecionado);

  /// Conflitos de horário do dia [chave], indexados por atividade.
  ///
  /// Derivado do template (não é estado): a mesma rotina tem os mesmos choques
  /// em todas as semanas, então não há nada a persistir nem a sincronizar.
  Map<String, List<Conflito>> conflitosDoDia(String chave) {
    final dia = _semana.dia(chave);
    if (dia == null) return const {};
    return Conflitos.porAtividade(dia.atividades);
  }

  /// Abre outra data (dentro ou fora da semana atual).
  ///
  /// Só muda o que a tela lê: o template é o mesmo para todas as semanas, e as
  /// marcações são consultadas pela data.
  void irPara(DateTime data) {
    final alvo = Datas.dia(data);
    if (Datas.mesmoDia(alvo, selecionado)) return;
    _selecionadoFixo = alvo;
    _erro = null;
    notifyListeners();
  }

  /// Abre a semana de [data], mantendo o mesmo dia da semana quando possível.
  void irParaSemana(DateTime data) {
    final mesmaPosicao = Datas.indiceNaSemana(selecionado);
    final segunda = Datas.segundaDe(data);
    irPara(Datas.somarDias(segunda, mesmaPosicao));
  }

  /// Volta para hoje (e deixa de fixar uma data).
  void irParaHoje() {
    _selecionadoFixo = null;
    _erro = null;
    notifyListeners();
  }

  /// Avança ou recua semanas.
  void moverSemana(int semanas) => irPara(Datas.somarDias(selecionado, semanas * 7));

  // ---------------------------------------------------------------------------
  // Estado
  // ---------------------------------------------------------------------------

  Semana get semana => _semana;
  List<Dia> get dias => _semana.dias;
  List<Comodo> get comodos => _semana.comodos;

  EstadoCarga get estado => _estado;
  String? get erro => _erro;
  bool get carregando => _estado == EstadoCarga.carregando;
  bool get pronto => _estado == EstadoCarga.pronto;
  bool get permiteEscrita => fonte.permiteEscrita && _estado == EstadoCarga.pronto;

  /// Percentual da semana aberta (não do histórico inteiro).
  int get percentual => agenda.percentualDaSemana;
  int get totalFeitas => agenda.feitasNaSemana;
  int get totalAtividades => agenda.totalDaSemana;

  bool get hojeNaSemana => agenda.datas.any((d) => Datas.mesmoDia(d, Datas.hoje(agora())));

  /// Índice do dia de hoje (segunda = 0), calculado a cada leitura para que o
  /// app atravesse a meia-noite sem reiniciar.
  int get indiceHoje => Semana.indiceDeHoje(agora());

  /// O estado está em um servidor, não no aparelho.
  bool get fonteRemota => fonte.remota;

  /// Data em que a marcação de [atividade] deve cair.
  ///
  /// Se a data pedida já é o dia da semana da atividade, é ela. Caso contrário
  /// usa o mesmo dia da semana **dentro da semana aberta**: uma atividade de
  /// segunda marcada enquanto a tela mostra quinta pertence à segunda daquela
  /// semana, não à quinta. Sem isso, a marcação não apareceria em lugar nenhum
  /// (nem no dia, nem no progresso).
  DateTime dataDaAtividade(Atividade atividade, {DateTime? data}) {
    final referencia = Datas.dia(data ?? selecionado);
    if (Semana.chaveDaData(referencia) == atividade.dia) return referencia;
    final semana = Agenda.de(_semana, referencia);
    for (final d in semana.datas) {
      if (Semana.chaveDaData(d) == atividade.dia) return d;
    }
    return referencia;
  }

  /// Conclui ou não uma atividade **na semana aberta**.
  ///
  /// A data é explícita porque a mesma atividade existe em todas as semanas:
  /// marcar a quarta não pode marcar todas as quartas.
  Future<bool> marcar(
    Atividade atividade, {
    required bool concluida,
    DateTime? data,
  }) {
    final alvo = dataDaAtividade(atividade, data: data);
    return _aplicar(
      (atual) => atual.definirConcluida(alvo, atividade.id, concluida: concluida),
      gravar: () => fonte.definirConcluida(alvo, atividade.id, concluida: concluida),
      evento: concluida ? 'atividade_concluida' : 'atividade_desmarcada',
      propriedades: {
        'atividade': atividade.titulo,
        'horario': atividade.horario,
        'categoria': atividade.categoria.chave,
        'dia': atividade.dia,
        'data': Datas.iso(alvo),
      },
      entidade: 'atividade',
      entidadeId: atividade.id,
    );
  }

  /// Inverte a marcação de uma atividade na semana aberta.
  Future<bool> alternar(Atividade atividade, {DateTime? data}) {
    final alvo = dataDaAtividade(atividade, data: data);
    return marcar(atividade, concluida: !_semana.concluidaEm(alvo, atividade), data: alvo);
  }

  /// Verdadeiro quando a atividade está marcada na data aberta.
  bool concluidaNaData(Atividade atividade, {DateTime? data}) =>
      _semana.concluidaEm(data ?? selecionado, atividade);

  /// Atividade nova, ainda não persistida, no dia indicado.
  ///
  /// O id é escolhido aqui (e não na tela) para garantir unicidade: a mesma
  /// regra vale para o editor e para o botão "adicionar".
  Atividade novaAtividade(String chaveDia, {String? horario, String? titulo, String? detalhe}) {
    final atual = _semana.dia(chaveDia) ?? _semana.dias.first;
    return _semana.novaAtividade(
      atual.atividades.isNotEmpty
          ? atual.atividades.last
          : Atividade(
              id: Atividade.chavear(atual.chave, '08:00'),
              dia: atual.chave,
              horario: '08:00',
              titulo: '',
              categoria: Categoria.casa,
            ),
      // Sem horário explícito, começa "agora" arredondado para os próximos
      // 15 min: é o palpite útil quando se cria no meio do dia. O último
      // horário do dia seria 22:00 (Dormir), o que raramente serve.
      horario: horario ?? _proximaQuinzena(),
      titulo: titulo,
      detalhe: detalhe,
    );
  }

  /// Hora atual arredondada para cima em 15 min (mínimo 00:05).
  String _proximaQuinzena() {
    final agora = this.agora();
    final minutos = agora.hour * 60 + agora.minute;
    final arredondado = ((minutos + 14) ~/ 15) * 15;
    return Horario.formatar(arredondado);
  }

  /// Cria ou atualiza uma atividade do plano.
  ///
  /// Devolve `false` sem gravar quando o título está vazio ou o horário não é
  /// válido — validar aqui evita um registro inútil no banco e uma tela
  /// inconsistente com a fonte.
  Future<bool> salvarAtividade(Atividade atividade) async {
    final titulo = atividade.titulo.trim();
    if (titulo.isEmpty) {
      _erro = 'A atividade precisa de um título.';
      notifyListeners();
      return false;
    }
    if (Horario.minutos(atividade.horario) == null) {
      _erro = 'Horário inválido. Use HH:mm.';
      notifyListeners();
      return false;
    }
    final normalizada = atividade.copiarCom(
      titulo: titulo,
      horario: Horario.normalizar(atividade.horario)!,
      detalhe: atividade.detalhe.trim(),
    );
    final eraNova = _semana.dia(normalizada.dia)?.atividade(normalizada.id) == null;
    return _aplicar(
      (atual) => atual.salvarAtividade(normalizada),
      gravar: () => fonte.salvarAtividade(normalizada),
      evento: eraNova ? 'atividade_criada' : 'atividade_editada',
      propriedades: {
        'atividade': normalizada.titulo,
        'horario': normalizada.horario,
        'duracao': normalizada.duracaoMinutos,
        'categoria': normalizada.categoria.chave,
        'dia': normalizada.dia,
      },
      entidade: 'atividade',
      entidadeId: normalizada.id,
    );
  }

  /// Remove uma atividade (e a marcação dela, se havia).
  Future<bool> removerAtividade(Atividade atividade) => _aplicar(
    (atual) => atual.removerAtividade(atividade.dia, atividade.id),
    gravar: () => fonte.removerAtividade(atividade.dia, atividade.id),
    evento: 'atividade_removida',
    propriedades: {'atividade': atividade.titulo, 'dia': atividade.dia},
    entidade: 'atividade',
    entidadeId: atividade.id,
  );

  /// Desmarca a semana aberta, preservando o template e os cômodos.
  ///
  /// É a ação "Começar nova semana" do planejador original — agora restrita à
  /// semana visível: as anteriores ficam no histórico, como um calendário.
  Future<bool> limparMarcacoes() {
    final inicio = agenda.inicio;
    final antes = agenda.feitasNaSemana;
    return _aplicar(
      (atual) => atual.limparIntervalo(inicio),
      gravar: () => fonte.limparMarcacoes(inicio),
      evento: 'semana_reiniciada',
      propriedades: {'marcadasAntes': antes, 'semana': Datas.iso(inicio)},
    );
  }

  /// Marca ou desmarca um cômodo da reorganização.
  Future<bool> alternarComodo(Comodo comodo) {
    final novo = comodo.copiarCom(concluido: !comodo.concluido);
    return _aplicar(
      (atual) => atual.copiarCom(
        comodos: [for (final c in atual.comodos) if (c.id == comodo.id) novo else c],
      ),
      gravar: () => fonte.salvarComodo(novo),
      evento: novo.concluido ? 'comodo_concluido' : 'comodo_reaberto',
      propriedades: {'comodo': comodo.nome},
      entidade: 'comodo',
      entidadeId: comodo.id,
    );
  }

  /// Adiciona um cômodo ou categoria. Ignora nome vazio e duplicado.
  Future<bool> adicionarComodo(String nome) async {
    final limpo = nome.trim();
    if (limpo.isEmpty) return false;
    final id = Comodo.idDe(limpo);
    if (_semana.comodos.any((c) => c.id == id)) {
      _erro = '“$limpo” já está na lista.';
      analytics.registrar('comodo_duplicado', propriedades: {'comodo': limpo});
      notifyListeners();
      return false;
    }
    final novo = Comodo(id: id, nome: limpo);
    return _aplicar(
      (atual) => atual.copiarCom(comodos: [...atual.comodos, novo]),
      gravar: () => fonte.salvarComodo(novo),
      evento: 'comodo_criado',
      propriedades: {'comodo': limpo},
      entidade: 'comodo',
      entidadeId: id,
    );
  }

  /// Remove um cômodo.
  Future<bool> removerComodo(Comodo comodo) => _aplicar(
    (atual) => atual.copiarCom(comodos: [for (final c in atual.comodos) if (c.id != comodo.id) c]),
    gravar: () => fonte.removerComodo(comodo.id),
    evento: 'comodo_removido',
    propriedades: {'comodo': comodo.nome},
    entidade: 'comodo',
    entidadeId: comodo.id,
  );

  /// Substitui o estado inteiro (importação de backup).
  Future<bool> importar(EstadoSemana novo) => _aplicar(
    (_) => _semana.comEstado(novo),
    gravar: () => fonte.salvar(novo),
    evento: 'semana_importada',
    propriedades: {
      'diasComMarcacao': novo.concluidas.length,
      'comodos': novo.comodos.length,
      'atividades': novo.dias?.fold<int>(0, (s, d) => s + d.atividades.length),
    },
  );

  // ---------------------------------------------------------------------------
  // Carga e escrita
  // ---------------------------------------------------------------------------

  Future<void> carregar() async {
    _estado = EstadoCarga.carregando;
    _erro = null;
    notifyListeners();
    try {
      final estado = await fonte.carregar();
      // Estado sem plano (v2) é migrado para o template no primeiro
      // carregamento.
      _semana = Semana(
        dias: estado.dias ?? _base,
        concluidas: estado.concluidas,
        comodos: estado.comodos,
      );
      _estado = EstadoCarga.pronto;
      if (estado.dias == null) await _semearPlano();
      analytics.registrar(
        'semana_carregada',
        propriedades: {
          'fonte': fonte.descricao,
          'diasComMarcacao': _semana.concluidas.length,
          'comodos': _semana.comodos.length,
          'atividades': _semana.totalAtividades,
        },
      );
    } on ErroFonte catch (e) {
      _erro = e.mensagem;
      _estado = EstadoCarga.erro;
      analytics.erro('carregar_semana', e.mensagem, propriedades: {'fonte': fonte.descricao});
    } catch (e) {
      _erro = 'Falha inesperada ao carregar a semana: $e';
      _estado = EstadoCarga.erro;
      analytics.erro('carregar_semana', '$e', propriedades: {'fonte': fonte.descricao});
    }
    notifyListeners();
  }

  /// Grava o plano migrado na fonte que ainda não o tinha.
  ///
  /// Sem isto, numa fonte remota o plano só existiria na memória do aparelho:
  /// ao editar uma atividade, o servidor teria uma linha e mais nada, e outro
  /// aparelho veria um plano quase vazio. A falha aqui não derruba o app — o
  /// estado carregado continua utilizável e o erro fica visível.
  Future<void> _semearPlano() async {
    if (!fonte.permiteEscrita) return;
    try {
      await fonte.salvar(_semana.estado);
      analytics.registrar(
        'plano_semeado',
        propriedades: {'fonte': fonte.descricao, 'atividades': _semana.totalAtividades},
      );
    } on ErroFonte catch (e) {
      _erro = e.mensagem;
      analytics.erro('semear_plano', e.mensagem, propriedades: {'fonte': fonte.descricao});
    }
  }

  /// Aplica a transformação local, persiste e só então registra o evento.
  ///
  /// O evento descreve o que **aconteceu**: por isso ele vem depois da
  /// gravação, ao contrário do estado local, que vem antes para a tela responder
  /// de imediato.
  Future<bool> _aplicar(
    Semana Function(Semana atual) transformacao, {
    required Future<void> Function() gravar,
    required String evento,
    Map<String, Object?> propriedades = const {},
    String? entidade,
    String? entidadeId,
  }) async {
    if (!permiteEscrita) {
      _erro = 'A fonte de dados atual não aceita alterações.';
      notifyListeners();
      analytics.erro('gravacao_recusada', _erro!, propriedades: {'evento': evento});
      return false;
    }
    _semana = transformacao(_semana);
    _erro = null;
    notifyListeners();
    try {
      await gravar();
      analytics.registrar(
        evento,
        propriedades: {
          ...propriedades,
          'fonte': fonte.descricao,
          'percentual': agenda.percentualDaSemana,
        },
        entidade: entidade,
        entidadeId: entidadeId,
      );
      return true;
    } on ErroFonte catch (e) {
      _erro = e.mensagem;
      analytics.erro('gravar_semana', e.mensagem, propriedades: {'evento': evento});
      notifyListeners();
      return false;
    } catch (e) {
      _erro = 'Falha inesperada ao gravar: $e';
      analytics.erro('gravar_semana', '$e', propriedades: {'evento': evento});
      notifyListeners();
      return false;
    }
  }
}
