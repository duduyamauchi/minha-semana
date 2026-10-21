// Autenticação do Worker: senha, sessão e controle de acesso.
//
// Decisões (as mesmas do projeto de referência, que já passaram por produção):
//   * Senha com PBKDF2-HMAC-SHA256 via WebCrypto (nativo no runtime, sem
//     dependência). O runtime da Cloudflare recusa acima de 100 mil iterações,
//     então esse é o teto — e para não depender só dele a senha passa antes por
//     um HMAC com segredo do servidor (pepper): um dump do banco, sem o
//     segredo, não permite ataque offline nenhum.
//   * Sessão em cookie `HttpOnly` + `Secure` + `SameSite=Strict` assinado com
//     HMAC-SHA256. O token não fica em `localStorage`: um XSS não alcança a
//     credencial, e o `SameSite=Strict` bloqueia CSRF.
//   * O papel é lido do banco a cada requisição, não do token. Revogar o acesso
//     vale na requisição seguinte.
//
// O que NÃO se faz aqui: guardar segredo no bundle. `--dart-define` vai para o
// JavaScript publicado — serve para configuração pública, nunca para segredo.

const NOME_COOKIE = 'minha_semana_sessao';

// Teto absoluto: passadas 8 h, a sessão morre mesmo com uso contínuo.
const VALIDADE_SESSAO = 60 * 60 * 8;

// Inatividade: sem nenhuma requisição por 1 h, a sessão é encerrada.
//
// Quem entrasse de manhã continuaria autenticado à noite sem tocar em nada —
// numa máquina compartilhada, isso é uma porta aberta. O cookie carrega o
// instante do último uso; cada requisição autenticada o renova.
const INATIVIDADE_MAXIMA = 60 * 60;
const MARGEM_RENOVACAO = 60; // renova no máximo 1x por minuto

const ITERACOES_PBKDF2 = 100000;
const TAMANHO_HASH = 32; // bytes

// ---------------------------------------------------------------------------
// Codificação
// ---------------------------------------------------------------------------

export function bytesParaBase64(bytes) {
  let s = '';
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return btoa(s);
}

export function base64ParaBytes(texto) {
  const s = atob(texto);
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}

