# Admission Round Upsert API — Integration Guide

## Document control

| Item | Value |
|---|---|
| System | Ahmedabad University Salesforce |
| API | Admission Round Upsert API |
| Version | `v1` |
| Environments | UAT sandbox and Production |
| Status | Existing API deployed in both environments; date-window revision validated and pending UAT deployment |
| Last updated | 2026-10-22 |
| Audience | External integration developers, QA, and Salesforce support |

## Purpose

This authenticated REST API creates or updates Admission Rounds in Salesforce. It supports bulk requests, record-level partial success, idempotent upsert by Round Code, validation, failure logging, and date-window Lead assignment by Department and Admission Year.

## Environment endpoints

### UAT sandbox

```text
Base URL: https://ahmedabaduniversity2--hlisuat.sandbox.my.salesforce.com
Method: POST
Path: /services/apexrest/v1/admission-rounds/upsert
```

### Production

```text
Base URL: https://ahmedabaduniversity2.my.salesforce.com
Method: POST
Path: /services/apexrest/v1/admission-rounds/upsert
Full endpoint: https://ahmedabaduniversity2.my.salesforce.com/services/apexrest/v1/admission-rounds/upsert
```

Always use the `instance_url` returned by Salesforce OAuth instead of hardcoding either environment URL. Never send UAT credentials or test payloads to Production.

The existing Active-based API is currently deployed in Production. The date-window behavior documented here must not be treated as live in Production until its separately validated and approved Production deployment is completed.

## Authentication

The endpoint uses the existing Salesforce Connected App and OAuth 2.0. It does not allow anonymous access or custom username/password headers.

Obtain these securely from the Connected App owner:

- OAuth client/consumer ID
- Approved OAuth flow and token endpoint
- Client secret or certificate when required
- Integration username/principal
- Token-refresh procedure

Standard Salesforce OAuth token hosts:

```text
UAT sandbox: https://test.salesforce.com/services/oauth2/token
Production:  https://login.salesforce.com/services/oauth2/token
```

Use the Connected App configuration and integration principal approved for the target environment. Access tokens are environment-specific and must not be reused across UAT and Production.

Use only the OAuth flow approved for the existing Connected App. Never store client secrets, private keys, passwords, or access tokens in source control, tickets, email, or this document.

The API user should have the `Salesforce API Only System Integrations` profile. `System Administrator` also has access. Required permissions include Apex access to `AdmissionRoundRestResource`, Admission Round Read/Create/Edit, relevant field access, and `API_Log__c` Create access. Delete permission is not used.

### Request headers

```http
Authorization: Bearer <salesforce_access_token>
Content-Type: application/json
Accept: application/json
```

## Request contract

Send a JSON object containing 1–200 records:

```json
{
  "records": [
    {
      "roundCode": "MBA-2027-R1",
      "roundName": "MBA Admission Round 1",
      "admissionYear": "Admission Year - 2027",
      "department": "Masters",
      "program": "MBA",
      "startDate": "2027-01-01",
      "endDate": "2027-03-31"
    }
  ]
}
```

### Recommended multi-record payload

The integration may send current, future, and historical Admission Rounds together. Each item is independently upserted using `roundCode`.

```json
{
  "records": [
    {
      "roundCode": "MBA-2027-R1",
      "roundName": "MBA Admission Round 1",
      "admissionYear": "Admission Year - 2027",
      "department": "Masters",
      "program": "MBA",
      "startDate": "2027-01-01",
      "endDate": "2027-03-31"
    },
    {
      "roundCode": "UG-2027-R1",
      "roundName": "UG Admission Round 1",
      "admissionYear": "Admission Year - 2027",
      "department": "Undergraduation",
      "program": "",
      "startDate": "2027-01-01",
      "endDate": "2027-03-31"
    },
    {
      "roundCode": "MBA-2026-R1",
      "roundName": "MBA Admission Round 1 - Historical",
      "admissionYear": "Admission Year - 2026",
      "department": "Masters",
      "program": "MBA",
      "startDate": "2026-01-01",
      "endDate": "2026-03-31"
    }
  ]
}
```

Do not send `isActive` in new integrations. If an older client sends it, Salesforce accepts the property for payload compatibility but ignores its value.

### Fields

| JSON field | Salesforce field | Type | Required | Rules |
|---|---|---|---|---|
| `roundCode` | `Round_Code__c` | String(50) | Always | Unique external ID/upsert key. Trimmed. Cannot occur twice in one request. |
| `roundName` | `Name` | String(80) | On create | Required for a new Round Code. Omission preserves it on update. |
| `admissionYear` | `Admission_Year__c` | Unrestricted picklist | For a complete record | Use the agreed format, such as `Admission Year - 2027`. New values are allowed. |
| `department` | `Department__c` | Restricted picklist | For a complete record | Must exactly match an allowed value below. |
| `program` | `Program__c` | String(255) | No | Omission preserves it on update. |
| `startDate` | `Start_Date__c` | Date string | For a complete record | Valid `YYYY-MM-DD`; inclusive eligibility start. |
| `endDate` | `End_Date__c` | Date string | For a complete record | Valid `YYYY-MM-DD`; inclusive eligibility end. |
| `isActive` | None | Boolean | No | Deprecated. Accepted for backward compatibility but ignored. |

