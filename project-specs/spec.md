# ProEstimate AI — Full Product Spec and Build Instructions

This is the implementation spec to hand to a coding LLM. It is written so the coding model produces production-grade code for an iOS-first product with a web portal on Vercel and PostgreSQL on Railway. The visual direction should follow Apple’s current Liquid Glass/material guidance for layered, translucent UI, while the image preview engine should be built around Google’s Nano Banana 2, which Google describes as a high-efficiency image generation and editing model optimized for speed, high-volume use cases, conversational editing, and low-latency creative workflows. Vercel officially supports full-stack Next.js deployments, and Railway provides a zero-config PostgreSQL path that fits this stack well. ([Apple Developer][1])

## 1. Master instruction to the coding LLM

You are building a real product, not a demo. Every file, module, and screen must be written as if it will ship to production and be maintained by a professional team. Output only top-tier code quality. Favor clarity, composability, and long-term maintainability over shortcuts. Add concise comments to every major file and to important functions so another engineer can immediately understand what the code does, what it expects, what it returns, and what side effects it has.

Use these rules throughout implementation:

1. Never generate mock or placeholder logic unless the spec explicitly allows a stub.
2. Keep files small and focused.
3. Separate UI, state, domain logic, networking, persistence, and provider integrations.
4. Use strong typing everywhere.
5. Validate all external input.
6. Centralize design tokens, localization keys, and API types.
7. Keep secrets server-side only.
8. Do not let the iOS client call privileged AI or material-sourcing APIs directly.
9. Design every domain module so it can grow into teams, workspaces, subscriptions, and integrations.
10. Add robust loading, empty, retry, and error states for every asynchronous user flow.
11. Use explicit naming. Never use vague names like `data`, `temp`, `helper`, `manager2`.
12. Write code that is testable. Business logic must not be trapped inside views.
13. Favor deterministic services over magic abstractions.
14. Prefer feature-based organization over giant shared folders.
15. Keep comments useful and short. Explain intent, not the obvious.

## 2. Product definition

ProEstimate AI is an iOS-first AI estimating and invoicing platform for contractors, remodelers, and home project professionals. A user uploads room or job-site photos, describes the desired remodel or work scope, and the system:

* generates a remodel preview image with Nano Banana 2,
* extracts likely materials and labor categories,
* builds a draft estimate,
* converts it into a professional proposal,
* and can turn an approved proposal into an invoice.

The app supports English first and Spanish as a first-class localized experience.

This product is not just an invoice app and not just a visualization app. It is a revenue workflow tool. Its job is to help contractors quote faster, win more jobs, and produce better-looking client-facing documents.

## 3. Product goals

The product must make this sequence feel fast and obvious:

Photo upload -> AI remodel preview -> material suggestions -> draft estimate -> proposal -> invoice.

The user should feel that the app does the heavy lifting, but that they still remain fully in control of pricing, quantities, markup, tax, terms, and branding.

The most important product qualities are:

* speed,
* trust,
* editability,
* professional output,
* bilingual usability,
* premium but minimal iOS UX.

## 4. Platform and deployment architecture

The main app is iOS. The web app exists for admin, share, and client-view workflows. The backend is the source of truth.

Platform plan:

* iOS app: SwiftUI native app
* Web app: Next.js on Vercel
* API/backend: Node.js + TypeScript
* Database: PostgreSQL on Railway
* File storage: S3-compatible object storage
* Auth: email/password, magic link, Sign in with Apple for iOS, optional Google later
* Background jobs: queue worker process
* PDF generation: server-side document rendering service

Vercel’s current docs support Next.js full-stack deployment patterns, and Railway’s PostgreSQL template is suitable as the primary relational store. ([Vercel][2])

## 5. Users and roles

### Owner or admin

This user manages company branding, pricing profiles, taxes, numbering rules, templates, documents, subscription, and team members.

### Estimator or staff

This user creates projects, uploads photos, generates previews, edits estimates, and prepares proposals or invoices based on permissions.

### Client

This user receives a proposal link, views before-and-after visuals, reviews pricing and scope, and can approve, decline, or request changes.

## 6. Core user stories

The system must satisfy these jobs to be done.

As a contractor, I want to upload project photos and describe the work so the system can draft a visual preview and estimate.

As a contractor, I want materials and labor categories suggested automatically so I can quote faster.

As a contractor, I want to edit every number before sending anything to a client.

As a contractor, I want the final proposal to look custom-branded and professional, with project images included.

As a contractor, I want to generate invoices from approved estimates without rebuilding line items from scratch.

As a contractor, I want the product to work in English and Spanish, including UI and generated documents.

As a client, I want to understand what the finished project could look like and what I am paying for.

## 7. UX and visual direction

The app should feel native, premium, and minimal. The design language should use Apple-style layered translucent materials, soft depth, rounded cards, and strong typography, without becoming ornamental or cluttered. Apple’s current guidance describes Liquid Glass as a dynamic material for presenting controls and navigation without obscuring content, which fits this product’s image-heavy workflow well. ([Apple Developer][1])

### Visual personality

The product should feel like modern contractor software, not a toy AI app.

The emotional mix should be:

* professional,
* confident,
* clean,
* slightly premium,
* fast,
* field-ready.

### Color system

