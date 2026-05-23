-- Apple's canonical idempotency key for App Store Server Notifications V2.
-- Stored on SubscriptionEvent rows that originate from a webhook so we can
-- short-circuit duplicate notifications at O(1) cost without depending on
-- the {entitlementId, transactionId, eventType} compound check.
--
-- Nullable because sync/restore-driven events have no notificationUUID.
-- Postgres treats NULLs as distinct under a UNIQUE constraint, so the
-- index doesn't collide for those rows.
ALTER TABLE "SubscriptionEvent"
  ADD COLUMN "notificationUUID" TEXT;

CREATE UNIQUE INDEX "SubscriptionEvent_notificationUUID_key"
  ON "SubscriptionEvent" ("notificationUUID");
