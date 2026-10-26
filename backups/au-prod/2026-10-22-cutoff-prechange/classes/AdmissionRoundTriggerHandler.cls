/**
 * @description Launches pending Lead assignment after an Admission Round becomes active.
 * @author AU Development Team
 * @date 2026-10-19
 * @version 1.0
 * @lastModified 2026-10-19
 */
public without sharing class AdmissionRoundTriggerHandler {
    private static final Integer BATCH_SCOPE_SIZE = 200;
    @TestVisible private static Boolean hasLaunchedBatch = false;

    public static void afterInsertOrUpdate(
        List<Admission_Round__c> newRecords,
        Map<Id, Admission_Round__c> oldRecords
    ) {
        List<Admission_Round__c> newlyActiveRounds = getNewlyActiveRounds(newRecords, oldRecords);
        if (hasLaunchedBatch || newlyActiveRounds.isEmpty()) return;
        hasLaunchedBatch = true;
        try {
            Database.executeBatch(new AdmissionRoundLeadAssignmentBatch(newlyActiveRounds), BATCH_SCOPE_SIZE);
        } catch (Exception exceptionValue) {
            AdmissionRoundAssignmentService.logUnexpected('AdmissionRoundTriggerHandler', exceptionValue.getMessage(), null);
        }
    }

    private static List<Admission_Round__c> getNewlyActiveRounds(
        List<Admission_Round__c> newRecords,
        Map<Id, Admission_Round__c> oldRecords
    ) {
        List<Admission_Round__c> newlyActiveRounds = new List<Admission_Round__c>();
        for (Admission_Round__c roundValue : newRecords) {
            if (!roundValue.Is_Active__c) continue;
            Admission_Round__c oldValue = oldRecords == null ? null : oldRecords.get(roundValue.Id);
            if (oldValue == null || !oldValue.Is_Active__c) newlyActiveRounds.add(roundValue);
        }
        return newlyActiveRounds;
    }
}