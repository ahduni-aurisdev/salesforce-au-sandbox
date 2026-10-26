/**
 * @description Launches pending Lead assignment after a saved Admission Round is still on or before its Cutoff Date.
 * @author AU Development Team
 * @date 2026-10-19
 * @version 1.2
 * @lastModified 2026-10-22
 */
public without sharing class AdmissionRoundTriggerHandler {
    private static final Integer BATCH_SCOPE_SIZE = 200;
    @TestVisible private static Boolean hasLaunchedBatch = false;

    public static void afterInsertOrUpdate(
        List<Admission_Round__c> newRecords,
        Map<Id, Admission_Round__c> oldRecords
    ) {
        if (hasLaunchedBatch || newRecords == null || newRecords.isEmpty()) return;
        try {
            List<Admission_Round__c> eligibleRounds = getEligibleRounds(newRecords);
            if (eligibleRounds.isEmpty()) return;
            hasLaunchedBatch = true;
            Database.executeBatch(new AdmissionRoundLeadAssignmentBatch(eligibleRounds), BATCH_SCOPE_SIZE);
        } catch (Exception exceptionValue) {
            AdmissionRoundAssignmentService.logUnexpected('AdmissionRoundTriggerHandler', exceptionValue.getMessage(), null);
        }
    }

    private static List<Admission_Round__c> getEligibleRounds(List<Admission_Round__c> newRecords) {
        // Cutoff_Date__c is a formula, so it is re-read once rather than trusted from trigger context.
        List<Admission_Round__c> eligibleRounds = new List<Admission_Round__c>();
        Date todayValue = Date.today();
        for (Admission_Round__c roundValue : AdmissionRoundAssignmentSelector.selectByIds(
            new Map<Id, Admission_Round__c>(newRecords).keySet()
        )) {
            if (roundValue.Cutoff_Date__c != null && roundValue.Cutoff_Date__c >= todayValue) {
                eligibleRounds.add(roundValue);
            }
        }
        return eligibleRounds;
    }
}
