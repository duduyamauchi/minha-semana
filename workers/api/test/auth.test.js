// Testes de autenticação e validação.
//
// Rodam no Node puro (`node --test`), sem rede e sem banco: exercitam as
// funções puras que o Worker usa. A verificação contra o banco real é feita no
// navegador e por curl depois do deploy; aqui o objetivo é pegar regressão de
// lógica antes de publicar.

import test from 'node:test';
import assert from 'node:assert/strict';

import {
  base64ParaBytes,
  bytesParaBase64,
  conferirSenha,
  cookieDeSessao,
  derivarHash,
  emitirSessao,
  gerarSalt,
  identificar,
  iguaisEmTempoConstante,
  lerCookie,
  lerSessao,
  paraHex,
  segundosAteExpirar,
} from '../src/auth.js';

const SEGREDO = 'segredo-de-teste-nao-use-em-producao';
const PEPPER = 'pepper-de-teste';

test('hash de senha confere com a mesma senha e falha com outra', async () => {
  const salt = gerarSalt();
  const hash = await derivarHash('senha-correta', salt, 100000, PEPPER);

  assert.equal(await conferirSenha('senha-correta', { hash, salt, iteracoes: 100000 }, PEPPER), true);
  assert.equal(await conferirSenha('senha-errada', { hash, salt, iteracoes: 100000 }, PEPPER), false);
});

test('pepper errado invalida a senha certa', async () => {
  const salt = gerarSalt();
  const hash = await derivarHash('senha-correta', salt, 100000, PEPPER);

  // Sem o pepper do servidor, o dump do banco não autentica.
  assert.equal(await conferirSenha('senha-correta', { hash, salt, iteracoes: 100000 }, 'outro'), false);
  // Sem pepper nenhum é erro de configuração, não "senha errada": falhar alto
  // evita aceitar login por engano com um hash derivado sem segredo.
  await assert.rejects(() =>
    conferirSenha('senha-correta', { hash, salt, iteracoes: 100000 }, undefined),
  );
});

test('sem pepper configurado o hash nem é calculado', async () => {
  // Falhar alto é melhor que gerar um hash sem segredo e aceitar login com ele.
  await assert.rejects(() => derivarHash('x', gerarSalt(), 100000, undefined));
});

test('salt diferente gera hash diferente para a mesma senha', async () => {
  const a = await derivarHash('mesma-senha', gerarSalt(), 100000, PEPPER);
  const b = await derivarHash('mesma-senha', gerarSalt(), 100000, PEPPER);
  assert.notEqual(a, b);
});

test('codificação base64 ida e volta preserva bytes', () => {
  const bytes = Uint8Array.from([0, 1, 2, 65, 200, 255]);
  assert.deepEqual([...base64ParaBytes(bytesParaBase64(bytes))], [...bytes]);
});

test('hex tem dois dígitos por byte', () => {
  assert.equal(paraHex(Uint8Array.from([0, 15, 255])), '000fff');
});

test('comparação em tempo constante', () => {
  assert.equal(iguaisEmTempoConstante('abc', 'abc'), true);
  assert.equal(iguaisEmTempoConstante('abc', 'abd'), false);
  assert.equal(iguaisEmTempoConstante('abc', 'abcd'), false);
});

test('sessão emitida é válida e carrega o usuário', async () => {
  const valor = await emitirSessao('sarah', SEGREDO);
  const lida = await lerSessao(valor, SEGREDO);
  assert.equal(lida.usuarioId, 'sarah');
  assert.ok(lida.expiraEm > Date.now());
});

test('sessão adulterada é recusada', async () => {
  const valor = await emitirSessao('sarah', SEGREDO);
  const [corpo] = valor.split('.');
  const forjado = `${corpo}.assinatura-errada`;
  assert.equal(await lerSessao(forjado, SEGREDO), null);
});

test('sessão não aceita payload trocado sem reassinar', async () => {
  const deOutro = await emitirSessao('intruso', SEGREDO);
  const [, assinatura] = deOutro.split('.');
  const alvo = await emitirSessao('sarah', SEGREDO);
  const [corpoAlvo] = alvo.split('.');
  assert.equal(await lerSessao(`${corpoAlvo}.${assinatura}`, SEGREDO), null);
});

