import { test, expect } from '@playwright/test';
import { USUARIO, senha, temSenha, semana, procurar, idUnico } from '../../helpers.js';

/**
 * API: contrato, autorização e ciclo de vida dos dados.
 *
 * Estes testes não usam navegador. Cada um cria o próprio registro e o remove no
 * fim, para não deixar resíduo no plano real.
 */

const DIAS = ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'];

test.describe('API — público e autorização', () => {
  test('rotas do app respondem 200 e mantêm a URL', async ({ request, baseURL }) => {
    for (const caminho of [
      '/',
      '/semana',
      '/semana/2026-10-21',
      '/dia/dom',
      '/calendario',
      '/acesso',
      '/ajustes',
    ]) {
      const r = await request.get(caminho, { maxRedirects: 0 });
      expect(r.status(), caminho).toBe(200);
      expect(r.headers()['content-type']).toContain('text/html');
    }
  });

  test('sem sessão, o plano é 401', async ({ request }) => {
    expect((await request.get('/api/semana')).status()).toBe(401);
    expect(
      (await request.put('/api/dias/seg/atividades/x', { data: { horario: '08:00', titulo: 'x' } })).status(),
    ).toBe(401);
    expect((await request.delete('/api/dias/seg/atividades/x')).status()).toBe(401);
    expect(
      (await request.put('/api/atividades/2026-10-21/seg-06:00', { data: { concluida: true } })).status(),
    ).toBe(401);
    expect((await request.delete('/api/atividades')).status()).toBe(401);
    expect((await request.put('/api/comodos/sala', { data: { nome: 'Sala' } })).status()).toBe(401);
    expect((await request.get('/api/eventos')).status()).toBe(401);
  });

  test('login errado responde 401 com a mesma mensagem de usuário inexistente', async ({ request }) => {
    const errada = await request.post('/api/sessao', { data: { usuario: USUARIO, senha: 'senha-errada-e2e' } });
    expect(errada.status()).toBe(401);
    const corpo = await errada.json();
    expect(corpo.erro).toBe('Usuário ou senha inválidos.');

    const inexistente = await request.post('/api/sessao', { data: { usuario: 'ninguem-e2e', senha: 'x' } });
    expect(inexistente.status()).toBe(401);
    expect((await inexistente.json()).erro).toBe(corpo.erro);
  });

  test('cabeçalhos de segurança no HTML', async ({ request }) => {
    const r = await request.get('/');
    const h = r.headers();
    expect(h['strict-transport-security']).toContain('max-age=');
    expect(h['x-frame-options']).toBe('DENY');
    expect(h['content-security-policy']).toContain("default-src 'self'");
    // `wasm-unsafe-eval` é necessário ao CanvasKit e não abre `eval` clássico;
    // o que não pode existir é a diretiva `'unsafe-eval'` entre aspas.
    expect(h['content-security-policy']).not.toContain("'unsafe-eval'");
  });

  test('preflight libera a própria origem e recusa outra', async ({ request, baseURL }) => {
    const proprio = await request.fetch('/api/semana', {
      method: 'OPTIONS',
      headers: { origin: baseURL },
    });
    expect(proprio.status()).toBe(204);
    expect(proprio.headers()['access-control-allow-origin']).toBe(baseURL);

    const intruso = await request.fetch('/api/semana', {
      method: 'OPTIONS',
      headers: { origin: 'https://exemplo.invalido' },
    });
    expect(intruso.status()).toBe(403);
    expect(intruso.headers()['access-control-allow-origin']).toBeUndefined();
  });
});

