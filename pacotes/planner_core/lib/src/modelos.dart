/// Modelo do domínio do Minha Semana.
///
/// É Dart puro: não importa `flutter/material.dart` e não conhece HTTP, banco
/// nem widget. Tudo o que a tela precisa saber sobre a semana (quais
/// atividades existem, o que está marcado, quanto já foi feito) é calculado
/// aqui, e não dentro de `build`.
///
/// O plano **é dado do usuário**: cada atividade pode ser criada, editada e
/// removida, e o que se persiste é o plano inteiro (mais as marcações). O
/// template do HTML original é apenas o ponto de partida (`dados_semana.dart`).
library;

import 'datas.dart';
import 'horario.dart';

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

/// Uma entrada da timeline de um dia.
class Atividade {
  const Atividade({
    required this.id,
    required this.dia,
    required this.horario,
    required this.titulo,
    this.detalhe = '',
    this.duracaoMinutos,
    required this.categoria,
    this.fixo = false,
    this.prioridade = false,
  });

  /// Identificador estável e opaco: `seg-06:00` ou `seg-08:00-2`.
  ///
  /// O horário faz parte do id **de criação**, não da identidade: editar o
  /// horário mantém o id, então a marcação da atividade não se perde.
  final String id;

  /// Dia a que pertence (`seg`, `ter`, …).
  final String dia;

  /// Início no formato `HH:mm`.
  final String horario;

  final String titulo;

  /// Linha secundária; vazio quando a atividade não tem detalhe.
  final String detalhe;

  /// Duração em minutos. `null` para itens pontuais ("Acordar").
  final int? duracaoMinutos;

  final Categoria categoria;

  /// Compromisso com hora marcada (academia, pilates): não é negociável.
  final bool fixo;

  /// Bloco que ocupa a maior parte do dia (a reorganização da casa).
  final bool prioridade;

  bool get temDetalhe => detalhe.isNotEmpty;

  /// Horário de término, quando há duração.
  String? get termino =>
      duracaoMinutos == null ? null : Horario.somar(horario, duracaoMinutos);

  /// Duração em texto curto (`3h30`, `45 min`); vazio quando não há.
  String get duracaoTexto {
    final minutos = duracaoMinutos;
    if (minutos == null || minutos <= 0) return '';
    final h = minutos ~/ 60;
    final m = minutos % 60;
    if (h == 0) return '$m min';
    if (m == 0) return '${h}h';
    return '${h}h${m.toString().padLeft(2, '0')}';
  }

  /// Faixa exibida na linha: `06:00 · 45 min` ou só `06:00`.
  String get faixaHoraria {
    final duracao = duracaoTexto;
    return duracao.isEmpty ? horario : '$horario · $duracao';
  }

  /// Minutos desde a meia-noite, para ordenar; horário inválido vai para o fim.
  int get minutosDoDia => Horario.minutos(horario) ?? 24 * 60;

  Atividade copiarCom({
    String? dia,
    String? horario,
    String? titulo,
    String? detalhe,
    int? duracaoMinutos,
    bool limparDuracao = false,
    Categoria? categoria,
    bool? fixo,
    bool? prioridade,
  }) => Atividade(
    id: id,
    dia: dia ?? this.dia,
    horario: horario ?? this.horario,
    titulo: titulo ?? this.titulo,
    detalhe: detalhe ?? this.detalhe,
    duracaoMinutos: limparDuracao ? null : (duracaoMinutos ?? this.duracaoMinutos),
    categoria: categoria ?? this.categoria,
    fixo: fixo ?? this.fixo,
    prioridade: prioridade ?? this.prioridade,
  );

  static String chavear(String dia, String horario) => '$dia-$horario';

  Map<String, dynamic> toJson() => {
    'id': id,
    'dia': dia,
    'horario': horario,
    'titulo': titulo,
    if (detalhe.isNotEmpty) 'detalhe': detalhe,
    if (duracaoMinutos != null) 'duracaoMinutos': duracaoMinutos,
    'categoria': categoria.chave,
    'fixo': fixo,
    'prioridade': prioridade,
  };

