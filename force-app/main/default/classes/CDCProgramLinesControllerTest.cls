@isTest
public class CDCProgramLinesControllerTest {

    private static Drive_Program_Line__c createTestLine() {
        List<Map<String, String>> programOptions = CDCProgramLinesController.getProgramOptions();
        String prog = 'CSE';
        if (!programOptions.isEmpty()) {
            prog = programOptions[0].get('value');
        }
        List<Map<String, String>> aoiOptions = CDCProgramLinesController.getAOIOptions(prog);
        String aoi = 'Software Development';
        if (!aoiOptions.isEmpty()) {
            aoi = aoiOptions[0].get('value');
        }
        return new Drive_Program_Line__c(
            Program__c = prog,
            AOI__c = aoi
        );
    }

    @isTest
    static void testGetLinesAndSaveAndDelete() {
        // Create Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = System.today().addDays(30)
        );
        insert opp;

        // Retrieve active program options dynamically
        List<Map<String, String>> programOptions = CDCProgramLinesController.getProgramOptions();
        System.assert(!programOptions.isEmpty(), 'Program options should not be empty.');
        String prog1 = programOptions[0].get('value');

        // Retrieve valid AOI options for prog1 dynamically
        List<Map<String, String>> aoiOptions = CDCProgramLinesController.getAOIOptions(prog1);
        System.assert(!aoiOptions.isEmpty(), 'AOI options for ' + prog1 + ' should not be empty.');
        String aoi1 = aoiOptions[0].get('value');
        String aoi2 = aoiOptions.size() > 1 ? aoiOptions[1].get('value') : aoi1;

        // Test saveLines with valid data
        List<Drive_Program_Line__c> linesToSave = new List<Drive_Program_Line__c>();
        Drive_Program_Line__c line1 = new Drive_Program_Line__c(
            Program__c = prog1,
            AOI__c = aoi1,
            Expected_Students__c = 10,
            Registered_Students__c = 10,
            Appeared_Students__c = 8,
            Selected_Students__c = 5,
            Offer_Accepted__c = 3,
            Remarks__c = 'Test Remarks 1'
        );
        linesToSave.add(line1);

        if (aoi1 != aoi2) {
            Drive_Program_Line__c line2 = new Drive_Program_Line__c(
                Program__c = prog1,
                AOI__c = aoi2,
                Expected_Students__c = 20,
                Registered_Students__c = 15,
                Appeared_Students__c = 12,
                Selected_Students__c = 8,
                Offer_Accepted__c = 6,
                Remarks__c = 'Test Remarks 2'
            );
            linesToSave.add(line2);
        }

        Test.startTest();
        List<Drive_Program_Line__c> savedLines;
        try {
            savedLines = CDCProgramLinesController.saveLines(opp.Id, linesToSave);
        } catch (AuraHandledException e) {
            System.debug('DML saveLines failed. Message: ' + e.getMessage());
            throw e;
        }
        Test.stopTest();

        System.assertEquals(linesToSave.size(), savedLines.size(), 'Should have saved all lines.');
        for (Drive_Program_Line__c l : savedLines) {
            System.assertEquals(opp.Id, l.Opportunity__c, 'Opportunity ID must be set.');
        }

        // Verify getLines
        List<Drive_Program_Line__c> retrievedLines = CDCProgramLinesController.getLines(opp.Id);
        System.assertEquals(linesToSave.size(), retrievedLines.size(), 'Should retrieve all saved lines.');

