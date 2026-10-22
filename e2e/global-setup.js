import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * Prepara o ambiente dos testes de ponta a ponta.
 *
 * Duas limpezas, ambas idempotentes:
 *
 * 1. **Tentativas de login.** A suíte exercita credencial inválida de propósito;
 *    sem zerar, a execução seguinte encontraria o bloqueio de 15 minutos em vez
 *    do 401 esperado.
 * 2. **Resíduos de execuções interrompidas.** Atividades criadas pelos testes
 *    têm título começando em "E2E "; uma falha no meio do caminho as deixaria no
 *    plano real. Removê-las no início mantém o plano da usuária limpo.
 *
 * Best-effort: sem `psycopg` ou sem a senha local, apenas avisa.
 */

const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const BASE = process.env.E2E_BASE_URL ?? 'https://minhasemana.pages.dev';
const USUARIO = process.env.E2E_USUARIO ?? 'sarah';

function senha() {
  const arquivo = path.join(os.homedir(), '.segredos', 'minha-semana', 'senha.txt');
  return fs.existsSync(arquivo) ? fs.readFileSync(arquivo, 'utf8').trim() : '';
}

async function limparResiduos() {
  const segredo = senha();
  if (!segredo) return 'sem senha local: resíduos não foram removidos';

  const login = await fetch(`${BASE}/api/sessao`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ usuario: USUARIO, senha: segredo }),
  });
  if (!login.ok) return `login recusado (${login.status}): resíduos não foram removidos`;
  const cookie = login.headers.get('set-cookie')?.split(';')[0] ?? '';

  const resposta = await fetch(`${BASE}/api/semana`, { headers: { cookie } });
  if (!resposta.ok) return `semana indisponível (${resposta.status})`;
  const estado = await resposta.json();

  const alvos = (estado.dias ?? []).flatMap((d) =>
    d.atividades.filter((a) => a.titulo.startsWith('E2E ') || a.titulo.startsWith('Teste '),
    ).map((a) => ({ dia: d.chave, id: a.id })),
  );
  for (const alvo of alvos) {
    await fetch(`${BASE}/api/dias/${alvo.dia}/atividades/${encodeURIComponent(alvo.id)}`, {
      method: 'DELETE',
      headers: { cookie },
    });
  }
  return `${alvos.length} atividade(s) de teste removida(s)`;
}

export default async function globalSetup() {
  const script = path.join(raiz, 'deploy', 'limpar_tentativas.py');
  try {
    const saida = execFileSync('python', [script], { encoding: 'utf8', timeout: 60_000 });
    process.stdout.write(`[e2e] ${saida.trim()}\n`);
  } catch (erro) {
    process.stdout.write(`[e2e] limpeza de tentativas falhou: ${erro.message}\n`);
  }

  try {
    process.stdout.write(`[e2e] ${await limparResiduos()}\n`);
  } catch (erro) {
    process.stdout.write(`[e2e] limpeza de resíduos falhou: ${erro.message}\n`);
  }
}
