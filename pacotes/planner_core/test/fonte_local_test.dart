import 'package:flutter_test/flutter_test.dart';
import 'package:planner_core/planner_core.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Cada teste começa com um armazenamento vazio — o mesmo contrato da
  /// `SharedPreferencesAsync`, sem tocar no disco.
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  test('começa com o estado padrão quando não há nada salvo', () async {
    final fonte = FonteLocal();
    final estado = await fonte.carregar();
    expect(estado.marcadas, isEmpty);
    expect(estado.comodos.map((c) => c.nome), contains('Cozinha'));
  });

  test('grava e relê a marcação no aparelho', () async {
    final fonte = FonteLocal();
    await fonte.carregar();
    await fonte.definirConcluida('seg-06:00', concluida: true);
    await fonte.salvarComodo(const Comodo(id: 'cozinha', nome: 'Cozinha', concluido: true));

    // Uma instância nova simula o app reaberto.
    final outra = FonteLocal();
    final estado = await outra.carregar();
    expect(estado.marcadas, {'seg-06:00'});
    expect(estado.comodos.firstWhere((c) => c.id == 'cozinha').concluido, isTrue);
  });

  test('gravar antes de carregar não apaga o que já estava salvo', () async {
    final primeira = FonteLocal();
    await primeira.carregar();
    await primeira.definirConcluida('ter-11:00', concluida: true);

    final segunda = FonteLocal();
    await segunda.salvarComodo(const Comodo(id: 'sala', nome: 'Sala'));
    final estado = await FonteLocal().carregar();
    expect(estado.marcadas, contains('ter-11:00'));
    expect(estado.comodos.any((c) => c.id == 'sala'), isTrue);
  });

  test('desmarcar e remover comodo persistem', () async {
    final fonte = FonteLocal();
    await fonte.carregar();
    await fonte.definirConcluida('seg-06:00', concluida: true);
    await fonte.definirConcluida('seg-06:00', concluida: false);
    await fonte.removerComodo('sala');

    final estado = await FonteLocal().carregar();
    expect(estado.marcadas, isEmpty);
    expect(estado.comodos.any((c) => c.id == 'sala'), isFalse);
  });

  test('JSON corrompido reinicia a semana em vez de impedir o app de abrir', () async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData({
      'minha-semana-v2': '{isso não é json',
    });
    final fonte = FonteLocal();
    await expectLater(fonte.carregar(), throwsA(isA<ErroFonte>()));
    expect(fonte.estadoAtual.marcadas, isEmpty);
  });
}
