# SetzO — Product & Technical Spec

_Status: reflects the codebase on branch `flutter-migration` as of 2026-10-19. "Built" means implemented in code; "Schema only" means a table exists but there is no API or UI._

## 1. Overview

SetzO is a generic event-planning platform, targeting weddings first. Event type is stored as data, not hardcoded. The core ideas:

- **AI-generated task roadmap**: an LLM picks and customizes tasks from seeded templates.
- **LLM-suggested budget categories**: a total budget is split into categories at event creation.
- **Event-type-driven creation**: each event type has a profile (a list of steps and questions served by the API). The mobile wizard renders it generically, so each type is asked only what matters to it. For a custom event type, the LLM writes the extra questions.
- **Vendor directory with a review gate**: vendors self-register, and an admin approves them before families can see them.

Guest list/RSVP, a vendor marketplace and bookings are modelled in the schema but not built.

## 2. Roles

| Role | Login | Capabilities |
|---|---|---|
| **Organizer** (individual, family, company, committee) | Phone + OTP (mobile) | Complete profile; create, edit and delete events; manage budget categories; generate and edit the roadmap; browse published vendors (read-only). |
| **Vendor** | Phone + OTP (mobile) | Build a profile (categories, past work); submit for review; withdraw; edit (a material edit while published triggers re-review). |
| **Admin** | Email + password (web) | `super_admin` and `vendor_reviewer` can approve, reject, suspend and unsuspend vendors. `support` can view the queue but not act. |

Vendor status lifecycle: `draft → pending_review → published | rejected`, plus `suspended`. A rejected vendor can edit and resubmit.

## 3. Architecture & stack

pnpm monorepo (`pnpm-workspace.yaml`):

| Path | Stack | Deploy |
|---|---|---|
| `apps/backend` | Express 5, TypeScript, Prisma 6, PostgreSQL, Zod 4, jsonwebtoken, bcryptjs, libphonenumber-js, run with tsx | Render |
| `apps/mobile_flutter` | Flutter 3, Riverpod, go_router, dio, flutter_secure_storage, shared_preferences (replaced the Expo/React Native app, see `FLUTTER_MIGRATION.md`) | Android APK (`com.setzo.app`) |
| `apps/admin` | Vite 8, React 19, react-router-dom 7, axios, plain CSS, oxlint | Vercel (SPA rewrite) |
| `packages/shared-types` | Type-only TypeScript interfaces | — |

- **Backend layering:** `routes/` → `controllers/` → `services/`. Zod `schemas/` handle validation. `config/` holds static data (event type profiles). `lib/` holds env, jwt, hash, llm, msg91 and otp. `middleware/` holds auth and error handling.
- **Database:** Postgres 16 via Docker locally; Neon in production (direct, non-pooled connection string).
- **LLM:** a raw-`fetch` adapter (`apps/backend/src/lib/llm.ts`) supporting Anthropic, OpenAI, Gemini and Groq, selected by `LLM_PROVIDER` and `LLM_MODEL`. Truncated output is rejected. Groq uses the OpenAI-compatible code path with its own base URL. Token usage is returned for metering. Groq and Gemini both have free tiers, which suit local testing.
- **SMS:** MSG91, used only when `NODE_ENV=production`; otherwise the OTP is logged to the console.
- **Planned, not integrated:** WhatsApp Business API (env stubs only).
- **Deploy flow:** APK → Render (Express) → Neon. See `DEPLOY_AND_APK.md`. Render free tier has about a 50 s cold start.
- **CORS:** only `ADMIN_APP_ORIGIN` is allowed.

## 4. Data model

Defined in `apps/backend/prisma/schema.prisma`. Tables use snake_case via `@@map` and UUID ids. There are no cascade rules; event deletion removes children manually in one transaction.

