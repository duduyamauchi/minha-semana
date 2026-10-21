import 'fonte_dados.dart';
import 'modelos.dart';

/// Fonte de demonstração: guarda o estado na memória do processo.
///
/// Duas consequências, propositais: recarregar a página volta ao começo e dois
/// aparelhos não compartilham nada. É a fonte dos testes e do modo offline.
class FonteMemoria with GravacaoGranular implements FonteDeDados {
  FonteMemoria([EstadoSemana? inicial]) : _estado = inicial ?? EstadoSemana.inicial();

  EstadoSemana _estado;

  @override
  String get descricao => 'Memória (demonstração)';

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
    _estado = estado;
    return estado;
  }
}