test.describe('API — plano editável', () => {
  test.skip(() => !temSenha, 'senha local ausente em ~/.segredos/minha-semana/senha.txt');

  test('ciclo completo: criar, ler, editar horário/duração, excluir', async ({ request, baseURL }) => {
    await request.post('/api/sessao', { data: { usuario: USUARIO, senha: senha() } });

    const id = idUnico('api');
    const titulo = `E2E ${id}`;
    const criar = await request.put(`/api/dias/qua/atividades/${encodeURIComponent(id)}`, {
      data: {
        horario: '06:20',
        titulo,
        detalhe: 'criado pelo teste e2e',
        duracaoMinutos: 20,
        categoria: 'movimento',
        fixo: true,
        prioridade: false,
      },
    });
    expect(criar.status()).toBe(200);
    const criada = (await criar.json()).atividade;
    expect(criada).toMatchObject({ id, dia: 'qua', horario: '06:20', duracaoMinutos: 20, fixo: true });

    let estado = await semana(request, baseURL);
    expect(estado.versao).toBe(4);
    expect(procurar(estado, titulo)).toMatchObject({ dia: 'qua', horario: '06:20', duracaoMinutos: 20 });

    // Editar mantém o id: a marcação, se houvesse, não se perderia.
    const editar = await request.put(`/api/dias/qua/atividades/${encodeURIComponent(id)}`, {
      data: { horario: '07:05', titulo: `${titulo} editada`, duracaoMinutos: 90, categoria: 'estudo' },
    });
    expect(editar.status()).toBe(200);
    estado = await semana(request, baseURL);
    const editada = procurar(estado, `${titulo} editada`);
    expect(editada).toMatchObject({ id, horario: '07:05', duracaoMinutos: 90, categoria: 'estudo' });

    const excluir = await request.delete(`/api/dias/qua/atividades/${encodeURIComponent(id)}`);
    expect(excluir.status()).toBe(200);
    estado = await semana(request, baseURL);
    expect(procurar(estado, `${titulo} editada`)).toBeNull();
  });

  test('validação recusa dia, horário, categoria, título e duração inválidos', async ({ request, baseURL }) => {
    await request.post('/api/sessao', { data: { usuario: USUARIO, senha: senha() } });
    const base = { horario: '08:00', titulo: 'Válido', categoria: 'casa' };
    const enviar = (corpo, caminho = '/api/dias/seg/atividades/valida-e2e') =>
      request.put(caminho, { data: corpo });

    expect((await enviar({ ...base, horario: '25:00' })).status()).toBe(400);
    expect((await enviar({ ...base, horario: '8h' })).status()).toBe(400);
    expect((await enviar({ ...base, categoria: 'inventada' })).status()).toBe(400);
    expect((await enviar({ ...base, titulo: '' })).status()).toBe(400);
    expect((await enviar({ ...base, duracaoMinutos: 0 })).status()).toBe(400);
    expect((await enviar({ ...base, duracaoMinutos: 5000 })).status()).toBe(400);
    expect((await enviar(base, '/api/dias/xyz/atividades/valida-e2e')).status()).toBe(400);
    expect((await enviar(base, '/api/dias/seg/atividades/id%20com%20espaco')).status()).toBe(400);

    // Nada disso pode ter entrado no plano.
    const estado = await semana(request, baseURL);
    const intrusas = (estado.dias ?? [])
      .flatMap((d) => d.atividades)
      .filter((a) => a.id === 'valida-e2e');
    expect(intrusas).toHaveLength(0);
  });

  test('corpo que não é JSON responde 400', async ({ request }) => {
    await request.post('/api/sessao', { data: { usuario: USUARIO, senha: senha() } });
    // `Buffer` garante corpo cru: passar uma string faria o Playwright
    // serializá-la como JSON válido (uma string), exercitando outro caminho.
    const r = await request.fetch('/api/dias/seg/atividades/x', {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      data: Buffer.from('{isso não é json'),
    });
    expect(r.status()).toBe(400);
    expect((await r.json()).erro).toBe('Corpo não é JSON válido.');
  });

  test('marcação sobrevive à edição e é removida junto com a atividade', async ({ request, baseURL }) => {
    await request.post('/api/sessao', { data: { usuario: USUARIO, senha: senha() } });
    const id = idUnico('marca');
    const titulo = `E2E ${id}`;

    const data = '2026-10-19';
    await request.put(`/api/dias/seg/atividades/${encodeURIComponent(id)}`, {
      data: { horario: '05:59', titulo, categoria: 'bemEstar' },
    });
    expect(
      (await request.put(`/api/atividades/${data}/${encodeURIComponent(id)}`, { data: { concluida: true } })).status(),
    ).toBe(200);

    // Muda o horário: o id não muda, então a marcação daquela data continua.
    await request.put(`/api/dias/seg/atividades/${encodeURIComponent(id)}`, {
      data: { horario: '06:05', titulo, categoria: 'bemEstar', duracaoMinutos: 10 },
    });
    let estado = await semana(request, baseURL);
    expect(estado.concluidas[data]).toContain(id);

    // Excluir a atividade remove a marcação: senão o percentual contaria um id órfão.
    await request.delete(`/api/dias/seg/atividades/${encodeURIComponent(id)}`);
    estado = await semana(request, baseURL);
    expect(estado.concluidas[data] ?? []).not.toContain(id);
    expect(procurar(estado, titulo)).toBeNull();
  });

  test('cômodos: criar, marcar e remover', async ({ request, baseURL }) => {
    await request.post('/api/sessao', { data: { usuario: USUARIO, senha: senha() } });
    const id = idUnico('comodo');

    expect((await request.put(`/api/comodos/${id}`, { data: { id, nome: `Cômodo ${id}` } })).status()).toBe(200);
    expect((await request.put(`/api/comodos/${id}`, { data: { id, nome: `Cômodo ${id}`, concluido: true } })).status()).toBe(200);

    let estado = await semana(request, baseURL);
    expect(estado.comodos.find((c) => c.id === id)).toMatchObject({ concluido: true });

    expect((await request.delete(`/api/comodos/${id}`)).status()).toBe(200);
    estado = await semana(request, baseURL);
    expect(estado.comodos.find((c) => c.id === id)).toBeUndefined();
  });

  test('semana vazia de marcações continua com o plano intacto', async ({ request, baseURL }) => {
    await request.post('/api/sessao', { data: { usuario: USUARIO, senha: senha() } });
    const antes = await semana(request, baseURL);
    const total = (antes.dias ?? []).reduce((s, d) => s + d.atividades.length, 0);
    expect(total).toBeGreaterThan(0);

    expect((await request.delete('/api/atividades')).status()).toBe(200);
    const depois = await semana(request, baseURL);
    expect(depois.concluidas).toEqual({});
    expect((depois.dias ?? []).reduce((s, d) => s + d.atividades.length, 0)).toBe(total);
  });

  test('telemetria chega ao banco e é legível pelo dono', async ({ request, baseURL }) => {
    await request.post('/api/sessao', { data: { usuario: USUARIO, senha: senha() } });
    const sessao = idUnico('ses');
    const nome = idUnico('evento');

    const envio = await request.post('/api/eventos', {
      data: {
        eventos: [
          { nome, quando: new Date().toISOString(), sessao, tela: '/e2e', valor: 3, propriedades: { e2e: true } },
        ],
      },
    });
    expect(envio.status()).toBe(201);
    expect((await envio.json()).recebidos).toBe(1);

    const lidos = await request.get('/api/eventos?limite=200');
    expect(lidos.status()).toBe(200);
    const corpo = await lidos.json();
    const evento = corpo.eventos.find((e) => e.nome === nome);
    expect(evento).toMatchObject({ sessao, tela: '/e2e', valor: 3 });
  });

  test('logout invalida a sessão', async ({ request }) => {
    await request.post('/api/sessao', { data: { usuario: USUARIO, senha: senha() } });
    expect((await request.get('/api/semana')).status()).toBe(200);
    expect((await request.delete('/api/sessao')).status()).toBe(200);
    expect((await request.get('/api/semana')).status()).toBe(401);
  });
});

