ALTER TABLE "Invoice" ADD COLUMN "paymentReviewRequired" BOOLEAN NOT NULL DEFAULT false;
CREATE TABLE "StripeMerchant" (
 "companyId" TEXT NOT NULL, "requestId" TEXT NOT NULL, "accountId" TEXT,
 "country" TEXT NOT NULL, "displayName" TEXT NOT NULL, "contactEmail" TEXT,
 "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL,
 CONSTRAINT "StripeMerchant_pkey" PRIMARY KEY ("companyId"),
 CONSTRAINT "StripeMerchant_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "StripeMerchant_requestId_key" ON "StripeMerchant"("requestId");
CREATE UNIQUE INDEX "StripeMerchant_accountId_key" ON "StripeMerchant"("accountId");
CREATE TABLE "InvoiceCheckoutAttempt" (
 "id" TEXT NOT NULL, "invoiceId" TEXT NOT NULL, "companyId" TEXT NOT NULL,
 "accountId" TEXT NOT NULL, "state" TEXT NOT NULL DEFAULT 'PREPARING',
 "amount" DECIMAL(12,2) NOT NULL, "currencyCode" TEXT NOT NULL, "paymentScope" TEXT NOT NULL,
 "sessionId" TEXT, "paymentIntentId" TEXT, "checkoutUrl" TEXT, "integrationIdentifier" TEXT NOT NULL,
 "refundedAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
 "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL,
 CONSTRAINT "InvoiceCheckoutAttempt_pkey" PRIMARY KEY ("id"),
 CONSTRAINT "InvoiceCheckoutAttempt_valid_state" CHECK ("state" IN ('PREPARING','OPEN','PROCESSING','PAID','EXPIRED','CANCELED','FAILED','REFUNDED')),
 CONSTRAINT "InvoiceCheckoutAttempt_valid_money" CHECK ("amount" > 0 AND "refundedAmount" >= 0 AND "refundedAmount" <= "amount"),
 CONSTRAINT "InvoiceCheckoutAttempt_invoiceId_fkey" FOREIGN KEY ("invoiceId") REFERENCES "Invoice"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "InvoiceCheckoutAttempt_sessionId_key" ON "InvoiceCheckoutAttempt"("sessionId");
CREATE UNIQUE INDEX "InvoiceCheckoutAttempt_paymentIntentId_key" ON "InvoiceCheckoutAttempt"("paymentIntentId");
CREATE INDEX "InvoiceCheckoutAttempt_companyId_createdAt_idx" ON "InvoiceCheckoutAttempt"("companyId", "createdAt");
CREATE INDEX "InvoiceCheckoutAttempt_invoiceId_state_idx" ON "InvoiceCheckoutAttempt"("invoiceId", "state");
CREATE UNIQUE INDEX "InvoiceCheckoutAttempt_one_active_per_invoice" ON "InvoiceCheckoutAttempt"("invoiceId") WHERE "state" IN ('PREPARING','OPEN','PROCESSING');
CREATE TABLE "StripePaymentEvent" (
 "id" TEXT NOT NULL, "companyId" TEXT NOT NULL, "accountId" TEXT NOT NULL, "processedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT "StripePaymentEvent_pkey" PRIMARY KEY ("id"),
 CONSTRAINT "StripePaymentEvent_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