### Allowed departments

```text
CLeF
Career Development Centre
Executive Education
Graduation
Masters
Phd
Undergraduation
```

Values are exact and case-sensitive. For this API, `PhD`, `Undergraduate`, abbreviations, and other aliases are invalid.

### Date and omission rules

- When both dates are supplied, `startDate` must be on or before `endDate`.
- Salesforce does not calculate a Cutoff Date or Reminder Date.
- Omitted optional fields are preserved on update.
- Blank date strings do not clear stored dates; they are treated as not supplied.
- New rounds require effective Department, Admission Year, Start Date, and End Date. Updates may preserve existing stored values.

## Upsert and idempotency

`roundCode` is the unique Salesforce External ID:

- New Round Code → `INSERTED`.
- Existing Round Code → `UPDATED`.
- Retrying the same logical record with the same Round Code does not create a duplicate.
- Do not create a new Round Code merely to retry a failed transmission.

The API allows record-level partial success. A failed row does not roll back other valid rows.

## Date-window assignment rule

Salesforce does not use `isActive` to select rounds. A round is eligible only when `Start Date <= Today <= End Date`, and its Department and Admission Year match the Lead. Both date boundaries are inclusive.

Historical rounds for different Admission Years remain stored independently. If multiple rounds in the same Department + Admission Year contain today, the round with the latest Start Date wins; latest Last Modified Date and record ID are tie-breakers.

Saving a round that contains today immediately launches the scoped pending-Lead batch. There is no daily scheduler. Future and expired rounds do not launch the batch. When a future round reaches its Start Date, new Leads are evaluated dynamically; existing pending Leads require another round upsert/update or manual batch execution.

## Response contract

| Field | Type | Meaning |
|---|---|---|
| `requestId` | String | Salesforce-generated troubleshooting correlation ID. |
| `success` | Boolean | `true` only when every record succeeded. |
| `totalRecords` | Integer | Records accepted for processing. |
| `successCount` | Integer | Successful records. |
| `failureCount` | Integer | Failed records. |
| `results` | Array | One result per request record. |

Each result contains:

| Field | Type | Meaning |
|---|---|---|
| `index` | Integer | Zero-based request position; envelope errors use `-1`. |
| `roundCode` | String/null | Associated Round Code. |
| `salesforceId` | ID/null | Salesforce record ID after success. |
| `action` | String | `INSERTED`, `UPDATED`, or `FAILED`. |
| `success` | Boolean | Record outcome. |
| `errors` | String array | Exact errors; empty on success. |

### HTTP 200 example

```json
{
  "requestId": "AR-20261019094530123-A1B2C3D4",
  "success": true,
  "totalRecords": 1,
  "successCount": 1,
  "failureCount": 0,
  "results": [
    {
      "index": 0,
      "roundCode": "MBA-2027-R1",
      "salesforceId": "a00XXXXXXXXXXXXXXX",
      "action": "INSERTED",
      "success": true,
      "errors": []
    }
  ]
}
```

JSON property order is not guaranteed; parse by property name.

### HTTP 207 partial-success example

Always inspect every result when HTTP `207 Multi-Status` is returned.

```json
{
  "requestId": "AR-20261019094600123-B1C2D3E4",
  "success": false,
  "totalRecords": 2,
  "successCount": 1,
  "failureCount": 1,
  "results": [
    {
      "index": 0,
      "roundCode": "MBA-2027-R2",
      "salesforceId": "a00XXXXXXXXXXXXXXX",
      "action": "INSERTED",
      "success": true,
      "errors": []
    },
    {
      "index": 1,
      "roundCode": "MBA-INVALID",
      "salesforceId": null,
      "action": "FAILED",
      "success": false,
      "errors": ["startDate must use YYYY-MM-DD format and be a valid date."]
    }
  ]
}
```

### HTTP 400 envelope-error example

```json
{
  "requestId": "AR-20261019094700123-C1D2E3F4",
  "success": false,
  "totalRecords": 0,
  "successCount": 0,
  "failureCount": 1,
  "results": [
    {
      "index": -1,
      "roundCode": null,
      "salesforceId": null,
      "action": "FAILED",
      "success": false,
      "errors": ["records must contain at least one admission round."]
    }
  ]
}
```

## Status codes

