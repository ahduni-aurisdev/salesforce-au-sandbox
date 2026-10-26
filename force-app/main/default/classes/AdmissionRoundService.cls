/**
 * @description Validates and upserts admission rounds received through the partner API.
 * @author AU Development Team
 * @date 2026-10-16
 * @version 1.2
 * @lastModified 2026-10-22
 */
public with sharing class AdmissionRoundService {
    private static final Integer MAX_RECORDS = 200;
    private static final Integer MAX_LOG_MESSAGE_LENGTH = 255;
    private static final String LOG_NAME = 'AdmissionRoundUpsert';
    private static final String CLASS_NAME = 'AdmissionRoundRestResource';
    private static final String ACTION_INSERTED = 'INSERTED';
    private static final String ACTION_UPDATED = 'UPDATED';
    private static final String ACTION_FAILED = 'FAILED';
    private static final Set<String> ALLOWED_DEPARTMENTS = new Set<String>{
        'CLeF',
        'Career Development Centre',
        'Executive Education',
        'Graduation',
        'Masters',
        'Phd',
        'Undergraduation'
    };

    public class AdmissionRoundApiException extends Exception {
    }

    public static AdmissionRoundApiModels.ResponseEnvelope process(
        AdmissionRoundApiModels.RequestEnvelope requestEnvelope,
        String requestId
    ) {
        validateEnvelope(requestEnvelope);
        enforceObjectAccess();

        AdmissionRoundApiModels.ResponseEnvelope response = new AdmissionRoundApiModels.ResponseEnvelope();
        response.requestId = requestId;
        response.totalRecords = requestEnvelope.records.size();
        response.successCount = 0;
        response.failureCount = 0;

        Map<String, Integer> codeCounts = countRoundCodes(requestEnvelope.records);
        List<Integer> candidateIndexes = new List<Integer>();
        Set<String> candidateCodes = new Set<String>();

        for (Integer index = 0; index < requestEnvelope.records.size(); index++) {
            AdmissionRoundApiModels.AdmissionRoundRequest input = requestEnvelope.records[index];
            AdmissionRoundApiModels.RecordResult result = newResult(index, input);
            response.results.add(result);

            validateInput(input, codeCounts, result.errors);
            if (result.errors.isEmpty()) {
                candidateIndexes.add(index);
                candidateCodes.add(input.roundCode.trim());
            } else {
                markFailure(result, response);
            }
        }

        Map<String, Admission_Round__c> existingByCode = queryExisting(candidateCodes);
        List<Admission_Round__c> recordsToUpsert = new List<Admission_Round__c>();
        List<Integer> dmlIndexes = new List<Integer>();
        for (Integer requestIndex : candidateIndexes) {
            AdmissionRoundApiModels.AdmissionRoundRequest input = requestEnvelope.records[requestIndex];
            String normalizedCode = input.roundCode.trim();
            Admission_Round__c existing = existingByCode.get(normalizedCode);

            if (existing == null && String.isBlank(input.roundName)) {
                AdmissionRoundApiModels.RecordResult result = response.results[requestIndex];
                result.errors.add('roundName is required when creating a new admission round.');
                markFailure(result, response);
                continue;
            }

            validateRequiredAssignmentFields(input, existing, response.results[requestIndex].errors);
            if (!response.results[requestIndex].errors.isEmpty()) {
                markFailure(response.results[requestIndex], response);
                continue;
            }

            recordsToUpsert.add(mapRecord(input, existing));
            dmlIndexes.add(requestIndex);
        }

        if (!recordsToUpsert.isEmpty()) {
            SObjectAccessDecision accessDecision = Security.stripInaccessible(
                AccessType.UPSERTABLE,
                recordsToUpsert,
                true
            );
            if (!accessDecision.getRemovedFields().isEmpty()) {
                throw new AdmissionRoundApiException(
                    'The integration user does not have create or edit access to all Admission Round fields.'
                );
            }

            List<Admission_Round__c> accessibleRecords = new List<Admission_Round__c>();
            for (SObject recordValue : accessDecision.getRecords()) {
                accessibleRecords.add((Admission_Round__c) recordValue);
            }

            Database.UpsertResult[] dmlResults = Database.upsert(
                accessibleRecords,
                Admission_Round__c.Fields.Round_Code__c,
                false
            );
            applyDmlResults(dmlResults, dmlIndexes, response);
        }

        response.success = response.failureCount == 0;
        logFailures(response);
        return response;
    }

    public static void logUnexpectedFailure(String requestId, String message) {
        AdmissionRoundApiModels.ResponseEnvelope response = new AdmissionRoundApiModels.ResponseEnvelope();
        response.requestId = requestId;
        AdmissionRoundApiModels.RecordResult result = new AdmissionRoundApiModels.RecordResult();
        result.index = -1;
        result.roundCode = requestId;
        result.success = false;
        result.action = ACTION_FAILED;
        result.errors.add(message);
        response.results.add(result);
        logFailures(response);
    }

    private static void validateEnvelope(AdmissionRoundApiModels.RequestEnvelope requestEnvelope) {
        if (requestEnvelope == null || requestEnvelope.records == null || requestEnvelope.records.isEmpty()) {
            throw new AdmissionRoundApiException('records must contain at least one admission round.');
        }
        if (requestEnvelope.records.size() > MAX_RECORDS) {
            throw new AdmissionRoundApiException('A maximum of 200 admission rounds is allowed per request.');
        }
    }

    private static void enforceObjectAccess() {
        if (!Schema.sObjectType.Admission_Round__c.isCreateable()
            || !Schema.sObjectType.Admission_Round__c.isUpdateable()) {
            throw new AdmissionRoundApiException(
                'The integration user requires create and edit access to Admission Round.'
            );
        }
    }

    private static Map<String, Integer> countRoundCodes(
        List<AdmissionRoundApiModels.AdmissionRoundRequest> inputs
    ) {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (AdmissionRoundApiModels.AdmissionRoundRequest input : inputs) {
            if (input != null && String.isNotBlank(input.roundCode)) {
                String code = input.roundCode.trim();
                counts.put(code, counts.containsKey(code) ? counts.get(code) + 1 : 1);
            }
        }
        return counts;
    }

    private static void validateInput(
        AdmissionRoundApiModels.AdmissionRoundRequest input,
        Map<String, Integer> codeCounts,
        List<String> errors
    ) {
        if (input == null) {
            errors.add('Record must not be null.');
            return;
        }
        if (String.isBlank(input.roundCode)) {
            errors.add('roundCode is required.');
        } else {
            String code = input.roundCode.trim();
            if (code.length() > 50) {
                errors.add('roundCode must not exceed 50 characters.');
            }
            if (codeCounts.get(code) > 1) {
                errors.add('roundCode occurs more than once in this request.');
            }
        }
        if (input.roundName != null && input.roundName.length() > 80) {
            errors.add('roundName must not exceed 80 characters.');
        }
        if (input.program != null && input.program.length() > 255) {
            errors.add('program must not exceed 255 characters.');
        }
        if (String.isNotBlank(input.department) && !ALLOWED_DEPARTMENTS.contains(input.department.trim())) {
            errors.add(
                'department must be one of: CLeF, Career Development Centre, Executive Education, ' +
                'Graduation, Masters, Phd, Undergraduation.'
            );
        }

        Date startDate = parseDate(input.startDate, 'startDate', errors);
        Date endDate = parseDate(input.endDate, 'endDate', errors);
        if (startDate != null && endDate != null && startDate > endDate) {
            errors.add('startDate must be on or before endDate.');
        }
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

    private static Map<String, Admission_Round__c> queryExisting(Set<String> codes) {
        Map<String, Admission_Round__c> existingByCode = new Map<String, Admission_Round__c>();
        if (codes.isEmpty()) {
            return existingByCode;
        }
        for (Admission_Round__c recordValue : [
            SELECT Id, Round_Code__c, Admission_Year__c, Department__c, Start_Date__c, End_Date__c
            FROM Admission_Round__c
            WHERE Round_Code__c IN :codes
            WITH SECURITY_ENFORCED
        ]) {
            existingByCode.put(recordValue.Round_Code__c, recordValue);
        }
        return existingByCode;
    }

    private static void validateRequiredAssignmentFields(
        AdmissionRoundApiModels.AdmissionRoundRequest input,
        Admission_Round__c existing,
        List<String> errors
    ) {
        Date startDate = effectiveStartDate(input, existing);
        Date endDate = effectiveEndDate(input, existing);
        if (String.isBlank(effectiveDepartment(input, existing))) {
            errors.add('department is required.');
        }
        if (String.isBlank(effectiveAdmissionYear(input, existing))) {
            errors.add('admissionYear is required.');
        }
        if (startDate == null) {
            errors.add('startDate is required.');
        }
        if (endDate == null) {
            errors.add('endDate is required.');
        }
        if (startDate != null && endDate != null && startDate > endDate) {
            errors.add('startDate must be on or before endDate.');
        }
    }

    private static String effectiveDepartment(
        AdmissionRoundApiModels.AdmissionRoundRequest input,
        Admission_Round__c existing
    ) {
        return input.department != null
            ? input.department.trim()
            : (existing == null ? null : existing.Department__c);
    }

    private static String effectiveAdmissionYear(
        AdmissionRoundApiModels.AdmissionRoundRequest input,
        Admission_Round__c existing
    ) {
        return input.admissionYear != null
            ? input.admissionYear.trim()
            : (existing == null ? null : existing.Admission_Year__c);
    }

    private static Date effectiveStartDate(
        AdmissionRoundApiModels.AdmissionRoundRequest input,
        Admission_Round__c existing
    ) {
        if (String.isNotBlank(input.startDate)) return Date.valueOf(input.startDate.trim());
        return existing == null ? null : existing.Start_Date__c;
    }

    private static Date effectiveEndDate(
        AdmissionRoundApiModels.AdmissionRoundRequest input,
        Admission_Round__c existing
    ) {
        if (String.isNotBlank(input.endDate)) return Date.valueOf(input.endDate.trim());
        return existing == null ? null : existing.End_Date__c;
    }

    private static Admission_Round__c mapRecord(
        AdmissionRoundApiModels.AdmissionRoundRequest input,
        Admission_Round__c existing
    ) {
        Admission_Round__c output = existing == null
            ? new Admission_Round__c(Round_Code__c = input.roundCode.trim())
            : new Admission_Round__c(Id = existing.Id, Round_Code__c = input.roundCode.trim());

        if (input.roundName != null) output.Name = input.roundName.trim();
        if (input.admissionYear != null) output.Admission_Year__c = input.admissionYear.trim();
        if (input.department != null) output.Department__c = input.department.trim();
        if (input.program != null) output.Program__c = input.program.trim();
        if (String.isNotBlank(input.startDate)) output.Start_Date__c = Date.valueOf(input.startDate.trim());
        if (String.isNotBlank(input.endDate)) output.End_Date__c = Date.valueOf(input.endDate.trim());
        return output;
    }

    private static void applyDmlResults(
        Database.UpsertResult[] dmlResults,
        List<Integer> dmlIndexes,
        AdmissionRoundApiModels.ResponseEnvelope response
    ) {
        for (Integer index = 0; index < dmlResults.size(); index++) {
            Database.UpsertResult dmlResult = dmlResults[index];
            AdmissionRoundApiModels.RecordResult result = response.results[dmlIndexes[index]];
            if (dmlResult.isSuccess()) {
                result.success = true;
                result.salesforceId = dmlResult.getId();
                result.action = dmlResult.isCreated() ? ACTION_INSERTED : ACTION_UPDATED;
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

    private static AdmissionRoundApiModels.RecordResult newResult(
        Integer index,
        AdmissionRoundApiModels.AdmissionRoundRequest input
    ) {
        AdmissionRoundApiModels.RecordResult result = new AdmissionRoundApiModels.RecordResult();
        result.index = index;
        result.roundCode = input == null ? null : input.roundCode;
        result.success = false;
        return result;
    }

    private static void markFailure(
        AdmissionRoundApiModels.RecordResult result,
        AdmissionRoundApiModels.ResponseEnvelope response
    ) {
        result.success = false;
        result.action = ACTION_FAILED;
        response.failureCount++;
    }

    private static void logFailures(AdmissionRoundApiModels.ResponseEnvelope response) {
        if (!Schema.sObjectType.API_Log__c.isCreateable()) {
            return;
        }
        List<API_Log__c> logs = new List<API_Log__c>();
        for (AdmissionRoundApiModels.RecordResult result : response.results) {
            if (!result.success) {
                String errorText = String.join(result.errors, ' | ');
                logs.add(new API_Log__c(
                    Log_Name__c = LOG_NAME,
                    Apex_Class_Name__c = CLASS_NAME,
                    Response__c = truncate(errorText, MAX_LOG_MESSAGE_LENGTH),
                    Log_Type__c = 'Failed',
                    Registration_Number__c = truncate(result.roundCode, 50)
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