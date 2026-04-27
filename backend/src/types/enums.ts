// Auth & Users
export type UserRole = "OWNER" | "ADMIN" | "ESTIMATOR" | "VIEWER";

// Projects
export type ProjectType =
  | "KITCHEN"
  | "BATHROOM"
  | "FLOORING"
  | "ROOFING"
  | "PAINTING"
  | "SIDING"
  | "ROOM_REMODEL"
  | "EXTERIOR"
  | "CUSTOM";

export type ProjectStatus =
  | "DRAFT"
  | "PHOTOS_UPLOADED"
  | "GENERATING"
  | "GENERATION_COMPLETE"
  | "ESTIMATE_CREATED"
  | "PROPOSAL_SENT"
  | "APPROVED"
  | "DECLINED"
  | "INVOICED"
  | "COMPLETED"
  | "ARCHIVED";

export type QualityTier = "STANDARD" | "PREMIUM" | "LUXURY";

// Assets
export type AssetType = "ORIGINAL" | "AI_GENERATED" | "DOCUMENT";

// AI
export type GenerationStatus = "QUEUED" | "PROCESSING" | "COMPLETED" | "FAILED";

// Estimates
export type EstimateStatus =
  | "DRAFT"
  | "SENT"
  | "APPROVED"
  | "DECLINED"
  | "EXPIRED";
export type LineItemCategory = "MATERIALS" | "LABOR" | "OTHER";

// Proposals
export type ProposalStatus =
  | "DRAFT"
  | "SENT"
  | "VIEWED"
  | "APPROVED"
  | "DECLINED"
  | "EXPIRED";

// Invoices
export type InvoiceStatus =
  | "DRAFT"
  | "SENT"
  | "VIEWED"
  | "PARTIALLY_PAID"
  | "PAID"
  | "OVERDUE"
  | "VOID";

// Commerce
export type PlanCode =
  | "FREE_STARTER"
  | "PRO_MONTHLY"
  | "PRO_ANNUAL"
  | "PREMIUM_MONTHLY"
  | "PREMIUM_ANNUAL";

export type EntitlementStatus =
  | "FREE"
  | "TRIAL_ACTIVE"
  | "PRO_ACTIVE"
  | "GRACE_PERIOD"
  | "BILLING_RETRY"
  | "CANCELED_ACTIVE"
  | "EXPIRED"
  | "REVOKED";

export type UsageMetricCode =
  | "AI_GENERATION"
  | "QUOTE_EXPORT"
  | "PROJECT_CREATED"
  | "ESTIMATE_GENERATED";
export type UsageResetPolicy = "NEVER" | "MONTHLY";

export type SubscriptionEventType =
  | "PURCHASED"
  | "RENEWED"
  | "TRIAL_STARTED"
  | "TRIAL_CONVERTED"
  | "CANCELED"
  | "EXPIRED"
  | "GRACE_PERIOD_STARTED"
  | "BILLING_RETRY_STARTED"
  | "REVOKED"
  | "RESTORED";

export type PurchaseAttemptStatus =
  | "PENDING"
  | "COMPLETED"
  | "FAILED"
  | "ABANDONED";

// Activity
export type ActivityAction =
  | "CREATED"
  | "UPDATED"
  | "STATUS_CHANGED"
  | "IMAGE_UPLOADED"
  | "GENERATION_STARTED"
  | "GENERATION_COMPLETED"
  | "ESTIMATE_CREATED"
  | "ESTIMATE_UPDATED"
  | "PROPOSAL_SENT"
  | "PROPOSAL_VIEWED"
  | "PROPOSAL_APPROVED"
  | "PROPOSAL_DECLINED"
  | "INVOICE_CREATED"
  | "INVOICE_SENT"
  | "INVOICE_PAID";

// Feature codes
export type FeatureCode =
  | "CAN_GENERATE_PREVIEW"
  | "CAN_EXPORT_QUOTE"
  | "CAN_REMOVE_WATERMARK"
  | "CAN_USE_BRANDING"
  | "CAN_CREATE_INVOICE"
  | "CAN_SHARE_APPROVAL_LINK"
  | "CAN_EXPORT_MATERIAL_LINKS"
  | "CAN_USE_HIGH_RES_PREVIEW";

// Paywall placements
export type PaywallPlacement =
  | "ONBOARDING_SOFT_GATE"
  | "POST_FIRST_GENERATION"
  | "POST_FIRST_QUOTE_EXPORT"
  | "GENERATION_LIMIT_HIT"
  | "QUOTE_LIMIT_HIT"
  | "INVOICE_LOCKED"
  | "BRANDING_LOCKED"
  | "APPROVAL_SHARE_LOCKED"
  | "WATERMARK_REMOVAL_LOCKED"
  | "SETTINGS_UPGRADE";
