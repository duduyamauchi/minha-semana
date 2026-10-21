import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:planner_core/planner_core.dart';

import 'app.dart';

/// Ponto de entrada do aplicativo.
///
/// A fonte de dados e o coletor são decididos em tempo de compilação (ver
/// `Ambiente`), de modo que o mesmo código roda em memória, no aparelho ou
/// contra o Worker + Postgres.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Rotas sem `#`: `/dia/qua` precisa chegar ao servidor como caminho, senão o
  // link compartilhado abre a tela inicial.
  usePathUrlStrategy();

  final repositorio = Repositorio(
    Ambiente.criarFonte(),
    analytics: Analytics(Ambiente.criarColetor()),
  );

  // Sem backend, o estado vive no aparelho e a tela abre na hora. Com backend,
  // a casca pergunta quem entrou antes de carregar.
  if (Ambiente.somenteLocal) {
    repositorio.carregar();
  }

  runApp(
    Aplicativo(
      repositorio: repositorio,
      clienteSessao: Ambiente.criarSessao(),
    ),
  );
}
