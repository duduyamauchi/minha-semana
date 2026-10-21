// Contrato da API: autorização, validação e forma do estado.
//
// Exercita `tratar` com um duplo de banco em memória — sem rede e sem Neon. O
// que estes testes protegem é o que um erro silencioso quebraria: escrita
// anônima, escrita de leitor, corpo inválido, e o formato que o `FonteHttp`
// consome.

import test from 'node:test';
import assert from 'node:assert/strict';

import { tratar } from '../src/index.js';
import { derivarHash, emitirSessao } from '../src/auth.js';

const SEGREDO = 'segredo-de-teste';
const PEPPER = 'pepper-de-teste';
const QUADRO = '00000000-0000-0000-0000-000000000001';

const env = {
  SESSION_SECRET: SEGREDO,
  PEPPER_SENHA: PEPPER,
  SERVICE_TOKEN: 'token-servico',
  QUADRO_ID: QUADRO,
  ORIGENS_PERMITIDAS: 'https://app.test',
  DATABASE_URL: 'postgres://nao-usado',
};

/**
 * Duplo de banco.
 *
 * Responde às consultas que o Worker faz: leitura de credencial, resolução de
 * acesso, leitura/escrita das tabelas da semana e telemetria. Guarda o estado
 * em memória para o teste poder conferir o efeito.
 */
function banco({ papel = 'proprietario', senhaHash = null } = {}) {
  const estado = {
    marcadas: new Set(),
    comodos: new Map(),
    eventos: [],
  };

  const sql = async (strings, ...valores) => {
    const consulta = strings.join('?').replace(/\s+/g, ' ').trim();

    if (consulta.includes('from quadro_do_usuario')) {
      return papel ? [{ quadro_id: QUADRO, papel }] : [];
    }
    if (consulta.includes('from credenciais')) {
      return senhaHash ? [senhaHash] : [];
    }
    if (consulta.includes('from tentativas_login')) {
      return [{ n: 0 }];
    }
    if (consulta.includes('insert into tentativas_login') || consulta.includes('delete from tentativas_login')) {
      return [];
    }
    if (consulta.includes('select atividade_id from atividades_concluidas')) {
      return [...estado.marcadas].sort().map((id) => ({ atividade_id: id }));
    }
    if (consulta.includes('select id, nome, concluido from comodos')) {
      return [...estado.comodos.values()].sort((a, b) => a.nome.localeCompare(b.nome));
    }
    if (consulta.includes('delete from atividades_concluidas')) {
      if (consulta.includes('atividade_id =')) {
        estado.marcadas.delete(valores[1]);
      } else {
        estado.marcadas.clear();
      }
      return [];
    }
    if (consulta.includes('insert into atividades_concluidas')) {
      // Marcação individual manda um id; a importação manda a lista inteira
      // para o `unnest`.
      const alvo = valores[1];
      if (Array.isArray(alvo)) {
        for (const id of alvo) estado.marcadas.add(id);
      } else {
        estado.marcadas.add(alvo);
      }
      return [];
    }
    if (consulta.includes('delete from comodos')) {
      estado.comodos.delete(valores[1]);
      return [];
    }
    if (consulta.includes('insert into comodos')) {
      // As duas formas que o Worker usa: uma linha (`values`) e o lote da
      // importação (`unnest ... with ordinality`). Em ambas, o quadro vem
      // primeiro e sobra (id, nome, concluido) na ordem.
      const [, ids, nomes, concluidos] = valores;
      if (Array.isArray(ids)) {
        ids.forEach((id, i) => estado.comodos.set(id, { id, nome: nomes[i], concluido: concluidos[i] }));
      } else {
        estado.comodos.set(ids, { id: ids, nome: nomes, concluido: concluidos });
      }
      return [];
    }
    if (consulta.includes('insert into eventos_analiticos')) {
      estado.eventos.push(valores.map((v) => v));
      return [];
    }
    if (consulta.includes('from eventos_analiticos')) {
      return [];
    }
    throw new Error(`Consulta não prevista no duplo: ${consulta.slice(0, 120)}`);
  };

  return { sql, estado };
}

const comSessao = async (usuario = 'sarah') => {
  const valor = await emitirSessao(usuario, SEGREDO);
  return `minha_semana_sessao=${valor}`;
};

const pedir = (caminho, { metodo = 'GET', cookie, corpo, env: ambiente = env } = {}) => {
  const headers = { origin: 'https://app.test' };
  if (cookie) headers.cookie = cookie;
  if (corpo) headers['content-type'] = 'application/json';
  return new Request(`https://api.test${caminho}`, {
    method: metodo,
    headers,
    body: corpo ? JSON.stringify(corpo) : undefined,
  });
};

