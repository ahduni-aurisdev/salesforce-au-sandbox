/**
 * @description Validates Task requests received through the partner API and creates each Task on the
 *              Account (converted Lead or Account ID) or on the Lead itself (unconverted Lead ID).
 * @author AU Development Team
 * @date 2026-10-23
 * @version 1.2
 * @lastModified 2026-10-26
 */
// System mode is intentional: the partner API runs as a Salesforce Integration license user,
// and that license cannot hold the Edit Tasks permission or Lead/Account/Contact access.
// Access is controlled by Apex class access on TaskActivityRestResource and by the input
// validation below; the response returns only IDs, never Lead/Account/Contact data.
public without sharing class TaskActivityService {
    private static final Integer MAX_RECORDS = 200;
    private static final Integer MAX_SUBJECT_LENGTH = 255;
    private static final Integer MAX_COMMENTS_LENGTH = 32000;
    private static final Integer MAX_LOG_MESSAGE_LENGTH = 255;
    private static final String LOG_NAME = 'TaskActivityCreate';
    private static final String CLASS_NAME = 'TaskActivityRestResource';
    private static final String ACTION_CREATED = 'CREATED';
    private static final String ACTION_FAILED = 'FAILED';
    private static final String STATUS_COMPLETED = 'Completed';
    private static final String STATUS_IN_PROGRESS = 'In Progress';
    private static final String PRIORITY_NORMAL = 'Normal';
    @TestVisible
    private static final String TARGET_LEAD = 'LEAD';
    @TestVisible
    private static final String TARGET_ACCOUNT = 'ACCOUNT';
    @TestVisible
    private static final String TARGET_CONVERTED_LEAD_ACCOUNT = 'CONVERTED_LEAD_ACCOUNT';

    public class TaskActivityApiException extends Exception {
    }

    private class TaskTarget {
        String targetType;
        Id whoId;
        Id whatId;
        Id ownerId;
    }

    public static TaskActivityApiModels.ResponseEnvelope process(
        TaskActivityApiModels.RequestEnvelope requestEnvelope,
        String requestId
    ) {
        validateEnvelope(requestEnvelope);

        TaskActivityApiModels.ResponseEnvelope response = new TaskActivityApiModels.ResponseEnvelope();
        response.requestId = requestId;
        response.totalRecords = requestEnvelope.records.size();
        response.successCount = 0;
        response.failureCount = 0;

        Map<Integer, Id> parsedIdsByIndex = new Map<Integer, Id>();
        Map<Integer, Date> dueDatesByIndex = new Map<Integer, Date>();
        Set<Id> leadIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();

        for (Integer index = 0; index < requestEnvelope.records.size(); index++) {
            TaskActivityApiModels.TaskRequest input = requestEnvelope.records[index];
            TaskActivityApiModels.RecordResult result = newResult(index, input);
            response.results.add(result);

            Id recordId = validateInput(input, result.errors);
            Date dueDate = input == null ? null : parseDate(input.dueDate, 'dueDate', result.errors);
            if (!result.errors.isEmpty()) {
                markFailure(result, response);
                continue;
            }
            parsedIdsByIndex.put(index, recordId);
            dueDatesByIndex.put(index, dueDate);
            if (recordId.getSobjectType() == Lead.SObjectType) {
                leadIds.add(recordId);
            } else {
                accountIds.add(recordId);
            }
        }

        Map<Id, Lead> leadsById = TaskActivitySelector.selectLeadsByIds(leadIds);
        Map<Id, Account> accountsById = TaskActivitySelector.selectAccountsByIds(accountIds);

        Map<Integer, TaskTarget> targetsByIndex = new Map<Integer, TaskTarget>();
        Set<Id> ownerIds = new Set<Id>();
        for (Integer index : parsedIdsByIndex.keySet()) {
            TaskActivityApiModels.RecordResult result = response.results[index];
            TaskTarget target = resolveTarget(parsedIdsByIndex.get(index), leadsById, accountsById, result.errors);
            if (target == null) {
                markFailure(result, response);
                continue;
            }
            targetsByIndex.put(index, target);
            if (target.ownerId != null) {
                ownerIds.add(target.ownerId);
            }
        }

        Set<Id> activeOwnerIds = TaskActivitySelector.selectActiveUserIds(ownerIds);
        List<Task> tasksToInsert = new List<Task>();
        List<Integer> dmlIndexes = new List<Integer>();
        for (Integer index : targetsByIndex.keySet()) {
            TaskTarget target = targetsByIndex.get(index);
            Task taskValue = mapTask(
                requestEnvelope.records[index],
                dueDatesByIndex.get(index),
                target,
                activeOwnerIds
            );
            TaskActivityApiModels.RecordResult result = response.results[index];
            result.targetType = target.targetType;
            result.relatedToId = target.whatId != null ? target.whatId : target.whoId;
            result.taskStatus = taskValue.Status;
            tasksToInsert.add(taskValue);
            dmlIndexes.add(index);
        }

        if (!tasksToInsert.isEmpty()) {
            Database.SaveResult[] dmlResults = Database.insert(tasksToInsert, false);
            applyDmlResults(dmlResults, dmlIndexes, response);
        }

        response.success = response.failureCount == 0;
        logFailures(response);
        return response;
    }

    public static void logUnexpectedFailure(String requestId, String message) {
        TaskActivityApiModels.ResponseEnvelope response = new TaskActivityApiModels.ResponseEnvelope();
        response.requestId = requestId;
        TaskActivityApiModels.RecordResult result = new TaskActivityApiModels.RecordResult();
        result.index = -1;
        result.recordId = requestId;
        result.success = false;
        result.action = ACTION_FAILED;
        result.errors.add(message);
        response.results.add(result);
        logFailures(response);
    }

    private static void validateEnvelope(TaskActivityApiModels.RequestEnvelope requestEnvelope) {
        if (requestEnvelope == null || requestEnvelope.records == null || requestEnvelope.records.isEmpty()) {
            throw new TaskActivityApiException('records must contain at least one task.');
        }
        if (requestEnvelope.records.size() > MAX_RECORDS) {
            throw new TaskActivityApiException('A maximum of 200 tasks is allowed per request.');
        }
    }

    private static Id validateInput(TaskActivityApiModels.TaskRequest input, List<String> errors) {
        if (input == null) {
            errors.add('Record must not be null.');
            return null;
        }
        if (String.isBlank(input.subject)) {
            errors.add('subject is required.');
        } else if (input.subject.trim().length() > MAX_SUBJECT_LENGTH) {
            errors.add('subject must not exceed 255 characters.');
        }
        if (input.comments != null && input.comments.length() > MAX_COMMENTS_LENGTH) {
            errors.add('comments must not exceed 32000 characters.');
        }
        return parseRecordId(input.recordId, errors);
    }

    private static Id parseRecordId(String value, List<String> errors) {
        if (String.isBlank(value)) {
            errors.add('recordId is required.');
            return null;
        }
        Id recordId;
        Schema.SObjectType objectType;
        try {
            recordId = Id.valueOf(value.trim());
            objectType = recordId.getSobjectType();
        } catch (StringException exceptionValue) {
            errors.add('recordId must be a valid 15 or 18 character Salesforce ID.');
            return null;
        } catch (SObjectException exceptionValue) {
            errors.add('recordId must reference a Lead or an Account.');
            return null;
        }
        if (objectType != Lead.SObjectType && objectType != Account.SObjectType) {
            errors.add('recordId must reference a Lead or an Account.');
            return null;
        }
        return recordId;
    }

    private static Date parseDate(String value, String fieldName, List<String> errors) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Date.valueOf(value.trim());
        } catch (TypeException exceptionValue) {
            errors.add(fieldName + ' must use YYYY-MM-DD format and be a valid date.');
            return null;
        }
    }

    private static TaskTarget resolveTarget(
        Id recordId,
        Map<Id, Lead> leadsById,
        Map<Id, Account> accountsById,
        List<String> errors
    ) {
        TaskTarget target = new TaskTarget();
        if (recordId.getSobjectType() == Account.SObjectType) {
            Account accountValue = accountsById.get(recordId);
            if (accountValue == null) {
                errors.add('No Account found for recordId.');
                return null;
            }
            target.targetType = TARGET_ACCOUNT;
            target.whatId = accountValue.Id;
            target.ownerId = accountValue.OwnerId;
            return target;
        }

        Lead leadValue = leadsById.get(recordId);
        if (leadValue == null) {
            errors.add('No Lead found for recordId.');
            return null;
        }
        if (!leadValue.IsConverted) {
            target.targetType = TARGET_LEAD;
            target.whoId = leadValue.Id;
            target.ownerId = leadValue.OwnerId;
            return target;
        }
        if (leadValue.ConvertedAccountId == null) {
            errors.add('The Lead is converted but has no converted Account to receive the task.');
            return null;
        }
        target.targetType = TARGET_CONVERTED_LEAD_ACCOUNT;
        target.whatId = leadValue.ConvertedAccountId;
        target.whoId = leadValue.ConvertedContactId;
        target.ownerId = leadValue.ConvertedAccount?.OwnerId;
        return target;
    }

    private static Task mapTask(
        TaskActivityApiModels.TaskRequest input,
        Date dueDate,
        TaskTarget target,
        Set<Id> activeOwnerIds
    ) {
        // A Lead owned by a queue, or a record owned by an inactive user, cannot own a Task;
        // the integration user owns the Task instead so the activity is never lost.
        Id ownerId = activeOwnerIds.contains(target.ownerId) ? target.ownerId : UserInfo.getUserId();
        return new Task(
            Subject = input.subject.trim(),
            ActivityDate = dueDate,
            Description = input.comments,
            Status = dueDate != null && dueDate <= Date.today() ? STATUS_COMPLETED : STATUS_IN_PROGRESS,
            Priority = PRIORITY_NORMAL,
            OwnerId = ownerId,
            WhoId = target.whoId,
            WhatId = target.whatId
        );
    }

    private static void applyDmlResults(
        Database.SaveResult[] dmlResults,
        List<Integer> dmlIndexes,
        TaskActivityApiModels.ResponseEnvelope response
    ) {
        for (Integer index = 0; index < dmlResults.size(); index++) {
            Database.SaveResult dmlResult = dmlResults[index];
            TaskActivityApiModels.RecordResult result = response.results[dmlIndexes[index]];
            if (dmlResult.isSuccess()) {
                result.success = true;
                result.taskId = dmlResult.getId();
                result.action = ACTION_CREATED;
                response.successCount++;
            } else {
                for (Database.Error errorValue : dmlResult.getErrors()) {
                    result.errors.add(formatDatabaseError(errorValue));
                }
                markFailure(result, response);
            }
        }
    }

    private static String formatDatabaseError(Database.Error errorValue) {
        String message = String.valueOf(errorValue.getStatusCode()) + ': ' + errorValue.getMessage();
        if (errorValue.getFields() != null && !errorValue.getFields().isEmpty()) {
            message += ' Fields: ' + String.join(errorValue.getFields(), ', ');
        }
        return message;
    }

    private static TaskActivityApiModels.RecordResult newResult(
        Integer index,
        TaskActivityApiModels.TaskRequest input
    ) {
        TaskActivityApiModels.RecordResult result = new TaskActivityApiModels.RecordResult();
        result.index = index;
        result.recordId = input == null ? null : input.recordId;
        result.success = false;
        return result;
    }

    private static void markFailure(
        TaskActivityApiModels.RecordResult result,
        TaskActivityApiModels.ResponseEnvelope response
    ) {
        result.success = false;
        result.action = ACTION_FAILED;
        response.failureCount++;
    }

    private static void logFailures(TaskActivityApiModels.ResponseEnvelope response) {
        if (!Schema.sObjectType.API_Log__c.isCreateable()) {
            return;
        }
        List<API_Log__c> logs = new List<API_Log__c>();
        for (TaskActivityApiModels.RecordResult result : response.results) {
            if (!result.success) {
                String errorText = String.join(result.errors, ' | ');
                logs.add(new API_Log__c(
                    Log_Name__c = LOG_NAME,
                    Apex_Class_Name__c = CLASS_NAME,
                    Response__c = truncate(errorText, MAX_LOG_MESSAGE_LENGTH),
                    Log_Type__c = 'Failed',
                    Registration_Number__c = truncate(result.recordId, 50)
                ));
            }
        }
        if (!logs.isEmpty()) {
            SObjectAccessDecision accessDecision = Security.stripInaccessible(AccessType.CREATABLE, logs);
            Database.insert(accessDecision.getRecords(), false);
        }
    }

    private static String truncate(String value, Integer maxLength) {
        if (value == null || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }
}