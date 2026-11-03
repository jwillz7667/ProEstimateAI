ALTER TABLE "Proposal"
  ADD COLUMN "sentRecipientClientId" TEXT,
  ADD COLUMN "sentRecipientEmail" TEXT,
  ADD COLUMN "sentRecipientName" TEXT;

-- Historical recipients cannot be reconstructed from a mutable project/client.
-- Leave them unknown; a reviewed revision is required for further email delivery.
CREATE OR REPLACE FUNCTION preserve_proposal_document_snapshot() RETURNS trigger AS $$
BEGIN
  IF OLD."sentSnapshot" IS NOT NULL AND (
    NEW."sentSnapshot" IS DISTINCT FROM OLD."sentSnapshot" OR
    NEW."sentSnapshotCapturedAt" IS DISTINCT FROM OLD."sentSnapshotCapturedAt" OR
    NEW."sentRecipientClientId" IS DISTINCT FROM OLD."sentRecipientClientId" OR
    NEW."sentRecipientEmail" IS DISTINCT FROM OLD."sentRecipientEmail" OR
    NEW."sentRecipientName" IS DISTINCT FROM OLD."sentRecipientName"
  ) THEN
    RAISE EXCEPTION 'Sent proposal documents and recipients cannot be replaced' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
