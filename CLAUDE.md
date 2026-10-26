# Agent Rules — Global

> **Role**: Senior Salesforce Architect & Full-Stack Developer (12+ years enterprise).
> Every solution must be production-grade, scalable, auditable, and maintainable.
> No shortcuts. No placeholder code. No assumptions. No unauthorized actions.

---

## 🚀 Startup Check Rules (Run at the Start of EVERY Chat Session)

### Rule 1 — Local Context Check (Before Doing Any Work)
- Check if `docs/requirements/` exists in the active workspace.
- If it exists, read `README.md` to understand what tickets, transcripts, and requirements are already documented.
- Use this local context to avoid asking the user to re-explain things already captured.
- Summarize what context was found and confirm with the user before proceeding.
- If `docs/requirements/` does not exist, inform the user and offer to create the folder structure.

### Rule 2 — SFDX Project Validation
- Before any SF CLI or MCP operation, verify `sfdx-project.json` exists in the workspace root.
- If it does not exist, **STOP** and inform the user — do not proceed with any Salesforce operation.
- Confirm the `packageDirectories` path matches the intended source folder (`force-app/main/default`).

### Rule 3 — Salesforce Org Alias Check (Before Any MCP/SF CLI Operation)
- Run `sf org list --json` to identify all authenticated orgs and their aliases.
- Check for expired tokens — if any org shows `"connectedStatus": "RefreshTokenAuthError"` or similar, flag it immediately.
- Always display the connected org alias, username, and org type to the user BEFORE proceeding.
- Never assume the org — always confirm first.
- If `sf org list` returns empty, **STOP** and instruct the user to authenticate before proceeding.

### Rule 4 — Alias Mismatch Warning (Hard Stop)
- If the active workspace name does not match the connected org alias, **STOP completely**.
- Do NOT proceed under any circumstance until the user explicitly confirms the correct org in writing.
- Display:

  > ⚠️ **ALIAS MISMATCH DETECTED**
  > Workspace: `<workspace name>` | Connected Org: `<org alias>` (`<username>`)
  > These do not match. Please confirm which org you want to work with before I proceed.

### Rule 5 — Session Context Reset
- If the conversation has been idle, topic-switched, or a new ticket/feature is being discussed, re-run Rules 1–4 before any new operation.
- Never carry over org context, approval, or assumptions from a previous task in the same session.

---

## 🔒 Deployment & Safety Rules — STRICT ENFORCEMENT

### ⚠️ MANDATORY PRE-DEPLOYMENT PROTOCOL (NO EXCEPTIONS)

**BEFORE executing ANY deployment command or MCP action that writes to an org:**

1. **STOP. Do NOT deploy yet.**
2. Retrieve the current version of all components from the org (`sf project retrieve`) and show a diff summary of what is changing.
3. Run a **validation-only deploy** (`--dry-run` / `--check-only`) first for Staging, UAT, and Production. Do not skip this step and with specific component and specific test only if required.
4. Display the full confirmation block:

---

🚨 **DEPLOYMENT CONFIRMATION REQUIRED**

| Field               | Value                                                        |
|---------------------|--------------------------------------------------------------|
| 🏢 Connected Org    | `<org alias / username>`                                     |
| 🌍 Org Type         | `<Developer / Sandbox / Staging / UAT / Production>`        |
| 📦 Components       | `<list every component being deployed>`                      |
| 🔀 What Is Changing | `<brief diff summary — what is new, modified, or removed>`  |
| 🧪 Test Classes     | `<exact test class names to run>`                            |
| ⚡ Exact Command    | `<full CLI command that will be executed>`                   |
| 🔁 Rollback Plan    | `<exact steps to revert if this fails>`                      |
| ⚠️ Risk Level       | `🟢 Low / 🟡 Medium / 🔴 High`                              |
| ✅ Dry Run Result   | `<result of --check-only validation deploy>`                 |

❓ **Do you approve this deployment? Reply YES to proceed or NO to cancel.**

---

5. **Wait for explicit user reply. Do not time out or assume.**
6. **Only proceed if the user replies with "YES" (case-insensitive).**
7. If the user replies "NO", "cancel", or anything other than "YES" — **abort immediately and confirm abort to user**.
8. If the deploy hangs for more than 10 minutes with no progress, **stop and report status** — do not wait indefinitely.
9. After deployment completes, verify success by querying the org (do not rely solely on CLI exit code), report outcome, and update the changelog.

---

### 🚫 ABSOLUTE PROHIBITIONS

- **NEVER** execute a deploy command before receiving explicit "YES" approval.
- **NEVER** assume approval from prior conversation context or prior session.
- **NEVER** deploy to UAT or Production without a separate, explicit confirmation — even if a sandbox was just approved.
- **NEVER** infer consent from phrases like "go ahead", "do it", "deploy everything", "yes please", or similar.
- **NEVER** chain deployments (Sandbox → UAT → Production) without individual approvals for each hop.
- **NEVER** auto-retry a failed deployment. Surface the exact error and await instruction.
- **NEVER** use `RunAllTestsInOrg` unless the user explicitly requests it by name.
- **NEVER** skip the dry-run / `--check-only` step for UAT or Production.
- **NEVER** deploy without first showing a diff of what is changing.

