import 'analytics/coletor.dart';
import 'fonte_dados.dart';
import 'fonte_http.dart';
import 'fonte_local.dart';
import 'fonte_memoria.dart';
import 'sessao.dart';

/// Configuração de ambiente do aplicativo.
///
/// Tudo vem de `--dart-define` em tempo de compilação; nada de segredo vai para
/// o bundle (o JavaScript publicado é público).
///
/// ```bash
/// # Demonstração: estado em memória
/// flutter build web --release --dart-define=PLANNER_FONTE=memoria
///
/// # Produção: Worker + Postgres
/// flutter build web --release \
///   --dart-define=PLANNER_FONTE=http \
///   --dart-define=PLANNER_API=/api
/// ```
abstract final class Ambiente {
  /// `local` (padrão), `memoria` ou `http`.
  static const fonte = String.fromEnvironment('PLANNER_FONTE', defaultValue: 'local');

  /// Raiz da API quando [fonte] é `http`. `/api` é o proxy de mesma origem.
  static const api = String.fromEnvironment('PLANNER_API', defaultValue: '');

  /// Token de serviço enviado em `Authorization`. Vazio no uso por pessoa: a
  /// sessão vai por cookie `HttpOnly`.
  static const token = String.fromEnvironment('PLANNER_TOKEN', defaultValue: '');

  /// Destino dos eventos: `memoria` (padrão), `http`, `console`, `nulo`.
  static const analytics = String.fromEnvironment('PLANNER_ANALYTICS', defaultValue: 'memoria');

  /// Raiz da API de eventos. Sem valor próprio, usa [api]: o endpoint vive no
  /// mesmo Worker, e exigir uma segunda variável só criava a chance de
  /// esquecer uma delas.
  static const apiEventos = String.fromEnvironment('PLANNER_API_EVENTOS', defaultValue: api);

  /// Endereço do app, exibido em textos de compartilhamento.
  static const site = String.fromEnvironment(
    'PLANNER_SITE',
    defaultValue: 'https://minhasemana.pages.dev',
  );

  /// Quanto tempo a sessão pode ficar parada antes de pedir login de novo.
  ///
  /// Encurtável por compilação para testar o aviso de inatividade sem esperar
  /// uma hora: `--dart-define=PLANNER_INATIVIDADE_SEGUNDOS=25`.
  static const inatividadeSegundos = int.fromEnvironment(
    'PLANNER_INATIVIDADE_SEGUNDOS',
    defaultValue: 3600,
  );

  /// A fonte exige login? Vale para qualquer fonte remota.
  static bool get exigeLogin => fonte == 'http';

  /// O estado vive só no aparelho (sem conta, sem servidor).
  static bool get somenteLocal => fonte == 'local' || fonte == 'memoria';

  /// Monta a fonte de dados conforme a configuração acima.
  static FonteDeDados criarFonte() {
    switch (fonte) {
      case 'http':
        if (api.isEmpty) {
          throw StateError(
            'PLANNER_FONTE=http exige PLANNER_API definido. '
            'Ex.: --dart-define=PLANNER_API=/api',
          );
        }
        return FonteHttp(base: api, cabecalhos: _cabecalhos);
      case 'memoria':
        return FonteMemoria();
      default:
        return FonteLocal();
    }
  }

  /// Monta o destino dos eventos.
  ///
  /// Quando `http` é pedido sem endereço, cai no coletor em memória em vez de
  /// falhar: telemetria não deve impedir o aplicativo de subir.
  static ColetorAnalytics criarColetor() {
    switch (analytics) {
      case 'http':
        if (apiEventos.isEmpty) return ColetorMemoria();
        return ColetorHttp(base: apiEventos, cabecalhos: _cabecalhos);
      case 'console':
        return ColetorConsole();
      case 'nulo':
        return const ColetorNulo();
      default:
        return ColetorMemoria();
    }
  }

  /// Cliente de sessão, quando há backend. `null` sem servidor.
  static SessaoApi? criarSessao() {
    if (!exigeLogin || api.isEmpty) return null;
    return SessaoApi(base: api);
  }

  static Map<String, String> get _cabecalhos =>
      token.isEmpty ? const {} : {'Authorization': 'Bearer $token'};
}
