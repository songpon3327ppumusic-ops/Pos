create index if not exists business_document_attachments_document_id_idx on public.business_document_attachments(document_id);
create index if not exists business_document_attachments_created_by_idx on public.business_document_attachments(created_by) where created_by is not null;