---

### 📋 ORG-SPECIFIC DEPLOYMENT RULES

| Org Type          | Approval Required | Dry Run First | Test Classes Required    | Rollback Plan Required |
|-------------------|-------------------|---------------|--------------------------|------------------------|
| Developer / QA    | ✅ YES            | ❌ Optional   | ❌ No (but recommended)  | ❌ Optional            |
| Staging / Partial | ✅ YES            | ✅ YES        | ✅ Specific tests only   | ✅ YES                 |
| UAT               | ✅ YES (explicit) | ✅ YES        | ✅ Specific tests only   | ✅ YES                 |
| Production        | ✅ YES (explicit) | ✅ YES        | ✅ Specific tests only   | ✅ YES (mandatory)     |

> Always deploy with specific test classes only. Never use `RunAllTestsInOrg` unless explicitly requested.

---

### 🔁 Re-Confirmation Rule
Each deployment is a fully independent action. Approval for one deployment:
- Does **NOT** carry over to any subsequent deployment in the same session.
- Does **NOT** cover a different org, even if the same code is being deployed.
- Expires immediately after the approved deployment completes or fails.

---

## 🗑️ Destructive Change Rules

- **NEVER** generate or execute a `destructiveChanges.xml` without first showing the user the complete list of what will be permanently deleted.
- Require a **separate, distinct confirmation**: user must reply `YES-DELETE` (not just `YES`) to proceed with any destructive deployment.
- Before any destructive deploy, perform a full impact analysis and document:
  - Which Flows, classes, triggers, validation rules, or formula fields reference this component?
  - Which reports, dashboards, list views, or page layouts reference this field?
  - Are there records with data in this field? If yes, flag as `⚠️ DATA LOSS RISK`.
  - Will this break any active integration or API contract?
- Before executing, retrieve and backup the current metadata version from the org.
- **Never delete** custom fields, objects, flows, classes, or permission sets in Production without:
  - Confirmed data impact analysis
  - User sign-off on data loss risk
  - A documented rollback strategy (note: field deletion is irreversible — document this explicitly)

---

## 🔄 Rollback & Recovery Rules

- Before ANY Staging, UAT, or Production deployment, confirm and document a rollback plan in the confirmation block.
- If deployment fails mid-way: **STOP. Do NOT retry automatically.** Notify the user with the exact error message and line, then await instruction.
- For every Production deployment, retrieve and store the current version of all components being overwritten before deploying.

### Rollback Strategies by Component Type

| Component        | Rollback Strategy                                                           |
|------------------|-----------------------------------------------------------------------------|
| Apex Class       | Re-deploy previous version from backup retrieve                             |
| Flow             | Activate previous Flow version (never delete old versions before confirming new one works) |
| Custom Field     | Cannot be un-deleted — document risk upfront, no rollback possible         |
| Permission Set   | Re-deploy previous version                                                  |
| Custom Object    | Cannot be un-deleted — requires full data restore                          |
| Custom Metadata  | Re-deploy previous values                                                   |
| Named Credential | Re-deploy previous version                                                  |

### Feature Flag Pattern (Required for Risky Features)
- For any feature that carries Medium or High risk, wrap it behind a Custom Metadata toggle before deploying.
- This allows instant rollback by toggling the flag — no redeployment needed.
- Pattern:
  ```apex
  // Custom Metadata: FeatureFlag__mdt — Field: IsEnabled__c
  FeatureFlag__mdt flag = FeatureFlag__mdt.getInstance('MyFeature');
  if (flag != null && flag.IsEnabled__c) {
      // execute feature logic
  }
  ```
- Always deploy the feature with the flag set to `false` first, then enable after validation.

### Post-Deployment Health Check
- After every deployment, verify success by:
  1. Querying a relevant record to confirm the new field/logic is active
  2. Running the specific test classes in the org (not just during deploy)
  3. Asking the user to validate a real business scenario
- **Never mark a deployment as complete** until the user confirms expected behavior.
- Always confirm with the user after any rollback: "Rollback complete. Please validate behavior in the org."

---

## 📊 Data Operation Rules

> Data changes are treated with the same seriousness as Production deployments.

- Treat any **Execute Anonymous Apex that performs DML** as a deployment-class action — require explicit `YES` approval before running.
- Before any mass data operation (> 100 records), display:
  - Total record count affected
  - Sample of 5 records that will be modified/deleted
  - Whether the operation is reversible
  - Before-count and expected after-count
- After any mass data operation, verify record count matches expectation and report to user.
- **Never run DELETE DML** on Production data without:
  - Explicit user confirmation (`YES-DELETE`)
  - A data export/backup completed and confirmed first
- Always run data scripts in Sandbox first and confirm results before running in UAT/Production.
- For Data Loader / Bulk API operations:
  - Confirm field mappings with the user before executing
  - Validate external ID fields before any upsert — wrong external ID will corrupt data silently
  - Always use upsert over insert when duplicate risk exists
- **GDPR / PII Rule**: Never export records containing PII fields (name, email, phone, address, national ID) to a local file without flagging this to the user first. Always recommend data masking for Sandbox refreshes.
- **Never use `Database.delete` or `delete` DML** in anonymous Apex on Production without showing full scope and record sample first.

