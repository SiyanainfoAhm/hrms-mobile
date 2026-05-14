-- Allow signed-in users to upload reimbursement receipts under the same paths as
-- hrms-web `POST /api/reimbursements/upload` (bucket default `photomedia`):
--   HRMS/{company_id}/reimbursements/{uuid}_{filename}
--
-- Apply in Supabase SQL Editor after the `photomedia` bucket exists. If you use a
-- different bucket name, set `reimbursementStorageBucket` in mobile `config.json` and
-- duplicate this policy for that bucket id.

drop policy if exists "hrms_reimbursement_inserts_own_company" on storage.objects;

create policy "hrms_reimbursement_inserts_own_company"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'photomedia'
  and name like 'HRMS/%/reimbursements/%'
  and split_part(name, '/', 2) = (
    select u.company_id::text
    from "HRMS_users" u
    where u.id = auth.uid()
    limit 1
  )
);
