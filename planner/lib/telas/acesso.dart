import 'package:flutter/material.dart';
import 'package:planner_core/planner_core.dart';
import 'package:planner_ui/planner_ui.dart';

/// Tela de acesso.
///
/// Só existe quando há backend (`PLANNER_FONTE=http`). No modo só-aparelho ela
/// nunca é montada: pedir login para marcar hábitos locais seria atrito sem
/// ganho de segurança.
class TelaAcesso extends StatefulWidget {
  const TelaAcesso({super.key, required this.aoEntrar, this.motivo});

  final Future<Sessao> Function(String usuario, String senha) aoEntrar;

  /// Explicação de por que o login está sendo pedido (ex.: sessão expirada).
  final String? motivo;

  @override
  State<TelaAcesso> createState() => _TelaAcessoState();
}

class _TelaAcessoState extends State<TelaAcesso> {
  final _usuario = TextEditingController();
  final _senha = TextEditingController();
  final _focoSenha = FocusNode();
  bool _ocupado = false;
  bool _mostrarSenha = false;
  String? _erro;

  @override
  void dispose() {
    _usuario.dispose();
    _senha.dispose();
    _focoSenha.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (_ocupado) return;
    final usuario = _usuario.text.trim();
    final senha = _senha.text;
    if (usuario.isEmpty || senha.isEmpty) {
      setState(() => _erro = 'Informe usuário e senha.');
      return;
    }
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      await widget.aoEntrar(usuario, senha);
    } on ErroLogin catch (e) {
      if (!mounted) return;
      setState(() => _erro = e.mensagem);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = 'Não foi possível entrar: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Minha Semana',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.motivo ?? 'Entre para sincronizar a sua semana.',
                      style: TextStyle(
                        fontSize: 14,
                        color: paleta.textoSecundario,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      key: const Key('campo-usuario'),
                      controller: _usuario,
                      autofocus: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      onSubmitted: (_) => _focoSenha.requestFocus(),
                      decoration: const InputDecoration(labelText: 'Usuário'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('campo-senha'),
                      controller: _senha,
                      focusNode: _focoSenha,
                      obscureText: !_mostrarSenha,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _entrar(),
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _mostrarSenha = !_mostrarSenha),
                          icon: Icon(
                            _mostrarSenha
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 19,
                          ),
                          color: paleta.textoSecundario,
                          tooltip: _mostrarSenha
                              ? 'Ocultar senha'
                              : 'Mostrar senha',
                        ),
                      ),
                    ),
                    if (_erro != null) ...[
                      const SizedBox(height: 14),
                      FaixaErroUi(mensagem: _erro!),
                    ],
                    const SizedBox(height: 20),
                    BotaoUi(
                      rotulo: _ocupado ? 'Entrando…' : 'Entrar',
                      onPressed: _ocupado ? null : _entrar,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'O plano fica salvo na sua conta e aparece em qualquer aparelho.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: paleta.textoSecundario,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
