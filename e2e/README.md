# Testes de ponta a ponta

Suíte Playwright contra o site publicado: cobre a API (contrato, autorização,
ciclo de vida dos dados) e a interface em Chromium real (login, semana, plano
editável, cômodos, reset, ajustes, backup, links profundos, mobile e tema).

## Rodar

```bash
cd e2e
npm install
npx playwright install chromium   # uma vez
npm test                          # tudo
npm run test:api                  # só API
npm run test:ui                   # só interface
npm run report                    # relatório HTML
```

Alvo padrão: `https://minhasemana.pages.dev`. Para um preview:

```bash
E2E_BASE_URL=https://<hash>.minhasemana.pages.dev npm test
```

A senha é lida de `~/.segredos/minha-semana/senha.txt` (nunca do repositório).
Sem ela, os testes que exigem login são **pulados** com a razão no relatório —
a suíte continua valendo para rotas públicas e API anônima.

## O que a suíte assume

- **Fluxos destrutivos controlados.** Os testes marcam, desmarcam e reiniciam a
  semana; cada um deixa o estado como encontrou. Atividades de teste nascem com
  título `E2E …` e são removidas no fim.
- **`global-setup.js`** zera as tentativas de login falhas (o teste de senha
  errada conta para o bloqueio de 5/15 min) e remove resíduos `E2E ` de
  execuções interrompidas.
- **Estado real da usuária.** Os testes rodam sobre o plano de verdade. Não há
  banco de teste separado; é o custo de testar o ambiente publicado de ponta a
  ponta.

## Armadilhas do Flutter Web (aprendidas aqui)

| Sintoma | Causa | Solução |
| --- | --- | --- |
| `getByRole` não acha nada | a árvore de semântica é opt-in | clicar em `flt-semantics-placeholder` |
| `fill` não grava | o motor guarda o texto fora do `<input>` | teclas reais (`keyboard.type`) |
| `Control+A` não limpa | o atalho é do motor, não do `<input>` | `End` + backspaces |
| primeira tecla some | clique no meio do placeholder | `locator.focus()` antes de digitar |
| texto do widget não é achado por `getByText` | vive no rótulo de um `group` | `getByRole('group', { name: /…/ })` |
| clique cai no lugar errado | canvas por cima, ou linha fora da viewport | coordenadas do `boundingBox` após rolar |
| `scrollIntoViewIfNeeded` não rola | scroll é do motor | `mouse.wheel` |
| mensagem duplicada | snackbar + `flt-announcement-polite` | `.first()` |
| conteúdo do `TextField` invisível | o DOM é só ponte de teclado | verificar pela API |
| `labelText` não vira `aria-label` | o Flutter não propaga em `textarea` | selecionar por tag |
