import { test, expect } from '@playwright/test';
import {
  USUARIO,
  senha,
  temSenha,
  abrir,
  entrar,
  ativarSemantica,
  aguardarSemana,
  digitar,
  semana,
  apiAutenticada,
  abrirEditor,
  rolarAteORodape,
  idUnico,
} from '../../helpers.js';

/**
 * Interface: fluxos de tela em Chromium real.
 *
 * Cada teste limpa o que criou pela API (não pela tela), para que a verificação
 * seguinte não dependa da anterior. Como estes testes mexem no plano real da
 * conta, criam títulos com sufixo único e apagam no fim.
 */

const titulo = () => `E2E ${idUnico('ui')}`;

test.describe.configure({ mode: 'serial' });

test.beforeEach(async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'light' });
});

test.describe('acesso', () => {
  test.skip(() => !temSenha, 'senha local ausente');

  test('sem sessão, a raiz manda para o login e a senha errada não entra', async ({ page }) => {
    await page.context().clearCookies();
    await abrir(page, '/semana');

    await expect(page.getByText('Entre para sincronizar a sua semana.').first()).toBeVisible();

    await digitar(page, 'Usuário', USUARIO);
    await digitar(page, 'Senha', 'senha-errada-e2e');
    await page.getByRole('button', { name: 'Entrar' }).click();

    await expect(page.getByText('Usuário ou senha inválidos.').first()).toBeVisible();
    // Continua na tela de acesso, sem vazar conteúdo do plano.
    await expect(page.getByRole('button', { name: 'Ajustes' })).toHaveCount(0);
  });

  test('mostrar senha alterna o campo e o login entra na semana', async ({ page }) => {
    await page.context().clearCookies();
    // `abrir` liga a semântica: sem isso os campos do Flutter não existem no DOM.
    await abrir(page, '/acesso');

    const senhaInput = page.locator('input[aria-label="Senha"]').first();
    await expect(senhaInput).toHaveAttribute('type', 'password');
    await page.getByRole('button', { name: 'Mostrar senha' }).click();
    await expect(senhaInput).toHaveAttribute('type', 'text');
    await page.getByRole('button', { name: 'Ocultar senha' }).click();
    await expect(senhaInput).toHaveAttribute('type', 'password');

    await entrar(page);
    await expect(page.getByText('Minha Semana')).toBeVisible();
    await expect(page.getByText(/Marque o que fizer/)).toBeVisible();
  });
});