Light mode should use white backgrounds, soft neutral surfaces, charcoal text, and orange as the primary accent.

Dark mode should use near-black backgrounds, slightly lifted dark surfaces, white text, and the same orange accent.

Recommended colors:

* Primary orange: `#F97316`
* Light background: `#FFFFFF`
* Light surface: `#F8F9FB`
* Light border: `#E5E7EB`
* Dark background: `#0B0B0C`
* Dark surface: `#111214`
* Dark border: `#1F2937`
* Primary text light mode: `#111827`
* Primary text dark mode: `#F9FAFB`
* Secondary text light mode: `#6B7280`
* Secondary text dark mode: `#9CA3AF`
* Success: `#22C55E`
* Warning: `#F59E0B`
* Error: `#EF4444`

### Icon direction

The app icon should be a geometric orange checkmark integrated with a house roofline on a black background. No invoice glyph. No text. Thick shape. High-contrast. Recognizable at small size.

### Typography

Use SF Pro on iOS, with a clean fallback design system for the web. Typography should be bold for headings, clear for numbers, and highly legible in tables and forms.

### Motion

Use subtle spring-based transitions, depth changes, blurred material sheets, and polished loading transitions. Avoid flashy animations that slow task completion.

## 8. Information architecture

### iOS top-level navigation

The iOS app should have six primary areas:

* Dashboard
* Projects
* Estimates
* Invoices
* Clients
* Settings

### Project detail structure

Every project detail screen should have these sections:

* Overview
* Images
* AI Preview Versions
* Material Suggestions
* Estimate Versions
* Proposal
* Invoice
* Activity

### Web app structure

The web app is not the main product, but it must support these flows well:

* admin dashboard,
* estimate and invoice editing with larger layouts,
* branding and pricing settings,
* proposal share pages,
* client approval pages,
* light team management.

## 9. End-to-end user flow

### Flow 1: Create project

The user taps New Estimate on the dashboard. The app opens a guided creation flow. The user selects a project type such as kitchen, bathroom, flooring, roofing, painting, siding, room remodel, exterior, or custom. The user selects an existing client or creates a new one. The user uploads one or more room or job-site images. The user enters a project prompt in English or Spanish and optionally enters budget range, quality tier, finish preferences, dimensions, or square footage. The project is saved immediately in draft status and background jobs begin.

### Flow 2: Generate visual preview

Once the project is created, the backend constructs a structured prompt packet and sends the edit request to Nano Banana 2. Google’s current docs describe Nano Banana and Gemini 2.5 Flash Image as native image generation and editing capabilities optimized for high-volume, low-latency image workflows and conversational editing. That makes it appropriate for “show me the remodeled version of this exact room” previews. ([Google AI for Developers][3])

The app should show a clear progress sequence:

* uploading images,
* analyzing room,
* generating remodel preview,
* extracting materials,
* building estimate.

When the job completes, the project detail screen shows one or more generated variations.

### Flow 3: Build estimate

The backend turns project type, image metadata, prompt, preview output, and company pricing settings into a draft estimate. The user sees grouped line items by category. The user edits quantities, unit costs, labor hours, tax, markup, and notes. The user saves the estimate as a versioned document.

### Flow 4: Generate proposal

The user chooses an estimate version and taps Generate Proposal. The backend assembles a professional branded proposal containing company branding, before-and-after images, scope summary, material highlights, estimate table, assumptions, exclusions, timeline notes, and terms. The proposal is rendered as a PDF and a shareable web link.

### Flow 5: Generate invoice

The user converts an approved estimate or proposal into an invoice. The system copies line items, totals, taxes, discounts, and branding into a clean invoice layout. The invoice is exportable and shareable.

## 10. Functional scope

### V1 must include

Authentication. Company setup. Branding. Client management. Project creation. Image upload. Prompt entry in English or Spanish. Nano Banana 2 preview generation. Material suggestion pipeline. Draft estimate generation. Estimate editing. Proposal creation. Invoice creation. PDF export. Shareable proposal page. Bilingual UI and document templates. Core analytics and audit trail.

### V1.5 should include

Multiple estimate options per project. Pricing profiles by region. Reusable proposal templates. Client approval state tracking. Project notes and attachments. Better material-link management.

### V2 should include

Team accounts. Roles and permissions expansion. Supplier integrations. Affiliate material links. Signature capture. Payment collection. Automated reminders. CRM-like follow-up workflow.

## 11. Architecture overview

Think of the product as three systems.

The first system is the iOS app. It handles the user experience, project creation, image upload, estimate editing, and document viewing.

The second system is the backend orchestration layer. It owns project state, security, AI provider calls, pricing logic, document generation, asset lifecycle, and material sourcing.

The third system is the web app. It handles admin configuration, larger-screen editing workflows, and the share/approval experience for clients.

The backend is the source of truth. The iOS app and web app are clients of the backend.

## 12. Recommended tech stack

### iOS

Use SwiftUI. Use async/await. Use a feature-based architecture with isolated view models or observable state containers per feature. Keep networking in a centralized typed API client. Use PhotosPicker and camera integration. Store tokens securely in Keychain. Use string catalogs for localization.

### Web

