# Verificação e decisões — Minha Semana

Registro do que foi verificado nesta entrega, com o comando ou a evidência de
cada item. Serve para não repetir checagem nem confiar em memória.

## Testes automatizados

| Suíte | Comando | Resultado |
| --- | --- | --- |
| Núcleo | `cd pacotes/planner_core && flutter test` | 107 testes |
| App | `cd planner && flutter test` | 27 testes |
| API | `cd api && npm test` | 48 testes |
| **Ponta a ponta** | `cd e2e && npm test` | **41 testes** (18 API + 23 interface) |
| Análise estática | `flutter analyze` nos dois pacotes Dart | limpo |

Os testes de ponta a ponta rodam contra o site publicado, em Chromium real, e
cobrem o que os testes de unidade não alcançam: cookie de sessão, roteamento do
Pages, semântica do Flutter no navegador e persistência no Postgres. Eles
encontraram dois bugs que nenhuma outra suíte pegava:

1. **Dias sem nome ao vir da nuvem.** A API só persiste a chave (`qua`), e o
   `Dia.fromJson` usava a chave como nome: as abas mostravam "qua, 0 de 14" em
   vez de "Quarta, 0 de 14", e a nota do dia sumia. Corrigido com nomes e notas
   canônicos no domínio (`Dia.nomeDe`, `Dia.notaDe`, `nomeExibido`).
2. **Rota desconhecida mostrava "Page Not Found".** Um link antigo
   (`/caminho/que/nao/existe`) caía na tela de erro do GoRouter. Agora um
   catch-all redireciona para a semana.

Além disso, o E2E expôs que o export de backup não dava saída prática: o texto
ficava só num campo interno. O botão **Exportar** agora copia o JSON para a área
de transferência.

## Calendário (verificado em produção)

| O que | Evidência |
| --- | --- |
| Data na URL | `/semana/2026-10-21` abre aquela semana; abas mostram 19 a 25 |
| Navegação | setas mudam a semana e a URL; "Hoje" volta para a atual |
| Date picker | abre em português, aceita `05/11/2026` e troca a semana |
| Progresso por data | marcar a quarta marca só aquela quarta (API: `concluidas['2026-10-21']`) |
| Visão de calendário | mês (outubro de 2026) + prancha dos 7 dias, com progresso real |
| Voltar do calendário | retorna ao dia aberto (`/semana/2026-10-21`), não a hoje |

## Plano editável (verificado em produção)

| O que | Evidência |
| --- | --- |
| Criar atividade | `PUT /api/dias/seg/atividades/seg-05:55` → 200, `GET /api/semana` com `versao: 3` e a atividade |
| Editar horário/duração | linha mostra `07:10`, `45 min · até 07:55` |
| Excluir | `DELETE` → 200 e a atividade some do `GET` |
| Editor na tela | campos Título, Horário, Duração (h), min, categoria, switches e "Adicionar ao dia" |
| Menu por linha | "Opções de Acordar" com Editar/Excluir |
| Semeadura na nuvem | ao abrir com estado v2, o app grava o plano: `PUT /api/semana` e 14 atividades na quarta |
| Exportar backup | botão copia o JSON; conferido pela área de transferência contra `GET /api/semana` |
| Rota desconhecida | `/caminho/que/nao/existe` responde 200 e abre a semana |

## Verificação manual no navegador

Feita contra o build de produção (`minhasemana.pages.dev`),
com Chromium real:

| O que | Evidência |
| --- | --- |
| Tela de login aparece sem sessão | árvore de acessibilidade com `Usuário`, `Senha`, `Entrar` |
| Login com a senha correta | tela da semana, "progresso fica salvo na sua conta" |
| Marcar atividade | contador da aba `1/14`, cabeçalho `1%` |
| Recarregar mantém a marcação | `1%` e checkbox `checked` após reload |
| Estado no banco | `atividades_concluidas` com a linha `qua-06:00` |
| Modo escuro | captura com fundo `#141B19` e destaque `#6FC2AE` |
| Layout estreito (430 px) | abas sem contador, timeline em coluna |
| Cômodos (adicionar/remover) | teste de widget + captura da seção |
| `/api/semana` anônima | `401` |
| `/api/atividades/:id` anônima | `401` |
| `GET /api/sessao` anônima | `{"autenticado":false}` |
| Telemetria HTTP | 4 eventos no banco após marcar e aguardar o flush: `usuario_identificado`, `tela_visualizada`, `semana_carregada`, `atividade_concluida` |

## Armadilhas encontradas (não repita)

1. **Texto invisível no navegador.** Um `TextStyle` criado do zero perde a
   família tipográfica e cai na fonte padrão do motor (Roboto), que o CSP não
   libera — o texto simplesmente não aparece. Todo estilo precisa derivar de
   `Theme.of(context).textTheme` ou declarar `fontFamily`.
2. **Variável de fonte não basta.** As fontes do Google Fonts em formato
   variável, instanciadas pelo `fontTools`, renderizavam no desktop e sumiam no
   CanvasKit. Foram substituídas pelos TTF estáticos originais (upstream).
3. **Servidor local de thread única.** O `SimpleHTTPServer` atende uma conexão
   por vez e o navegador abre várias em paralelo (fonte, ícone, CanvasKit): o
   build parece "não carregar". `ferramentas/servir.py` usa `ThreadingTCPServer`
   e HTTP/1.1.
4. **`curl` sem User-Agent** leva 403 (erro 1010) do Cloudflare.
5. **Secrets do Pages exigem redeploy.** `wrangler pages secret put` não afeta o
   deployment já publicado: a Function continua respondendo `503 Servidor sem
   SESSION_SECRET`. Publique de novo depois de criar o secret.
6. **`_redirects` para SPA perde a rota.** `/ajustes /index.html 200` vira 308
   para `/index.html` e o Pages normaliza para `/`: a barra de endereço perde o
   caminho. A solução é um middleware (`functions/_middleware.js`) que serve o
   índice com 200 no próprio caminho. Redirects também não se aplicam a rotas de
   Function, então um curinga ali engoliria `/api`.
7. **`initialLocation` no GoRouter sobrescreve a URL.** Num link
   compartilhado (`/dia/qua`), o app abria `/semana`. Sem esse campo, o
   roteador parte da URL atual; no mobile a rota inicial `/` redireciona.
8. **`node --test test/`** falha no Node 22 do Windows tratando o diretório como
   módulo. Use `node --test` (sem argumento).
9. **`usePathUrlStrategy`** é obrigatório: sem ele `/dia/qua` abre a tela
   inicial, porque tudo depois do `#` é ignorado.
10. **Não carregue `flutter_bootstrap.js` junto com o bloco inline.** Inicializa
   o motor duas vezes e o Canvaskit quebra no primeiro rebuild.

## O que não foi verificado

- **Android/iOS**: as pastas existem (o `flutter create` as gerou), mas nenhum
  build foi feito. A sessão por cookie é o ponto a revisar no mobile — o
  `http.Client` fora do navegador não gerencia cookies sozinho; o caminho é usar
  `PLANNER_TOKEN` ou um gerenciador de cookies.
- **Inatividade de 1 h** em tempo real: a lógica tem teste unitário (`Inatividade`
  com relógio injetado) e o servidor tem teste de expiração, mas o aviso de 2 min
  não foi observado numa sessão real. Para testar:
  `--dart-define=PLANNER_INATIVIDADE_SEGUNDOS=25`.
- **Flush da telemetria em produção sob falha**: o caminho feliz foi observado
  (lote de 4 eventos chegou ao banco após 10 s). A reentrega em caso de erro de
  rede só tem teste unitário do coletor.
