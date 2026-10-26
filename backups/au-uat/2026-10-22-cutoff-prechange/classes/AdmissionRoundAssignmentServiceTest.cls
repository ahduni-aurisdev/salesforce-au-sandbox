/**
 * @description Tests date-window selection, aliases, preservation, deterministic overlap handling, and bulk behavior.
 * @author AU Development Team
 * @date 2026-10-19
 * @version 1.1
 * @lastModified 2026-10-22
 */
@IsTest
private class AdmissionRoundAssignmentServiceTest {
    private static final String YEAR = 'Admission Year - 2027';

    @TestSetup
    static void createData() {
        List<Lead> leads = new List<Lead>();
        for (Integer index = 0; index < 200; index++) {
            leads.add(new Lead(
                LastName = 'Pending ' + index,
                Company = 'AU Test',
                Department__c = 'Masters',
                Admission_Year__c = YEAR
            ));
        }
        insert leads;
    }

    @IsTest
    static void shouldAssignDateEligibleMatchThroughBeforeInsertTrigger() {
        Admission_Round__c roundValue = createRound('ELIGIBLE', 'Masters', YEAR, Date.today(), Date.today(), false);
        insert roundValue;
        Lead leadValue = new Lead(
            LastName = 'Eligible', Company = 'AU Test', Department__c = 'Masters', Admission_Year__c = YEAR
        );

        Test.startTest();
        insert leadValue;
        Test.stopTest();

        Lead saved = [SELECT Assigned_Admission_Round__c FROM Lead WHERE Id = :leadValue.Id];
        System.assertEquals(roundValue.Id, saved.Assigned_Admission_Round__c, 'Inclusive boundary dates should assign regardless of Active.');
    }

    @IsTest
    static void shouldAssignOnlyRoundsContainingToday() {
        List<Admission_Round__c> rounds = new List<Admission_Round__c>{
            createRound('FUTURE-START', 'Masters', 'Admission Year - 2028', Date.today().addDays(30), Date.today().addDays(40), true),
            createRound('PAST-END', 'Phd', YEAR, Date.today().addDays(-30), Date.today().addDays(-1), true),
            createRound('MISSING-DATE', 'Graduation', YEAR, null, null, true),
            createRound('CURRENT', 'CLeF', YEAR, Date.today().addDays(-1), Date.today().addDays(1), false)
        };
        insert rounds;
        List<Lead> leads = new List<Lead>{
            lead('Future', 'Masters', 'Admission Year - 2028'),
            lead('Past', 'Phd', YEAR),
            lead('Missing', 'Graduation', YEAR),
            lead('Current', 'CLeF', YEAR)
        };

        Test.startTest();
        insert leads;
        Test.stopTest();

        Set<Id> leadIds = new Map<Id, Lead>(leads).keySet();
        Map<Id, Lead> saved = new Map<Id, Lead>([
            SELECT Assigned_Admission_Round__c FROM Lead WHERE Id IN :leadIds
        ]);
        System.assertEquals(null, saved.get(leads[0].Id).Assigned_Admission_Round__c, 'A future round must not be selected.');
        System.assertEquals(null, saved.get(leads[1].Id).Assigned_Admission_Round__c, 'An expired round must not be selected.');
        System.assertEquals(null, saved.get(leads[2].Id).Assigned_Admission_Round__c, 'A round with missing dates must not be selected.');
        System.assertEquals(rounds[3].Id, saved.get(leads[3].Id).Assigned_Admission_Round__c, 'A current round must be selected even when Active is false.');
    }

    @IsTest
    static void shouldNormalizeApprovedDepartmentAliases() {
        Admission_Round__c phdRound = createRound('PHD', 'Phd', YEAR, Date.today(), Date.today().addDays(10), true);
        Admission_Round__c ugRound = createRound('UG', 'Undergraduation', YEAR, Date.today(), Date.today().addDays(10), true);
        insert new List<Admission_Round__c>{phdRound, ugRound};
        List<Lead> leads = new List<Lead>{
            lead('PhD Alias', 'PhD', YEAR),
            lead('UG Alias', 'Undergraduate', YEAR)
        };

        insert leads;
        Set<Id> leadIds = new Map<Id, Lead>(leads).keySet();
        Map<Id, Lead> saved = new Map<Id, Lead>([
            SELECT Assigned_Admission_Round__c FROM Lead WHERE Id IN :leadIds
        ]);
        System.assertEquals(phdRound.Id, saved.get(leads[0].Id).Assigned_Admission_Round__c, 'PhD alias should match Phd.');
        System.assertEquals(ugRound.Id, saved.get(leads[1].Id).Assigned_Admission_Round__c, 'Undergraduate alias should match Undergraduation.');
    }

