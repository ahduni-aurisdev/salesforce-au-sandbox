# Requirements — Zoom Integration (Webinars, then Meetings)

| Field | Value |
|---|---|
| Source | Developer documentation `docs/zoom-integration-development.md` / `docs/Zoom_Integration_Documentation.docx`, plus org verification |
| Captured by | Jitendra Varma (with Claude Code) |
| Date captured | 2026-11-02 |
| Target org | `au-uat` (`salesforce.admin@ahduni.edu.in.hlisuat`) — Production (`au-prod`) not yet in scope |

## 1. Business requirement

Track Zoom **webinar** and **meeting** registrations and attendance in Salesforce, create or update a Lead for each person (in the Department and Admission Year set on the session), and log activity (Task) on that Lead so admissions counsellors can see who registered and who attended. See "Decision — Zoom → Lead create/update (2026-11-03)" below.

## 2. Current implementation (webinars only)

See `docs/zoom-integration-development.md` for the full design. Summary:

- Real-time: Zoom webhook → Site `Zoom_Webhook` → `ZoomWebhook` (HMAC verified) → `ZoomEventService`.
- Safety net: `ZoomWebinarSyncScheduler` (every 2 hours) → `ZoomWebinarSync` (Queueable) → `ZoomApiService`.
- Data: `Zoom_Webinar__c`, `Zoom_Registration__c`, config in `Zoom_Config__mdt.Default`.
- Activity: completed Task "Zoom Webinar Registered: …" / "Zoom Webinar Attended: …" on the matched Lead (preferred) or Contact.

## 3. Verified org status — `au-uat`, 2026-11-02

| Check | Result |
|---|---|
| Zoom Apex | 2026-11-02 deploy `0Afft000000PuyHCAS`: 7 Zoom classes updated + `FeatureFlagService`, `ZoomLogger`, `ZoomSelector` and tests, all API 64.0 |
| Objects, CMDT type, layouts, tabs, permission set, guest profile, remote sites, Site | Present; retrieved into `force-app` on 2026-11-02 (backup: `backups/au-uat/2026-11-02-zoom-baseline/`) |
| `Zoom_Config.Default` credentials (Account ID, Client ID, Client Secret, Webhook Secret) | All populated (values not exported to the repo) |
| Site `Zoom_Webhook` | Active, Visualforce, prefix `/zoomwebhook` |
| Webhook URL | `https://ahmedabaduniversity2--hlisuat.sandbox.my.salesforce-sites.com/zoomwebhook/services/apexrest/zoom/webhook` |
| Public endpoint test | `endpoint.url_validation` → HTTP 200 with correct `encryptedToken`; bad signature → HTTP 401 |
| Tests (post-deploy run `707ft000004EryJ`) | 34/34 pass across `ZoomIntegrationTest`, `ZoomSelectorTest`, `ZoomLoggerTest`, `FeatureFlagServiceTest`. Coverage: ZoomApiService 94%, ZoomWebinarSync 87.2%, ZoomEventService 91.2%, all others 100% |
| Scheduled job "Zoom Webinar Sync" | **Paused** 2026-11-02 for the deployment (never ran). User will reschedule when all work is done |
| Feature flags | `Zoom_Integration`, `Zoom_Meetings`, `Zoom_Named_Credential` **on**; `Zoom_Webinars` **off** (user decisions 2026-11-02) |
| Zoom user / licence | `Zoom_User_Id__c` = `virtual.admissionsoffice@ahduni.edu.in`. **No webinar plan** on this user → meetings only for now (decision 2026-11-02). Turn `Zoom_Webinars` on if a webinar licence is added |
| Zoom login | Named Credential path verified 2026-11-02 (token issued). Meeting list blocked: Zoom app missing scope `meeting:read:list_meetings:admin` |
| Named Credentials | `ZOOM_OAUTH`, `ZOOM_API` deployed; ClientId / ClientSecret entered on `ZoomPrincipal`; permission set assigned to salesforce.admin user |
| Data received | 0 webinars, 0 registrations, 0 Zoom Tasks — no webhook events have arrived yet |
| `au-prod` | Nothing deployed |

