import { expect } from '@playwright/test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

/**
 * Apoio comum dos testes E2E.
 *
 * Duas dificuldades específicas do Flutter Web:
 *
 * 1. **Semântica opt-in.** O canvas não expõe DOM até a árvore de acessibilidade
 *    ser ativada: é preciso clicar no `flt-semantics-placeholder`. Sem isso,
 *    `getByRole` e `getByLabel` não encontram nada.
 * 2. **Campos não aceitam `fill`.** O motor mantém o estado do texto fora do
 *    `<input>`; escrever via DOM (ou `fill`) não chega ao widget. Teclas reais
 *    (`pressSequentially`) funcionam — é o caminho usado aqui.
 */

export const USUARIO = process.env.E2E_USUARIO ?? 'sarah';

/** Senha lida do arquivo local de segredos; nunca versionada. */
export function senha() {
  const arquivo = path.join(os.homedir(), '.segredos', 'minha-semana', 'senha.txt');
  if (!fs.existsSync(arquivo)) return '';
  return fs.readFileSync(arquivo, 'utf8').trim();
}

/** Verdadeiro quando há senha local para testar fluxos autenticados. */
export const temSenha = senha().length > 0;

/**
 * Ativa a árvore de semântica do Flutter Web e espera o motor montar a tela.
 *
 * Não exige nenhuma tela específica: a tela de login e a semana têm árvores
 * diferentes, e quem sabe o que esperar é o teste.
 */
export async function ativarSemantica(page) {
  await page.waitForFunction(
    () => document.querySelector('flt-semantics-placeholder') !== null,
    undefined,
    { timeout: 30_000 },
  );
  await page.evaluate(() => {
    document.querySelector('flt-semantics-placeholder')?.dispatchEvent(
      new MouseEvent('click', { bubbles: true }),
    );
  });
  // Qualquer `flt-semantics` montada indica que a árvore existe.
  await page.waitForSelector('flt-semantics', { state: 'attached', timeout: 30_000 });
}

/** Espera a tela da semana (pós-login). */
export async function aguardarSemana(page) {
  await expect(page.getByRole('button', { name: 'Ajustes' })).toBeVisible({ timeout: 30_000 });
}

/** Espera a tela de acesso. */
export async function aguardarAcesso(page) {
  await expect(page.getByRole('button', { name: 'Entrar' })).toBeVisible({ timeout: 30_000 });
}

/** Abre o app e espera o motor pintar. */
export async function abrir(page, caminho = '/semana') {
  await page.goto(caminho, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(
    () => !document.querySelector('flt-glass-pane')?.shadowRoot || true,
    undefined,
    { timeout: 30_000 },
  );
  // O app só tem DOM útil depois de ligar a semântica.
  await ativarSemantica(page);
}

/**
 * Preenche um campo do Flutter com teclas reais.
 *
 * O `<input>` da camada de semântica é só a ponte de teclado: o Flutter limpa o
 * valor do DOM depois de consumi-lo, então `toHaveValue` não serve de prova. A
 * confirmação vem do que a tela mostra (resumo do editor, eco na timeline) ou da
 * API — quem chama sabe qual é.
 */
export async function digitar(page, rotulo, texto) {
  // Campo de uma linha vira `<input>`; o de detalhe (multilinha) vira
  // `<textarea>`. O seletor cobre os dois.
  const campo = page.locator(`input[aria-label="${rotulo}"], textarea[aria-label="${rotulo}"]`).first();
  await expect(campo).toBeVisible();
  await campo.click();
  // `Control+A` não chega ao widget do Flutter (o atalho é tratado pelo motor,
  // não pelo `<input>`): o campo mantém o texto anterior e a nova digitação se
  // soma. Backspace é entregue e idempotente quando o campo já está vazio.
  // Um clique no meio do campo coloca o cursor no meio do placeholder; o foco
  // programático mantém o cursor no fim e evita a primeira tecla se perder.
  await campo.focus();
  await page.keyboard.press('End');
  for (let i = 0; i < 24; i++) await page.keyboard.press('Backspace');
  await page.keyboard.type(texto, { delay: 45 });
  await page.waitForTimeout(200);
}

/** Faz login pela tela e espera a semana. */
export async function entrar(page) {
  await page.goto('/acesso', { waitUntil: 'domcontentloaded' });
  await ativarSemantica(page);
  await digitar(page, 'Usuário', USUARIO);
  await digitar(page, 'Senha', senha());
  await page.getByRole('button', { name: 'Entrar' }).click();
  await expect(page.getByRole('button', { name: 'Ajustes' })).toBeVisible({ timeout: 30_000 });
}

/** Cria um contexto de requisição autenticado (cookie de sessão). */
export async function apiAutenticada(request, baseURL) {
  const resposta = await request.post(`${baseURL}/api/sessao`, {
    data: { usuario: USUARIO, senha: senha() },
  });
  expect(resposta.status(), await resposta.text()).toBe(200);
  return request;
}

/** Lê o estado atual da semana pela API. */
export async function semana(request, baseURL) {
  const r = await request.get(`${baseURL}/api/semana`);
  expect(r.status()).toBe(200);
  return r.json();
}

/** Atividade por título em qualquer dia. */
export function procurar(semanaJson, titulo) {
  for (const dia of semanaJson.dias ?? []) {
    for (const a of dia.atividades) {
      if (a.titulo === titulo) return { ...a, dia: dia.chave };
    }
  }
  return null;
}

/** Id único para não colidir entre execuções. */
export function idUnico(prefixo = 'e2e') {
  return `${prefixo}-${Date.now().toString(36)}`;
}

/**
 * Abre o editor de uma atividade tocando na linha (não no checkbox nem no menu).
 *
 * O alvo é o rótulo do grupo com `force`, porque o Flutter desenha em canvas:
 * o elemento de semântica cobre a linha, mas a checagem de "recebe clique" do
 * Playwright considera o canvas por cima. Clicar nas coordenadas do próprio
 * grupo é o que a pessoa faz na tela.
 */
export async function abrirEditor(page, nome) {
  const linha = page.getByRole('group', { name: new RegExp(`^${escapeRegex(nome)}`) });
  await expect(linha).toHaveCount(1);
  // A timeline rola: sem trazer a linha para a viewport, o clique cai no vazio.
  await linha.scrollIntoViewIfNeeded();
  await page.waitForTimeout(250);
  const caixa = await linha.boundingBox();
  if (!caixa) throw new Error(`linha "${nome}" sem geometria`);
  // Longe do checkbox (direita) e do menu (extrema direita): 30% da largura.
  await page.mouse.click(caixa.x + caixa.width * 0.3, caixa.y + caixa.height / 2);
  await expect(page.getByText(/Nova atividade|Editar atividade/)).toBeVisible();
}

/** Escapa caracteres especiais de regex num texto. */
export function escapeRegex(texto) {
  return texto.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Rola até o fim da página.
 *
 * `scrollIntoViewIfNeeded` do Playwright não funciona aqui: o Flutter desenha em
 * canvas e o scroll é do motor, não do DOM. A roda do mouse chega ao motor.
 */
export async function digitarTexto(page, rotulo, texto) {
  await digitar(page, rotulo, texto);
}

export async function rolarAteORodape(page, passos = 6) {
  for (let i = 0; i < passos; i++) {
    await page.mouse.move(550, 500);
    await page.mouse.wheel(0, 1200);
    await page.waitForTimeout(150);
  }
  await page.waitForTimeout(500);
}