  factory Atividade.fromJson(Map<String, dynamic> j) {
    final dia = (j['dia'] as String?) ?? _diaDoId(j['id'] as String?);
    final horario = Horario.normalizar(j['horario'] as String?) ?? '00:00';
    final duracao = (j['duracaoMinutos'] as num?)?.toInt();
    return Atividade(
      id: (j['id'] as String?) ?? chavear(dia, horario),
      dia: dia,
      horario: horario,
      titulo: (j['titulo'] as String?)?.trim().isNotEmpty == true
          ? (j['titulo'] as String).trim()
          : 'Sem título',
      detalhe: (j['detalhe'] as String?) ?? '',
      // Duração inválida (negativa, absurda) é descartada em vez de quebrar.
      duracaoMinutos: duracao == null || duracao <= 0 || duracao > 24 * 60 ? null : duracao,
      categoria: Categoria.de(j['categoria'] as String?),
      fixo: j['fixo'] == true,
      prioridade: j['prioridade'] == true,
    );
  }

  /// Dia deduzido de um id antigo (`seg-06:00`), para planos na versão 2.
  static String _diaDoId(String? id) {
    final texto = id ?? '';
    final i = texto.indexOf('-');
    return i <= 0 ? 'seg' : texto.substring(0, i);
  }

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

  /// Chaves válidas, na ordem da semana.
  static const chavesValidas = ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'];

  /// Verdadeiro quando [chave] identifica um dia da semana conhecido.
  ///
  /// O plano é editável nas atividades, não na estrutura: um dia inventado
  /// viraria uma aba fantasma sem lugar na semana.
  static bool chaveValida(String chave) => chavesValidas.contains(chave);

  /// Nomes canônicos por chave.
  ///
  /// A API persiste só a chave e as atividades: nome e nota são apresentação.
  /// Deixá-los no banco faria a mesma semana ter dois textos possíveis, e um
  /// plano vindo do servidor apareceria como "qua" em vez de "Quarta".
  static const nomes = {
    'seg': 'Segunda',
    'ter': 'Terça',
    'qua': 'Quarta',
    'qui': 'Quinta',
    'sex': 'Sexta',
    'sab': 'Sábado',
    'dom': 'Domingo',
  };

  /// Notas padrão por dia, na ausência de uma nota gravada.
  static const notas = {
    'seg': 'Dia inteiro de reorganização',
    'ter': 'Reorganização entre academia e pilates',
    'qua': 'Dia inteiro de reorganização',
    'qui': 'Reorganização entre academia e pilates',
    'sex': 'Academia e tarde longa de reorganização',
    'sab': 'Limpeza completa e reorganização',
    'dom': 'Reorganização de manhã, recarga à tarde',
  };

  /// Nome por extenso de uma chave (`qua` → `Quarta`).
  static String nomeDe(String chave) => nomes[chave] ?? chave;

  /// Nota padrão de uma chave.
  static String notaDe(String chave) => notas[chave] ?? '';

  /// Nome garantido: usa o canônico quando o dado veio sem nome.
  String get nomeExibido => nome.trim().isEmpty || nome == chave ? nomeDe(chave) : nome;

  /// `Seg`, `Ter`, … como nas abas do planejador.
  String get nomeCurto {
    final base = nomeExibido;
    return base.length <= 3 ? base : base.substring(0, 3);
  }

  bool get ehFimDeSemana => chave == 'sab' || chave == 'dom';