### Identity & auth (built)
- `organizers`: phone (unique), email, displayName, organizerType, preferredLanguage, status.
- `vendors`: businessName, contactPersonName, phone (unique), email, priceTier (essential/standard/premium/luxury), serviceArea, description, yearsOfExperience, startingPrice, social/website/WhatsApp links, status, rejectionReason, submittedAt, reviewedAt, reviewedBy.
- `vendor_categories` and the join `vendor_vendor_categories`.
- `vendor_portfolio_items`: text-only past work (title, caption, displayOrder). `mediaUrl` is unused.
- `vendor_review_logs`: append-only. Actions: submitted, withdrawn, approved, rejected, suspended, unsuspended, reverification_required.
- `admins`: name, email, passwordHash, role.
- `otp_requests`: bcrypt-hashed OTP, purpose, expiry, attemptCount, consumedAt.
- `refresh_tokens`: id equals the JWT `jti`, tokenHash, revokedAt. It is polymorphic on (userId, role) with no foreign key.
- `role_permissions`: per-event roles (owner/editor/viewer/approver). Scaffold only.

### Events (built)
- `event_groups`: eventType (wedding/birthday/corporate/religious/engagement_only/custom), name, region, tradition, totalBudget, budgetTier, guestCountEstimate, primaryDate, status, and `details` (JSON: answers to the type-specific questions).
- `generated_event_profiles`: the question set the LLM wrote for a custom event (organizer, description, full profile JSON, status `draft`, model, token counts, latency). Kept for later admin review; there is no admin screen for it yet.
- `sub_events`: one is auto-created and mirrors the event. Multiple sub-events are not exposed in the UI.

### Roadmap (built)
- `task_categories` (key lookup) and `task_templates` (eventType, region, tradition, taskKey, defaultLeadTimeDays, defaultDependencyKeys, typicalOwnerType, version).
- `tasks`: status (not_started/in_progress/done/overdue/not_applicable), source (ai_generated/template_default/user_added), ownerType, dueDate, optional links to a vendor and a budget category. `task_dependencies` is the join.
- `task_edit_logs`: every edit, with previous and new values as JSON.
- `roadmap_generation_logs`: inputParams, templateIdsUsed, llmModelUsed, rawOutput.

### Budget
- `budget_categories` (built): categoryKey (free string), allocatedAmount, budgetTierOverride.
- `budget_lines` (schema only): planned and actual entries.

### Guests (schema only)
`guest_groups`, `guests`, `guest_sub_event_invites` (per-sub-event RSVP), `guest_seating_assignments`.

### Future (schema only)
`bookings`, `payments`, `vendor_availability`, `reviews`, `documents`, `legal_checklist_items`, `event_media`, `thank_you_notes`, `notification_logs`, `translation_strings`, `production_pipeline_items`.

### Seed (`apps/backend/prisma/seed.ts`)
- 12 task categories and 10 vendor categories.
- 14 wedding task templates, for example `book_venue` (120 days lead) and `book_catering` (90 days, depends on `finalize_guest_count`).
- An admin `admin@setzo.internal` with a random password.
- Sample vendors in every state when `SEED_SAMPLE_VENDORS=true`.

## 5. Functional requirements

### 5.1 Authentication
1. `POST /auth/otp/request {phoneNumber, role}`:
   - 3 requests per phone per 10 minutes.
   - The purpose is `login`, `organizer_signup` or `vendor_signup`.
   - The OTP is 6 digits, bcrypt-hashed, valid for 5 minutes, with 5 verify attempts.
2. `POST /auth/otp/verify`:
   - Upserts the user (an organizer is `active`, a vendor is `draft`).
   - Returns an access token and a refresh token.
3. **Tokens:**
   - The access token is an HS256 JWT `{sub, role, adminRole?}` that expires in 15 minutes.
   - The refresh token has a `jti`, is stored hashed, and lasts 30 days.
   - `/auth/refresh` returns a new access token. For admins, the role is re-read from the database.
   - `/auth/logout` revokes the refresh token, even if it has expired.
