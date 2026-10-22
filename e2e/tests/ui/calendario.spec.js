import { test, expect } from '@playwright/test';
import {
  USUARIO,
  senha,
  temSenha,
  ativarSemantica,
  entrar,
  aguardarSemana,
  semana,
  apiAutenticada,
} from '../../helpers.js';

/**
 * Calendário no navegador: date picker, navegação por semana e a prancha dos
 * sete dias.
 *
 * A data é fixa (`2026-10-21`) em todas as navegações: a suíte não pode depender
 * do dia em que roda, e as marcações precisam de uma data previsível.
 */

const DATA = '2026-10-21';

test.describe.configure({ mode: 'serial' });

test.describe('semana por data', () => {
  test.skip(() => !temSenha, 'senha local ausente');

  test('link com data abre aquela semana e mostra as sete datas', async ({ page }) => {
    await entrar(page);
    await page.goto(`/semana/${DATA}`, { waitUntil: 'domcontentloaded' });
    await ativarSemantica(page);
    await aguardarSemana(page);

    await expect(page).toHaveURL(new RegExp(`/semana/${DATA}$`));
    await expect(page.getByText('19 a 25 de outubro')).toBeVisible();
    await expect(page.getByText(/Semana 43/)).toBeVisible();

    // Cada aba carrega a data: 19 a 25.
    for (const [dia, numero] of [
      ['Segunda', '19'],
      ['Terça', '20'],
      ['Quarta', '21'],
      ['Quinta', '22'],
      ['Sexta', '23'],
      ['Sábado', '24'],
      ['Domingo', '25'],
    ]) {
      await expect(
        page.getByRole('button', { name: new RegExp(`^${dia}, ${numero}/10/2026`) }),
      ).toBeVisible();
    }
    // "Quarta, 21/10" aparece no título do dia e no rótulo de acessibilidade da
    // grade; o primeiro é o da timeline.
    await expect(page.getByText('Quarta, 21/10').first()).toBeVisible();
  });

  test('navegar semanas muda a URL e o progresso volta a zero', async ({ page, request, baseURL }) => {
    const api = await apiAutenticada(request, baseURL);
    // Estado conhecido: nada marcado na semana de referência antes do teste.
    await api.delete('/api/atividades?inicio=2026-10-19');

    await entrar(page);
    await page.goto(`/semana/${DATA}`, { waitUntil: 'domcontentloaded' });
    await ativarSemantica(page);
    await aguardarSemana(page);

    // O rótulo alterna entre "Marcar … como feito" e "Desmarcar …": casar pelo
    // nome da atividade é o que sobrevive à mudança de estado.
    const caixa = page.getByRole('checkbox', { name: /Acordar/ }).first();
    await expect(caixa).toBeVisible();
    await expect(caixa).not.toBeChecked();
    await caixa.click();

    // O percentual aparece no cabeçalho e no resumo da semana: `.first()`.
    await expect(page.getByText('1%').first()).toBeVisible({ timeout: 15_000 });
    expect((await semana(api, baseURL)).concluidas[DATA]).toEqual(['qua-06:00']);

    await page.getByRole('button', { name: 'Próxima semana' }).click();
    await expect(page).toHaveURL(/\/semana\/2026-10-28$/);
    await expect(page.getByText('26 de outubro a 1 de novembro')).toBeVisible();
    await expect(page.getByText('0%').first()).toBeVisible();
    // A marcação da semana anterior não aparece aqui.
    await expect(page.getByRole('checkbox').first()).not.toBeChecked();

    await page.getByRole('button', { name: 'Semana anterior' }).click();
    await expect(page).toHaveURL(new RegExp(`/semana/${DATA}$`));
    await expect(page.getByRole('checkbox', { name: /Acordar/ }).first()).toBeChecked();
    await expect(page.getByText('1%').first()).toBeVisible();
  });

  test('botão Hoje volta para a semana atual', async ({ page }) => {
    await entrar(page);
    await page.goto('/semana/2026-12-09', { waitUntil: 'domcontentloaded' });
    await ativarSemantica(page);
    await aguardarSemana(page);

    await page.getByText('Hoje', { exact: true }).click();
    await expect(page.getByText(/esta semana/)).toBeVisible();
    await expect(page).toHaveURL(/\/semana\/\d{4}-\d{2}-\d{2}$/);
  });
});

test.describe('date picker', () => {
  test.skip(() => !temSenha, 'senha local ausente');

  test('escolher uma data abre a semana dela', async ({ page }) => {
    await entrar(page);
    await page.goto(`/semana/${DATA}`, { waitUntil: 'domcontentloaded' });
    await ativarSemantica(page);
    await aguardarSemana(page);

    await page.getByRole('button', { name: 'Escolher data' }).click();
    // O seletor do Material aparece como diálogo, com título e botões em
    // português.
    const dialogo = page.getByRole('dialog');
    await expect(dialogo).toBeVisible();
    await expect(dialogo.getByRole('button', { name: 'Mudar para modo de entrada' })).toBeVisible();

    // Modo de digitação (lápis) e data no formato brasileiro.
    await dialogo.getByRole('button', { name: 'Mudar para modo de entrada' }).click();
    const campo = page.locator('input[aria-label="Data"], input').last();
    await expect(campo).toBeVisible();
    await campo.fill('05/11/2026');
    await page.getByRole('button', { name: 'Abrir' }).click();

    await expect(page).toHaveURL(/\/semana\/2026-11-05$/);
    await expect(page.getByText('2 a 8 de novembro')).toBeVisible();
    await expect(page.getByText('Quinta, 05/11').first()).toBeVisible();
  });

  test('cancelar o seletor não muda a data', async ({ page }) => {
    await entrar(page);
    await page.goto(`/semana/${DATA}`, { waitUntil: 'domcontentloaded' });
    await ativarSemantica(page);
    await aguardarSemana(page);

    await page.getByRole('button', { name: 'Escolher data' }).click();
    await page.getByRole('button', { name: 'Cancelar' }).click();

    await expect(page).toHaveURL(new RegExp(`/semana/${DATA}$`));
    await expect(page.getByText('19 a 25 de outubro')).toBeVisible();
  });
});

