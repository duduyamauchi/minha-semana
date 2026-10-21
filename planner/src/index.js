// Worker do aplicativo: serve o build estático e encaminha `/api/*` para a API.
//
// O motivo de existir um proxy é o cookie de sessão: `SameSite=Strict` não
// atravessa host diferente, então chamar `minha-semana-api...workers.dev`
// direto é cross-site e o navegador descarta o cookie. Servindo a API sob o
// mesmo host, a sessão vale no app — e o visitante não precisa de CORS.
//
// Para o modo só-aparelho (`PLANNER_FONTE=local`) nada disso é usado: o app não
// chama a API.

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === '/api' || url.pathname.startsWith('/api/')) {
      const destino = new URL(request.url);
      destino.pathname = url.pathname.slice('/api'.length) || '/';

      const encaminhada = new Request(destino.toString(), {
        method: request.method,
        headers: request.headers,
        body: ['GET', 'HEAD'].includes(request.method) ? undefined : request.body,
        redirect: 'manual',
      });

      const resposta = await env.API.fetch(encaminhada);

      // O `Set-Cookie` do login precisa chegar ao navegador como se fosse deste
      // host; cabeçalhos de CORS não fazem sentido em mesma origem.
      const cabecalhos = new Headers();
      for (const [chave, valor] of resposta.headers) {
        if (chave.toLowerCase().startsWith('access-control-')) continue;
        cabecalhos.append(chave, valor);
      }
      return new Response(resposta.body, { status: resposta.status, headers: cabecalhos });
    }

    return env.ASSETS.fetch(request);
  },
};