test.describe('API — importação de backup', () => {
  test.skip(() => !temSenha, 'senha local ausente');

  test('PUT /semana sem `dias` preserva o plano (backup v2)', async ({ request, baseURL }) => {
    await request.post('/api/sessao', { data: { usuario: USUARIO, senha: senha() } });
    const antes = await semana(request, baseURL);
    const totalAntes = (antes.dias ?? []).reduce((s, d) => s + d.atividades.length, 0);

    const r = await request.put('/api/semana', {
      data: { concluidas: {}, comodos: antes.comodos },
    });
    expect(r.status()).toBe(200);

    const depois = await semana(request, baseURL);
    expect((depois.dias ?? []).reduce((s, d) => s + d.atividades.length, 0)).toBe(totalAntes);
  });
});


test.describe('API — semanas no calendário', () => {
  test.skip(() => !temSenha, 'senha local ausente');

  const marcar = (request, data, id, concluida = true) =>
    request.put(`/api/atividades/${data}/${encodeURIComponent(id)}`, { data: { concluida } });

  test('a mesma atividade em duas datas tem marcações independentes', async ({ request, baseURL }) => {
    await request.post('/api/sessao', { data: { usuario: USUARIO, senha: senha() } });

    expect((await marcar(request, '2026-10-21', 'qua-06:00')).status()).toBe(200);
    expect((await marcar(request, '2026-10-28', 'qua-06:00')).status()).toBe(200);

    const estado = await semana(request, baseURL);
    expect(estado.concluidas['2026-10-21']).toContain('qua-06:00');
    expect(estado.concluidas['2026-10-28']).toContain('qua-06:00');

    // Desmarcar uma data não afeta a outra.
    expect((await marcar(request, '2026-10-21', 'qua-06:00', false)).status()).toBe(200);
    const depois = await semana(request, baseURL);
    expect(depois.concluidas['2026-10-21'] ?? []).not.toContain('qua-06:00');
    expect(depois.concluidas['2026-10-28']).toContain('qua-06:00');

    await request.delete(`/api/atividades/${encodeURIComponent('2026-10-28')}/qua-06:00`);
  });

  test('data inválida na rota é 400', async ({ request }) => {
    await request.post('/api/sessao', { data: { usuario: USUARIO, senha: senha() } });
    for (const data of ['ontem', '2026-13-01', '2026-02-31', '19-10-2026']) {
      const r = await request.put(`/api/atividades/${encodeURIComponent(data)}/qua-06:00`, {
        data: { concluida: true },
      });
      expect(r.status(), data).toBe(400);
    }
  });

  test('limpar uma semana preserva as outras', async ({ request, baseURL }) => {
    await request.post('/api/sessao', { data: { usuario: USUARIO, senha: senha() } });
    const alvo = '2026-11-04';
    const vizinha = '2026-11-11';

    await marcar(request, alvo, 'qua-06:00');
    await marcar(request, vizinha, 'qua-06:00');

    const r = await request.delete(`/api/atividades?inicio=2026-11-02`);
    expect(r.status()).toBe(200);
    expect((await r.json()).escopo).toBe('semana');

    const estado = await semana(request, baseURL);
    expect(estado.concluidas[alvo] ?? []).not.toContain('qua-06:00');
    expect(estado.concluidas[vizinha]).toContain('qua-06:00');

    await request.delete(`/api/atividades/${vizinha}/qua-06:00`);
  });

  test('PUT /semana importa um estado com datas', async ({ request, baseURL }) => {
    await request.post('/api/sessao', { data: { usuario: USUARIO, senha: senha() } });
    const antes = await semana(request, baseURL);

    const r = await request.put('/api/semana', {
      data: {
        concluidas: { '2026-10-20': ['ter-22:00'], '2026-10-22': ['qui-06:00'] },
        comodos: antes.comodos,
      },
    });
    expect(r.status()).toBe(200);

    const depois = await semana(request, baseURL);
    expect(depois.concluidas).toEqual({
      '2026-10-20': ['ter-22:00'],
      '2026-10-22': ['qui-06:00'],
    });
    // O plano não foi tocado.
    expect(depois.dias).toBeDefined();
    expect((depois.dias ?? []).reduce((s, d) => s + d.atividades.length, 0)).toBeGreaterThan(0);

    await request.delete('/api/atividades');
  });
});