## 4. Pending work

### Phase 1 — repo + UAT readiness
- [x] Retrieve Zoom metadata from UAT into the repo
- [x] Run `ZoomIntegrationTest` in UAT and record coverage
- [x] Verify credentials populated and webhook endpoint reachable
- [x] Start the scheduler in UAT — done 2026-11-02, then paused the same day for the Phase 2/3 deployment
- [x] Enter ClientId and ClientSecret on External Credential **Zoom OAuth** → principal **ZoomPrincipal** (required because `Zoom_Named_Credential` is on)
- [x] Assign permission set **Zoom Webinar Full Access** to the user who schedules the job
- [ ] Reschedule: `ZoomWebinarSyncScheduler.schedule();` (owner: user)
- [ ] **Blocking:** Zoom app scopes `meeting:read:list_meetings:admin`, `meeting:read:meeting:admin`, `meeting:read:list_registrants:admin`, `meeting:read:list_past_participants:admin`
- [ ] Zoom app: subscribe webhook to `meeting.*` events (`meeting:read:admin`, past-meeting participants) and subscribe to `meeting.*` events
- [ ] **Zoom side (owner: Zoom app admin):** register the webhook URL above in the Zoom Marketplace app, subscribe to the webinar events listed in the developer doc, click *Validate*
- [ ] Run one real webinar end-to-end and confirm records + Tasks

### Phase 2 — code hardening — ✅ deployed to UAT 2026-11-02
- Move Zoom secrets from unprotected Custom Metadata to a Named / External Credential
- Explicit callout timeouts; retry with backoff capped at 3
- Logger framework instead of `System.debug`; specific exception handling
- Feature flag (`FeatureFlag__mdt`) around webhook processing and sync
- ApexDoc headers, constants, API version 64.0 on all Zoom metadata (currently 66.0)
- Tests: 200-record bulk, Zoom 401/429/5xx failures, missing config

### Phase 3 — Zoom Meetings — ✅ deployed to UAT 2026-11-02
- **Decision (2026-11-02, user):** Option B — `Type__c` (Webinar / Meeting) on `Zoom_Webinar__c`, object relabelled "Zoom Session". Reason: same data shape, reuses all logic, roll-ups and reports. (Option A, a separate `Zoom_Meeting__c`, was rejected.)
- Webhook secret stays in `Zoom_Config__mdt` (user decision): Apex must read it to verify signatures.
- Gated by FeatureFlag `Zoom_Meetings`. Meeting keys in the sync queue are prefixed `M:`.
- Handle `meeting.*` webhook events and sync `/users/{id}/meetings`, `/meetings/{id}/registrants`, `/past_meetings/{id}/participants`

### Decision — sync approach (2026-11-02, user)
- **Keep current design: webhook (real-time) + 2-hourly API sync (safety net). No code change.**
- Reason: webhook covers short-notice meetings, cancellations and real-time updates; the API sync repairs anything a missed webhook leaves out.
- Considered and not chosen: API-sync-only (simpler Zoom setup, but misses meetings created and ended between runs and does not record cancellations).
- Zoom admin request: 4 meeting read scopes (+ any event scopes Zoom asks for), event subscription `Salesforce UAT`, Secret Token must match `Zoom_Config.Default.Webhook_Secret_Token__c`.

