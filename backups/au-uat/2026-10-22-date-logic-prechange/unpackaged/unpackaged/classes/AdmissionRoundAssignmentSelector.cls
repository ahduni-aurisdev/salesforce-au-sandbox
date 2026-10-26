/**
 * @description Selects active Admission Rounds for automatic Lead assignment.
 * @author AU Development Team
 * @date 2026-10-19
 * @version 1.0
 * @lastModified 2026-10-19
 */
public without sharing class AdmissionRoundAssignmentSelector {
    // System-mode selection is intentional: Lead assignment must behave consistently for
    // every Lead creator even when that user cannot directly browse Admission Round records.
    public static List<Admission_Round__c> selectActive(
        Set<String> departments,
        Set<String> admissionYears
    ) {
        if (departments == null || admissionYears == null || departments.isEmpty() || admissionYears.isEmpty()) {
            return new List<Admission_Round__c>();
        }
        return [
            SELECT Id, Department__c, Admission_Year__c, CreatedDate
            FROM Admission_Round__c
            WHERE Is_Active__c = true
                AND Department__c IN :departments
                AND Admission_Year__c IN :admissionYears
            ORDER BY CreatedDate DESC
        ];
    }
}