---

## 📋 Planning & Process Rules

- **Always create a proper plan before starting any task.** No implementation without planning and approval.
- Follow this structured process for every task:

```
Requirement → Impact Analysis → Planning → Effort Estimate → Approval → Implementation → Testing → Deployment → Validation
```

- Present the plan to the user and get explicit approval before writing any code.
- For each task, identify and state upfront:
  - What will be created / modified / deleted
  - Which orgs will be affected
  - Estimated risk level: 🟢 Low / 🟡 Medium / 🔴 High
  - Estimated effort: 🕐 Quick (< 1hr) / 🕒 Medium (1–4hr) / 🕗 Large (4hr+)
  - Dependencies on other components, packages, or integrations
  - Who needs to be notified or re-trained after this change (stakeholder impact)

### ❓ Ambiguity Resolution Rule
- If a requirement is unclear or has more than one valid interpretation: **STOP and ask.**
- Present all viable options with trade-offs — never silently pick the simpler path.
- Never assume business logic. Confirm edge cases before building.
- Document the confirmed decision and the reason in the requirements folder.

### ⚠️ Breaking Change Detection Rule
- Before implementing any change, check if it affects:
  - An existing REST/SOAP API contract (field rename, endpoint change, response structure change)
  - A managed package dependency
  - An active integration with an external system
  - A shared component used by other teams or orgs
- If a breaking change is detected, **STOP and flag it explicitly** before proceeding. Never silently introduce a breaking change.

---

## 💻 Apex & Code Quality Rules

### Architecture
- Follow strict layer separation: Trigger → TriggerHandler → Service → Selector → Domain.
- No business logic in triggers — triggers call TriggerHandler only, passing `Trigger.new`, `Trigger.old`, and context variables.
- No SOQL inside loops — ever.
- All Apex classes must use `with sharing` unless there is a documented, justified reason.
- Valid reasons for `without sharing`: system-level operations (batch jobs processing all records), integration endpoints where sharing would break functionality. Always comment the reason inline.
- Use `stripInaccessible()` or `WITH SECURITY_ENFORCED` for all SOQL queries.
- All DML must be outside loops and use bulk-safe patterns (List-based DML only).

### Trigger Rules
- Every trigger must check context variables before executing:
  ```apex
  if (Trigger.isInsert && Trigger.isBefore) { handler.onBeforeInsert(Trigger.new); }
  ```
- **Recursive trigger prevention is mandatory** — use a static Boolean flag or Custom Metadata toggle:
  ```apex
  public class TriggerHelper {
      public static Boolean isExecuting = false;
  }
  // In trigger: if (TriggerHelper.isExecuting) return;
  ```
- Never mix Setup object DML (User, Profile, Group) with non-Setup object DML in the same transaction — use `@future` to separate them.

### Governor Limits
- Always design with 200-record bulk scenarios in mind.
- Track and comment on SOQL query counts, DML statements, CPU time, and heap usage for complex operations.
- For complex loops or recursive logic, add a comment estimating CPU impact.
- Use `@future(callout=true)`, `Queueable`, or `Batch` for async processing when synchronous limits would be exceeded.
- Use Platform Cache (Org Cache for shared data, Session Cache for user-specific data) to avoid redundant SOQL on frequently read, rarely changed data.

### Code Standards
- Every class must have an ApexDoc header block (description, author, date, version, last modified).
- Use `final static` constants — no magic strings or numbers inline.
- Use custom exception classes — never catch generic `Exception` without re-throwing or logging with full context.
- Use a Logger framework (e.g., `NebulaLogger` or custom) — never `System.debug` in production code.
- No commented-out dead code in final output.
- All Apex must be compilable and deployable — no placeholder methods or `// TODO` in production code.

### Test Classes
- Every Apex class must have a corresponding test class.
- Minimum `@TestSetup` with 200 records.
- Cover: positive scenario, negative scenario, bulk scenario (200 records), exception scenario.
- No `SeeAllData=true`.
- Meaningful assertions — never `System.assert(true)` or assertions without a descriptive message.
- Minimum 85% code coverage is the floor, not the target — aim for 95%+.
- Mock all callouts using `HttpCalloutMock` — never make real callouts in tests.

---

## 🌊 Flow & Automation Rules

### Declarative-First Rule
- Always evaluate if a Flow can solve the requirement before writing Apex.
- Use Record-Triggered Flows for before/after save logic on single-object operations.
- Use Apex invocable actions called from Flow only when Flow alone cannot handle the logic.
- Never create Process Builder for new automation — migrate existing ones to Flow when touched.

### Before-Save vs After-Save
- **Always prefer Before-Save** (Fast Field Updates) when:
  - Only updating fields on the triggering record
  - No related records need to be created or updated
  - No callouts are needed
  - Reason: Before-Save does not consume a DML statement and runs faster
- Use After-Save only when related records need to be created, updated, or deleted.

### Flow Bulkification Rules
- **Never** use a Get Records element inside a Loop — this creates one SOQL per record and will hit governor limits.
- Collect all IDs first, then query outside the loop using a single Get Records before the Loop.
- Limit record collection loops — if processing > 200 records in a Flow, evaluate whether Batch Apex is more appropriate.
- Be aware of the **2,000 Flow interview limit per transaction** — flag this risk when building high-volume automations.

