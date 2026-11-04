-- Freeze customer-visible documents at send time. Existing sent/decided rows
-- are captured from their CURRENT values: historical edits cannot be recovered.
ALTER TABLE "Estimate" ADD COLUMN "revisesEstimateId" TEXT;
ALTER TABLE "Estimate" ADD COLUMN "revisionRequestId" TEXT;
CREATE UNIQUE INDEX "Estimate_companyId_revisionRequestId_key" ON "Estimate"("companyId", "revisionRequestId");
CREATE INDEX "Estimate_revisesEstimateId_idx" ON "Estimate"("revisesEstimateId");
ALTER TABLE "Estimate" ADD CONSTRAINT "Estimate_revisesEstimateId_fkey" FOREIGN KEY ("revisesEstimateId") REFERENCES "Estimate"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "Proposal" ADD COLUMN "sentSnapshot" JSONB;
ALTER TABLE "Proposal" ADD COLUMN "sentSnapshotCapturedAt" TIMESTAMP(3);

UPDATE "Proposal" p SET
  "sentSnapshotCapturedAt" = CURRENT_TIMESTAMP AT TIME ZONE 'UTC',
  "sentSnapshot" = jsonb_build_object(
    'schema_version', 1,
    'estimate_id', e.id,
    'estimate_version', e.version,
    'captured_at', to_char(CURRENT_TIMESTAMP AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'capture_reason', 'legacy_backfill',
    'content', jsonb_build_object(
      'company', jsonb_build_object(
        'name', c.name, 'phone', c.phone, 'email', c.email,
        'address', c.address, 'city', c.city, 'state', c.state, 'zip', c.zip,
        'logo_url', c."logoUrl", 'primary_color', c."primaryColor", 'website_url', c."websiteUrl"
      ),
      'project', jsonb_build_object(
        'title', pr.title, 'description', pr.description, 'project_type', lower(pr."projectType"::text)
      ),
      'estimate', jsonb_build_object(
        'subtotal_materials', e."subtotalMaterials", 'subtotal_labor', e."subtotalLabor",
        'subtotal_other', e."subtotalOther", 'tax_amount', e."taxAmount",
        'discount_amount', e."discountAmount", 'total_amount', e."totalAmount",
        'line_items', COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'name', li.name, 'description', li.description, 'category', lower(li.category::text),
          'quantity', li.quantity, 'unit', li.unit, 'unit_cost', li."unitCost", 'line_total', li."lineTotal"
        ) ORDER BY li."sortOrder", li.id) FROM "EstimateLineItem" li WHERE li."estimateId" = e.id), '[]'::jsonb)
      ),
      'proposal', jsonb_build_object(
        'title', p.title, 'proposal_number', p."proposalNumber", 'status', lower(p.status::text),
        'intro_text', p."introText", 'scope_of_work', p."scopeOfWork", 'timeline_text', p."timelineText",
        'terms_and_conditions', p."termsAndConditions", 'footer_text', p."footerText",
        'client_message', p."clientMessage", 'hero_image_url', p."heroImageUrl",
        'expires_at', to_char(p."expiresAt", 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'sent_at', to_char(p."sentAt", 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'viewed_at', to_char(p."viewedAt", 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'responded_at', to_char(p."respondedAt", 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      ),
      'before_after_images', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'asset_id', a.id, 'asset_type', lower(a."assetType"::text), 'url', a.url, 'sort_order', a."sortOrder"
      ) ORDER BY a."sortOrder", a.id) FROM "Asset" a WHERE a."projectId" = pr.id), '[]'::jsonb)
    )
  )
FROM "Estimate" e, "Project" pr, "Company" c
WHERE p."estimateId" = e.id AND p."projectId" = pr.id AND p."companyId" = c.id
  AND p."sentSnapshot" IS NULL
  AND (p.status <> 'DRAFT' OR p."sentAt" IS NOT NULL OR p."respondedAt" IS NOT NULL);

-- Older send paths left the estimate DRAFT; close that edit window as well.
UPDATE "Estimate" e SET status = CASE
  WHEN EXISTS (SELECT 1 FROM "Proposal" p WHERE p."estimateId" = e.id AND p.status = 'APPROVED') THEN 'APPROVED'::"EstimateStatus"
  WHEN EXISTS (SELECT 1 FROM "Proposal" p WHERE p."estimateId" = e.id AND p.status = 'DECLINED') THEN 'DECLINED'::"EstimateStatus"
  ELSE 'SENT'::"EstimateStatus" END,
  "updatedAt" = CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
WHERE e.status = 'DRAFT' AND EXISTS (
  SELECT 1 FROM "Proposal" p WHERE p."estimateId" = e.id AND p."sentSnapshot" IS NOT NULL
);

-- A stored version is append-only even if a later code path accidentally
-- attempts to replace it. Account/project deletion remains explicitly supported.
CREATE FUNCTION preserve_proposal_document_snapshot() RETURNS trigger AS $$
BEGIN
  IF OLD."sentSnapshot" IS NOT NULL AND (
    NEW."sentSnapshot" IS DISTINCT FROM OLD."sentSnapshot" OR
    NEW."sentSnapshotCapturedAt" IS DISTINCT FROM OLD."sentSnapshotCapturedAt"
  ) THEN
    RAISE EXCEPTION 'Sent proposal documents cannot be replaced' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER "Proposal_preserve_sent_document" BEFORE UPDATE ON "Proposal"
FOR EACH ROW EXECUTE FUNCTION preserve_proposal_document_snapshot();
