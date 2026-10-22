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

/** Inteiro dentro de um intervalo; ausente devolve o padrão. */
function inteiro(valor, campo, { min = 0, max = 1_000_000, padrao = 0 } = {}) {
  if (valor == null || valor === '') return padrao;
  const n = Number(valor);
  if (!Number.isFinite(n)) throw new ErroValidacao(`Campo ${campo} deve ser numérico.`);
  const i = Math.trunc(n);
  if (i < min || i > max) throw new ErroValidacao(`Campo ${campo} fora do intervalo.`);
  return i;
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

/// Nomes dos dias, na ordem da semana.
const DIAS = ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'];

/// Categorias aceitas (as mesmas do app).
const CATEGORIAS = ['estudo', 'movimento', 'casa', 'bemEstar'];

/** `Date` do driver → `yyyy-MM-dd`, no fuso do banco (a coluna é `date`). */
function paraIsoData(valor) {
  if (typeof valor === 'string') return valor.slice(0, 10);
  const d = valor instanceof Date ? valor : new Date(valor);
  // `toISOString` usa UTC: numa coluna `date` lida como meia-noite UTC, o dia
  // já é o certo; formatar à mão evita depender disso.
  return d.toISOString().slice(0, 10);
}

/** Valida `yyyy-MM-dd` como data real. */
function dataCalendario(valor, campo) {
  const s = texto(valor, campo, { max: 10, obrigatorio: true });
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) {
    throw new ErroValidacao(`Campo ${campo} deve estar no formato AAAA-MM-DD.`);
  }
  const [ano, mes, dia] = s.split('-').map(Number);
  const d = new Date(Date.UTC(ano, mes - 1, dia));
  if (d.getUTCFullYear() !== ano || d.getUTCMonth() !== mes - 1 || d.getUTCDate() !== dia) {
    throw new ErroValidacao(`Campo ${campo} não é uma data válida.`);
  }
  return s;
}

/**
 * Lê o estado: template, marcações **por data** e cômodos de um quadro.
 *
 * Três consultas em paralelo, não N+1: o volume é pequeno (uma linha por
 * atividade do template, uma por marcação) e o Worker tem limite de
 * subrequests.
 *
 * `concluidas` é `{ "2026-10-21": ["qua-06:00", …] }`. A versão 4 do formato
 * trouxe a data: antes uma marcação valia para todas as semanas.
 *
 * `dias` só aparece quando há template gravado. O app usa a ausência para
 * migrar: estados antigos (v2) não tinham plano.
 */
async function lerSemana(sql, quadroId) {
  const [atividades, marcadas, comodos] = await Promise.all([
    sql`
      select dia, id, horario, titulo, detalhe, duracao_minutos, categoria, fixo, prioridade
      from atividades where quadro_id = ${quadroId}
      order by dia, horario, id
    `,
    sql`
      select data, atividade_id from atividades_concluidas
      where quadro_id = ${quadroId}
      order by data, atividade_id
    `,
    sql`select id, nome, concluido from comodos where quadro_id = ${quadroId} order by ordem, nome`,
  ]);

  const porDia = new Map(DIAS.map((d) => [d, []]));
  for (const a of atividades) {
    const lista = porDia.get(a.dia);
    if (!lista) continue;
    lista.push({
      id: a.id,
      dia: a.dia,
      horario: a.horario,
      titulo: a.titulo,
      detalhe: a.detalhe,
      duracaoMinutos: a.duracao_minutos == null ? null : Number(a.duracao_minutos),
      categoria: a.categoria,
      fixo: a.fixo,
      prioridade: a.prioridade,
    });
  }

  // Agrupa por data no servidor: o app espera um mapa, não uma lista.
  const concluidas = {};
  for (const linha of marcadas) {
    const chave = paraIsoData(linha.data);
    (concluidas[chave] ??= []).push(linha.atividade_id);
  }

  const corpo = {
    versao: 4,
    concluidas,
    comodos: comodos.map((c) => ({ id: c.id, nome: c.nome, concluido: c.concluido })),
  };
  // Plano vazio é ausência válida (a pessoa apagou tudo?) — mas o app só migra
  // quando `dias` não vem. Enviar dias vazios faria o app perder o template.
  if (atividades.length) {
    corpo.dias = DIAS.filter((d) => porDia.get(d).length).map((d) => ({
      chave: d,
      atividades: porDia.get(d),
    }));
  }
  return corpo;
}

