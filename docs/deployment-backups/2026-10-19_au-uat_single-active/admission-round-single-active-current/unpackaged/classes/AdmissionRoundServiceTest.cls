/**
 * @description Tests validation, bulk upsert, partial success, and logging for admission rounds.
 * @author AU Development Team
 * @date 2026-10-16
 * @version 1.0
 * @lastModified 2026-10-16
 */
@IsTest
private class AdmissionRoundServiceTest {
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
    static void shouldInsertAndUpdateInOneBulkOperation() {
        AdmissionRoundApiModels.RequestEnvelope requestEnvelope = new AdmissionRoundApiModels.RequestEnvelope();
        requestEnvelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>{
            request('SERVICE-0', 'Updated Existing Round', '2027-28', 'B.Tech', '2027-01-01', '2027-02-01', false),
            request('SERVICE-NEW', 'New Round', '2027-28', 'MBA', '2027-03-01', '2027-04-01', null)
        };

        Test.startTest();
        AdmissionRoundApiModels.ResponseEnvelope response =
            AdmissionRoundService.process(requestEnvelope, 'REQ-SERVICE-SUCCESS');
        Test.stopTest();

        System.assertEquals(true, response.success, 'The mixed insert/update request should succeed.');
        System.assertEquals(2, response.successCount, 'Both records should succeed.');
        System.assertEquals('UPDATED', response.results[0].action, 'The existing record should be updated.');
        System.assertEquals('INSERTED', response.results[1].action, 'The new record should be inserted.');

        Map<String, Admission_Round__c> savedByCode = new Map<String, Admission_Round__c>();
        for (Admission_Round__c saved : [
            SELECT Name, Round_Code__c, Is_Active__c
            FROM Admission_Round__c
            WHERE Round_Code__c IN ('SERVICE-0', 'SERVICE-NEW')
        ]) {
            savedByCode.put(saved.Round_Code__c, saved);
        }
        System.assertEquals(
            'Updated Existing Round',
            savedByCode.get('SERVICE-0').Name,
            'The existing record should contain the updated name.'
        );
        System.assertEquals(false, savedByCode.get('SERVICE-0').Is_Active__c, 'Active should be updated to false.');
        System.assertEquals(true, savedByCode.get('SERVICE-NEW').Is_Active__c, 'New records should default active.');
    }

    @IsTest
    static void shouldReturnExactValidationErrorsAndLogFailures() {
        AdmissionRoundApiModels.RequestEnvelope requestEnvelope = new AdmissionRoundApiModels.RequestEnvelope();
        requestEnvelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>{
            request('DUPLICATE', 'First', null, null, null, null, true),
            request('DUPLICATE', 'Second', null, null, null, null, true),
            request('INVALID-DATE', 'Invalid Date', null, null, '2027-04-02', '2027-04-01', true),
            requestWithDepartment('INVALID-DEPARTMENT', 'Invalid Department', 'Unknown Department'),
            request('VALID-PARTIAL', 'Valid Partial', null, null, null, null, true)
        };

        Test.startTest();
        AdmissionRoundApiModels.ResponseEnvelope response =
            AdmissionRoundService.process(requestEnvelope, 'REQ-SERVICE-PARTIAL');
        Test.stopTest();

        System.assertEquals(false, response.success, 'A partial-success request should not be marked fully successful.');
        System.assertEquals(1, response.successCount, 'Only the valid record should succeed.');
        System.assertEquals(4, response.failureCount, 'Four invalid records should fail.');
        System.assert(
            response.results[0].errors[0].contains('more than once'),
            'Duplicate round codes should return an exact validation message.'
        );
        System.assert(
            response.results[2].errors[0].contains('on or before'),
            'Invalid date order should return an exact validation message.'
        );
        System.assert(
            response.results[3].errors[0].contains('department must be one of'),
            'An unsupported department should return the allowed-values error.'
        );
        System.assertEquals(
            4,
            [SELECT COUNT() FROM API_Log__c WHERE Log_Name__c = 'AdmissionRoundUpsert'],
            'Every failed record should create an API log entry.'
        );
    }

    @IsTest
    static void shouldProcessTwoHundredRecords() {
        AdmissionRoundApiModels.RequestEnvelope requestEnvelope = new AdmissionRoundApiModels.RequestEnvelope();
        requestEnvelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>();
        for (Integer index = 0; index < 200; index++) {
            requestEnvelope.records.add(
                request('BULK-' + index, 'Bulk Round ' + index, '2028-29', 'Program ' + index, null, null, true)
            );
        }

        Test.startTest();
        AdmissionRoundApiModels.ResponseEnvelope response =
            AdmissionRoundService.process(requestEnvelope, 'REQ-SERVICE-BULK');
        Test.stopTest();

        System.assertEquals(200, response.successCount, 'All 200 bulk records should be processed.');
        System.assertEquals(
            200,
            [SELECT COUNT() FROM Admission_Round__c WHERE Round_Code__c LIKE 'BULK-%'],
            'The API should insert all 200 admission rounds.'
        );
    }

    @IsTest
    static void shouldRejectMoreThanTwoHundredRecords() {
        AdmissionRoundApiModels.RequestEnvelope requestEnvelope = new AdmissionRoundApiModels.RequestEnvelope();
        requestEnvelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>();
        for (Integer index = 0; index < 201; index++) {
            requestEnvelope.records.add(request('LIMIT-' + index, 'Limit ' + index, null, null, null, null, true));
        }

        try {
            AdmissionRoundService.process(requestEnvelope, 'REQ-SERVICE-LIMIT');
            System.assert(false, 'A request containing 201 records must throw an API exception.');
        } catch (AdmissionRoundService.AdmissionRoundApiException exceptionValue) {
            System.assertEquals(
                'A maximum of 200 admission rounds is allowed per request.',
                exceptionValue.getMessage(),
                'The limit error should be explicit.'
            );
        }
    }

    private static AdmissionRoundApiModels.AdmissionRoundRequest request(
        String roundCode,
        String roundName,
        String admissionYear,
        String program,
        String startDate,
        String endDate,
        Boolean isActive
    ) {
        AdmissionRoundApiModels.AdmissionRoundRequest input = new AdmissionRoundApiModels.AdmissionRoundRequest();
        input.roundCode = roundCode;
        input.roundName = roundName;
        input.admissionYear = admissionYear;
        input.department = 'CLeF';
        input.program = program;
        input.startDate = startDate;
        input.endDate = endDate;
        input.isActive = isActive;
        return input;
    }

    private static AdmissionRoundApiModels.AdmissionRoundRequest requestWithDepartment(
        String roundCode,
        String roundName,
        String department
    ) {
        AdmissionRoundApiModels.AdmissionRoundRequest input =
            request(roundCode, roundName, null, null, null, null, true);
        input.department = department;
        return input;
    }
}