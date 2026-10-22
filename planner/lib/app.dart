import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:planner_core/planner_core.dart';
import 'package:planner_ui/planner_ui.dart';

import 'core/inatividade.dart';
import 'core/tema.dart';
import 'rotas.dart';

/// Casca do aplicativo: repositório, sessão, rotas e tema.
///
/// Criada uma vez em `main.dart`. A sessão vive num [ValueNotifier] para que o
/// roteador reaja a ela sem que as telas conheçam o cliente HTTP.
class Aplicativo extends StatefulWidget {
  const Aplicativo({super.key, required this.repositorio, this.clienteSessao});

  final Repositorio repositorio;

  /// `null` quando o app funciona só no aparelho (sem conta).
  final SessaoApi? clienteSessao;

  @override
  State<Aplicativo> createState() => _AplicativoState();
}

class _AplicativoState extends State<Aplicativo> {
  final ValueNotifier<Sessao?> _sessao = ValueNotifier(null);

  /// Mensagem da faixa de sessão (aviso de inatividade ou de expiração).
  final ValueNotifier<String?> _avisoSessao = ValueNotifier(null);

  Inatividade? _inatividade;
  late final GoRouter _rotas;

  bool get _exigeLogin => widget.clienteSessao != null;

  @override
  void initState() {
    super.initState();
    _rotas = Rotas(
      repositorio: widget.repositorio,
      exigeLogin: _exigeLogin,
      sessao: _sessao,
      aoEntrar: _entrar,
      aoSair: _sair,
    ).criar();
    _restaurarSessao();
  }

  @override
  void dispose() {
    _inatividade?.parar();
    _sessao.dispose();
    _avisoSessao.dispose();
    _rotas.dispose();
    super.dispose();
  }

  /// Restaura a sessão ao abrir.
  ///
  /// Sem isto, um cookie válido ainda mostraria a tela de login: o servidor
  /// lembra de quem entrou, mas o app precisa perguntar.
  Future<void> _restaurarSessao() async {
    final cliente = widget.clienteSessao;
    if (cliente == null) return;
    final atual = await cliente.atual();
    if (!mounted || atual == null) return;
    _sessao.value = atual;
    widget.repositorio.analytics.identificar(atual.usuario);
    _iniciarInatividade();
    // Com sessão, o estado vem da nuvem — não do que estava no aparelho.
    await widget.repositorio.carregar();
  }

  Future<Sessao> _entrar(String usuario, String senha) async {
    final cliente = widget.clienteSessao;
    if (cliente == null) {
      throw const ErroLogin('Este aplicativo não tem servidor configurado.');
    }
    final sessao = await cliente.entrar(usuario, senha);
    _sessao.value = sessao;
    _avisoSessao.value = null;
    widget.repositorio.analytics.identificar(usuario);
    _iniciarInatividade();
    await widget.repositorio.carregar();
    return sessao;
  }

  Future<void> _sair() async {
    _inatividade?.parar();
    _inatividade = null;
    await widget.clienteSessao?.sair();
    _sessao.value = null;
    _avisoSessao.value = null;
    widget.repositorio.analytics.registrar('sessao_encerrada');
  }

  void _iniciarInatividade() {
    _inatividade?.parar();
    _inatividade = Inatividade(
      limite: Duration(seconds: Ambiente.inatividadeSegundos),
      aoAvisar: () {
        if (mounted) {
          _avisoSessao.value =
              'Sua sessão expira em instantes por inatividade.';
        }
      },
      aoExpirar: () async {
        if (!mounted) return;
        widget.repositorio.analytics.registrar(
          'sessao_expirada',
          propriedades: {'motivo': 'inatividade'},
        );
        await _sair();
        if (!mounted) return;
        _rotas.go(
          '/acesso?motivo=${Uri.encodeComponent('Sessão encerrada. Entre de novo.')}',
        );
      },
    )..iniciar();
  }

  /// Qualquer toque conta como uso — o mesmo critério do servidor, que renova a
  /// sessão a cada requisição.
  void _registrarUso() {
    if (_sessao.value == null || _inatividade == null) return;
    _inatividade!.registrarUso();
    if (_avisoSessao.value != null) {
      _avisoSessao.value = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Sessao?>(
      valueListenable: _sessao,
      builder: (context, sessao, _) => escopoDoApp(
        repositorio: widget.repositorio,
        sessao: _sessao,
        cliente: widget.clienteSessao,
        aoEntrar: _entrar,
        aoSair: _sair,
        child: MaterialApp.router(
          title: 'Minha Semana',
          debugShowCheckedModeBanner: false,
          theme: Tema.claro(),
          darkTheme: Tema.escuro(),
          themeMode: ThemeMode.system,
          routerConfig: _rotas,
          builder: (context, child) {
            final escuro = Theme.of(context).brightness == Brightness.dark;
            return EscopoUi(
              paleta: escuro ? PaletaUi.escura : PaletaUi.clara,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _registrarUso(),
                child: _ComAviso(
                  aviso: _avisoSessao,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Envolve as telas e mostra a faixa de sessão sobre o conteúdo.
class _ComAviso extends StatelessWidget {
  const _ComAviso({required this.aviso, required this.child});

  final ValueNotifier<String?> aviso;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        ValueListenableBuilder<String?>(
          valueListenable: aviso,
          builder: (context, mensagem, _) {
            if (mensagem == null) return const SizedBox.shrink();
            return Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 12,
              right: 12,
              child: Material(
                color: Colors.transparent,
                child: FaixaErroUi(mensagem: mensagem),
              ),
            );
          },
        ),
      ],
    );
  }
}
