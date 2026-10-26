/**
 * @description Selects eligible active Admission Rounds for automatic Lead assignment.
 * @author AU Development Team
 * @date 2026-10-19
 * @version 1.0
 * @lastModified 2026-10-19
 */
public without sharing class AdmissionRoundAssignmentSelector {
    // System-mode selection is intentional: Lead assignment must behave consistently for
    // every Lead creator even when that user cannot directly browse Admission Round records.
    public static List<Admission_Round__c> selectEligible(
        Set<String> departments,
        Set<String> admissionYears,
        Date assignmentDate
    ) {
        if (departments == null || admissionYears == null || assignmentDate == null ||
            departments.isEmpty() || admissionYears.isEmpty()) {
            return new List<Admission_Round__c>();
        }
        Date minimumEndDate = assignmentDate.addDays(5);
        return [
            SELECT Id, Department__c, Admission_Year__c, Start_Date__c, End_Date__c, CreatedDate
            FROM Admission_Round__c
            WHERE Is_Active__c = true
                AND Department__c IN :departments
                AND Admission_Year__c IN :admissionYears
                AND Start_Date__c <= :assignmentDate
                AND End_Date__c > :minimumEndDate
            ORDER BY Start_Date__c DESC, CreatedDate DESC
        ];
    }
}