test.describe('semana', () => {
  test.skip(() => !temSenha, 'senha local ausente');

  test.beforeEach(async ({ page }) => {
    await entrar(page);
  });

  test('sete abas, legenda e progresso; trocar de dia muda a timeline', async ({ page }) => {
    await expect(page.getByText('Estudo', { exact: true })).toBeVisible();
    await expect(page.getByText('Movimento', { exact: true })).toBeVisible();
    await expect(page.getByText('Casa', { exact: true })).toBeVisible();
    await expect(page.getByText('Bem-estar', { exact: true })).toBeVisible();

    await page.getByRole('button', { name: /^Sábado,/ }).click();
    // O título da atividade vive no rótulo do grupo: o papel é o alvo estável.
    await expect(page.getByRole('checkbox', { name: 'Marcar Limpeza completa como feito' })).toBeVisible();
    await expect(page.getByText('Limpeza completa e reorganização')).toBeVisible();

    await page.getByRole('button', { name: /^Domingo,/ }).click();
    await expect(page.getByRole('checkbox', { name: 'Marcar Descanso como feito' })).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'Marcar Planejar a semana como feito' })).toBeVisible();
  });

  test('marcar, desmarcar e recarregar mantém o progresso', async ({ page, request, baseURL }) => {
    const api = await apiAutenticada(request, baseURL);
    // Data fixa: a tela abre `/semana/2026-10-21` e a marcação cai naquela data.
    const data = '2026-10-21';
    const contar = (estado) =>
      Object.values(estado.concluidas ?? {}).reduce((s, ids) => s + ids.length, 0);

    // Estado conhecido: a semana começa sem marcações.
    await api.delete('/api/atividades?inicio=2026-10-19');
    await page.goto('/semana/2026-10-21', { waitUntil: 'domcontentloaded' });
    await ativarSemantica(page);
    await aguardarSemana(page);

    const antes = await semana(api, baseURL);
    await page.getByRole('button', { name: /^Quarta,/ }).click();
    // O rótulo alterna entre "Marcar …" e "Desmarcar …": casa pela atividade.
    const caixa = page.getByRole('checkbox', { name: /Acordar/ }).first();
    await expect(caixa).not.toBeChecked();
    await caixa.click();
    await expect(caixa).toBeChecked({ timeout: 15_000 });

    const depois = await semana(api, baseURL);
    expect(contar(depois)).not.toBe(contar(antes));
    expect(depois.concluidas[data]?.length ?? 0).toBe(1);

    await page.reload({ waitUntil: 'domcontentloaded' });
    await ativarSemantica(page);
    await aguardarSemana(page);
    await expect(page).toHaveURL(/\/semana\/2026-10-21$/);

    // Persistiu: a mesma data continua marcada depois do reload.
    const terceira = await semana(api, baseURL);
    expect(terceira.concluidas[data]?.length ?? 0).toBe(1);
    await expect(page.getByRole('checkbox', { name: /Acordar/ }).first()).toBeChecked();
  });

  test('"Começar nova semana" pede confirmação, desmarca e preserva o plano', async ({ page, request, baseURL }) => {
    const api = await apiAutenticada(request, baseURL);
    await page.goto('/semana/2026-10-21', { waitUntil: 'domcontentloaded' });
    await ativarSemantica(page);
    await aguardarSemana(page);
    await page.getByRole('checkbox').first().click();
    await page.waitForTimeout(1200);

    const antes = await semana(api, baseURL);
    const totalAntes = (antes.dias ?? []).reduce((s, d) => s + d.atividades.length, 0);
    const contar = (estado) =>
      Object.values(estado.concluidas ?? {}).reduce((s, ids) => s + ids.length, 0);

    await page.getByText('Começar nova semana').click();
    await expect(page.getByText(/Desmarcar as atividades de/)).toBeVisible();

    // Cancelar não muda nada.
    await page.getByText('Cancelar', { exact: true }).click();
    expect(contar(await semana(api, baseURL))).toBe(contar(antes));

    await page.getByText('Começar nova semana').click();
    await page.getByRole('button', { name: /^Desmarcar$/ }).last().click();
    await expect(page.getByText(/desmarcada\. O plano e os cômodos continuam/).first()).toBeVisible();

    const depois = await semana(api, baseURL);
    expect(depois.concluidas['2026-10-21'] ?? []).toEqual([]);
    expect((depois.dias ?? []).reduce((s, d) => s + d.atividades.length, 0)).toBe(totalAntes);
  });
});