4. **Admin login:** `POST /admin/auth/login` with email and password.
5. **Mobile client:** keeps the session on transient refresh failures. A stored session with a missing role forces a re-login.
6. **Authorization:** `requireAuth`, `requireRole`, `requireAdminRole`. Ownership is checked in services; a missing event returns 404 and another organizer's event returns 403.

### 5.2 Organizer profile and events
- Creating an event requires a complete profile (displayName and organizerType). Otherwise it returns 400 with `missingFields`.
- **Event type profiles** (`apps/backend/src/config/event-type-profiles.ts`, served by `GET /event-types`):
  - One profile per type: wedding, birthday, corporate, religious, engagement_only, and a generic one for `custom` (also the fallback for any unknown type).
  - A profile is `{eventType, version, steps[]}`; a step has questions. Question kinds: `single_select`, `multi_select`, `chips`, `text`, `number`, `date`, `budget`. A question can have options, `allowOther`, `required` and a `showIf` condition on another answer.
  - A question with `mapsTo` fills a top-level EventGroup field (name, region, religionOrTradition, primaryDate, guestCountEstimate, totalBudget, budgetTier). Every other answer is stored in `EventGroup.details`.
  - Every profile ends with the same core step (date, guests, budget, budget style). Shared questions (food, venue, outstation stay, entertainment) are defined once.
  - `POST /event-groups` validates `details` against the profile of its event type. The details are passed to the budget and roadmap prompts.
- **Custom events** (`POST /event-types/generate {description}`):
  - The LLM writes the extra questions from a one-line description.
  - It may only use `single_select`, `multi_select`, `text` and `number`; it cannot set `mapsTo` or `showIf`, or reuse a core key. At most 3 steps, 3 questions per step and 8 questions in total; select questions have 2–8 options.
  - One retry with the validation error fed back. On repeated failure, or if the LLM is down, it returns the generic profile (`profileId: null`) so the event can still be created.
  - Limited to 6 calls per organizer per hour (429 beyond that).
  - A successful result is stored in `generated_event_profiles`. `POST /event-groups` with `generatedProfileId` (custom events only; the profile must belong to the caller) validates `details` against that profile.
- **Creation flow:**
  - The LLM suggests 4–10 budget categories as percentages summing to 100, including a small contingency.
  - There is one retry with the validation error fed back.
  - On repeated failure it falls back to `DEFAULT_BUDGET_SPLIT` (venue 30, catering 25, decor 15, photography 15, attire 10, misc 5).
  - The EventGroup, SubEvent and BudgetCategories are created in one transaction.
- **Edit** (`PATCH`): name, budget, tier, guest count and date.
  - A budget change takes `budgetAdjustment: rescale | keep`.
  - `rescale` puts the rounding remainder on the largest category.
  - The sub-event stays in sync.
- **Delete:** removes children in one transaction. It returns 409 if payments exist.

### 5.3 Budget categories
- Create, update and delete return a `warning` when the allocated total exceeds the total budget. Amounts are not forced to sum to the total.
- A duplicate key returns 409.
- A category with budget lines cannot be deleted.

### 5.4 Roadmap
- `POST /event-groups/:id/generate-roadmap`: the LLM selects and customizes seeded templates rather than inventing a graph.
  - Output is JSON `{tasks: [...]}` with dueDateOffsetDays, dependencyKeys, ownerType and category.
  - At most 3 custom tasks (taskKey prefixed `custom_`).
  - There is one validation retry. Failure returns 502.
  - Everything is created in one transaction and logged to `roadmap_generation_logs`.
- **Regeneration `mode`:**
  - `replace_all`
  - `add_missing`
  - `keep_my_work` (keeps user-added, in-progress and edited tasks)
  - Without a mode, a second generation returns 400.
- **Task CRUD:** edits write `task_edit_logs`. Delete is soft (the task becomes `not_applicable`) and can be restored.

### 5.5 Vendor self-serve
- Profile: `GET/PATCH /vendor/me`, categories, and past work (create, reorder, update, delete).
- **Submit requirements:**
  - businessName, contactPersonName, priceTier and serviceArea.
  - A description of at least 30 characters.
  - At least 1 category and at least 1 past-work entry.
  - Otherwise 400 with `missing`.
