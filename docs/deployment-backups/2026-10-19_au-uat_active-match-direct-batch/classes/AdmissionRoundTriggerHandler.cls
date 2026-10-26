/**
 * @description Schedules pending Lead assignment after an Admission Round becomes active.
 * @author AU Development Team
 * @date 2026-10-19
 * @version 1.0
 * @lastModified 2026-10-19
 */
public without sharing class AdmissionRoundTriggerHandler {
    private static Boolean hasScheduled = false;

    public static void afterInsertOrUpdate(
        List<Admission_Round__c> newRecords,
        Map<Id, Admission_Round__c> oldRecords
    ) {
        if (hasScheduled || !containsNewlyActiveRound(newRecords, oldRecords)) return;
        hasScheduled = true;
        try {
            AdmissionRoundLeadAssignmentScheduler.scheduleAfterCommit();
        } catch (Exception exceptionValue) {
            AdmissionRoundAssignmentService.logUnexpected('AdmissionRoundTriggerHandler', exceptionValue.getMessage(), null);
        }
    }

    private static Boolean containsNewlyActiveRound(
        List<Admission_Round__c> newRecords,
        Map<Id, Admission_Round__c> oldRecords
    ) {
        for (Admission_Round__c roundValue : newRecords) {
            if (!roundValue.Is_Active__c) continue;
            if (oldRecords == null || !oldRecords.get(roundValue.Id).Is_Active__c) return true;
        }
        return false;
    }
}