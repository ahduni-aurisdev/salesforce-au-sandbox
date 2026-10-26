/**
 * @description Tests cutoff-based Batch Apex launch, group filtering, assignment, and preservation.
 * @author AU Development Team
 * @date 2026-10-19
 * @version 1.2
 * @lastModified 2026-10-22
 */
@IsTest
private class AdmissionRoundLeadAssignmentAsyncTest {
    private static final String YEAR = 'Admission Year - 2027';
    private static final Integer CUTOFF_OFFSET_DAYS = 5;

    @TestSetup
    static void createData() {
        List<Lead> leads = new List<Lead>();
        for (Integer index = 0; index < 200; index++) {
            leads.add(new Lead(
                LastName = 'Batch ' + index,
                Company = 'AU Test',
                Department__c = 'Masters',
                Admission_Year__c = YEAR
            ));
        }
        leads.add(new Lead(
            LastName = 'Unrelated Department',
            Company = 'AU Test',
            Department__c = 'Graduation',
            Admission_Year__c = YEAR
        ));
        leads.add(new Lead(
            LastName = 'Unrelated Year',
            Company = 'AU Test',
            Department__c = 'Masters',
            Admission_Year__c = 'Admission Year - 2028'
        ));
        insert leads;
    }

    @IsTest
    static void shouldLaunchBatchWhenRoundIsReceivedBeforeStartDate() {
        Admission_Round__c roundValue = round('ADVANCE-BATCH', Date.today().addDays(10), Date.today().addDays(20), false);

        Test.startTest();
        insert roundValue;
        System.assertEquals(true, AdmissionRoundTriggerHandler.hasLaunchedBatch, 'A round received before its Start Date should launch one batch immediately.');
        Test.stopTest();

        System.assertEquals(
            200,
            [SELECT COUNT() FROM Lead WHERE Assigned_Admission_Round__c = :roundValue.Id],
            'Only pending Leads in the matching Department and Admission Year group should be assigned.'
        );
        System.assertEquals(
            2,
            [SELECT COUNT() FROM Lead WHERE Assigned_Admission_Round__c = null],
            'Leads outside the matching group must remain pending.'
        );
    }

    @IsTest
    static void shouldNotLaunchBatchWhenRoundIsPastCutoff() {
        Admission_Round__c roundValue = round(
            'PAST-CUTOFF-BATCH', Date.today().addDays(-10), Date.today().addDays(CUTOFF_OFFSET_DAYS - 1), true
        );

        Test.startTest();
        insert roundValue;
        Test.stopTest();

        System.assertEquals(false, AdmissionRoundTriggerHandler.hasLaunchedBatch, 'A round past its Cutoff Date must not launch a batch.');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Lead WHERE Assigned_Admission_Round__c = :roundValue.Id],
            'No pending Lead should be assigned to a round past its Cutoff Date.'
        );
    }

    @IsTest
    static void shouldAssignPendingLeadsAndPreserveExistingAssignments() {
        Admission_Round__c roundValue = round(
            'BATCH-RUN', Date.today().addDays(-10), Date.today().addDays(CUTOFF_OFFSET_DAYS - 1), true
        );
        insert roundValue;
        System.assertEquals(false, AdmissionRoundTriggerHandler.hasLaunchedBatch, 'A round past its Cutoff Date must not launch a batch.');
        Lead protectedLead = [SELECT Id FROM Lead WHERE Department__c = 'Masters' AND Admission_Year__c = :YEAR LIMIT 1];
        protectedLead.Assigned_Admission_Round__c = roundValue.Id;
        update protectedLead;

        Test.startTest();
        roundValue.End_Date__c = Date.today().addDays(20);
        update roundValue;
        Test.stopTest();

        System.assertEquals(
            200,
            [SELECT COUNT() FROM Lead WHERE Assigned_Admission_Round__c = :roundValue.Id],
            'The batch should assign all pending matching Leads and preserve the existing assignment.'
        );
    }

    private static Admission_Round__c round(String code, Date startDate, Date endDate, Boolean active) {
        return new Admission_Round__c(
            Name = code,
            Round_Code__c = code,
            Department__c = 'Masters',
            Admission_Year__c = YEAR,
            Start_Date__c = startDate,
            End_Date__c = endDate,
            Is_Active__c = active
        );
    }
}