# Zoom Integration – Salesforce Documentation

**Org:** AU UAT (`hlisuat` sandbox) · **Branch:** `whatsapp-engagement-tracking` · **Source API version:** 66.0
**Status in one line:** Zoom **Webinar** registrations and attendance sync into Salesforce and log activities on Leads/Contacts. Zoom **Meetings** are **not implemented**.

> **Update 2026-11-02 (deployed to `au-uat`, API 64.0):** Meetings are now implemented. `Zoom_Webinar__c` is labelled **Zoom Session** with a new `Type__c` (Webinar / Meeting); `meeting.*` events and meeting sync are handled behind FeatureFlag `Zoom_Meetings`. Also added: `FeatureFlag__mdt` toggles (`Zoom_Integration`, `Zoom_Meetings`, `Zoom_Named_Credential`, all on), Named Credentials `ZOOM_OAUTH` / `ZOOM_API`, 30 s callout timeouts, retries (max 3, 1/2/4 min), failure logging to `API_Log__c`, webhook rollback on failure, `ZoomSelector`, and 34 tests. Sections below describe the original webinar build; current status, decisions and open items are in `docs/requirements/req_zoom-integration.md`.

---

## 1. Scope at a glance

| Area | Status |
|---|---|
| Webinar create/update/start/end/delete (webhook) | Done |
| Webinar registration created / approved / denied / cancelled (webhook) | Done |
| Participant joined / left (webhook) | Done |
| Scheduled API sync (import + safety net for missed webhooks) | Done (needs the scheduler started once) |
| Match registrant to Lead / Contact by email | Done |
| Completed Task on the Lead/Contact (Registered, Attended) | Done |
| Roll-up counts and attendance rate on the webinar | Done |
| Permission set, tabs, Site for the webhook | Done |
| Apex unit tests | Done (5 test methods) |
| **Zoom Meetings** (scheduled meetings, registrants, participants) | **Not started** |
| Custom UI (LWC, related lists on Lead/Contact, reports, dashboards) | Not started |
| Creating a Lead for an unmatched registrant | Not started |
| Pushing Salesforce leads *into* Zoom as registrants | Not started |

> The request mentioned "webinar and meeting". Only webinars exist in the code; there is no meeting object, class or webhook handler.

---

## 2. Architecture

```
                       (A) real-time
 Zoom  ── event ──►  https://<site-domain>/zoomwebhook/services/apexrest/zoom/webhook
 Marketplace app            │  ZoomWebhook   (verifies HMAC signature)
                            ▼
                       ZoomEventService.process()  ──►  Zoom_Webinar__c
                            │                           Zoom_Registration__c
                            │                           Task on Lead / Contact
                            │
                       (B) every 2 hours / on demand
 Salesforce ── callout ──►  zoom.us/oauth/token  +  api.zoom.us/v2/...
   ZoomWebinarSyncScheduler → ZoomWebinarSync (Queueable) → ZoomApiService
                            └──► ZoomEventService.applyPeople()
```

Two paths feed the same logic (`ZoomEventService`), so webhook data and API data produce identical records. The API sync repairs anything a missed webhook left out.

---

## 3. Components

### 3.1 Apex classes (`force-app/main/default/classes`)

| Class | Purpose |
|---|---|
| `ZoomWebhook` | `@RestResource(urlMapping='/zoom/webhook/*')`, `without sharing`. Handles Zoom's `endpoint.url_validation` challenge, verifies `x-zm-signature` (`v0=` + HMAC-SHA256 of `v0:<timestamp>:<body>`), then calls `ZoomEventService.process`. Returns 401 on bad signature, 500 on processing error (so Zoom retries), 500 if no secret is configured. |
| `ZoomEventService` | Core logic. Upserts the webinar, upserts registrations by `Registration_Key__c`, matches by email, creates Tasks, tracks join/leave time. |
| `ZoomApiService` | Server-to-Server OAuth (`account_credentials` grant) + GET helper + paginated `getAll` (page size 300, follows `next_page_token`, max 20 pages). Token is cached per transaction only. A 404 returns an empty map. |
| `ZoomWebinarSync` | `Queueable`, `AllowsCallouts`. Discovers webinars, then syncs one webinar per job and chains the next. |
| `ZoomWebinarSyncScheduler` | `Schedulable`. `schedule()` registers job **"Zoom Webinar Sync"** with cron `0 0 0/2 * * ?` (every 2 hours). |
| `ZoomConfig` | Reads `Zoom_Config__mdt` record `Default`. |
| `ZoomIntegrationTest` | Tests: registration + attendance flow, cancel and end events, webhook validation and signature, API sync, scheduler/default config. |