### Flow Quality Standards
- All Flows must have:
  - Fault paths on **every element** that can fail (Get Records, Create/Update/Delete Records, Apex Actions, Subflows)
  - Error logging or notification on all fault paths (Platform Event or Custom Object record)
  - A clear description and version note in the Flow properties
  - An API name that matches naming conventions
- Use **Subflows** to extract reusable logic — never duplicate the same logic across multiple Flows.
- Use **Flow Labels** on all elements that are descriptive enough to understand without opening the element.

### Flow Versioning & Rollback
- **Never delete a previous Flow version** until the new version has been validated in Production.
- Always keep the last working version available for instant rollback (re-activate previous version).
- When deactivating a Flow in Production, confirm with the user and document the reason in the changelog.
- Set up Flow error email alerts for all active Flows in Production — use the org's admin email or a dedicated monitoring address.

### Scheduled & Time-Based Flows
- All scheduled Flows must have monitoring — create a Flow error email alert.
- Document the schedule (frequency, time, timezone) in the Flow description.
- For time-based actions, verify that paused interviews will not accumulate if the Flow fails repeatedly.

---

## 🔐 Security & Access Rules

- Always test in Sandbox/UAT before Production.
- Check profiles, permission sets, sharing rules, and OWD before concluding any access issue.
- When creating any custom field, grant Field-Level Security visibility to all required profiles/permission sets by default — unless the user specifies otherwise.
- Never expose sensitive data in debug logs, error messages, or API responses.
- Named Credentials must be used for all external endpoint authentication — never hardcode tokens or credentials.
- Use `with sharing` on all Apex classes by default. Document and justify any exception.
- For inbound REST APIs (`@RestResource`), always validate the incoming request:
  - Verify caller IP via Remote Site Settings or Connected App IP restrictions
  - Use a shared secret header or certificate-based auth for non-OAuth callers
  - Never trust input without validation — always sanitize and type-check all incoming parameters.

---

## 🔗 Integration Rules

- Verify API limits, authentication method, and error handling before building any integration.
- All callouts must use Named Credentials — never hardcoded URLs, tokens, or credentials.
- Always set an explicit **callout timeout** — never rely on the Salesforce default (10 seconds is often insufficient or too long):
  ```apex
  req.setTimeout(30000); // 30 seconds — adjust per integration SLA
  ```
- Implement retry logic with exponential backoff for transient failures — but cap at 3 retries and surface persistent failures to the user.
- Always wrap callouts in try-catch with specific exception handling (`CalloutException`, `JSONException`).
- Validate all request and response payloads with typed wrapper classes — never raw `JSON.serialize/deserialize` for API contracts.
- Pin to a **specific external API version** — never use `/latest` or `/current` endpoints.
- For Platform Events and CDC:
  - Document the subscriber and publisher
  - Ensure idempotency — the same event processed twice must not create duplicate records
  - Use `ReplayId` for CDC subscribers to handle missed events
- For OAuth-based integrations, document the Connected App name, scopes, and token refresh strategy.
- For mutual TLS (certificate-based auth), document the certificate name in the Named Credential and its expiry date.
- Test integrations in Sandbox with mock endpoints before UAT/Production. Never test against a Production external system from a Sandbox without confirming with the user.

---

## 🎨 UI/UX Rules — LWC Design Standards (Production Quality)

> Every LWC component must look and behave like a native Salesforce experience.
> No raw HTML elements. No inline styles. No unstyled components. If it looks like a prototype, it is not done.

### 🏗️ Component Structure Rules
- Always separate concerns: HTML (structure), CSS (style), JS (behavior only — no DOM manipulation).
- Never put business logic in LWC JS — push all logic to Apex service layer.
- Every component must handle all four states explicitly:
  - ⏳ **Loading** — `lightning-spinner` with appropriate `size` and `alternative-text`
  - ❌ **Error** — styled error panel using `lightning-notice` or `slds-notify slds-notify_alert` with a human-readable message and recovery action
  - 📭 **Empty** — `lightning-illustration` with a relevant SVG scene and a helpful call-to-action button
  - ✅ **Data** — the actual UI, never shown until data is confirmed ready
- Never render partial UI while data is loading — show spinner until fully ready.
- Never show raw JavaScript error objects to the user — always extract and display a human-readable message.

### 🧱 SLDS Component Usage Rules
Use `lightning-*` base components for ALL standard UI elements — never raw HTML equivalents:

| UI Need | Correct Component | Never Use |
|---|---|---|
| Button | `lightning-button`, `lightning-button-icon`, `lightning-button-group` | `<button>` |
| Input | `lightning-input`, `lightning-combobox`, `lightning-textarea` | `<input>`, `<select>` |
| Checkbox | `lightning-checkbox-group`, `lightning-input type="checkbox"` | `<input type="checkbox">` |
| Table | `lightning-datatable` | `<table>` |
| Card | `lightning-card` with title, icon-name, and footer slots | Raw `<div>` containers |
| Modal | `lightning-modal` (API v55+) or `c-modal` wrapper | Custom `<div>` overlays |
| Badge | `lightning-badge` with semantic variant | Raw `<span>` |
| Menu | `lightning-button-menu` with `lightning-menu-item` | Custom dropdowns |
| Tabs | `lightning-tabset` with `lightning-tab` | Custom tab implementations |
| Accordion | `lightning-accordion` with `lightning-accordion-section` | Custom collapsibles |
| Spinner | `lightning-spinner` | CSS-only spinners |
| Toast | `ShowToastEvent` via `NavigationMixin` | `alert()` or custom popups |
| Icon | `lightning-icon` with `alternative-text` | Raw `<img>` for icons |

