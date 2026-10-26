/**
 * @description Tests event scheduling, Batch Apex assignment, and Scheduled Apex execution.
 * @author AU Development Team
 * @date 2026-10-19
 * @version 1.0
 * @lastModified 2026-10-19
 */
@IsTest
private class AdmissionRoundLeadAssignmentAsyncTest {
    private static final String YEAR = 'Admission Year - 2027';

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
        insert leads;
    }

    @IsTest
    static void shouldRequestScheduleOnlyWhenRoundBecomesActive() {
        Integer initialRequests = AdmissionRoundLeadAssignmentScheduler.scheduleRequestCount;
        Admission_Round__c roundValue = round('SCHEDULE', false);
        insert roundValue;
        System.assertEquals(initialRequests, AdmissionRoundLeadAssignmentScheduler.scheduleRequestCount, 'Inactive insert should not schedule.');

        roundValue.Is_Active__c = true;
        update roundValue;
        System.assertEquals(initialRequests + 1, AdmissionRoundLeadAssignmentScheduler.scheduleRequestCount, 'Activation should schedule once.');
    }

    @IsTest
    static void shouldAssignPendingLeadsAndPreserveExistingAssignments() {
        Admission_Round__c roundValue = round('BATCH-RUN', true);
        insert roundValue;
        Lead protectedLead = [SELECT Id FROM Lead LIMIT 1];
        protectedLead.Assigned_Admission_Round__c = roundValue.Id;
        update protectedLead;

        Test.startTest();
        Database.executeBatch(new AdmissionRoundLeadAssignmentBatch(), 200);
        Test.stopTest();

        System.assertEquals(
            200,
            [SELECT COUNT() FROM Lead WHERE Assigned_Admission_Round__c = :roundValue.Id],
            'The batch should assign all pending eligible Leads and preserve the existing assignment.'
        );
    }

    @IsTest
    static void shouldLaunchBatchFromScheduler() {
        insert round('SCHEDULER-RUN', true);
        Test.startTest();
        new AdmissionRoundLeadAssignmentScheduler().execute(null);
        Test.stopTest();
        System.assertEquals(
            200,
            [SELECT COUNT() FROM Lead WHERE Assigned_Admission_Round__c != null],
            'Scheduler execution should launch the assignment batch.'
        );
    }

    @IsTest
    static void shouldCreateAndExecuteOneTimeScheduledJob() {
        AdmissionRoundLeadAssignmentScheduler.forceSchedulingInTest = true;
        Test.startTest();
        AdmissionRoundLeadAssignmentScheduler.scheduleAfterCommit();
        List<CronTrigger> jobs = [
            SELECT Id, State
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Admission Round Lead Assignment%'
        ];
        System.assertEquals(1, jobs.size(), 'Exactly one event-driven scheduled job should be created.');
        Test.stopTest();
    }

    private static Admission_Round__c round(String code, Boolean active) {
        return new Admission_Round__c(
            Name = code,
            Round_Code__c = code,
            Department__c = 'Masters',
            Admission_Year__c = YEAR,
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addDays(10),
            Is_Active__c = active
        );
    }
}