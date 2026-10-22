import { defineConfig } from '@playwright/test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

/**
 * Configuração dos testes de ponta a ponta.
 *
 * O alvo padrão é o site publicado (`https://minhasemana.pages.dev`): é o único
 * lugar onde a Function do Pages, o cookie `SameSite=Strict` e o Chromium real
 * convivem. `E2E_BASE_URL` permite apontar para um deploy de preview.
 *
 * A senha vem do arquivo local de segredos (nunca do repositório). Sem ela, os
 * testes que exigem login são pulados em vez de falhar — a suíte continua
 * útil para checar rotas públicas e a API anônima.
 */

const segredo = path.join(os.homedir(), '.segredos', 'minha-semana', 'senha.txt');

export default defineConfig({
  testDir: './tests',
  timeout: 90_000,
  expect: { timeout: 15_000 },
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: [['list'], ['html', { open: 'never', outputFolder: 'relatorio' }]],
  // Antes de tudo: o teste de senha errada conta para o bloqueio de força bruta
  // do servidor (5 falhas/15 min). Zera o contador para a execução ser repetível.
  globalSetup: './global-setup.js',
  use: {
    baseURL: process.env.E2E_BASE_URL ?? 'https://minhasemana.pages.dev',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'off',
    locale: 'pt-BR',
    timezoneId: 'America/Sao_Paulo',
  },
  projects: [
    {
      name: 'api',
      testDir: './tests/api',
      use: { baseURL: process.env.E2E_BASE_URL ?? 'https://minhasemana.pages.dev' },
    },
    {
      name: 'ui',
      testDir: './tests/ui',
      use: { viewport: { width: 1100, height: 1100 } },
    },
  ],
});