test('sessão com outro segredo é recusada', async () => {
  const valor = await emitirSessao('sarah', SEGREDO);
  assert.equal(await lerSessao(valor, 'outro-segredo'), null);
});

test('sessão expirada por tempo absoluto é recusada', async () => {
  const agora = Date.now();
  const valor = await emitirSessao('sarah', SEGREDO, agora);
  // 9 horas depois: passou do teto de 8 h.
  assert.equal(await lerSessao(valor, SEGREDO, agora + 9 * 60 * 60 * 1000), null);
});

test('sessão expira por inatividade, mesmo dentro do prazo absoluto', async () => {
  const agora = Date.now();
  const valor = await emitirSessao('sarah', SEGREDO, agora);
  // 2 horas sem uso: ainda dentro das 8 h, mas passou da 1 h de inatividade.
  assert.equal(await lerSessao(valor, SEGREDO, agora + 2 * 60 * 60 * 1000), null);
});

test('sessão recente é renovável', async () => {
  const agora = Date.now();
  const valor = await emitirSessao('sarah', SEGREDO, agora);
  const lida = await lerSessao(valor, SEGREDO, agora);
  assert.equal(lida.renovavel, false);
  // Com uso registrado, a renovação respeita a margem de 1 minuto.
  const comUso = await emitirSessao('sarah', SEGREDO, agora + 120000, Math.floor(agora / 1000));
  const depois = await lerSessao(comUso, SEGREDO, agora + 120000);
  assert.equal(depois.renovavel, true);
});

test('segundosAteExpirar desconta o tempo já usado', async () => {
  const agora = Date.now();
  const valor = await emitirSessao('sarah', SEGREDO, agora);
  const lida = await lerSessao(valor, SEGREDO, agora);
  // O arredondamento para segundo vem do `floor` do timestamp de assinatura,
  // então a margem é de 1 s.
  const restante = segundosAteExpirar(lida, agora + 60_000);
  assert.ok(restante === 3540 || restante === 3539, `restante=${restante}`);
});

test('cookie carrega as flags de segurança', () => {
  const cookie = cookieDeSessao('valor');
  assert.match(cookie, /HttpOnly/);
  assert.match(cookie, /SameSite=Strict/);
  assert.match(cookie, /Secure/);
  assert.match(cookie, /Path=\//);
  // Em http local o `Secure` sai, senão o navegador descarta o cookie.
  assert.doesNotMatch(cookieDeSessao('valor', { seguro: false }), /Secure/);
});

test('lerCookie encontra o valor entre outros cookies', () => {
  assert.equal(lerCookie('outro=1; minha_semana_sessao=abc.def; terceiro=2'), 'abc.def');
  assert.equal(lerCookie('outro=1'), null);
  assert.equal(lerCookie(null), null);
});

test('identificar reconhece cookie, token de serviço e anônimo', async () => {
  const valor = await emitirSessao('sarah', SEGREDO);
  const env = { SESSION_SECRET: SEGREDO, SERVICE_TOKEN: 'token-servico' };

  const porCookie = await identificar(
    new Request('https://api.test/semana', { headers: { cookie: `minha_semana_sessao=${valor}` } }),
    env,
  );
  assert.equal(porCookie.tipo, 'usuario');
  assert.equal(porCookie.usuarioId, 'sarah');

  const porToken = await identificar(
    new Request('https://api.test/semana', { headers: { authorization: 'Bearer token-servico' } }),
    env,
  );
  assert.equal(porToken.tipo, 'servico');

  const anonimo = await identificar(new Request('https://api.test/semana'), env);
  assert.equal(anonimo.tipo, 'anonimo');

  const tokenErrado = await identificar(
    new Request('https://api.test/semana', { headers: { authorization: 'Bearer outro' } }),
    env,
  );
  assert.equal(tokenErrado.tipo, 'anonimo');
});

test('cookie de sessão inválido cai para anônimo', async () => {
  const env = { SESSION_SECRET: SEGREDO, SERVICE_TOKEN: 'x' };
  const r = await identificar(
    new Request('https://api.test/semana', { headers: { cookie: 'minha_semana_sessao=forjado' } }),
    env,
  );
  assert.equal(r.tipo, 'anonimo');
});
