import 'modelos.dart';

/// Contrato de qualquer origem de dados do aplicativo.
///
/// O app inteiro conhece só esta interface. Trocar `local` (o padrão, estado no
/// próprio aparelho) por `http` (Worker + Postgres) é trocar uma implementação
/// — nenhuma tela muda.
///
/// A gravação é **por entidade** (`definirAtividade`, `salvarComodo`), não
/// "salvar a semana inteira". Dois aparelhos marcando atividades diferentes não
/// se sobrescrevem; `salvar` existe como fallback para carga em lote e para
/// fontes que não suportam escrita granular.
abstract interface class FonteDeDados {
  /// Nome curto exibido na tela de ajustes (ex.: `Neste aparelho`, `API`).
  String get descricao;

  /// Indica se a fonte aceita alterações.
  bool get permiteEscrita;

  /// Indica se o estado vive fora do aparelho (servidor).
  ///
  /// A tela usa isto para dizer se o plano está "na nuvem" ou "neste aparelho";
  /// a fonte é quem sabe, não a tela.
  bool get remota;

  /// Lê o estado atual. Deve lançar [ErroFonte] em caso de falha.
  Future<EstadoSemana> carregar();

  /// Persiste o estado completo e devolve o que foi efetivamente gravado.
  ///
  /// Usado na primeira gravação e na importação de um backup. **Não** é o
  /// caminho do dia a dia: para marcar uma atividade, use [definirAtividade].
  Future<EstadoSemana> salvar(EstadoSemana estado);

  /// Marca ou desmarca uma atividade (`seg-06:00`).
  Future<void> definirAtividade(String id, {required bool concluida});

  /// Desmarca a semana inteira, preservando os cômodos.
  Future<void> limparMarcacoes();

  /// Insere ou atualiza um cômodo, identificado por [Comodo.id].
  Future<void> salvarComodo(Comodo comodo);

  /// Remove um cômodo.
  Future<void> removerComodo(String id);
}

/// Comportamento padrão para fontes sem gravação granular.
///
/// Aplica a mudança sobre o estado conhecido e delega para [salvar]. Serve para
/// `FonteMemoria`, `FonteLocal` e qualquer fonte de teste. Uma fonte real
/// (Postgres por trás de uma API) sobrescreve os métodos para tocar só o
/// registro afetado.
mixin GravacaoGranular implements FonteDeDados {
  /// Fontes com gravação granular local guardam o estado no aparelho ou em
  /// memória; `FonteHttp` sobrescreve para `true`.
  @override
  bool get remota => false;

  /// Estado atualmente conhecido pela fonte.
  EstadoSemana get estadoAtual;

  /// Substitui o estado conhecido após a gravação.
  set estadoAtual(EstadoSemana valor);

  /// Garante que [estadoAtual] reflete o que já está gravado, antes de compor
  /// uma alteração sobre ele.
  ///
  /// Uma fonte que começa vazia não precisa fazer nada; `FonteLocal` precisa
  /// carregar, senão a primeira marcação de uma sessão nova sobrescreveria o
  /// que o aparelho já tinha.
  Future<void> garantirCarregado() async {}

  /// Aplica a transformação sobre o estado conhecido e devolve o resultado.
  Future<void> _compor(EstadoSemana Function(EstadoSemana atual) transformacao) async {
    await garantirCarregado();
    estadoAtual = await salvar(transformacao(estadoAtual));
  }

  @override
  Future<void> definirAtividade(String id, {required bool concluida}) => _compor((atual) {
    final marcadas = Set<String>.of(atual.marcadas);
    if (concluida) {
      marcadas.add(id);
    } else {
      marcadas.remove(id);
    }
    return EstadoSemana(marcadas: marcadas, comodos: atual.comodos);
  });

  @override
  Future<void> limparMarcacoes() => _compor(
    (atual) => EstadoSemana(marcadas: const {}, comodos: atual.comodos),
  );

  @override
  Future<void> salvarComodo(Comodo comodo) => _compor((atual) {
    final existe = atual.comodos.any((c) => c.id == comodo.id);
    return EstadoSemana(
      marcadas: atual.marcadas,
      comodos: existe
          ? [for (final c in atual.comodos) if (c.id == comodo.id) comodo else c]
          : [...atual.comodos, comodo],
    );
  });

  @override
  Future<void> removerComodo(String id) => _compor(
    (atual) => EstadoSemana(
      marcadas: atual.marcadas,
      comodos: [for (final c in atual.comodos) if (c.id != id) c],
    ),
  );
}
