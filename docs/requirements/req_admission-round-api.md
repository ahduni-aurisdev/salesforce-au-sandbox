# Admission Round Upsert API

## Source

- Source: User-provided requirements and decisions
- Author: Project stakeholder
- Date captured: 2026-10-16
- Status: Date-window contract revision approved on 2026-10-22; implementation and UAT validation in progress

## Objective

Provide an authenticated Apex REST endpoint that allows the existing external system to insert or update admission rounds in Salesforce. The external system will continue using the existing Connected App and OAuth authentication.

## Salesforce data model

Object: `Admission_Round__c` (Admission Round)

| Label | API name | Type | Configuration |
|---|---|---|---|
| Round Name | `Name` | Standard Text | Required by Salesforce for new records |
| Round Code | `Round_Code__c` | Text(50) | Required, Unique, External ID |
| Admission Year | `Admission_Year__c` | Unrestricted Picklist | Initial values: `Admission Year - 2024`, `Admission Year - 2025`, `Admission Year - 2027`; new values may be supplied as required |
| Department | `Department__c` | Restricted Picklist | `CLeF`, `Career Development Centre`, `Executive Education`, `Graduation`, `Masters`, `Phd`, `Undergraduation` |
| Program | `Program__c` | Text(255) | Optional |
| Round Start Date | `Start_Date__c` | Date | Required for a complete round |
| Round End Date | `End_Date__c` | Date | Required for a complete round |
| Active | `Is_Active__c` | Checkbox | Retained for compatibility but unused by API and assignment logic |

`Cutoff_Date__c` is a read-only formula (`End_Date__c - 5`) used for Lead assignment; it is not sent by the API. `Reminder_Date__c` remains out of scope.

## Endpoint

```http
POST /services/apexrest/v1/admission-rounds/upsert
Authorization: Bearer <existing OAuth access token>
Content-Type: application/json
```

### Request

The endpoint accepts 1–200 records per request.

```json
{
  "records": [
    {
      "roundCode": "UG-2027-R1",
      "roundName": "Undergraduate Round 1",
      "admissionYear": "2027-28",
      "department": "CLeF",
      "program": "B.Tech",
      "startDate": "2027-01-01",
      "endDate": "2027-03-31"
    }
  ]
}
```

### Processing rules

- `roundCode` is required and cannot exceed 50 characters.
- `roundName` is required when the round code does not already exist.
- Dates must use `YYYY-MM-DD` format.
- `department`, when supplied, must match one of the seven configured values exactly.
- Start date must be on or before end date when both are supplied.
- A round code cannot occur more than once in the same request.
- Upsert explicitly uses `Round_Code__c` as the external ID.
- The operation allows partial success. Valid records are committed even when other records fail.
- Omitted optional fields are preserved on updates.
- New records require effective `department`, `admissionYear`, `startDate`, and `endDate`; updates may omit values already stored on the existing Round Code.
- Incoming `isActive` is accepted for backward payload compatibility but ignored.
- The API never activates, deactivates, or deletes historical rounds.
- Lead eligibility is derived dynamically using the inclusive rule `today <= Cutoff_Date__c` (End Date - 5) within the exact Department + Admission Year group. Start Date does not delay eligibility.
- If multiple rounds in one group are usable, the earliest Cutoff Date wins, followed by earliest Start Date, latest Last Modified Date, and record ID.
- Any insert/update of a round on or before its Cutoff Date (including rounds received before their Start Date) immediately launches the group-scoped pending-Lead batch; rounds past their Cutoff Date do not launch it.
- No Scheduled Apex job is used.

### Response behavior

- `200 OK`: all records succeeded.
- `207 Multi-Status`: at least one record failed and at least one record may have succeeded.
- `400 Bad Request`: invalid JSON, missing/empty `records`, or more than 200 records.
- `500 Internal Server Error`: unexpected server-side failure.

Every result contains its request index, round code, Salesforce ID when successful, action (`INSERTED`, `UPDATED`, or `FAILED`), success flag, and record-specific errors.

## Error logging

Failures are inserted in bulk into the existing `API_Log__c` object using:

- `Log_Name__c`: `AdmissionRoundUpsert`
- `Apex_Class_Name__c`: `AdmissionRoundRestResource`
- `Response__c`: sanitized error text
- `Log_Type__c`: `Failed`
- `Registration_Number__c`: round code (reused because the current log schema has no generic external-key field)

The request payload is not persisted, reducing PII and sensitive-data exposure.

## Security and access

- REST and service classes use `with sharing`.
- CRUD and field access are enforced before DML.
- Access is granted directly through only the `Admin` (System Administrator) and `Salesforce API Only System Integrations` profiles. These profiles receive access to `AdmissionRoundRestResource`, Admission Round Read/Create/Edit, visibility/editability for the five non-required custom fields, automatic visibility to required `Round_Code__c`, and the minimum `API_Log__c` Create/field access needed to write failure logs.
- Delete access is intentionally not granted because deletion is outside the approved scope.
- Current profile metadata was retrieved from `au-uat` before modification. The other 37 retrieved profiles remain unchanged and are excluded from the deployment manifest.

## Rollout decision

- On 2026-10-22, the stakeholder approved replacing active/inactive enforcement with date-window eligibility and no scheduler.
- On 2026-10-22, the stakeholder approved cutoff-based eligibility: a round is usable from receipt until `Cutoff_Date__c` (End Date - 5, inclusive), earliest cutoff wins, existing assignments are preserved. Reason: pending Leads must be assigned as soon as a round is received rather than waiting for its Start Date, and new Leads must stop being assigned five days before the End Date. A Lead-Created-Date rule was considered and rejected because it would only assign Leads created inside a round's window.
- Rollback requires redeploying the backed-up UAT versions of the affected Apex classes.

## Deployment status

- Initial UAT deployment: `0Afft000000NbLRCA0` — succeeded.
- Single-active-rule UAT deployment: `0Afft000000NpmbCAC` — succeeded.
- The original active-based implementation was deployed to Production on 2026-10-22. This date-window revision has not been deployed to UAT or Production.
