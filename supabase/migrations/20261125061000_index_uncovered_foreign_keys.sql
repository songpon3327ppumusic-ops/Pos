-- Add indexes for foreign-key columns not already covered by a leading index.
do $$
declare r record; idx_name text;
begin
 for r in
  select con.conname as fk_name,c.relname as table_name,
   string_agg(format('%I',a.attname),',' order by u.ord) as quoted_columns
  from pg_constraint con
  join pg_class c on c.oid=con.conrelid
  join pg_namespace n on n.oid=c.relnamespace
  join lateral unnest(con.conkey) with ordinality u(attnum,ord) on true
  join pg_attribute a on a.attrelid=c.oid and a.attnum=u.attnum
  where con.contype='f' and n.nspname='public'
  and not exists (
   select 1 from pg_index i
   where i.indrelid=con.conrelid and i.indisvalid and i.indpred is null
   and (select array_agg(k.attnum order by k.ord) from unnest(i.indkey) with ordinality k(attnum,ord) where k.ord<=cardinality(con.conkey))=con.conkey
  )
  group by con.conname,c.relname
 loop
  idx_name:='idx_fk_'||left(md5(r.fk_name),12);
  execute format('create index if not exists %I on public.%I (%s)',idx_name,r.table_name,r.quoted_columns);
 end loop;
end $$;
