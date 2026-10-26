/**
 * @description Assigns cutoff-eligible Admission Rounds and records non-blocking assignment failures.
 * @author AU Development Team
 * @date 2026-10-19
 * @version 1.2
 * @lastModified 2026-10-22
 */
public without sharing class AdmissionRoundAssignmentService {
    private static final String LOG_NAME = 'LeadAdmissionRoundAssignment';
    private static final String LOG_TYPE_FAILED = 'Failed';
    private static final Integer MAX_SHORT_TEXT = 255;
    private static final Map<String, String> DEPARTMENT_ALIASES = new Map<String, String>{
        'phd' => 'Phd',
        'undergraduate' => 'Undergraduation',
        'undergraduation' => 'Undergraduation',
        'clef' => 'CLeF',
        'career development centre' => 'Career Development Centre',
        'executive education' => 'Executive Education',
        'graduation' => 'Graduation',
        'masters' => 'Masters'
    };

    public static List<Lead> assignEligibleRounds(List<Lead> leads) {
        List<Lead> candidates = new List<Lead>();
        Set<String> departments = new Set<String>();
        Set<String> admissionYears = new Set<String>();
        for (Lead leadValue : leads) {
            if (leadValue.Assigned_Admission_Round__c != null) continue;
            String department = canonicalDepartment(leadValue.Department__c);
            String admissionYear = normalize(leadValue.Admission_Year__c);
            if (department == null || admissionYear == null) continue;
            candidates.add(leadValue);
            departments.add(department);
            admissionYears.add(admissionYear);
        }
        if (candidates.isEmpty()) return new List<Lead>();

        Map<String, Admission_Round__c> roundByGroup = new Map<String, Admission_Round__c>();
        for (Admission_Round__c roundValue : AdmissionRoundAssignmentSelector.selectEligible(
            departments,
            admissionYears
        )) {
            String key = groupKey(roundValue.Department__c, roundValue.Admission_Year__c);
            if (!roundByGroup.containsKey(key)) roundByGroup.put(key, roundValue);
        }

        List<Lead> changedLeads = new List<Lead>();
        for (Lead leadValue : candidates) {
            Admission_Round__c match = roundByGroup.get(groupKey(
                canonicalDepartment(leadValue.Department__c),
                normalize(leadValue.Admission_Year__c)
            ));
            if (match != null) {
                leadValue.Assigned_Admission_Round__c = match.Id;
                changedLeads.add(leadValue);
            }
        }
        return changedLeads;
    }

    public static void logUnexpected(String className, String message, Id leadId) {
        try {
            if (!Schema.sObjectType.API_Log__c.isCreateable()) return;
            insertLogs(new List<API_Log__c>{new API_Log__c(
                Log_Name__c = LOG_NAME,
                Apex_Class_Name__c = truncate(className, MAX_SHORT_TEXT),
                Log_Type__c = LOG_TYPE_FAILED,
                Response__c = message,
                Registration_Number__c = leadId == null ? null : String.valueOf(leadId)
            )});
        } catch (Exception ignored) {
            // Logging is deliberately best-effort and must never interrupt Lead or Round DML.
        }
    }

    public static void logUpdateFailures(List<Lead> leads, Database.SaveResult[] results) {
        List<API_Log__c> logs = new List<API_Log__c>();
        for (Integer index = 0; index < results.size(); index++) {
            if (results[index].isSuccess()) continue;
            List<String> messages = new List<String>();
            for (Database.Error errorValue : results[index].getErrors()) {
                messages.add(String.valueOf(errorValue.getStatusCode()) + ': ' + errorValue.getMessage());
            }
            logs.add(new API_Log__c(
                Log_Name__c = LOG_NAME,
                Apex_Class_Name__c = 'AdmissionRoundLeadAssignmentBatch',
                Log_Type__c = LOG_TYPE_FAILED,
                Response__c = String.join(messages, ' | '),
                Registration_Number__c = String.valueOf(leads[index].Id)
            ));
        }
        try {
            if (!logs.isEmpty() && Schema.sObjectType.API_Log__c.isCreateable()) insertLogs(logs);
        } catch (Exception ignored) {
            // Batch failure logging is best-effort and cannot fail the remaining scope.
        }
    }

    private static void insertLogs(List<API_Log__c> logs) {
        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, logs);
        Database.insert(decision.getRecords(), false);
    }

    private static String canonicalDepartment(String value) {
        String normalized = normalize(value);
        return normalized == null ? null : DEPARTMENT_ALIASES.get(normalized.toLowerCase());
    }

    public static Set<String> leadDepartmentValues(String roundDepartment) {
        String canonical = canonicalDepartment(roundDepartment);
        Set<String> values = new Set<String>();
        if (canonical == null) return values;
        values.add(canonical);
        if (canonical == 'Phd') values.add('PhD');
        if (canonical == 'Undergraduation') values.add('Undergraduate');
        return values;
    }

    private static String normalize(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static String groupKey(String department, String admissionYear) {
        return department.toLowerCase() + '|' + admissionYear.toLowerCase();
    }

    private static String truncate(String value, Integer maximumLength) {
        if (value == null || value.length() <= maximumLength) return value;
        return value.substring(0, maximumLength);
    }
}