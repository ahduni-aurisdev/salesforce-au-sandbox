/**
 * @description Selects date-eligible Admission Rounds for automatic Lead assignment.
 * @author AU Development Team
 * @date 2026-10-19
 * @version 1.1
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
        return [
            SELECT Id, Department__c, Admission_Year__c, Start_Date__c, End_Date__c, LastModifiedDate
            FROM Admission_Round__c
            WHERE Department__c IN :departments
                AND Admission_Year__c IN :admissionYears
                AND Start_Date__c <= :todayValue
                AND End_Date__c >= :todayValue
            ORDER BY Start_Date__c DESC, LastModifiedDate DESC, Id DESC
        ];
    }
}