| Status | Meaning | Action |
|---|---|---|
| `200` | All records succeeded. | Store IDs, actions, and `requestId`. |
| `207` | One or more record failures. | Keep successes; inspect and correct failed items. |
| `400` | Invalid request/contract/configuration or safely surfaced enforcement error. | Correct it; do not retry unchanged validation errors. |
| `401` | Missing, invalid, or expired OAuth token. | Refresh/reacquire the token. |
| `403` | Insufficient permission or Connected App/org restriction. | Contact Salesforce administration. |
| `500` | Unexpected Salesforce failure. | Retain `requestId`; retry transient failures with capped backoff. |

## Exact validation messages

```text
Request body is required.
records must contain at least one admission round.
A maximum of 200 admission rounds is allowed per request.
Record must not be null.
roundCode is required.
roundCode must not exceed 50 characters.
roundCode occurs more than once in this request.
roundName is required when creating a new admission round.
roundName must not exceed 80 characters.
program must not exceed 255 characters.
department must be one of: CLeF, Career Development Centre, Executive Education, Graduation, Masters, Phd, Undergraduation.
department is required.
admissionYear is required.
startDate is required.
endDate is required.
startDate must use YYYY-MM-DD format and be a valid date.
endDate must use YYYY-MM-DD format and be a valid date.
startDate must be on or before endDate.
```

Salesforce DML failures also include Salesforce status codes, messages, and field names when available.

## cURL example

```bash
curl --request POST \
  "${SF_INSTANCE_URL}/services/apexrest/v1/admission-rounds/upsert" \
  --header "Authorization: Bearer ${SF_ACCESS_TOKEN}" \
  --header "Content-Type: application/json" \
  --header "Accept: application/json" \
  --data '{
    "records": [{
      "roundCode": "MBA-2027-R1",
      "roundName": "MBA Admission Round 1",
      "admissionYear": "Admission Year - 2027",
      "department": "Masters",
      "program": "MBA",
      "startDate": "2027-01-01",
      "endDate": "2027-03-31"
    }]
  }'
```

## Retry rules

- Preserve `roundCode` as the idempotency key.
- For `207`, retry only failed records after correcting retryable causes.
- Do not retry unchanged `400` validation errors.
- Refresh OAuth after `401`.
- For network failures or transient `500` responses, use exponential backoff capped at three retries.
- Retain the Salesforce `requestId` and your external correlation ID. A caller-supplied correlation header is not currently part of this API contract.

## Salesforce failure logging

Failures are written to `API_Log__c`:

| Field | Value |
|---|---|
| `Log_Name__c` | `AdmissionRoundUpsert` |
| `Apex_Class_Name__c` | `AdmissionRoundRestResource` |
| `Response__c` | Sanitized/truncated error text |
| `Log_Type__c` | `Failed` |
| `Registration_Number__c` | Round Code |

The request payload is not stored. Never place OAuth credentials or sensitive personal data in Admission Round fields or integration logs.

## UAT verification

1. Authenticate with the approved Connected App principal.
2. Insert a unique Round Code; expect `200` and `INSERTED`.
3. Update the same Round Code; expect `UPDATED` and the same Salesforce ID.
4. Confirm Salesforce contains only one record for that Round Code.
5. Send a round containing today and confirm matching pending Leads are assigned by the batch.
6. Confirm future and expired rounds are not assigned; confirm overlapping current rounds select the latest Start Date.
7. Test missing/invalid Department, Admission Year, Start Date, and End Date values.
8. Confirm failed results are recorded in `API_Log__c`.
9. Confirm the client handles `207` per record.
10. Retain evidence and obtain business acceptance before Production deployment.

## Deployment references

### UAT

| Change | Deployment ID | Result |
|---|---|---|
| Admission Round object, API, access, and Department | `0Afft000000NbLRCA0` | Succeeded |
| Single-active-round API enforcement | `0Afft000000NpmbCAC` | Succeeded |

Latest independent related UAT test run: `707ft000003jh7B` — 100% pass rate and 85% test-run coverage.

Date-window UAT validation: `0Afft000000OGjZCAW` — 10/10 components compiled and 34/34 specified tests passed. This was validation-only and did not commit metadata.

### Production

| Change | Deployment ID | Result |
|---|---|---|
| Admission Round object, API, Lead lookup, assignment automation, layout, and access | `0Affv000000zDLJCA2` | Succeeded |

Production post-deployment test run: `707fv00001ZaGRk` — 42/42 specified tests passed. This reference covers the existing Active-based version. The date-window revision remains pending UAT deployment and subsequent Production approval.

## Incident information

Provide these details without secrets:

- Environment
- UTC timestamp
- Salesforce `requestId`
- HTTP status
- Affected `roundCode`
- Sanitized request fields
- Full response body
- Retry timestamps and results

Never share access tokens, secrets, passwords, or private keys.
