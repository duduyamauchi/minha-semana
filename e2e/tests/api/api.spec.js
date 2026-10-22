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
    for (const caminho of ['/', '/semana', '/dia/dom', '/acesso', '/ajustes']) {
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
    expect((await request.put('/api/atividades/seg-06:00', { data: { concluida: true } })).status()).toBe(401);
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
    expect(estado.versao).toBe(3);
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

    await request.put(`/api/dias/seg/atividades/${encodeURIComponent(id)}`, {
      data: { horario: '05:59', titulo, categoria: 'bemEstar' },
    });
    expect((await request.put(`/api/atividades/${encodeURIComponent(id)}`, { data: { concluida: true } })).status()).toBe(200);

    // Muda o horário: o id não muda, então a marcação continua.
    await request.put(`/api/dias/seg/atividades/${encodeURIComponent(id)}`, {
      data: { horario: '06:05', titulo, categoria: 'bemEstar', duracaoMinutos: 10 },
    });
    let estado = await semana(request, baseURL);
    expect(estado.marcadas).toContain(id);

    // Excluir a atividade remove a marcação: senão o percentual contaria um id órfão.
    await request.delete(`/api/dias/seg/atividades/${encodeURIComponent(id)}`);
    estado = await semana(request, baseURL);
    expect(estado.marcadas).not.toContain(id);
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
    expect(depois.marcadas).toEqual([]);
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
      data: { marcadas: [], comodos: antes.comodos },
    });
    expect(r.status()).toBe(200);

    const depois = await semana(request, baseURL);
    expect((depois.dias ?? []).reduce((s, d) => s + d.atividades.length, 0)).toBe(totalAntes);
  });
});
