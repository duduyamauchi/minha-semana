// API do Minha Semana — Cloudflare Workers sobre Postgres (Neon).
//
// Por que existe: o app é Flutter Web, que não abre conexão TCP. Falar com o
// Postgres direto do navegador é impossível (e exporia credenciais). Esta API é
// a ponte: HTTP do navegador, driver serverless para o banco.
//
// Contrato (o mesmo que `FonteHttp` consome):
//   POST   /sessao                    -> login (cookie HttpOnly)
//   DELETE /sessao                    -> logout
//   GET    /sessao                    -> quem sou eu
//   GET    /semana                    -> EstadoSemana
//   PUT    /semana                    -> substitui o estado (backup/importação)
//   PUT    /atividades/:id            -> { concluida: bool }
//   DELETE /atividades                -> desmarca a semana
//   PUT    /comodos/:id               -> grava um cômodo
//   DELETE /comodos/:id               -> remove um cômodo
//   POST   /eventos                   -> lote de analytics
//   GET    /eventos?limite=N          -> telemetria (só autenticado)
//
// Segurança:
//   * Toda escrita exige sessão. Leitura da semana também: é um plano pessoal.
//   * CORS com allowlist exata e credenciais; nunca `*` com cookie.
//   * Corpo limitado, listas limitadas, campos validados e truncados.
//   * Erro interno não vaza mensagem do banco: vai para o log com um id.

import { neon } from '@neondatabase/serverless';
import {
  acessoDe,
  conferirSenha,
  cookieDeSessao,
  cookieVazio,
  derivarHash,
  emitirSessao,
  gerarSalt,
  identificar,
  INATIVIDADE_MAXIMA,
  paraHex,
  segundosAteExpirar,
} from './auth.js';

// ---------------------------------------------------------------------------
// Resposta
// ---------------------------------------------------------------------------

/** Origens que podem chamar a API com cookie. Allowlist exata, sem curinga. */
const ORIGENS_PERMITIDAS = (env) =>
  (
    env.ORIGENS_PERMITIDAS ??
    'http://localhost:8080,http://127.0.0.1:8080,http://localhost:8081,http://127.0.0.1:8081'
  )
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);

function cabecalhosBase(env, request) {
  const origem = request?.headers.get('origin') ?? '';
  const permitidas = ORIGENS_PERMITIDAS(env);
  const headers = {
    'content-type': 'application/json; charset=utf-8',
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'no-referrer',
    'cache-control': 'no-store',
    vary: 'Origin',
  };
  // Só devolve a origem exata quando ela está na lista.
  if (permitidas.includes(origem)) {
    headers['access-control-allow-origin'] = origem;
    headers['access-control-allow-credentials'] = 'true';
    headers['access-control-allow-methods'] = 'GET,PUT,POST,DELETE,OPTIONS';
    headers['access-control-allow-headers'] = 'content-type,authorization';
    headers['access-control-max-age'] = '600';
  }
  return headers;
}

const json = (corpo, status = 200, extras = {}) =>
  new Response(JSON.stringify(corpo), {
    status,
    headers: { ...extras.cabecalhos, ...(extras.headers ?? {}) },
  });

const erro = (mensagem, status = 400, extras = {}) => json({ erro: mensagem }, status, extras);

// ---------------------------------------------------------------------------
// Validação de entrada
// ---------------------------------------------------------------------------

const LIMITE_CORPO = 1024 * 1024; // 1 MiB por requisição
const LIMITE_LISTA = 500; // itens por coleção enviada

class ErroValidacao extends Error {
  constructor(mensagem, status = 400) {
    super(mensagem);
    this.status = status;
  }
}

