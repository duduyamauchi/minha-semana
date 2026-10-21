import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:planner_core/planner_core.dart';

import 'core/escopo.dart';
import 'telas/acesso.dart';
import 'telas/ajustes.dart';
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

  GoRouter criar() => GoRouter(
    initialLocation: '/semana',
    refreshListenable: sessao,
    redirect: (context, estado) {
      final naTelaDeAcesso = estado.matchedLocation == '/acesso';
      final autenticado = !exigeLogin || sessao.value != null;

      if (!autenticado) return naTelaDeAcesso ? null : '/acesso';
      if (naTelaDeAcesso) return '/semana';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/semana'),
      GoRoute(path: '/semana', builder: (context, estado) => _semana(context, estado)),
      GoRoute(path: '/dia/:chave', builder: (context, estado) => _semana(context, estado)),
      GoRoute(
        path: '/acesso',
        builder: (context, estado) => TelaAcesso(
          aoEntrar: aoEntrar,
          motivo: estado.uri.queryParameters['motivo'],
        ),
      ),
      GoRoute(path: '/ajustes', builder: (context, estado) => const TelaAjustes()),
    ],
  );

  Widget _semana(BuildContext context, GoRouterState estado) => TelaSemana(
    repositorio: repositorio,
    abaInicial: estado.pathParameters['chave'],
    usuario: sessao.value?.usuario,
    aoAbrirAjustes: () => context.go('/ajustes'),
    // Sem backend não há conta: esconder "Sair" evita prometer um recurso que
    // não existe (e o rodapé diz "neste aparelho", não "na sua conta").
    aoSair: exigeLogin ? aoSair : null,
  );
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