### 3.2 Data model

**`Zoom_Webinar__c`**

| Field | Notes |
|---|---|
| `Name` | Webinar topic (max 80 chars) |
| `Webinar_Id__c` | Zoom webinar ID; upsert key |
| `Status__c` | Scheduled / Started / Ended / Deleted |
| `Start_Time__c`, `End_Time__c`, `Duration_Minutes__c`, `Timezone__c` | End = start + duration |
| `Join_URL__c`, `Registration_URL__c` | From Zoom |
| `Last_Synced_At__c` | Set by the API sync |
| `Registered_Count__c` | Roll-up count of registrations |
| `Attended_Count__c` | Roll-up count, registered **and** attended |
| `Walk_In_Count__c` | Roll-up count, attended without registering |
| `Attendance_Rate__c` | Formula: attended ÷ registered |

**`Zoom_Registration__c`** (one row per person per webinar)

| Field | Notes |
|---|---|
| `Registration_Key__c` | External ID, unique: `<webinarId>\|<email lower-case>` (falls back to registrant ID, then participant name) |
| `Webinar__c` | Lookup/master to webinar |
| `Email__c`, `First_Name__c`, `Last_Name__c`, `Phone__c`, `Registrant_Id__c`, `Join_URL__c` | From registrant |
| `Form_Answers__c` | Address/city/org/job title/etc. and custom questions, one per line |
| `Status__c` | Approved / Pending / Cancelled / Denied / Not Registered |
| `Is_Registered__c`, `Registered_At__c` | Registration state |
| `Attended__c`, `First_Joined_At__c`, `Last_Joined_At__c`, `Last_Left_At__c`, `Time_In_Session_Minutes__c` | Attendance |
| `Lead__c`, `Contact__c`, `Is_Matched__c` | Email match result |
| `Registration_Task_Id__c`, `Attendance_Task_Id__c` | Prevents duplicate Tasks |

**`Zoom_Config__mdt`** (record `Default`): `Account_Id__c`, `Client_Id__c`, `Client_Secret__c`, `Webhook_Secret_Token__c`, `Zoom_User_Id__c` (default `me`), `Create_Activities__c` (default true).

### 3.3 Security and connectivity metadata

- **Site `Zoom_Webhook`** – Visualforce site, path prefix `zoomwebhook`, index page `ZoomWebhookInfo` (plain text placeholder).
- **Profile `Zoom Webhook Profile`** – guest profile with access to `ZoomWebhook`, `ZoomEventService`, `ZoomConfig`.
- **Permission set `Zoom_Webinar_Full_Access`** – full access to both objects, their fields, tabs and all Zoom Apex classes. Assign to admins/operators.
- **Remote Site Settings** `Zoom_API` (`https://api.zoom.us`) and `Zoom_OAuth` (`https://zoom.us`).
- **Tabs** for both objects.
- **Manifests:** `manifest/zoom-package.xml` (objects, metadata, classes, tabs, remote sites, permission set) and `manifest/zoom-site.xml` (page + site).

---

## 4. Behaviour

### 4.1 Webhook events handled