    @IsTest
    static void shouldPreserveSuppliedAssignmentAndHandleTwoHundredRecords() {
        Admission_Round__c supplied = createRound('SUPPLIED', 'Masters', YEAR, Date.today().addDays(-20), Date.today().addDays(-10), true);
        Admission_Round__c eligible = createRound('BULK', 'Masters', YEAR, Date.today(), Date.today().addDays(10), false);
        insert new List<Admission_Round__c>{supplied, eligible};
        Lead preassigned = lead('Preassigned', 'Masters', YEAR);
        preassigned.Assigned_Admission_Round__c = supplied.Id;
        insert preassigned;
        System.assertEquals(
            supplied.Id,
            [SELECT Assigned_Admission_Round__c FROM Lead WHERE Id = :preassigned.Id].Assigned_Admission_Round__c,
            'A supplied lookup must be preserved without overwrite.'
        );

        List<Lead> bulkLeads = new List<Lead>();
        for (Integer index = 0; index < 200; index++) bulkLeads.add(lead('Bulk ' + index, 'Masters', YEAR));
        Test.startTest();
        List<Lead> changed = AdmissionRoundAssignmentService.assignEligibleRounds(bulkLeads);
        Test.stopTest();
        System.assertEquals(200, changed.size(), 'All 200 eligible Leads should be assigned in one bulk call.');
        for (Lead leadValue : bulkLeads) {
            System.assertEquals(eligible.Id, leadValue.Assigned_Admission_Round__c, 'Every bulk Lead should receive the round.');
        }
    }

    @IsTest
    static void shouldHandleInvalidSelectorInputsAndLogPartialFailures() {
        System.assertEquals(
            0,
            AdmissionRoundAssignmentSelector.selectEligible(null, null).size(),
            'Invalid selector inputs should safely produce no matches.'
        );
        Lead invalidLead = [SELECT Id, OwnerId FROM Lead LIMIT 1];
        invalidLead.OwnerId = '005000000000000';
        Database.SaveResult[] results = Database.update(new List<Lead>{invalidLead}, false);
        System.assertEquals(false, results[0].isSuccess(), 'The invalid Lead update should provide a partial-DML failure to log.');

        Test.startTest();
        AdmissionRoundAssignmentService.logUpdateFailures(new List<Lead>{invalidLead}, results);
        AdmissionRoundAssignmentService.logUnexpected('AdmissionRoundAssignmentServiceTest', 'Expected test error', invalidLead.Id);
        Test.stopTest();

        System.assert(
            [SELECT COUNT() FROM API_Log__c WHERE Log_Name__c = 'LeadAdmissionRoundAssignment'] >= 2,
            'Both failure logging paths should create audit records without throwing.'
        );
    }

    @IsTest
    static void shouldChooseLatestStartDateWhenCurrentRoundsOverlap() {
        Admission_Round__c older = createRound(
            'OVERLAP-OLDER', 'Masters', YEAR, Date.today().addDays(-10), Date.today().addDays(10), true
        );
        Admission_Round__c newer = createRound(
            'OVERLAP-NEWER', 'Masters', YEAR, Date.today().addDays(-2), Date.today().addDays(10), false
        );
        insert new List<Admission_Round__c>{older, newer};

        Lead leadValue = lead('Overlap', 'Masters', YEAR);
        insert leadValue;

        System.assertEquals(
            newer.Id,
            [SELECT Assigned_Admission_Round__c FROM Lead WHERE Id = :leadValue.Id].Assigned_Admission_Round__c,
            'The current round with the latest Start Date must win regardless of Active values.'
        );
    }

    private static Lead lead(String lastName, String department, String admissionYear) {
        return new Lead(LastName = lastName, Company = 'AU Test', Department__c = department, Admission_Year__c = admissionYear);
    }

    private static Admission_Round__c createRound(
        String code, String department, String admissionYear, Date startDate, Date endDate, Boolean isActive
    ) {
        return new Admission_Round__c(
            Name = code,
            Round_Code__c = code,
            Department__c = department,
            Admission_Year__c = admissionYear,
            Start_Date__c = startDate,
            End_Date__c = endDate,
            Is_Active__c = isActive
        );
    }
}