ALTER TABLE "Proposal" ADD COLUMN "changesRequestedAt" TIMESTAMP(3);
ALTER TABLE "Proposal" ADD COLUMN "requestedChangesMessage" TEXT;
ALTER TABLE "Proposal" ADD COLUMN "responseMessage" TEXT;
UPDATE "Proposal" SET "responseMessage" = "clientMessage" WHERE "respondedAt" IS NOT NULL;
CREATE TABLE "ProposalAcceptance" (
  "id" TEXT NOT NULL PRIMARY KEY, "proposalId" TEXT NOT NULL UNIQUE, "companyId" TEXT NOT NULL,
  "estimateId" TEXT NOT NULL, "estimateVersion" INTEGER NOT NULL, "documentHash" TEXT NOT NULL,
  "signerName" TEXT NOT NULL, "consentText" TEXT NOT NULL, "consentVersion" TEXT NOT NULL,
  "identityAssurance" TEXT NOT NULL DEFAULT 'SELF_ATTESTED', "acceptedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ProposalAcceptance_proposalId_fkey" FOREIGN KEY ("proposalId") REFERENCES "Proposal"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX "ProposalAcceptance_companyId_acceptedAt_idx" ON "ProposalAcceptance"("companyId", "acceptedAt");
CREATE FUNCTION preserve_proposal_acceptance() RETURNS trigger AS $$
BEGIN
  IF NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'Proposal acceptance evidence cannot be changed' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER "ProposalAcceptance_preserve_evidence" BEFORE UPDATE ON "ProposalAcceptance"
FOR EACH ROW EXECUTE FUNCTION preserve_proposal_acceptance();

CREATE TABLE "FollowUpSettings" (
  "companyId" TEXT NOT NULL PRIMARY KEY, "enabled" BOOLEAN NOT NULL DEFAULT false,
  "quoteDays" INTEGER NOT NULL DEFAULT 3, "invoiceDays" INTEGER NOT NULL DEFAULT 7,
  "enabledAt" TIMESTAMP(3), "updatedByUserId" TEXT, "lastCheckedAt" TIMESTAMP(3), "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "FollowUpSettings_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "FollowUpSettings_days_check" CHECK ("quoteDays" BETWEEN 1 AND 30 AND "invoiceDays" BETWEEN 1 AND 30)
);
CREATE TABLE "FollowUpMessage" (
  "id" TEXT NOT NULL PRIMARY KEY, "companyId" TEXT NOT NULL, "projectId" TEXT NOT NULL,
  "entityKind" TEXT NOT NULL, "entityId" TEXT NOT NULL, "dedupeKey" TEXT NOT NULL UNIQUE,
  "source" TEXT NOT NULL, "status" TEXT NOT NULL DEFAULT 'QUEUED', "attempts" INTEGER NOT NULL DEFAULT 0,
  "runAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "claimedUntil" TIMESTAMP(3), "attemptToken" TEXT,
  "firstAttemptAt" TIMESTAMP(3), "acceptedAt" TIMESTAMP(3), "deliveredAt" TIMESTAMP(3),
  "providerMessageId" TEXT UNIQUE, "recipientEmail" TEXT, "payloadJson" JSONB, "lastError" TEXT,
  "unsubscribeToken" TEXT NOT NULL UNIQUE, "createdByUserId" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "FollowUpMessage_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "FollowUpMessage_projectId_fkey" FOREIGN KEY ("projectId") REFERENCES "Project"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "FollowUpMessage_kind_check" CHECK ("entityKind" IN ('proposal', 'invoice')),
  CONSTRAINT "FollowUpMessage_source_check" CHECK ("source" IN ('MANUAL', 'AUTOMATIC')),
  CONSTRAINT "FollowUpMessage_status_check" CHECK ("status" IN ('QUEUED', 'SENDING', 'SENT', 'DELIVERED', 'FAILED', 'CANCELLED', 'BOUNCED', 'COMPLAINED'))
);
CREATE INDEX "FollowUpMessage_status_runAt_idx" ON "FollowUpMessage"("status", "runAt");
CREATE INDEX "FollowUpMessage_companyId_entityKind_entityId_createdAt_idx" ON "FollowUpMessage"("companyId", "entityKind", "entityId", "createdAt");
CREATE FUNCTION preserve_follow_up_payload() RETURNS trigger AS $$
BEGIN
  IF OLD."firstAttemptAt" IS NOT NULL AND (
    NEW."payloadJson" IS DISTINCT FROM OLD."payloadJson" OR
    NEW."recipientEmail" IS DISTINCT FROM OLD."recipientEmail" OR
    NEW."firstAttemptAt" IS DISTINCT FROM OLD."firstAttemptAt"
  ) THEN
    RAISE EXCEPTION 'A prepared follow-up payload cannot change during retries' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER "FollowUpMessage_preserve_payload" BEFORE UPDATE ON "FollowUpMessage"
FOR EACH ROW EXECUTE FUNCTION preserve_follow_up_payload();
CREATE TABLE "FollowUpSuppression" (
  "id" TEXT NOT NULL PRIMARY KEY, "companyId" TEXT NOT NULL, "projectId" TEXT NOT NULL, "entityKind" TEXT NOT NULL,
  "entityId" TEXT NOT NULL, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "FollowUpSuppression_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "FollowUpSuppression_projectId_fkey" FOREIGN KEY ("projectId") REFERENCES "Project"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "FollowUpSuppression_companyId_entityKind_entityId_key" ON "FollowUpSuppression"("companyId", "entityKind", "entityId");