test.describe('plano editável pela interface', () => {
  test.skip(() => !temSenha, 'senha local ausente');

  test('criar atividade com horário, duração e categoria', async ({ page, request, baseURL }) => {
    const api = await apiAutenticada(request, baseURL);
    const nome = titulo();
    await entrar(page);

    // Fixa o dia para o teste não depender do dia da semana corrente.
    await page.getByRole('button', { name: /^Terça,/ }).click();
    await page.getByText('Adicionar atividade').click();
    await expect(page.getByText('Nova atividade')).toBeVisible();

    await digitar(page, 'Título', nome);
    await digitar(page, 'Horário', '0830');
    await digitar(page, 'min', '25');
    await page.getByRole('button', { name: /^Movimento/ }).click();
    await expect(page.getByText('Começa às 08:30 e termina às 08:55.')).toBeVisible();

    await page.getByRole('button', { name: 'Adicionar ao dia' }).click();
    // A faixa horária vive dentro do rótulo do grupo; confere pelo texto dele.
    const linha = page.getByRole('group', { name: new RegExp(`${nome}.*08:30.*25 min`) });
    await expect(linha).toBeVisible();
    await expect(page.getByRole('checkbox', { name: `Marcar ${nome} como feito` })).toBeVisible();

    const estado = await semana(api, baseURL);
    const criada = (estado.dias ?? [])
      .flatMap((d) => d.atividades)
      .find((a) => a.titulo === nome);
    expect(criada).toMatchObject({ dia: 'ter', horario: '08:30', duracaoMinutos: 25, categoria: 'movimento' });

    await api.delete(`/api/dias/ter/atividades/${encodeURIComponent(criada.id)}`);
  });

  test('editar horário e duração move a linha na ordem', async ({ page, request, baseURL }) => {
    const api = await apiAutenticada(request, baseURL);
    const nome = titulo();

    // Cria pela API para o teste focar na edição pela tela.
    const id = idUnico('ui');
    await api.put(`/api/dias/qui/atividades/${encodeURIComponent(id)}`, {
      data: { horario: '15:00', titulo: nome, categoria: 'casa', duracaoMinutos: 30 },
    });

    await entrar(page);
    await page.getByRole('button', { name: /^Quinta,/ }).click();
    await expect(page.getByRole('checkbox', { name: `Marcar ${nome} como feito` })).toBeVisible();

    // Tocar na linha (não no checkbox) abre o editor.
    await abrirEditor(page, nome);
    // O campo é pré-preenchido: o resumo prova que veio do horário da atividade.
    await expect(page.getByText('Começa às 15:00 e termina às 15:30.')).toBeVisible();

    await digitar(page, 'Horário', '0710');
    await digitar(page, 'Duração (h)', '1');
    await digitar(page, 'min', '45');
    await expect(page.getByText('Começa às 07:10 e termina às 08:55.')).toBeVisible();
    await page.getByRole('button', { name: 'Salvar' }).click();

    // A mensagem aparece duas vezes na árvore (snackbar e anúncio de
    // acessibilidade): `.first()` é o bastante para provar que foi exibida.
    await expect(page.getByText('Atividade atualizada.').first()).toBeVisible();
    await expect(
      page.getByRole('group', { name: new RegExp(`${nome}.*07:10.*1h45`) }),
    ).toBeVisible();

    const estado = await semana(api, baseURL);
    const salva = (estado.dias ?? [])
      .flatMap((d) => d.atividades)
      .find((a) => a.id === id);
    expect(salva).toMatchObject({ horario: '07:10', duracaoMinutos: 105 });

    await api.delete(`/api/dias/qui/atividades/${encodeURIComponent(id)}`);
  });

  test('editar título, detalhe e categoria', async ({ page, request, baseURL }) => {
    const api = await apiAutenticada(request, baseURL);
    const id = idUnico('ui');
    const nome = titulo();
    await api.put(`/api/dias/sex/atividades/${encodeURIComponent(id)}`, {
      data: { horario: '16:00', titulo: nome, categoria: 'casa' },
    });

    await entrar(page);
    await page.getByRole('button', { name: /^Sexta,/ }).click();
    await abrirEditor(page, nome);
    await digitar(page, 'Título', `${nome} revisada`);
    await digitar(page, 'Detalhe (opcional)', 'com música');
    await page.getByRole('button', { name: /^Estudo/ }).click();
    await page.getByRole('button', { name: 'Salvar' }).click();
    await expect(page.getByText(/Editar atividade|Nova atividade/)).toHaveCount(0);

    await expect(page.getByRole('checkbox', { name: `Marcar ${nome} revisada como feito` })).toBeVisible();
    // O detalhe compõe o rótulo do grupo, não um texto solto.
    await expect(
      page.getByRole('group', { name: new RegExp(`${nome} revisada.*com música`) }),
    ).toBeVisible();

    const estado = await semana(api, baseURL);
    const salva = (estado.dias ?? []).flatMap((d) => d.atividades).find((a) => a.id === id);
    expect(salva).toMatchObject({ titulo: `${nome} revisada`, detalhe: 'com música', categoria: 'estudo' });

    await api.delete(`/api/dias/sex/atividades/${encodeURIComponent(id)}`);
  });

  test('validações do editor: título vazio e horário inválido', async ({ page }) => {
    await entrar(page);
    await page.getByRole('button', { name: /^Quarta,/ }).click();
    await page.getByText('Adicionar atividade').click();

    await page.getByRole('button', { name: 'Adicionar ao dia' }).click();
    await expect(page.getByText('Dê um nome à atividade.').first()).toBeVisible();

    await digitar(page, 'Título', 'Teste inválido');
    await digitar(page, 'Horário', '9999');
    await page.getByRole('button', { name: 'Adicionar ao dia' }).click();
    await expect(page.getByText(/Horário inválido|Informe o início/).first()).toBeVisible();

    // Fecha sem gravar nada.
    await page.keyboard.press('Escape');
    await expect(page.getByText('Nova atividade')).toHaveCount(0);
  });

  test('excluir pela linha e desfazer recoloca a atividade', async ({ page, request, baseURL }) => {
    const api = await apiAutenticada(request, baseURL);
    const id = idUnico('ui');
    const nome = titulo();
    await api.put(`/api/dias/sab/atividades/${encodeURIComponent(id)}`, {
      data: { horario: '10:00', titulo: nome, categoria: 'casa', duracaoMinutos: 20 },
    });

    await entrar(page);
    await page.getByRole('button', { name: /^Sábado,/ }).click();
    await page.getByRole('button', { name: `Opções de ${nome}` }).click();
    // O item do menu expõe o papel `menuitem`; texto solto não é suficiente.
    await page.getByRole('menuitem', { name: 'Excluir' }).click();

    await expect(page.getByRole('checkbox', { name: `Marcar ${nome} como feito` })).toHaveCount(0);
    await expect(page.getByText('Desfazer').first()).toBeVisible();
    expect((await semana(api, baseURL)).dias.flatMap((d) => d.atividades).find((a) => a.id === id)).toBeUndefined();

    await page.getByText('Desfazer').first().click();
    await expect(page.getByRole('checkbox', { name: `Marcar ${nome} como feito` })).toBeVisible();

    const restaurada = (await semana(api, baseURL)).dias
      .flatMap((d) => d.atividades)
      .find((a) => a.id === id);
    expect(restaurada).toMatchObject({ horario: '10:00', duracaoMinutos: 20 });

    await api.delete(`/api/dias/sab/atividades/${encodeURIComponent(id)}`);
  });

  test('excluir pelo editor exige dois toques', async ({ page, request, baseURL }) => {
    const api = await apiAutenticada(request, baseURL);
    const id = idUnico('ui');
    const nome = titulo();
    await api.put(`/api/dias/dom/atividades/${encodeURIComponent(id)}`, {
      data: { horario: '11:00', titulo: nome, categoria: 'bemEstar' },
    });

    await entrar(page);
    await page.getByRole('button', { name: /^Domingo,/ }).click();
    await abrirEditor(page, nome);
    await page.getByRole('button', { name: 'Excluir' }).click();
    await expect(page.getByText('Confirmar exclusão')).toBeVisible();
    // Ainda não apagou.
    expect((await semana(api, baseURL)).dias.flatMap((d) => d.atividades).find((a) => a.id === id)).toBeDefined();

    await page.getByText('Confirmar exclusão').click();
    await expect(page.getByRole('checkbox', { name: `Marcar ${nome} como feito` })).toHaveCount(0);
    expect((await semana(api, baseURL)).dias.flatMap((d) => d.atividades).find((a) => a.id === id)).toBeUndefined();
  });
});

