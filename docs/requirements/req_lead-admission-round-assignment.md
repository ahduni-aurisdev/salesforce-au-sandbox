# Lead Admission Round Assignment

## Source and status

- Source: Stakeholder requirements and clarifications
- Captured: 2026-10-19
- Target: `au-uat`
- Status: Date-window revision approved on 2026-10-22; implementation and UAT validation in progress

## Confirmed behavior

- Use Apex only: triggers, handlers, reusable service/selector, and Batch Apex. No Flow is created or modified.
- Reuse `LeadCombinedTrigger` and `LeadTriggerHandler` for Lead before-insert processing.
- Preserve any pre-populated `Lead.Assigned_Admission_Round__c` value without overwriting it.
- Match on `Lead.Department__c` + `Lead.Admission_Year__c` to a cutoff-eligible `Admission_Round__c`.
- Normalize `PhD` to `Phd` and `Undergraduate` to `Undergraduation`.
- A round is eligible when `Date.today() <= Cutoff_Date__c` (formula: `End_Date__c - 5`); the cutoff day is inclusive and Start Date does not delay eligibility.
- `Is_Active__c` remains physically present for compatibility but is not used by assignment or batch logic.
- Historical rounds for other Admission Years remain independent and are never deleted or deactivated.
- If multiple rounds in the same Department + Admission Year are eligible, the earliest Cutoff Date wins; earliest Start Date, latest Last Modified Date, and then record ID provide deterministic tie-breakers.
- Missing grouping data, a blank End Date (blank cutoff), or no cutoff-eligible matching round leaves the Lead lookup blank and never blocks Lead creation.
- Existing blank-assignment Leads are processed with partial-success Batch Apex. Converted Leads remain in scope as requested; Salesforce update failures are logged and do not stop other Leads.
- Call Batch Apex directly after an Admission Round on or before its Cutoff Date is inserted or updated, including rounds received before their Start Date. Do not create a scheduled job.
- Restrict each batch query to blank-assignment Leads in the saved cutoff-eligible Department + Admission Year combinations.
- Future-dated rounds do not launch the batch. When their date arrives, new Leads are evaluated dynamically, while existing pending Leads require another round upsert/update or manual batch execution.
- Batch-launch failures must not block Admission Round insert/update.
- Reuse `API_Log__c`; do not store Lead PII in logs.

## Live UAT findings

- Lead fields: `Department__c`, `Admission_Year__c`, `Assigned_Admission_Round__c`.
- Round fields: `Department__c`, `Admission_Year__c`, `Is_Active__c`, `Start_Date__c`, `End_Date__c`.
- `Lead_Record_Type_Update_B_CU` is an existing before-save Flow that fills blank Department before Apex triggers. It is not modified.
- No Flow references `Assigned_Admission_Round__c`.
- Existing Apex reuse point: `LeadCombinedTrigger` → `LeadTriggerHandler`.
- No existing Admission Round batch or scheduler was found before the original implementation.
- UAT contained 10,980 blank-assignment Leads and zero assigned Leads at analysis time.

## Failure isolation

- Trigger entry points catch assignment/batch-launch exceptions and never call `addError`.
- Batch updates use `Database.update(records, false)`.
- Only Leads whose lookup was assigned are updated.
- Logging is best-effort and cannot throw into the originating business transaction.
