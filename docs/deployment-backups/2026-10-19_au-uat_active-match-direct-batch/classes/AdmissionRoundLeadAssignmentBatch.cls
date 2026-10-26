/**
 * @description Assigns eligible Admission Rounds to existing unassigned Leads.
 * @author AU Development Team
 * @date 2026-10-19
 * @version 1.0
 * @lastModified 2026-10-19
 */
global without sharing class AdmissionRoundLeadAssignmentBatch implements Database.Batchable<SObject> {
    global Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, Department__c, Admission_Year__c, Assigned_Admission_Round__c
            FROM Lead
            WHERE Assigned_Admission_Round__c = null
                AND Department__c != null
                AND Admission_Year__c != null
        ]);
    }

    global void execute(Database.BatchableContext context, List<Lead> scope) {
        try {
            List<Lead> changedLeads = AdmissionRoundAssignmentService.assignEligibleRounds(scope, Date.today());
            if (changedLeads.isEmpty()) return;
            Database.SaveResult[] results = Database.update(changedLeads, false);
            AdmissionRoundAssignmentService.logUpdateFailures(changedLeads, results);
        } catch (Exception exceptionValue) {
            AdmissionRoundAssignmentService.logUnexpected('AdmissionRoundLeadAssignmentBatch', exceptionValue.getMessage(), null);
        }
    }

    global void finish(Database.BatchableContext context) {
    }
}