### Decision — Zoom → Lead create/update (2026-11-03, user; replaces the 2026-11-02 deferral)
- **Where Department and Admission Year come from:** Zoom sends neither, so they are set by hand once per session on `Zoom_Webinar__c.Department__c` (picklist; API name = Lead Record Type developer name, label = `Lead.Department__c` text) and `Zoom_Webinar__c.Admission_Year__c` (same values as `Lead.Admission_Year__c`). Departments: Undergraduation, Graduation, Masters, PhD, Executive Education, Career Development Centre, CLeF.
- **New-session email:** Flow `Zoom Session - Notify New Session Setup` emails Custom Label `ZOOM_SESSION_SETUP_EMAIL` (salescloudsupport@ahduni.edu.in) 1 minute after a session is created, if Department or Admission Year is still blank. A scheduled path is used because webhook-created sessions are saved by the Site guest user.
- **When Leads are created:** only in the scheduled sync (`ZoomWebinarSync` chain ends by starting `ZoomLeadQueueable`), never in the webhook (user: "dont create lead on webhook"). Schedule stays every 2 hours. Sessions without both values keep registrations in Lead Status "Pending setup"; once set, the next scheduled run processes them.
- **Who:** all registrants and walk-ins (participants who joined without registering).
- **Matching** (unconverted Leads, same Record Type and same Admission Year): email + phone both when both known; email only when no phone; phone only (last 10 digits) when no email; oldest match wins. No email and no phone -> Lead Status "No contact details", no Lead, no error email. A Lead with the same email but a different phone does not match (strict, as decided).
- **New Lead:** Record Type + `Department__c` from the session, `Admission_Year__c`, first/last name (walk-in display name split: last word = last name; blank -> "Unknown"), email, mobile, **LeadSource = Zoom** (new picklist value) and `Multi_Select_Lead_Source__c` = Zoom. Duplicate rules saved with allowSave.
- **Existing Lead:** fill blank First Name, Email, Mobile, `Department__c` only. Lead Source, Most Recent Lead Source and Admission Year are never changed (user: "dont update in existing").
- **Owner:** set by the existing Lead trigger (`LeadCombinedTrigger` department round-robin), the same as website Leads. Assignment Rules are not run, because the active rule ("MBA Leads from Meta") would override that owner (user choice 2026-11-03, after first answering "standard").
- **Activities:** Task "Zoom Meeting Registered: <topic>" when linked; after the session ends, "Attended: <topic>" (with minutes) or, for registered no-shows, "Did Not Attend: <topic>".
- **Existing data:** not migrated. The user deletes all Zoom sessions and registrations in UAT (and before Production go-live) for a fresh start.
- **Contacts:** the old email-only Lead/Contact match was removed; Zoom registrations link to Leads only.
- **No feature flag (deviation):** the rulebook asks for a Custom Metadata flag on Medium-risk features; the user explicitly declined a `Zoom_Lead_Sync` flag. Instant off switch remains `FeatureFlag.Zoom_Integration` (stops webhook, sync and the Lead step).
- **Known limitation:** CDC Lead validation rule `CDC_Required_Field_Validation` requires Account, Contact and Academic Year, so Zoom cannot create CDC Leads; such registrations get Lead Status "Error" and an error email.

### Decision — host filter (2026-11-03, user)
- The Zoom app receives webhook events for every meeting on the university account (seen: class EPI706, IT Helpdesk meetings). Only sessions hosted by the admissions user belong in Salesforce.
- `Zoom_Config__mdt.Allowed_Host_Ids__c` (comma-separated Zoom host IDs) filters webhook events and synced sessions; blank = accept all. Events without host_id are applied only to sessions Salesforce already holds.
- Admissions host `virtual.admissionsoffice@ahduni.edu.in` = host ID `Vj58A57CQtWF3eN4trJaQg` (read from the Zoom meetings API, 17 upcoming meetings). Value is entered in Setup on Zoom_Config.Default in each org (record not in source control because it holds secrets).

### Known remaining deviations from project standards
- Zoom payloads are parsed with `JSON.deserializeUntyped`, not typed wrapper classes
- No cross-transaction token cache (Platform Cache)
- `Zoom_Config__mdt` still holds Client ID / Secret for the legacy path; clear them once the Named Credential path is confirmed working
- Remote Site Settings `Zoom_API` / `Zoom_OAuth` kept for the legacy path

### Not yet scheduled
- Related lists, reports, dashboards
- Salesforce → Zoom registrant push
- Post-webinar follow-up messages (WhatsApp / Email)

## 5. Notes for Production deployment

- `sites/Zoom_Webhook.site-meta.xml` contains `siteAdmin` = `salesforce.admin@ahduni.edu.in`; confirm this user is valid in the target org.
- `Zoom_Config.Default` record is intentionally **not** in source control; enter credentials in each org after deployment.
- The scheduler must be started manually in each org after deployment.
