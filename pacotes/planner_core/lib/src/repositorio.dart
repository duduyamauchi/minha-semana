import 'package:flutter/foundation.dart';

import 'analytics/analytics.dart';
import 'analytics/coletor.dart';
import 'dados_semana.dart';
import 'fonte_dados.dart';
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
      _semana = Semana(dias: template ?? construirSemana(), marcadas: const {}, comodos: comodosPadrao());

  final FonteDeDados fonte;

  /// Telemetria do app. Toda escrita relevante gera evento aqui, sem que as
  /// telas precisem instrumentar nada manualmente.
  final Analytics analytics;

  Semana _semana;
  EstadoCarga _estado = EstadoCarga.inicial;
  String? _erro;

  /// Data de referência do "hoje" — fixável nos testes.
  DateTime Function() agora = DateTime.now;

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

  int get percentual => _semana.percentual;
  int get totalFeitas => _semana.totalFeitas;
  int get totalAtividades => _semana.totalAtividades;

  /// Índice do dia de hoje (segunda = 0), calculado a cada leitura para que o
  /// app atravesse a meia-noite sem reiniciar.
  int get indiceHoje => Semana.indiceDeHoje(agora());

  /// O estado está em um servidor, não no aparelho.
  bool get fonteRemota => fonte.remota;

  /// Conclui ou não uma atividade. Devolve `false` quando a gravação falha.
  Future<bool> marcar(Atividade atividade, {required bool concluida}) => _aplicar(
    (atual) {
      final marcadas = Set<String>.of(atual.marcadas);
      if (concluida) {
        marcadas.add(atividade.id);
      } else {
        marcadas.remove(atividade.id);
      }
      return atual.copiarCom(marcadas: marcadas);
    },
    gravar: () => fonte.definirAtividade(atividade.id, concluida: concluida),
    evento: concluida ? 'atividade_concluida' : 'atividade_desmarcada',
    propriedades: {
      'atividade': atividade.titulo,
      'horario': atividade.horario,
      'categoria': atividade.categoria.chave,
      'dia': atividade.id.split('-').first,
    },
    entidade: 'atividade',
    entidadeId: atividade.id,
  );

  /// Inverte a marcação de uma atividade.
  Future<bool> alternar(Atividade atividade) =>
      marcar(atividade, concluida: !_semana.concluida(atividade));

  /// Desmarca a semana inteira, preservando os cômodos.
  ///
  /// É a ação "Começar nova semana" do planejador original.
  Future<bool> limparMarcacoes() => _aplicar(
    (atual) => atual.copiarCom(marcadas: const <String>{}),
    gravar: () => fonte.limparMarcacoes(),
    evento: 'semana_reiniciada',
    propriedades: {'marcadasAntes': _semana.marcadas.length},
  );

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
    propriedades: {'marcadas': novo.marcadas.length, 'comodos': novo.comodos.length},
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
      _semana = _semana.comEstado(estado);
      _estado = EstadoCarga.pronto;
      analytics.registrar(
        'semana_carregada',
        propriedades: {
          'fonte': fonte.descricao,
          'marcadas': _semana.marcadas.length,
          'comodos': _semana.comodos.length,
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
          'percentual': _semana.percentual,
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