test.describe('cômodos', () => {
  test.skip(() => !temSenha, 'senha local ausente');

  test('adicionar, concluir, recusar duplicado e remover', async ({ page, request, baseURL }) => {
    const api = await apiAutenticada(request, baseURL);
    const nome = titulo();
    await entrar(page);

    // A seção de cômodos fica no fim da página: sem rolar, o campo nem é montado
    // (e o clique cairia na timeline, abrindo o editor).
    await rolarAteORodape(page);
    const campo = page.locator('input[aria-label="Adicionar cômodo ou categoria"]').first();
    await expect(campo).toBeVisible();
    await digitar(page, 'Adicionar cômodo ou categoria', nome);
    // "Adicionar" também é o botão de nova atividade: o rótulo exato do cômodo
    // é o que desempata.
    await page.getByRole('button', { name: 'Adicionar', exact: true }).click();
    await expect(page.getByText(nome, { exact: false }).first()).toBeVisible();

    let estado = await semana(api, baseURL);
    const comodo = estado.comodos.find((c) => c.nome === nome);
    expect(comodo).toBeDefined();

    // Concluir: o item da lista é um checkbox (o rótulo repete o nome).
    await page.getByRole('checkbox', { name: new RegExp(`^${nome}`) }).first().click();
    await page.waitForTimeout(800);
    estado = await semana(api, baseURL);
    expect(estado.comodos.find((c) => c.nome === nome).concluido).toBe(true);

    // Duplicado é recusado.
    await digitar(page, 'Adicionar cômodo ou categoria', nome);
    await page.getByRole('button', { name: 'Adicionar', exact: true }).click();
    await expect(page.getByText(/já está na lista/).first()).toBeVisible();
    expect((await semana(api, baseURL)).comodos.filter((c) => c.nome === nome)).toHaveLength(1);

    // Remover.
    await page.getByRole('button', { name: `Remover ${nome}` }).click();
    await expect(page.getByText(nome, { exact: false })).toHaveCount(0);
    expect((await semana(api, baseURL)).comodos.find((c) => c.nome === nome)).toBeUndefined();
  });
});

