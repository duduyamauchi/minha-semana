-- Minha Semana — migração para calendário (marcações por data)
--
-- Bancos criados antes da edição por data tinham `atividades_concluidas` com PK
-- `(quadro_id, atividade_id)` — uma marcação valia para todas as semanas. Esta
-- migração acrescenta a data e troca a chave.
--
-- As marcações antigas **não têm data**: atribuí-las a um dia seria inventar
-- informação. Elas são descartadas; o template e os cômodos ficam intactos.
--
-- Idempotente: rodar de novo não muda nada.

do $$
begin
  -- 1. Coluna nova, nula na primeira passagem.
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'atividades_concluidas' and column_name = 'data'
  ) then
    alter table atividades_concluidas add column data date;
  end if;

  -- 2. Descarta linhas sem data (as antigas).
  delete from atividades_concluidas where data is null;

  -- 3. Troca a chave primária.
  if exists (
    select 1 from pg_constraint
    where conrelid = 'atividades_concluidas'::regclass
      and contype = 'p'
      and pg_get_constraintdef(oid) not like '%data%'
  ) then
    alter table atividades_concluidas drop constraint atividades_concluidas_pkey;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'atividades_concluidas'::regclass and contype = 'p'
  ) then
    alter table atividades_concluidas
      add constraint atividades_concluidas_pkey primary key (quadro_id, data, atividade_id);
  end if;

  -- 4. A coluna passa a ser obrigatória.
  alter table atividades_concluidas alter column data set not null;
end $$;

create index if not exists atividades_concluidas_data_idx
  on atividades_concluidas (quadro_id, data);