test.describe('visão de calendário', () => {
  test.skip(() => !temSenha, 'senha local ausente');

  test('mês e semana inteira juntos, com progresso real', async ({ page, request, baseURL }) => {
    const api = await apiAutenticada(request, baseURL);
    await api.put(`/api/atividades/${DATA}/qua-06:00`, { data: { concluida: true } });
    const estado = await semana(api, baseURL);
    const feitasNaSemana = Object.entries(estado.concluidas ?? {})
      .filter(([data]) => data >= '2026-10-19' && data <= '2026-10-25')
      .reduce((s, [, ids]) => s + ids.length, 0);

    await entrar(page);
    await page.goto(`/semana/${DATA}`, { waitUntil: 'domcontentloaded' });
    await ativarSemantica(page);
    await aguardarSemana(page);
    await page.getByRole('button', { name: 'Ver calendário' }).click();
    await expect(page).toHaveURL(/\/calendario$/);

    await expect(page.getByText('Calendário').first()).toBeVisible();
    await expect(page.getByText('outubro de 2026')).toBeVisible();
    await expect(page.getByText('Semana 43')).toBeVisible();
    await expect(page.getByText('19 a 25 de outubro')).toBeVisible();
    // O resumo da prancha e as células do mês repetem o texto: `.first()`.
    await expect(
      page.getByText(new RegExp(`${feitasNaSemana} de \\d+ feitas`)).first(),
    ).toBeVisible();

    // A prancha mostra os sete dias e as atividades de cada um.
    // A prancha é a versão que lista as atividades: a célula do mês só tem o
    // número. `nada feito` distingue as duas.
    await expect(
      page.getByRole('button', { name: /^segunda, 19 de outubro, Segunda,/ }),
    ).toBeVisible();
    await expect(
      page.getByRole('button', { name: /^domingo, 25 de outubro, Domingo,/ }),
    ).toBeVisible();
    await expect(page.getByRole('button', { name: /Acordar.*Dormir/ }).first()).toBeVisible();

    await api.delete(`/api/atividades/${DATA}/qua-06:00`);
  });

  test('tocar num dia do mês abre a timeline daquela data', async ({ page }) => {
    await entrar(page);
    await page.goto('/calendario', { waitUntil: 'domcontentloaded' });
    await ativarSemantica(page);

    await expect(page.getByText('outubro de 2026').first()).toBeVisible();
    await page.getByRole('button', { name: /^sábado, 24 de outubro, nada feito/ }).first().click();

    await expect(page).toHaveURL(/\/semana\/2026-10-24$/);
    await expect(page.getByText('Sábado, 24/10').first()).toBeVisible();
  });

  test('navegar meses e semanas na visão de calendário', async ({ page }) => {
    await entrar(page);
    await page.goto('/calendario', { waitUntil: 'domcontentloaded' });
    await ativarSemantica(page);

    await page.getByRole('button', { name: 'Próximo mês' }).click();
    await expect(page.getByText('novembro de 2026').first()).toBeVisible();
    await page.getByRole('button', { name: 'Mês anterior' }).click();
    await expect(page.getByText('outubro de 2026').first()).toBeVisible();

    // O número da semana aparece no título e no resumo da prancha: `.first()`.
    await page.getByRole('button', { name: 'Próxima semana' }).click({ force: true });
    await expect(page.getByText('Semana 44').first()).toBeVisible();
    await expect(page.getByText('26 de outubro a 1 de novembro').first()).toBeVisible();

    // `force` porque o Flutter desenha a prancha em canvas: o botão está na
    // árvore de semântica, mas a camada de canvas por cima intercepta o clique.
    await page.getByRole('button', { name: 'Esta semana' }).click({ force: true });
    await expect(page.getByText('Semana 43').first()).toBeVisible();
  });

  test('voltar do calendário retorna ao dia aberto', async ({ page }) => {
    await entrar(page);
    await page.goto(`/semana/${DATA}`, { waitUntil: 'domcontentloaded' });
    await ativarSemantica(page);
    await aguardarSemana(page);

    await page.getByRole('button', { name: 'Ver calendário' }).click();
    await expect(page).toHaveURL(/\/calendario$/);
    await page.getByRole('button', { name: 'Voltar para o dia' }).click();
    await expect(page).toHaveURL(/\/semana\//);
    await aguardarSemana(page);
  });

  test('o calendário cabe em tela estreita', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 900 });
    await entrar(page);
    await page.goto('/calendario', { waitUntil: 'domcontentloaded' });
    await ativarSemantica(page);

    await expect(page.getByText('outubro de 2026').first()).toBeVisible();
    // A prancha vira lista: o dia aparece com o nome curto e a contagem.
    await expect(page.getByText('Semana 43').first()).toBeVisible();
    await expect(
      page.getByRole('button', { name: /^quarta, 21 de outubro/ }).first(),
    ).toBeVisible();
  });
});
