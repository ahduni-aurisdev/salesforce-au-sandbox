/**
 * @description Assigns cutoff-eligible Admission Rounds to existing unassigned, unconverted Leads.
 * @author AU Development Team
 * @date 2026-10-19
 * @version 1.3
 * @lastModified 2026-10-22
 */
global without sharing class AdmissionRoundLeadAssignmentBatch implements Database.Batchable<SObject> {
    private Map<String, Set<String>> departmentsByYear = new Map<String, Set<String>>();

    // Retained so the previously deployed, now-unused scheduler remains binary compatible.
    global AdmissionRoundLeadAssignmentBatch() {
    }

    global AdmissionRoundLeadAssignmentBatch(List<Admission_Round__c> eligibleRounds) {
        if (eligibleRounds == null) return;
        Date todayValue = Date.today();
        for (Admission_Round__c roundValue : eligibleRounds) {
            if (roundValue == null || roundValue.Cutoff_Date__c == null || roundValue.Cutoff_Date__c < todayValue ||
                String.isBlank(roundValue.Department__c) || String.isBlank(roundValue.Admission_Year__c)) continue;
            String admissionYear = roundValue.Admission_Year__c.trim();
            if (!departmentsByYear.containsKey(admissionYear)) {
                departmentsByYear.put(admissionYear, new Set<String>());
            }
            departmentsByYear.get(admissionYear).addAll(
                AdmissionRoundAssignmentService.leadDepartmentValues(roundValue.Department__c)
            );
        }
    }

    global Database.QueryLocator start(Database.BatchableContext context) {
        String queryValue = 'SELECT Id, Department__c, Admission_Year__c, Assigned_Admission_Round__c ' +
            'FROM Lead WHERE Assigned_Admission_Round__c = null AND IsConverted = false';
        List<String> groupFilters = new List<String>();
        for (String admissionYear : departmentsByYear.keySet()) {
            Set<String> departmentValues = departmentsByYear.get(admissionYear);
            if (departmentValues.isEmpty()) continue;
            groupFilters.add(
                '(Admission_Year__c = \'' + String.escapeSingleQuotes(admissionYear) + '\' AND Department__c IN (' +
                quotedValues(departmentValues) + '))'
            );
        }
        queryValue += groupFilters.isEmpty() ? ' AND Id = null' : ' AND (' + String.join(groupFilters, ' OR ') + ')';
        return Database.getQueryLocator(queryValue);
    }

    global void execute(Database.BatchableContext context, List<Lead> scope) {
        try {
            List<Lead> changedLeads = AdmissionRoundAssignmentService.assignEligibleRounds(scope);
            if (changedLeads.isEmpty()) return;
            Database.SaveResult[] results = Database.update(changedLeads, false);
            AdmissionRoundAssignmentService.logUpdateFailures(changedLeads, results);
        } catch (Exception exceptionValue) {
            AdmissionRoundAssignmentService.logUnexpected('AdmissionRoundLeadAssignmentBatch', exceptionValue.getMessage(), null);
        }
    }

    global void finish(Database.BatchableContext context) {
    }

    private static String quotedValues(Set<String> values) {
        List<String> quoted = new List<String>();
        for (String value : values) quoted.add('\'' + String.escapeSingleQuotes(value) + '\'');
        return String.join(quoted, ',');
    }
}