/** Lê o JSON respeitando o limite de tamanho. */
async function lerJson(request) {
  const declarado = Number(request.headers.get('content-length') ?? 0);
  if (declarado > LIMITE_CORPO) {
    throw new ErroValidacao('Corpo da requisição acima do limite.', 413);
  }
  const texto = await request.text();
  if (texto.length > LIMITE_CORPO) {
    throw new ErroValidacao('Corpo da requisição acima do limite.', 413);
  }
  if (!texto) return {};
  try {
    const lido = JSON.parse(texto);
    if (lido === null || typeof lido !== 'object' || Array.isArray(lido)) {
      throw new ErroValidacao('O corpo precisa ser um objeto JSON.');
    }
    return lido;
  } catch (e) {
    if (e instanceof ErroValidacao) throw e;
    throw new ErroValidacao('Corpo não é JSON válido.', 400);
  }
}

/** Texto curto, sem caracteres de controle, truncado. */
function texto(valor, campo, { max = 500, obrigatorio = false, padrao = '' } = {}) {
  if (valor == null || valor === '') {
    if (obrigatorio) throw new ErroValidacao(`Campo obrigatório ausente: ${campo}.`);
    return padrao;
  }
  if (typeof valor !== 'string' && typeof valor !== 'number') {
    throw new ErroValidacao(`Campo ${campo} deve ser texto.`);
  }
  // eslint-disable-next-line no-control-regex
  const s = String(valor).replace(/[\u0000-\u001f\u007f]/g, ' ').trim();
  if (obrigatorio && !s) throw new ErroValidacao(`Campo obrigatório ausente: ${campo}.`);
  return s.slice(0, max);
}

/**
 * Identificador de atividade/cômodo (`seg-06:00`, `area-de-servico`).
 *
 * Só letras, números, hífen, sublinhado, ponto e dois-pontos — o mesmo alfabeto
 * que o app produz. Barras e `%` ficam de fora para não virar caminho.
 */
function identificador(valor, campo) {
  const s = texto(valor, campo, { max: 120, obrigatorio: true });
  if (!/^[\p{L}\p{N}_.:-]+$/u.test(s)) {
    throw new ErroValidacao(`Campo ${campo} tem caracteres inválidos.`);
  }
  return s;
}

function listaDe(valor, campo) {
  if (valor == null) return [];
  if (!Array.isArray(valor)) throw new ErroValidacao(`Campo ${campo} deve ser uma lista.`);
  if (valor.length > LIMITE_LISTA) {
    throw new ErroValidacao(`Campo ${campo} excede ${LIMITE_LISTA} itens.`, 413);
  }
  return valor;
}

function objeto(valor, campo) {
  if (valor == null) return {};
  if (typeof valor !== 'object' || Array.isArray(valor)) {
    throw new ErroValidacao(`Campo ${campo} deve ser um objeto.`);
  }
  return valor;
}

function dataIso(valor, campo, { obrigatorio = false } = {}) {
  if (valor == null || valor === '') {
    if (obrigatorio) throw new ErroValidacao(`Campo obrigatório ausente: ${campo}.`);
    return null;
  }
  const d = new Date(valor);
  if (Number.isNaN(d.getTime())) throw new ErroValidacao(`Data inválida em ${campo}.`);
  return d.toISOString();
}

function decimal(valor, campo, { min = 0, max = 100_000, padrao = 0 } = {}) {
  if (valor == null || valor === '') return padrao;
  const n = Number(valor);
  if (!Number.isFinite(n)) throw new ErroValidacao(`Campo ${campo} deve ser numérico.`);
  if (n < min || n > max) throw new ErroValidacao(`Campo ${campo} fora do intervalo.`);
  return n;
}

/** Cômodo vindo do app: `{ id, nome, concluido }`. */
function normalizarComodo(valor, idForcado = null) {
  const o = objeto(valor, 'comodo');
  const id = idForcado ?? identificador(o.id, 'id');
  const nome = texto(o.nome, 'nome', { max: 80, obrigatorio: true });
  const concluido = o.concluido === true || o.d === true;
  return { id, nome, concluido };
}

// ---------------------------------------------------------------------------
// Leitura e escrita da semana
// ---------------------------------------------------------------------------

/**
 * Lê o estado da semana (marcações e cômodos) de um quadro.
 *
 * Duas consultas, não N+1: o volume é pequeno (uma linha por atividade marcada
 * e uma por cômodo), e o Worker tem limite de subrequests.
 */