test('sem sessão, nem a leitura da semana passa', async () => {
  const { sql } = banco();
  const r = await tratar(pedir('/semana'), env, sql);
  assert.equal(r.status, 401);
});

test('GET /semana devolve o formato que o app espera', async () => {
  const { sql, estado } = banco();
  estado.marcadas.add('seg-06:00');
  estado.comodos.set('cozinha', { id: 'cozinha', nome: 'Cozinha', concluido: true });

  const r = await tratar(pedir('/semana', { cookie: await comSessao() }), env, sql);
  assert.equal(r.status, 200);
  const corpo = await r.json();
  assert.deepEqual(corpo.marcadas, ['seg-06:00']);
  assert.deepEqual(corpo.comodos, [{ id: 'cozinha', nome: 'Cozinha', concluido: true }]);
});

test('login com senha certa devolve cookie HttpOnly e identidade', async () => {
  const salt = 'c2FsdC1kZS10ZXN0ZQ==';
  const hash = await derivarHash('senha-certa', salt, 100000, PEPPER);
  const { sql } = banco({ senhaHash: { usuario_id: 'sarah', hash, salt, iteracoes: 100000 } });

  const r = await tratar(
    pedir('/sessao', { metodo: 'POST', corpo: { usuario: 'sarah', senha: 'senha-certa' } }),
    env,
    sql,
  );
  assert.equal(r.status, 200);
  const cookie = r.headers.get('set-cookie');
  assert.match(cookie, /HttpOnly/);
  assert.match(cookie, /SameSite=Strict/);
  const corpo = await r.json();
  assert.equal(corpo.usuario, 'sarah');
  assert.equal(corpo.papel, 'proprietario');
});

test('login com senha errada responde 401 sem revelar a causa', async () => {
  const salt = 'c2FsdC1kZS10ZXN0ZQ==';
  const hash = await derivarHash('senha-certa', salt, 100000, PEPPER);
  const { sql } = banco({ senhaHash: { usuario_id: 'sarah', hash, salt, iteracoes: 100000 } });

  const r = await tratar(
    pedir('/sessao', { metodo: 'POST', corpo: { usuario: 'sarah', senha: 'errada' } }),
    env,
    sql,
  );
  assert.equal(r.status, 401);
  assert.equal((await r.json()).erro, 'Usuário ou senha inválidos.');
});

test('usuário inexistente responde igual a senha errada', async () => {
  const { sql } = banco({ senhaHash: null });
  const r = await tratar(
    pedir('/sessao', { metodo: 'POST', corpo: { usuario: 'ninguem', senha: 'x' } }),
    env,
    sql,
  );
  assert.equal(r.status, 401);
  assert.equal((await r.json()).erro, 'Usuário ou senha inválidos.');
});

test('PUT /atividades/:id marca e desmarca', async () => {
  const { sql, estado } = banco();
  const cookie = await comSessao();

  const marcar = await tratar(
    pedir('/atividades/seg-06:00', { metodo: 'PUT', cookie, corpo: { concluida: true } }),
    env,
    sql,
  );
  assert.equal(marcar.status, 200);
  assert.ok(estado.marcadas.has('seg-06:00'));

  const desmarcar = await tratar(
    pedir('/atividades/seg-06:00', { metodo: 'PUT', cookie, corpo: { concluida: false } }),
    env,
    sql,
  );
  assert.equal(desmarcar.status, 200);
  assert.equal(estado.marcadas.has('seg-06:00'), false);
});

test('marcas de dois aparelhos se somam (gravação por atividade)', async () => {
  const { sql, estado } = banco();
  const a = await comSessao('sarah');
  await tratar(pedir('/atividades/seg-06:00', { metodo: 'PUT', cookie: a, corpo: { concluida: true } }), env, sql);
  await tratar(pedir('/atividades/ter-22:00', { metodo: 'PUT', cookie: a, corpo: { concluida: true } }), env, sql);
  assert.deepEqual([...estado.marcadas].sort(), ['seg-06:00', 'ter-22:00']);
});

test('concluida precisa ser booleano', async () => {
  const { sql } = banco();
  const r = await tratar(
    pedir('/atividades/seg-06:00', { metodo: 'PUT', cookie: await comSessao(), corpo: { concluida: 'sim' } }),
    env,
    sql,
  );
  assert.equal(r.status, 400);
});

test('id de atividade com barra é recusado', async () => {
  const { sql } = banco();
  const r = await tratar(
    pedir('/atividades/..%2Fsegredo', { metodo: 'PUT', cookie: await comSessao(), corpo: { concluida: true } }),
    env,
    sql,
  );
  assert.equal(r.status, 400);
});

