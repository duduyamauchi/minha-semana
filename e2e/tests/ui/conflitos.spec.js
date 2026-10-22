import { test, expect } from '@playwright/test';
import {
  temSenha,
  entrar,
  ativarSemantica,
  aguardarSemana,
  semana,
  apiAutenticada,
  abrirEditor,
  digitar,
} from '../../helpers.js';

/**
 * Conflito de horário: aviso visível na lista e no editor, gravação liberada.
 *
 * O cenário é o do pedido: "Acordar" 06:00 e "Manutenção da limpeza" 06:10.
 * Com 10 min no primeiro, os dois encaixam; com mais, há sobreposição — e o app
 * precisa avisar sem impedir salvar.
 *
 * A data é fixa (`2026-10-21`, quarta) e o teste restaura a duração original no
 * fim, porque o plano é compartilhado entre todas as semanas.
 */

const DATA = '2026-10-21';
const ID = 'qua-06:00';

test.describe.configure({ mode: 'serial' });

async function abrirQuarta(page) {
  await page.goto(`/semana/${DATA}`, { waitUntil: 'domcontentloaded' });
  await ativarSemantica(page);
  await aguardarSemana(page);
  await page.getByRole('button', { name: /^Quarta,/ }).click();
}

test.describe('conflito de horário', () => {
  test.skip(() => !temSenha, 'senha local ausente');

  test.afterEach(async ({ request, baseURL }) => {
    // Restaura "Acordar" como item pontual.
    const api = await apiAutenticada(request, baseURL);
    await api.put(`/api/dias/qua/atividades/${encodeURIComponent(ID)}`, {
      data: { horario: '06:00', titulo: 'Acordar', detalhe: 'Água e higiene', categoria: 'bemEstar' },
    });
  });

  test('10 min em Acordar não gera conflito com a próxima atividade', async ({ page, request, baseURL }) => {
    const api = await apiAutenticada(request, baseURL);
    // Normaliza a atividade antes de medir: o plano é real e pode ter sido
    // editado à mão fora dos testes.
    await api.put(`/api/dias/qua/atividades/${encodeURIComponent(ID)}`, {
      data: { horario: '06:00', titulo: 'Acordar', categoria: 'bemEstar', duracaoMinutos: 10 },
    });

    await entrar(page);
    await abrirQuarta(page);

    // Nada entre 06:00 e 06:10: o próximo compromisso é às 06:10.
    await expect(page.getByRole('group', { name: /^Acordar.*10 min.*06:10/ })).toBeVisible();
    await expect(page.getByRole('group', { name: /Conflito com Manutenção/ })).toHaveCount(0);
  });

  test('duração que invade a próxima atividade avisa no editor sem bloquear', async ({ page }) => {
    await entrar(page);
    await abrirQuarta(page);

    await abrirEditor(page, 'Acordar');
    await digitar(page, 'min', '25');

    await expect(page.getByText('Este horário sobrepõe outra atividade.')).toBeVisible();
    await expect(page.getByText(/Manutenção da limpeza/)).toBeVisible();
    await expect(page.getByText('Você pode salvar assim mesmo.')).toBeVisible();

    // Salvar continua habilitado e conclui.
    await page.getByRole('button', { name: 'Salvar' }).click();
    await expect(page.getByText('Atividade atualizada.').first()).toBeVisible();
  });

  test('o conflito aparece na lista e no resumo do dia', async ({ page, request, baseURL }) => {
    const api = await apiAutenticada(request, baseURL);
    await api.put(`/api/dias/qua/atividades/${encodeURIComponent(ID)}`, {
      data: { horario: '06:00', titulo: 'Acordar', categoria: 'bemEstar', duracaoMinutos: 25 },
    });

    await entrar(page);
    await abrirQuarta(page);

    await expect(page.getByText(/sobreposição de horário/).first()).toBeVisible();
    // O texto do conflito vive no rótulo da linha (grupo), não como texto solto.
    await expect(
      page.getByRole('group', {
        name: /^Acordar.*25 min.*Conflito com Manutenção da limpeza \(06:10\)/,
      }),
    ).toBeVisible();
  });

  test('10 minutos não geram conflito', async ({ page, request, baseURL }) => {
    const api = await apiAutenticada(request, baseURL);
    await api.put(`/api/dias/qua/atividades/${encodeURIComponent(ID)}`, {
      data: { horario: '06:00', titulo: 'Acordar', categoria: 'bemEstar', duracaoMinutos: 10 },
    });

    await entrar(page);
    await abrirQuarta(page);

    await expect(page.getByText(/sobreposição de horário/)).toHaveCount(0);
    await expect(page.getByText(/^Conflito com/)).toHaveCount(0);
    await expect(page.getByRole('group', { name: /^Acordar.*10 min.*06:10/ })).toBeVisible();
  });

  test('marcar como feito continua funcionando com conflito', async ({ page, request, baseURL }) => {
    const api = await apiAutenticada(request, baseURL);
    await api.put(`/api/dias/qua/atividades/${encodeURIComponent(ID)}`, {
      data: { horario: '06:00', titulo: 'Acordar', categoria: 'bemEstar', duracaoMinutos: 25 },
    });

    await entrar(page);
    await abrirQuarta(page);

    await expect(page.getByText(/sobreposição de horário/).first()).toBeVisible();

    // A marcação alterna: o que importa é que o app **aceita** a ação com
    // conflito visível, não o estado anterior.
    const antes = await semana(api, baseURL);
    const estavaMarcada = (antes.concluidas[DATA] ?? []).includes(ID);

    const caixa = page.getByRole('checkbox', { name: /Acordar/ }).first();
    // `force` porque o canvas do Flutter fica por cima da camada de semântica.
    await caixa.click({ force: true });

    await expect
      .poll(
        async () => {
          const estado = await semana(api, baseURL);
          return (estado.concluidas[DATA] ?? []).includes(ID);
        },
        { timeout: 20_000 },
      )
      .toBe(!estavaMarcada);
    // O aviso é do horário e permanece.
    await expect(page.getByText(/sobreposição de horário/).first()).toBeVisible();

    await api.delete(`/api/atividades/${DATA}/${encodeURIComponent(ID)}`);
  });

  test('corrigir a duração remove o aviso', async ({ page, request, baseURL }) => {
    const api = await apiAutenticada(request, baseURL);
    await api.put(`/api/dias/qua/atividades/${encodeURIComponent(ID)}`, {
      data: { horario: '06:00', titulo: 'Acordar', categoria: 'bemEstar', duracaoMinutos: 40 },
    });

    await entrar(page);
    await abrirQuarta(page);
    await expect(page.getByText(/sobreposição de horário/).first()).toBeVisible();

    await abrirEditor(page, 'Acordar');
    await digitar(page, 'min', '');
    await page.getByRole('button', { name: 'Salvar' }).click();
    await expect(page.getByText('Atividade atualizada.').first()).toBeVisible();

    await expect(page.getByText(/sobreposição de horário/)).toHaveCount(0);
    const estado = await semana(api, baseURL);
    const acordar = estado.dias
      .flatMap((d) => d.atividades)
      .find((a) => a.id === ID);
    expect(acordar.duracaoMinutos).toBeNull();
  });
});
