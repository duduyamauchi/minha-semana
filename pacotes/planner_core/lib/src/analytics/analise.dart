/// Funções puras sobre os eventos analíticos.
///
/// Não importa Flutter, não conhece HTTP e não conhece widget: recebe uma lista
/// de eventos e devolve agregados. O mesmo cálculo pode rodar no app, num teste
/// ou num backend Dart — e é isso que permite trocar o destino da telemetria
/// sem reescrever relatório nenhum.
library;

import 'evento.dart';

/// Série diária de eventos.
class PontoSerie {
  const PontoSerie(this.dia, this.quantidade);

  final String dia;
  final int quantidade;
}

/// Duração de uma sessão, do primeiro ao último evento.
class DuracaoSessao {
  const DuracaoSessao(this.sessao, this.segundos);

  final String sessao;
  final Duration segundos;
}

/// Agregados de um conjunto de eventos.
abstract final class Analise {
  /// Eventos por dia, do dia mais antigo ao mais recente, sem buracos.
  static List<PontoSerie> porDia(List<EventoAnalitico> eventos) {
    if (eventos.isEmpty) return const [];
    final contagem = <String, int>{};
    for (final e in eventos) {
      contagem.update(e.dia, (v) => v + 1, ifAbsent: () => 1);
    }
    final dias = contagem.keys.toList()..sort();
    final primeiro = DateTime.parse(dias.first);
    final ultimo = DateTime.parse(dias.last);
    final serie = <PontoSerie>[];
    for (var d = primeiro; !d.isAfter(ultimo); d = d.add(const Duration(days: 1))) {
      final chave =
          '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      serie.add(PontoSerie(chave, contagem[chave] ?? 0));
    }
    return serie;
  }

  /// Quantidade de eventos, ignorados os nomes em [ignorar].
  static int total(List<EventoAnalitico> eventos, {Set<String> ignorar = const {}}) =>
      eventos.where((e) => !ignorar.contains(e.nome)).length;

  /// Sessões distintas.
  static Set<String> sessoes(List<EventoAnalitico> eventos) => {for (final e in eventos) e.sessao};

  /// Duração média das sessões (intervalo entre o primeiro e o último evento).
  ///
  /// Sessões com um único evento entram com duração zero — é o que elas são.
  static Duration duracaoMedia(List<EventoAnalitico> eventos) {
    final porSessao = <String, List<DateTime>>{};
    for (final e in eventos) {
      porSessao.putIfAbsent(e.sessao, () => []).add(e.quando);
    }
    if (porSessao.isEmpty) return Duration.zero;
    var totalSegundos = 0;
    for (final datas in porSessao.values) {
      datas.sort();
      totalSegundos += datas.last.difference(datas.first).inSeconds;
    }
    return Duration(seconds: totalSegundos ~/ porSessao.length);
  }

  /// Contagem por nome de evento, do mais frequente ao menos frequente.
  static Map<String, int> porNome(List<EventoAnalitico> eventos) {
    final contagem = <String, int>{};
    for (final e in eventos) {
      contagem.update(e.nome, (v) => v + 1, ifAbsent: () => 1);
    }
    final entradas = contagem.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return {for (final e in entradas) e.key: e.value};
  }

  /// Soma de [EventoAnalitico.valor], ignorando os eventos sem valor.
  static num somarValores(List<EventoAnalitico> eventos) {
    num soma = 0;
    for (final e in eventos) {
      soma += e.valor ?? 0;
    }
    return soma;
  }

  /// Maior valor de [EventoAnalitico.valor]; `0` quando não há nenhum.
  ///
  /// Existe para que as telas não repitam `reduce((a, b) => a > b ? a : b)` —
  /// cálculo de apresentação é função pura e testável.
  static num maiorValor(List<EventoAnalitico> eventos) {
    num maior = 0;
    for (final e in eventos) {
      final v = e.valor;
      if (v != null && v > maior) maior = v;
    }
    return maior;
  }

  /// Porcentagem de [parte] sobre [todo], arredondada. `0` quando o todo é 0.
  static int percentual(num parte, num todo) => todo == 0 ? 0 : (parte / todo * 100).round();
}
