# Task Activity API — Integration Guide

## Document control

| Item | Value |
|---|---|
| System | Ahmedabad University Salesforce |
| API | Task Activity Create API |
| Version | `v1` |
| Environments | UAT sandbox and Production — both live |
| Last updated | 2026-10-23 |
| Audience | External integration developers, QA, and Salesforce support |

## Purpose

This authenticated REST API creates follow-up activities (Salesforce Tasks) against a Lead or an Account. Send the Salesforce ID of the Lead or Account you have, plus a subject, an optional due date, and optional comments. Salesforce decides where the Task belongs:

| `recordId` you send | Where the Task is created | Task owner |
|---|---|---|
| Lead that has **not** been converted | On the Lead | Lead owner |
| Lead that **has** been converted | On the Account the Lead was converted into (also linked to the converted Contact) | Account owner |
| Account | On the Account | Account owner |
| Any other ID (Contact, Opportunity, etc.) | Rejected with an error | — |

If the owner is a queue or an inactive user, the integration user owns the Task instead.

The API supports bulk requests (1–200 Tasks per call) with record-level partial success.

## Environment endpoints

### UAT sandbox

```text
Base URL: https://ahmedabaduniversity2--hlisuat.sandbox.my.salesforce.com
Method: POST
Path: /services/apexrest/v1/activities/tasks
Full endpoint: https://ahmedabaduniversity2--hlisuat.sandbox.my.salesforce.com/services/apexrest/v1/activities/tasks
```

### Production

```text
Base URL: https://ahmedabaduniversity2.my.salesforce.com
Method: POST
Path: /services/apexrest/v1/activities/tasks
Full endpoint: https://ahmedabaduniversity2.my.salesforce.com/services/apexrest/v1/activities/tasks
```

Always use the `instance_url` returned by Salesforce OAuth instead of hardcoding either base URL. Never send UAT credentials, UAT record IDs, or test payloads to Production — Salesforce IDs differ between environments.

## Authentication

The endpoint uses the same Salesforce Connected App and OAuth 2.0 setup as the existing Admission Round API. Anonymous access and username/password headers are not supported.

Obtain these securely from the Connected App owner (if you do not already have them):

- OAuth client/consumer ID
- Approved OAuth flow and token endpoint
- Client secret or certificate when required
- Integration username/principal
- Token-refresh procedure

```text
UAT token host:        https://test.salesforce.com/services/oauth2/token
Production token host: https://login.salesforce.com/services/oauth2/token
```

Access tokens are environment-specific. Never store client secrets, private keys, passwords, or access tokens in source control, tickets, email, or this document.

The API user must have the `Salesforce API Only System Integrations` profile (already granted access to this API in both environments).

### Request headers

```http
Authorization: Bearer <salesforce_access_token>
Content-Type: application/json
Accept: application/json
```

## Request contract

```json
{
  "records": [
    {
      "recordId": "<Lead or Account Salesforce ID>",
      "subject": "<text>",
      "dueDate": "<YYYY-MM-DD>",
      "comments": "<text>"
    }
  ]
}
```

### Fields

| Field | Type | Required | Rules |
|---|---|---|---|
| `records` | Array | Yes | 1–200 items |
| `recordId` | String | Yes | 15 or 18 character Salesforce ID of a **Lead** or **Account** |
| `subject` | String | Yes | Max 255 characters; leading/trailing spaces are trimmed |
| `dueDate` | String | No | `YYYY-MM-DD`; omit or send `null` for no due date |
| `comments` | String | No | Max 32,000 characters; stored as the Task comments |

Unknown fields are ignored. `status` and `priority` are **not** accepted — Salesforce sets them as described below.

### Status and priority rules

| `dueDate` | Task status |
|---|---|
| Before today (in the past) | `Completed` |
| Today | `In Progress` |
| In the future | `In Progress` |
| Not sent / `null` | `In Progress` |

"Today" is evaluated on the Salesforce server date at the time of the request. Priority is always `Normal`.

## Payload variations

All IDs below are illustrative examples — replace them with real IDs from the target environment.

### 1. Minimum payload — subject only (no due date, no comments)

```json
{
  "records": [
    {
      "recordId": "00Q5g00000AbCdEEAX",
      "subject": "Call back requested"
    }
  ]
}
```

Result: Task on the Lead (or its converted Account), status `In Progress`, no due date.

### 2. Lead with a future due date and comments

```json
{
  "records": [
    {
      "recordId": "00Q5g00000AbCdEEAX",
      "subject": "Follow-up call",
      "dueDate": "2026-11-05",
      "comments": "Student asked about scholarship options. Call after 4 PM."
    }
  ]
}
```

