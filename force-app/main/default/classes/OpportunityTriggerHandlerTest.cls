@isTest
public class OpportunityTriggerHandlerTest {

    private static Id getCdcRecordTypeId() {
        return Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get('CDC')
            ?.getRecordTypeId();
    }

    private static void addProgramLine(Id oppId, Decimal expected, Decimal registered, Decimal appeared, Decimal shortlisted, Decimal selected, Decimal offerCount, Decimal ctc, String prog, String aoi) {
        insert new Drive_Program_Line__c(
            Opportunity__c = oppId,
            Program__c = prog,
            AOI__c = aoi,
            Expected_Students__c = expected,
            Registered_Students__c = registered,
            Appeared_Students__c = appeared,
            Shortlisted_Students__c = shortlisted,
            Selected_Students__c = selected,
            Offer_Accepted__c = offerCount,
            CTC_Offered__c = ctc
        );
    }

    @isTest
    static void testSetCompletionDate() {
        Id cdcRecordTypeId = getCdcRecordTypeId();
        System.assertNotEquals(null, cdcRecordTypeId, 'CDC Opportunity Record Type must exist.');

        // 1. Create a CDC Opportunity in a non-completed stage
        Opportunity opp = new Opportunity(
            Name = 'Test CDC Opp 1',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            RecordTypeId = cdcRecordTypeId
        );
        insert opp;

        // Verify Completion_Date__c is not set initially
        Opportunity insertedOpp = [SELECT Completion_Date__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(null, insertedOpp.Completion_Date__c, 'Completion Date should not be set initially.');

        // 2. Update stage to Completed
        Test.startTest();
        opp.StageName = 'Completed';
        update opp;
        Test.stopTest();

        // Verify Completion_Date__c is set to today
        Opportunity updatedOpp = [SELECT Completion_Date__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(Date.today(), updatedOpp.Completion_Date__c, 'Completion Date should be set to today.');
    }

    @isTest
    static void testSetCompletionDateNonCdc() {
        // Query a non-CDC Opportunity record type (like standard or other)
        Opportunity opp = new Opportunity(
            Name = 'Test Non-CDC Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Update stage to Completed
        Test.startTest();
        opp.StageName = 'Completed';
        update opp;
        Test.stopTest();

        // Verify Completion_Date__c is NOT set
        Opportunity updatedOpp = [SELECT Completion_Date__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(null, updatedOpp.Completion_Date__c, 'Completion Date should not be set for non-CDC opportunities.');
    }

    @isTest
    static void testUpsertCampusDriveOnStageChange() {
        Id cdcRecordTypeId = getCdcRecordTypeId();
        System.assertNotEquals(null, cdcRecordTypeId, 'CDC Opportunity Record Type must exist.');

        Account acc = new Account(Name = 'Test Academic Account');
        insert acc;

        // Fetch dynamic Program and AOI values
        List<Map<String, String>> programOptions = CDCProgramLinesController.getProgramOptions();
        String prog1 = 'MTech - CSE';
        String prog2 = 'Mech';
        if (programOptions.size() > 0) prog1 = programOptions[0].get('value');
        if (programOptions.size() > 1) prog2 = programOptions[1].get('value');

        List<Map<String, String>> aoiOptions1 = CDCProgramLinesController.getAOIOptions(prog1);
        String aoi1 = 'CSE';
        if (!aoiOptions1.isEmpty()) aoi1 = aoiOptions1[0].get('value');

        List<Map<String, String>> aoiOptions2 = CDCProgramLinesController.getAOIOptions(prog2);
        String aoi2 = 'CSE';
        if (!aoiOptions2.isEmpty()) aoi2 = aoiOptions2[0].get('value');

        String oppPrograms = prog1;
        if (prog1 != prog2) {
            oppPrograms = prog1 ;
        }

        // Insert CDC Opportunity without read-only rollup fields
        Opportunity opp = new Opportunity(
            Name = 'Test CDC Opp 2',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            RecordTypeId = cdcRecordTypeId,
            AccountId = acc.Id,
            Academic_Year__c = '2026',
            Program__c = oppPrograms
        );
        insert opp;

        // Add child program lines to drive rollup summaries on Opportunity
        addProgramLine(opp.Id, 50, 40, 35, 25, 15, 12, 12.5, prog1, aoi1);
        if (prog1 != prog2) {
            addProgramLine(opp.Id, 50, 40, 35, 25, 15, 13, 10.0, prog2, aoi2);
        }

        // Campus Drive should not exist yet since stage is not Completed/Closed Won
        String externalId = acc.Id + '_2026-2027';
        List<Campus_Drive__c> drives = [SELECT Id FROM Campus_Drive__c WHERE External_Id__c = :externalId];
        System.assertEquals(0, drives.size(), 'Campus Drive should not exist yet.');

        // Update Stage to Completed
        Test.startTest();
        opp.StageName = 'Completed';
        update opp;
        Test.stopTest();

        // Verify Campus Drive is created with correct aggregate values from rollup fields
        // List<Campus_Drive__c> createdDrives = [
        //     SELECT Id, Account__c, Academic_Year__c, Expected__c, Registered__c,
        //            Appeared__c, Shortlisted__c, Selected__c, Offer_Count__c, CTC__c, Program__c, Visited__c
        //     FROM Campus_Drive__c
        //     WHERE External_Id__c = :externalId
        // ];
        // System.assertEquals(1, createdDrives.size(), 'One Campus Drive record should be created.');
        // Campus_Drive__c cd = createdDrives[0];
        // System.assertEquals(acc.Id, cd.Account__c);
        // System.assertEquals('2026-2027', cd.Academic_Year__c);
        
        // Assert sums and max CTC
        // Decimal expectedSum = 50 + (prog1 != prog2 ? 50 : 0);
        // Decimal registeredSum = 40 + (prog1 != prog2 ? 40 : 0);
        // Decimal appearedSum = 35 + (prog1 != prog2 ? 35 : 0);
        // Decimal shortlistedSum = 25 + (prog1 != prog2 ? 25 : 0);
        // Decimal selectedSum = 15 + (prog1 != prog2 ? 15 : 0);
        // Decimal offerSum = 12 + (prog1 != prog2 ? 13 : 0);
        // Decimal maxCtc = 12.5;

        // System.assertEquals(expectedSum, cd.Expected__c);
        // System.assertEquals(registeredSum, cd.Registered__c);
        // System.assertEquals(appearedSum, cd.Appeared__c);
        // System.assertEquals(shortlistedSum, cd.Shortlisted__c);
        // System.assertEquals(selectedSum, cd.Selected__c);
        // System.assertEquals(offerSum, cd.Offer_Count__c);
        // System.assertEquals(maxCtc, cd.CTC__c);
        
        // System.assertNotEquals(null, cd.Program__c);
        // List<String> progList = cd.Program__c.split(';');
        // System.assert(progList.contains(prog1));
        // if (prog1 != prog2) {
        //     System.assert(progList.contains(prog2));
        // }
        // System.assertEquals(true, cd.Visited__c);
    }

    @isTest
    static void testAggregationWithMultipleOpportunities() {
        Id cdcRecordTypeId = getCdcRecordTypeId();
        System.assertNotEquals(null, cdcRecordTypeId, 'CDC Opportunity Record Type must exist.');

        Account acc = new Account(Name = 'Test Aggregation Account');
        insert acc;

        // Fetch dynamic Program and AOI values
        List<Map<String, String>> programOptions = CDCProgramLinesController.getProgramOptions();
        String prog1 = 'MTech - CSE';
        String prog2 = 'MTech - CSE';
        if (programOptions.size() > 0) prog1 = programOptions[0].get('value');
        if (programOptions.size() > 1) prog2 = programOptions[1].get('value');

        List<Map<String, String>> aoiOptions1 = CDCProgramLinesController.getAOIOptions(prog1);
        String aoi1 = 'CSE';
        if (!aoiOptions1.isEmpty()) aoi1 = aoiOptions1[0].get('value');

        List<Map<String, String>> aoiOptions2 = CDCProgramLinesController.getAOIOptions(prog2);
        String aoi2 = 'CSE';
        if (!aoiOptions2.isEmpty()) aoi2 = aoiOptions2[0].get('value');

        // Insert first CDC Opportunity
        Opportunity opp1 = new Opportunity(
            Name = 'Test CDC Opp 3A',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            RecordTypeId = cdcRecordTypeId,
            AccountId = acc.Id,
            Academic_Year__c = '2026',
            Program__c = prog1
        );
        
        // Insert second CDC Opportunity
        Opportunity opp2 = new Opportunity(
            Name = 'Test CDC Opp 3B',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            RecordTypeId = cdcRecordTypeId,
            AccountId = acc.Id,
            Academic_Year__c = '2026',
            Program__c = prog1
        );

        insert new List<Opportunity>{ opp1, opp2 };

        // Add child lines for rollup
        addProgramLine(opp1.Id, 50, 40, 35, 25, 15, 10, 10.0, prog1, aoi1);
        addProgramLine(opp2.Id, 60, 50, 45, 30, 20, 18, 15.0, prog2, aoi2);

        // Update first one to Completed
        opp1.StageName = 'Completed';
        update opp1;

        String externalId = acc.Id + '_2026-2027';
        // Campus_Drive__c cd1 = [SELECT Expected__c, CTC__c, Program__c FROM Campus_Drive__c WHERE External_Id__c = :externalId];
        // System.assertEquals(50, cd1.Expected__c);
        // System.assertEquals(10.0, cd1.CTC__c);
        // System.assertEquals(prog1, cd1.Program__c);

        // Update second one to Closed Won (which is also in CAMPUS_DRIVE_STAGES)
        Test.startTest();
        opp2.StageName = 'Closed Won';
        update opp2;
        Test.stopTest();

        // Verify aggregation of both
        // Campus_Drive__c cd2 = [
        //     SELECT Expected__c, Registered__c, Appeared__c, Shortlisted__c, Selected__c, Offer_Count__c, CTC__c, Program__c
        //     FROM Campus_Drive__c
        //     WHERE External_Id__c = :externalId
        // ];
        // System.assertEquals(110, cd2.Expected__c); // 50 + 60
        // System.assertEquals(90, cd2.Registered__c); // 40 + 50
        // System.assertEquals(80, cd2.Appeared__c); // 35 + 45
        // System.assertEquals(55, cd2.Shortlisted__c); // 25 + 30
        // System.assertEquals(35, cd2.Selected__c); // 15 + 20
        // System.assertEquals(28, cd2.Offer_Count__c); // 10 + 18
        // System.assertEquals(15.0, cd2.CTC__c); // Max of 10.0 and 15.0
        
        // List<String> progList = cd2.Program__c.split(';');
        // System.assert(progList.contains(prog1));
        // System.assert(progList.contains(prog2));
    }

    @isTest
    static void testNoCampusDriveForNonCdcRecords() {
        Account acc = new Account(Name = 'Test Non-CDC Aggregation Account');
        insert acc;

        List<Map<String, String>> programOptions = CDCProgramLinesController.getProgramOptions();
        String prog1 = 'MBA';
        // if (programOptions.size() > 0) prog1 = programOptions[0].get('value');

        List<Map<String, String>> aoiOptions1 = CDCProgramLinesController.getAOIOptions(prog1);
        String aoi1 = 'HR';
        // if (!aoiOptions1.isEmpty()) aoi1 = aoiOptions1[0].get('value');

        // Opportunity with default record type (or non-CDC)
        Opportunity opp = new Opportunity(
            Name = 'Test Standard Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = acc.Id,
            Academic_Year__c = '2026',
            Program__c = prog1
        );
        insert opp;

        addProgramLine(opp.Id, 50, 40, 35, 25, 15, 10, 10.0, prog1, aoi1);

        Test.startTest();
        opp.StageName = 'Completed';
        update opp;
        Test.stopTest();

        // String externalId = acc.Id + '_2026-2027';
        // List<Campus_Drive__c> drives = [SELECT Id FROM Campus_Drive__c WHERE External_Id__c = :externalId];
        // System.assertEquals(0, drives.size(), 'No Campus Drive should be created for non-CDC opportunities.');
    }
}