- **Limits:** at most 5 categories, 10 past-work entries and a 1000-character description.
- Submit is allowed from `draft` or `rejected`. Withdraw is allowed only from `pending_review`.
- On a published vendor, editing businessName, serviceArea, priceTier, description, categories or past work returns it to `pending_review`.
- Every transition is written to `vendor_review_logs`.

### 5.6 Admin review
- Approve and reject apply to pending vendors. Suspend and unsuspend apply to published and suspended vendors.
- Those four actions are limited to `super_admin` and `vendor_reviewer`.
- The queue is filterable by status.

### 5.6.1 Vendor-proposed categories
- A vendor can suggest a category that is not in the list (`POST /vendor/me/category-proposals`). The name is normalised to a key; an existing key returns 409, and a name already pending attaches the vendor to the same proposal. At most 3 pending proposals per vendor.
- Proposals are visible only to the proposing vendor (`GET /vendor/me/category-proposals`) and to admins. They are not listed in `GET /vendor-categories` and cannot be assigned until decided.
- Admins decide in a separate queue (`super_admin`, `vendor_reviewer`): **approve** creates a global `VendorCategory` and `TaskCategory` with the same key plus the starter `TaskTemplate`s the admin supplies, and assigns every attached vendor (skipping any already at 5 categories); **merge** maps the proposal to an existing category; **reject** records a reason.
- Because roadmap generation reads all `TaskCategory` rows and the templates for the event type, an approved category is offered to every later roadmap. Existing roadmaps are not regenerated.
- Not built: notifying the vendor of the decision (they see the status in the app).

### 5.7 Organizer vendor browse
- `GET /vendors` returns only `published` vendors, ordered by business name. Filters: category, priceTier, region.
- `GET /vendors/:id` is read-only.

## 6. API reference

All routes require a bearer token except `/auth/*`, `/admin/auth/login` and `GET /health`.

| Area | Endpoints |
|---|---|
| Auth | `POST /auth/otp/request`, `POST /auth/otp/verify`, `POST /auth/refresh`, `POST /auth/logout` |
| Organizer | `GET /organizers/me`, `POST /organizers/me/profile` |
| Event types | `GET /event-types` (all profiles, static, cacheable), `POST /event-types/generate` (organizer only) |
| Events | `POST /event-groups`, `GET /event-groups/me`, `GET/PATCH/DELETE /event-groups/:id` |
| Roadmap | `POST /event-groups/:id/generate-roadmap`, `GET/POST /event-groups/:id/tasks`, `PATCH/DELETE /tasks/:id`, `GET /task-categories` |
| Budget | `POST /event-groups/:id/budget-categories`, `PATCH/DELETE /event-groups/:id/budget-categories/:categoryId` |
| Vendor browse (organizer) | `GET /vendors`, `GET /vendors/:id` |
| Vendor self | `GET/PATCH /vendor/me`, `PUT /vendor/me/categories`, `POST /vendor/me/past-work`, `PUT /vendor/me/past-work/order`, `PATCH/DELETE /vendor/me/past-work/:itemId`, `POST /vendor/me/submit`, `POST /vendor/me/withdraw`, `GET/POST /vendor/me/category-proposals`, `GET /vendor-categories` (organizer or vendor) |
| Admin | `POST /admin/auth/login`, `GET /admin/vendors` (`?status`), `GET /admin/vendors/:id`, `POST /admin/vendors/:id/{approve,reject,suspend,unsuspend}`, `GET /admin/vendor-categories`, `GET /admin/category-proposals` (`?status`), `GET /admin/category-proposals/:id`, `POST /admin/category-proposals/:id/{approve,reject,merge}` |

## 7. Screens