  Atividade? atividade(String id) {
    for (final a in atividades) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Atividades em ordem de horário; empate preserva a ordem de criação.
  List<Atividade> get ordenadas {
    final lista = [...atividades];
    // `sort` não é estável em Dart, então o índice entra como desempate.
    final posicao = {for (var i = 0; i < lista.length; i++) lista[i].id: i};
    lista.sort((a, b) {
      final porHora = a.minutosDoDia.compareTo(b.minutosDoDia);
      return porHora != 0 ? porHora : posicao[a.id]!.compareTo(posicao[b.id]!);
    });
    return lista;
  }

  Dia copiarCom({String? nome, String? nota, List<Atividade>? atividades}) => Dia(
    chave: chave,
    nome: nome ?? this.nome,
    nota: nota ?? this.nota,
    atividades: atividades ?? this.atividades,
  );

  Map<String, dynamic> toJson() => {
    'chave': chave,
    'nome': nome,
    'nota': nota,
    'atividades': [for (final a in atividades) a.toJson()],
  };

  factory Dia.fromJson(Map<String, dynamic> j) {
    final chave = (j['chave'] as String?) ?? 'seg';
    final atividades = <Atividade>[];
    final vistos = <String>{};
    for (final a in (j['atividades'] as List? ?? const [])) {
      if (a is! Map) continue;
      final atividade = Atividade.fromJson(a.cast<String, dynamic>());
      // Ids repetidos dentro do dia quebrariam a marcação: descarta o duplicado.
      if (!vistos.add(atividade.id)) continue;
      atividades.add(atividade.id.startsWith('$chave-') ? atividade : atividade.copiarCom(dia: chave));
    }
    final nome = (j['nome'] as String?)?.trim() ?? '';
    final nota = (j['nota'] as String?)?.trim() ?? '';
    return Dia(
      chave: chave,
      // Plano vindo de uma API que só manda a chave: nome e nota vêm do
      // canônico, senão a aba mostraria "qua" e perderia o resumo do dia.
      nome: nome.isEmpty ? Dia.nomeDe(chave) : nome,
      nota: nota.isEmpty ? Dia.notaDe(chave) : nota,
      atividades: atividades,
    );
  }
}

/// O plano semanal do usuário, com o que já foi feito.
///
/// Duas dimensões, de propósito:
///
/// * [dias] é o **template** da semana (`seg`…`dom`) — a rotina que se repete;
/// * [concluidas] é o que foi feito **por data** (`2026-10-21` → ids), porque
///   cada quarta é uma quarta diferente mesmo compartilhando a rotina.
///
/// Essa separação é o que permite navegar por semanas com o mesmo plano sem
/// duplicar atividades: mudar de semana muda o mapa de marcações consultado,
/// não o template.
class Semana {
  const Semana({
    required this.dias,
    required this.concluidas,
    required this.comodos,
  });

  final List<Dia> dias;

  /// IDs das atividades concluídas, **por data** (`yyyy-MM-dd`).
  ///
  /// Ler sempre por [concluidasEm]; o mapa direto só existe para serialização.
  final Map<String, Set<String>> concluidas;

  final List<Comodo> comodos;

  /// Total de atividades do template, base do percentual.
  int get totalAtividades => dias.fold(0, (soma, d) => soma + d.atividades.length);

  /// IDs concluídos numa data.
  Set<String> concluidasEm(DateTime data) => concluidas[Datas.iso(data)] ?? const {};

  /// Quantas atividades do dia [chave] foram feitas na [data].
  int feitasEm(DateTime data, String chave) {
    final dia = this.dia(chave);
    if (dia == null) return 0;
    final feitas = concluidasEm(data);
    return dia.atividades.where((a) => feitas.contains(a.id)).length;
  }

  /// Verdadeiro quando a atividade está marcada naquela data.
  bool concluidaEm(DateTime data, Atividade atividade) =>
      concluidasEm(data).contains(atividade.id);

  bool comodoConcluido(Comodo comodo) => comodo.concluido;

  Dia? dia(String chave) {
    for (final d in dias) {
      if (d.chave == chave) return d;
    }
    return null;
  }

  /// Índice do dia de hoje (segunda = 0, domingo = 6).
  static int indiceDeHoje([DateTime? agora]) =>
      Datas.indiceNaSemana(agora ?? DateTime.now());

  /// Chave do dia da semana para uma data (segunda = 0).
  static String chaveDe([DateTime? agora]) => Dia.chavesValidas[indiceDeHoje(agora)];