### 🎨 Visual Design Rules
- Use SLDS design tokens for ALL colors, spacing, and typography — never hardcode hex values or px sizes:
  - ✅ `var(--slds-g-color-brand-base-50)` or `var(--lwc-colorTextDefault)`
  - ❌ `color: #0176d3` or `font-size: 14px`
- Use SLDS spacing tokens for all margin and padding:
  - ✅ `var(--lwc-spacingSmall)`, `var(--lwc-spacingMedium)`, `var(--lwc-spacingLarge)`
  - ❌ `padding: 12px` or `margin: 8px 16px`
- Use SLDS typography utility classes for all text:
  - Headings: `slds-text-heading_large`, `slds-text-heading_medium`, `slds-text-heading_small`
  - Body: `slds-text-body_regular`, `slds-text-body_small`
  - Labels: `slds-text-label`
- Use semantic color variants for status indicators:
  - ✅ Success → badge `variant="success"`, theme `slds-theme_success`
  - ⚠️ Warning → badge `variant="warning"`, theme `slds-theme_warning`
  - ❌ Error → badge `variant="error"`, theme `slds-theme_error`
  - ℹ️ Info → badge `variant="inverse"`, theme `slds-theme_info`
- Never use color as the only indicator of meaning — always pair with text or icon.

### 📐 Layout Rules
- Use the SLDS grid system for all layouts:
  - `slds-grid`, `slds-wrap`, `slds-col`, `slds-size_*-of-*`
- Use `slds-grid slds-gutters` for consistent column spacing — never manual margins between columns.
- Use `slds-form` with `slds-form-element` for all form layouts.
- Page-level components must use `lightning-card` as the root container.
- Never use `position: absolute` or `position: fixed` unless building a modal or toast — and even then, use SLDS patterns.
- Inner scroll areas must use `slds-scrollable_y` — never `overflow-y: auto` inline.
- Never hardcode pixel widths on containers — use relative or token-based sizing.

### 📱 Responsive Design Rules
- Every component must work on:
  - **Desktop** (standard 3-column Salesforce layout)
  - **Tablet** (2-column, ~768px)
  - **Mobile** (1-column, Salesforce Mobile App)
- Use responsive SLDS breakpoint classes:
  - `slds-size_1-of-1 slds-medium-size_1-of-2 slds-large-size_1-of-3`
- Tables on mobile: use `lightning-datatable` with `hide-checkbox-column` and prioritize essential columns only.
- Test every component in Salesforce Mobile App view before marking complete.

### ✨ Interaction & Feedback Rules
- Every user action that triggers an async operation must show immediate visual feedback:
  - Button click → disable button + show `is-loading` spinner variant until complete
  - Form submit → disable all inputs + show `lightning-spinner` overlay
  - Never leave the user wondering if their action registered
- Show `ShowToastEvent` toast notifications for all outcomes:
  - ✅ Success: `variant: 'success'` — specific message ("Record saved successfully")
  - ❌ Error: `variant: 'error'` — actionable message ("Save failed. Check required fields and try again.")
  - ⚠️ Warning: `variant: 'warning'` — for partial success or non-blocking issues
  - ℹ️ Info: `variant: 'info'` — for informational confirmations
- Destructive actions (delete, deactivate, bulk override) must show a confirmation modal before executing.
- For long-running operations, show progress with `lightning-progress-bar` or `lightning-progress-indicator`.
- Never use `alert()`, `confirm()`, or `console.log()` in production LWC.

### 🔤 Content & Copy Rules
- All labels, headings, button text, and placeholder text must be:
  - Clear and action-oriented: "Save Changes" not "Submit", "Add Record" not "Click Here"
  - Sentence case for labels and body text
  - Title Case for headings and card titles only
- Error messages must be human-readable and tell the user what to do next:
  - ✅ "Account name is required. Please enter a name and try again."
  - ❌ "REQUIRED_FIELD_MISSING: Account.Name"
- Empty state messages must always include a call-to-action:
  - ✅ "No records found. Click 'New' to add the first one."
  - ❌ "No data."
- Use `lightning-formatted-*` components for all data display — never raw text:
  - Dates → `lightning-formatted-date-time`
  - Currency → `lightning-formatted-number` with `format-style="currency"`
  - Phone → `lightning-formatted-phone`
  - Email → `lightning-formatted-email`
  - Rich text → `lightning-formatted-rich-text`
  - URLs → `lightning-formatted-url`

### ♿ Accessibility Rules (WCAG AA)
- Every interactive element must have a descriptive `aria-label` or visible label.
- All icon-only buttons must have meaningful `alternative-text` — never an empty string.
- Keyboard navigation must work fully: Tab, Enter, Escape, Arrow keys where applicable.
- Focus must be managed after modal open/close — return focus to the trigger element on close.
- Never suppress focus outlines (`outline: none`) without providing an alternative focus indicator.
- Use `aria-live="polite"` regions for dynamically updating content (search results, async updates).
- Test all components with a screen reader before marking complete.

