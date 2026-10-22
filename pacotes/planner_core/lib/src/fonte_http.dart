import 'dart:convert';

import 'package:http/http.dart' as http;

import 'datas.dart';
import 'fonte_dados.dart';
import 'modelos.dart';

/// Fonte de dados servida por uma API REST.
///
/// Contrato esperado do backend:
///
/// | Método | Rota                       | Corpo                   |
/// |--------|----------------------------|-------------------------|
/// | GET    | `/semana`                  | —                       |
/// | PUT    | `/semana`                  | `EstadoSemana` (total)  |
/// | PUT    | `/atividades/:id`          | `{"concluida": bool}`   |
/// | DELETE | `/atividades`              | — (desmarca a semana)   |
/// | PUT    | `/comodos/:id`             | `Comodo`                |
/// | DELETE | `/comodos/:id`             | —                       |
///
/// Gravar por atividade, e não a semana inteira, é o que permite dois
/// aparelhos marcarem coisas diferentes sem um apagar o outro.
///
/// Sessão: o token de sessão nunca passa por Dart — no web ele vive num cookie
/// `HttpOnly` emitido por `POST /sessao`. [cabecalhos] serve para o token de
/// serviço, em chamadas máquina-a-máquina.
class FonteHttp implements FonteDeDados {
  FonteHttp({
    required this.base,
    this.cabecalhos = const {},
    this.tempoLimite = const Duration(seconds: 20),
    http.Client? cliente,
  }) : _cliente = cliente ?? http.Client();

  /// Raiz da API, sem barra final (ex.: `https://api.exemplo.app`).
  final String base;
  final Map<String, String> cabecalhos;
  final Duration tempoLimite;
  final http.Client _cliente;

  @override
  String get descricao => 'Nuvem ($base)';

  @override
  bool get permiteEscrita => true;

  @override
  bool get remota => true;

  Map<String, String> get _cabecalhosPadrao => {
    'Accept': 'application/json',
    'Content-Type': 'application/json; charset=utf-8',
    ...cabecalhos,
  };

  Uri _rota(String caminho) => Uri.parse('$base$caminho');

  /// Traduz o status HTTP em erro de domínio, para a interface reagir.
  Never _recusar(int status, String acao) {
    if (status == 401) {
      throw ErroAutenticacao('Sessão expirada ou não iniciada.', status: status);
    }
    if (status == 403) {
      throw ErroPermissao('Seu perfil não permite $acao.', status: status);
    }
    throw ErroFonte('A API recusou $acao ($status).', status: status);
  }

  @override
  Future<EstadoSemana> carregar() async {
    try {
      final resposta = await _cliente.get(_rota('/semana'), headers: _cabecalhosPadrao).timeout(tempoLimite);
      if (resposta.statusCode != 200) _recusar(resposta.statusCode, 'carregar a semana');
      final corpo = jsonDecode(utf8.decode(resposta.bodyBytes)) as Map<String, dynamic>;
      return EstadoSemana.fromJson(corpo);
    } on ErroFonte {
      rethrow;
    } catch (erro) {
      throw ErroFonte('Não foi possível carregar a semana da nuvem.', causa: erro);
    }
  }

  @override
  Future<EstadoSemana> salvar(EstadoSemana estado) async {
    try {
      final resposta = await _cliente
          .put(_rota('/semana'), headers: _cabecalhosPadrao, body: jsonEncode(estado.toJson()))
          .timeout(tempoLimite);
      if (resposta.statusCode != 200 && resposta.statusCode != 201) {
        _recusar(resposta.statusCode, 'gravar a semana');
      }
      if (resposta.bodyBytes.isEmpty) return estado;
      final corpo = jsonDecode(utf8.decode(resposta.bodyBytes)) as Map<String, dynamic>;
      return EstadoSemana.fromJson(corpo);
    } on ErroFonte {
      rethrow;
    } catch (erro) {
      throw ErroFonte('Não foi possível gravar a semana na nuvem.', causa: erro);
    }
  }

  Future<void> _enviar(String metodo, String caminho, Map<String, dynamic>? corpo) async {
    try {
      final uri = _rota(caminho);
      final resposta = metodo == 'DELETE'
          ? await _cliente.delete(uri, headers: _cabecalhosPadrao).timeout(tempoLimite)
          : await _cliente
                .put(uri, headers: _cabecalhosPadrao, body: corpo == null ? null : jsonEncode(corpo))
                .timeout(tempoLimite);
      if (resposta.statusCode >= 400 && resposta.statusCode != 404) {
        _recusar(resposta.statusCode, '$metodo $caminho');
      }
    } on ErroFonte {
      rethrow;
    } catch (erro) {
      throw ErroFonte('Falha ao gravar $caminho.', causa: erro);
    }
  }

  @override
  Future<void> definirConcluida(DateTime data, String id, {required bool concluida}) => _enviar(
    'PUT',
    '/atividades/${Datas.iso(data)}/${Uri.encodeComponent(id)}',
    {'concluida': concluida},
  );

  @override
  Future<void> salvarAtividade(Atividade atividade) => _enviar(
    'PUT',
    '/dias/${Uri.encodeComponent(atividade.dia)}/atividades/${Uri.encodeComponent(atividade.id)}',
    atividade.toJson(),
  );

  @override
  Future<void> removerAtividade(String dia, String id) => _enviar(
    'DELETE',
    '/dias/${Uri.encodeComponent(dia)}/atividades/${Uri.encodeComponent(id)}',
    null,
  );

  @override
  Future<void> limparMarcacoes(DateTime inicio) =>
      _enviar('DELETE', '/atividades?inicio=${Datas.iso(inicio)}', null);

  @override
  Future<void> salvarComodo(Comodo comodo) =>
      _enviar('PUT', '/comodos/${Uri.encodeComponent(comodo.id)}', comodo.toJson());

  @override
  Future<void> removerComodo(String id) => _enviar('DELETE', '/comodos/${Uri.encodeComponent(id)}', null);

  void encerrar() => _cliente.close();
}