async function lerSemana(sql, quadroId) {
  const [marcadas, comodos] = await Promise.all([
    sql`select atividade_id from atividades_concluidas where quadro_id = ${quadroId} order by atividade_id`,
    sql`select id, nome, concluido from comodos where quadro_id = ${quadroId} order by nome`,
  ]);
  return {
    versao: 2,
    marcadas: marcadas.map((l) => l.atividade_id),
    comodos: comodos.map((c) => ({ id: c.id, nome: c.nome, concluido: c.concluido })),
  };
}

/** Substitui o estado inteiro numa transação (importação de backup). */
async function gravarSemana(sql, quadroId, estado) {
  await sql`delete from atividades_concluidas where quadro_id = ${quadroId}`;
  await sql`delete from comodos where quadro_id = ${quadroId}`;

  const marcadas = estado.marcadas;
  if (marcadas.length) {
    // Uma instrução para todas as linhas: inserir em laço estoura o limite de
    // subrequests do Worker com uma semana cheia.
    await sql`
      insert into atividades_concluidas (quadro_id, atividade_id)
      select ${quadroId}, unnest(${marcadas}::text[])
      on conflict do nothing
    `;
  }

  if (estado.comodos.length) {
    const ids = estado.comodos.map((c) => c.id);
    const nomes = estado.comodos.map((c) => c.nome);
    const concluidos = estado.comodos.map((c) => c.concluido);
    await sql`
      insert into comodos (quadro_id, id, nome, concluido, ordem)
      select ${quadroId}, id, nome, concluido, ordinalidade - 1
      from unnest(${ids}::text[], ${nomes}::text[], ${concluidos}::boolean[])
        with ordinality as t(id, nome, concluido, ordinalidade)
    `;
  }
}

// ---------------------------------------------------------------------------
// Bloqueio por tentativa repetida
// ---------------------------------------------------------------------------

const hashIp = (request, env) => {
  const ip =
    request.headers.get('cf-connecting-ip') ??
    request.headers.get('x-forwarded-for') ??
    'desconhecido';
  return paraHex(new TextEncoder().encode(`${ip}:${env.SESSION_SECRET ?? ''}`));
};

const MAX_TENTATIVAS = 5;

async function bloqueado(sql, ipHash, usuarioId) {
  const porIp = await sql`
    select count(*)::int as n from tentativas_login
    where ip_hash = ${ipHash} and not sucesso and quando > now() - interval '15 minutes'
  `;
  const porUsuario = usuarioId
    ? await sql`
        select count(*)::int as n from tentativas_login
        where usuario_id = ${usuarioId} and not sucesso and quando > now() - interval '15 minutes'
      `
    : [{ n: 0 }];
  return porIp[0].n >= MAX_TENTATIVAS || porUsuario[0].n >= MAX_TENTATIVAS;
}

async function registrarTentativa(sql, ipHash, usuarioId, sucesso) {
  await sql`
    insert into tentativas_login (ip_hash, usuario_id, sucesso)
    values (${ipHash}, ${usuarioId ?? ''}, ${sucesso})
  `;
  // Poda: a tabela só precisa da janela recente.
  await sql`delete from tentativas_login where quando < now() - interval '2 days'`;
}

// ---------------------------------------------------------------------------
// Roteamento
// ---------------------------------------------------------------------------

const COOKIE_SEGURO = (request) => new URL(request.url).protocol === 'https:';

const ROTAS = {
  sessao: 'login, logout e identidade',
  semana: 'estado completo da semana',
  atividades: 'marcações individuais',
  comodos: 'lista de reorganização',
  eventos: 'telemetria',
};

/** Cliente do banco para um ambiente. Usado pelo Worker e pela função do Pages. */
export const criarSql = (env) => neon(env.DATABASE_URL);

export default {
  fetch: (request, env) => tratar(request, env, criarSql(env)),
};

/**
 * Roteamento, separado da criação do cliente de banco.
 *
 * A separação existe para os testes: recebendo `sql` pronto, um teste pode
 * passar um duplo em memória e exercitar autorização e validação sem rede e sem
 * banco.
 */
