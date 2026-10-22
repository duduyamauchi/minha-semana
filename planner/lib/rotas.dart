import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:planner_core/planner_core.dart';

import 'core/escopo.dart';
import 'telas/acesso.dart';
import 'telas/ajustes.dart';
import 'telas/calendario.dart';
import 'telas/semana.dart';

/// Rotas do aplicativo.
///
/// `usePathUrlStrategy` é chamado em `main.dart`: sem ele, `/dia/qua` abriria a
/// tela inicial, porque tudo depois do `#` é ignorado pelo roteador.
///
/// O redirecionamento de autenticação escuta [sessao]: quando ela muda, o
/// roteador reavalia a rota em vez de esperar a próxima navegação. Sem isso, um
/// logout deixava a tela de semana visível até o próximo toque.
class Rotas {
  Rotas({
    required this.repositorio,
    required this.exigeLogin,
    required this.sessao,
    required this.aoEntrar,
    required this.aoSair,
  });

  final Repositorio repositorio;
  final bool exigeLogin;

  /// Sessão atual; `null` quando ninguém entrou.
  final ValueListenable<Sessao?> sessao;

  final Future<Sessao> Function(String usuario, String senha) aoEntrar;
  final Future<void> Function() aoSair;

  /// Rota pedida antes do login, para retomar depois dele.
  String? _destinoAposLogin;

  GoRouter criar() => GoRouter(
    // O link compartilhado precisa abrir o dia pedido. O GoRouter só usa a URL
    // do navegador quando `initialLocation` é nulo **e** a rota padrão da
    // plataforma não é `/`; na prática o caminho observado veio vazio e a tela
    // caía em `/semana`. Lendo `Uri.base` explicitamente, a URL manda.
    initialLocation: _rotaInicial(),
    refreshListenable: sessao,
    redirect: (context, estado) {
      final naTelaDeAcesso = estado.matchedLocation == '/acesso';
      final autenticado = !exigeLogin || sessao.value != null;

      if (!autenticado) {
        if (naTelaDeAcesso) return null;
        // Guarda o destino para voltar a ele depois do login: sem isto, abrir
        // `/dia/qua` sem sessão terminava em `/semana` após entrar.
        _destinoAposLogin = estado.uri.toString();
        return '/acesso';
      }
      if (naTelaDeAcesso) {
        final destino = _destinoAposLogin;
        _destinoAposLogin = null;
        return destino == null || destino == '/acesso' ? '/semana' : destino;
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/semana'),
      GoRoute(
        path: '/semana',
        builder: (context, estado) => _semana(context, estado),
      ),
      // `/semana/2026-10-21` — a data é a chave de navegação: recarregar a
      // página mantém a semana aberta, e o link é compartilhável.
      GoRoute(
        path: '/semana/:data',
        builder: (context, estado) => _semana(context, estado),
      ),
      GoRoute(
        path: '/dia/:chave',
        builder: (context, estado) => _semana(context, estado),
      ),
      GoRoute(
        path: '/calendario',
        builder: (context, estado) => TelaCalendario(
          repositorio: repositorio,
          aoAbrirDia: (data) => context.go('/semana/${Datas.iso(data)}'),
          // Volta para o dia que estava aberto — não para "hoje": quem saiu de
          // 5 de novembro espera voltar a 5 de novembro.
          aoVoltar: () => context.go('/semana/${Datas.iso(repositorio.selecionado)}'),
          aoAbrirAjustes: () => context.go('/ajustes'),
        ),
      ),
      GoRoute(
        path: '/acesso',
        builder: (context, estado) => TelaAcesso(
          aoEntrar: aoEntrar,
          motivo: estado.uri.queryParameters['motivo'],
        ),
      ),
      GoRoute(
        path: '/ajustes',
        builder: (context, estado) => const TelaAjustes(),
      ),
      // Qualquer caminho desconhecido cai na semana. Sem isto o GoRouter mostra
      // a tela "Page Not Found", que num app de uma rota só é ruído — e um link
      // antigo (`/dia/terca`, por exemplo) viraria erro em vez de abrir o app.
      GoRoute(path: '/:resto(.*)', redirect: (_, _) => '/semana'),
    ],
  );

  /// Caminho pedido pela URL atual; `/` no mobile, onde não há URL.
  static String _rotaInicial() {
    if (!kIsWeb) return '/semana';
    final caminho = Uri.base.path;
    return caminho.isEmpty || caminho == '/' ? '/semana' : caminho;
  }

  Widget _semana(BuildContext context, GoRouterState estado) {
    // Duas formas de abrir um dia: `/semana/AAAA-MM-DD` (calendário e navegação)
    // e `/dia/qua` (link antigo). A segunda resolve para a primeira quarta a
    // partir de hoje, para não depender de "qual semana".
    final porData = Datas.deIso(estado.pathParameters['data']);
    final chave = estado.pathParameters['chave'];
    final porChave = chave == null
        ? null
        : _primeiraDataDaChave(repositorio.selecionado, chave);

    return TelaSemana(
      repositorio: repositorio,
      dataInicial: porData ?? porChave,
      usuario: sessao.value?.usuario,
      aoAbrirAjustes: () => context.go('/ajustes'),
      aoAbrirCalendario: () => context.go('/calendario'),
      // A rota acompanha a data escolhida: sem isto, recarregar a página
      // voltaria para hoje e o link deixaria de representar a tela.
      aoMudarData: (data) => context.replace('/semana/${Datas.iso(data)}'),
      // Sem backend não há conta: esconder "Sair" evita prometer um recurso que
      // não existe (e o rodapé diz "neste aparelho", não "na sua conta").
      aoSair: exigeLogin ? aoSair : null,
    );
  }

  /// Data da semana aberta que corresponde a [chave] (`qua`).
  static DateTime _primeiraDataDaChave(DateTime referencia, String chave) {
    if (!Dia.chaveValida(chave)) return referencia;
    for (final data in Datas.semanaDe(referencia)) {
      if (Semana.chaveDaData(data) == chave) return data;
    }
    return referencia;
  }
}

/// Monta o [Escopo] a partir do estado corrente da sessão.
///
/// Fica aqui, e não no widget raiz, para que o roteador e a árvore de widgets
/// leiam exatamente os mesmos dados.
Escopo escopoDoApp({
  required Repositorio repositorio,
  required ValueListenable<Sessao?> sessao,
  required SessaoApi? cliente,
  required Future<Sessao> Function(String usuario, String senha) aoEntrar,
  required Future<void> Function() aoSair,
  required Widget child,
}) => Escopo(
  repositorio: repositorio,
  sessao: sessao.value,
  clienteSessao: cliente,
  aoEntrar: aoEntrar,
  aoSair: aoSair,
  child: child,
);
