/// Modelo do domínio do Minha Semana.
///
/// É Dart puro: não importa `flutter/material.dart` e não conhece HTTP, banco
/// nem widget. Tudo o que a tela precisa saber sobre a semana (quais
/// atividades existem, o que está marcado, quanto já foi feito) é calculado
/// aqui, e não dentro de `build`.
library;

/// Áreas da rotina, com a cor que o template original dava a cada bloco.
enum Categoria {
  estudo('estudo', 'Estudo'),
  movimento('movimento', 'Movimento'),
  casa('casa', 'Casa'),
  bemEstar('bemEstar', 'Bem-estar');

  const Categoria(this.chave, this.rotulo);

  /// Identificador estável usado em JSON e no banco.
  final String chave;

  /// Rótulo exibido na legenda.
  final String rotulo;

  /// Lê a categoria tolerando valor desconhecido (cai em [casa]).
  ///
  /// Garante que um backend possa evoluir o esquema sem derrubar o app.
  static Categoria de(String? valor) {
    for (final c in Categoria.values) {
      if (c.chave == valor || c.name == valor) return c;
    }
    return Categoria.casa;
  }
}

/// Uma linha da timeline de um dia.
class Atividade {
  const Atividade({
    required this.id,
    required this.horario,
    required this.titulo,
    this.detalhe = '',
    required this.categoria,
    this.fixo = false,
    this.prioridade = false,
  });

  /// Identificador estável: `seg-06:00`.
  ///
  /// Chavear por dia + horário (e não pelo índice) faz a marcação sobreviver a
  /// uma mudança no template — inserir uma atividade não remarca as outras.
  final String id;

  /// Horário no formato `HH:mm`, como no planejador original.
  final String horario;

  final String titulo;

  /// Linha secundária; vazio quando a atividade não tem detalhe.
  final String detalhe;

  final Categoria categoria;

  /// Compromisso com hora marcada (academia, pilates): não é negociável.
  final bool fixo;

  /// Bloco que ocupa a maior parte do dia (a reorganização da casa).
  final bool prioridade;

  bool get temDetalhe => detalhe.isNotEmpty;

  Atividade copiarCom({String? horario, String? titulo, String? detalhe}) => Atividade(
    id: id,
    horario: horario ?? this.horario,
    titulo: titulo ?? this.titulo,
    detalhe: detalhe ?? this.detalhe,
    categoria: categoria,
    fixo: fixo,
    prioridade: prioridade,
  );

  static String chavear(String dia, String horario) => '$dia-$horario';

  Map<String, dynamic> toJson() => {
    'id': id,
    'horario': horario,
    'titulo': titulo,
    if (detalhe.isNotEmpty) 'detalhe': detalhe,
    'categoria': categoria.chave,
    'fixo': fixo,
    'prioridade': prioridade,
  };

  factory Atividade.fromJson(Map<String, dynamic> j) => Atividade(
    id: (j['id'] as String?) ?? chavear((j['dia'] as String?) ?? 'seg', (j['horario'] as String?) ?? '00:00'),
    horario: (j['horario'] as String?) ?? '00:00',
    titulo: (j['titulo'] as String?) ?? 'Sem título',
    detalhe: (j['detalhe'] as String?) ?? '',
    categoria: Categoria.de(j['categoria'] as String?),
    fixo: j['fixo'] == true,
    prioridade: j['prioridade'] == true,
  );

  @override
  String toString() => 'Atividade($id, $titulo)';
}

/// Um dia da semana com a sua timeline.
class Dia {
  const Dia({required this.chave, required this.nome, required this.nota, required this.atividades});

  /// `seg`, `ter`, … — usado na URL do dia e na chave de marcação.
  final String chave;

  /// Nome por extenso: `Segunda`.
  final String nome;

  /// Resumo do dia exibido ao lado do título.
  final String nota;

  final List<Atividade> atividades;

  /// `Seg`, `Ter`, … como nas abas do planejador.
  String get nomeCurto => nome.length <= 3 ? nome : nome.substring(0, 3);

  bool get ehFimDeSemana => chave == 'sab' || chave == 'dom';

  Atividade? atividade(String id) {
    for (final a in atividades) {
      if (a.id == id) return a;
    }
    return null;
  }
}

/// O plano semanal completo (o "template" e o estado do usuário).
///
/// [dias] é o template compilado; [marcadas] é o que o usuário já fez e
/// [comodos] é a lista de reorganização. Tudo o que muda é serializável: é
/// exatamente isso que a fonte de dados grava.
class Semana {
  const Semana({required this.dias, required this.marcadas, required this.comodos});

  final List<Dia> dias;

  /// IDs (`seg-06:00`) das atividades concluídas.
  final Set<String> marcadas;

  final List<Comodo> comodos;

  /// Total de atividades da semana, base do percentual.
  int get totalAtividades => dias.fold(0, (soma, d) => soma + d.atividades.length);

  /// Quantidade de atividades concluídas que ainda existem no template.
  int get totalFeitas {
    var feitas = 0;
    for (final d in dias) {
      for (final a in d.atividades) {
        if (marcadas.contains(a.id)) feitas++;
      }
    }
    return feitas;
  }

  /// Fração de 0 a 1; `0` quando não há atividades.
  double get progresso {
    final total = totalAtividades;
    return total == 0 ? 0 : totalFeitas / total;
  }

  /// Percentual arredondado, como o `0%` do cabeçalho.
  int get percentual => (progresso * 100).round();

  int feitasNoDia(Dia dia) =>
      dia.atividades.where((a) => marcadas.contains(a.id)).length;

  bool concluida(Atividade atividade) => marcadas.contains(atividade.id);

  bool comodoConcluido(Comodo comodo) => comodo.concluido;