| Zoom event | Effect |
|---|---|
| `endpoint.url_validation` | Replies with `plainToken` and `encryptedToken` (HMAC of the plain token with the secret) |
| `webinar.started` / `webinar.ended` / `webinar.deleted` | Webinar upserted; status set to Started / Ended / Deleted |
| `webinar.registration_created` | Registration Approved (or Pending if Zoom says pending); Task "Zoom Webinar Registered: <topic>" |
| `webinar.registration_approved` / `_denied` / `_cancelled` | Status set to Approved / Denied / Cancelled; `Is_Registered__c` true only for Approved or Pending |
| `webinar.participant_joined` | `Attended__c` = true, first/last join times; Task "Zoom Webinar Attended: <topic>". If the person has no registration row they become **Not Registered** (walk-in). |
| `webinar.participant_left` | Adds minutes (leave − last join) to `Time_In_Session_Minutes__c`; ignored if no matching row |

Any other event only upserts the webinar header from the payload.

### 4.2 Matching and activities

- Matching is by lower-case email against `Contact` and unconverted `Lead`. **A Lead wins over a Contact.** If several records share an email, the oldest wins.
- A completed Task (`Status=Completed`, `ActivityDate=today`) is created on the matched record once for registration and once for attendance. The Task IDs are stored on the registration, so re-sent events do not duplicate them.
- Unmatched people are stored on `Zoom_Registration__c` only (`Is_Matched__c` false); no Lead is created.
- `Create_Activities__c = false` turns Task creation off.

### 4.3 API sync (`ZoomWebinarSync`)

1. **Discover:** upcoming scheduled webinars from `GET /users/{Zoom_User_Id}/webinars?type=scheduled`, plus webinars already in Salesforce that started in the last 3 days (and are not Deleted).
2. **Per webinar** (one queueable per webinar, chained): `GET /webinars/{id}`, registrants with status `approved` and `pending`, and – only if the webinar has ended – `GET /past_webinars/{id}/participants`. Participants are aggregated per person (earliest join, latest leave, summed duration in minutes).
3. All callouts happen before any DML (Salesforce restriction), then webinar and people are upserted.

Manual runs (Developer Console → Execute Anonymous):

```apex
System.enqueueJob(new ZoomWebinarSync());                                   // discover + sync all
System.enqueueJob(new ZoomWebinarSync(new List<String>{'91234567890'}));    // specific webinar(s)
ZoomWebinarSyncScheduler.schedule();                                        // start the 2-hourly job
```

---

## 5. Setup checklist

**In Zoom (Marketplace)**
1. Create a **Server-to-Server OAuth** app. Note Account ID, Client ID, Client Secret.
2. Scopes (granular names may vary by Zoom version): `webinar:read:admin` (webinar + registrants), `report:read:admin` or the past-webinar participants scope.
3. Add a **Event Subscription** (webhook) with endpoint URL `https://<site-domain>/zoomwebhook/services/apexrest/zoom/webhook` and copy the **Secret Token**.
4. Subscribe to: Webinar started/ended/deleted, Registration created/approved/denied/cancelled, Participant/Host joined and left.
5. Click *Validate* – Zoom calls the endpoint and the Apex class answers the challenge.

**In Salesforce**
1. Deploy using `manifest/zoom-package.xml`, then `manifest/zoom-site.xml`.
2. Enter the 4 credential values in Custom Metadata → **Zoom Config → Default** (the committed record has them blank).
3. Setup → Sites → **Zoom Webhook**: confirm it is active and note the domain. Guest profile must have the three Apex classes (already in the profile).
4. Assign permission set **Zoom Webinar Full Access** to the team.
5. Run `ZoomWebinarSyncScheduler.schedule();` once and run an initial `ZoomWebinarSync` to import existing webinars.

> **Verified in `au-uat` on 2026-11-02:** components deployed, credentials populated, Site active, webhook URL `https://ahmedabaduniversity2--hlisuat.sandbox.my.salesforce-sites.com/zoomwebhook/services/apexrest/zoom/webhook` answers the validation challenge (200) and rejects bad signatures (401). The "Zoom Webinar Sync" job is **not** scheduled yet and no events have been received. Details: `docs/requirements/req_zoom-integration.md`.

---

## 6. Testing

