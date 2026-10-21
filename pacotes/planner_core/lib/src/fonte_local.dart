import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'fonte_dados.dart';
import 'modelos.dart';

/// Armazenamento do estado no próprio aparelho.
///
/// É a fonte padrão: o planejador funciona sem conta e sem servidor, como o
/// arquivo HTML original — a diferença é que o dado sobrevive a limpar o
/// navegador, porque sai do `localStorage` e vai para o armazenamento do app.
///
/// O JSON guardado é pequeno (uma lista de IDs e os cômodos), então cada
/// marcação regrava alguns poucos kilobytes. Não há debounce: a gravação é
/// local e síncrona do ponto de vista do usuário.
class FonteLocal with GravacaoGranular implements FonteDeDados {
  FonteLocal({this.chave = 'minha-semana-v2', SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  /// Chave de armazenamento. O sufixo numérico é a versão do formato.
  final String chave;

  final SharedPreferencesAsync _prefs;
  EstadoSemana _estado = EstadoSemana.inicial();
  bool _carregado = false;

  @override
  String get descricao => 'Neste aparelho';

  @override
  bool get permiteEscrita => true;

  @override
  EstadoSemana get estadoAtual => _estado;

  @override
  set estadoAtual(EstadoSemana valor) => _estado = valor;

  /// A primeira escrita de uma sessão nova precisa ler o disco antes de
  /// compor: sem isso, marcar uma atividade apagaria o histórico do aparelho.
  @override
  Future<void> garantirCarregado() async {
    if (!_carregado) await carregar();
  }

  @override
  Future<EstadoSemana> carregar() async {
    try {
      final texto = await _prefs.getString(chave);
      if (texto == null || texto.isEmpty) {
        _estado = EstadoSemana.inicial();
      } else {
        final json = jsonDecode(texto);
        _estado = json is Map
            ? EstadoSemana.fromJson(json.cast<String, dynamic>())
            : EstadoSemana.inicial();
      }
      _carregado = true;
      return _estado;
    } on ErroFonte {
      rethrow;
    } catch (erro) {
      // Um JSON corrompido não pode impedir o app de abrir: começa limpo.
      _estado = EstadoSemana.inicial();
      _carregado = true;
      throw ErroFonte('Estado salvo ilegível; a semana foi reiniciada.', causa: erro);
    }
  }

  @override
  Future<EstadoSemana> salvar(EstadoSemana estado) async {
    try {
      await _prefs.setString(chave, jsonEncode(estado.toJson()));
      _estado = estado;
      return estado;
    } catch (erro) {
      throw ErroFonte('Não foi possível salvar no aparelho.', causa: erro);
    }
  }

  /// Apaga o estado guardado (usado nos testes e em "começar nova semana").
  Future<void> apagar() async {
    await _prefs.remove(chave);
    _estado = EstadoSemana.inicial();
    _carregado = true;
  }
}