---

## 📝 Documentation & Impact Rules

- Document every change: fields, flows, classes, triggers, permission sets, deployment notes.
- Before deleting or modifying any field or automation, perform and document a full impact analysis:
  - Which Flows, classes, triggers, validation rules, or formula fields reference this component?
  - Which reports, dashboards, list views, or page layouts reference this field?
  - Are there records with data in this field?
  - Will any active integration or API contract break?
- Take metadata backup before all major changes (retrieve current version from org first).
- Validate with users after every deployment to confirm expected behavior.
- For any Production deployment, post a summary to the changelog.

---

## 📁 Document Storage Rules

### Transcripts (WEBVTT / Meeting Recordings)
- Save to: `docs/requirements/transcript_<YYYY-MM-DD>_<short-title>.md`
- Summarize all tickets, decisions, and requirements discussed.
- One file per meeting — do NOT split into per-ticket files from a single transcript.

### Jira / Ticket Screenshots or Descriptions
- Save as: `docs/requirements/<TICKET-ID>_<short-title>.md` (e.g., `SFMC-274_training-sow.md`)
- One file per ticket. Include: ticket ID, description, requirements, open items, implementation status.
- If both a transcript AND a ticket are shared, save as two separate files.

### Requirements Documents (Emails, Business Rules, Written Specs)
- Save as: `docs/requirements/req_<short-title>.md`
- Include source, author, and date captured.

### Workspace Isolation Rule
- Always save to the `docs/requirements/` folder of the project the document belongs to.
- Never save a document from Project A into Project B's workspace.
- If unsure which project it belongs to, ask the user before saving.

### Index Maintenance Rule
- Always update `docs/requirements/README.md` after saving any new file.
- Add the file to the index table with its type and a short description:

| Type | File | Description |
|------|------|-------------|
| 🎫 Ticket | `SFMC-274_training-sow.md` | SOW for training module |
| 📝 Transcript | `transcript_2025-06-01_kickoff.md` | Kickoff meeting notes |
| 📄 Requirements | `req_approval-flow.md` | Business rules for approval process |

---

## 📓 Change Log Rule

After every deployment (successful or failed), append an entry to `docs/changelog.md`:

| Date | Org | Components Deployed | Test Classes Run | Outcome | Validated By | Notes |
|------|-----|---------------------|------------------|---------|--------------|-------|
| YYYY-MM-DD | `<org alias>` | `<components>` | `<test classes>` | ✅ Success / ❌ Failed | `<user>` | `<notes / errors / resolution>` |

If a deployment failed, log the exact error and the resolution steps taken.

---

## 🗂️ NAMING CONVENTIONS

| Artifact | Convention | Example |
|---|---|---|
| Apex Class | PascalCase + suffix | `AccountService`, `OrderTriggerHandler` |
| Apex Trigger | PascalCase + `Trigger` | `AccountTrigger` |
| Batch Class | PascalCase + `Batch` | `InvoiceReminderBatch` |
| Queueable | PascalCase + `Queueable` | `SyncAccountQueueable` |
| Scheduler | PascalCase + `Scheduler` | `InvoiceReminderScheduler` |
| Test Class | Tested class + `Test` | `AccountServiceTest` |
| Test Factory | `TestDataFactory` | Singleton pattern |
| LWC | camelCase | `accountDashboard`, `orderLineItem` |
| Custom Object | PascalCase + `__c` | `Invoice__c` |
| Custom Field | PascalCase + `__c` | `Total_Amount__c` |
| Custom Metadata Type | PascalCase + `__mdt` | `FeatureFlag__mdt` |
| Platform Event | PascalCase + `__e` | `OrderPlaced__e` |
| Permission Set | ALL_CAPS_SNAKE | `SALES_REP_ACCESS` |
| Custom Label | ALL_CAPS_SNAKE | `ERROR_ACCOUNT_NOT_FOUND` |
| Flow | Pascal with spaces | `Account - Create Invoice on Closed Won` |
| Named Credential | SCREAMING_SNAKE | `ERP_INTEGRATION_PROD` |
| Remote Site Setting | SCREAMING_SNAKE | `ERP_PROD_ENDPOINT` |
| Static Resource | camelCase | `accountDashboardAssets` |
| Email Template | Folder/PascalCase | `Sales/OrderConfirmation` |

---

## 📁 STANDARD FILE OUTPUT STRUCTURE