Use Next.js App Router with TypeScript on Vercel. Use Tailwind CSS or a similarly disciplined design token system. Use typed API clients or server actions only where appropriate. Keep the web app focused on admin and client-share experiences.

### Backend

Use Node.js with TypeScript. Use either NestJS or Fastify, but choose one and stay consistent. Use Zod for validation. Use Prisma or Drizzle for the ORM, but choose one and stay consistent. Use a background job worker. Use a storage adapter abstraction for object storage. Use provider abstractions for Nano Banana 2 and future AI providers.

### Database

Use PostgreSQL on Railway.

### Storage

Use S3-compatible object storage for originals, generated previews, logos, and PDFs.

### Background jobs

Use a queue-backed worker system so long-running jobs do not block request-response cycles.

## 13. Monorepo structure

Use a monorepo. Suggested layout:

`apps/ios`
This is the native iOS app.

`apps/web`
This is the Vercel-hosted web app for admin and share pages.

`apps/api`
This is the Node.js backend.

`packages/types`
Shared domain types and DTOs.

`packages/ui-tokens`
Shared color, spacing, radius, typography, and semantic tokens.

`packages/i18n`
Shared localization keys, namespaces, and translation tooling.

`packages/pdf-templates`
Proposal and invoice layout composition logic.

`packages/config`
Shared lint, formatting, TS config, and tooling settings.

## 14. iOS screen-by-screen spec

### Launch and authentication

The app launches into a minimal branded splash. Restore session if possible. Authentication supports email/password, magic link, and Sign in with Apple. Language can be selected immediately.

### Dashboard

The dashboard should be clean and easy. This is the main operational screen. It should open fast and show only the most useful information.

It should include:

* a translucent top bar with company identity and profile access,
* a large primary CTA for New Estimate,
* a compact revenue or conversion summary,
* recent projects,
* pending approvals,
* unpaid invoices,
* quick filters.

The dashboard should feel airy, not dense. Strong spacing. Large rounded cards. Orange should be used to guide action, not flood the screen.

### New project flow

The create-project flow should be multi-step, but fast. Each step should show progress and keep the user focused on one decision at a time.

Step 1: choose project type.
Step 2: choose or create client.
Step 3: upload photos.
Step 4: enter prompt.
Step 5: add optional dimensions, budget tier, finish tier, and language.
Step 6: submit and begin AI processing.

### Project detail

This screen is the heart of the product.

It should contain:

* header summary with status and key totals,
* before images,
* AI preview carousel,
* material suggestions,
* estimate version list,
* actions to edit estimate, generate proposal, create invoice,
* activity feed.

The user should be able to move from visual concept to numbers without leaving the project context.

### Estimate editor

This needs to be extremely clean and controllable. It should support grouped categories, editable fields, notes, and total rollups without feeling like enterprise bloat.

Sections:

* materials,
* labor,
* other,
* taxes and discounts,
* assumptions and exclusions,
* totals.

Every line item should show quantity, unit, unit cost, line subtotal, tax, and total. Swipe or contextual actions can support delete, duplicate, and convert to template.

### Proposal preview

This should feel premium. Use large imagery, clean type hierarchy, and strong spacing. The preview should include a before-and-after hero, scope section, material highlights, estimate table, terms, and approval actions.

### Invoice preview

This should be more compact and operational. Strong emphasis on invoice number, dates, client info, totals, and payment instructions.

### Settings

Settings should include company branding, language defaults, tax rules, numbering prefixes, pricing profiles, labor rules, team management, and document template controls.

## 15. Nano Banana 2 integration spec

### Role in the system

Nano Banana 2 is the visual preview engine. It is not the pricing engine, materials source of truth, or billing system. It generates or edits room images to represent the likely finished result.

Google’s docs list Nano Banana 2 in the Gemini API model lineup and describe Nano Banana image generation as native image generation and editing capabilities suitable for contextual image creation and modification. The current release notes also indicate Nano Banana 2 launched in late February 2026 as a high-efficiency model for speed and high-volume use. ([Google AI for Developers][4])

### Integration rules

The iOS app must never call the AI provider with privileged credentials directly. All AI requests must go through the backend.

Store originals and generated outputs separately.

Store all generation metadata for auditing and reproducibility.

Treat generated visuals as proposal assets, not exact contractual or estimating truth.

### Generation pipeline

The user uploads images. The backend stores the originals. The backend normalizes the prompt. If the user entered Spanish, preserve the original but also create a normalized internal prompt for the generation layer. The backend builds a structured edit prompt that emphasizes preserving room geometry, perspective, and camera angle while applying the requested remodel.

The backend sends the request to Nano Banana 2 with the source image and structured text instructions.

When outputs return, save them as assets, link them to a generation record, and attach them to the project.

Then pass the generation result and project context into the materials and estimate pipeline.

### Generation metadata to store

Every generation record must include:

* project id,
* input image asset ids,
* output image asset ids,
* original prompt,
* normalized prompt,
* prompt language,
* provider name,
* provider model,
* provider request id,
* generation status,
* timestamps,
* error details,
* request payload snapshot,
* response payload snapshot.

### Prompt composition rules

Do not send raw user text only. Build structured prompts.

Example structure:

Preserve room geometry and camera angle. Remodel this uploaded kitchen photo. Replace cabinets with warm oak shaker cabinets. Add white quartz counters with subtle veining. Add matte black hardware. Add warm under-cabinet lighting. Maintain realistic material textures and correct proportions. Output a photoreal remodel preview suitable for client proposal use.

### Failure behavior

If generation fails, preserve project state, log the error, and show a retry path in the UI. Never lose the uploaded originals. Never block estimate creation permanently because preview generation failed.

## 16. Material suggestion and sourcing engine

This subsystem exists to bridge the visual concept and the estimate.

It should generate a draft list of likely materials and project components such as:

* flooring,
* paint,
* cabinetry,
* countertops,
* fixtures,
* trim,
* lighting,
* tile,
* hardware,
* appliances,
* labor categories.

Each suggestion should store:

* category,
* name,
* description,
* estimated quantity,
* unit,
* estimated unit cost,
* supplier if available,
* source link if available,
* confidence score,
* optional image.

The user must be able to remove suggestions, override quantities, replace items, and choose whether client-facing documents show sourcing links.

The app must not imply that every product recommendation is an exact match to the AI preview. If exact product matching is not guaranteed, label recommendations as similar items or suggested materials.

## 17. Estimation engine

### Purpose

Generate a usable draft estimate quickly, but keep everything editable.

### Inputs

The estimate pipeline should use:

* project type,
* project prompt,
* original images,
* preview metadata,
* optional room dimensions,
* company pricing profile,
* region defaults,
* labor rates,
* tax settings,
* markup rules,
* waste factor,
* contingency rules.

### Outputs

The system must output:

* estimate header,
* grouped line items,
* material subtotal,
* labor subtotal,
* tax,
* discount,
* contingency,
* total,
* assumptions,
* exclusions.

### Business logic principles

Use deterministic pricing logic. AI can help infer categories and draft quantities, but every total must roll up through clear business rules.

The pricing engine must support:

* labor markup,
* material markup,
* waste factor,
* contingency percent,
* tax rate,
* discounts,
* flat-rate items,
* per-unit items,
* hourly labor.

The estimate editor must allow overrides for all important values.

## 18. Proposal generation

The proposal is the polished client-facing sales document.

Required sections:

* cover or header,
* company branding,
* client and project summary,
* before-and-after visuals,
* scope of work,
* material highlights,
* line-item estimate summary,
* assumptions,
* exclusions,
* timeline text,
* terms,
* approval section.

The PDF must be generated server-side. It must support English and Spanish. It must embed images and clickable material links when enabled. It must handle pagination cleanly and avoid ugly table splits.

The proposal should also have a shareable web view with a secure token.

## 19. Invoice generation

The invoice should derive from the estimate or proposal whenever possible. The goal is to avoid duplicate data entry.

Invoice sections:

* company branding,
* invoice number,
* client details,
* project reference,
* issued and due dates,
* itemized charges,
* subtotal,
* tax,
* discount,
* total,
* balance due,
* notes,
* payment instructions.

## 20. Localization spec

English is primary. Spanish is fully supported.

Localization must cover:

* UI text,
* validation messages,
* system states,
* notification copy,
* proposal templates,
* invoice templates,
* estimate field labels,
* onboarding.

Never mix languages in a generated document unless the user explicitly selects bilingual output.

Store both user preferred language and company default language.

Allow prompt entry in either language. Preserve the original prompt for auditability. Internally normalize or translate as needed for consistent downstream processing.

## 21. Security requirements

This system is multi-tenant. Tenant scoping is mandatory on every query.

Requirements:

* all company data must be isolated by company id,
* use signed URLs for private asset access,
* keep AI keys server-side only,
* rate limit generation and export endpoints,
* log sensitive document actions,
* secure share links with high-entropy tokens,
* validate and sanitize all text rendered into PDFs,
* enforce role-based access controls,
* store passwords securely if used,
* support audit trails for critical document and pricing edits.

## 22. Performance requirements

The dashboard should feel immediate. Project creation should save instantly, even if AI work continues in the background. Image uploads should show optimistic placeholders. Long-running tasks should be job-based, not synchronous request locks.

The backend should offload generation, sourcing, and PDF rendering to worker jobs. Synchronous APIs should remain fast and return status handles where appropriate.

The web share pages should load quickly and render cleanly on mobile.

## 23. API design principles

Use versioned endpoints.

Use typed request and response contracts.

Support polling or push for long-running generation and export jobs.

Use idempotency keys for operations that may be retried.

Return structured error objects.

Use cursor pagination where lists can grow.

Do not over-fetch large nested objects by default.

### Example endpoint groups

Authentication endpoints. Company settings endpoints. Client endpoints. Project endpoints. Asset upload endpoints. Generation endpoints. Estimate endpoints. Proposal endpoints. Invoice endpoints. Share endpoints. Analytics endpoints.

Examples of key operations:

* create project,
* upload asset,
* start preview generation,
* fetch generation status,
* create estimate draft,
* update estimate,
* create proposal,
* export proposal PDF,
* create invoice,
* export invoice PDF,
* fetch share page.

## 24. Complete PostgreSQL schema

The schema below is normalized for versioning, auditability, and long-term growth.

### Table: companies

Fields:

* id UUID primary key
* name TEXT not null
* slug TEXT unique not null
* default_language TEXT not null default `'en'`
* timezone TEXT not null default `'America/Chicago'`
* logo_asset_id UUID nullable
* primary_color TEXT nullable
* secondary_color TEXT nullable
* estimate_prefix TEXT nullable
* proposal_prefix TEXT nullable
* invoice_prefix TEXT nullable
* tax_label TEXT nullable
* tax_rate NUMERIC(8,4) nullable
* currency_code TEXT not null default `'USD'`
* phone TEXT nullable
* email TEXT nullable
* website_url TEXT nullable
* address_line_1 TEXT nullable
* address_line_2 TEXT nullable
* city TEXT nullable
* state_region TEXT nullable
* postal_code TEXT nullable
* country_code TEXT not null default `'US'`
* created_at TIMESTAMPTZ not null default `now()`
* updated_at TIMESTAMPTZ not null default `now()`

### Table: users

Fields:

* id UUID primary key
* company_id UUID not null references companies(id)
* email TEXT unique not null
* password_hash TEXT nullable
* full_name TEXT not null
* role TEXT not null
* preferred_language TEXT not null default `'en'`
* is_active BOOLEAN not null default `true`
* last_login_at TIMESTAMPTZ nullable
* created_at TIMESTAMPTZ not null default `now()`
* updated_at TIMESTAMPTZ not null default `now()`

### Table: user_identities

Fields:

* id UUID primary key
* user_id UUID not null references users(id)
* provider TEXT not null
* provider_subject TEXT not null
* created_at TIMESTAMPTZ not null default `now()`
  Constraints:
* unique(provider, provider_subject)

### Table: clients

Fields:

* id UUID primary key
* company_id UUID not null references companies(id)
* first_name TEXT nullable
* last_name TEXT nullable
* company_name TEXT nullable
* email TEXT nullable
* phone TEXT nullable
* preferred_language TEXT not null default `'en'`
* address_line_1 TEXT nullable
* address_line_2 TEXT nullable
* city TEXT nullable
* state_region TEXT nullable
* postal_code TEXT nullable
* country_code TEXT not null default `'US'`
* notes TEXT nullable
* created_at TIMESTAMPTZ not null default `now()`
* updated_at TIMESTAMPTZ not null default `now()`

### Table: projects

Fields:

* id UUID primary key
* company_id UUID not null references companies(id)
* client_id UUID nullable references clients(id)
* created_by_user_id UUID not null references users(id)
* title TEXT not null
* description TEXT nullable
* project_type TEXT not null
* status TEXT not null default `'draft'`
* source_language TEXT not null default `'en'`
* display_language TEXT not null default `'en'`
* budget_min NUMERIC(12,2) nullable
* budget_max NUMERIC(12,2) nullable
* room_type TEXT nullable
* site_address_line_1 TEXT nullable
* site_address_line_2 TEXT nullable
* site_city TEXT nullable
* site_state_region TEXT nullable
* site_postal_code TEXT nullable
* site_country_code TEXT not null default `'US'`
* square_footage NUMERIC(10,2) nullable
* dimensions_json JSONB nullable
* metadata_json JSONB nullable
* created_at TIMESTAMPTZ not null default `now()`
* updated_at TIMESTAMPTZ not null default `now()`

### Table: project_members

Fields:

* id UUID primary key
* project_id UUID not null references projects(id)
* user_id UUID not null references users(id)
* role TEXT not null
* created_at TIMESTAMPTZ not null default `now()`
  Constraints:
* unique(project_id, user_id)

### Table: assets

Fields:

* id UUID primary key
* company_id UUID not null references companies(id)
* project_id UUID nullable references projects(id)
* uploaded_by_user_id UUID nullable references users(id)
* storage_key TEXT not null unique
* original_filename TEXT nullable
* mime_type TEXT not null
* byte_size BIGINT not null
* width INT nullable
* height INT nullable
* kind TEXT not null
* checksum_sha256 TEXT nullable
* metadata_json JSONB nullable
* created_at TIMESTAMPTZ not null default `now()`

### Table: project_images

Fields:

* id UUID primary key
* project_id UUID not null references projects(id)
* asset_id UUID not null references assets(id)
* image_role TEXT not null
* sort_order INT not null default `0`
* created_at TIMESTAMPTZ not null default `now()`

### Table: ai_generations

Fields:

* id UUID primary key
* company_id UUID not null references companies(id)
* project_id UUID not null references projects(id)
* initiated_by_user_id UUID not null references users(id)
* provider_name TEXT not null
* provider_model TEXT not null
* generation_type TEXT not null
* status TEXT not null
* prompt_language TEXT not null
* original_prompt TEXT not null
* normalized_prompt TEXT not null
* request_payload_json JSONB nullable
* response_payload_json JSONB nullable
* provider_request_id TEXT nullable
* error_code TEXT nullable
* error_message TEXT nullable
* started_at TIMESTAMPTZ nullable
* completed_at TIMESTAMPTZ nullable
* created_at TIMESTAMPTZ not null default `now()`

### Table: ai_generation_inputs

Fields:

* id UUID primary key
* ai_generation_id UUID not null references ai_generations(id)
* asset_id UUID not null references assets(id)
* created_at TIMESTAMPTZ not null default `now()`

### Table: ai_generation_outputs

