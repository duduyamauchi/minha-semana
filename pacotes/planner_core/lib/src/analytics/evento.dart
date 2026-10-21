/// Modelo de evento analítico.
///
/// Deliberadamente genérico: `nome` é texto livre e o que é específico vai em
/// [propriedades]. Instrumentar um domínio novo (pagamento, funil) não exige
/// migração de esquema.
library;

/// Um evento registrado por qualquer ponto do sistema.
class EventoAnalitico {
  const EventoAnalitico({
    required this.nome,
    required this.quando,
    required this.sessao,
    this.usuario,
    this.tela,
    this.propriedades = const {},
    this.valor,
    this.entidade,
    this.entidadeId,
  });

  /// Identificador do acontecimento, em `snake_case` (ex.: `atividade_marcada`).
  final String nome;

  /// Momento em que ocorreu (UTC no transporte, local na exibição).
  final DateTime quando;

  /// Identificador da sessão de uso.
  final String sessao;

  /// Usuário logado, quando conhecido.
  final String? usuario;

  /// Tela em que o evento ocorreu.
  final String? tela;

  /// Dados específicos do evento.
  final Map<String, Object?> propriedades;

  /// Medida numérica: minutos, quantidade, preço.
  final num? valor;

  /// Tipo da entidade afetada (`atividade`, `comodo`).
  final String? entidade;

  /// Identificador da entidade afetada.
  final String? entidadeId;

  /// Chave de agrupamento por dia (`2026-10-16`).
  String get dia =>
      '${quando.year.toString().padLeft(4, '0')}-'
      '${quando.month.toString().padLeft(2, '0')}-'
      '${quando.day.toString().padLeft(2, '0')}';

  factory EventoAnalitico.fromJson(Map<String, dynamic> j) => EventoAnalitico(
    nome: j['nome'] as String? ?? 'desconhecido',
    quando: _data(j['quando']),
    sessao: j['sessao'] as String? ?? 'sem-sessao',
    usuario: j['usuario'] as String?,
    tela: j['tela'] as String?,
    propriedades: {
      for (final e in ((j['propriedades'] as Map?) ?? const {}).entries) e.key.toString(): e.value,
    },
    valor: j['valor'] as num?,
    entidade: j['entidade'] as String?,
    entidadeId: j['entidadeId'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'nome': nome,
    'quando': quando.toUtc().toIso8601String(),
    'sessao': sessao,
    if (usuario != null) 'usuario': usuario,
    if (tela != null) 'tela': tela,
    if (propriedades.isNotEmpty) 'propriedades': propriedades,
    if (valor != null) 'valor': valor,
    if (entidade != null) 'entidade': entidade,
    if (entidadeId != null) 'entidadeId': entidadeId,
  };

  static DateTime _data(Object? valor) {
    if (valor is DateTime) return valor;
    if (valor is String) {
      final lido = DateTime.tryParse(valor);
      if (lido != null) return lido.toLocal();
    }
    return DateTime.now();
  }

  @override
  String toString() => 'EventoAnalitico($nome em $quando)';
}
