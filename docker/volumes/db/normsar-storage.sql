-- Normsar Silo — storage bucket + RLS policies.
--
-- On a self-hosted stack the storage schema (storage.buckets / storage.objects)
-- is created by the storage service at runtime, AFTER Postgres init. So the
-- main schema's storage block skips at db-init; the storage-init one-shot
-- container applies this file once the storage service is healthy. Idempotent.

INSERT INTO storage.buckets (id, name, public)
VALUES ('silo_uploads', 'silo_uploads', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Valid token holders can view files" ON storage.objects;
CREATE POLICY "Valid token holders can view files" ON storage.objects
FOR SELECT USING (
  (bucket_id = 'silo_uploads'::text) AND
  (((auth.jwt() ->> 'sub'::text))::uuid IS NOT NULL)
);

DROP POLICY IF EXISTS "Valid token holders can upload files" ON storage.objects;
CREATE POLICY "Valid token holders can upload files" ON storage.objects
FOR INSERT WITH CHECK (
  (bucket_id = 'silo_uploads'::text) AND
  (((auth.jwt() ->> 'sub'::text))::uuid IS NOT NULL)
);

DROP POLICY IF EXISTS "Users can delete their own files" ON storage.objects;
CREATE POLICY "Users can delete their own files" ON storage.objects
FOR DELETE USING (
  (bucket_id = 'silo_uploads'::text) AND
  ((string_to_array(name, '/'::text))[1] = (auth.jwt() ->> 'sub'::text))
);