### Mobile (`apps/mobile_flutter`, Android)
Routes are in `lib/core/router/router.dart`, and the UX flow is in `docs/ux-flow.md`.
- **Auth:** a welcome screen with a role picker, then a country-code picker with an E.164-validated phone number, then 6-digit OTP entry. A stored session with a missing role forces a re-login.
- **Organizer** (bottom-navigation shell):
  - Profile setup, home, an events list (multiple events) and an organizer profile.
  - **Event creation wizard** (`event_wizard_view.dart`):
    - A step-by-step flow whose questions come from `GET /event-types`, so each event type asks only what matters for it.
    - A custom event gets a "describe it" step where the server writes the questions; a loading state covers the LLM call, and the generic questions are used if it fails.
    - The question sets are cached on the device.
    - A half-finished event is saved as a draft (shared_preferences) and can be resumed.
    - If the question sets cannot be loaded, the old single-page form is used.
  - **Event detail** has tabs for budget (category add/edit/delete), roadmap (generate, regenerate with a mode, task sheet, add, restore) and vendors, plus an edit-event form.
  - Vendor browse is a filterable list with a read-only detail page.
- **Vendor:** one dashboard route whose content depends on status (draft or rejected → profile editor, pending_review → under review, published → home, suspended → suspended). The editor has a past-work sheet and shows profile completeness and what a material edit would trigger.
- Shared: an offline banner, a dio client with token refresh, secure-storage session, a launcher icon and a native splash (the diya mark). Debug builds have a previews gallery and a dev bar.

### Admin web (`apps/admin/src`)
- `/`: dashboard. `/families`, `/events`, `/roadmap`, `/audit` and their detail pages are described under "Admin oversight".
- `/login`: email and password. Five wrong passwords lock the account for 15 minutes (429), with a per-IP limit on top.
- Everything else sits inside a shell (`components/Layout.tsx`): a sidebar with role-aware navigation, the admin's name and role, a skip link and logout. Styling uses shared design tokens in `index.css` and inline SVG icons (`components/icons.tsx`). Unknown paths show a 404 page.
- `/vendors`: queue with tabs (with counts) for pending review, published, rejected, suspended and drafts. Search, category, tier and sort filters and pagination are all kept in the URL. Reviewers can select several pending vendors and approve or reject them together; each is decided on its own and failures are reported.
- `/vendors/:id`: detail with approve, reject (reason), suspend (reason) and unsuspend, each behind a confirmation dialog. Support admins see no action buttons.
- `/categories`: all categories with vendor and starter-task counts; retire or restore a category. `/categories/:key` edits the display name and event types and manages the category's starter tasks (add, edit, delete). `/categories/proposals`: the proposal queue (approve with starter tasks, optionally drafted by AI; merge with a preview; reject).
- `/team` (super admin): add admins, change roles, disable/enable, reset passwords (a temporary password is shown once).
- `/account`: change password, log out everywhere. A temporary password forces this page first.

### Admin oversight
- Dashboard (`/`): queues that need action with the age of the oldest item, platform counts, failed roadmaps in the last 7 days, AI token use over 30 days, and (super admin) recent activity.
- Families: `GET /admin/organizers`, `/:id`; suspend and restore are super-admin only and need a reason (kept in the audit log). A suspended organizer cannot sign in or refresh, and is blocked on every organizer route straight away, even with a valid access token.
- Events: `GET /admin/events`, `/:id` (sub-events, tasks, budget, AI generations). Read-only.
- Roadmap: `GET /admin/roadmap-logs`, `/:id` and `GET /admin/task-edit-stats`. Each generation records status, attempts, latency and tokens; failed generations are kept with the model's replies and the validation error. The feedback tab shows which template tasks families edit or remove most.
- Audit log (super admin): `GET /admin/audit-logs` with filters, and `GET /admin/audit-logs.csv`, which prefixes cells starting with `=`, `+`, `-` or `@` so spreadsheets do not run them.