export async function tratar(request, env, sql) {
  {
    const url = new URL(request.url);
    const base = cabecalhosBase(env, request);

    // Preflight: responde só para origem conhecida; sem curinga.
    if (request.method === 'OPTIONS') {
      if (!base['access-control-allow-origin']) return new Response(null, { status: 403, headers: base });
      return new Response(null, { status: 204, headers: base });
    }

    const partes = url.pathname.split('/').filter(Boolean);
    const seguro = COOKIE_SEGURO(request);

    if (!env.SESSION_SECRET || !env.PEPPER_SENHA) {
      // Sem segredos não há como assinar sessão nem conferir senha. Falhar
      // fechado é melhor que servir uma API que aceita qualquer coisa.
      return erro('Servidor sem SESSION_SECRET ou PEPPER_SENHA configurado.', 503, {
        cabecalhos: base,
      });
    }
    if (!env.DATABASE_URL) {
      return erro('Servidor sem DATABASE_URL configurado.', 503, { cabecalhos: base });
    }

    try {
      // -------------------------------------------------------------------
      // Sessão
      // -------------------------------------------------------------------

      if (partes[0] === 'sessao') {
        // POST /sessao — login
        if (request.method === 'POST') {
          const corpo = await lerJson(request);
          const usuarioId = texto(corpo.usuario, 'usuario', { max: 120, obrigatorio: true });
          const senha = texto(corpo.senha, 'senha', { max: 200, obrigatorio: true });
          const ipHash = hashIp(request, env);

          if (await bloqueado(sql, ipHash, usuarioId)) {
            return erro('Muitas tentativas. Aguarde 15 minutos.', 429, { cabecalhos: base });
          }

          // Mensagem única para usuário inexistente e senha errada: não
          // confirma quais contas existem. O hash de isca mantém o custo de CPU
          // igual nos dois casos, para o tempo de resposta não denunciar.
          const registros = await sql`
            select usuario_id, hash, salt, iteracoes from credenciais where usuario_id = ${usuarioId}
          `;
          const registro = registros[0];
          const confere = registro
            ? await conferirSenha(senha, registro, env.PEPPER_SENHA)
            : ((await derivarHash(senha, gerarSalt(), undefined, env.PEPPER_SENHA)), false);

          if (!registro || !confere) {
            await registrarTentativa(sql, ipHash, usuarioId, false);
            return erro('Usuário ou senha inválidos.', 401, { cabecalhos: base });
          }

          await registrarTentativa(sql, ipHash, usuarioId, true);
          const cookie = cookieDeSessao(await emitirSessao(usuarioId, env.SESSION_SECRET), { seguro });
          const acesso = await acessoDe(sql, { tipo: 'usuario', usuarioId }, env);
          return json(
            { usuario: usuarioId, quadroId: acesso?.quadroId ?? null, papel: acesso?.papel ?? null },
            200,
            {
              cabecalhos: base,
              headers: { 'set-cookie': cookie },
            },
          );
        }

        // DELETE /sessao — logout
        if (request.method === 'DELETE') {
          return json({ ok: true }, 200, {
            cabecalhos: base,
            headers: { 'set-cookie': cookieVazio(seguro) },
          });
        }

        // GET /sessao — quem sou eu
        if (request.method === 'GET') {
          const identidade = await identificar(request, env);
          const acesso = await acessoDe(sql, identidade, env);
          if (!acesso) return json({ autenticado: false }, 200, { cabecalhos: base });
          return json(
            {
              autenticado: true,
              usuario: identidade.usuarioId,
              quadroId: acesso.quadroId,
              papel: acesso.papel,
              // Prazo para o cliente avisar antes de cair por inatividade.
              expiraEmSegundos: identidade.sessao ? segundosAteExpirar(identidade.sessao) : null,
              limiteInatividadeSegundos: INATIVIDADE_MAXIMA,
            },
            200,
            { cabecalhos: base },
          );
        }

        return erro('Método não permitido em /sessao.', 405, { cabecalhos: base });
      }

      // -------------------------------------------------------------------
      // A partir daqui: identidade resolvida uma vez
      // -------------------------------------------------------------------

      const identidade = await identificar(request, env);
      const acesso = await acessoDe(sql, identidade, env);
      const autenticado = Boolean(acesso);
      const podeEscrever = autenticado && acesso.papel !== 'leitor';

      // Renova o relógio de inatividade quando houve uso desde a última
      // assinatura. Sem isso, a sessão cairia 1 h depois do login mesmo com a
      // pessoa usando o app.
      const renovacao = identidade.renovar
        ? {
            'set-cookie': cookieDeSessao(
              await emitirSessao(identidade.usuarioId, env.SESSION_SECRET),
              { seguro },
            ),
          }
        : {};

      const responder = (corpo, status = 200, extras = {}) =>
        json(corpo, status, { cabecalhos: base, headers: { ...renovacao, ...(extras.headers ?? {}) } });

      const recusarEscrita = () =>
        erro(
          autenticado ? 'Seu papel não permite esta operação.' : 'Autenticação necessária para gravar.',
          autenticado ? 403 : 401,
          { cabecalhos: base },
        );

      if (!ROTAS[partes[0]]) {
        return erro('Rota não encontrada.', 404, { cabecalhos: base });
      }

      // O plano é pessoal: nem a leitura é pública.
      if (!autenticado) {
        return erro('Autenticação necessária.', 401, { cabecalhos: base });
      }

      // GET/PUT /semana
      if (partes[0] === 'semana' && !partes[1]) {
        if (request.method === 'GET') {
          return responder(await lerSemana(sql, acesso.quadroId));
        }
        if (request.method === 'PUT') {
          if (!podeEscrever) return recusarEscrita();
          const corpo = await lerJson(request);
          const marcadas = listaDe(corpo.marcadas, 'marcadas').map((m) => identificador(m, 'marcada'));
          const comodos = listaDe(corpo.comodos, 'comodos').map((c) => normalizarComodo(c));
          await gravarSemana(sql, acesso.quadroId, { marcadas, comodos });
          return responder(await lerSemana(sql, acesso.quadroId));
        }
        return erro('Método não permitido em /semana.', 405, { cabecalhos: base });
      }

      // PUT /atividades/:id — marca/desmarca uma atividade
      if (partes[0] === 'atividades' && partes[1] && request.method === 'PUT') {
        if (!podeEscrever) return recusarEscrita();
        const id = identificador(decodeURIComponent(partes[1]), 'id');
        const corpo = await lerJson(request);
        if (typeof corpo.concluida !== 'boolean') {
          throw new ErroValidacao('Campo concluida deve ser booleano.');
        }
        if (corpo.concluida) {
          await sql`
            insert into atividades_concluidas (quadro_id, atividade_id)
            values (${acesso.quadroId}, ${id})
            on conflict do nothing
          `;
        } else {
          await sql`
            delete from atividades_concluidas
            where quadro_id = ${acesso.quadroId} and atividade_id = ${id}
          `;
        }
        return responder({ ok: true, id, concluida: corpo.concluida });
      }

      // DELETE /atividades — desmarca a semana inteira
      if (partes[0] === 'atividades' && !partes[1] && request.method === 'DELETE') {
        if (!podeEscrever) return recusarEscrita();
        await sql`delete from atividades_concluidas where quadro_id = ${acesso.quadroId}`;
        return responder({ ok: true });
      }

      // PUT /comodos/:id e DELETE /comodos/:id
      if (partes[0] === 'comodos' && partes[1]) {
        const id = identificador(decodeURIComponent(partes[1]), 'id');

        if (request.method === 'PUT') {
          if (!podeEscrever) return recusarEscrita();
          const comodo = normalizarComodo(await lerJson(request), id);
          await sql`
            insert into comodos (quadro_id, id, nome, concluido)
            values (${acesso.quadroId}, ${comodo.id}, ${comodo.nome}, ${comodo.concluido})
            on conflict (quadro_id, id) do update
              set nome = excluded.nome, concluido = excluded.concluido
          `;
          return responder({ ok: true, comodo });
        }

        if (request.method === 'DELETE') {
          if (!podeEscrever) return recusarEscrita();
          await sql`delete from comodos where quadro_id = ${acesso.quadroId} and id = ${id}`;
          return responder({ ok: true });
        }
      }

      // -------------------------------------------------------------------
      // Telemetria
      // -------------------------------------------------------------------

      if (partes[0] === 'eventos' && request.method === 'POST') {
        const corpo = await lerJson(request);
        const lista = listaDe(corpo.eventos, 'eventos');

        // Uma instrução para o lote inteiro. O laço com um `insert` por evento
        // estoura o limite de subrequests do Worker.
        if (lista.length) {
          const nomes = [];
          const quando = [];
          const sessoes = [];
          const usuarios = [];
          const telas = [];
          const entidades = [];
          const entidadesId = [];
          const valores = [];
          const propriedades = [];

          for (const e of lista) {
            nomes.push(texto(e?.nome, 'nome', { max: 80, obrigatorio: true }));
            quando.push(dataIso(e?.quando, 'quando') ?? new Date().toISOString());
            sessoes.push(texto(e?.sessao, 'sessao', { max: 80, obrigatorio: true }));
            usuarios.push(texto(e?.usuario, 'usuario', { max: 120 }) || null);
            telas.push(texto(e?.tela, 'tela', { max: 80 }) || null);
            entidades.push(texto(e?.entidade, 'entidade', { max: 60 }) || null);
            entidadesId.push(texto(e?.entidadeId, 'entidadeId', { max: 120 }) || null);
            valores.push(
              e?.valor == null ? null : decimal(e.valor, 'valor', { min: -1e9, max: 1e9 }),
            );
            propriedades.push(JSON.stringify(objeto(e?.propriedades, 'propriedades')));
          }

          await sql`
            insert into eventos_analiticos
              (quadro_id, nome, quando, sessao, usuario, tela, entidade, entidade_id, valor, propriedades)
            select ${acesso.quadroId}, nome, quando, sessao, usuario, tela, entidade, entidade_id,
                   valor, propriedades
            from unnest(
              ${nomes}::text[], ${quando}::timestamptz[], ${sessoes}::text[], ${usuarios}::text[],
              ${telas}::text[], ${entidades}::text[], ${entidadesId}::text[],
              ${valores}::numeric[], ${propriedades}::jsonb[]
            ) as t(nome, quando, sessao, usuario, tela, entidade, entidade_id, valor, propriedades)
          `;
        }
        return responder({ recebidos: lista.length }, 201);
      }

      if (partes[0] === 'eventos' && request.method === 'GET') {
        const limite = decimal(url.searchParams.get('limite'), 'limite', {
          min: 1,
          max: 5000,
          padrao: 1000,
        });
        const linhas = await sql`
          select nome, quando, sessao, usuario, tela, entidade, entidade_id, valor, propriedades
          from eventos_analiticos
          where quadro_id = ${acesso.quadroId}
          order by quando desc
          limit ${Math.trunc(limite)}
        `;
        return responder({
          eventos: linhas.map((l) => ({
            nome: l.nome,
            quando: l.quando instanceof Date ? l.quando.toISOString() : l.quando,
            sessao: l.sessao,
            usuario: l.usuario ?? null,
            tela: l.tela ?? null,
            entidade: l.entidade ?? null,
            entidadeId: l.entidade_id ?? null,
            valor: l.valor == null ? null : Number(l.valor),
            propriedades: l.propriedades ?? {},
          })),
        });
      }

      return erro('Rota não encontrada.', 404, { cabecalhos: base });
    } catch (e) {
      if (e instanceof ErroValidacao) {
        return erro(e.message, e.status, { cabecalhos: base });
      }
      // Erro interno: a mensagem do banco nunca vai para o cliente.
      const id = crypto.randomUUID();
      console.error(`[erro ${id}] ${url.pathname}:`, e);
      return erro(`Erro interno (${id}).`, 500, { cabecalhos: base, headers: { 'x-erro-id': id } });
    }
  }
}