        // Verify deleteLine
        CDCProgramLinesController.deleteLine(retrievedLines[0].Id);
        List<Drive_Program_Line__c> afterDelete = CDCProgramLinesController.getLines(opp.Id);
        System.assertEquals(linesToSave.size() - 1, afterDelete.size(), 'Should have one less line after deletion.');
    }

    @isTest
    static void testSaveDuplicateValidationError() {
        Opportunity opp = new Opportunity(
            Name = 'Test Opp Duplicate',
            StageName = 'Prospecting',
            CloseDate = System.today().addDays(30)
        );
        insert opp;

        Drive_Program_Line__c line1 = createTestLine();
        Drive_Program_Line__c line2 = createTestLine();

        List<Drive_Program_Line__c> lines = new List<Drive_Program_Line__c>{line1, line2};

        Boolean exceptionThrown = false;
        try {
            CDCProgramLinesController.saveLines(opp.Id, lines);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        System.assert(exceptionThrown, 'AuraHandledException should be thrown for duplicate entries.');
    }

    @isTest
    static void testSaveStudentCountValidationAppearedExceedsRegistered() {
        Opportunity opp = new Opportunity(
            Name = 'Test Opp Counts 1',
            StageName = 'Prospecting',
            CloseDate = System.today().addDays(30)
        );
        insert opp;

        Drive_Program_Line__c line = createTestLine();
        line.Registered_Students__c = 10;
        line.Appeared_Students__c = 12;

        List<Drive_Program_Line__c> lines = new List<Drive_Program_Line__c>{line};

        Boolean exceptionThrown = false;
        try {
            CDCProgramLinesController.saveLines(opp.Id, lines);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        System.assert(exceptionThrown, 'Exception should be thrown when Appeared exceeds Registered.');
    }

    @isTest
    static void testSaveStudentCountValidationSelectedExceedsAppeared() {
        Opportunity opp = new Opportunity(
            Name = 'Test Opp Counts 2',
            StageName = 'Prospecting',
            CloseDate = System.today().addDays(30)
        );
        insert opp;

        Drive_Program_Line__c line = createTestLine();
        line.Appeared_Students__c = 10;
        line.Selected_Students__c = 12;

        List<Drive_Program_Line__c> lines = new List<Drive_Program_Line__c>{line};

        Boolean exceptionThrown = false;
        try {
            CDCProgramLinesController.saveLines(opp.Id, lines);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        System.assert(exceptionThrown, 'Exception should be thrown when Selected exceeds Appeared.');
    }

    @isTest
    static void testSaveStudentCountValidationOfferAcceptedExceedsSelected() {
        Opportunity opp = new Opportunity(
            Name = 'Test Opp Counts 3',
            StageName = 'Prospecting',
            CloseDate = System.today().addDays(30)
        );
        insert opp;

        Drive_Program_Line__c line = createTestLine();
        line.Selected_Students__c = 10;
        line.Offer_Accepted__c = 12;

        List<Drive_Program_Line__c> lines = new List<Drive_Program_Line__c>{line};

        Boolean exceptionThrown = false;
        try {
            CDCProgramLinesController.saveLines(opp.Id, lines);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        System.assert(exceptionThrown, 'Exception should be thrown when Offer Accepted exceeds Selected.');
    }

    @isTest
    static void testDeleteLineException() {
        Boolean exceptionThrown = false;
        try {
            CDCProgramLinesController.deleteLine(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('Delete failed'), 'Message should indicate delete failed: ' + e.getMessage());
        }
    }

    @isTest
    static void testSaveExceptionGeneral() {
        Drive_Program_Line__c line = createTestLine();
        List<Drive_Program_Line__c> lines = new List<Drive_Program_Line__c>{line};
        Boolean exceptionThrown = false;
        try {
            CDCProgramLinesController.saveLines('006000000000000AAA', lines);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('Save failed'), 'Message should indicate save failed: ' + e.getMessage());
        }
        System.assert(exceptionThrown, 'AuraHandledException should be thrown when save fails due to invalid ID.');
    }

    @isTest
    static void testGetOptionsAndHelperMethods() {
        // Test options retrieval
        Map<String, List<Map<String, String>>> allAOIOptions = CDCProgramLinesController.getAllAOIOptions();
        System.assertNotEquals(null, allAOIOptions, 'AOI options map should not be null.');

        List<Map<String, String>> programOptions = CDCProgramLinesController.getProgramOptions();
        System.assertNotEquals(null, programOptions, 'Program options should not be null.');

        String existingProgram = 'CSE';
        if (!programOptions.isEmpty()) {
            existingProgram = programOptions[0].get('value');
        }
        List<Map<String, String>> aoiOpts = CDCProgramLinesController.getAOIOptions(existingProgram);
        System.assertNotEquals(null, aoiOpts, 'Should return list of options even if empty.');

        List<Map<String, String>> invalidAoiOpts = CDCProgramLinesController.getAOIOptions('NonExistentProgramXYZ');
        System.assertEquals(0, invalidAoiOpts.size(), 'Should return empty list for invalid program.');

        // Test fallback map directly
        Map<String, List<Map<String, String>>> fallbackMap = CDCProgramLinesController.buildAOIMapFallback();
        System.assertNotEquals(null, fallbackMap, 'Fallback map should not be null.');
        System.assert(fallbackMap.containsKey('CSE'), 'Fallback map should contain CSE key.');

        // Test hexToInt
        System.assertEquals(10, CDCProgramLinesController.hexToInt('a'));
        System.assertEquals(11, CDCProgramLinesController.hexToInt('b'));
        System.assertEquals(12, CDCProgramLinesController.hexToInt('c'));
        System.assertEquals(13, CDCProgramLinesController.hexToInt('d'));
        System.assertEquals(14, CDCProgramLinesController.hexToInt('e'));
        System.assertEquals(15, CDCProgramLinesController.hexToInt('f'));
        System.assertEquals(16, CDCProgramLinesController.hexToInt('10'));
        System.assertEquals(255, CDCProgramLinesController.hexToInt('FF'));

        // Test intPow
        System.assertEquals(1, CDCProgramLinesController.intPow(2, 0));
        System.assertEquals(2, CDCProgramLinesController.intPow(2, 1));
        System.assertEquals(8, CDCProgramLinesController.intPow(2, 3));

        // Test isBitSet
        System.assertEquals(true, CDCProgramLinesController.isBitSet('80', 0));
        System.assertEquals(false, CDCProgramLinesController.isBitSet('80', 1));
        System.assertEquals(true, CDCProgramLinesController.isBitSet('40', 1));
        System.assertEquals(false, CDCProgramLinesController.isBitSet('40', 0));
        System.assertEquals(false, CDCProgramLinesController.isBitSet('80', 20));
    }
}