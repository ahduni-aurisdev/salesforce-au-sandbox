/**
 * @description Tests date-based validation, bulk upsert, partial success, and logging for admission rounds.
 * @author AU Development Team
 * @date 2026-10-16
 * @version 1.2
 * @lastModified 2026-10-22
 */
@IsTest
private class AdmissionRoundServiceTest {
    private static final String FUTURE_START = '2027-01-01';
    private static final String FUTURE_END = '2027-03-31';

    @TestSetup
    static void createData() {
        List<Admission_Round__c> rounds = new List<Admission_Round__c>();
        for (Integer index = 0; index < 200; index++) {
            rounds.add(new Admission_Round__c(
                Name = 'Service Setup ' + index,
                Round_Code__c = 'SERVICE-' + index,
                Is_Active__c = true
            ));
        }
        insert rounds;
    }

    @IsTest
    static void shouldInsertAndUpdateWhileIgnoringIsActive() {
        AdmissionRoundApiModels.RequestEnvelope envelope = new AdmissionRoundApiModels.RequestEnvelope();
        envelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>{
            request('SERVICE-0', 'Updated Existing Round', 'Admission Year - 2027', 'Masters', FUTURE_START, FUTURE_END, false),
            request('SERVICE-NEW', 'New Round', 'Admission Year - 2027', 'Undergraduation', FUTURE_START, FUTURE_END, false)
        };

        Test.startTest();
        AdmissionRoundApiModels.ResponseEnvelope response = AdmissionRoundService.process(envelope, 'REQ-SUCCESS');
        Test.stopTest();

        System.assertEquals(true, response.success, 'Both valid records should be upserted.');
        System.assertEquals(2, response.successCount, 'Both records should succeed.');
        System.assertEquals('UPDATED', response.results[0].action, 'The existing record should update.');
        System.assertEquals('INSERTED', response.results[1].action, 'The new record should insert.');

        Map<String, Admission_Round__c> saved = queryRounds(new Set<String>{'SERVICE-0', 'SERVICE-NEW'});
        System.assertEquals(true, saved.get('SERVICE-0').Is_Active__c, 'Incoming isActive must not modify the existing field.');
        System.assertEquals(true, saved.get('SERVICE-NEW').Is_Active__c, 'The unused field may retain its object default.');
        System.assertEquals(Date.newInstance(2027, 1, 1), saved.get('SERVICE-NEW').Start_Date__c, 'Start Date must be stored.');
    }

    @IsTest
    static void shouldReturnExactValidationErrorsAndKeepPartialSuccess() {
        AdmissionRoundApiModels.RequestEnvelope envelope = new AdmissionRoundApiModels.RequestEnvelope();
        envelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>{
            request('DUPLICATE', 'First', 'Admission Year - 2027', 'Masters', FUTURE_START, FUTURE_END, null),
            request('DUPLICATE', 'Second', 'Admission Year - 2027', 'Masters', FUTURE_START, FUTURE_END, null),
            request('INVALID-DATE', 'Invalid Date', 'Admission Year - 2027', 'Masters', '2027-04-02', '2027-04-01', null),
            request('INVALID-DEPARTMENT', 'Invalid Department', 'Admission Year - 2027', 'Unknown Department', FUTURE_START, FUTURE_END, null),
            request('VALID-PARTIAL', 'Valid Partial', 'Admission Year - 2027', 'CLeF', FUTURE_START, FUTURE_END, true)
        };

        Test.startTest();
        AdmissionRoundApiModels.ResponseEnvelope response = AdmissionRoundService.process(envelope, 'REQ-PARTIAL');
        Test.stopTest();

        System.assertEquals(false, response.success, 'Partial success must not report complete success.');
        System.assertEquals(1, response.successCount, 'The valid record should still be committed.');
        System.assertEquals(4, response.failureCount, 'Four invalid records should fail independently.');
        System.assert(response.results[0].errors[0].contains('more than once'), 'Duplicate codes need an exact error.');
        System.assert(response.results[2].errors[0].contains('on or before'), 'Invalid date order needs an exact error.');
        System.assert(response.results[3].errors[0].contains('department must be one of'), 'Invalid Department needs an exact error.');
        System.assertEquals(4, [SELECT COUNT() FROM API_Log__c WHERE Log_Name__c = 'AdmissionRoundUpsert'], 'Every failure should be logged.');
    }

    @IsTest
    static void shouldRequireGroupingAndDatesForNewRounds() {
        AdmissionRoundApiModels.RequestEnvelope envelope = new AdmissionRoundApiModels.RequestEnvelope();
        envelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>{
            request('MISSING-DEPT', 'Missing Department', 'Admission Year - 2027', null, FUTURE_START, FUTURE_END, null),
            request('MISSING-YEAR', 'Missing Year', null, 'Masters', FUTURE_START, FUTURE_END, null),
            request('MISSING-START', 'Missing Start', 'Admission Year - 2027', 'Masters', null, FUTURE_END, null),
            request('MISSING-END', 'Missing End', 'Admission Year - 2027', 'Masters', FUTURE_START, null, null)
        };

        AdmissionRoundApiModels.ResponseEnvelope response = AdmissionRoundService.process(envelope, 'REQ-REQUIRED');

        System.assertEquals(0, response.successCount, 'No incomplete new round should be saved.');
        System.assertEquals('department is required.', response.results[0].errors[0], 'Department error must be exact.');
        System.assertEquals('admissionYear is required.', response.results[1].errors[0], 'Admission Year error must be exact.');
        System.assertEquals('startDate is required.', response.results[2].errors[0], 'Start Date error must be exact.');
        System.assertEquals('endDate is required.', response.results[3].errors[0], 'End Date error must be exact.');
    }

