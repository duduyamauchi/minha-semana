// Middleware do projeto Pages: preserva a URL nas rotas do SPA.
//
// Por que não `_redirects`: o arquivo de redirects faz o Pages responder 308
// para `/index.html` (que ele normaliza para `/`), apagando a rota da barra de
// endereço — um link compartilhado como `/dia/qua` abriria a raiz. Aqui o
// índice é servido com 200 no próprio caminho, e o Flutter resolve a rota no
// cliente (`usePathUrlStrategy`).
//
// A ordem importa: primeiro a Function da API (`functions/api/`), depois os
// assets; este middleware só entra quando nenhum dos dois atende.

export async function onRequest(context) {
  const resposta = await context.next();
  if (resposta.status !== 404) return resposta;

  const metodo = context.request.method;
  if (metodo !== 'GET' && metodo !== 'HEAD') return resposta;

  const indice = new URL('/index.html', context.request.url);
  const doIndice = await context.env.ASSETS.fetch(new Request(indice.toString(), { method: metodo }));
  return new Response(doIndice.body, {
    status: 200,
    headers: doIndice.headers,
  });
}
