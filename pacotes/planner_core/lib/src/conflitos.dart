/// Choques de horário entre atividades do mesmo dia.
///
/// Não é uma regra de negócio que impede algo: é um aviso derivado do plano.
/// Duas atividades podem se sobrepor (às vezes de propósito), então o conflito
/// é **calculado** e mostrado, nunca bloqueia salvar.
///
/// Regra, deliberadamente simples e previsível:
///
/// * **intervalo × intervalo** conflitam quando dividem tempo — `[06:00, 06:25)`
///   e `[06:10, 06:30)` se cruzam por 15 min;
/// * **intervalo × item pontual** ("Manutenção", 06:10, sem duração) conflitam
///   quando o instante cai dentro do intervalo. É o caso que motivou a feature:
///   06:00 com 25 min engole o compromisso das 06:10; com 10 min termina
///   exatamente nele e não há conflito;
/// * **dois itens pontuais** no mesmo horário não conflitam: não ocupam tempo;
/// * o intervalo é **semiaberto** (`[início, fim)`), mas o item pontual entra
///   também no início: estar em dois lugares às 06:00 é choque. Terminar 06:10 e
///   começar 06:10 não é — é encaixe, e o template depende disso.
library;

import 'horario.dart';
import 'modelos.dart';

/// Um par de atividades que se sobrepõe no tempo.
class Conflito {
  const Conflito({
    required this.primeira,
    required this.segunda,
    required this.minutos,
  });

  /// A que começa primeiro (empate: a com duração, depois a de menor id).
  final Atividade primeira;

  /// A outra ponta do choque.
  final Atividade segunda;

  /// Minutos que os dois ocupam em comum.
  ///
  /// `0` quando o choque é com um item pontual: o instante está dentro do
  /// intervalo, mas não há tempo compartilhado para medir.
  final int minutos;

  /// Texto curto para a etiqueta da linha, visto de [referencia].
  String descricaoPara(Atividade referencia) {
    final outra = outraDe(referencia);
    if (outra == null) return 'Conflito de horário';
    final detalhe = outra.duracaoMinutos == null ? outra.horario : outra.faixaComTermino;
    return 'Conflito com ${outra.titulo} ($detalhe)';
  }

  /// A outra ponta do conflito, vista de [referencia].
  Atividade? outraDe(Atividade referencia) {
    if (referencia.id == primeira.id) return segunda;
    if (referencia.id == segunda.id) return primeira;
    return null;
  }

  /// Trecho compartilhado, para leitura rápida.
  String get minutosTexto {
    if (minutos == 0) return 'horário ocupado';
    return minutos == 1 ? '1 minuto' : '$minutos minutos';
  }

  @override
  String toString() => 'Conflito(${primeira.id} × ${segunda.id}, $minutos min)';
}

/// Cálculo de sobreposições de um dia.
abstract final class Conflitos {
  /// Todos os pares que conflitam entre [atividades].
  ///
  /// Ordenado pelo início, para a leitura seguir a timeline.
  static List<Conflito> de(Iterable<Atividade> atividades) {
    final validas = [
      for (final a in atividades)
        if (Horario.minutos(a.horario) != null) a,
    ]..sort(_porInicio);

    final achados = <Conflito>[];
    for (var i = 0; i < validas.length; i++) {
      final a = validas[i];
      for (var j = i + 1; j < validas.length; j++) {
        final b = validas[j];
        final minutos = _sobreposicao(a, b);
        if (minutos != null) {
          achados.add(Conflito(primeira: a, segunda: b, minutos: minutos));
        }
      }
    }
    return achados;
  }

  /// Conflitos de um conjunto de atividades, indexados por id.
  ///
  /// Uma atividade pode aparecer em vários pares: o mapa guarda todos.
  static Map<String, List<Conflito>> porAtividade(Iterable<Atividade> atividades) {
    final mapa = <String, List<Conflito>>{};
    for (final conflito in de(atividades)) {
      mapa.putIfAbsent(conflito.primeira.id, () => []).add(conflito);
      mapa.putIfAbsent(conflito.segunda.id, () => []).add(conflito);
    }
    return mapa;
  }

  /// Conflitos de [referencia] contra [outras].
  ///
  /// Usado pelo editor: recebe a lista do dia e a atividade como está no
  /// formulário, então o aviso acompanha a digitação.
  static List<Conflito> deAtividade(
    Atividade referencia,
    Iterable<Atividade> outras,
  ) {
    if (Horario.minutos(referencia.horario) == null) return const [];
    final conflitos = <Conflito>[];

    for (final outra in outras) {
      if (outra.id == referencia.id) continue;
      if (Horario.minutos(outra.horario) == null) continue;
      final minutos = _sobreposicao(referencia, outra);
      if (minutos == null) continue;
      final referenciaPrimeiro = _porInicio(referencia, outra) <= 0;
      conflitos.add(
        Conflito(
          primeira: referenciaPrimeiro ? referencia : outra,
          segunda: referenciaPrimeiro ? outra : referencia,
          minutos: minutos,
        ),
      );
    }

    // Ordena pela **outra** atividade: no editor a referência é fixa, e o que
    // interessa é a ordem em que os vizinhos aparecem no dia.
    conflitos.sort(
      (a, b) => _porInicio(
        a.outraDe(referencia) ?? a.primeira,
        b.outraDe(referencia) ?? b.primeira,
      ),
    );
    return conflitos;
  }

  /// Minutos em comum, ou `null` quando não há conflito.
  ///
  /// Dois intervalos: o tamanho da interseção. Intervalo × pontual: `0` quando
  /// o instante está em `[início, fim)`. Dois pontuais: nunca.
  static int? _sobreposicao(Atividade a, Atividade b) {
    final inicioA = Horario.minutos(a.horario)!;
    final inicioB = Horario.minutos(b.horario)!;
    final faixaA = _faixa(a);
    final faixaB = _faixa(b);

    if (faixaA == null && faixaB == null) return null;
    if (faixaA == null) return _pontoEm(faixaB!, inicioA);
    if (faixaB == null) return _pontoEm(faixaA, inicioB);

    final inicio = faixaA.inicio > faixaB.inicio ? faixaA.inicio : faixaB.inicio;
    final fim = faixaA.fim < faixaB.fim ? faixaA.fim : faixaB.fim;
    return fim > inicio ? fim - inicio : null;
  }

  /// Um item pontual em [instante] colide com [faixa] quando cai no intervalo
  /// semiaberto `[início, fim)`.
  static int? _pontoEm(_Faixa faixa, int instante) =>
      instante >= faixa.inicio && instante < faixa.fim ? 0 : null;

  /// `[início, fim)` em minutos; `null` para item pontual (sem duração).
  static _Faixa? _faixa(Atividade a) {
    final inicio = Horario.minutos(a.horario);
    final duracao = a.duracaoMinutos;
    if (inicio == null || duracao == null || duracao <= 0) return null;
    return _Faixa(inicio, inicio + duracao);
  }

  static int _porInicio(Atividade a, Atividade b) {
    final porHora = a.minutosDoDia.compareTo(b.minutosDoDia);
    if (porHora != 0) return porHora;
    return a.id.compareTo(b.id);
  }
}

class _Faixa {
  const _Faixa(this.inicio, this.fim);

  final int inicio;
  final int fim;
}