### Admin bookings, payments and reviews
- `GET /admin/bookings` (`status`, `q`, `page`), `/:id`, and `GET /admin/payments` (`status`: overdue, pending, paid) are read-only. "Overdue" is derived: unpaid and past its due date. Admins cannot change a booking or move money.
- Reviews have a `status` (`visible`, `flagged`, `hidden`). `GET /admin/reviews` filters by status, rating and text; `POST /admin/reviews/:id/hide` (reason required) and `/restore` are limited to `super_admin` and `vendor_reviewer`, apply once each (a second attempt is 409) and are audited.
- Bookings, payments and client reviews are not built into the app yet, so these screens show an explanatory empty state until they are. Hiding a review has no effect on families yet because nothing shows reviews to them.

### Admin catalog
- `GET /admin/vendors` takes `status`, `q`, `category`, `priceTier`, `sort`, `page`, `pageSize` and returns `{vendors, total, page, pageSize}`; `GET /admin/category-proposals` takes `status`, `q`, `page`. `POST /admin/vendors/bulk` approves or rejects up to 50 vendors. `GET /admin/stats` returns counts.
- `GET /admin/categories`, `PATCH /admin/categories/:key` (label, event types, `isActive`). A retired category disappears from the vendor picker and from roadmap generation; vendors who already have it keep it.
- `GET/POST /admin/task-templates`, `PATCH/DELETE /admin/task-templates/:id`. Task keys are unique; dependencies must exist and cannot form a loop; a task that others depend on cannot be deleted or renamed; each edit bumps `version`.
- `POST /admin/category-proposals/:id/draft-templates` asks the configured LLM for starter tasks. The admin edits them before saving; nothing is stored by this call.
- Editing is limited to `super_admin` and `vendor_reviewer`.

### Admin accounts and security
- `GET /admin/me`, `POST /admin/me/password`, `POST /admin/me/logout-all`; `GET/POST /admin/admins`, `PATCH /admin/admins/:id`, `POST /admin/admins/:id/reset-password` (super admin only).
- The admin's status and role are re-read on every admin request, so disabling or demoting takes effect immediately. A disabled admin's refresh tokens are revoked.
- You cannot disable or demote yourself or the last active super admin.
- `admin_audit_logs` records logins, failed logins, lockouts, vendor and proposal decisions and team changes. The audit log screen is described under "Admin oversight".
- The API sends helmet headers, limits JSON bodies to 100 kB and exposes `GET /health`. In production `ADMIN_APP_ORIGIN` must be set.

## 8. Configuration & local setup

**Backend env** (validated by Zod in `apps/backend/src/lib/env.ts`; the server fails at boot if a required variable is missing):
- Required:
  - `DATABASE_URL`
  - `JWT_ACCESS_SECRET` and `JWT_REFRESH_SECRET` (at least 32 characters)
  - `OTP_PROVIDER_API_KEY`
  - `LLM_PROVIDER` (anthropic, openai, google or groq), `LLM_MODEL`, `LLM_API_KEY`
- Optional, with defaults:
  - `PORT` (3000), `NODE_ENV`
  - `JWT_ACCESS_EXPIRES_IN` (15m), `JWT_REFRESH_EXPIRES_IN` (30d)
  - `OTP_PROVIDER_BASE_URL`
  - `OTP_EXPIRES_IN_MINUTES` (5), `OTP_MAX_REQUESTS_PER_WINDOW` (3), `OTP_REQUEST_WINDOW_MINUTES` (10), `OTP_MAX_VERIFY_ATTEMPTS` (5)
  - `ADMIN_APP_ORIGIN` (`http://localhost:5173`)
- `WHATSAPP_*` variables appear in `.env.example` but are not read by the code.

**Client env:**
- Mobile: `--dart-define=API_URL=...`. Debug builds default to `http://10.0.2.2:3000` (the Android emulator); use the LAN IP for a physical device. Release builds have no default and fail at startup without it. It is baked in at build time.
- Admin: `VITE_API_URL`.

**Local setup:**
```
docker compose up -d
pnpm install
cp .env.example apps/backend/.env
pnpm prisma:migrate
pnpm --filter @setzo/backend exec prisma db seed
```

