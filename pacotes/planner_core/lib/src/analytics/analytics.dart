import 'dart:async';

import 'package:flutter/foundation.dart';

import 'coletor.dart';
import 'evento.dart';

/// Fachada de telemetria usada pela interface.
///
/// Centraliza sessão, tela atual e usuário, de modo que quem instrumenta só
/// precise dizer **o que aconteceu**:
///
/// ```dart
/// analytics.registrar('atividade_marcada', entidade: 'atividade', entidadeId: id);
/// ```
///
/// O envio é sempre "dispare e esqueça": nenhuma chamada lança.
class Analytics extends ChangeNotifier {
  Analytics(this.coletor, {this.usuario, String? sessao}) : sessao = sessao ?? _novaSessao();

  final ColetorAnalytics coletor;

  /// Identificador da sessão atual, usado em funil e retenção.
  final String sessao;

  String? usuario;
  String? tela;

  final List<EventoAnalitico> _recentes = [];
  static const _maxRecentes = 200;

  /// Eventos registrados nesta sessão (diagnóstico e testes).
  List<EventoAnalitico> get recentes => List.unmodifiable(_recentes);

  String get descricaoColetor => coletor.descricao;
  String? get ultimoErro => coletor.ultimoErro;

  static String _novaSessao() => 'ses-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  /// Registra um evento. Nunca lança.
  EventoAnalitico registrar(
    String nome, {
    Map<String, Object?> propriedades = const {},
    num? valor,
    String? entidade,
    String? entidadeId,
    String? tela,
    String? usuario,
    DateTime? quando,
  }) {
    final evento = EventoAnalitico(
      nome: nome,
      quando: quando ?? DateTime.now(),
      sessao: sessao,
      usuario: usuario ?? this.usuario,
      tela: tela ?? this.tela,
      propriedades: propriedades,
      valor: valor,
      entidade: entidade,
      entidadeId: entidadeId,
    );
    try {
      coletor.registrar(evento);
      _recentes.add(evento);
      if (_recentes.length > _maxRecentes) _recentes.removeRange(0, _recentes.length - _maxRecentes);
      notifyListeners();
    } catch (erro) {
      debugPrint('[analytics] evento "$nome" descartado: $erro');
    }
    return evento;
  }

  /// Marca a troca de tela e registra a visita.
  void visitar(String rota, {Map<String, Object?> propriedades = const {}}) {
    tela = rota;
    registrar('tela_visualizada', propriedades: {'rota': rota, ...propriedades});
  }

  /// Identifica a usuária e registra o evento de sessão iniciada.
  void identificar(String usuario, {Map<String, Object?> propriedades = const {}}) {
    this.usuario = usuario;
    registrar('usuario_identificado', propriedades: {'usuario': usuario, ...propriedades});
  }

  /// Erro observado, com contexto para investigação.
  void erro(String origem, String mensagem, {Map<String, Object?> propriedades = const {}}) =>
      registrar('erro', propriedades: {'origem': origem, 'mensagem': mensagem, ...propriedades});

  /// Exporta os eventos da sessão em JSON, no formato do coletor HTTP.
  Map<String, dynamic> exportarJson() => {
    'sessao': sessao,
    if (usuario != null) 'usuario': usuario,
    'eventos': [for (final e in _recentes) e.toJson()],
  };

  @override
  void dispose() {
    unawaited(coletor.encerrar());
    super.dispose();
  }
}