/** Atividade vinda do app, validada e normalizada. */
function normalizarAtividade(valor, dia, idForcado = null) {
  const o = objeto(valor, 'atividade');
  const id = idForcado ?? identificador(o.id, 'id');
  const horario = texto(o.horario, 'horario', { max: 5, obrigatorio: true });
  if (!/^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(horario)) {
    throw new ErroValidacao('Campo horario deve estar no formato HH:mm.');
  }
  const categoria = texto(o.categoria, 'categoria', { max: 20, padrao: 'casa' });
  if (!CATEGORIAS.includes(categoria)) {
    throw new ErroValidacao(`Categoria desconhecida: ${categoria}.`);
  }
  const duracao = o.duracaoMinutos == null ? null : inteiro(o.duracaoMinutos, 'duracaoMinutos', {
    min: 1,
    max: 1440,
  });
  return {
    id,
    dia,
    horario,
    titulo: texto(o.titulo, 'titulo', { max: 120, obrigatorio: true }),
    detalhe: texto(o.detalhe, 'detalhe', { max: 300 }),
    duracaoMinutos: duracao,
    categoria,
    fixo: o.fixo === true,
    prioridade: o.prioridade === true,
  };
}

/** Grava (insert/update) uma atividade do plano. */
async function gravarAtividade(sql, quadroId, atividade) {
  await sql`
    insert into atividades (quadro_id, dia, id, horario, titulo, detalhe,
                            duracao_minutos, categoria, fixo, prioridade)
    values (${quadroId}, ${atividade.dia}, ${atividade.id}, ${atividade.horario},
            ${atividade.titulo}, ${atividade.detalhe}, ${atividade.duracaoMinutos},
            ${atividade.categoria}, ${atividade.fixo}, ${atividade.prioridade})
    on conflict (quadro_id, id) do update
      set dia = excluded.dia, horario = excluded.horario, titulo = excluded.titulo,
          detalhe = excluded.detalhe, duracao_minutos = excluded.duracao_minutos,
          categoria = excluded.categoria, fixo = excluded.fixo,
          prioridade = excluded.prioridade, atualizado_em = now()
  `;
}