  /// Chave do dia de uma data específica.
  static String chaveDaData(DateTime data) => Dia.chavesValidas[Datas.indiceNaSemana(data)];

  // ---------------------------------------------------------------------------
  // Edição do plano (template)
  //
  // Todas devolvem uma nova `Semana`: quem chama decide quando publicar.
  // ---------------------------------------------------------------------------

  /// Id livre para uma atividade nova naquele dia e horário.
  ///
  /// Preferir `dia-HH:mm` mantém os ids legíveis; quando já existe, ganha um
  /// sufixo numérico. Nunca reaproveita id de outra atividade — nem de uma
  /// marcação antiga, que voltaria a parecer concluída.
  String idLivre(String chaveDia, String horario) {
    final existentes = {
      for (final d in dias)
        for (final a in d.atividades) a.id,
      for (final ids in concluidas.values) ...ids,
    };
    final base = Atividade.chavear(chaveDia, horario);
    if (!existentes.contains(base)) return base;
    for (var i = 2; i < 1000; i++) {
      final candidato = '$base-$i';
      if (!existentes.contains(candidato)) return candidato;
    }
    // Sem vaga legível, cai num id opaco: nunca deve acontecer no uso normal.
    return '$base-${DateTime.now().microsecondsSinceEpoch}';
  }

  /// Atividade nova no dia de [referencia] — o id e o `dia` são preenchidos.
  Atividade novaAtividade(
    Atividade referencia, {
    String? horario,
    String? titulo,
    String? detalhe,
    int? duracaoMinutos,
    Categoria? categoria,
  }) {
    final chave = referencia.dia;
    final inicio = Horario.normalizar(horario ?? referencia.horario) ?? '08:00';
    return Atividade(
      id: idLivre(chave, inicio),
      dia: chave,
      horario: inicio,
      // Rascunho nasce sem título: o campo do editor deve começar vazio, e o
      // repositório recusa gravar sem nome.
      titulo: titulo ?? '',
      detalhe: detalhe ?? '',
      duracaoMinutos: duracaoMinutos,
      categoria: categoria ?? Categoria.casa,
    );
  }

  /// Insere ou substitui uma atividade pelo id, no dia indicado.
  Semana salvarAtividade(Atividade atividade) {
    final chave = atividade.dia;
    final alvo = dia(chave);
    if (alvo == null) return this;
    final existe = alvo.atividades.any((a) => a.id == atividade.id);
    final atividades = existe
        ? [for (final a in alvo.atividades) if (a.id == atividade.id) atividade else a]
        : [...alvo.atividades, atividade];
    return copiarCom(
      dias: [
        for (final d in dias)
          if (d.chave == chave) d.copiarCom(atividades: atividades) else d,
      ],
    );
  }