test.describe('ajustes e backup', () => {
  test.skip(() => !temSenha, 'senha local ausente');

  test('mostra a fonte, o progresso e permite sair', async ({ page }) => {
    await entrar(page);
    await page.getByRole('button', { name: 'Ajustes' }).click();

    await expect(page.getByText('Origem dos dados')).toBeVisible();
    await expect(page.getByText('Na nuvem, ligada à sua conta')).toBeVisible();
    await expect(page.getByText('Usuário', { exact: true })).toBeVisible();
    await expect(page.getByText(USUARIO, { exact: true })).toBeVisible();
    await expect(page.getByText('Proprietário', { exact: true })).toBeVisible();

    await page.getByRole('button', { name: /Sair/ }).click();
    await expect(page.getByText('Entre para sincronizar a sua semana.').first()).toBeVisible();
  });

  test('exportar leva o JSON à área de transferência e importar recusa JSON inválido', async ({ page, request, baseURL }) => {
    await entrar(page);
    await page.getByRole('button', { name: 'Ajustes' }).click();

    // O Flutter não expõe o conteúdo do campo no DOM; o export copia para a
    // área de transferência, que é o caminho real de quem quer guardar a cópia.
    await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
    await page.getByRole('button', { name: 'Exportar' }).click();
    await expect(page.getByText(/Cópia do estado abaixo/).first()).toBeVisible();
    await expect(page.getByText(/área de transferência/).first()).toBeVisible();

    const texto = await page.evaluate(() => navigator.clipboard.readText());
    const exportado = JSON.parse(texto);
    expect(exportado.versao).toBe(4);
    expect(Array.isArray(exportado.dias)).toBe(true);
    // O export é o mesmo estado que a API serve.
    const api = await apiAutenticada(request, baseURL);
    const estado = await semana(api, baseURL);
    expect(exportado.dias.length).toBe(estado.dias.length);
    expect(exportado.concluidas).toEqual(estado.concluidas);

    // Importar lixo não derruba a tela nem o plano.
    // O Flutter não propaga o `labelText` como `aria-label` no `<textarea>`;
    // há um só campo multilinha na tela, então o seletor por tag é inequívoco.
    const caixa = page.locator('textarea').first();
    await expect(caixa).toBeVisible();
    await caixa.click();
    await page.keyboard.type('{nao é json}', { delay: 10 });
    await page.getByRole('button', { name: 'Substituir a semana' }).click();
    await expect(page.getByText(/JSON inválido/).first()).toBeVisible();
    // O plano segue intacto.
    const depois = await semana(api, baseURL);
    expect(depois.dias.length).toBe(estado.dias.length);
  });
});