/** Substitui o estado inteiro (importação de backup). */
async function gravarSemana(sql, quadroId, estado) {
  await sql`delete from atividades_concluidas where quadro_id = ${quadroId}`;
  await sql`delete from comodos where quadro_id = ${quadroId}`;
  if (estado.substituirPlano) {
    await sql`delete from atividades where quadro_id = ${quadroId}`;
  }

  // Marcações: uma instrução para todas as linhas. `datas` e `ids` vêm em
  // paralelo, um par por marcação.
  if (estado.datas.length) {
    await sql`
      insert into atividades_concluidas (quadro_id, data, atividade_id)
      select ${quadroId}, data, atividade_id
      from unnest(${estado.datas}::date[], ${estado.ids}::text[]) as t(data, atividade_id)
      on conflict do nothing
    `;
  }

  // Plano: um `insert` com `unnest`, pelo mesmo motivo das marcações.
  if (estado.atividades.length) {
    const a = estado.atividades;
    await sql`
      insert into atividades (quadro_id, dia, id, horario, titulo, detalhe,
                              duracao_minutos, categoria, fixo, prioridade)
      select ${quadroId}, dia, id, horario, titulo, detalhe, duracao, categoria, fixo, prioridade
      from unnest(
        ${a.map((x) => x.dia)}::text[], ${a.map((x) => x.id)}::text[],
        ${a.map((x) => x.horario)}::text[], ${a.map((x) => x.titulo)}::text[],
        ${a.map((x) => x.detalhe)}::text[], ${a.map((x) => x.duracaoMinutos)}::int[],
        ${a.map((x) => x.categoria)}::text[], ${a.map((x) => x.fixo)}::boolean[],
        ${a.map((x) => x.prioridade)}::boolean[]
      ) as t(dia, id, horario, titulo, detalhe, duracao, categoria, fixo, prioridade)
      on conflict (quadro_id, id) do nothing
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
  dias: 'plano editável: atividades de um dia',
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
          // Marcações por data: `{ "2026-10-21": ["qua-06:00"] }`.
          // `marcadas` (formato v3) é aceito e descartado — sem data não há
          // como atribuir a uma semana sem inventar.
          const datas = [];
          const ids = [];
          const concluidas = objeto(corpo.concluidas, 'concluidas');
          for (const [chave, lista] of Object.entries(concluidas)) {
            const data = dataCalendario(chave, 'concluidas');
            for (const id of listaDe(lista, 'concluidas')) {
              datas.push(data);
              ids.push(identificador(id, 'marcada'));
            }
          }
          const comodos = listaDe(corpo.comodos, 'comodos').map((c) => normalizarComodo(c));
          // Plano é opcional na carga: ausente significa "não mexe no plano".
          // É assim que um backup v2 (sem dias) continua válido.
          const atividades = [];
          for (const d of listaDe(corpo.dias, 'dias')) {
            const dia = objeto(d, 'dia');
            const chave = texto(dia.chave, 'chave', { max: 3, obrigatorio: true });
            if (!DIAS.includes(chave)) throw new ErroValidacao(`Dia inválido: ${chave}.`);
            for (const a of listaDe(dia.atividades, 'atividades')) {
              atividades.push(normalizarAtividade(a, chave));
            }
          }
          await gravarSemana(sql, acesso.quadroId, {
            datas,
            ids,
            comodos,
            atividades,
            substituirPlano: Array.isArray(corpo.dias),
          });
          return responder(await lerSemana(sql, acesso.quadroId));
        }
        return erro('Método não permitido em /semana.', 405, { cabecalhos: base });
      }

      // PUT /dias/:dia/atividades/:id — cria ou edita uma atividade do plano
      if (partes[0] === 'dias' && partes[1] && partes[2] === 'atividades') {
        const dia = texto(decodeURIComponent(partes[1]), 'dia', { max: 3, obrigatorio: true });
        if (!DIAS.includes(dia)) return erro(`Dia inválido: ${dia}.`, 400, { cabecalhos: base });

        if (request.method === 'PUT' && partes[3]) {
          if (!podeEscrever) return recusarEscrita();
          const id = identificador(decodeURIComponent(partes[3]), 'id');
          const atividade = normalizarAtividade(await lerJson(request), dia, id);
          await gravarAtividade(sql, acesso.quadroId, atividade);
          return responder({ ok: true, atividade });
        }

        if (request.method === 'DELETE' && partes[3]) {
          if (!podeEscrever) return recusarEscrita();
          const id = identificador(decodeURIComponent(partes[3]), 'id');
          await sql`
            delete from atividades where quadro_id = ${acesso.quadroId} and id = ${id} and dia = ${dia}
          `;
          // A marcação não pode sobreviver à atividade removida: senão o
          // percentual contaria um id que não existe mais.
          await sql`
            delete from atividades_concluidas
            where quadro_id = ${acesso.quadroId} and atividade_id = ${id}
          `;
          return responder({ ok: true, id });
        }

        return erro('Método não permitido em /dias/:dia/atividades.', 405, { cabecalhos: base });
      }

      // PUT /atividades/:data/:id — marca/desmarca numa data.
      //
      // A data faz parte da rota: a mesma atividade existe em todas as semanas,
      // e marcar a quarta não pode marcar todas as quartas.
      if (partes[0] === 'atividades' && partes[1] && partes[2] && request.method === 'PUT') {
        if (!podeEscrever) return recusarEscrita();
        const data = dataCalendario(decodeURIComponent(partes[1]), 'data');
        const id = identificador(decodeURIComponent(partes[2]), 'id');
        const corpo = await lerJson(request);
        if (typeof corpo.concluida !== 'boolean') {
          throw new ErroValidacao('Campo concluida deve ser booleano.');
        }
        if (corpo.concluida) {
          await sql`
            insert into atividades_concluidas (quadro_id, data, atividade_id)
            values (${acesso.quadroId}, ${data}::date, ${id})
            on conflict do nothing
          `;
        } else {
          await sql`
            delete from atividades_concluidas
            where quadro_id = ${acesso.quadroId} and data = ${data}::date and atividade_id = ${id}
          `;
        }
        return responder({ ok: true, data, id, concluida: corpo.concluida });
      }

      // DELETE /atividades?inicio=AAAA-MM-DD — desmarca a semana (segunda
      // informada, sete dias) ou, sem o parâmetro, tudo.
      if (partes[0] === 'atividades' && !partes[1] && request.method === 'DELETE') {
        if (!podeEscrever) return recusarEscrita();
        const inicio = url.searchParams.get('inicio');
        if (inicio == null || inicio === '') {
          await sql`delete from atividades_concluidas where quadro_id = ${acesso.quadroId}`;
          return responder({ ok: true, escopo: 'tudo' });
        }
        const data = dataCalendario(inicio, 'inicio');
        await sql`
          delete from atividades_concluidas
          where quadro_id = ${acesso.quadroId}
            and data between ${data}::date and (${data}::date + interval '6 days')
        `;
        return responder({ ok: true, escopo: 'semana', inicio: data });
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