Result: if the Lead is not converted, Task on the Lead owned by the Lead owner; if the Lead is converted, Task on the converted Account owned by the Account owner. Status `In Progress`.

### 3. Account with a past due date (logging an activity that already happened)

```json
{
  "records": [
    {
      "recordId": "0015g00000XyZ12AAB",
      "subject": "Campus visit completed",
      "dueDate": "2026-10-15",
      "comments": "Parent and student attended the campus tour."
    }
  ]
}
```

Result: Task on the Account owned by the Account owner, status `Completed`.

### 4. Batch — several Tasks in one call (recommended for volume)

```json
{
  "records": [
    {
      "recordId": "00Q5g00000AbCdEEAX",
      "subject": "Send brochure",
      "dueDate": "2026-11-01"
    },
    {
      "recordId": "00Q5g00000AbCdFEAX",
      "subject": "Document verification call",
      "comments": "Pending 12th mark sheet."
    },
    {
      "recordId": "0015g00000XyZ12AAB",
      "subject": "Fee discussion",
      "dueDate": "2026-10-20",
      "comments": "Discussed instalment plan."
    }
  ]
}
```

Each record is processed independently. Results are returned in the same order, identified by `index` (0-based position in `records`).

## Response contract

| Field | Description |
|---|---|
| `requestId` | Salesforce-generated ID for this call (format `TA-<timestamp>-<suffix>`). Keep it for support. |
| `success` | `true` only when every record succeeded |
| `totalRecords` / `successCount` / `failureCount` | Counts for the request |
| `results[]` | One entry per request record |
| `results[].index` | Position of the record in your request (0-based); `-1` for request-level errors |
| `results[].recordId` | The `recordId` exactly as you sent it |
| `results[].targetType` | `LEAD`, `ACCOUNT`, or `CONVERTED_LEAD_ACCOUNT` |
| `results[].relatedToId` | Salesforce ID of the Lead or Account the Task was created on |
| `results[].taskId` | Salesforce ID of the new Task (`null` on failure) |
| `results[].taskStatus` | `In Progress` or `Completed` |
| `results[].action` | `CREATED` or `FAILED` |
| `results[].success` | Per-record result |
| `results[].errors` | Validation or Salesforce error messages for that record |

### HTTP 200 example — all records succeeded

```json
{
  "requestId": "TA-20261023101500123-1a2b3c4d",
  "success": true,
  "totalRecords": 2,
  "successCount": 2,
  "failureCount": 0,
  "results": [
    {
      "index": 0,
      "recordId": "00Q5g00000AbCdEEAX",
      "targetType": "CONVERTED_LEAD_ACCOUNT",
      "relatedToId": "0015g00000XyZ99AAB",
      "taskId": "00T5g00000Qw3rTEAR",
      "taskStatus": "In Progress",
      "action": "CREATED",
      "success": true,
      "errors": []
    },
    {
      "index": 1,
      "recordId": "0015g00000XyZ12AAB",
      "targetType": "ACCOUNT",
      "relatedToId": "0015g00000XyZ12AAB",
      "taskId": "00T5g00000Qw3rUEAR",
      "taskStatus": "Completed",
      "action": "CREATED",
      "success": true,
      "errors": []
    }
  ]
}
```

### HTTP 207 example — partial success

```json
{
  "requestId": "TA-20261023101612456-5e6f7a8b",
  "success": false,
  "totalRecords": 2,
  "successCount": 1,
  "failureCount": 1,
  "results": [
    {
      "index": 0,
      "recordId": "00Q5g00000AbCdFEAX",
      "targetType": "LEAD",
      "relatedToId": "00Q5g00000AbCdFEAX",
      "taskId": "00T5g00000Qw3rVEAR",
      "taskStatus": "In Progress",
      "action": "CREATED",
      "success": true,
      "errors": []
    },
    {
      "index": 1,
      "recordId": "0035g00000Mn0PqAAB",
      "targetType": null,
      "relatedToId": null,
      "taskId": null,
      "taskStatus": null,
      "action": "FAILED",
      "success": false,
      "errors": ["recordId must reference a Lead or an Account."]
    }
  ]
}
```

Successful records in a `207` response are already saved — do not resend them.

### HTTP 400 example — request-level error

```json
{
  "requestId": "TA-20261023101733789-9c0d1e2f",
  "success": false,
  "totalRecords": 0,
  "successCount": 0,
  "failureCount": 1,
  "results": [
    {
      "index": -1,
      "recordId": null,
      "targetType": null,
      "relatedToId": null,
      "taskId": null,
      "taskStatus": null,
      "action": "FAILED",
      "success": false,
      "errors": ["records must contain at least one task."]
    }
  ]
}
```

Nothing is saved when a `400` is returned.