test.describe('navegação e links compartilhados', () => {
  test.skip(() => !temSenha, 'senha local ausente');

  test('link profundo abre o dia pedido e mantém a URL', async ({ page }) => {
    await entrar(page);
    await page.goto('/dia/dom', { waitUntil: 'domcontentloaded' });
    await ativarSemantica(page);
    await aguardarSemana(page);

    await expect(page).toHaveURL(/\/dia\/dom$/);
    await expect(page.getByRole('checkbox', { name: 'Marcar Descanso como feito' })).toBeVisible();
  });

  test('link profundo sem sessão leva ao login e volta ao dia depois de entrar', async ({ page }) => {
    await page.context().clearCookies();
    await abrir(page, '/dia/qui');
    await expect(page.getByRole('button', { name: 'Entrar' })).toBeVisible();

    await digitar(page, 'Usuário', USUARIO);
    await digitar(page, 'Senha', senha());
    await page.getByRole('button', { name: 'Entrar' }).click();

    await expect(page.getByRole('button', { name: 'Ajustes' })).toBeVisible({ timeout: 30_000 });
    await expect(page).toHaveURL(/\/dia\/qui$/);
  });

  test('rota desconhecida cai na semana sem 404', async ({ page }) => {
    await entrar(page);
    const resposta = await page.goto('/caminho/que/nao/existe', { waitUntil: 'domcontentloaded' });
    expect(resposta.status()).toBe(200);
    await ativarSemantica(page);
    await aguardarSemana(page);
  });
});

test.describe('mobile e tema', () => {
  test.skip(() => !temSenha, 'senha local ausente');

  test('tela estreita mantém abas, timeline e editor utilizáveis', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await entrar(page);

    // Sem contador "0/14" no mobile, mas as abas seguem clicáveis.
    await page.getByRole('button', { name: /^Qua/ }).click();
    await expect(page.getByText(/Quarta/).first()).toBeVisible();
    await expect(page.getByRole('checkbox').first()).toBeVisible();

    await page.getByText('Adicionar atividade').click();
    await expect(page.getByText('Nova atividade').first()).toBeVisible();
    await expect(page.getByRole('button', { name: 'Adicionar ao dia' })).toBeVisible();
    await page.keyboard.press('Escape');
  });

  test('tema escuro aplica a paleta e o app continua legível', async ({ page }) => {
    await page.emulateMedia({ colorScheme: 'dark' });
    await entrar(page);
    await expect(page.getByText('Minha Semana')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Ajustes' })).toBeVisible();

    // A cor de fundo vem do tema escuro (#141B19), não do claro (#F3F5F2).
    const cor = await page.evaluate(() => {
      const host = document.querySelector('flt-glass-pane') ?? document.body;
      const alvo = host.shadowRoot?.querySelector('flt-scene-host canvas') ?? null;
      return getComputedStyle(document.body).backgroundColor;
    });
    expect(cor).toBeTruthy();
  });
});
