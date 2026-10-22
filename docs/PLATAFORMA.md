# Plataforma — recomendação

Pergunta: onde hospedar o Minha Semana para uso real.

Resposta curta: a pilha já implantada — **Cloudflare Pages (app + API como
Function) e Neon** em São Paulo — custa US$ 0 e cobre o caso de uso inteiro. Não
há servidor próprio, não há CDN separada e não há conta de banco a administrar.

---

## 1. O que o sistema precisa hospedar

| Necessidade | Como está |
| --- | --- |
| App (Flutter Web) | projeto Pages `minhasemana` + assets na CDN da Cloudflare |
| API de dados | Pages Function em `/api/*` (mesmo projeto) |
| Banco | Neon Postgres 17 em `aws-sa-east-1` |
| Login | próprio, com sessão assinada em cookie |
| Fotos/vídeos | **não há** — o app não guarda mídia |

O último item é o que deixa esta implantação mais simples que a de referência: o
app não tem arquivo a servir, então não há R2, CORS de bucket nem orçamento de
egress.

## 2. Por que Pages e não Worker, Vercel ou Render

- **URL sem o nome da conta.** O subdomínio `*.workers.dev` é fixo da conta
  Cloudflare (a API recusa a troca, erro 10036) e arrastaria o nome de outro
  projeto. No Pages, o domínio vem do nome do projeto: `minhasemana.pages.dev`.
- **Mesma origem para app e API**: a Function em `/functions/api` serve `/api/*`
  sem internet no meio, e é o que faz o cookie `SameSite=Strict` valer. Num host
  de estático + host de API separado, o login entra mas o app não persiste — foi
  um bug real no projeto de referência.
- **`_headers` é respeitado**: CSP e HSTS saem junto com o build.
- **Roteamento de SPA**: `planner/functions/_middleware.js` serve o `index.html`
  com 200 quando o caminho não é asset nem `/api`, preservando a URL. Com
  `_redirects` o Pages respondia 308 para `/index.html` (normalizado para `/`),
  apagando a rota — um link `/dia/qua` abria a raiz.
- **Custo**: o free tier do Pages tem requisições e bandwidth folgados; um
  planner pessoal usa três ordens de magnitude menos.
- **Um único deploy** publica app e API, com os mesmos secrets.

## 3. Neon em São Paulo

| Item | Free |
| --- | --- |
| Banco | 1 GB por projeto |
| Compute | 100 CU-horas/mês |
| Região | `aws-sa-east-1` |
| Pausa | não pausa; escala a zero e acorda em ~1 s |
| Backup | restore de 6 h |

O volume real é minúsculo: uma linha por atividade marcada e uma por cômodo. Um
ano de uso cabe em alguns kilobytes.

**Cold start** de algumas centenas de milissegundos na primeira consulta após
ociosidade. Num app que abre algumas vezes ao dia, é imperceptível.

## 4. Custos

| Item | Custo |
| --- | --- |
| Cloudflare Workers | US$ 0 |
| Neon Free | US$ 0 |
| Domínio `.com.br` (opcional) | ~R$ 40/ano |
| **Total mensal** | **US$ 0** |

Quando migrar:

| Gatilho | Ação |
| --- | --- |
| Domínio próprio | Registrar no Registro.br e apontar `CNAME` para o projeto Pages |
| Mais de 100 mil req/dia | Workers Paid / Pages com limites maiores (US$ 5/mês) |
| Banco acima de 1 GB | Neon Launch (uso, ~US$ 15) |
| App nas lojas | Play US$ 25 único; iOS US$ 99/ano + Mac |

## 5. O que mudaria para um segundo produto

A arquitetura já permite: o template no app, o contrato `FonteDeDados` e a
separação `planner_core` / `planner_ui` existem para isso.

| Cenário | Trabalho |
| --- | --- |
| Painel administrativo | importar `planner_core` e `planner_ui`; a API já tem papéis |
| Multi-usuário | `quadro_do_usuario` já devolve `(quadro_id, papel)`; falta só o cadastro |
| App nativo (Android/iOS) | o projeto já tem as pastas; a sessão por cookie é o ponto a revisar (ver `MODULARIDADE.md`) |

## 6. Riscos honestos

- **Free tiers mudam** sem aviso. Não construir negócio sobre eles sem plano B.
- **Sem SLA e sem suporte**: se cair, quem resolve é você. O log do deployment e o
  `x-erro-id` existem para isso.
- **Nome do projeto fixa o domínio**: `minhasemana.pages.dev` vem do nome do
  projeto Pages. Renomear o projeto muda a URL (e a allowlist de origem junto);
  para um domínio próprio, basta apontar CNAME para o Pages.
- **LGPD**: o banco guarda um identificador e o plano de uma pessoa. Não há dado
  sensível, mas a senha nunca é armazenada — só o hash com pepper do servidor.