Fields:

* id UUID primary key
* ai_generation_id UUID not null references ai_generations(id)
* asset_id UUID not null references assets(id)
* variant_index INT not null
* created_at TIMESTAMPTZ not null default `now()`

### Table: material_catalog_items

Fields:

* id UUID primary key
* company_id UUID nullable references companies(id)
* source_system TEXT not null
* external_id TEXT nullable
* supplier_name TEXT nullable
* category TEXT not null
* subcategory TEXT nullable
* name TEXT not null
* description TEXT nullable
* image_url TEXT nullable
* product_url TEXT nullable
* unit TEXT nullable
* base_unit_cost NUMERIC(12,2) nullable
* currency_code TEXT not null default `'USD'`
* metadata_json JSONB nullable
* created_at TIMESTAMPTZ not null default `now()`
* updated_at TIMESTAMPTZ not null default `now()`

### Table: project_material_suggestions

Fields:

* id UUID primary key
* project_id UUID not null references projects(id)
* ai_generation_id UUID nullable references ai_generations(id)
* category TEXT not null
* subcategory TEXT nullable
* name TEXT not null
* description TEXT nullable
* estimated_quantity NUMERIC(12,2) nullable
* unit TEXT nullable
* unit_cost_estimate NUMERIC(12,2) nullable
* material_catalog_item_id UUID nullable references material_catalog_items(id)
* confidence_score NUMERIC(5,4) nullable
* notes TEXT nullable
* created_at TIMESTAMPTZ not null default `now()`

### Table: pricing_profiles

Fields:

* id UUID primary key
* company_id UUID not null references companies(id)
* name TEXT not null
* region_code TEXT nullable
* labor_markup_percent NUMERIC(8,4) nullable
* material_markup_percent NUMERIC(8,4) nullable
* contingency_percent NUMERIC(8,4) nullable
* waste_factor_percent NUMERIC(8,4) nullable
* tax_rate NUMERIC(8,4) nullable
* is_default BOOLEAN not null default `false`
* created_at TIMESTAMPTZ not null default `now()`
* updated_at TIMESTAMPTZ not null default `now()`

### Table: labor_rate_rules

Fields:

* id UUID primary key
* pricing_profile_id UUID not null references pricing_profiles(id)
* category TEXT not null
* rate_type TEXT not null
* hourly_rate NUMERIC(12,2) nullable
* flat_rate NUMERIC(12,2) nullable
* unit_rate NUMERIC(12,2) nullable
* unit TEXT nullable
* created_at TIMESTAMPTZ not null default `now()`
* updated_at TIMESTAMPTZ not null default `now()`

### Table: estimates

Fields:

* id UUID primary key
* company_id UUID not null references companies(id)
* project_id UUID not null references projects(id)
* pricing_profile_id UUID nullable references pricing_profiles(id)
* created_by_user_id UUID not null references users(id)
* version_number INT not null
* status TEXT not null default `'draft'`
* title TEXT not null
* notes TEXT nullable
* assumptions TEXT nullable
* exclusions TEXT nullable
* subtotal_materials NUMERIC(12,2) not null default `0`
* subtotal_labor NUMERIC(12,2) not null default `0`
* subtotal_other NUMERIC(12,2) not null default `0`
* subtotal NUMERIC(12,2) not null default `0`
* tax_amount NUMERIC(12,2) not null default `0`
* discount_amount NUMERIC(12,2) not null default `0`
* contingency_amount NUMERIC(12,2) not null default `0`
* total_amount NUMERIC(12,2) not null default `0`
* currency_code TEXT not null default `'USD'`
* created_at TIMESTAMPTZ not null default `now()`
* updated_at TIMESTAMPTZ not null default `now()`
  Constraints:
* unique(project_id, version_number)

### Table: estimate_line_items

Fields:

* id UUID primary key
* estimate_id UUID not null references estimates(id)
* parent_line_item_id UUID nullable references estimate_line_items(id)
* item_type TEXT not null
* category TEXT not null
* subcategory TEXT nullable
* name TEXT not null
* description TEXT nullable
* quantity NUMERIC(12,2) not null default `1`
* unit TEXT nullable
* unit_cost NUMERIC(12,2) not null default `0`
* markup_percent NUMERIC(8,4) nullable
* tax_rate NUMERIC(8,4) nullable
* line_subtotal NUMERIC(12,2) not null default `0`
* line_tax NUMERIC(12,2) not null default `0`
* line_total NUMERIC(12,2) not null default `0`
* sort_order INT not null default `0`
* material_catalog_item_id UUID nullable references material_catalog_items(id)
* source_material_suggestion_id UUID nullable references project_material_suggestions(id)
* metadata_json JSONB nullable
* created_at TIMESTAMPTZ not null default `now()`
* updated_at TIMESTAMPTZ not null default `now()`

### Table: proposals

Fields:

* id UUID primary key
* company_id UUID not null references companies(id)
* project_id UUID not null references projects(id)
* estimate_id UUID not null references estimates(id)
* created_by_user_id UUID not null references users(id)
* proposal_number TEXT not null
* status TEXT not null default `'draft'`
* title TEXT not null
* intro_text TEXT nullable
* scope_of_work TEXT nullable
* timeline_text TEXT nullable
* terms_text TEXT nullable
* footer_text TEXT nullable
* hero_image_asset_id UUID nullable references assets(id)
* pdf_asset_id UUID nullable references assets(id)
* share_token TEXT unique nullable
* shared_at TIMESTAMPTZ nullable
* client_viewed_at TIMESTAMPTZ nullable
* approved_at TIMESTAMPTZ nullable
* declined_at TIMESTAMPTZ nullable
* created_at TIMESTAMPTZ not null default `now()`
* updated_at TIMESTAMPTZ not null default `now()`

### Table: invoices

Fields:

* id UUID primary key
* company_id UUID not null references companies(id)
* project_id UUID nullable references projects(id)
* client_id UUID nullable references clients(id)
* estimate_id UUID nullable references estimates(id)
* proposal_id UUID nullable references proposals(id)
* created_by_user_id UUID not null references users(id)
* invoice_number TEXT not null
* status TEXT not null default `'draft'`
* issued_date DATE nullable
* due_date DATE nullable
* notes TEXT nullable
* payment_instructions TEXT nullable
* subtotal NUMERIC(12,2) not null default `0`
* tax_amount NUMERIC(12,2) not null default `0`
* discount_amount NUMERIC(12,2) not null default `0`
* total_amount NUMERIC(12,2) not null default `0`
* amount_paid NUMERIC(12,2) not null default `0`
* balance_due NUMERIC(12,2) not null default `0`
* currency_code TEXT not null default `'USD'`
* pdf_asset_id UUID nullable references assets(id)
* created_at TIMESTAMPTZ not null default `now()`
* updated_at TIMESTAMPTZ not null default `now()`

### Table: invoice_line_items

Fields:

* id UUID primary key
* invoice_id UUID not null references invoices(id)
* name TEXT not null
* description TEXT nullable
* quantity NUMERIC(12,2) not null default `1`
* unit TEXT nullable
* unit_price NUMERIC(12,2) not null default `0`
* tax_rate NUMERIC(8,4) nullable
* line_subtotal NUMERIC(12,2) not null default `0`
* line_tax NUMERIC(12,2) not null default `0`
* line_total NUMERIC(12,2) not null default `0`
* sort_order INT not null default `0`
* created_at TIMESTAMPTZ not null default `now()`

### Table: activity_log

Fields:

* id UUID primary key
* company_id UUID not null references companies(id)
* user_id UUID nullable references users(id)
* project_id UUID nullable references projects(id)
* entity_type TEXT not null
* entity_id UUID not null
* action TEXT not null
* metadata_json JSONB nullable
* created_at TIMESTAMPTZ not null default `now()`

### Table: job_runs

Fields:

* id UUID primary key
* company_id UUID nullable references companies(id)
* project_id UUID nullable references projects(id)
* job_type TEXT not null
* status TEXT not null
* queue_name TEXT nullable
* attempts INT not null default `0`
* error_message TEXT nullable
* payload_json JSONB nullable
* result_json JSONB nullable
* started_at TIMESTAMPTZ nullable
* completed_at TIMESTAMPTZ nullable
* created_at TIMESTAMPTZ not null default `now()`

## 25. Required indexes

Create indexes on:

* users(company_id)
* clients(company_id)
* projects(company_id, created_at desc)
* projects(client_id)
* assets(project_id)
* ai_generations(project_id, created_at desc)
* estimates(project_id, version_number desc)
* proposals(project_id)
* invoices(project_id)
* activity_log(project_id, created_at desc)
* job_runs(status, created_at)

Add more partial indexes later for hot paths such as open invoices or pending proposals.

## 26. Domain modules in the backend

Organize the API by domain, not by random utility folders.

Use these modules:

* auth
* companies
* users
* clients
* projects
* assets
* ai-generations
* materials
* pricing
* estimates
* proposals
* invoices
* localization
* notifications
* analytics
* share-links
* jobs

Each module should have its own controller or route definitions, service layer, validation schema, data access layer, and tests.

## 27. Suggested iOS feature modules

Organize the iOS app by feature.

Suggested features:

* Auth
* Dashboard
* Clients
* Projects
* ProjectCreation
* ProjectDetail
* PreviewGeneration
* EstimateEditor
* ProposalPreview
* InvoicePreview
* Settings
* SharedComponents
* Networking
* Localization
* DesignSystem

Each feature should contain its views, state, service protocols, models, and tests. Shared UI must live in a controlled shared design system, not in ad hoc global folders.

## 28. Shared components

### iOS components

Key shared components should include:

* GlassHeaderBar
* PrimaryCTAButton
* MetricCard
* ProjectHeroCard
* ImageUploadGrid
* GenerationProgressCard
* BeforeAfterSlider
* MaterialSuggestionCard
* EstimateSectionCard
* LineItemEditorRow
* TotalsSummaryCard
* ProposalHeroView
* InvoiceTotalsView
* StatusBadge
* EmptyStateView
* RetryStateView

### Web components

Key shared components should include:

* DataTable
* FilterToolbar
* ProposalPreviewPanel
* BrandingSettingsPanel
* PricingProfileEditor
* AssetUploader
* ShareLinkCard

## 29. PDF system requirements

The PDF renderer must be server-side and deterministic.

It must support:

* branded company colors,
* company logo,
* before and after images,
* clean tables,
* English and Spanish templates,
* clickable material links,
* invoice and proposal variants,
* pagination that avoids ugly splits.

The PDF rendering layer should be its own module. Do not scatter document composition logic through controllers.

## 30. Environment variables

### API

Required server environment variables:

* DATABASE_URL
* DIRECT_DATABASE_URL if required by ORM
* STORAGE_BUCKET
* STORAGE_REGION
* STORAGE_ACCESS_KEY
* STORAGE_SECRET_KEY
* STORAGE_ENDPOINT if non-default
* NANO_BANANA_API_KEY
* NANO_BANANA_BASE_URL
* APP_BASE_URL
* SHARE_TOKEN_SIGNING_SECRET
* AUTH_SESSION_SECRET
* APPLE_SIGN_IN credentials if enabled
* email provider vars if emails are added
* analytics keys if used
* queue or redis variables if queue backend requires them

### Web

Required web variables:

* NEXT_PUBLIC_APP_URL
* NEXT_PUBLIC_API_BASE_URL

### iOS

Client variables should be limited to:

* API base URL
* public feature flags if needed

No privileged provider secrets should exist in the iOS app bundle.

## 31. Build order

### Phase 1: foundation

Set up the monorepo. Set up linting, formatting, shared configs, design tokens, and shared types. Provision Railway PostgreSQL. Set up Vercel web app deployment. Set up API deployment pipeline. Implement authentication scaffolding. Create initial schema migrations.

### Phase 2: core domain

Implement companies, users, clients, projects, assets, and basic dashboard APIs. Build iOS auth, dashboard shell, project creation flow, and image upload.

### Phase 3: AI preview system

Implement the Nano Banana provider service, job orchestration, generation records, asset linkage, status polling, and iOS preview results UI.

### Phase 4: estimate engine

Implement pricing profiles, labor rates, material suggestion persistence, estimate drafting, and estimate editor screens.

### Phase 5: proposal and invoice system

Implement document builders, PDF rendering, proposal share pages, invoice generation, and client share views.

### Phase 6: localization and polish

Complete English and Spanish coverage, refine the visual system, add analytics, improve accessibility, harden permissions, and complete testing.

## 32. Testing strategy

### Unit tests

Test pricing calculations, subtotal rollups, tax logic, markup logic, localization helpers, prompt normalization, and permission checks.

### Integration tests

Test project creation, upload flow, generation lifecycle, estimate drafting, proposal export, invoice export, and share-link access.

### iOS UI tests

Test auth, project creation, image upload, generation state handling, estimate editing, document preview, and language switching.

### Snapshot and visual tests

Use snapshot or PDF comparison tests for proposal and invoice rendering.

## 33. Analytics events

Track:

* auth_signed_in
* project_created
* project_image_uploaded
* generation_started
* generation_completed
* generation_failed
* estimate_draft_generated
* estimate_saved
* proposal_exported
* proposal_shared
* proposal_viewed
* proposal_approved
* invoice_created
* invoice_exported
* language_changed

## 34. Accessibility requirements

The iOS app must include VoiceOver-friendly labels, semantic grouping, adequate contrast, large tap targets, scalable type support, and meaningful state announcements for long-running tasks.

The web app must support keyboard navigation, semantic headings, focus visibility, and accessible tables.

## 35. Coding-LLM implementation instructions

When you generate code from this spec, follow this order.

First, define the repo layout and architectural boundaries.

Second, define shared types, validation schemas, and localization keys.

Third, implement database schema and migrations.

Fourth, implement backend domain modules one at a time.

Fifth, implement the iOS shell and feature modules with typed API integration.

Sixth, implement the web app for admin and share flows.

Seventh, implement PDF generation and document exports.

Eighth, add tests, analytics, and polish.

For every file you generate, include comments that explain the file’s role. For every major service or function, include concise comments explaining inputs, outputs, and important logic. Keep views small. Keep business logic out of views. Keep network clients centralized and typed. Keep provider logic swappable. Keep environment variables documented.

## 36. Final implementation mindset

The product should feel like this in use:

A contractor opens the app on site. The dashboard is simple, calm, and fast. They tap New Estimate. They upload photos. They speak or type what the project should become. The app immediately creates a project and starts working. Within a short time, the user sees a convincing remodel preview, a draft materials list, and an editable estimate. The numbers are easy to adjust. The proposal looks premium. The whole system feels like it helps them close the job faster.

That is the bar. Every architectural and code decision should support that outcome.

If you want, I can turn this into the next layer: a repo-by-repo implementation plan with exact folders, endpoint contracts, ORM models, and the first prompt to feed into a coding LLM.

[1]: https://developer.apple.com/design/human-interface-guidelines/materials?utm_source=chatgpt.com "Materials | Apple Developer Documentation"
[2]: https://vercel.com/docs/frameworks/full-stack/nextjs?utm_source=chatgpt.com "Next.js on Vercel"
[3]: https://ai.google.dev/gemini-api/docs/image-generation?utm_source=chatgpt.com "Nano Banana image generation - Google AI for Developers"
[4]: https://ai.google.dev/gemini-api/docs/models?utm_source=chatgpt.com "Models | Gemini API - Google AI for Developers"