  /// Remove uma atividade do template e todas as marcações dela.
  ///
  /// A marcação órfã inflaria o percentual de semanas passadas com um id que
  /// não existe mais, então sai junto.
  Semana removerAtividade(String chaveDia, String id) {
    final alvo = dia(chaveDia);
    if (alvo == null || !alvo.atividades.any((a) => a.id == id)) return this;
    return copiarCom(
      dias: [
        for (final d in dias)
          if (d.chave == chaveDia)
            d.copiarCom(atividades: [for (final a in d.atividades) if (a.id != id) a])
          else
            d,
      ],
      concluidas: {
        for (final e in concluidas.entries)
          if (e.value.contains(id)) e.key: {...e.value}..remove(id) else e.key: e.value,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Marcações por data
  // ---------------------------------------------------------------------------

  /// Marca ou desmarca uma atividade numa data.
  Semana definirConcluida(DateTime data, String id, {required bool concluida}) {
    final chave = Datas.iso(data);
    final atual = Set<String>.of(concluidasEm(data));
    if (concluida) {
      atual.add(id);
    } else {
      atual.remove(id);
    }
    final mapa = {
      for (final e in concluidas.entries)
        if (e.key != chave) e.key: e.value,
      if (atual.isNotEmpty) chave: atual,
    };
    return copiarCom(concluidas: mapa);
  }

  /// Desmarca a semana inteira de [inicio] a [fim] (datas inclusivas).
  Semana limparIntervalo(DateTime inicio, {int dias = 7}) {
    final alvo = {
      for (var i = 0; i < dias; i++) Datas.iso(Datas.somarDias(inicio, i)),
    };
    return copiarCom(
      concluidas: {
        for (final e in concluidas.entries)
          if (!alvo.contains(e.key)) e.key: e.value,
      },
    );
  }

  Semana copiarCom({
    List<Dia>? dias,
    Map<String, Set<String>>? concluidas,
    List<Comodo>? comodos,
  }) => Semana(
    dias: dias ?? this.dias,
    concluidas: concluidas ?? this.concluidas,
    comodos: comodos ?? this.comodos,
  );

  /// Esta semana com outro estado, mantendo o template.
  Semana comEstado(EstadoSemana novo) => Semana(
    dias: novo.dias ?? dias,
    concluidas: novo.concluidas,
    comodos: novo.comodos,
  );

  /// O que efetivamente se persiste: o template, as marcações e os cômodos.
  EstadoSemana get estado =>
      EstadoSemana(dias: dias, concluidas: concluidas, comodos: comodos);

  Map<String, dynamic> toJson() => estado.toJson();

  /// Reconstrói o plano a partir do JSON.
  ///
  /// Sem template no estado (formatos v2/v3), usa o do app como ponto de
  /// partida — é a migração do que já estava salvo no aparelho ou no banco.
  factory Semana.doJson(Map<String, dynamic> j, {required List<Dia> base}) {
    final estado = EstadoSemana.fromJson(j);
    return Semana(
      dias: estado.dias ?? base,
      concluidas: estado.concluidas,
      comodos: estado.comodos,
    );
  }
}

/// A semana de uma data, pronta para a tela.
///
/// Cruza o template com as marcações daquela semana. Nada é copiado: os dias
/// apontam para o mesmo template, então editar uma atividade vale para todas as
/// semanas, sem "propagar" nada.
class Agenda {
  const Agenda({
    required this.semana,
    required this.inicio,
    required this.selecionado,
  });

  final Semana semana;

  /// Segunda-feira da semana.
  final DateTime inicio;

  /// Data aberta na timeline (sempre dentro da semana).
  final DateTime selecionado;

  List<DateTime> get datas => [for (var i = 0; i < 7; i++) Datas.somarDias(inicio, i)];

  DateTime get fim => Datas.somarDias(inicio, 6);

  /// Dia do template correspondente à data.
  Dia diaDaData(DateTime data) {
    final chave = Semana.chaveDaData(data);
    return semana.dia(chave) ??
        Dia(chave: chave, nome: Dia.nomeDe(chave), nota: Dia.notaDe(chave), atividades: const []);
  }

  String chaveDoSelecionado() => Semana.chaveDaData(selecionado);

  Dia get diaSelecionado => diaDaData(selecionado);

  int totalEm(DateTime data) => diaDaData(data).atividades.length;

  int feitasEm(DateTime data) => semana.feitasEm(data, Semana.chaveDaData(data));

  /// Fração feita na data (0..1).
  double progressoEm(DateTime data) {
    final total = totalEm(data);
    return total == 0 ? 0 : feitasEm(data) / total;
  }

  /// Percentual da data, arredondado.
  int percentualEm(DateTime data) => (progressoEm(data) * 100).round();

  int get totalDaSemana => datas.fold(0, (s, d) => s + totalEm(d));

  int get feitasNaSemana => datas.fold(0, (s, d) => s + feitasEm(d));

  double get progressoDaSemana {
    final total = totalDaSemana;
    return total == 0 ? 0 : feitasNaSemana / total;
  }

  int get percentualDaSemana => (progressoDaSemana * 100).round();

  /// Número da semana ISO (para exibir "semana 43").
  int get numeroDaSemana {
    // ISO-8601: a semana 1 é a que contém a primeira quinta-feira do ano.
    final quinta = Datas.somarDias(inicio, 3);
    final primeiroDia = DateTime(quinta.year, 1, 1);
    final dias = quinta.difference(primeiroDia).inDays;
    return (dias / 7).floor() + 1;
  }

  /// Cópia com outro dia selecionado (dentro ou fora da semana).
  Agenda comSelecionado(DateTime data) {
    final d = Datas.dia(data);
    return Agenda(
      semana: semana,
      inicio: Datas.segundaDe(d),
      selecionado: d,
    );
  }

  static Agenda de(Semana semana, DateTime data) {
    final d = Datas.dia(data);
    return Agenda(semana: semana, inicio: Datas.segundaDe(d), selecionado: d);
  }
}

/// Fotografia persistida: template, marcações por data e cômodos.
class EstadoSemana {
  const EstadoSemana({
    required this.concluidas,
    required this.comodos,
    this.dias,
  });

  /// Data (`yyyy-MM-dd`) → ids concluídos naquele dia.
  final Map<String, Set<String>> concluidas;

  final List<Comodo> comodos;

  /// Template do usuário. `null` significa "use o do app".
  final List<Dia>? dias;

  /// Versão do formato gravado.
  ///
  /// v2: marcações sem data e cômodos. v3: acrescenta o template.
  /// v4: marcações **por data** — é o que permite semanas no calendário.
  static const versaoFormato = 4;

  EstadoSemana comTemplate(List<Dia> plano) =>
      EstadoSemana(concluidas: concluidas, comodos: comodos, dias: plano);

  Map<String, dynamic> toJson() => {
    'versao': versaoFormato,
    'concluidas': {
      for (final chave in concluidas.keys.toList()..sort())
        if (concluidas[chave]!.isNotEmpty) chave: concluidas[chave]!.toList()..sort(),
    },
    'comodos': [for (final c in comodos) c.toJson()],
    if (dias != null) 'dias': [for (final d in dias!) d.toJson()],
  };

  /// Campos ausentes ou inválidos não quebram a leitura: entradas ruins são
  /// descartadas, o resto do estado continua válido.
  factory EstadoSemana.fromJson(Map<String, dynamic> j) {
    final concluidas = <String, Set<String>>{};
    final bruto = j['concluidas'];
    if (bruto is Map) {
      for (final e in bruto.entries) {
        final data = Datas.deIso(e.key.toString());
        if (data == null) continue;
        final ids = {
          for (final id in (e.value is List ? e.value as List : const []))
            if (id is String && id.isNotEmpty) id,
        };
        if (ids.isNotEmpty) concluidas[Datas.iso(data)] = ids;
      }
    }

    // Formato antigo: `marcadas` era uma lista sem data. Ela não pode ser
    // atribuída a nenhum dia sem inventar informação, então é descartada — as
    // semanas começam zeradas e o template é preservado.
    final comodos = <Comodo>[];
    final vistos = <String>{};
    for (final c in (j['comodos'] as List? ?? const [])) {
      if (c is! Map) continue;
      final comodo = Comodo.fromJson(c.cast<String, dynamic>());
      if (comodo.nome.isEmpty || !vistos.add(comodo.id)) continue;
      comodos.add(comodo);
    }

    List<Dia>? plano;
    final dias = j['dias'];
    if (dias is List && dias.isNotEmpty) {
      final lidos = <Dia>[];
      final chaves = <String>{};
      for (final d in dias) {
        if (d is! Map) continue;
        final dia = Dia.fromJson(d.cast<String, dynamic>());
        if (!Dia.chaveValida(dia.chave) || !chaves.add(dia.chave)) continue;
        lidos.add(dia);
      }
      if (lidos.isNotEmpty) plano = lidos;
    }

    return EstadoSemana(
      concluidas: concluidas,
      comodos: comodos.isEmpty ? comodosPadrao() : comodos,
      dias: plano,
    );
  }

  static EstadoSemana inicial() =>
      EstadoSemana(concluidas: const {}, comodos: comodosPadrao());
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
