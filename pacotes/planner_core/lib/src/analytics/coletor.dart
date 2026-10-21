import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../modelos.dart';
import 'evento.dart';

/// Destino dos eventos analíticos.
///
/// A tela nunca fala com um serviço: entrega eventos a um [ColetorAnalytics].
/// Implementações **nunca lançam** — uma falha de telemetria não pode derrubar
/// a ação que a usuária pediu.
abstract interface class ColetorAnalytics {
  /// Nome curto do destino (ex.: `memória`, `HTTP`).
  String get descricao;

  void registrar(EventoAnalitico evento);

  void registrarVarios(Iterable<EventoAnalitico> eventos);

  /// Última falha observada, para diagnóstico.
  String? get ultimoErro;

  Future<void> encerrar();
}

/// Guarda eventos em memória, com limite de retenção. Destino padrão.
class ColetorMemoria implements ColetorAnalytics {
  ColetorMemoria({this.limite = 2000});

  final int limite;
  final List<EventoAnalitico> _eventos = [];
  String? _ultimoErro;

  /// Eventos registrados, do mais antigo para o mais recente.
  List<EventoAnalitico> get eventos => List.unmodifiable(_eventos);

  @override
  String get descricao => 'memória (${_eventos.length} eventos)';

  @override
  String? get ultimoErro => _ultimoErro;

  @override
  void registrar(EventoAnalitico evento) {
    try {
      _eventos.add(evento);
      if (_eventos.length > limite) _eventos.removeRange(0, _eventos.length - limite);
    } catch (erro) {
      _ultimoErro = 'Falha ao registrar evento: $erro';
    }
  }

  @override
  void registrarVarios(Iterable<EventoAnalitico> eventos) {
    for (final e in eventos) {
      registrar(e);
    }
  }

  @override
  Future<void> encerrar() async {}
}

/// Envia eventos em lotes para `POST /eventos`.
///
/// Contrato: `{"eventos": [Evento, ...]}`. Falha devolve o lote à fila: perder
/// telemetria por indisponibilidade momentânea seria pior do que reenviar.
class ColetorHttp implements ColetorAnalytics {
  ColetorHttp({
    required this.base,
    this.cabecalhos = const {},
    this.tamanhoLote = 20,
    this.intervalo = const Duration(seconds: 10),
    this.tempoLimite = const Duration(seconds: 15),
    http.Client? cliente,
  }) : _cliente = cliente ?? http.Client();

  final String base;
  final Map<String, String> cabecalhos;
  final int tamanhoLote;
  final Duration intervalo;
  final Duration tempoLimite;
  final http.Client _cliente;

  final List<EventoAnalitico> _fila = [];
  Timer? _agendador;
  String? _ultimoErro;
  bool _enviando = false;

  @override
  String get descricao => 'HTTP ($base)';

  @override
  String? get ultimoErro => _ultimoErro;

  @override
  void registrar(EventoAnalitico evento) {
    try {
      _fila.add(evento);
      if (_fila.length >= tamanhoLote) {
        unawaited(_enviar());
      } else {
        _agendar();
      }
    } catch (erro) {
      _ultimoErro = 'Falha ao enfileirar evento: $erro';
    }
  }

  @override
  void registrarVarios(Iterable<EventoAnalitico> eventos) {
    for (final e in eventos) {
      registrar(e);
    }
  }

  void _agendar() {
    _agendador?.cancel();
    _agendador = Timer(intervalo, () => unawaited(_enviar()));
  }

  /// Envia o lote pendente. Nunca lança.
  Future<void> _enviar() async {
    if (_enviando || _fila.isEmpty) return;
    _enviando = true;
    final lote = List<EventoAnalitico>.from(_fila);
    _fila.clear();
    try {
      final resposta = await _cliente
          .post(
            Uri.parse('$base/eventos'),
            headers: {'Content-Type': 'application/json; charset=utf-8', ...cabecalhos},
            body: jsonEncode({'eventos': [for (final e in lote) e.toJson()]}),
          )
          .timeout(tempoLimite);
      if (resposta.statusCode >= 400) throw ErroFonte('HTTP ${resposta.statusCode}');
      _ultimoErro = null;
    } catch (erro) {
      _fila.insertAll(0, lote);
      _ultimoErro = 'Falha ao enviar eventos: $erro';
      debugPrint('[analytics] $_ultimoErro');
      _agendar();
    } finally {
      _enviando = false;
    }
  }

  @override
  Future<void> encerrar() async {
    _agendador?.cancel();
    await _enviar();
    _cliente.close();
  }
}

/// Imprime no console de depuração.
class ColetorConsole implements ColetorAnalytics {
  ColetorConsole({void Function(String)? imprimir}) : imprimir = imprimir ?? debugPrint;

  final void Function(String) imprimir;
  String? _ultimoErro;

  @override
  String get descricao => 'console (depuração)';

  @override
  String? get ultimoErro => _ultimoErro;

  @override
  void registrar(EventoAnalitico evento) {
    try {
      imprimir('[analytics] ${evento.toJson()}');
    } catch (erro) {
      _ultimoErro = 'Falha ao imprimir evento: $erro';
    }
  }

  @override
  void registrarVarios(Iterable<EventoAnalitico> eventos) {
    for (final e in eventos) {
      registrar(e);
    }
  }

  @override
  Future<void> encerrar() async {}
}

/// Telemetria desligada.
class ColetorNulo implements ColetorAnalytics {
  const ColetorNulo();

  @override
  String get descricao => 'desligado';

  @override
  String? get ultimoErro => null;

  @override
  void registrar(EventoAnalitico evento) {}

  @override
  void registrarVarios(Iterable<EventoAnalitico> eventos) {}

  @override
  Future<void> encerrar() async {}
}

/// Encaminha cada evento para vários coletores (memória **e** HTTP, por ex.).
class ColetorComposto implements ColetorAnalytics {
  ColetorComposto(this.coletores);

  final List<ColetorAnalytics> coletores;

  @override
  String get descricao => coletores.map((c) => c.descricao).join(' + ');

  @override
  String? get ultimoErro {
    for (final c in coletores) {
      if (c.ultimoErro != null) return c.ultimoErro;
    }
    return null;
  }

  @override
  void registrar(EventoAnalitico evento) {
    for (final c in coletores) {
      c.registrar(evento);
    }
  }

  @override
  void registrarVarios(Iterable<EventoAnalitico> eventos) {
    final lista = eventos.toList(growable: false);
    for (final c in coletores) {
      c.registrarVarios(lista);
    }
  }

  @override
  Future<void> encerrar() async {
    for (final c in coletores) {
      await c.encerrar();
    }
  }
}