  Dia? dia(String chave) {
    for (final d in dias) {
      if (d.chave == chave) return d;
    }
    return null;
  }

  /// Índice do dia de hoje (segunda = 0, domingo = 6).
  static int indiceDeHoje([DateTime? agora]) {
    final hoje = agora ?? DateTime.now();
    return (hoje.weekday - DateTime.monday) % 7;
  }

  /// Nome do dia da semana para uma data (segunda = 0).
  static String chaveDe([DateTime? agora]) {
    const chaves = ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'];
    return chaves[indiceDeHoje(agora)];
  }

  Semana copiarCom({
    List<Dia>? dias,
    Set<String>? marcadas,
    List<Comodo>? comodos,
  }) => Semana(
    dias: dias ?? this.dias,
    marcadas: marcadas ?? this.marcadas,
    comodos: comodos ?? this.comodos,
  );

  /// Esta semana com outro estado, mantendo o template.
  Semana comEstado(EstadoSemana novo) =>
      Semana(dias: dias, marcadas: novo.marcadas, comodos: novo.comodos);

  /// O que efetivamente se persiste: marcações e cômodos.
  ///
  /// O template não vai para o banco — ele é compilado no app, então mudar a
  /// rotina não exige migração de dados.
  EstadoSemana get estado => EstadoSemana(marcadas: marcadas, comodos: comodos);

  Map<String, dynamic> toJson() => estado.toJson();

  /// Reconstrói a semana a partir do JSON, sobre o template compilado.
  factory Semana.doJson(Map<String, dynamic> j, {required List<Dia> base}) {
    final estado = EstadoSemana.fromJson(j);
    return Semana(dias: base, marcadas: estado.marcadas, comodos: estado.comodos);
  }
}

/// Fotografia persistida da semana: o que o usuário fez, não o que o app propõe.
class EstadoSemana {
  const EstadoSemana({required this.marcadas, required this.comodos});

  final Set<String> marcadas;
  final List<Comodo> comodos;

  /// Versão do formato gravado. Serve para migrações futuras sem quebrar o
  /// estado já salvo no aparelho ou no banco.
  static const versaoFormato = 2;

  Map<String, dynamic> toJson() => {
    'versao': versaoFormato,
    'marcadas': marcadas.toList()..sort(),
    'comodos': [for (final c in comodos) c.toJson()],
  };

  /// Campos ausentes ou inválidos não quebram a leitura: entradas ruins são
  /// descartadas, o resto da semana continua válido.
  factory EstadoSemana.fromJson(Map<String, dynamic> j) {
    final marcadas = <String>{
      for (final m in (j['marcadas'] as List? ?? const []))
        if (m is String && m.isNotEmpty) m,
    };
    final comodos = <Comodo>[];
    final vistos = <String>{};
    for (final c in (j['comodos'] as List? ?? const [])) {
      if (c is! Map) continue;
      final comodo = Comodo.fromJson(c.cast<String, dynamic>());
      if (comodo.nome.isEmpty || !vistos.add(comodo.id)) continue;
      comodos.add(comodo);
    }
    return EstadoSemana(
      marcadas: marcadas,
      comodos: comodos.isEmpty ? comodosPadrao() : comodos,
    );
  }

  static EstadoSemana inicial() => EstadoSemana(marcadas: const {}, comodos: comodosPadrao());
}

/// Um cômodo (ou categoria) da reorganização da casa.
class Comodo {
  const Comodo({required this.id, required this.nome, this.concluido = false});

  final String id;
  final String nome;
  final bool concluido;

  Comodo copiarCom({String? nome, bool? concluido}) =>
      Comodo(id: id, nome: nome ?? this.nome, concluido: concluido ?? this.concluido);

  Map<String, dynamic> toJson() => {'id': id, 'nome': nome, 'concluido': concluido};

  factory Comodo.fromJson(Map<String, dynamic> j) => Comodo(
    id: (j['id'] as String?) ?? _idDe((j['nome'] as String?) ?? ''),
    nome: (j['nome'] as String?) ?? '',
    concluido: j['concluido'] == true || j['d'] == true,
  );

  /// ID determinístico a partir do nome: o mesmo cômodo nos dois aparelhos.
  static String idDe(String nome) => _idDe(nome);

  static String _idDe(String nome) {
    final limpo = nome
        .toLowerCase()
        .replaceAll(RegExp('[áàâãä]'), 'a')
        .replaceAll(RegExp('[éèêë]'), 'e')
        .replaceAll(RegExp('[íìîï]'), 'i')
        .replaceAll(RegExp('[óòôõö]'), 'o')
        .replaceAll(RegExp('[úùûü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp('^-+|-+\$'), '');
    return limpo.isEmpty ? 'comodo' : limpo;
  }
}

/// Lista inicial de cômodos do planejador original.
List<Comodo> comodosPadrao() => const [
  'Guarda-roupa',
  'Cozinha',
  'Banheiro',
  'Papéis e documentos',
  'Sala',
  'Área de serviço',
].map((n) => Comodo(id: Comodo.idDe(n), nome: n)).toList(growable: false);

/// Erro de comunicação com a fonte de dados, já com mensagem em português.
class ErroFonte implements Exception {
  const ErroFonte(this.mensagem, {this.causa, this.status});

  final String mensagem;
  final Object? causa;
  final int? status;

  @override
  String toString() => mensagem;
}

/// A fonte exige sessão: a interface deve pedir login.
class ErroAutenticacao extends ErroFonte {
  const ErroAutenticacao(super.mensagem, {super.status = 401, super.causa});
}

/// A sessão existe, mas o papel do usuário não permite a operação.
class ErroPermissao extends ErroFonte {
  const ErroPermissao(super.mensagem, {super.status = 403, super.causa});
}
