# Verificação e decisões — Minha Semana

Registro do que foi verificado nesta entrega, com o comando ou a evidência de
cada item. Serve para não repetir checagem nem confiar em memória.

## Testes automatizados

| Suíte | Comando | Resultado |
| --- | --- | --- |
| Núcleo | `cd pacotes/planner_core && flutter test` | 55 testes |
| App | `cd planner && flutter test` | 9 testes |
| API | `cd api && npm test` | 37 testes |
| Análise estática | `flutter analyze` nos dois pacotes Dart | limpo |

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