    @IsTest
    static void shouldPreserveExistingValuesWhenUpdateOmitsOptionalFields() {
        Admission_Round__c existing = new Admission_Round__c(
            Name = 'Existing Complete', Round_Code__c = 'EXISTING-COMPLETE',
            Admission_Year__c = 'Admission Year - 2026', Department__c = 'Phd',
            Start_Date__c = Date.newInstance(2026, 1, 1), End_Date__c = Date.newInstance(2026, 3, 31)
        );
        insert existing;
        AdmissionRoundApiModels.AdmissionRoundRequest input = new AdmissionRoundApiModels.AdmissionRoundRequest();
        input.roundCode = 'EXISTING-COMPLETE';
        input.roundName = 'Renamed';
        input.isActive = false;
        AdmissionRoundApiModels.RequestEnvelope envelope = new AdmissionRoundApiModels.RequestEnvelope();
        envelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>{input};

        AdmissionRoundApiModels.ResponseEnvelope response = AdmissionRoundService.process(envelope, 'REQ-PRESERVE');

        System.assertEquals(true, response.success, 'A partial update may preserve existing required values.');
        Admission_Round__c saved = queryRounds(new Set<String>{'EXISTING-COMPLETE'}).get('EXISTING-COMPLETE');
        System.assertEquals('Phd', saved.Department__c, 'Existing Department must be preserved.');
        System.assertEquals(Date.newInstance(2026, 1, 1), saved.Start_Date__c, 'Existing Start Date must be preserved.');
    }

    @IsTest
    static void shouldUpsertTwoHundredHistoricalRoundsWithoutDeactivation() {
        AdmissionRoundApiModels.RequestEnvelope envelope = new AdmissionRoundApiModels.RequestEnvelope();
        envelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>();
        for (Integer index = 0; index < 200; index++) {
            envelope.records.add(request(
                'BULK-' + index, 'Bulk Round ' + index, 'Admission Year - ' + (2020 + Math.mod(index, 8)),
                'Masters', '2020-01-01', '2030-12-31', false
            ));
        }

        Test.startTest();
        AdmissionRoundApiModels.ResponseEnvelope response = AdmissionRoundService.process(envelope, 'REQ-BULK');
        Test.stopTest();

        System.assertEquals(200, response.successCount, 'All 200 history records should upsert.');
        System.assertEquals(200, [SELECT COUNT() FROM Admission_Round__c WHERE Round_Code__c LIKE 'BULK-%'], 'No history record should be removed.');
        System.assertEquals(200, [SELECT COUNT() FROM Admission_Round__c WHERE Round_Code__c LIKE 'BULK-%' AND Is_Active__c = true], 'No active/inactive enforcement should run.');
    }

    @IsTest
    static void shouldRejectMoreThanTwoHundredRecords() {
        AdmissionRoundApiModels.RequestEnvelope envelope = new AdmissionRoundApiModels.RequestEnvelope();
        envelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>();
        for (Integer index = 0; index < 201; index++) {
            envelope.records.add(request('LIMIT-' + index, 'Limit ' + index, 'Admission Year - 2027', 'Masters', FUTURE_START, FUTURE_END, null));
        }
        try {
            AdmissionRoundService.process(envelope, 'REQ-LIMIT');
            System.assert(false, 'A request containing 201 records must throw.');
        } catch (AdmissionRoundService.AdmissionRoundApiException exceptionValue) {
            System.assertEquals('A maximum of 200 admission rounds is allowed per request.', exceptionValue.getMessage(), 'Limit error must be explicit.');
        }
    }

    private static AdmissionRoundApiModels.AdmissionRoundRequest request(
        String code, String name, String year, String department, String startDate, String endDate, Boolean isActive
    ) {
        AdmissionRoundApiModels.AdmissionRoundRequest input = new AdmissionRoundApiModels.AdmissionRoundRequest();
        input.roundCode = code;
        input.roundName = name;
        input.admissionYear = year;
        input.department = department;
        input.program = 'Program';
        input.startDate = startDate;
        input.endDate = endDate;
        input.isActive = isActive;
        return input;
    }

    private static Map<String, Admission_Round__c> queryRounds(Set<String> codes) {
        Map<String, Admission_Round__c> result = new Map<String, Admission_Round__c>();
        for (Admission_Round__c roundValue : [
            SELECT Name, Round_Code__c, Department__c, Admission_Year__c, Start_Date__c, End_Date__c, Is_Active__c
            FROM Admission_Round__c WHERE Round_Code__c IN :codes
        ]) result.put(roundValue.Round_Code__c, roundValue);
        return result;
    }
}