**Scripts:**
- Backend: `dev`, `build`, `start`, `test`, `prisma:*`.
- Mobile: standard Flutter commands (`flutter run`, `flutter test`, `flutter build apk`); see `apps/mobile_flutter/README.md`.
- Admin: `dev`, `build`, `lint`, `preview`, `test`.
- shared-types: `typecheck`.

**Production deploy:**
- Render build: `npm i -g pnpm && pnpm install --frozen-lockfile --prod=false && pnpm --filter @setzo/backend prisma:generate && pnpm --filter @setzo/backend build`.
- Render start: `pnpm --filter @setzo/backend exec node dist/index.js`.
- Run migrations with `npx prisma migrate deploy` from a dev machine (the latest are `event_details` and `generated_event_profiles`).
- Mobile release build: `flutter build apk --dart-define=API_URL=https://...` (see `DEPLOY_AND_APK.md`).

## 9. Roadmap & non-goals

Phased, risk-ordered plan (v1.0):

| Phase | Scope | Exit condition |
|---|---|---|
| 0 | No code: pick one city and one event type, write the success sentence, recruit vendors and pilot families | Commitments in hand |
| 1 | MVP: data model, AI roadmap, guest list/RSVP via WhatsApp, budget tracker, vendor directory with admin queue, mobile | Feature-complete for pilot |
| 2 | Pilot with 5–10 real families | Usage data collected |
| 3 | Decision point | Go or no-go |
| 4 | Marketplace: bookings, contracts, payments | — |
| 5+ | Day-of runsheets, multi-city, new event types, multi-language | — |

**Success sentence:** 10 families in the chosen city use the roadmap, guest list and budget tracker as their primary planning tool for at least 3 weeks, and at least 6 say they'd use it again.

**Locked-in decisions:**
- SubEvent is modelled from day one.
- Vendors have their own auth and status.
- `event_type` is a data field.
- Every roadmap generation and task edit is logged.
- LLM cost is tracked from day one.
- The admin app is separate, and family-facing vendor browse is read-only.

**Non-goals before Phase 4:** booking, payments and contracts.

## 10. Known gaps & risks

**Security (fix before real users)**
- `apps/backend/src/lib/otp.ts` returns a fixed OTP of `123456`, a temporary testing change. Anyone can log in as any phone number. Restore the CSPRNG.

**Engineering debt**
- There is no CI. Tests exist but run only by hand: backend (vitest, including DB and event-profile tests), admin (vitest) and Flutter (`flutter test`, plus a live integration test). The root `test` script is a placeholder.
- Runtime constants are duplicated by hand between `apps/backend/src/lib/vendor-limits.ts` and shared-types. The shared-types package mirrors the schema by hand and can drift.
- Budget split rounding can drift by a cent or two on non-round inputs.
- The OpenAI adapter may not suit every model's `response_format` behaviour. Anthropic relies on prompt instructions for JSON-only output.
- Task categories and templates are seeded for weddings only. Other event types now collect type-specific answers in `details` and feed them to the prompts, but still get an empty template list, so their roadmaps depend on the LLM alone.
- Generated custom-event question sets are stored as `draft` but there is no admin screen to review or promote them.
- Free-tier LLMs (small Groq or Gemini models) may return invalid structured output more often. The retry-then-fallback paths cover it, but check output quality per model.
- Vendor image upload is not supported. Only the Android APK is documented, with no iOS or web build.

**Not yet built** (schema exists, no API or UI)
- Guest list and RSVP, WhatsApp integration, and a headcount feed into the budget.
- Budget planned vs actual.
- Bookings, payments, contracts and vendor availability.
- Vendor reviews and ratings.
- A vendor dashboard beyond profile editing.
- Multiple sub-events in the UI.
- Co-organizer roles.
- Notifications and push.
- Multi-language support.
- Documents, legal checklist, event media, thank-you notes and the production pipeline.
