/**
 * @description Launches pending Lead assignment after a currently date-eligible Admission Round is saved.
 * @author AU Development Team
 * @date 2026-10-19
 * @version 1.1
 * @lastModified 2026-10-22
 */
public without sharing class AdmissionRoundTriggerHandler {
    private static final Integer BATCH_SCOPE_SIZE = 200;
    @TestVisible private static Boolean hasLaunchedBatch = false;

    public static void afterInsertOrUpdate(
        List<Admission_Round__c> newRecords,
        Map<Id, Admission_Round__c> oldRecords
    ) {
        List<Admission_Round__c> eligibleRounds = getEligibleRounds(newRecords);
        if (hasLaunchedBatch || eligibleRounds.isEmpty()) return;
        hasLaunchedBatch = true;
        try {
            Database.executeBatch(new AdmissionRoundLeadAssignmentBatch(eligibleRounds), BATCH_SCOPE_SIZE);
        } catch (Exception exceptionValue) {
            AdmissionRoundAssignmentService.logUnexpected('AdmissionRoundTriggerHandler', exceptionValue.getMessage(), null);
        }
    }

    private static List<Admission_Round__c> getEligibleRounds(List<Admission_Round__c> newRecords) {
        List<Admission_Round__c> eligibleRounds = new List<Admission_Round__c>();
        Date todayValue = Date.today();
        for (Admission_Round__c roundValue : newRecords) {
            if (roundValue.Start_Date__c == null || roundValue.End_Date__c == null) continue;
            if (roundValue.Start_Date__c <= todayValue && roundValue.End_Date__c >= todayValue) {
                eligibleRounds.add(roundValue);
            }
        }
        return eligibleRounds;
    }
}