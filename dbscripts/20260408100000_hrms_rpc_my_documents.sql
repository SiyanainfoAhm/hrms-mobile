-- Employee onboarding / uploaded documents for profile "Documents" tab (mobile + RPC consumers)

create or replace function hrms_my_documents_list(p_user_id uuid)
returns jsonb
language sql
stable
security definer
as $$
  select coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'submission_id', s.id,
          'document_id', s.document_id,
          'document_name', d.name,
          'kind', d.kind::text,
          'status', s.status,
          'file_url', s.file_url,
          'signature_name', s.signature_name,
          'signed_at', s.signed_at,
          'submitted_at', s.submitted_at,
          'review_note', s.review_note
        )
        order by coalesce(s.submitted_at, s.signed_at, s.updated_at, s.created_at) desc nulls last
      )
      from "HRMS_employee_document_submissions" s
      inner join "HRMS_company_documents" d on d.id = s.document_id
      where s.user_id = p_user_id
    ),
    '[]'::jsonb
  );
$$;
