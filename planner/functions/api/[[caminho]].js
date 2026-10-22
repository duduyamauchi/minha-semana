// Função do Pages: encaminha `/api/*` para o código da API.
//
// O app e a API vivem na mesma origem (`minhasemana.pages.dev`), então o cookie
// de sessão `SameSite=Strict` vale — chamar outro host seria cross-site e o
// navegador descartaria o cookie, deixando o app "logado" que não persiste.
//
// O código é o mesmo que roda no Worker (`api/src`): uma implementação,
// dois ambientes possíveis. O Pages injeta variáveis e secrets em `context.env`,
// exatamente como o Worker faz.

import { criarSql, tratar } from '../../../api/src/index.js';

export async function onRequest(context) {
  const { request, env } = context;
  const url = new URL(request.url);

  // A função só cuida de `/api`; o resto é servido como asset estático.
  const caminho = url.pathname === '/api' ? '/' : url.pathname.slice('/api'.length);
  const destino = new URL(request.url);
  destino.pathname = caminho;

  const interna = new Request(destino.toString(), {
    method: request.method,
    headers: request.headers,
    body: ['GET', 'HEAD'].includes(request.method) ? undefined : request.body,
  });

  const resposta = await tratar(interna, env, criarSql(env));

  // O `Set-Cookie` do login passa intacto; cabeçalhos de CORS não fazem sentido
  // em mesma origem.
  return new Response(resposta.body, { status: resposta.status, headers: resposta.headers });
}
