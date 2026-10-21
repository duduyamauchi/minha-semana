import 'package:flutter/material.dart';
import 'package:planner_core/planner_core.dart';

/// Escopo global do app: sessão, repositório, ajustes e conta.
///
/// É um `InheritedNotifier`: quando o repositório notifica, quem depende dele
/// reconstrói — e ninguém precisa passar `Repositorio` de widget em widget.
class Escopo extends InheritedNotifier<Repositorio> {
  const Escopo({
    super.key,
    required Repositorio repositorio,
    required this.sessao,
    required this.clienteSessao,
    required this.aoEntrar,
    required this.aoSair,
    required super.child,
  }) : super(notifier: repositorio);

  /// Sessão atual, `null` quando o app funciona só no aparelho ou ninguém
  /// entrou.
  final Sessao? sessao;

  /// Cliente de login; `null` sem backend.
  final SessaoApi? clienteSessao;

  /// Entra com usuário e senha (a rota usa para voltar à tela anterior).
  final Future<Sessao> Function(String usuario, String senha) aoEntrar;

  final Future<void> Function() aoSair;

  /// O app exige login para mostrar a semana.
  bool get exigeLogin => clienteSessao != null;

  bool get autenticado => !exigeLogin || sessao != null;

  static Escopo de(BuildContext context) {
    final escopo = context.dependOnInheritedWidgetOfExactType<Escopo>();
    assert(escopo != null, 'Escopo ausente: envolva a árvore com Escopo.');
    return escopo!;
  }

  /// Atalho para o repositório.
  Repositorio get repositorio => notifier!;
}
