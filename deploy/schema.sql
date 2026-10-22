-- Minha Semana — schema
--
-- Objetivo: guardar o plano semanal de uma pessoa (marcações e cômodos) mais a
-- telemetria, atrás de login. O template da semana NÃO fica aqui: ele é
-- compilado no app, então mudar a rotina não exige migração de dados.
--
-- Este arquivo é idempotente: pode rodar mais de uma vez.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Quadros e acesso
--
-- Chama-se "quadro" e não "haras" porque aqui o dono é uma pessoa só; manter o
-- formato (quadro + vínculo + papel) deixa a porta aberta para mais de um quadro
-- por usuário sem mudar o contrato da API.
-- ---------------------------------------------------------------------------

create table if not exists quadros (
  id         uuid primary key default gen_random_uuid(),
  nome       text not null,
  criado_em  timestamptz not null default now()
);

create table if not exists usuario_quadros (
  usuario_id text not null,
  quadro_id  uuid not null references quadros(id) on delete cascade,
  papel      text not null default 'proprietario'
             check (papel in ('proprietario', 'operador', 'leitor')),
  primary key (usuario_id, quadro_id)
);

-- ---------------------------------------------------------------------------
-- Senha
-- ---------------------------------------------------------------------------

create table if not exists credenciais (
  usuario_id text primary key,
  hash       text not null,            -- PBKDF2 em base64
  salt       text not null,            -- salt em base64
  iteracoes  integer not null default 100000,
  criado_em  timestamptz not null default now(),
  trocado_em timestamptz,
  provisoria boolean not null default false
);

-- ---------------------------------------------------------------------------
-- Bloqueio por tentativa repetida
-- ---------------------------------------------------------------------------

create table if not exists tentativas_login (
  ip_hash    text not null,            -- sha256(ip + segredo), sem o IP em claro
  usuario_id text not null default '',
  quando     timestamptz not null default now(),
  sucesso    boolean not null default false
);

create index if not exists tentativas_ip_idx on tentativas_login (ip_hash, quando desc);
create index if not exists tentativas_usuario_idx on tentativas_login (usuario_id, quando desc);

-- ---------------------------------------------------------------------------
-- Estado da semana
-- ---------------------------------------------------------------------------

-- Uma linha por atividade concluída. O `id` é o do template (`seg-06:00`), o que
-- faz a marcação sobreviver a mudanças no template: inserir uma atividade nova
-- não remarca as outras.
create table if not exists atividades_concluidas (
  quadro_id    uuid not null references quadros(id) on delete cascade,
  atividade_id text not null,
  concluida_em timestamptz not null default now(),
  primary key (quadro_id, atividade_id)
);

-- Plano do usuário: uma linha por atividade de um dia.
--
-- O plano deixou de ser código no app e passou a ser dado: por isso esta tabela.
-- `id` é opaco e estável (o app não usa o horário como identidade), então editar
-- horário ou duração não perde a marcação em `atividades_concluidas`.
create table if not exists atividades (
  quadro_id       uuid not null references quadros(id) on delete cascade,
  dia             text not null check (dia in ('seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom')),
  id              text not null,
  horario         text not null check (horario ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  titulo          text not null,
  detalhe         text not null default '',
  duracao_minutos integer check (duracao_minutos is null or duracao_minutos between 1 and 1440),
  categoria       text not null default 'casa'
                  check (categoria in ('estudo', 'movimento', 'casa', 'bemEstar')),
  fixo            boolean not null default false,
  prioridade      boolean not null default false,
  atualizado_em   timestamptz not null default now(),
  primary key (quadro_id, id)
);

-- Leitura é sempre "as atividades deste dia, em ordem".
create index if not exists atividades_dia_idx on atividades (quadro_id, dia, horario);

-- Cômodos da reorganização. `ordem` preserva a ordem em que a pessoa os criou.
create table if not exists comodos (
  quadro_id  uuid not null references quadros(id) on delete cascade,
  id         text not null,
  nome       text not null,
  concluido  boolean not null default false,
  ordem      integer not null default 0,
  criado_em  timestamptz not null default now(),
  primary key (quadro_id, id)
);

create index if not exists comodos_quadro_idx on comodos (quadro_id, ordem);

-- ---------------------------------------------------------------------------
-- Telemetria
-- ---------------------------------------------------------------------------

create table if not exists eventos_analiticos (
  id           bigint generated always as identity primary key,
  quadro_id    uuid not null references quadros(id) on delete cascade,
  nome         text not null,
  quando       timestamptz not null default now(),
  sessao       text not null,
  usuario      text,
  tela         text,
  entidade     text,
  entidade_id  text,
  valor        numeric,
  propriedades jsonb not null default '{}'::jsonb
);

create index if not exists eventos_quadro_idx on eventos_analiticos (quadro_id, quando desc);
create index if not exists eventos_nome_idx on eventos_analiticos (quadro_id, nome);

-- ---------------------------------------------------------------------------
-- Funções de autorização
-- ---------------------------------------------------------------------------

-- Devolve o quadro e o papel do usuário. Usada a cada requisição autenticada.
-- O papel vem do banco (e não do token) para que revogar acesso valha na hora.
create or replace function quadro_do_usuario(p_usuario text)
returns table (quadro_id uuid, papel text)
language sql
stable
as $$
  select uq.quadro_id, uq.papel
  from usuario_quadros uq
  where uq.usuario_id = p_usuario
  order by uq.quadro_id
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- Dados iniciais
--
-- O quadrúplo (quadro, vínculo, credencial) de quem usa o app é criado pelo
-- script de provisionamento (`deploy/provisionar.py`), que lê a senha de um
-- arquivo local e grava só o hash. Nada de senha em SQL versionado.
-- ---------------------------------------------------------------------------
