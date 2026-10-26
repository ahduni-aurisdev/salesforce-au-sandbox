/**
 * @description Selects Admission Rounds that are usable for automatic Lead assignment (today on or before Cutoff Date).
 * @author AU Development Team
 * @date 2026-10-19
 * @version 1.2
 * @lastModified 2026-10-22
 */
public without sharing class AdmissionRoundAssignmentSelector {
    // System-mode selection is intentional: Lead assignment must behave consistently for
    // every Lead creator even when that user cannot directly browse Admission Round records.
    public static List<Admission_Round__c> selectEligible(
        Set<String> departments,
        Set<String> admissionYears
    ) {
        if (departments == null || admissionYears == null || departments.isEmpty() || admissionYears.isEmpty()) {
            return new List<Admission_Round__c>();
        }
        Date todayValue = Date.today();
        // Earliest Cutoff Date first so the round closing soonest is filled before the next one.
        return [
            SELECT Id, Department__c, Admission_Year__c, Start_Date__c, End_Date__c, Cutoff_Date__c, LastModifiedDate
            FROM Admission_Round__c
            WHERE Department__c IN :departments
                AND Admission_Year__c IN :admissionYears
                AND Cutoff_Date__c != null
                AND Cutoff_Date__c >= :todayValue
            ORDER BY Cutoff_Date__c ASC, Start_Date__c ASC NULLS LAST, LastModifiedDate DESC, Id DESC
        ];
    }

    public static List<Admission_Round__c> selectByIds(Set<Id> roundIds) {
        if (roundIds == null || roundIds.isEmpty()) return new List<Admission_Round__c>();
        return [
            SELECT Id, Department__c, Admission_Year__c, Cutoff_Date__c
            FROM Admission_Round__c
            WHERE Id IN :roundIds
        ];
    }
}