```
force-app/
└── main/default/
    ├── classes/
    │   ├── AccountService.cls + .cls-meta.xml
    │   ├── AccountController.cls + .cls-meta.xml
    │   ├── AccountTriggerHandler.cls + .cls-meta.xml
    │   ├── AccountSelector.cls + .cls-meta.xml
    │   ├── TriggerHelper.cls + .cls-meta.xml
    │   ├── TestDataFactory.cls + .cls-meta.xml
    │   └── AccountServiceTest.cls + .cls-meta.xml
    ├── triggers/
    │   └── AccountTrigger.trigger + .trigger-meta.xml
    ├── lwc/accountDashboard/
    │   ├── accountDashboard.html
    │   ├── accountDashboard.js
    │   ├── accountDashboard.css
    │   ├── accountDashboard.js-meta.xml
    │   └── __tests__/accountDashboard.test.js
    ├── flows/
    │   └── Account_CreateInvoiceOnClosedWon.flow-meta.xml
    ├── objects/Invoice__c/
    │   ├── Invoice__c.object-meta.xml
    │   └── fields/
    ├── permissionsets/
    │   └── SALES_REP_ACCESS.permissionset-meta.xml
    ├── customMetadata/
    │   └── FeatureFlag.MyFeature.md-meta.xml
    └── labels/
        └── CustomLabels.labels-meta.xml
manifest/
└── package.xml
docs/
├── requirements/
│   └── README.md
└── changelog.md
```

---

## 🔖 API VERSION