- Apex: run `ZoomIntegrationTest` (`sf apex run test --class-names ZoomIntegrationTest --result-format human --code-coverage`). Result in `au-uat` on 2026-11-02: 5/5 pass; coverage ZoomEventService 99%, ZoomWebhook 86%, ZoomConfig 100%, ZoomApiService 97%, ZoomWebinarSync 93%, ZoomWebinarSyncScheduler 100%.
- End to end: use the attached Postman collection `Zoom_Integration.postman_collection.json`:
  - Folder **1 – Zoom API** calls Zoom directly (token, webinars, registrants, participants) to see what Salesforce would receive.
  - Folder **2 – Salesforce Webhook (simulate Zoom)** posts signed sample events to the Site. A pre-request script computes the `x-zm-signature` header from your secret token.
  - Folder **3 – Verify in Salesforce** runs SOQL via the REST API.
  - Folder **4 – Meetings (reference, not implemented)** lists the Zoom endpoints needed for the pending meeting work.

---

## 7. Pending work and gaps

### 7.1 Not implemented
1. **Zoom Meetings.** Nothing exists for meetings: no object, no `meeting.*` event handling, no sync (`/users/{id}/meetings`, `/meetings/{id}/registrants`, `/past_meetings/{id}/participants`). Meetings do not support registration in the same way as webinars (registration is optional), so this needs a short design decision: a separate `Zoom_Meeting__c` object or a `Type__c` on the existing one.
2. **Webinar `created` / `updated` events.** Changes to topic or time reach Salesforce only on the next 2-hourly sync, or when a started/ended/registration event carries the data.
3. **Lead creation for unmatched registrants.** Today they sit on `Zoom_Registration__c` with `Is_Matched__c = false`.
4. **UI and reporting:** related lists on Lead/Contact, Lightning page layouts, reports and dashboards for registered vs attended.
5. **Reverse direction:** registering Salesforce leads in Zoom via API (`POST /webinars/{id}/registrants`).
6. **Follow-ups:** no automation yet that sends "thanks for attending / sorry we missed you" (e.g. WhatsApp or Email) from the attendance data.
7. **Activation of the scheduled job** is a manual step.

### 7.2 Known limitations / risks to review
- **Credentials in Custom Metadata** (`protected=false`): Client Secret and Webhook Secret are readable by anyone with metadata access. Consider making the type protected (managed packages only), or moving to Named/External Credentials.
- **Import window:** the sync imports only *upcoming* scheduled webinars and re-checks Salesforce webinars from the last 3 days. A past webinar missing from Salesforce is not imported automatically; run `new ZoomWebinarSync(new List<String>{'<id>'})` for it. Webinars that ended more than 3 days ago are never re-synced.
- **Participant report delay:** Zoom may take time to publish participants after a webinar ends. Webhook join/leave data covers this; the sync fills in the rest on a later run.
- **Cancelled registration** sets `Is_Registered__c` false but does not remove the earlier "Registered" Task.
- **Pending approval** counts as registered and logs a "Registered" Task.
- **Time in session:** webhook "left" adds (leave − last join); the API sync overwrites it with the summed duration. Values can differ slightly.
- **Governor limits:** one webinar per queueable; each sync job makes several callouts, so a webinar with a very large registrant list (pagination is capped at 20 pages of 300) would need batching.
- **Token** is fetched once per transaction (no cross-transaction cache), so each webhook-triggered sync costs an extra OAuth call.
- **Site URL:** `ZoomWebhook` comments omit the site path prefix; the Site is configured with prefix `zoomwebhook`, so the registered URL must include it. Confirm with a real *Validate* from Zoom.
- **Names:** `Zoom_Webinar__c.Attended_Count__c` is labelled "Registered&Attended"; `Walk_In_Count__c` is "JoinedWithoutRegistration". Roll-up filter criteria are in the field metadata.
- **Test coverage** for the five classes has not been measured; the test mocks only success paths (no 401/429/5xx from Zoom).

### 7.3 Suggested order
1. Confirm deployment + credentials + scheduler in the UAT org and run a real webhook Validate.
2. Decide on the Meeting design and build it by reusing `ZoomEventService` and `ZoomApiService`.
3. Add Lead/Contact related lists and reports.
4. Harden secrets storage and add negative-path tests.
