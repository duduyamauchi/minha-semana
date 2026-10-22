import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:planner_core/planner_core.dart';
import 'package:planner_ui/planner_ui.dart';

import '../core/escopo.dart';

/// Tela de ajustes: de onde vêm os dados, backup e conta.
///
/// Existe para tornar a arquitetura visível: mostra a fonte ativa, permite
/// exportar e importar o estado (o mesmo JSON em qualquer fonte) e sair da
/// conta. É o equivalente, no app, da tela "Fonte de dados" do painel do
/// EquiLink — sem ela, trocar de backend é uma caixa-preta.
class TelaAjustes extends StatefulWidget {
  const TelaAjustes({super.key});

  @override
  State<TelaAjustes> createState() => _TelaAjustesState();
}

class _TelaAjustesState extends State<TelaAjustes> {
  final _importar = TextEditingController();
  bool _mostrarImportar = false;
  String? _aviso;
  String? _erro;

  @override
  void dispose() {
    _importar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final escopo = Escopo.de(context);
    final rep = escopo.repositorio;
    final paleta = EscopoUi.de(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
        backgroundColor: paleta.fundo,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CaixaUi(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Origem dos dados',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      _LinhaInfo(rotulo: 'Fonte', valor: rep.fonte.descricao),
                      _LinhaInfo(
                        rotulo: 'Onde fica',
                        valor: rep.fonteRemota
                            ? 'Na nuvem, ligada à sua conta'
                            : 'Neste aparelho',
                      ),
                      _LinhaInfo(
                        rotulo: 'Progresso',
                        valor: '${rep.percentual}% da semana',
                      ),
                      _LinhaInfo(
                        rotulo: 'Atividades',
                        valor: '${rep.totalFeitas} de ${rep.totalAtividades}',
                      ),
                      _LinhaInfo(
                        rotulo: 'Telemetria',
                        valor: rep.analytics.descricaoColetor,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_aviso != null) ...[
                  FaixaErroUi(
                    mensagem: _aviso!,
                    onDispensar: () => setState(() => _aviso = null),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_erro != null) ...[
                  FaixaErroUi(
                    mensagem: _erro!,
                    onDispensar: () => setState(() => _erro = null),
                  ),
                  const SizedBox(height: 12),
                ],
                CaixaUi(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Backup',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'O estado é um JSON pequeno: marcações e cômodos. Exporte para guardar '
                        'uma cópia ou para levar o plano de um aparelho a outro.',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: paleta.textoSecundario,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          BotaoUi(
                            rotulo: 'Exportar',
                            icone: Icons.download,
                            onPressed: () async {
                              final json = Formatos.jsonBonito(
                                rep.semana.estado.toJson(),
                              );
                              _importar.text = json;
                              setState(() {
                                _mostrarImportar = true;
                                _aviso =
                                    'Cópia do estado abaixo. Selecione e copie o texto.';
                                _erro = null;
                              });
                              // O texto fica no campo e também na área de
                              // transferência: exportar sem conseguir colar em
                              // outro lugar não serve de nada.
                              final copiou = await _copiar(json);
                              if (!mounted || !copiou) return;
                              setState(() {
                                _aviso =
                                    'Cópia do estado abaixo — também está na área de transferência.';
                              });
                            },
                          ),
                          BotaoUi(
                            rotulo: _mostrarImportar
                                ? 'Ocultar importação'
                                : 'Importar',
                            icone: Icons.upload,
                            secundario: true,
                            onPressed: () => setState(() {
                              _mostrarImportar = !_mostrarImportar;
                              _aviso = null;
                              _erro = null;
                            }),
                          ),
                        ],
                      ),
                      if (_mostrarImportar) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _importar,
                          minLines: 6,
                          maxLines: 14,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12.5,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Cole aqui o JSON exportado',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        BotaoUi(
                          rotulo: 'Substituir a semana',
                          onPressed: () => _importarEstado(rep),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                if (escopo.autenticado) ...[
                  const SizedBox(height: 16),
                  CaixaUi(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Conta',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        _LinhaInfo(
                          rotulo: 'Usuário',
                          valor: escopo.sessao?.usuario ?? '—',
                        ),
                        _LinhaInfo(
                          rotulo: 'Papel',
                          valor: escopo.sessao?.papelRotulo ?? '—',
                        ),
                        const SizedBox(height: 12),
                        BotaoUi(
                          rotulo: 'Sair',
                          secundario: true,
                          onPressed: () async {
                            await escopo.aoSair();
                            if (context.mounted) Navigator.of(context).pop();
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Minha Semana · ${Ambiente.site}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: paleta.textoSecundario),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Copia para a área de transferência; devolve `false` quando o navegador
  /// recusa (sem permissão, contexto não seguro).
  Future<bool> _copiar(String texto) async {
    try {
      await Clipboard.setData(ClipboardData(text: texto));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _importarEstado(Repositorio rep) async {
    final texto = _importar.text.trim();
    if (texto.isEmpty) {
      setState(() => _erro = 'Cole um JSON antes de importar.');
      return;
    }
    try {
      final json = jsonDecode(texto);
      if (json is! Map) {
        throw const FormatException('O JSON precisa ser um objeto.');
      }
      final estado = EstadoSemana.fromJson(json.cast<String, dynamic>());
      final ok = await rep.importar(estado);
      if (!mounted) return;
      setState(() {
        _erro = ok ? null : rep.erro;
        _aviso = ok
            ? 'Semana importada: ${estado.marcadas.length} atividades e ${estado.comodos.length} cômodos.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'JSON inválido: não foi possível ler o backup.';
      });
    }
  }
}

class _LinhaInfo extends StatelessWidget {
  const _LinhaInfo({required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final paleta = EscopoUi.de(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              rotulo,
              style: TextStyle(fontSize: 13.5, color: paleta.textoSecundario),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(fontSize: 13.5, color: paleta.texto),
            ),
          ),
        ],
      ),
    );
  }
}