export function paraHex(buffer) {
  return [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Comparação em tempo constante: não revela o prefixo correto do hash. */
export function iguaisEmTempoConstante(a, b) {
  const x = new TextEncoder().encode(String(a));
  const y = new TextEncoder().encode(String(b));
  if (x.length !== y.length) return false;
  let dif = 0;
  for (let i = 0; i < x.length; i++) dif |= x[i] ^ y[i];
  return dif === 0;
}

// ---------------------------------------------------------------------------
// Senha
// ---------------------------------------------------------------------------

export function gerarSalt() {
  return bytesParaBase64(crypto.getRandomValues(new Uint8Array(16)));
}

/**
 * Material de entrada do PBKDF2: HMAC(senha, pepper).
 *
 * O pepper é segredo do servidor (`PEPPER_SENHA`). Sem ele, o hash guardado não
 * pode ser atacado offline — o atacante precisaria do banco *e* do segredo.
 */
async function comPepper(senha, pepper) {
  if (!pepper) throw new Error('PEPPER_SENHA ausente: sem ele o hash não pode ser conferido.');
  const chave = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(pepper),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return new Uint8Array(await crypto.subtle.sign('HMAC', chave, new TextEncoder().encode(senha)));
}

export async function derivarHash(senha, saltBase64, iteracoes = ITERACOES_PBKDF2, pepper) {
  const chave = await crypto.subtle.importKey(
    'raw',
    await comPepper(senha, pepper),
    'PBKDF2',
    false,
    ['deriveBits'],
  );
  const bits = await crypto.subtle.deriveBits(
    {
      name: 'PBKDF2',
      salt: base64ParaBytes(saltBase64),
      iterations: iteracoes,
      hash: 'SHA-256',
    },
    chave,
    TAMANHO_HASH * 8,
  );
  return bytesParaBase64(bits);
}

/** Confere a senha contra o registro guardado, em tempo constante. */
export async function conferirSenha(senha, registro, pepper) {
  if (!registro?.hash || !registro?.salt) return false;
  const calculado = await derivarHash(
    senha,
    registro.salt,
    registro.iteracoes ?? ITERACOES_PBKDF2,
    pepper,
  );
  return iguaisEmTempoConstante(calculado, registro.hash);
}

// ---------------------------------------------------------------------------
// Sessão assinada
// ---------------------------------------------------------------------------

const textoJson = (obj) => new TextEncoder().encode(JSON.stringify(obj));

const textoBase64Url = (texto) =>
  btoa(String.fromCharCode(...texto))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');

const deBase64Url = (texto) => {
  const t = texto.replace(/-/g, '+').replace(/_/g, '/');
  const s = atob(t + '='.repeat((4 - (t.length % 4)) % 4));
  return new Uint8Array([...s].map((c) => c.charCodeAt(0)));
};

async function assinar(dados, segredo) {
  const chave = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(segredo),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return textoBase64Url(new Uint8Array(await crypto.subtle.sign('HMAC', chave, textoJson(dados))));
}

/**
 * Emite o valor do cookie: `payload.assinatura`.
 *
 * `a` é o instante do último uso conhecido; sem ele a sessão nasce agora.
 */
export async function emitirSessao(usuarioId, segredo, agora = Date.now(), ultimoUso = null) {
  const segundos = Math.floor(agora / 1000);
  const dados = { u: usuarioId, e: segundos + VALIDADE_SESSAO, a: ultimoUso ?? segundos };
  const corpo = textoBase64Url(textoJson(dados));
  return `${corpo}.${await assinar(dados, segredo)}`;
}

/** Valida a assinatura e a expiração; devolve a sessão ou `null`. */
export async function lerSessao(valor, segredo, agora = Date.now()) {
  if (!valor || !segredo) return null;
  const [corpo, assinatura] = String(valor).split('.');
  if (!corpo || !assinatura) return null;

  let dados;
  try {
    dados = JSON.parse(new TextDecoder().decode(deBase64Url(corpo)));
  } catch {
    return null;
  }
  if (!dados?.u || !dados?.e) return null;

  // Compara a assinatura recalculada — nunca confia no payload sem conferir.
  const esperada = await assinar(dados, segredo);
  if (!iguaisEmTempoConstante(esperada, assinatura)) return null;

  if (dados.e * 1000 <= agora) return null;

  // Inatividade: `a` é o último uso. Sessão antiga sem `a` conta como expirada,
  // para não deixar passar cookie emitido antes desta regra.
  const ultimoUso = (dados.a ?? 0) * 1000;
  if (!ultimoUso || agora - ultimoUso >= INATIVIDADE_MAXIMA * 1000) return null;

  return {
    usuarioId: dados.u,
    expiraEm: dados.e * 1000,
    ultimoUso,
    renovavel: agora - ultimoUso >= MARGEM_RENOVACAO * 1000,
  };
}

/** Quanto falta para a sessão cair por inatividade, em segundos. */
export function segundosAteExpirar(sessao, agora = Date.now()) {
  const restante = sessao.ultimoUso + INATIVIDADE_MAXIMA * 1000 - agora;
  return Math.max(0, Math.floor(restante / 1000));
}

export { INATIVIDADE_MAXIMA, VALIDADE_SESSAO };

export function cookieDeSessao(valor, { seguro = true, maxAge = VALIDADE_SESSAO } = {}) {
  const partes = [`${NOME_COOKIE}=${valor}`, 'Path=/', 'HttpOnly', 'SameSite=Strict', `Max-Age=${maxAge}`];
  if (seguro) partes.push('Secure');
  return partes.join('; ');
}

export const cookieVazio = (seguro = true) => cookieDeSessao('', { seguro, maxAge: 0 });

export function lerCookie(cabecalhoCookie, nome = NOME_COOKIE) {
  if (!cabecalhoCookie) return null;
  for (const par of String(cabecalhoCookie).split(';')) {
    const i = par.indexOf('=');
    if (i < 0) continue;
    if (par.slice(0, i).trim() === nome) return par.slice(i + 1).trim();
  }
  return null;
}

// ---------------------------------------------------------------------------
// Sessão a partir da requisição
// ---------------------------------------------------------------------------

/**
 * Identidade da requisição.
 *
 * Aceita duas formas:
 *   * cookie de sessão (navegador);
 *   * `Authorization: Bearer` com um segredo de serviço, para chamadas
 *     máquina-a-máquina (sincronização, testes). Não é login de pessoa.
 */
export async function identificar(request, env) {
  const cookie = lerCookie(request.headers.get('cookie'));
  if (cookie) {
    const sessao = await lerSessao(cookie, env.SESSION_SECRET);
    if (sessao) {
      return {
        tipo: 'usuario',
        usuarioId: sessao.usuarioId,
        sessao,
        // O router assina um cookie novo quando isto é verdadeiro, renovando o
        // relógio de inatividade a cada uso real.
        renovar: sessao.renovavel ? sessao : null,
      };
    }
  }

  const auth = request.headers.get('authorization') ?? '';
  if (auth.startsWith('Bearer ')) {
    const token = auth.slice(7).trim();
    if (env.SERVICE_TOKEN && iguaisEmTempoConstante(token, env.SERVICE_TOKEN)) {
      return { tipo: 'servico', usuarioId: 'servico' };
    }
  }

  return { tipo: 'anonimo', usuarioId: null };
}

/**
 * Resolve o quadro e o papel do usuário. `null` quando não há acesso.
 *
 * Para o token de serviço usa `env.QUADRO_ID` e papel de proprietário — é o
 * caminho de migração/sincronização, não de operador humano.
 */
export async function acessoDe(sql, identidade, env) {
  if (identidade.tipo === 'servico') {
    return { quadroId: env.QUADRO_ID, papel: 'proprietario' };
  }
  if (identidade.tipo !== 'usuario') return null;

  const linhas = await sql`select * from quadro_do_usuario(${identidade.usuarioId})`;
  const linha = linhas[0];
  if (!linha) return null;
  return { quadroId: linha.quadro_id, papel: linha.papel };
}