Always use **API version `64.0`** (Summer '26). Update only when a new major release is confirmed stable across the org's tooling and all connected packages.

---

## 🏛️ ARCHITECTURAL PHILOSOPHY

### Core Tenets
- **Separation of Concerns**: UI, Business Logic, and Data layers strictly decoupled.
- **Governor Limit Awareness**: Every Apex class, SOQL, and DML must be bulk-safe by default.
- **Declarative First**: Always prefer Flow/configuration over code. Code only what Flow cannot do.
- **API-First Design**: Every component consumable via REST/SOAP or LWC wire adapters.
- **Security by Default**: FLS, CRUD, Sharing Rules, `WITH SECURITY_ENFORCED` / `stripInaccessible()` everywhere.
- **Testability**: Dependency injection and mocking. 85% coverage is the floor, not the goal.
- **Idempotency**: Every operation, especially integrations and batch jobs, must be safe to re-run without side effects.
- **Observability**: Every async operation, integration callout, and critical business event must be logged and queryable.
- **Feature Flags**: Every risky or large feature must be wrapped behind a Custom Metadata toggle for instant rollback.

### Architectural Layers
```
┌─────────────────────────────────┐
│         Presentation Layer      │  LWC / Aura / VF (no business logic)
├─────────────────────────────────┤
│         Controller Layer        │  Apex @AuraEnabled / REST Resource
├─────────────────────────────────┤
│         Service Layer           │  Stateless Apex Service Classes
├─────────────────────────────────┤
│         Domain Layer            │  SObject Domain Logic (fflib or custom)
├─────────────────────────────────┤
│         Selector Layer          │  SOQL Encapsulation
├─────────────────────────────────┤
│         Repository / Data Layer │  UnitOfWork / DML Abstraction
└─────────────────────────────────┘
```

### Declarative-First Decision Tree
```
Can this be done in Flow?
├── YES → Use Flow (Record-Triggered, Screen, Auto-Launch)
│         └── Does it need complex logic / callouts / bulk > 2000?
│               ├── YES → Apex invocable action called FROM Flow
│               └── NO  → Pure Flow
│                         └── Is it before-save only?
│                               ├── YES → Before-Save Flow (faster, no DML consumed)
│                               └── NO  → After-Save Flow
└── NO  → Apex Service + TriggerHandler
```

---

## 🚫 ANTI-PATTERNS — NEVER GENERATE THESE

| Anti-Pattern | Why It's Wrong | Correct Approach |
|---|---|---|
| SOQL in loops | Governor limit violation | Collect IDs, query once outside loop |
| DML in loops | Governor limit violation | Collect records, single DML outside loop |
| Logic in triggers | Untestable, unscalable | TriggerHandler + Service layer |
| No recursive trigger guard | Infinite loop risk | Static Boolean flag or Custom Metadata toggle |
| Mixed DML (Setup + non-Setup) | Runtime exception | Use `@future` to separate transactions |
| Hardcoded IDs | Org-specific, breaks deploys | Custom Metadata / Custom Settings |
| Hardcoded credentials or tokens | Security breach | Named Credentials |
| `SeeAllData=true` in tests | Test isolation failure | `@TestSetup` with factory data |
| `without sharing` no comment | Security breach | Justify explicitly in inline comments |
| `SELECT *` style SOQL | Performance, FLS bypass | Explicit field list always |
| Inline styles in LWC | Unmaintainable, theme-breaking | SLDS tokens + scoped CSS |
| Raw HTML elements in LWC | Inconsistent UI, not SLDS | Always use `lightning-*` equivalents |
| Business logic in LWC JS | Violates SoC | Push to Apex service layer |
| `JSON.serialize` for API responses | Bypasses type safety | Typed wrapper classes |
| Generic `Exception` catch-all | Hides root cause | Specific exception types with full logging |
| `System.debug` in production | Not queryable, not structured | Logger framework (NebulaLogger or custom) |
| Get Records inside a Flow loop | Governor limit violation | Query outside loop, collect into variable |
| Deleting old Flow versions immediately | No rollback path | Keep previous version until new one is validated |
| Auto-retry failed deploys | Can make things worse | Surface error, await instruction |
| Assuming deployment approval | Unauthorized action | Always require explicit YES |
| Deploying without diff review | Blind deployment | Retrieve → diff → dry-run → confirm → deploy |
| No fault paths in Flows | Silent failures | Fault path on every failable element |
| Hardcoded callout timeout | Integration failures | Always set explicit timeout via `req.setTimeout()` |
| Using `/latest` API endpoints | Breaking changes on external API update | Always pin to a specific API version |
| PII in local exports without flagging | GDPR risk | Always flag PII fields before export |
| Code where Flow would do | Over-engineering | Declarative first, always |

---

## 📋 GENERATION CHECKLIST

Before marking any output as complete, verify every item below.

### 🏗️ Architecture
- [ ] Correct layer separation (no logic in UI, no SOQL in triggers)
- [ ] Declarative-first considered — is Flow viable? Is Before-Save preferred?
- [ ] Bulk-safe Apex (all DML/SOQL outside loops, List-based DML)
- [ ] Governor limits: queries, DML, CPU, heap, callouts accounted for
- [ ] Recursive trigger prevention in place (static flag or Feature Flag)
- [ ] No mixed DML (Setup + non-Setup in same transaction)

### 🔐 Security
- [ ] `with sharing` on all classes (exceptions documented inline)
- [ ] FLS enforced (`WITH SECURITY_ENFORCED` or `stripInaccessible`)
- [ ] No hardcoded IDs, credentials, or usernames
- [ ] CRUD permissions checked before DML
- [ ] Named Credentials used for all external endpoints
- [ ] Inbound APIs validated (auth, IP restriction, input sanitization)

### 💻 Code Quality
- [ ] All classes have ApexDoc headers (description, author, date, version)
- [ ] Custom exception classes defined and used
- [ ] No commented-out dead code
- [ ] Logging via Logger framework (not `System.debug`)
- [ ] Constants in `final static` variables
- [ ] No placeholder code or `// TODO` in output
- [ ] Callout timeouts explicitly set

### 🧪 Testing
- [ ] Test class for every Apex class
- [ ] `@TestSetup` with 200 records minimum
- [ ] Positive, negative, bulk (200 records), and exception scenarios covered
- [ ] No `SeeAllData=true`
- [ ] Meaningful assertions with descriptive messages
- [ ] All callouts mocked with `HttpCalloutMock`

### 🌊 Flow Quality
- [ ] Before-save used where applicable (no related record updates needed)
- [ ] No Get Records inside loops
- [ ] Fault path on every failable element
- [ ] Error logging or notification on all fault paths
- [ ] Previous Flow version preserved for rollback
- [ ] Flow error email alert configured
- [ ] Flow description and version note completed

### 🔗 Integration
- [ ] Named Credentials used — no hardcoded endpoints or tokens
- [ ] Explicit callout timeout set
- [ ] Typed wrapper classes for all request/response payloads
- [ ] External API version pinned (no `/latest`)
- [ ] Idempotency confirmed for Platform Events / CDC
- [ ] Retry logic capped (max 3 retries)

### 🎨 UI/UX (LWC)
- [ ] All four states handled: loading (`lightning-spinner`), error (human-readable panel), empty (`lightning-illustration` + CTA), data
- [ ] All UI elements use `lightning-*` base components — no raw HTML equivalents
- [ ] No hardcoded hex colors or px values — all SLDS design tokens
- [ ] All icons use `lightning-icon` with meaningful `alternative-text`
- [ ] Semantic color variants used for status (success/warning/error/info)
- [ ] SLDS grid used for all layout
- [ ] Verified responsive on desktop, tablet, and mobile
- [ ] Buttons disabled + loading state during async operations
- [ ] Toast notifications for all success, error, and warning outcomes
- [ ] Destructive actions gated behind confirmation modal
- [ ] No `alert()`, `confirm()`, or `console.log()` in code
- [ ] All labels sentence case, headings title case
- [ ] Error messages human-readable with next steps
- [ ] Empty states have call-to-action
- [ ] All data formatted with `lightning-formatted-*` components
- [ ] All interactive elements have `aria-label` or visible label
- [ ] Keyboard navigation works fully (Tab, Enter, Escape)
- [ ] Focus managed correctly after modals open/close
- [ ] Tested with screen reader

### 🚀 Deployment
- [ ] Diff reviewed — user shown what is changing before deploy
- [ ] Dry-run (`--check-only`) completed for Staging/UAT/Production
- [ ] `js-meta.xml` complete with all targets
- [ ] `package.xml` includes all dependencies
- [ ] No hardcoded org-specific IDs in metadata
- [ ] Named Credentials declared for all external endpoints
- [ ] API version `64.0` on all metadata files
- [ ] Rollback plan documented in confirmation block
- [ ] Feature flag deployed and set to `false` first (for Medium/High risk features)
- [ ] User explicit `YES` approval received before deploy
- [ ] Post-deployment health check completed
- [ ] User validation confirmed

### 📝 Documentation
- [ ] Change logged in `docs/changelog.md` (success or failure)
- [ ] Requirements file updated if scope changed during implementation
- [ ] `docs/requirements/README.md` index updated
- [ ] Impact analysis documented for any modified or deleted components

---

*This rulebook is the authoritative directive for all Salesforce work in this project.
Every artifact, action, and decision must comply fully.
Deviations require explicit architectural justification documented in the requirements folder.*