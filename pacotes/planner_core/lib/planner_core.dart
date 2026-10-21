/// Núcleo do Minha Semana.
///
/// Reúne o que a interface consome: o template da semana, o contrato de fonte de
/// dados, a fachada `Repositorio` e a telemetria. Nada aqui conhece uma tela.
///
/// Trocar a origem do estado (aparelho, memória, API) não exige mudar nenhuma
/// tela — basta implementar `FonteDeDados` e apontar
/// `--dart-define=PLANNER_FONTE`.
library;

export 'src/ambiente.dart';
export 'src/analytics/analise.dart';
export 'src/analytics/analytics.dart';
export 'src/analytics/coletor.dart';
export 'src/analytics/evento.dart';
export 'src/dados_semana.dart';
export 'src/fonte_dados.dart';
export 'src/fonte_http.dart';
export 'src/fonte_local.dart';
export 'src/fonte_memoria.dart';
export 'src/formatos.dart';
export 'src/modelos.dart';
export 'src/repositorio.dart';
export 'src/sessao.dart';