## Status codes

| Status | Meaning | Action |
|---|---|---|
| `200` | All records succeeded. | Store `taskId` values and `requestId`. |
| `207` | One or more records failed; others may have succeeded. | Keep successes; correct and resend only the failed records. |
| `400` | Invalid JSON, empty body, empty `records`, or more than 200 records. Nothing saved. | Fix the request; do not retry unchanged. |
| `401` | Missing, invalid, or expired OAuth token. | Refresh/reacquire the token. |
| `403` | The user is not permitted to call this API. | Contact Salesforce administration. |
| `500` | Unexpected Salesforce failure. | Keep `requestId`; see retry rules below. |

## Exact validation messages

Request-level (HTTP 400):

```text
Request body is required.
Invalid JSON payload: <parser detail>
records must contain at least one task.
A maximum of 200 tasks is allowed per request.
```

Record-level (HTTP 207, in `results[].errors`):

```text
Record must not be null.
recordId is required.
recordId must be a valid 15 or 18 character Salesforce ID.
recordId must reference a Lead or an Account.
No Lead found for recordId.
No Account found for recordId.
The Lead is converted but has no converted Account to receive the task.
subject is required.
subject must not exceed 255 characters.
comments must not exceed 32000 characters.
dueDate must use YYYY-MM-DD format and be a valid date.
```

Salesforce save failures are returned as `<STATUS_CODE>: <message>` with field names when available.

## cURL examples

### UAT

```bash
curl --request POST \
  "https://ahmedabaduniversity2--hlisuat.sandbox.my.salesforce.com/services/apexrest/v1/activities/tasks" \
  --header "Authorization: Bearer ${SF_ACCESS_TOKEN}" \
  --header "Content-Type: application/json" \
  --header "Accept: application/json" \
  --data '{
    "records": [{
      "recordId": "00Q5g00000AbCdEEAX",
      "subject": "Follow-up call",
      "dueDate": "2026-11-05",
      "comments": "Created from UAT integration test"
    }]
  }'
```

### Production

```bash
curl --request POST \
  "https://ahmedabaduniversity2.my.salesforce.com/services/apexrest/v1/activities/tasks" \
  --header "Authorization: Bearer ${SF_ACCESS_TOKEN}" \
  --header "Content-Type: application/json" \
  --header "Accept: application/json" \
  --data '{
    "records": [{
      "recordId": "<Production Lead or Account ID>",
      "subject": "Follow-up call",
      "dueDate": "2026-11-05"
    }]
  }'
```

## Retry rules

**This API is not idempotent:** every successful call creates a new Task. Sending the same record twice creates two Tasks.

- For `207`, resend **only** the failed records after correcting them — never the whole batch.
- Do not retry unchanged `400` responses or record-level validation errors.
- Refresh OAuth after `401`, then resend.
- For `500` or a network timeout where no response was received, check with the Salesforce team (using the `requestId` or timestamp) before resending, or accept that a duplicate Task may be created. If you retry automatically, use exponential backoff capped at three retries.
- Keep the Salesforce `requestId` and your own correlation ID for every call.

## Salesforce failure logging

Failed records are logged in Salesforce (`API_Log__c`, log name `TaskActivityCreate`) with the `recordId` and error text. Request payloads, including comments, are not stored in the log. Do not place credentials or unnecessary personal data in `subject` or `comments`.

## UAT verification checklist

1. Authenticate with the approved Connected App principal against UAT.
2. Send an unconverted Lead ID with no `dueDate` — expect `200`, `targetType` `LEAD`, `taskStatus` `In Progress`.
3. Send a converted Lead ID — expect `targetType` `CONVERTED_LEAD_ACCOUNT` and `relatedToId` equal to the converted Account.
4. Send an Account ID with a past `dueDate` — expect `targetType` `ACCOUNT`, `taskStatus` `Completed`.
5. Send a Contact or Opportunity ID — expect `207` with `recordId must reference a Lead or an Account.`
6. Send `dueDate` in a wrong format (e.g. `30-10-2026`) — expect the `YYYY-MM-DD` error.
7. Send a batch mixing valid and invalid records — confirm your client handles `207` per record using `index`.
8. Send `{"records": []}` — expect `400`.
9. Confirm the created Tasks appear on the expected Lead/Account in Salesforce with the expected owner.
10. Retain evidence and obtain business sign-off before switching to Production.

## Incident information

When raising an issue, provide (without secrets):

- Environment (UAT or Production)
- UTC timestamp
- Salesforce `requestId`
- HTTP status
- Affected `recordId` values and `index`
- Sanitized request body
- Full response body
- Retry timestamps and results

Never share access tokens, secrets, passwords, or private keys.
