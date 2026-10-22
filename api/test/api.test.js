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
    // Chave `data|id`, como a PK da tabela. Um `Set` simples manteria o índice
    // de consulta por data trivial de conferir nos testes.
    marcadas: new Set(),
    comodos: new Map(),
    // Plano: id -> atividade. Espelha a tabela `atividades`.
    atividades: new Map(),
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
    if (consulta.includes('select data, atividade_id from atividades_concluidas')) {
      return [...estado.marcadas]
        .sort()
        .map((chave) => {
          const [data, ...resto] = chave.split('|');
          return { data, atividade_id: resto.join('|') };
        });
    }
    if (consulta.includes('delete from atividades where')) {
      // Sem id no `where` (substituição total), limpa o plano inteiro.
      if (valores.length > 1 && valores[1] !== undefined) {
        estado.atividades.delete(valores[1]);
      } else {
        estado.atividades.clear();
      }
      return [];
    }
    if (consulta.includes('insert into atividades (quadro_id, dia, id')) {
      // `values (quadroId, dia, id, horario, …)` e, no lote, `select quadroId,
      // dia, id, …` — mesma ordem nos dois casos.
      const [, dia, id, horario, titulo, detalhe, duracao, categoria, fixo, prioridade] = valores;
      if (Array.isArray(id)) {
        id.forEach((x, i) =>
          estado.atividades.set(x, {
            dia: dia[i], id: x, horario: horario[i], titulo: titulo[i], detalhe: detalhe[i],
            duracao_minutos: duracao[i], categoria: categoria[i], fixo: fixo[i], prioridade: prioridade[i],
          }),
        );
      } else {
        estado.atividades.set(id, {
          dia, id, horario, titulo, detalhe, duracao_minutos: duracao, categoria, fixo, prioridade,
        });
      }
      return [];
    }
    // Leitura do plano: depois dos branches de escrita, porque `delete from
    // atividades where ...` também contém "from atividades".
    if (consulta.startsWith('select dia, id, horario')) {
      return [...estado.atividades.values()].sort(
        (a, b) => a.dia.localeCompare(b.dia) || a.horario.localeCompare(b.horario) || a.id.localeCompare(b.id),
      );
    }
    if (consulta.includes('select id, nome, concluido from comodos')) {
      return [...estado.comodos.values()].sort((a, b) => a.nome.localeCompare(b.nome));
    }
    if (consulta.includes('delete from atividades_concluidas')) {
      if (consulta.includes('data between')) {
        // DELETE ?inicio=...
        const inicio = valores[1];
        const fim = new Date(`${inicio}T00:00:00Z`);
        fim.setUTCDate(fim.getUTCDate() + 6);
        const limite = fim.toISOString().slice(0, 10);
        for (const chave of [...estado.marcadas]) {
          const data = chave.split('|')[0];
          if (data >= inicio && data <= limite) estado.marcadas.delete(chave);
        }
      } else if (consulta.includes('data =')) {
        // Marcação individual: `where … and data = ? and atividade_id = ?`.
        // Vem antes do caso "só id", pois também contém `atividade_id =`.
        estado.marcadas.delete(`${valores[1]}|${valores[2]}`);
      } else if (consulta.includes('atividade_id =')) {
        const id = valores[1];
        for (const chave of [...estado.marcadas]) {
          if (chave.split('|').slice(1).join('|') === id) estado.marcadas.delete(chave);
        }
      } else {
        estado.marcadas.clear();
      }
      return [];
    }
    if (consulta.includes('insert into atividades_concluidas')) {
      // Marcação individual: (quadro, data, id). Importação: dois arrays.
      const [primeiro, segundo, terceiro] = valores.slice(1);
      if (Array.isArray(primeiro)) {
        primeiro.forEach((data, i) => estado.marcadas.add(`${data}|${segundo[i]}`));
      } else {
        estado.marcadas.add(`${primeiro}|${segundo}`);
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
  estado.marcadas.add('2026-10-19|seg-06:00');
  estado.marcadas.add('2026-10-21|qua-06:00');
  estado.comodos.set('cozinha', { id: 'cozinha', nome: 'Cozinha', concluido: true });

  const r = await tratar(pedir('/semana', { cookie: await comSessao() }), env, sql);
  assert.equal(r.status, 200);
  const corpo = await r.json();
  assert.equal(corpo.versao, 4);
  assert.deepEqual(corpo.concluidas, {
    '2026-10-19': ['seg-06:00'],
    '2026-10-21': ['qua-06:00'],
  });
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

test('PUT /atividades/:data/:id marca e desmarca naquela data', async () => {
  const { sql, estado } = banco();
  const cookie = await comSessao();

  const marcar = await tratar(
    pedir('/atividades/2026-10-19/seg-06:00', { metodo: 'PUT', cookie, corpo: { concluida: true } }),
    env,
    sql,
  );
  assert.equal(marcar.status, 200);
  assert.ok(estado.marcadas.has('2026-10-19|seg-06:00'));

  // Outra data com a mesma atividade: marcações independentes.
  await tratar(
    pedir('/atividades/2026-10-26/seg-06:00', { metodo: 'PUT', cookie, corpo: { concluida: true } }),
    env,
    sql,
  );
  assert.ok(estado.marcadas.has('2026-10-26|seg-06:00'));

  const desmarcar = await tratar(
    pedir('/atividades/2026-10-19/seg-06:00', { metodo: 'PUT', cookie, corpo: { concluida: false } }),
    env,
    sql,
  );
  assert.equal(desmarcar.status, 200);
  assert.equal(estado.marcadas.has('2026-10-19|seg-06:00'), false);
  assert.ok(estado.marcadas.has('2026-10-26|seg-06:00'));
});

test('data inválida na rota é recusada', async () => {
  const { sql } = banco();
  const cookie = await comSessao();
  for (const data of ['ontem', '2026-13-01', '2026-02-31', '19-10-2026']) {
    const r = await tratar(
      pedir(`/atividades/${encodeURIComponent(data)}/seg-06:00`, {
        metodo: 'PUT',
        cookie,
        corpo: { concluida: true },
      }),
      env,
      sql,
    );
    assert.equal(r.status, 400, data);
  }
});

test('marcas de dois aparelhos se somam (gravação por atividade)', async () => {
  const { sql, estado } = banco();
  const a = await comSessao('sarah');
  await tratar(
    pedir('/atividades/2026-10-19/seg-06:00', { metodo: 'PUT', cookie: a, corpo: { concluida: true } }),
    env,
    sql,
  );
  await tratar(
    pedir('/atividades/2026-10-19/ter-22:00', { metodo: 'PUT', cookie: a, corpo: { concluida: true } }),
    env,
    sql,
  );
  assert.deepEqual([...estado.marcadas].sort(), [
    '2026-10-19|seg-06:00',
    '2026-10-19|ter-22:00',
  ]);
});

test('concluida precisa ser booleano', async () => {
  const { sql } = banco();
  const r = await tratar(
    pedir('/atividades/2026-10-21/seg-06:00', {
      metodo: 'PUT',
      cookie: await comSessao(),
      corpo: { concluida: 'sim' },
    }),
    env,
    sql,
  );
  assert.equal(r.status, 400);
});

test('id de atividade com barra é recusado', async () => {
  const { sql } = banco();
  const r = await tratar(
    pedir('/atividades/2026-10-21/..%2Fsegredo', {
      metodo: 'PUT',
      cookie: await comSessao(),
      corpo: { concluida: true },
    }),
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
    pedir('/atividades/2026-10-21/seg-06:00', { metodo: 'PUT', cookie, corpo: { concluida: true } }),
    env,
    sql,
  );
  assert.equal(escrita.status, 403);
});

test('token de serviço escreve sem cookie (sincronização)', async () => {
  const { sql, estado } = banco();
  const r = await tratar(
    new Request('https://api.test/atividades/2026-10-21/seg-06:00', {
      method: 'PUT',
      headers: { 'content-type': 'application/json', authorization: 'Bearer token-servico' },
      body: JSON.stringify({ concluida: true }),
    }),
    env,
    sql,
  );
  assert.equal(r.status, 200);
  assert.ok(estado.marcadas.has('2026-10-21|seg-06:00'));
});

test('DELETE /atividades?inicio= limpa só aquela semana', async () => {
  const { sql, estado } = banco();
  estado.marcadas.add('2026-10-12|seg-06:00');
  estado.marcadas.add('2026-10-19|seg-06:00');
  estado.marcadas.add('2026-10-25|dom-22:00');
  estado.marcadas.add('2026-10-26|seg-06:00');

  const r = await tratar(
    pedir('/atividades?inicio=2026-10-19', { metodo: 'DELETE', cookie: await comSessao() }),
    env,
    sql,
  );
  assert.equal(r.status, 200);
  assert.deepEqual([...estado.marcadas].sort(), [
    '2026-10-12|seg-06:00',
    '2026-10-26|seg-06:00',
  ]);
});

test('DELETE /atividades sem início limpa tudo', async () => {
  const { sql, estado } = banco();
  estado.marcadas.add('2026-10-19|seg-06:00');
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
  estado.marcadas.add('2026-10-12|antiga-00:00');

  const r = await tratar(
    pedir('/semana', {
      metodo: 'PUT',
      cookie: await comSessao(),
      corpo: {
        concluidas: {
          '2026-10-21': ['qua-09:00'],
          '2026-10-25': ['dom-22:00'],
        },
        comodos: [{ id: 'sala', nome: 'Sala', concluido: true }],
      },
    }),
    env,
    sql,
  );
  assert.equal(r.status, 200);
  assert.deepEqual([...estado.marcadas].sort(), ['2026-10-21|qua-09:00', '2026-10-25|dom-22:00']);
  assert.equal(estado.comodos.get('sala').concluido, true);
});

test('PUT /semana recusa data inválida em concluidas', async () => {
  const { sql } = banco();
  const r = await tratar(
    pedir('/semana', {
      metodo: 'PUT',
      cookie: await comSessao(),
      corpo: { concluidas: { '2026-02-31': ['qua-09:00'] }, comodos: [] },
    }),
    env,
    sql,
  );
  assert.equal(r.status, 400);
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

// ---------------------------------------------------------------------------
// Plano editável
// ---------------------------------------------------------------------------

test('PUT /dias/:dia/atividades/:id cria a atividade e GET devolve o plano', async () => {
  const { sql, estado } = banco();
  const cookie = await comSessao();

  const r = await tratar(
    pedir('/dias/qua/atividades/qua-09:00', {
      metodo: 'PUT',
      cookie,
      corpo: {
        id: 'qua-09:00',
        horario: '09:00',
        titulo: 'Reorganização',
        detalhe: 'um cômodo por vez',
        duracaoMinutos: 210,
        categoria: 'casa',
        prioridade: true,
      },
    }),
    env,
    sql,
  );
  assert.equal(r.status, 200);
  assert.equal((await r.json()).atividade.duracaoMinutos, 210);

  const semana = await (await tratar(pedir('/semana', { cookie }), env, sql)).json();
  assert.equal(semana.versao, 4);
  assert.deepEqual(semana.dias.map((d) => d.chave), ['qua']);
  const atividade = semana.dias[0].atividades[0];
  assert.equal(atividade.titulo, 'Reorganização');
  assert.equal(atividade.duracaoMinutos, 210);
  assert.equal(atividade.dia, 'qua');
});

test('editar horário e duração mantém o id (e a marcação)', async () => {
  const { sql } = banco();
  const cookie = await comSessao();

  await tratar(
    pedir('/dias/seg/atividades/seg-06:00', {
      metodo: 'PUT',
      cookie,
      corpo: { horario: '06:00', titulo: 'Acordar', categoria: 'bemEstar' },
    }),
    env,
    sql,
  );
  await tratar(
    pedir('/atividades/2026-10-19/seg-06:00', { metodo: 'PUT', cookie, corpo: { concluida: true } }),
    env,
    sql,
  );
  await tratar(
    pedir('/dias/seg/atividades/seg-06:00', {
      metodo: 'PUT',
      cookie,
      corpo: { horario: '05:45', titulo: 'Acordar cedo', duracaoMinutos: 10, categoria: 'bemEstar' },
    }),
    env,
    sql,
  );

  const semana = await (await tratar(pedir('/semana', { cookie }), env, sql)).json();
  const atividade = semana.dias[0].atividades[0];
  assert.equal(atividade.horario, '05:45');
  assert.equal(atividade.duracaoMinutos, 10);
  assert.deepEqual(semana.concluidas['2026-10-19'], ['seg-06:00']);
});

test('DELETE da atividade também remove a marcação', async () => {
  const { sql, estado } = banco();
  const cookie = await comSessao();

  await tratar(
    pedir('/dias/ter/atividades/ter-11:00', {
      metodo: 'PUT',
      cookie,
      corpo: { horario: '11:00', titulo: 'Academia', categoria: 'movimento', fixo: true },
    }),
    env,
    sql,
  );
  await tratar(
    pedir('/atividades/2026-10-20/ter-11:00', { metodo: 'PUT', cookie, corpo: { concluida: true } }),
    env,
    sql,
  );
  assert.ok(estado.marcadas.has('2026-10-20|ter-11:00'));

  const r = await tratar(pedir('/dias/ter/atividades/ter-11:00', { metodo: 'DELETE', cookie }), env, sql);
  assert.equal(r.status, 200);
  assert.equal(estado.atividades.size, 0);
  assert.equal(estado.marcadas.has('2026-10-20|ter-11:00'), false);
});

test('atividade inválida é recusada com 400 (dia, horário, categoria, duração)', async () => {
  const { sql } = banco();
  const cookie = await comSessao();
  const enviar = (corpo, caminho = '/dias/seg/atividades/x') =>
    tratar(pedir(caminho, { metodo: 'PUT', cookie, corpo }), env, sql);

  const base = { horario: '09:00', titulo: 'X', categoria: 'casa' };
  assert.equal((await enviar({ ...base, horario: '25:00' })).status, 400);
  assert.equal((await enviar({ ...base, categoria: 'outra' })).status, 400);
  assert.equal((await enviar({ ...base, titulo: '' })).status, 400);
  assert.equal((await enviar({ ...base, duracaoMinutos: 0 })).status, 400);
  assert.equal((await enviar(base, '/dias/xyz/atividades/x')).status, 400);
});

test('leitor não cria atividade no plano', async () => {
  const { sql } = banco({ papel: 'leitor' });
  const r = await tratar(
    pedir('/dias/seg/atividades/seg-07:00', {
      metodo: 'PUT',
      cookie: await comSessao(),
      corpo: { horario: '07:00', titulo: 'X', categoria: 'casa' },
    }),
    env,
    sql,
  );
  assert.equal(r.status, 403);
});

test('PUT /semana sem dias não apaga o plano existente', async () => {
  const { sql, estado } = banco();
  const cookie = await comSessao();

  await tratar(
    pedir('/dias/seg/atividades/seg-09:00', {
      metodo: 'PUT',
      cookie,
      corpo: { horario: '09:00', titulo: 'Estudo', categoria: 'estudo' },
    }),
    env,
    sql,
  );
  // Importação de backup v2: só marcações e cômodos.
  const r = await tratar(
    pedir('/semana', {
      metodo: 'PUT',
      cookie,
      corpo: { concluidas: {}, comodos: [{ id: 'sala', nome: 'Sala' }] },
    }),
    env,
    sql,
  );
  assert.equal(r.status, 200);
  assert.equal(estado.atividades.size, 1);
});

test('PUT /semana com dias substitui o plano inteiro', async () => {
  const { sql, estado } = banco();
  const cookie = await comSessao();

  await tratar(
    pedir('/dias/seg/atividades/seg-09:00', {
      metodo: 'PUT',
      cookie,
      corpo: { horario: '09:00', titulo: 'Antiga', categoria: 'casa' },
    }),
    env,
    sql,
  );

  const r = await tratar(
    pedir('/semana', {
      metodo: 'PUT',
      cookie,
      corpo: {
        marcadas: [],
        comodos: [],
        dias: [
          {
            chave: 'dom',
            atividades: [
              { id: 'dom-08:00', horario: '08:00', titulo: 'Nova', categoria: 'bemEstar', duracaoMinutos: 30 },
            ],
          },
        ],
      },
    }),
    env,
    sql,
  );
  assert.equal(r.status, 200);
  assert.deepEqual([...estado.atividades.values()].map((a) => a.id), ['dom-08:00']);

  const semana = await (await tratar(pedir('/semana', { cookie }), env, sql)).json();
  assert.equal(semana.dias[0].atividades[0].titulo, 'Nova');
  assert.equal(semana.dias[0].atividades[0].duracaoMinutos, 30);
});

test('sem plano gravado, GET /semana não manda dias (o app migra)', async () => {
  const { sql } = banco();
  const semana = await (await tratar(pedir('/semana', { cookie: await comSessao() }), env, sql)).json();
  assert.equal(semana.dias, undefined);
  assert.deepEqual(semana.concluidas, {});
});
