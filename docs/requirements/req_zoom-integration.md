# Requirements — Zoom Integration (Webinars, then Meetings)

| Field | Value |
|---|---|
| Source | Developer documentation `docs/zoom-integration-development.md` / `docs/Zoom_Integration_Documentation.docx`, plus org verification |
| Captured by | Jitendra Varma (with Claude Code) |
| Date captured | 2026-11-02 |
| Target org | `au-uat` (`salesforce.admin@ahduni.edu.in.hlisuat`) — Production (`au-prod`) not yet in scope |

## 1. Business requirement

Track Zoom **webinar** and **meeting** registrations and attendance in Salesforce, match each person to a Lead or Contact by email, and log activity (Task) on the matched record so admissions counsellors can see who registered and who attended.

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

### Known remaining deviations from project standards
- Zoom payloads are parsed with `JSON.deserializeUntyped`, not typed wrapper classes
- No cross-transaction token cache (Platform Cache)
- `Zoom_Config__mdt` still holds Client ID / Secret for the legacy path; clear them once the Named Credential path is confirmed working
- Remote Site Settings `Zoom_API` / `Zoom_OAuth` kept for the legacy path

### Not yet scheduled
- Lead creation for unmatched registrants
- Related lists, reports, dashboards
- Salesforce → Zoom registrant push
- Post-webinar follow-up messages (WhatsApp / Email)

## 5. Notes for Production deployment

- `sites/Zoom_Webhook.site-meta.xml` contains `siteAdmin` = `salesforce.admin@ahduni.edu.in`; confirm this user is valid in the target org.
- `Zoom_Config.Default` record is intentionally **not** in source control; enter credentials in each org after deployment.
- The scheduler must be started manually in each org after deployment.
