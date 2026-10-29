# Task Activity Create API

## Source

- Source: User-provided requirements and decisions in chat
- Author: Project stakeholder
- Date captured: 2026-10-23
- Status: Deployed to `au-uat` (`0Afft000000OUBRCA4`) and `au-prod` (`0Affv000000zPzBCAU`) on 2026-10-23; post-deploy tests 16/16 in both. Pending user business validation.

## Objective

Provide an authenticated Apex REST endpoint that allows the external system to create Task activities in Salesforce against a Lead or an Account. The external system uses the same Connected App and OAuth authentication as the Admission Round API.

## Endpoint

```http
POST /services/apexrest/v1/activities/tasks
Authorization: Bearer <existing OAuth access token>
Content-Type: application/json
```

### Request

The endpoint accepts 1–200 records per request.

```json
{
  "records": [
    {
      "recordId": "00Q5g00000ABCDEEA1",
      "subject": "Follow-up call",
      "dueDate": "2026-10-30",
      "comments": "Discussed scholarship options"
    }
  ]
}
```

| Field | Required | Rules | Salesforce Task field |
|---|---|---|---|
| `recordId` | Yes | 15 or 18 character Lead or Account ID | `WhoId` / `WhatId` (see routing) |
| `subject` | Yes | Max 255 characters, trimmed | `Subject` |
| `dueDate` | No | `YYYY-MM-DD` | `ActivityDate` |
| `comments` | No | Max 32,000 characters | `Description` |

## Confirmed business rules (2026-10-23)

| Decision | Confirmed rule |
|---|---|
| Volume | Batch: 1–200 records per request, partial success allowed |
| Routing — unconverted Lead | Task is created on the Lead (`WhoId` = Lead) |
| Routing — converted Lead | Task is created on the converted Account (`WhatId`) and also names the converted Contact (`WhoId`) |
| Routing — Account ID | Task is created on the Account (`WhatId`) |
| Other object IDs (Contact, Opportunity, etc.) | Rejected with an error |
| Task owner | Account owner for converted Leads and Account IDs; Lead owner for unconverted Leads |
| Owner fallback | If the owner is a queue or an inactive user (neither can own a Task), the integration user owns the Task |
| Status | `Completed` when `dueDate` is today or earlier; otherwise (`dueDate` in future, or blank) `In Progress` |
| Priority | Always `Normal`; status and priority are not accepted in the payload |
| Duplicate protection | Not required — a retried request creates the Task again |

Decision confirmed 2026-10-26: a `dueDate` equal to today is created `Completed` (previously `In Progress`).

## Response behavior

- `200 OK`: all records succeeded.
- `207 Multi-Status`: at least one record failed.
- `400 Bad Request`: invalid JSON, empty body, missing/empty `records`, or more than 200 records.
- `500 Internal Server Error`: unexpected server-side failure.

Each result contains `index`, `recordId`, `targetType` (`LEAD`, `ACCOUNT`, `CONVERTED_LEAD_ACCOUNT`), `relatedToId`, `taskId`, `taskStatus`, `action` (`CREATED` or `FAILED`), `success`, and `errors`.

```json
{
  "requestId": "TA-20261023101500123-1a2b3c4d",
  "success": true,
  "totalRecords": 1,
  "successCount": 1,
  "failureCount": 0,
  "results": [
    {
      "index": 0,
      "recordId": "00Q5g00000ABCDEEA1",
      "targetType": "CONVERTED_LEAD_ACCOUNT",
      "relatedToId": "0015g00000XYZ12AAA",
      "taskId": "00T5g00000QWE34AAA",
      "taskStatus": "In Progress",
      "action": "CREATED",
      "success": true,
      "errors": []
    }
  ]
}
```

### Validation messages

| Condition | Message |
|---|---|
| Null record | `Record must not be null.` |
| Missing `recordId` | `recordId is required.` |
| Malformed ID | `recordId must be a valid 15 or 18 character Salesforce ID.` |
| ID of another object | `recordId must reference a Lead or an Account.` |
| Lead not found | `No Lead found for recordId.` |
| Account not found | `No Account found for recordId.` |
| Converted Lead without Account | `The Lead is converted but has no converted Account to receive the task.` |
| Missing `subject` | `subject is required.` |
| Long `subject` | `subject must not exceed 255 characters.` |
| Long `comments` | `comments must not exceed 32000 characters.` |
| Bad `dueDate` | `dueDate must use YYYY-MM-DD format and be a valid date.` |

## Error logging

Failures are inserted in bulk into `API_Log__c`:

- `Log_Name__c`: `TaskActivityCreate`
- `Apex_Class_Name__c`: `TaskActivityRestResource`
- `Response__c`: error text (truncated to 255)
- `Log_Type__c`: `Failed`
- `Registration_Number__c`: the request `recordId` (or the request ID for unexpected failures)

Payloads (including comments) are not persisted.

## Components

| Component | Purpose |
|---|---|
| `TaskActivityRestResource` | `@RestResource` endpoint, HTTP status mapping |
| `TaskActivityService` | Validation, routing, owner/status rules, bulk insert, logging |
| `TaskActivitySelector` | Lead, Account, and active-User queries (system mode) |
| `TaskActivityApiModels` | Typed request/response contracts |
| `TaskActivityRestResourceTest`, `TaskActivityServiceTest`, `TaskActivityApiModelsTest` | Tests (200-record setup, positive, negative, bulk, exception) |

Governor usage per request: 3 SOQL (Leads, Accounts, active Users), 1 Task insert DML, at most 1 `API_Log__c` insert DML.

## Security and access

Decision (2026-10-23, option 1): the external system calls as a `Salesforce API Only System Integrations` user on the **Salesforce Integration** license. A check-only deployment (`0Afft000000OTfBCAW`) proved the license cannot hold the `EditTask` permission ("The user license doesn't allow the permission: EditTask"), and Account/Contact OWD is Private. The stakeholder chose system mode over granting the integration user Lead/Account/Contact Read + View All.

- `TaskActivityService` and `TaskActivitySelector` run `without sharing` and without CRUD/FLS enforcement; the justification is documented inline. `TaskActivityRestResource` remains `with sharing`.
- Access is controlled by Apex class access: `TaskActivityRestResource` is granted only to the `Admin` and `Salesforce API Only System Integrations` profiles. No object permissions are added to the integration profile.
- The API reads only record IDs, conversion links, and owner IDs, and returns only IDs — no Lead/Account/Contact data is exposed to the caller.
- Accepted trade-off: the API creates a Task on any valid Lead or Account ID it receives, regardless of the caller's sharing.
- `TaskActivityServiceTest.shouldCreateTasksAsIntegrationUserWithoutRecordAccess` proves creation works as an integration-profile user with no record access.

## Impact analysis

- Additive only: no existing class, trigger, flow, or field is modified. No breaking change to the Admission Round API.
- Task inserts fire existing Task automation, including NPSP managed-package triggers, and Lead/Account activity rollups.
- Rollback: remove profile class access or deactivate the integration call; the new classes can be removed with a destructive deployment (requires separate `YES-DELETE` approval).