test('leitor pode ler mas não escrever', async () => {
  const { sql } = banco({ papel: 'leitor' });
  const cookie = await comSessao();

  const leitura = await tratar(pedir('/semana', { cookie }), env, sql);
  assert.equal(leitura.status, 200);

  const escrita = await tratar(
    pedir('/atividades/seg-06:00', { metodo: 'PUT', cookie, corpo: { concluida: true } }),
    env,
    sql,
  );
  assert.equal(escrita.status, 403);
});

test('token de serviço escreve sem cookie (sincronização)', async () => {
  const { sql, estado } = banco();
  const r = await tratar(
    new Request('https://api.test/atividades/seg-06:00', {
      method: 'PUT',
      headers: { 'content-type': 'application/json', authorization: 'Bearer token-servico' },
      body: JSON.stringify({ concluida: true }),
    }),
    env,
    sql,
  );
  assert.equal(r.status, 200);
  assert.ok(estado.marcadas.has('seg-06:00'));
});

test('DELETE /atividades limpa a semana', async () => {
  const { sql, estado } = banco();
  estado.marcadas.add('seg-06:00');
  const r = await tratar(pedir('/atividades', { metodo: 'DELETE', cookie: await comSessao() }), env, sql);
  assert.equal(r.status, 200);
  assert.equal(estado.marcadas.size, 0);
});

test('cômodo é gravado e removido', async () => {
  const { sql, estado } = banco();
  const cookie = await comSessao();

  await tratar(
    pedir('/comodos/escritorio', { metodo: 'PUT', cookie, corpo: { id: 'escritorio', nome: 'Escritório' } }),
    env,
    sql,
  );
  assert.equal(estado.comodos.get('escritorio').nome, 'Escritório');

  await tratar(pedir('/comodos/escritorio', { metodo: 'DELETE', cookie }), env, sql);
  assert.equal(estado.comodos.has('escritorio'), false);
});

test('PUT /semana substitui o estado (importação)', async () => {
  const { sql, estado } = banco();
  estado.marcadas.add('antiga-00:00');

  const r = await tratar(
    pedir('/semana', {
      metodo: 'PUT',
      cookie: await comSessao(),
      corpo: {
        marcadas: ['qua-09:00', 'dom-22:00'],
        comodos: [{ id: 'sala', nome: 'Sala', concluido: true }],
      },
    }),
    env,
    sql,
  );
  assert.equal(r.status, 200);
  assert.deepEqual([...estado.marcadas].sort(), ['dom-22:00', 'qua-09:00']);
  assert.equal(estado.comodos.get('sala').concluido, true);
});

test('corpo que não é JSON responde 400, não 500', async () => {
  const { sql } = banco();
  const r = await tratar(
    new Request('https://api.test/semana', {
      method: 'PUT',
      headers: { 'content-type': 'application/json', cookie: await comSessao() },
      body: '{isso não é json',
    }),
    env,
    sql,
  );
  assert.equal(r.status, 400);
  assert.equal((await r.json()).erro, 'Corpo não é JSON válido.');
});

test('preflight só libera origem da allowlist', async () => {
  const { sql } = banco();

  const permitida = await tratar(
    new Request('https://api.test/semana', { method: 'OPTIONS', headers: { origin: 'https://app.test' } }),
    env,
    sql,
  );
  assert.equal(permitida.status, 204);
  assert.equal(permitida.headers.get('access-control-allow-origin'), 'https://app.test');
  assert.equal(permitida.headers.get('access-control-allow-credentials'), 'true');

  const intrusa = await tratar(
    new Request('https://api.test/semana', { method: 'OPTIONS', headers: { origin: 'https://mau.test' } }),
    env,
    sql,
  );
  assert.equal(intrusa.status, 403);
  assert.equal(intrusa.headers.get('access-control-allow-origin'), null);
});

test('sem segredos configurados a API falha fechada', async () => {
  const { sql } = banco();
  const r = await tratar(pedir('/semana', { cookie: await comSessao() }), { ...env, PEPPER_SENHA: '' }, sql);
  assert.equal(r.status, 503);
});

test('erro interno não devolve mensagem do banco', async () => {
  const sql = async () => {
    throw new Error('relation "segredo" does not exist');
  };
  const r = await tratar(pedir('/semana', { cookie: await comSessao() }), env, sql);
  assert.equal(r.status, 500);
  const corpo = await r.json();
  assert.doesNotMatch(corpo.erro, /relation|segredo/);
  assert.ok(r.headers.get('x-erro-id'));
});
