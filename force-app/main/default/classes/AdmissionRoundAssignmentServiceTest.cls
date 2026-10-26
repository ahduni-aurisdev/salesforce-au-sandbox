/**
 * @description Tests cutoff-window selection, aliases, preservation, earliest-cutoff overlap handling, and bulk behavior.
 * @author AU Development Team
 * @date 2026-10-19
 * @version 1.2
 * @lastModified 2026-10-22
 */
@IsTest
private class AdmissionRoundAssignmentServiceTest {
    private static final String YEAR = 'Admission Year - 2027';
    private static final Integer CUTOFF_OFFSET_DAYS = 5;

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
    static void shouldAssignRoundReceivedBeforeStartDateThroughBeforeInsertTrigger() {
        Admission_Round__c roundValue = createRound(
            'UPCOMING', 'Masters', YEAR, Date.today().addDays(3), Date.today().addDays(20), false
        );
        insert roundValue;
        Lead leadValue = lead('Upcoming', 'Masters', YEAR);

        Test.startTest();
        insert leadValue;
        Test.stopTest();

        Lead saved = [SELECT Assigned_Admission_Round__c FROM Lead WHERE Id = :leadValue.Id];
        System.assertEquals(roundValue.Id, saved.Assigned_Admission_Round__c, 'A round received before its Start Date must be assigned immediately.');
    }

    @IsTest
    static void shouldAssignOnlyRoundsOnOrBeforeCutoffDate() {
        List<Admission_Round__c> rounds = new List<Admission_Round__c>{
            createRound('CUTOFF-TODAY', 'CLeF', YEAR, Date.today().addDays(-10), Date.today().addDays(CUTOFF_OFFSET_DAYS), false),
            createRound('PAST-CUTOFF', 'Phd', YEAR, Date.today().addDays(-10), Date.today().addDays(CUTOFF_OFFSET_DAYS - 1), true),
            createRound('MISSING-DATE', 'Graduation', YEAR, null, null, true)
        };
        insert rounds;
        List<Lead> leads = new List<Lead>{
            lead('Cutoff Today', 'CLeF', YEAR),
            lead('Past Cutoff', 'Phd', YEAR),
            lead('Missing', 'Graduation', YEAR)
        };

        Test.startTest();
        insert leads;
        Test.stopTest();

        Set<Id> leadIds = new Map<Id, Lead>(leads).keySet();
        Map<Id, Lead> saved = new Map<Id, Lead>([
            SELECT Assigned_Admission_Round__c FROM Lead WHERE Id IN :leadIds
        ]);
        System.assertEquals(rounds[0].Id, saved.get(leads[0].Id).Assigned_Admission_Round__c, 'The Cutoff Date itself is inclusive.');
        System.assertEquals(null, saved.get(leads[1].Id).Assigned_Admission_Round__c, 'A round past its Cutoff Date must not be selected, even before its End Date.');
        System.assertEquals(null, saved.get(leads[2].Id).Assigned_Admission_Round__c, 'A round without an End Date has no Cutoff Date and must not be selected.');
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
        System.assertEquals(
            0,
            AdmissionRoundAssignmentSelector.selectByIds(null).size(),
            'A null Id set should safely produce no rounds.'
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
    static void shouldChooseEarliestCutoffWhenRoundsOverlap() {
        Admission_Round__c current = createRound(
            'OVERLAP-CURRENT', 'Masters', YEAR, Date.today().addDays(-10), Date.today().addDays(10), true
        );
        Admission_Round__c upcoming = createRound(
            'OVERLAP-UPCOMING', 'Masters', YEAR, Date.today().addDays(1), Date.today().addDays(30), false
        );
        insert new List<Admission_Round__c>{current, upcoming};

        Lead leadValue = lead('Overlap', 'Masters', YEAR);
        insert leadValue;

        System.assertEquals(
            current.Id,
            [SELECT Assigned_Admission_Round__c FROM Lead WHERE Id = :leadValue.Id].Assigned_Admission_Round__c,
            'The round with the earliest Cutoff Date must be filled first.'
        );
    }

    @IsTest
    static void shouldMoveToNextRoundAfterEarlierCutoffPasses() {
        Admission_Round__c closed = createRound(
            'NEXT-CLOSED', 'Masters', YEAR, Date.today().addDays(-10), Date.today().addDays(CUTOFF_OFFSET_DAYS - 1), true
        );
        Admission_Round__c next = createRound(
            'NEXT-OPEN', 'Masters', YEAR, Date.today().addDays(2), Date.today().addDays(30), false
        );
        insert new List<Admission_Round__c>{closed, next};

        Lead leadValue = lead('Next Round', 'Masters', YEAR);
        insert leadValue;

        System.assertEquals(
            next.Id,
            [SELECT Assigned_Admission_Round__c FROM Lead WHERE Id = :leadValue.Id].Assigned_Admission_Round__c,
            'Once the earlier round passes its Cutoff Date, the next usable round must be assigned.'
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